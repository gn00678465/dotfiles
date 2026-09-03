# L10 — POSIX 回歸。SPEC Must NOT #2：Linux/macOS 現有的 target 集合與檔案內容
# 不得因為這次 Windows 支援而改變。nvim/uv 改走共用 template 屬等價重構，
# 渲染結果必須逐位元組相同。
#
# 做法：把 base ref 的來源樹解到暫存目錄，兩邊各 apply 一次到各自的 destination
# （--exclude=scripts,externals：不執行任何腳本、不下載任何 external），再整棵樹 diff。

_BASE_REF=$(sed -n 's/^- `base_ref`: `\([0-9a-f]*\)`.*/\1/p' "$REPO/specs/windows-support/SPEC.md" | head -1)

if [ -z "$_BASE_REF" ]; then
    skip "POSIX 回歸" "SPEC 裡讀不到 base ref"
elif ! git -C "$REPO" cat-file -e "$_BASE_REF^{commit}" 2>/dev/null; then
    skip "POSIX 回歸" "base ref $_BASE_REF 不在這個 repo 裡"
else
    _base_src="$TMP/base-src"
    mkdir -p "$_base_src"
    git -C "$REPO" archive "$_BASE_REF" | tar -x -C "$_base_src"

    # base ref 的模板直接讀 .chezmoi.os，沒有 osOverride 接縫，所以這一段只能用
    # 本機真實的 OS 跑。在 Linux 上跑就是 Linux 的回歸，在 mac 上跑就是 mac 的。
    mkdir -p "$TMP/dest-base" "$TMP/dest-new-native"
    _apply() { # source dest state config
        # 測試用的 --config 本來就不是 .chezmoi.toml.tmpl 產生的，chezmoi 每次都會
        # 提醒一次；那是預期中的，濾掉，其他任何輸出都算錯誤。
        chezmoi --source "$1" --destination "$2" --persistent-state "$3" \
                --config "$4" --no-tty apply --exclude=scripts,externals 2>&1 \
            | grep -v 'config file template has changed' || true
    }
    _base_out=$(_apply "$_base_src" "$TMP/dest-base" "$TMP/st-base.boltdb" "$FIXTURES/native.toml") || true
    _new_out=$(_apply "$REPO" "$TMP/dest-new-native" "$TMP/st-newnat.boltdb" "$FIXTURES/native.toml") || true

    if [ -n "$_base_out" ]; then _fail "base ref apply 無錯誤" "$_base_out"; else _pass "base ref apply 無錯誤"; fi
    if [ -n "$_new_out" ]; then _fail "目前來源 apply 無錯誤" "$_new_out"; else _pass "目前來源 apply 無錯誤"; fi

    _diff=$(diff -r "$TMP/dest-base" "$TMP/dest-new-native" 2>&1) || true
    assert_eq "本機 OS 上，套用結果與 base ref 逐位元組相同" "" "$_diff"

    # managed 清單：新舊之間只准多出四支 Windows 腳本，其他一律不准動。
    _base_mg=$(chezmoi --source "$_base_src" --destination "$TMP/dest-base" \
                 --persistent-state "$TMP/st-base.boltdb" --config "$FIXTURES/native.toml" \
                 --no-tty managed --exclude=externals | LC_ALL=C sort)
    _new_mg=$(chezmoi --source "$REPO" --destination "$TMP/dest-new-native" \
                 --persistent-state "$TMP/st-newnat.boltdb" --config "$FIXTURES/native.toml" \
                 --no-tty managed --exclude=externals | LC_ALL=C sort)
    # dash 沒有 process substitution，走暫存檔。
    printf '%s\n' "$_base_mg" > "$TMP/mg-base.txt"
    printf '%s\n' "$_new_mg"  > "$TMP/mg-new.txt"
    # LC_ALL=C 兩邊都要：清單是用 `LC_ALL=C sort` 排的，而 comm 在別的語系下會用
    # 不同的定序，於是判定「輸入沒有排序」並中止整層。這在合併 main 之前不會出現 ——
    # 要等到清單裡真的出現 C 與本機語系定序不同的項目（`.agents/workflow`、
    # `.claude/agents`）才會爆。
    _added=$(LC_ALL=C comm -13 "$TMP/mg-base.txt" "$TMP/mg-new.txt")
    _removed=$(LC_ALL=C comm -23 "$TMP/mg-base.txt" "$TMP/mg-new.txt")
    assert_eq "本機 OS 上，managed 只多出五支 Windows 腳本" \
