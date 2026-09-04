# L2 — 腳本渲染矩陣。
#
# 這一層存在的唯一理由是 SPEC F2/F3 這兩個實測事實：
#   F2 渲染後為空的腳本會被 chezmoi 靜默跳過（Linux 與 Windows 兩端皆然）
#   F3 非空的 .sh 在 Windows 上會硬失敗並中斷整個 apply
#       （fork/exec: %1 is not a valid Win32 application）
# 也就是說「跨平台隔離」在這個 repo 裡只有一種手段：渲染成空。
# 這裡逐一釘住每支腳本在每個平台上該空還是該不空。

# 該非空的平台清單。沒列在這張表裡的腳本會被視為「未預期的新腳本」而失敗，
# 免得新增一支腳本卻忘了給它平台守衛。
_expect() {
    case $1 in
        # 只在 isWSL = true 時非空；平台矩陣的 fixture 全是 isWSL = false，所以這裡
        # 是空清單，WSL 那一種渲染在下面用 native-wsl fixture 單獨釘。
        run_onchange_before_05-wsl-user-runtime-dir.sh.tmpl)   echo '' ;;
        run_onchange_before_10-install-packages.sh.tmpl)      echo 'linux linux-arm64' ;;
        run_once_before_20-install-homebrew.sh.tmpl)          echo 'linux linux-arm64 darwin-arm64 darwin-amd64' ;;
        run_onchange_before_30-install-brew-packages.sh.tmpl) echo 'linux linux-arm64 darwin-arm64 darwin-amd64' ;;
        run_onchange_before_30-install-winget-packages.ps1.tmpl) echo 'windows windows-arm64' ;;
        run_onchange_before_35-install-ps-modules.ps1.tmpl)    echo 'windows windows-arm64' ;;
        run_onchange_after_40-git-lfs.sh.tmpl)                echo 'linux linux-arm64 darwin-arm64 darwin-amd64' ;;
        run_onchange_after_40-git-lfs.ps1.tmpl)               echo 'windows windows-arm64' ;;
        run_onchange_before_50-neovim.sh.tmpl)                echo 'linux linux-arm64 darwin-arm64 darwin-amd64' ;;
        run_onchange_before_50-neovim.ps1.tmpl)               echo 'windows windows-arm64' ;;
        run_after_60-pwsh-profile.ps1.tmpl)                   echo 'windows windows-arm64' ;;
        run_after_default-shell.sh.tmpl)                      echo 'linux linux-arm64' ;;
        *) echo '__UNKNOWN__' ;;
    esac
}

# 表裡列到、但 source 樹裡不存在的腳本 —— 抓「整支檔案漏掉」
for _s in run_onchange_before_05-wsl-user-runtime-dir.sh.tmpl \
          run_onchange_before_10-install-packages.sh.tmpl \
          run_once_before_20-install-homebrew.sh.tmpl \
          run_onchange_before_30-install-brew-packages.sh.tmpl \
          run_onchange_before_30-install-winget-packages.ps1.tmpl \
          run_onchange_before_35-install-ps-modules.ps1.tmpl \
          run_onchange_after_40-git-lfs.sh.tmpl \
          run_onchange_after_40-git-lfs.ps1.tmpl \
          run_onchange_before_50-neovim.sh.tmpl \
          run_onchange_before_50-neovim.ps1.tmpl \
          run_after_60-pwsh-profile.ps1.tmpl \
          run_after_default-shell.sh.tmpl; do
    if [ -f "$REPO/.chezmoiscripts/$_s" ]; then
        _pass "腳本存在：$_s"
    else
        _fail "腳本存在：$_s" "$REPO/.chezmoiscripts/$_s 不存在"
    fi
done

