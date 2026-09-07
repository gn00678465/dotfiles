# L5 — .chezmoiexternal.toml.tmpl 的分平台結果。
#
# 最要緊的是 SPEC M6：.oh-my-zsh 那個 external 帶 exact = true，意思是 chezmoi 會
# 刪掉 ~/.oh-my-zsh 裡不屬於那個 tarball 的東西。它在 Windows 上必須整段不輸出，
# 否則就是在一個根本沒有 Oh My Zsh 的系統上執行一組刪除規則。

# 取出所有 external 的 section 名稱（TOML 的 ["..."] 表頭）
_sections() { render_file "$1" .chezmoiexternal.toml.tmpl | sed -n 's/^\["\(.*\)"\]$/\1/p' | LC_ALL=C sort; }

_posix_expected=$(printf '%s\n' \
    '.claude/cc-statusline/cc-statusline' \
    '.oh-my-zsh' \
    '.oh-my-zsh/custom/plugins/fzf-tab' \
    '.oh-my-zsh/custom/plugins/zsh-autosuggestions' \
    '.oh-my-zsh/custom/plugins/zsh-syntax-highlighting' \
    '.oh-my-zsh/custom/themes/powerlevel10k' | LC_ALL=C sort)

_windows_expected=$(printf '%s\n' \
    '.claude/cc-statusline/cc-statusline.exe' \
    '.config/oh-my-posh/powerlevel10k_rainbow.omp.json' | LC_ALL=C sort)

for _os in $POSIX_OSES; do
    assert_eq "$_os 的 external 清單" "$_posix_expected" "$(_sections "$_os")"
done
assert_eq "windows 的 external 清單" "$_windows_expected" "$(_sections windows)"

# M6 再獨立寫一次：Windows 上不得出現任何 .oh-my-zsh 相關的 external。
assert_not_contains "windows 上不得有任何 .oh-my-zsh external（exact=true 會刪東西）" \
    "$(render_file windows .chezmoiexternal.toml.tmpl)" ".oh-my-zsh"

# 每個 external 都要釘住內容。唯一的例外是 .oh-my-zsh 本體：ohmyzsh 不發 git tag，
# 這個 repo 刻意用 refreshPeriod 追 master（原始碼裡就有這句註解）。其餘每一個
# 條目都必須有 checksum.sha256，否則就是引入了未釘住的外部下載（Must NOT #5）。
# 比對的是「64 個十六進位字元」而不是「這一行存在」：實測 chezmoi 對空字串的
# checksum 是「不驗證就安裝」而不是「驗證失敗」，所以空值比錯值更危險，
# 而只檢查有沒有那一行的寫法會直接放它過去。
for _os in $ALL_OSES; do
    _missing=$(render_file "$_os" .chezmoiexternal.toml.tmpl | awk '
        function flush() { if (cur != "" && cur != ".oh-my-zsh" && !has) print cur }
        /^\[".*"\]$/ { flush(); cur = $0; sub(/^\["/, "", cur); sub(/"\]$/, "", cur); has = 0; next }
        /^[ \t]*checksum\.sha256[ \t]*=/ {
            v = $0; sub(/^[^=]*=[ \t]*/, "", v); gsub(/"/, "", v)
            if (length(v) == 64) has = 1        # mawk 不吃 {64} 區間量詞，改用長度
        }
        END { flush() }' | LC_ALL=C sort)
    assert_eq "$_os 的每個 external（.oh-my-zsh 本體除外）都有 checksum" "" "$_missing"
done

# 逐字釘住 Windows 兩個新 external 的 sha256。這兩個值是我從官方 .sha256 檔抓下來、
# 又把檔案下載回來自己算過一次比對相符的；寫死在這裡，日後 bump 版本時會被迫重算。
_win_ext=$(render_file windows .chezmoiexternal.toml.tmpl)
assert_contains "cc-statusline win32-x64 的 sha256" "$_win_ext" \
    "d55e2baee3dd6378ee7256574b5104737cfcffbe15228c9a3f50ee32f2ee8bd6"
assert_contains "oh-my-posh powerlevel10k_rainbow 主題的 sha256" "$_win_ext" \
    "d55074433400c2a532ab883986f4e2ebd2b35d9f5d61f355f27eeb1243a78713"
assert_contains "Windows 的 cc-statusline 取 .exe" "$_win_ext" "cc-statusline.exe"

unset _os _posix_expected _windows_expected _missing _win_ext

# Must NOT #5 不只適用於 .chezmoiexternal。安裝腳本裡任何抓「可執行程式碼」的
# 呼叫都算，而 PowerShell Gallery 的模組正是這種。獨立驗證指出原本的
# Install-PSResource 沒有 -Version，等於在安裝腳本裡放一個浮動相依。
_ps_install=$(render_file windows .chezmoiscripts/run_onchange_before_35-install-ps-modules.ps1.tmpl)
assert_contains "PowerShell 模組安裝有帶 -Version" "$_ps_install" "-Version"
# 註解行本來就會提到這個 cmdlet（說明為什麼要釘版本），先濾掉。
_unpinned=$(printf '%s\n' "$_ps_install" | grep 'Install-PSResource' \
    | grep -v '^[[:space:]]*#' | grep -v -- '-Version' || true)
assert_eq "沒有任何 Install-PSResource 少了 -Version" "" "$_unpinned"
unset _ps_install _unpinned

# 哪個平台拿哪一個 asset —— 這個「對應關係」原本沒有被任何東西釘住。
# supply-chain 那一層天生看不到它：sum 是**按 asset 名稱**查的，所以把
# darwin 的 arm64/x64 對調之後，URL 與 pin 仍然一致、也仍然雜湊相符，
# 全套與 supply-chain 都會過。實際後果是 Intel Mac 拿到 arm64 的執行檔
# （"Bad CPU type in executable"）。
_expected_asset() {
    case $1 in
        linux)         echo 'cc-statusline-linux-x64-musl.tar.gz' ;;
        linux-arm64)   echo 'cc-statusline-linux-arm64-musl.tar.gz' ;;
        darwin-amd64)  echo 'cc-statusline-darwin-x64.tar.gz' ;;
        darwin-arm64)  echo 'cc-statusline-darwin-arm64.tar.gz' ;;
        windows)       echo 'cc-statusline-win32-x64.zip' ;;
        windows-arm64) echo 'cc-statusline-win32-arm64.zip' ;;
    esac
}
for _os in $ALL_OSES; do
    _ext=$(render_file "$_os" .chezmoiexternal.toml.tmpl)
    assert_contains "$_os 取的是 $(_expected_asset "$_os")" "$_ext" "$(_expected_asset "$_os")"
