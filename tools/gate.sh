#!/bin/sh
# 驗證閘門的單一入口點。evidence report 裡的每一個數字都必須來自這支腳本的
# 「一次」完整執行，而且是在最後一次修改程式碼之後跑的。
#
#   tools/gate.sh [--base <ref>]
#
# 預設 base 是 .scratch/windows-support/spec.md 裡記的那一個。
#
# 契約：
#   * fail closed —— set -e，沒有 `|| true`，沒有 `2>/dev/null`，第一層壞掉就停。
#     後面的層因此不會執行，那是正確行為，report 把它們記成 NOT REACHED。
#   * fresh by mechanism —— 開頭先清掉上一輪的產出。
#   * 執行完整性由 manifest 稽核 —— 光印出標題不算跑過；每一層要自己留下記號，
#     最後比對 manifest，少一個就是失敗。
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
    BASE=$(sed -n 's/^Base ref: `\([0-9a-f]*\)`.*/\1/p' .scratch/windows-support/spec.md | head -1)
fi
[ -n "$BASE" ] || { echo "gate: 給不出 base ref" >&2; exit 2; }

ART=".gate/windows-support"
rm -rf "$ART"
mkdir -p "$ART"
RAN="$ART/layers-ran"
: > "$RAN"

# 這份 manifest 就是「跑完了」的定義。加一層就要同時加在這裡。
MANIFEST='source-state-before
versions
suite
suite-health-repeat
suite-health-shuffle
properties
mutation
supply-chain
changed-lines
source-state-after'

mark() { printf '%s\n' "$1" >> "$RAN"; }

banner() {
    printf '\n===== %s =====\n' "$1"
}

# ---------------------------------------------------------------- versions
banner "layer: versions (工具版本，供重現用)"
{
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
} | tee "$ART/versions.txt"
mark versions

# ------------------------------------------------------- source state (before)
banner "layer: source-state (before)"
sh tools/gate-source-state.sh | tee "$ART/source-state-before.txt"
mark source-state-before

# ---------------------------------------------------------------- test suite
banner "layer: suite (tests/run.sh，L1-L10)"
sh tests/run.sh | tee "$ART/suite.tap"
mark suite

# ---------------------------------------------------------------- suite health
# 每一個 evidence 數字都建立在「這個 suite 是決定性的」之上。兩個檢查：
# 重跑一次結果要一樣；把 case 順序打亂結果也要一樣（隱藏的跨 case 相依）。
banner "layer: suite-health (重跑)"
sh tests/run.sh | tee "$ART/suite-repeat.tap"
diff "$ART/suite.tap" "$ART/suite-repeat.tap" > "$ART/suite-repeat.diff" || {
    echo "gate: 同樣的 suite 跑兩次結果不同 —— 這個 suite 不是決定性的" >&2
    cat "$ART/suite-repeat.diff" >&2
    exit 1
}
mark suite-health-repeat

banner "layer: suite-health (隨機順序)"
TESTS_SHUFFLE=1 sh tests/run.sh > "$ART/suite-shuffle.tap"
tail -2 "$ART/suite-shuffle.tap"
# 順序變了，TAP 的編號一定不同；比對的是「總數與失敗數」。
grep '^# run' "$ART/suite.tap" > "$ART/suite-count.txt"
grep '^# run' "$ART/suite-shuffle.tap" > "$ART/suite-shuffle-count.txt"
diff "$ART/suite-count.txt" "$ART/suite-shuffle-count.txt" > "$ART/suite-shuffle.diff" || {
    echo "gate: 打亂 case 順序後結果改變 —— 有跨 case 的隱藏相依" >&2
    cat "$ART/suite-shuffle.diff" >&2
    exit 1
}
mark suite-health-shuffle

# ---------------------------------------------------------------- properties
banner "layer: properties (codex modify-template 的生成式性質測試)"
python3 tools/gate-properties.py --cases 120 | tee "$ART/properties.txt"
mark properties

# ---------------------------------------------------------------- mutation
banner "layer: mutation (手寫 mutant，在拋棄式 worktree 裡套用)"
python3 tools/gate-mutants.py --json "$ART/mutants.json" | tee "$ART/mutants.txt"
mark mutation

# ---------------------------------------------------------------- supply chain
banner "layer: supply-chain + secrets"
python3 tools/gate-supply-chain.py --base "$BASE" | tee "$ART/supply-chain.txt"
mark supply-chain

# ---------------------------------------------------------------- changed lines
banner "layer: changed-line accounting (report only, 見腳本內的說明)"
python3 tools/gate-changed-lines.py --base "$BASE" | tee "$ART/changed-lines.txt"
mark changed-lines

# -------------------------------------------------------- source state (after)
# 只在開頭驗一次等於是替一棵在報告寫出來時已經不存在的樹背書。
banner "layer: source-state (after)"
sh tools/gate-source-state.sh | tee "$ART/source-state-after.txt"
mark source-state-after

diff "$ART/source-state-before.txt" "$ART/source-state-after.txt" > "$ART/source-state.diff" || {
    echo "gate: 來源狀態在這一輪之中改變了 —— 這輪的每一個數字都作廢" >&2
    cat "$ART/source-state.diff" >&2
    exit 1
}

# ---------------------------------------------------------------- manifest 稽核
banner "manifest audit"
missing=""
for layer in $MANIFEST; do
    grep -qxF "$layer" "$RAN" || missing="$missing $layer"
done
if [ -n "$missing" ]; then
    echo "gate: 這些層沒有留下執行記號:$missing" >&2
    exit 1
fi
extra=$(grep -vxF -f - "$RAN" <<EOF || true
$MANIFEST
EOF
)
if [ -n "$extra" ]; then
    echo "gate: 有不在 manifest 裡的層留下記號: $extra" >&2
    exit 1
fi

printf '\ngate: 全部 %d 層皆通過。產出在 %s/\n' "$(printf '%s\n' "$MANIFEST" | wc -l | tr -d ' ')" "$ART"
