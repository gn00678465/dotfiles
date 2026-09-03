# 測試共用工具。純 POSIX sh，唯一外部相依是 chezmoi 本身。
# 由 tests/run.sh source，各 case 檔再 source 一次是無害的（有 guard）。

[ -n "${_TESTS_LIB_LOADED:-}" ] && return 0
_TESTS_LIB_LOADED=1

REPO="${REPO:?REPO must be set by run.sh}"
TMP="${TMP:?TMP must be set by run.sh}"
FIXTURES="$REPO/tests/fixtures"
GOLDEN="$REPO/tests/golden"

TESTS_RUN=0
TESTS_FAILED=0
TESTS_SKIPPED=0
CURRENT_CASE="?"

# ---- 回報 ---------------------------------------------------------------

_pass() { TESTS_RUN=$((TESTS_RUN + 1)); printf 'ok %d - [%s] %s\n' "$TESTS_RUN" "$CURRENT_CASE" "$1"; }
_fail() {
    TESTS_RUN=$((TESTS_RUN + 1)); TESTS_FAILED=$((TESTS_FAILED + 1))
    printf 'not ok %d - [%s] %s\n' "$TESTS_RUN" "$CURRENT_CASE" "$1"
    shift
    for line in "$@"; do printf '#   %s\n' "$line"; done
}
skip() {
    TESTS_RUN=$((TESTS_RUN + 1)); TESTS_SKIPPED=$((TESTS_SKIPPED + 1))
    printf 'ok %d - [%s] %s # SKIP %s\n' "$TESTS_RUN" "$CURRENT_CASE" "$1" "$2"
}

# 多行值印成可讀的 diff 註解
_dump() {
    printf '#   --- %s ---\n' "$1"
    printf '%s\n' "$2" | sed 's/^/#   | /'
}

# ---- 斷言 ---------------------------------------------------------------

assert_eq() { # name expected actual
    if [ "$2" = "$3" ]; then _pass "$1"; else
        TESTS_RUN=$((TESTS_RUN + 1)); TESTS_FAILED=$((TESTS_FAILED + 1))
        printf 'not ok %d - [%s] %s\n' "$TESTS_RUN" "$CURRENT_CASE" "$1"
        _dump expected "$2"; _dump actual "$3"
    fi
}

assert_contains() { # name haystack needle
    case "$2" in
        *"$3"*) _pass "$1" ;;
        *) TESTS_RUN=$((TESTS_RUN + 1)); TESTS_FAILED=$((TESTS_FAILED + 1))
           printf 'not ok %d - [%s] %s\n' "$TESTS_RUN" "$CURRENT_CASE" "$1"
           printf '#   expected to contain: %s\n' "$3"; _dump haystack "$2" ;;
    esac
}

assert_not_contains() { # name haystack needle
    case "$2" in
        *"$3"*) TESTS_RUN=$((TESTS_RUN + 1)); TESTS_FAILED=$((TESTS_FAILED + 1))
           printf 'not ok %d - [%s] %s\n' "$TESTS_RUN" "$CURRENT_CASE" "$1"
           printf '#   expected NOT to contain: %s\n' "$3"; _dump haystack "$2" ;;
        *) _pass "$1" ;;
    esac
}

# 真正的逐位元組比對。assert_eq 收的是字串，而字串是經過 $(...) 得到的 ——
# command substitution 會吃掉**全部**結尾換行，所以只差在結尾位元組的兩個檔案
# 用 assert_eq 永遠比不出來（實測：193 bytes 與 194 bytes 被判為相同）。
# 凡是宣稱「逐位元組」的斷言都必須走這一條。
assert_bytes_eq() { # name expected-file actual-file
    if [ ! -f "$3" ]; then
        TESTS_RUN=$((TESTS_RUN + 1)); TESTS_FAILED=$((TESTS_FAILED + 1))
        printf 'not ok %d - [%s] %s\n' "$TESTS_RUN" "$CURRENT_CASE" "$1"
        printf '#   實際檔案不存在: %s\n' "$3"
        return
    fi
    if cmp -s "$2" "$3"; then _pass "$1"; else
        TESTS_RUN=$((TESTS_RUN + 1)); TESTS_FAILED=$((TESTS_FAILED + 1))
        printf 'not ok %d - [%s] %s\n' "$TESTS_RUN" "$CURRENT_CASE" "$1"
        printf '#   %s\n' "$(cmp "$2" "$3" 2>&1)"
        printf '#   expected %s bytes, actual %s bytes\n' \
            "$(wc -c < "$2" | tr -d ' ')" "$(wc -c < "$3" | tr -d ' ')"
        _dump expected "$(cat "$2")"
        _dump actual "$(cat "$3")"
    fi
}