for _f in "$REPO"/.chezmoiscripts/*; do
    _s=$(basename "$_f")
    _want=$(_expect "$_s")
    if [ "$_want" = '__UNKNOWN__' ]; then
        _fail "腳本 $_s 在平台表裡有登記" \
              "新增腳本必須同時在 tests/cases/L2 的 _expect 表裡宣告它該在哪些平台非空"
        continue
    fi
    for _os in $ALL_OSES; do
        _out=$(render_file "$_os" ".chezmoiscripts/$_s" 2>&1)
        case " $_want " in
            *" $_os "*) assert_not_blank "$_s 在 $_os 上非空" "$_out" ;;
            *)          assert_blank     "$_s 在 $_os 上渲染成空" "$_out" ;;
        esac
    done
done

# 結構性不變式，與上面那張表互相獨立：
#   Windows 上不得有任何非空的 .sh（F3：會中斷整個 apply）
#   POSIX  上不得有任何非空的 .ps1（POSIX 沒有 pwsh 也不該有）
# 就算有人改壞了上面的表，這兩條也會擋下來。
for _f in "$REPO"/.chezmoiscripts/*.sh.tmpl; do
    [ -e "$_f" ] || continue
    assert_blank "不變式：$(basename "$_f") 在 windows 上必須是空的" \
        "$(render_file windows ".chezmoiscripts/$(basename "$_f")" 2>&1)"
done
for _f in "$REPO"/.chezmoiscripts/*.ps1.tmpl; do
    [ -e "$_f" ] || continue
    for _os in $POSIX_OSES; do
        assert_blank "不變式：$(basename "$_f") 在 $_os 上必須是空的" \
            "$(render_file "$_os" ".chezmoiscripts/$(basename "$_f")" 2>&1)"
    done
done

unset _s _f _want _out _os

# 05-wsl-user-runtime-dir 的守衛是 isWSL，不是 OS：WSL 會把 XDG_RUNTIME_DIR 塞進
# 每一個 process 卻不建那個目錄，原生 Linux 的 logind 會在登入時自己建。所以它在
# isWSL = true 時必須非空，在同一個 OS 的 isWSL = false 時必須是空的。
_wsl=$(render_file native-wsl .chezmoiscripts/run_onchange_before_05-wsl-user-runtime-dir.sh.tmpl 2>&1)
assert_not_blank "05-wsl-user-runtime-dir 在 isWSL = true 時非空" "$_wsl"
assert_contains "05-wsl-user-runtime-dir 用 loginctl enable-linger（不是 mkdir，那個目錄歸 logind 管）" \
    "$_wsl" 'loginctl enable-linger'
assert_blank "05-wsl-user-runtime-dir 在原生 Linux（isWSL = false）渲染成空" \
    "$(render_file native .chezmoiscripts/run_onchange_before_05-wsl-user-runtime-dir.sh.tmpl 2>&1)"
unset _wsl

# 跨檔案一致性：POSIX 與 Windows 的 50-neovim 是兩份檔案，但它們必須釘同一個
# neovim 版本、同一個 marker 檔名、同一個 starter repo。這三個值一旦各寫各的，
# 就會出現「有人 bump 了一邊，另一邊悄悄留在舊版」的分歧。
_posix_nvim=$(render_file linux .chezmoiscripts/run_onchange_before_50-neovim.sh.tmpl)
_win_nvim=$(render_file windows .chezmoiscripts/run_onchange_before_50-neovim.ps1.tmpl)

_pin_posix=$(printf '%s\n' "$_posix_nvim" | sed -n 's/.*neovim@\([0-9][0-9.]*\).*/\1/p' | head -1)
_pin_win=$(printf '%s\n' "$_win_nvim" | sed -n 's/.*neovim@\([0-9][0-9.]*\).*/\1/p' | head -1)
assert_not_blank "POSIX 50-neovim 有釘住的 neovim 版本" "$_pin_posix"
assert_eq "兩個平台的 50-neovim 釘同一個 neovim 版本" "$_pin_posix" "$_pin_win"

_marker_posix=$(printf '%s\n' "$_posix_nvim" | sed -n 's/.*\(\.chezmoi-[a-z-]*\).*/\1/p' | head -1)
_marker_win=$(printf '%s\n' "$_win_nvim" | sed -n 's/.*\(\.chezmoi-[a-z-]*\).*/\1/p' | head -1)
assert_not_blank "POSIX 50-neovim 有 marker 檔名" "$_marker_posix"
assert_eq "兩個平台的 50-neovim 用同一個 marker 檔名" "$_marker_posix" "$_marker_win"

