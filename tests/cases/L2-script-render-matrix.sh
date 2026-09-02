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
        run_onchange_before_10-install-packages.sh.tmpl)      echo 'linux' ;;
        run_once_before_20-install-homebrew.sh.tmpl)          echo 'linux darwin-arm64 darwin-amd64' ;;
        run_onchange_before_30-install-brew-packages.sh.tmpl) echo 'linux darwin-arm64 darwin-amd64' ;;
        run_onchange_before_30-install-winget-packages.ps1.tmpl) echo 'windows' ;;
        run_onchange_after_40-git-lfs.sh.tmpl)                echo 'linux darwin-arm64 darwin-amd64' ;;
        run_onchange_after_40-git-lfs.ps1.tmpl)               echo 'windows' ;;
        run_onchange_before_50-neovim.sh.tmpl)                echo 'linux darwin-arm64 darwin-amd64' ;;
        run_onchange_before_50-neovim.ps1.tmpl)               echo 'windows' ;;
        run_after_60-pwsh-profile.ps1.tmpl)                   echo 'windows' ;;
        run_after_default-shell.sh.tmpl)                      echo 'linux' ;;
        *) echo '__UNKNOWN__' ;;
    esac
}

# 表裡列到、但 source 樹裡不存在的腳本 —— 抓「整支檔案漏掉」
for _s in run_onchange_before_10-install-packages.sh.tmpl \
          run_once_before_20-install-homebrew.sh.tmpl \
          run_onchange_before_30-install-brew-packages.sh.tmpl \
          run_onchange_before_30-install-winget-packages.ps1.tmpl \
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
