#!/bin/sh
# 驗證閘門的單一入口點：一次完整執行，在最後一次修改程式碼之後跑。
#
#   tools/gate.sh --scope <scope> --base <ref>
#
# scope 是產出目錄 .gate/<scope>/ 的名稱。base 是比較基準的 commit。
# 兩者都必須明確給出，沒有預設值 —— 猜出來的基準讓每一層的數字失去意義。
#
# 契約：
#   * fail closed —— set -e，沒有 `|| true`，沒有 `2>/dev/null`，第一層壞掉就停。
#     後面的層因此不會執行，那是正確行為，report 把它們記成 NOT REACHED。
#     每一層都經過 run_layer：**不要**用 `cmd | tee`，管線的退出碼是 tee 的，
#     失敗的層會被靜靜吞掉（這支腳本第一版就是這樣寫的，是個 fail-open 的洞）。
#   * fresh by mechanism —— 先清掉上一輪的產出，但要在設定驗過之後才清
#     （require_sane_config）。
#   * 執行完整性由 tools/gate-manifest-audit.sh 稽核 —— 光印出標題不算跑過。
#   * 來源狀態在最後一次執行的前後各驗一次。兩次不同代表這輪的數字描述的是一棵
#     已經不存在的樹。
set -eu

REPO=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$REPO"

BASE=""
SCOPE=""
while [ $# -gt 0 ]; do
    case "$1" in
        --base) BASE=$2; shift 2 ;;
        --base=*) BASE=${1#*=}; shift ;;
        --scope) SCOPE=$2; shift 2 ;;
        --scope=*) SCOPE=${1#*=}; shift ;;
        *) echo "gate: unknown argument: $1" >&2; exit 2 ;;
    esac
done
[ -n "$SCOPE" ] || { echo "gate: 必須給 --scope" >&2; exit 2; }
[ -n "$BASE" ] || { echo "gate: 必須給 --base（scope $SCOPE）" >&2; exit 2; }

