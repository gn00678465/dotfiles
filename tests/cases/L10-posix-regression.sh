# L10 — POSIX 回歸。SPEC Must NOT #2：Linux/macOS 現有的 target 集合與檔案內容
# 不得因為這次 Windows 支援而改變。nvim/uv 改走共用 template 屬等價重構，
# 渲染結果必須逐位元組相同。
#
# 做法：把 base ref 的來源樹解到暫存目錄，兩邊各 apply 一次到各自的 destination
# （--exclude=scripts,externals：不執行任何腳本、不下載任何 external），再整棵樹 diff。

# SPEC 在 CLOSE（spec-archive）之後會搬到 specs/archive/ 底下，兩個位置都要找。
# 這一段原本只認一個路徑，而讀不到時是 skip —— 封存那一刻整層會靜靜消失，
# 那正是這條分支一路在防的「沉默的降級」。所以：SPEC 完全找不到 = 失敗（repo 的
# 不變量壞了），只有「SPEC 有、但那個 commit 不在這個 repo 裡」才 skip。
_find_spec() {
    for _s in "$REPO/specs/windows-support/SPEC.md" "$REPO/specs/archive/windows-support/SPEC.md"; do
        [ -f "$_s" ] && { printf '%s' "$_s"; return 0; }
    done
    return 1
}
_SPEC_PATH=$(_find_spec || true)
_BASE_REF=$(if [ -n "$_SPEC_PATH" ]; then sed -n 's/^- `base_ref`: `\([0-9a-f]*\)`.*/\1/p' "$_SPEC_PATH" | head -1; fi)

if [ -z "$_SPEC_PATH" ]; then
    _fail "找得到 SPEC（specs/ 或 specs/archive/）" "兩個位置都沒有 windows-support 的 SPEC"
elif [ -z "$_BASE_REF" ]; then
    _fail "SPEC 裡讀得到 base ref" "在 $_SPEC_PATH 裡找不到 base_ref 那一行"
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

    # SPEC v7 之前這裡要求「與 base 逐位元組相同」。base 改成 origin/main 之後，
    # 本分支**刻意**帶著還沒併進 main 的 commit（目前是 443bfc0，把 Phase 6 的
    # 封存時機改到合併前），而那個 commit 動到會部署出去的 agent 文件。
    #
    # 所以要求不再是「沒有差異」，而是「**每一個有差異的 target，都要有本分支
    # 動過的來源檔可以解釋**」。反查用 chezmoi 自己的 source-path，不是猜檔名；
    # 期望集合從 git 導出而不是寫死，所以 443bfc0 併進 main 之後這裡會自動變回
    # 「沒有差異」，不需要有人回來改。
    #
    # 抓得到的仍然是真正該抓的：某個 target 變了、卻沒有對應的來源改動 ——
    # 那就是算繪漂移或誤改，不是這次刻意帶的東西。
    git -C "$REPO" diff --name-only "$_BASE_REF"..HEAD > "$TMP/branch-changed.txt"
    _unexplained=''
    for _f in $(diff -rq "$TMP/dest-base" "$TMP/dest-new-native" 2>/dev/null \
                | sed -n 's|^Files .* and \(.*\) differ$|\1|p'); do
        # 先 realpath：chezmoi 管的是 ~/.claude/skills/<name> 這個 symlink 本身，
        # 不是穿過它看到的檔案。diff -r 會跟著 symlink 走，於是同一個檔案會以
        # 兩個路徑各出現一次，而穿過 symlink 的那一個 source-path 反查不到。
        _real=$(readlink -f "$_f" 2>/dev/null || printf '%s' "$_f")
        _src=$(chezmoi --source "$REPO" --destination "$TMP/dest-new-native" \
                 --persistent-state "$TMP/st-newnat.boltdb" --config "$FIXTURES/native.toml" \
                 --no-tty source-path "$_real" 2>/dev/null | sed "s|^$REPO/||")
        if [ -z "$_src" ] || ! grep -qxF "$_src" "$TMP/branch-changed.txt"; then
            _unexplained="$_unexplained${_unexplained:+ }${_f#$TMP/dest-new-native/}"
        fi
    done
    assert_eq "本機 OS 上，每一個與 base 有差異的 target 都由本分支改過的來源檔解釋" \
        "" "$_unexplained"

    # 只出現在其中一邊的檔案（新增或消失的 target）仍然一條都不准有 ——
    # 那是 managed 集合的變化，由下面兩條斷言各自釘住，這裡先看整棵樹。
    _onlyin=$(diff -rq "$TMP/dest-base" "$TMP/dest-new-native" 2>&1 | grep '^Only in ' || true)
    assert_eq "本機 OS 上，沒有任何 target 只存在於其中一邊" "" "$_onlyin"

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
    # SPEC v7：base_ref 改為 origin/main，而 main 已經含有這份移植（#7），
    # 所以那五支 Windows 腳本在基準裡本來就有，新增集合應該是**空的**。
    # 這是降級的一部分——L10 不再重新驗證「移植只多出這五支」，那件事的證據留在
    # 歷史裡（`777b122` 與更早的每一輪都對 `ccae9d8` 比對過）。
    # 多出來的 target 比照上面「有差異的檔案」的規則：每一條都要有本分支改過的
    # 來源檔可以解釋（05-wsl-user-runtime-dir 是第一個在 base 之後新增的 POSIX
    # 腳本）。反查同樣用 source-path，不猜檔名；沒有來源改動能解釋的新 target
    # 仍然是失敗 —— 那才是這條斷言原本要抓的漂移。
    _unexplained_added=''
    for _t in $_added; do
        _src=$(chezmoi --source "$REPO" --destination "$TMP/dest-new-native" \
                 --persistent-state "$TMP/st-newnat.boltdb" --config "$FIXTURES/native.toml" \
                 --no-tty source-path "$TMP/dest-new-native/$_t" 2>/dev/null | sed "s|^$REPO/||")
        if [ -z "$_src" ] || ! grep -qxF "$_src" "$TMP/branch-changed.txt"; then
            _unexplained_added="$_unexplained_added${_unexplained_added:+ }$_t"
        fi
    done
    assert_eq "本機 OS 上，managed 相對 base 多出的每一個 target 都由本分支新增的來源檔解釋" \
        "" "$_unexplained_added"
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

