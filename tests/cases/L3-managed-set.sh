# L3 — 每個平台上 chezmoi 到底會管哪些 target（不含 external，external 是 L5）。
#
# 這一層擋的是 SPEC M7：.chezmoiignore 寫反 → Windows 上落下 .zshrc、
# 或 POSIX 上落下 AppData\。整份清單用 golden 比對，順便擋住「新增檔案卻忘了
# 給它平台守衛」以及「repo-only 的檔案漏掉、被裝進 $HOME」。

# LC_ALL=C：排序結果不能隨機器語系而變，否則 golden 在別台機器上會假失敗。
_managed() { cm "$1" managed --exclude=externals | LC_ALL=C sort; }

for _os in $POSIX_OSES; do
    assert_eq "$_os 的 managed 清單" "$(cat "$GOLDEN/managed-posix.txt")" "$(_managed "$_os")"
done
for _os in $WINDOWS_OSES; do
    assert_eq "$_os 的 managed 清單" "$(cat "$GOLDEN/managed-windows.txt")" "$(_managed "$_os")"
done

# 上面的 golden 一旦被誰「順手更新」就會失去意義，所以把最關鍵的幾條互斥性
# 再獨立寫一次。這幾條是使用者真的會看到的後果。
_win=$(_managed windows)
_lin=$(_managed linux)

for _t in .zshrc .zprofile .p10k.zsh .config/nvim/lua/plugins/completion.lua .config/uv/uv.toml; do
    assert_not_contains "windows 上不得管理 $_t" "$_win" "$_t"
done
for _t in .config/powershell/profile.ps1 AppData/Local/nvim/lua/plugins/completion.lua AppData/Roaming/uv/uv.toml; do
    assert_contains "windows 上必須管理 $_t" "$_win" "$_t"
done
for _t in AppData .config/powershell; do
    assert_not_contains "linux 上不得管理 $_t" "$_lin" "$_t"
done
for _t in .zshrc .p10k.zsh .config/nvim/lua/plugins/completion.lua .config/uv/uv.toml; do
    assert_contains "linux 上必須管理 $_t" "$_lin" "$_t"
done

# repo-only 的東西不可以落進 $HOME。docs/ 早就在 .chezmoiignore 裡，tests/ 是這次新加的。
for _os in $ALL_OSES; do
    _m=$(_managed "$_os")
    assert_not_contains "$_os 不得把 tests/ 裝進 \$HOME" "$_m" "tests"
    assert_not_contains "$_os 不得把 docs/ 裝進 \$HOME" "$_m" "docs"
    assert_not_contains "$_os 不得把 .scratch/ 裝進 \$HOME" "$_m" ".scratch"
    # .scratch 開頭是點，chezmoi 本來就會跳過；specs/ 不是，只有 .chezmoiignore 擋得住。
    assert_not_contains "$_os 不得把 specs/ 裝進 \$HOME" "$_m" "specs"
    assert_not_contains "$_os 不得把 tools/ 裝進 \$HOME" "$_m" "tools"
done

unset _os _t _win _lin _m

# ---------- .gitattributes：強制 LF checkout（SPEC v5 M14，使用者選 (c)）----------
# Git for Windows 預設 core.autocrlf=true，全新 Windows 會把來源樹 checkout 成 CRLF，
# 算繪結果就把 \r 帶進受管的設定檔（L9 第二次執行實際抓到）。這是 repo 端的性質，
# 不能靠使用者的 git 設定。
#
# 用 `git check-attr` 問 git 自己的判定，而不是比對 .gitattributes 的字串 ——
# 後者只證明檔案裡有那行字，不證明它對任何一個路徑真的生效。
for _f in dot_codex/modify_private_config.toml \
          .chezmoiscripts/run_before_50-neovim.ps1.tmpl \
          tests/sandbox/_probe.ps1 \
          init.ps1; do
    assert_eq "git 對 $_f 的 eol 判定是 lf" "lf" \
        "$(git -C "$REPO" check-attr eol -- "$_f" | sed 's/.*: //')"
done
unset _f
