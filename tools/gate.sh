#!/bin/sh
# 驗證閘門的單一入口點。evidence report 裡的每一個數字都必須來自這支腳本的
# 「一次」完整執行，而且是在最後一次修改程式碼之後跑的。
#
#   tools/gate.sh [--base <ref>]
#
# 預設 base 是 specs/windows-support/SPEC.md 裡記的那一個。
#
# 契約：
#   * fail closed —— set -e，沒有 `|| true`，沒有 `2>/dev/null`，第一層壞掉就停。
#     後面的層因此不會執行，那是正確行為，report 把它們記成 NOT REACHED。
#     每一層都經過 run_layer：**不要**用 `cmd | tee`，管線的退出碼是 tee 的，
#     失敗的層會被靜靜吞掉（這支腳本第一版就是這樣寫的，是個 fail-open 的洞）。
#   * fresh by mechanism —— 開頭先清掉上一輪的產出。
#   * 執行完整性由 tools/gate-manifest-audit.sh 稽核 —— 光印出標題不算跑過。
#   * 來源狀態在最後一次執行的前後各驗一次。兩次不同代表這輪的數字描述的是一棵
#     已經不存在的樹。
set -eu

REPO=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$REPO"

BASE=""
while [ $# -gt 0 ]; do
    case "$1" in
        --base) BASE=$2; shift 2 ;;
        --base=*) BASE=${1#*=}; shift ;;
        *) echo "gate: unknown argument: $1" >&2; exit 2 ;;
    esac
done
if [ -z "$BASE" ]; then
    BASE=$(sed -n 's/^- `base_ref`: `\([0-9a-f]*\)`.*/\1/p' specs/windows-support/SPEC.md | head -1)
fi
[ -n "$BASE" ] || { echo "gate: 給不出 base ref" >&2; exit 2; }

ART=".gate/windows-support"
rm -rf "$ART"
mkdir -p "$ART"
RAN="$ART/layers-ran"
MANIFEST_FILE="$ART/layers-manifest"
: > "$RAN"

# 這份 manifest 就是「跑完了」的定義。加一層就要同時加在這裡。
cat > "$MANIFEST_FILE" <<'EOF'
versions
source-state-before
suite
suite-health-repeat
suite-health-shuffle
properties
mutation
supply-chain
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
versions() {
    printf 'chezmoi: %s\n' "$(chezmoi --version)"
    printf 'git:     %s\n' "$(git --version)"
    printf 'zsh:     %s\n' "$(zsh --version)"
    printf 'python3: %s\n' "$(python3 --version)"
    printf 'sh:      %s\n' "$(ls -l /bin/sh)"
    if command -v pwsh.exe >/dev/null 2>&1; then
        printf 'pwsh:    %s\n' "$(pwsh.exe -NoProfile -NonInteractive -Command '$PSVersionTable.PSVersion.ToString()' | tr -d '\r')"
    else
        printf 'pwsh:    ABSENT (L4/L7/L8 會標成 skip)\n'
    fi
    printf 'base:    %s\n' "$BASE"
}
run_layer versions "$ART/versions.txt" versions

# ------------------------------------------------------- source state (before)
run_layer source-state-before "$ART/source-state-before.txt" \
    sh tools/gate-source-state.sh

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
    python3 tools/gate-mutants.py --json "$ART/mutants.json"

# ---------------------------------------------------------------- supply chain
run_layer supply-chain "$ART/supply-chain.txt" \
    python3 tools/gate-supply-chain.py --base "$BASE"

# ---------------------------------------------------------------- changed lines
# 這一層只報告不設閘：這個 repo 的三種語言在這個環境裡都沒有覆蓋率工具，
# 詳見腳本內的說明與 evidence report 的 UNAVAILABLE 記錄。
run_layer changed-lines "$ART/changed-lines.txt" \
    python3 tools/gate-changed-lines.py --base "$BASE"

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

printf '\ngate: 全部通過。產出在 %s/\n' "$ART"