_starter_posix=$(printf '%s\n' "$_posix_nvim" | sed -n 's|.*\(https://github.com/[^ "]*\).*|\1|p' | head -1)
_starter_win=$(printf '%s\n' "$_win_nvim" | sed -n 's|.*\(https://github.com/[^ "]*\).*|\1|p' | head -1)
assert_eq "兩個平台的 50-neovim clone 同一個 starter repo" "$_starter_posix" "$_starter_win"

unset _posix_nvim _win_nvim _pin_posix _pin_win _marker_posix _marker_win _starter_posix _starter_win

# 60-pwsh-profile 必須挑 CurrentUserAllHosts（profile.ps1）而不是
# CurrentUserCurrentHost（Microsoft.PowerShell_profile.ps1）：Windows Terminal、
# VS Code 的整合終端機、裸 pwsh.exe 是三個不同的 host，只有 AllHosts 三者都載入。
# 目標路徑的「選擇」不在被抽出去的 partial 裡，所以 L7 的冪等測試涵蓋不到它。
_pwsh_profile=$(render_file windows .chezmoiscripts/run_after_60-pwsh-profile.ps1.tmpl)
# 比對的是實際的賦值那一行，不是「檔案裡有沒有出現這個字」——腳本的註解本來就
# 會提到 CurrentUserCurrentHost（說明為什麼不用它）。
assert_contains "60-pwsh-profile 把 \$target 指向 \$PROFILE.CurrentUserAllHosts" \
    "$_pwsh_profile" '$target = $PROFILE.CurrentUserAllHosts'
unset _pwsh_profile

# 每一支需要外部工具的 Windows 腳本都必須先套 windows-path partial。少了它，
# chezmoi 跑腳本時的 PATH 看不到 winget 剛裝好的東西，50-neovim 會走
# 「mise not found, skipping neovim」那條路 —— 而那條路**以 exit 0 結束**，
# 整個 neovim/LazyVim 安裝就靜靜地沒發生。實測過那個分歧。
for _s in run_onchange_before_30-install-winget-packages.ps1.tmpl \
          run_onchange_after_40-git-lfs.ps1.tmpl \
          run_onchange_before_50-neovim.ps1.tmpl; do
    _c=$(render_file windows ".chezmoiscripts/$_s")
    assert_contains "$_s 有套用 windows-path partial" "$_c" 'Microsoft\WinGet\Links'
    assert_contains "$_s 的 PATH 補強有含 mise shims" "$_c" 'mise\shims'
done

# PowerShell profile 的內容原本完全沒有被釘住：把主題檔名改掉、或整段拿掉
# PSReadLine 設定，都能存活整套測試。主題檔名尤其危險——external 裝的檔名與
# profile 讀的檔名不一致時，profile 裡的 Test-Path 守衛會**靜靜地跳過**
# oh-my-posh 初始化，使用者只會看到一個沒有主題的提示字元，沒有任何錯誤。
_profile=$(render_file windows private_dot_config/powershell/profile.ps1.tmpl)
_theme=$(render_file windows .chezmoiexternal.toml.tmpl | sed -n 's|^\["\.config/oh-my-posh/\(.*\)"\]$|\1|p')
assert_not_blank "external 有裝一個 oh-my-posh 主題檔" "$_theme"
assert_contains "profile 讀的主題檔名與 external 裝的那一個一致" "$_profile" "$_theme"
assert_contains "profile 有初始化 oh-my-posh" "$_profile" 'oh-my-posh init pwsh'
assert_contains "profile 有開啟 PSReadLine 的歷史預測（對應 zsh-autosuggestions）" \
    "$_profile" 'PredictionSource History'
assert_contains "profile 有載入 PSFzf 的 TabExpansion（對應 fzf-tab）" "$_profile" '-TabExpansion'
assert_contains "profile 有啟用 mise" "$_profile" 'mise activate pwsh'
unset _s _c _profile _theme