unset _base_src _base_out _new_out _diff _unexplained _onlyin _src _real _base_mg _new_mg _added _removed _unexplained_added _t _dw_out _changed_files _substantive

# external 也要釘回歸：L10 上面的 apply 帶 --exclude=externals，不會碰到它們。
# 比對忽略空行與註解：兩者在 TOML 裡都沒有語意，而 {{ if }} 包裹會多出空行、
# 註解這次也刻意改寫過（六個平台、多一種副檔名）。這裡要釘的是實際生效的定義。
_BASE_REF2=$_BASE_REF
if [ -n "$_BASE_REF2" ] && [ -d "$TMP/base-src" ]; then
    _base_ext=$(chezmoi --source "$TMP/base-src" --destination "$TMP/dest-base" \
        --persistent-state "$TMP/st-base.boltdb" --config "$FIXTURES/native.toml" --no-tty \
        execute-template < "$TMP/base-src/.chezmoiexternal.toml.tmpl" | sed -e '/^[[:space:]]*$/d' -e '/^[[:space:]]*#/d')
    _new_ext=$(render_file native .chezmoiexternal.toml.tmpl | sed -e '/^[[:space:]]*$/d' -e '/^[[:space:]]*#/d')
    assert_eq "本機 OS 上，external 的實際定義與 base ref 相同（忽略空行與註解）" "$_base_ext" "$_new_ext"
fi
unset _BASE_REF _BASE_REF2 _SPEC_PATH _base_ext _new_ext

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

        # 與上面 target 的規則相同：渲染結果變了，就要有本分支改過的來源檔解釋
        # （腳本自己的 .tmpl，或它 include 的 partial）。沒有來源改動卻變了才是漂移。
        if cmp -s "$TMP/base-script-$_s" "$TMP/new-script-$_s"; then
            _pass "本機 OS 上，$_s 的渲染結果與 base ref 逐位元組相同"
        elif grep -qxF ".chezmoiscripts/$_s" "$TMP/branch-changed.txt"; then
            _pass "本機 OS 上，$_s 的渲染結果與 base 不同，但由本分支改過的來源檔解釋"
        else
            _fail "本機 OS 上，$_s 的渲染結果與 base ref 逐位元組相同" \
                "來源檔 .chezmoiscripts/$_s 不在本分支的改動裡，卻渲染出不同結果" \
                "$(diff "$TMP/base-script-$_s" "$TMP/new-script-$_s" 2>&1 | head -20)"
        fi
    done
fi
unset _f _s
