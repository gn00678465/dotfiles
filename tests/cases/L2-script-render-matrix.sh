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
for _s in run_onchange_before_10-install-packages.sh.tmpl \
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
