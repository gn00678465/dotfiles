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
for _os in $ALL_OSES; do
    _missing=$(render_file "$_os" .chezmoiexternal.toml.tmpl | awk '
        function flush() { if (cur != "" && cur != ".oh-my-zsh" && !has) print cur }
        /^\[".*"\]$/ { flush(); cur = $0; sub(/^\["/, "", cur); sub(/"\]$/, "", cur); has = 0; next }
        /^[ \t]*checksum\.sha256/ { has = 1 }
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
