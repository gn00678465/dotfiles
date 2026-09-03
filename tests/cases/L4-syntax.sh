# L4 — 語法檢查。渲染後真的會被執行的腳本，至少要能被對應的直譯器解析。
#
# 這一層抓的是「模板拼出來的東西根本不是合法程式」這種錯 —— 那在 POSIX 上是
# apply 中途失敗，在 Windows 上是 chezmoi 直接把 apply 中斷（SPEC F3 同一類後果）。

_PWSH=$(command -v pwsh.exe 2>/dev/null || command -v pwsh 2>/dev/null || true)
_ZSH=$(command -v zsh 2>/dev/null || true)

# pwsh.exe 是 Windows 二進位，看不到 WSL 的路徑，所以待檢查的檔案要落在 Windows
# 自己的 TEMP 底下，兩邊才都讀得到。
#
# 不從 stdin 餵：實測 pwsh.exe 讀 stdin 時不是用 UTF-8 解碼，這些腳本裡的中文註解
# 會被解成亂碼、連換行都被吃掉，於是語法檢查報出一堆假的錯。改用 ParseFile 也更
# 貼近真實情形 —— chezmoi 執行 .ps1 的方式就是 `pwsh -NoLogo -File <檔案>`。
_WINTMP_WIN=""
_WINTMP_WSL="$TMP"
if [ -n "$_PWSH" ]; then
    case "$_PWSH" in
        *.exe)
            _WINTMP_WIN=$("$_PWSH" -NoProfile -NonInteractive -Command '$env:TEMP' 2>/dev/null | tr -d '\r')
            _WINTMP_WSL=$(wslpath -u "$_WINTMP_WIN" 2>/dev/null || echo "")
            [ -n "$_WINTMP_WSL" ] || _PWSH=""      # 轉不出路徑就等於沒有 pwsh
            ;;
    esac
fi

_ps_parse_file() { # wsl-path win-path
    "$_PWSH" -NoProfile -NonInteractive -Command "
\$errors = \$null
[void][System.Management.Automation.Language.Parser]::ParseFile('$2', [ref]\$null, [ref]\$errors)
if (\$errors.Count) { \$errors | ForEach-Object { \$_.ToString() }; exit 1 }
exit 0" 2>&1
}

_check_ps() { # label content
    if [ -z "$_PWSH" ]; then skip "$1 通過 PowerShell 解析" "找不到可用的 pwsh"; return; fi
    _n=$((${_n:-0} + 1))
    _wsl="$_WINTMP_WSL/chezmoi-l4-$$-$_n.ps1"
    printf '%s\n' "$2" > "$_wsl"
    if [ -n "$_WINTMP_WIN" ]; then _win="$_WINTMP_WIN\\chezmoi-l4-$$-$_n.ps1"; else _win="$_wsl"; fi
    # if 的條件位置會關掉 set -e，否則解析失敗會讓整個測試腳本直接中斷。
    if _err=$(_ps_parse_file "$_wsl" "$_win"); then _pass "$1 通過 PowerShell 解析"
    else _fail "$1 通過 PowerShell 解析" "$_err"; fi
    rm -f "$_wsl"
}

_check_sh() { # label content
    if [ -z "$_ZSH" ]; then skip "$1 通過 zsh 解析" "找不到 zsh"; return; fi
    # 腳本的 shebang 是 #!/bin/zsh，而且用了 [[ ]]、local、&> 這些 zsh 語法，
    # 所以要用 zsh -n 而不是 sh -n。
    if _err=$(printf '%s' "$2" | "$_ZSH" -n 2>&1); then _pass "$1 通過 zsh 解析"
    else _fail "$1 通過 zsh 解析" "$_err"; fi
}