# 執行前就判定得出的設定錯誤，要在下面 rm -rf 之前擋下來：一個打錯的 --base 或
# 少裝一個工具，代價不該是上一輪的證據被銷毀而這一輪什麼都沒量到。層跑到一半
# 失敗仍然會留下半套產出，那個 rc 不帶這個保證。
require_sane_config() {
    # scope 會直接接進下面 rm -rf 的路徑，`../x` 會把刪除帶出 .gate/。
    case "$SCOPE" in
        ""|.|..|*/*|*\\*)
            echo "gate: --scope 必須是單一路徑片段（得到：$SCOPE）" >&2; return 2 ;;
    esac
    # 只驗非空等於沒驗：解不到的 ref 要到 properties 層才會爆，那時產出已經沒了。
    if ! git cat-file -e "$BASE^{commit}"; then
        echo "gate: base ref 解不到 commit：$BASE" >&2; return 2
    fi
    # 每一個工具都有層在用。缺了不擋的話，versions 那一層會因為 run_layer 的
    # `if "$@"` 關掉 set -e 而印出一行空版本並記成完成。
    for _t in chezmoi git zsh python3 diff; do
        if ! command -v "$_t" > /dev/null; then
            echo "gate: 缺少必要工具：$_t" >&2; return 2
        fi
    done
}
require_sane_config || exit $?

# 受測 commit 解析一次，往下傳給每一個量測當前版本的層。用 ref `HEAD` 的話，
# 各層各自解析，報告裡的數字就可能描述不同的樹。baseline 與 RED 重建在 base，
# 不受這個值影響。
HEAD_SHA=$(git rev-parse HEAD)

ART=".gate/$SCOPE"
rm -rf "$ART"
mkdir -p "$ART"
RAN="$ART/layers-ran"
MANIFEST_FILE="$ART/layers-manifest"
: > "$RAN"

# 這份 manifest 就是「跑完了」的定義。加一層就要同時加在這裡。
cat > "$MANIFEST_FILE" <<'EOF'
versions
source-state-before
harness-selftest
suite
suite-health-repeat
suite-health-shuffle
properties
mutation
supply-chain
pacman-ids
changed-lines
source-state-after
EOF

run_layer() { # name outfile cmd...
    _name=$1; _out=$2; shift 2
    printf '\n===== layer: %s =====\n' "$_name"
    if "$@" > "$_out" 2>&1; then
        cat "$_out"
        printf '%s\n' "$_name" >> "$RAN"
    else
        _rc=$?
        cat "$_out"
        printf '\ngate: layer %s 失敗 (exit %s)。後面的層沒有執行。\n' "$_name" "$_rc" >&2
        exit 1
    fi
}

# ---------------------------------------------------------------- versions
# 這個 repo 沒有 lockfile 可以釘工具版本，所以照實記錄跑的是哪些版本。
# 這比釘住弱：它說明了什麼跑過，不保證下一次跑起來一樣。
# 上面的 command -v 只證明工具在 PATH 上。`printf '%s' "$(tool --version)"` 會吞掉
# tool 的退出碼，而 run_layer 的 `if "$@"` 讓 set -e 對整個函式體失效：一個裝了卻
# 跑不起來的工具，在這裡會印出一行空版本，這一層照樣被記成完成。每個版本各自檢查。
versions() {
    # 變數名稱帶 _ver 前綴：POSIX sh 沒有區域變數，這個函式是由 run_layer 叫起來的，
    # 用 _out 會蓋掉 run_layer 手上的輸出檔路徑，後面的 cat 就去讀版本字串了。
    _ver() { # label cmd...
        _ver_label=$1; shift
        if ! _ver_out=$("$@"); then
            printf 'gate: 取不到版本（%s）：%s\n' "$_ver_label" "$*" >&2
            return 1
        fi
        printf '%-9s%s\n' "$_ver_label" "$_ver_out"
    }
    _ver 'chezmoi:' chezmoi --version || return 1
    _ver 'git:' git --version || return 1
    _ver 'zsh:' zsh --version || return 1
    _ver 'python3:' python3 --version || return 1
    _ver 'sh:' ls -l /bin/sh || return 1
    if command -v pwsh.exe > /dev/null; then
        if ! _ver_out=$(pwsh.exe -NoProfile -NonInteractive -Command '$PSVersionTable.PSVersion.ToString()'); then
            echo "gate: pwsh.exe 在 PATH 上卻問不出版本" >&2
            return 1
        fi
        printf '%-9s%s\n' 'pwsh:' "$(printf '%s' "$_ver_out" | tr -d '\r')"
    else
        printf '%-9s%s\n' 'pwsh:' 'ABSENT (L4/L7/L8 會標成 skip)'
    fi
    printf '%-9s%s\n' 'base:' "$BASE"
    printf '%-9s%s\n' 'head:' "$HEAD_SHA"
    printf '%-9s%s\n' 'scope:' "$SCOPE"
}
run_layer versions "$ART/versions.txt" versions

# ------------------------------------------------------- source state (before)
run_layer source-state-before "$ART/source-state-before.txt" \
    sh tools/gate-source-state.sh

# ------------------------------------------------------------ harness selftest
# 這一層驗的是下面每一層的計數方式：稽核器漏讀末行、產出在設定錯誤時就被刪掉、
# 整層 SKIP 被算成綠燈、fixture 讀到主機的 ID_LIKE。四個都曾經只在綠燈裡出現。
# 排在 suite 之前：suite 的數字要能讀，得先知道 runner 怎麼算。
run_layer harness-selftest "$ART/harness-selftest.txt" \
    python3 tests/harness_test.py

# ---------------------------------------------------------------- test suite
run_layer suite "$ART/suite.tap" sh tests/run.sh

# ---------------------------------------------------------------- suite health
# 每一個 evidence 數字都建立在「這個 suite 是決定性的」之上，所以這一層排在
# mutation 與行數會計「之前」：那兩層的結論都是從這個 suite 的行為推出來的。
suite_repeat() {
    sh tests/run.sh > "$ART/suite-repeat.tap" 2>&1 || {
        cat "$ART/suite-repeat.tap"; return 1
    }
    if ! diff "$ART/suite.tap" "$ART/suite-repeat.tap" > "$ART/suite-repeat.diff"; then
        echo "同樣的 suite 跑兩次結果不同 —— 這個 suite 不是決定性的"
        cat "$ART/suite-repeat.diff"
        return 1
    fi
    echo "重跑結果與第一次逐行相同"
    tail -2 "$ART/suite-repeat.tap"
}
run_layer suite-health-repeat "$ART/suite-health-repeat.txt" suite_repeat

suite_shuffle() {
    TESTS_SHUFFLE=1 sh tests/run.sh > "$ART/suite-shuffle.tap" 2>&1 || {
        cat "$ART/suite-shuffle.tap"; return 1
    }
    # 順序換了，TAP 的編號一定不同；能比的是總數與失敗數。
    grep '^# run' "$ART/suite.tap" > "$ART/suite-count.txt"
    grep '^# run' "$ART/suite-shuffle.tap" > "$ART/suite-shuffle-count.txt"
    if ! diff "$ART/suite-count.txt" "$ART/suite-shuffle-count.txt" > "$ART/suite-shuffle.diff"; then
        echo "打亂 case 順序後結果改變 —— 有跨 case 的隱藏相依"
        cat "$ART/suite-shuffle.diff"
        return 1
    fi
    echo "隨機順序下的總數與失敗數不變"
    tail -2 "$ART/suite-shuffle.tap"
}
run_layer suite-health-shuffle "$ART/suite-health-shuffle.txt" suite_shuffle

# ---------------------------------------------------------------- properties
# --base 開啟 P0 差分：每個生成輸入的輸出都要與 base ref 的 awk 原版逐位元組相同。
# 多個 seed 是必要的：寫死單一 seed 曾經讓這一層綠得很幸運（生成器在 seed
# 2/3/4 會找到一個崩潰的形狀，在 1/5/6/20260902 不會）。
run_layer properties "$ART/properties.txt" \
    python3 tools/gate-properties.py --cases 30 --base "$BASE"

# ---------------------------------------------------------------- mutation
run_layer mutation "$ART/mutants.txt" \
    python3 tools/gate-mutants.py --json "$ART/mutants.json" --head-sha "$HEAD_SHA"

# ---------------------------------------------------------------- supply chain
run_layer supply-chain "$ART/supply-chain.txt" \
    python3 tools/gate-supply-chain.py --base "$BASE"

# ---------------------------------------------------------------- pacman ids
# S17 / M5：pacman 套件名逐一 `pacman -Si`（唯讀），在 omarchy WSL 內或 Arch 主機上。
# 兩者都不可達時印 SKIPPED 並 exit 0，報告記成 UNAVAILABLE（與 winget 那條同形）。
run_layer pacman-ids "$ART/pacman-ids.txt" sh tools/gate-pacman-ids.sh

# ---------------------------------------------------------------- changed lines
# 這一層只報告不設閘：這個 repo 的三種語言在這個環境裡都沒有覆蓋率工具，
# 詳見腳本內的說明與 evidence report 的 UNAVAILABLE 記錄。
run_layer changed-lines "$ART/changed-lines.txt" \
    python3 tools/gate-changed-lines.py --base "$BASE" --head "$HEAD_SHA"

# -------------------------------------------------------- source state (after)
# 只在開頭驗一次等於是替一棵在報告寫出來時已經不存在的樹背書。
run_layer source-state-after "$ART/source-state-after.txt" \
    sh tools/gate-source-state.sh

if ! diff "$ART/source-state-before.txt" "$ART/source-state-after.txt" > "$ART/source-state.diff"; then
    echo "gate: 來源狀態在這一輪之中改變了 —— 這輪的每一個數字都作廢" >&2
    cat "$ART/source-state.diff" >&2
    exit 1
fi

# ---------------------------------------------------------------- manifest 稽核
printf '\n===== manifest audit =====\n'
sh tools/gate-manifest-audit.sh "$MANIFEST_FILE" "$RAN"

# 套件裡「整層只有 SKIP」的層要跟著走到這一輪的結尾。前面印過診斷、最後一行卻
# 無條件寫「全部通過」，讀者拿到的還是一個不帶條件的綠燈。
if ! grep -q '^# skip-only 層' "$ART/suite.tap"; then
    echo "gate: suite 輸出沒有 skip-only 那一行 —— 跑的不是這個 runner" >&2
    exit 1
fi
_skip_only=$(sed -n 's/^# skip-only 層（沒有量測任何東西）://p' "$ART/suite.tap")

printf '\ngate: 每一層都執行到 exit 0。產出在 %s/\n' "$ART"
printf 'gate: 沒有量測任何東西的層（evidence 記成 UNAVAILABLE，不算進通過）:%s\n' "$_skip_only"