# tree-sitter CLI 在兩個平台都要裝，而且要的是 **CLI**：brew 的 `tree-sitter` formula
# 從 0.27 起只裝函式庫，CLI 拆到 `tree-sitter-cli`。少了 CLI，LazyVim 會退回 mason 的
# GitHub 預編譯二進位，那個要 glibc 2.39，Debian 12（2.36）上每一個 parser 都編不過（實測）。
# 只看 `for formula` 那一行：腳本的註解本來就會提到 tree-sitter-cli（說明為什麼不是
# tree-sitter），比對整個檔案會讓「清單裡拿掉、註解裡還在」的 mutant 存活。
_brew=$(render_file linux .chezmoiscripts/run_onchange_before_30-install-brew-packages.sh.tmpl \
        | grep '^for formula')
assert_contains "brew 清單裝的是 tree-sitter-cli（CLI）" "$_brew" ' tree-sitter-cli'
assert_not_contains "brew 清單沒有只裝函式庫的 tree-sitter formula" "$_brew" ' tree-sitter '
assert_contains "winget 清單裝的是 tree-sitter.tree-sitter-cli" \
    "$(render_file windows .chezmoiscripts/run_onchange_before_30-install-winget-packages.ps1.tmpl)" \
    "'tree-sitter.tree-sitter-cli'"
unset _brew

# ---------- .chezmoi.toml.tmpl：直譯器設定 ----------
# L9 第一次真實執行的根因：chezmoi 把 .ps1 寫到 %TEMP% 再交給直譯器，而全新
# Windows 的預設 ExecutionPolicy 是 Restricted，pwsh 7 也受它管（本機實測），
# 於是**第一支腳本就拒載**，整個 apply 在任何檔案落地前中止。乾淨的 Windows 11
# 使用者會在同一點失敗，這不是 Sandbox 特有的。
#
# 修法是讓 chezmoi 用它自己的直譯器設定跑：那份設定由 .chezmoi.toml.tmpl 產生，
# 而且**在同一次 init --apply 裡就生效**（實測：自訂直譯器留下了記號）。
_cfg_win=$(render_file windows .chezmoi.toml.tmpl)
assert_contains "Windows 的設定有釘住 .ps1 的直譯器" "$_cfg_win" '[interpreters.ps1]'
assert_contains "直譯器是 pwsh（不是 Windows PowerShell 5.1）" "$_cfg_win" 'command = "pwsh"'
assert_contains "直譯器帶 -ExecutionPolicy Bypass（Restricted 下腳本一律拒載）" \
    "$_cfg_win" '"-ExecutionPolicy", "Bypass"'
# chezmoi 的預設 args 只有 -NoLogo -File，於是腳本會載入使用者的 pwsh profile ——
# 也就是這個 repo 自己裝的那一份（oh-my-posh、PSFzf、mise）。安裝腳本的行為不該
# 取決於使用者的 profile，POSIX 那邊也沒有這個問題（chezmoi 不走互動 shell）。
assert_contains "直譯器帶 -NoProfile" "$_cfg_win" '"-NoProfile"'
assert_contains "直譯器的最後一個參數是 -File（腳本路徑接在後面）" "$_cfg_win" '"-File"]'

# POSIX 端不得出現這段：那裡沒有 execution policy，多一個設定就是多一條分歧。
for _os in linux linux-arm64 darwin-arm64 darwin-amd64; do
    assert_not_contains "$_os 的設定沒有 interpreters 區段" \
        "$(render_file "$_os" .chezmoi.toml.tmpl)" 'interpreters'
done
unset _cfg_win _os

# ---------- M12 的處置（SPEC v5，使用者選 (a)）----------
# zig 進 winget 清單的唯一理由是「當 nvim-treesitter 的 C compiler」。實測推翻：
# nvim-treesitter main 回報 C compiler ❌，而 zig version 在同一個終端機是 0.16.0
# ——zig 裝好了也找得到，是它的需求檢查不認 zig。所以換成 WinLibs 的 gcc。
_winget=$(render_file windows .chezmoiscripts/run_onchange_before_30-install-winget-packages.ps1.tmpl)
assert_contains "winget 清單有 WinLibs 的 gcc（nvim-treesitter 認得的 C compiler）" \
    "$_winget" "'BrechtSanders.WinLibs.POSIX.UCRT'"
assert_not_contains "zig 已從 winget 清單移除（它的唯一理由已不成立）" "$_winget" "'zig.zig'"
unset _winget