"$(printf '%s\n' \
  '.chezmoiscripts/30-install-winget-packages.ps1' \
  '.chezmoiscripts/35-install-ps-modules.ps1' \
  '.chezmoiscripts/40-git-lfs.ps1' \
  '.chezmoiscripts/50-neovim.ps1' \
  '.chezmoiscripts/60-pwsh-profile.ps1' | LC_ALL=C sort)" \
        "$_added"
    assert_eq "本機 OS 上，managed 沒有任何 target 消失" "" "$(printf '%s' "$_removed")"

    # macOS 沒有實機，base ref 也沒有 osOverride 接縫，所以 darwin 只能間接釘：
    # 證明「新來源的 darwin 輸出」與「新來源的 linux 輸出」之間的差異，就只有
    # brew prefix 那一項。上面已經證明 linux 側與 base 完全相同，兩段接起來，
    # darwin 側就被釘在 base 的行為上了。
    mkdir -p "$TMP/dest-new-darwin"
    _dw_out=$(_apply "$REPO" "$TMP/dest-new-darwin" "$TMP/st-newdw.boltdb" "$FIXTURES/os-darwin-arm64.toml") || true
    if [ -n "$_dw_out" ]; then _fail "darwin apply 無錯誤" "$_dw_out"; else _pass "darwin apply 無錯誤"; fi

    _changed_files=$(diff -rq "$TMP/dest-new-native" "$TMP/dest-new-darwin" 2>&1 \
                     | sed -n 's/^Files .* and \(.*\) differ$/\1/p' \
                     | sed "s|$TMP/dest-new-darwin/||" | LC_ALL=C sort)
    assert_eq "linux 與 darwin 的輸出差異只落在 .zprofile 與 .zshrc" \
        "$(printf '.zprofile\n.zshrc\n')" "$_changed_files"

    _substantive=$(diff -r "$TMP/dest-new-native" "$TMP/dest-new-darwin" 2>&1 \
                   | grep '^[<>]' | grep -v 'linuxbrew' | grep -v 'homebrew' || true)
    assert_eq "那兩個檔案的差異只有 brew prefix 一項" "" "$_substantive"
fi

unset _BASE_REF _base_src _base_out _new_out _diff _base_mg _new_mg _added _removed _dw_out _changed_files _substantive

# external 也要釘回歸：L10 上面的 apply 帶 --exclude=externals，不會碰到它們。
# 比對忽略空行與註解：兩者在 TOML 裡都沒有語意，而 {{ if }} 包裹會多出空行、
# 註解這次也刻意改寫過（六個平台、多一種副檔名）。這裡要釘的是實際生效的定義。
_BASE_REF2=$(sed -n 's/^- `base_ref`: `\([0-9a-f]*\)`.*/\1/p' "$REPO/specs/windows-support/SPEC.md" | head -1)
if [ -n "$_BASE_REF2" ] && [ -d "$TMP/base-src" ]; then
    _base_ext=$(chezmoi --source "$TMP/base-src" --destination "$TMP/dest-base" \
        --persistent-state "$TMP/st-base.boltdb" --config "$FIXTURES/native.toml" --no-tty \
        execute-template < "$TMP/base-src/.chezmoiexternal.toml.tmpl" | sed -e '/^[[:space:]]*$/d' -e '/^[[:space:]]*#/d')
    _new_ext=$(render_file native .chezmoiexternal.toml.tmpl | sed -e '/^[[:space:]]*$/d' -e '/^[[:space:]]*#/d')
    assert_eq "本機 OS 上，external 的實際定義與 base ref 相同（忽略空行與註解）" "$_base_ext" "$_new_ext"
fi
unset _BASE_REF2 _base_ext _new_ext