# 「渲染成空」是本 repo 唯一的跨平台隔離手段（見 SPEC F2/F3），所以它有專屬斷言：
# 只有空白的內容才算空，一個非空白字元就會讓 chezmoi 真的去執行這支腳本。
assert_blank() { # name actual
    stripped=$(printf '%s' "$2" | tr -d ' \t\n\r')
    if [ -z "$stripped" ]; then _pass "$1"; else
        TESTS_RUN=$((TESTS_RUN + 1)); TESTS_FAILED=$((TESTS_FAILED + 1))
        printf 'not ok %d - [%s] %s\n' "$TESTS_RUN" "$CURRENT_CASE" "$1"
        printf '#   expected blank (chezmoi 才會跳過這支腳本)\n'; _dump actual "$2"
    fi
}

assert_not_blank() { # name actual
    stripped=$(printf '%s' "$2" | tr -d ' \t\n\r')
    if [ -n "$stripped" ]; then _pass "$1"; else
        TESTS_RUN=$((TESTS_RUN + 1)); TESTS_FAILED=$((TESTS_FAILED + 1))
        printf 'not ok %d - [%s] %s\n' "$TESTS_RUN" "$CURRENT_CASE" "$1"
        printf '#   expected non-blank\n'
    fi
}

assert_ok() { # name command...
    name=$1; shift
    if out=$("$@" 2>&1); then _pass "$name"; else
        TESTS_RUN=$((TESTS_RUN + 1)); TESTS_FAILED=$((TESTS_FAILED + 1))
        printf 'not ok %d - [%s] %s\n' "$TESTS_RUN" "$CURRENT_CASE" "$name"
        printf '#   command: %s\n' "$*"; _dump output "$out"
    fi
}

# ---- chezmoi 呼叫 -------------------------------------------------------

# 用指定 OS fixture 跑 chezmoi。每個 OS 有自己的 destination 與 persistent state，
# 免得 run_onchange_ 的狀態在 OS 之間互相汙染。
cm() { # os subcommand...
    _os=$1; shift
    # fixture 檔名有兩種：平台矩陣用的 os-<name>.toml，以及不帶 override 的
    # <name>.toml（native、native-wsl）。兩種都找不到就硬失敗 —— chezmoi 對
    # 「--config 指向不存在的檔案」不會報錯，會安靜地用預設值算繪，於是一個
    # 打錯的 OS 名稱會變成一個看起來正常、實際上什麼 fixture 都沒套的測試。
    _cfg="$FIXTURES/os-$_os.toml"
    if [ ! -f "$_cfg" ]; then _cfg="$FIXTURES/$_os.toml"; fi
    if [ ! -f "$_cfg" ]; then
        printf 'tests: 找不到 fixture config: %s（試過 os-%s.toml 與 %s.toml）\n' \
            "$_os" "$_os" "$_os" >&2
        return 2
    fi
    mkdir -p "$TMP/dest-$_os"
    chezmoi \
        --source "$REPO" \
        --config "$_cfg" \
        --destination "$TMP/dest-$_os" \
        --persistent-state "$TMP/state-$_os.boltdb" \
        --no-tty \
        "$@"
}

# 用指定 OS 渲染一段模板字串
render() { # os template
    printf '%s' "$2" | cm "$1" execute-template
}

# 用指定 OS 渲染 source 裡的一個檔案（給腳本用；chezmoi 的 execute-template
# 讀 stdin，所以直接把檔案內容餵進去，與 chezmoi apply 時的算繪等價）
render_file() { # os path-relative-to-repo
    cm "$1" execute-template < "$REPO/$2"
}

# 六個組合，不是四個。cc-statusline 有六個 release asset，而每個平台的渲染只會吐出
# 對應它自己那一個 —— 少渲染一個組合，就等於那個 asset 的 checksum 從來沒有被任何
# 檢查看過。win32-arm64 與 linux-arm64-musl 原本就是這樣漏掉的。
ALL_OSES='linux linux-arm64 darwin-arm64 darwin-amd64 windows windows-arm64'
POSIX_OSES='linux linux-arm64 darwin-arm64 darwin-amd64'
WINDOWS_OSES='windows windows-arm64'