for _os in $ALL_OSES; do
    for _f in "$REPO"/.chezmoiscripts/*; do
        _s=$(basename "$_f")
        _c=$(render_file "$_os" ".chezmoiscripts/$_s" 2>&1)
        _stripped=$(printf '%s' "$_c" | tr -d ' \t\n\r')
        [ -n "$_stripped" ] || continue        # 渲染成空的不會被執行，不用檢查
        case $_s in
            *.ps1.tmpl) _check_ps "$_os / $_s" "$_c" ;;
            *.sh.tmpl)  _check_sh "$_os / $_s" "$_c" ;;
        esac
    done
done

# 使用者每次開 shell 都會載入的檔案，壞掉的後果最直接。
_check_ps "windows / profile.ps1" \
    "$(render_file windows private_dot_config/powershell/profile.ps1.tmpl)"
for _os in $POSIX_OSES; do
    _check_sh "$_os / .zshrc" "$(render_file "$_os" dot_zshrc.tmpl)"
    _check_sh "$_os / .zprofile" "$(render_file "$_os" dot_zprofile.tmpl)"
done

# 自舉腳本不經過 chezmoi 算繪，直接檢查原始檔。
if [ -f "$REPO/init.ps1" ]; then
    _check_ps "init.ps1" "$(cat "$REPO/init.ps1")"
else
    _fail "init.ps1 存在" "Windows 的自舉腳本還沒寫"
fi
if [ -f "$REPO/init.sh" ]; then
    if _err=$(sh -n "$REPO/init.sh" 2>&1); then _pass "init.sh 通過 sh 解析"
    else _fail "init.sh 通過 sh 解析" "$_err"; fi
fi

unset _PWSH _ZSH _os _f _s _c _stripped _err

# init.ps1 的前提是「機器上只有 Windows PowerShell 5.1」——它要先把 pwsh 7 裝起來。
# 所以它必須能被 5.1 的解析器接受，光是 pwsh 7 能解析並不夠。
_WPS=$(command -v powershell.exe 2>/dev/null || true)
if [ -z "$_WPS" ] || [ -z "$_WINTMP_WIN" ]; then
    skip "init.ps1 通過 Windows PowerShell 5.1 解析" "找不到 powershell.exe"
else
    cp "$REPO/init.ps1" "$_WINTMP_WSL/chezmoi-l4-51-$$.ps1"
    if _err=$("$_WPS" -NoProfile -NonInteractive -Command "
\$errors = \$null
[void][System.Management.Automation.Language.Parser]::ParseFile('$_WINTMP_WIN\\chezmoi-l4-51-$$.ps1', [ref]\$null, [ref]\$errors)
if (\$errors.Count) { \$errors | ForEach-Object { \$_.ToString() }; exit 1 }
exit 0" 2>&1); then
        _pass "init.ps1 通過 Windows PowerShell 5.1 解析"
    else
        _fail "init.ps1 通過 Windows PowerShell 5.1 解析" "$_err"
    fi
    rm -f "$_WINTMP_WSL/chezmoi-l4-51-$$.ps1"
fi

# sandbox 的探針由 Windows Sandbox 的 LogonCommand 以 Windows PowerShell 5.1 執行
# （沙箱基礎映像沒有 pwsh），所以它跟 init.ps1 受同一組限制。壞掉的探針等於白跑
# 一次 20-30 分鐘的沙箱。
if LC_ALL=C grep -qP '[^\x00-\x7F]' "$REPO/tests/sandbox/_probe.ps1" 2>/dev/null; then
    _fail "sandbox _probe.ps1 是純 ASCII" "$(LC_ALL=C grep -nP '[^\x00-\x7F]' "$REPO/tests/sandbox/_probe.ps1" | head -3)"
else
    _pass "sandbox _probe.ps1 是純 ASCII"
fi
if [ -z "$_WPS" ] || [ -z "$_WINTMP_WIN" ]; then
    skip "sandbox _probe.ps1 通過 Windows PowerShell 5.1 解析" "找不到 powershell.exe"
else
    cp "$REPO/tests/sandbox/_probe.ps1" "$_WINTMP_WSL/chezmoi-l4-probe-$$.ps1"
    if _err=$("$_WPS" -NoProfile -NonInteractive -Command "
\$errors = \$null
[void][System.Management.Automation.Language.Parser]::ParseFile('$_WINTMP_WIN\\chezmoi-l4-probe-$$.ps1', [ref]\$null, [ref]\$errors)
if (\$errors.Count) { \$errors | ForEach-Object { \$_.ToString() }; exit 1 }
exit 0" 2>&1); then
        _pass "sandbox _probe.ps1 通過 Windows PowerShell 5.1 解析"
    else
        _fail "sandbox _probe.ps1 通過 Windows PowerShell 5.1 解析" "$_err"
    fi
    rm -f "$_WINTMP_WSL/chezmoi-l4-probe-$$.ps1"
fi

unset _WPS _WINTMP_WIN _WINTMP_WSL

# init.ps1 必須是純 ASCII。Windows PowerShell 5.1 用 ANSI 代碼頁去解無 BOM 的
# .ps1，非 ASCII 位元組會被解壞，而被解壞的註解是語法錯誤不只是難看
# （這條斷言是被真實的 5.1 解析失敗逼出來的，不是預防性的）。
if LC_ALL=C grep -qP '[^\x00-\x7F]' "$REPO/init.ps1" 2>/dev/null; then
    _fail "init.ps1 是純 ASCII" "$(LC_ALL=C grep -nP '[^\x00-\x7F]' "$REPO/init.ps1" | head -3)"
else
    _pass "init.ps1 是純 ASCII"
fi