# .chezmoi.toml.tmpl 產生的是 chezmoi 自己的設定，不是 target，所以上面那段整棵樹
# 的 diff 看不到它。Windows 的直譯器修法動到這個檔案，而它同時決定 POSIX 機器
# 產生什麼設定 —— Must NOT #2 管得到，卻沒有任何程序在看。
if [ -d "$TMP/base-src" ]; then
    # sourceDir 那一行必然不同：兩次渲染用的 --source 就是不同的目錄。把它濾掉，
    # 再單獨斷言兩邊都還有那一行 —— 否則「整個功能被拿掉」也會通過這個比對。
    chezmoi --source "$TMP/base-src" --destination "$TMP/dest-base" \
        --persistent-state "$TMP/st-base.boltdb" --config "$FIXTURES/native.toml" --no-tty \
        execute-template < "$TMP/base-src/.chezmoi.toml.tmpl" > "$TMP/base-cfg-raw" 2>&1
    render_file native .chezmoi.toml.tmpl > "$TMP/new-cfg-raw" 2>&1
    grep -v '^sourceDir = ' "$TMP/base-cfg-raw" > "$TMP/base-cfg"
    grep -v '^sourceDir = ' "$TMP/new-cfg-raw" > "$TMP/new-cfg"
    assert_bytes_eq "本機 OS 上，.chezmoi.toml.tmpl 的渲染與 base ref 逐位元組相同（sourceDir 除外）" \
        "$TMP/base-cfg" "$TMP/new-cfg"
    assert_contains "sourceDir 仍然有被寫出來（濾掉它不等於可以拿掉它）" \
        "$(cat "$TMP/new-cfg-raw")" 'sourceDir = '
fi

# isWSL = true 的那一種渲染也要釘。dot_zshrc.tmpl 有一段只在 WSL 上輸出的 alias，
# 而上面的 apply 全部走 isWSL = false 的 fixture。
if [ -d "$TMP/base-src" ]; then
    _base_wsl=$(chezmoi --source "$TMP/base-src" --destination "$TMP/dest-base" \
        --persistent-state "$TMP/st-base.boltdb" --config "$FIXTURES/native-wsl.toml" --no-tty \
        execute-template < "$TMP/base-src/dot_zshrc.tmpl")
    _new_wsl=$(render_file native-wsl dot_zshrc.tmpl)
    assert_eq "isWSL = true 時 .zshrc 的渲染與 base ref 相同" "$_base_wsl" "$_new_wsl"
    assert_contains "isWSL = true 確實會輸出 WSL 專用的 alias（證明這個 fixture 有作用）" \
        "$_new_wsl" "clip.exe"
    _new_nowsl=$(render_file native dot_zshrc.tmpl)
    assert_not_contains "isWSL = false 時不輸出那段 alias" "$_new_nowsl" "clip.exe"
fi
unset _base_wsl _new_wsl _new_nowsl

# 上面的 apply 帶 --exclude=scripts，所以腳本的**內容**完全沒有跟 base 比對過。
# 獨立驗證用這個洞做到：把 tree-sitter 從 brew 清單裡拿掉（AGENTS.md 明文禁止的
# 那一項）→ 全套 387 個測試照樣全綠。Must NOT #2 說的是「不得改變 Linux/macOS
# 現有行為」，而腳本內容正是行為本身。
if [ -d "$TMP/base-src" ]; then
    for _f in "$TMP/base-src"/.chezmoiscripts/*; do
        [ -e "$_f" ] || continue
        _s=$(basename "$_f")
        # base 沒有的腳本（這次新增的 Windows 那幾支）沒有可比對的對象。
        [ -f "$REPO/.chezmoiscripts/$_s" ] || { _fail "base 的腳本 $_s 仍然存在" "被刪掉了"; continue; }
        chezmoi --source "$TMP/base-src" --destination "$TMP/dest-base" \
            --persistent-state "$TMP/st-base.boltdb" --config "$FIXTURES/native.toml" --no-tty \
            execute-template < "$_f" > "$TMP/base-script-$_s" 2>&1
        render_file native ".chezmoiscripts/$_s" > "$TMP/new-script-$_s" 2>&1

        assert_bytes_eq "本機 OS 上，$_s 的渲染結果與 base ref 逐位元組相同" \
            "$TMP/base-script-$_s" "$TMP/new-script-$_s"
    done
fi
unset _f _s