done
unset _os _ext

# ---- powerlevel10k 的 .zwc（exact = true 底下的執行期產物） --------------------
# p10k 只要自己的目錄可寫，載入時就把九支腳本 zcompile 成同名 .zwc，沒有開關
# （powerlevel10k.zsh-theme 開頭那段 for f in ...）。這個 external 帶 exact = true，
# 於是 apply 把它們刪掉並記成 remove；下一次 zsh 又編回來，再下一次 apply 就是 AD，
# 在 --no-tty 下停在「has changed since chezmoi last wrote it」、退出碼 1。
# 這裡用真正的 p10k external（釘 tag + sha256）走一遍；要網路，抓不到就 skip。
_zwc_dest="$TMP/l5-zwc"; _zwc_p10k="$_zwc_dest/.oh-my-zsh/custom/themes/powerlevel10k"
_zwc_cm() { # subcommand... -> stdout 濾掉 config 提醒；回傳 chezmoi 自己的退出碼
    chezmoi --source "$REPO" --config "$FIXTURES/os-linux.toml" --destination "$_zwc_dest" \
        --persistent-state "$_zwc_dest.state" --no-tty "$@" </dev/null > "$TMP/l5-zwc.out" 2>&1
    _zrc=$?
    grep -v 'config file template has changed' "$TMP/l5-zwc.out" || true
    return "$_zrc"
}
rm -rf "$_zwc_dest" "$_zwc_dest.state"; mkdir -p "$_zwc_dest/.oh-my-zsh/custom/themes"
if _out=$(_zwc_cm apply --exclude=scripts "$_zwc_p10k") && [ -f "$_zwc_p10k/internal/p10k.zsh" ]; then
    # 模擬 zsh 已經跑過一次：p10k 編譯的九支 .zwc 都在。
    for _f in powerlevel9k.zsh-theme powerlevel10k.zsh-theme internal/p10k.zsh internal/icons.zsh \
              internal/configure.zsh internal/worker.zsh internal/parser.zsh \
              gitstatus/gitstatus.plugin.zsh gitstatus/install; do
        printf 'zwc' > "$_zwc_p10k/$_f.zwc"
    done
    # 已經中招的機器 state 裡有 remove 記錄（那正是 AD 的來源）；先種一筆，證明它們也能復原。
    _zwc_cm state set --bucket=entryState --key="$_zwc_p10k/internal/p10k.zsh.zwc" --value='{"type":"remove"}' >/dev/null         || _fail "種入 remove 記錄" "chezmoi state set 失敗"
    assert_eq "p10k 的 .zwc 不出現在 status" "" "$(_zwc_cm status "$_zwc_p10k")"
    # 寫成 if：run.sh 開了 set -e，`_out=$(失敗的指令)` 會直接結束整個 runner 而不是留下 not ok。
    if _out=$(_zwc_cm apply --exclude=scripts "$_zwc_p10k"); then _rc=0; else _rc=$?; fi
    if [ "$_rc" -eq 0 ] && [ -z "$_out" ]; then _pass "有 .zwc 時 apply --no-tty 不互動、退出碼 0"
    else _fail "有 .zwc 時 apply --no-tty 不互動、退出碼 0（rc=$_rc）" "$_out"; fi
    assert_eq "九支 .zwc 在 apply 後全數保留" "9" "$(find "$_zwc_p10k" -name '*.zwc' | wc -l | tr -d ' ')"
    # exact 仍然有效：不是 .zwc 的雜物照刪。
    printf 'x' > "$_zwc_p10k/internal/stray.txt"
    _zwc_cm apply --exclude=scripts "$_zwc_p10k" >/dev/null || true
    if [ -e "$_zwc_p10k/internal/stray.txt" ]; then _fail "exact 仍會移除非 .zwc 的雜物"
    else _pass "exact 仍會移除非 .zwc 的雜物"; fi
else
    skip "p10k 的 .zwc 在 exact external 底下保留" "p10k external 抓不到（離線？）：$(printf '%s' "$_out" | head -1)"
fi
# 離線時上面整段 skip，這一條不靠網路：pattern 本身要在每個 POSIX 平台的 .chezmoiignore 裡。
for _os in $POSIX_OSES; do
    assert_contains "$_os 的 .chezmoiignore 有 .oh-my-zsh/**/*.zwc" "$(render_file "$_os" .chezmoiignore)" '.oh-my-zsh/**/*.zwc'
done
unset _zwc_dest _zwc_p10k _zrc _out _rc _f _os
