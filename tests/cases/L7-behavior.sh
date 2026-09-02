# L7 — 行為測試。真的把腳本跑起來，看它對既有檔案做了什麼。
#
# 這是 Tier 3 的核心：M2（Windows 上覆蓋或刪除既有的 nvim 設定）、
# M3（重跑時把使用者自己的設定當成外來設定搬走）、M10（profile loader 重複追加）。
# 這三條的傷害都是使用者資料，而且都不是靠讀模板渲染結果能看出來的。
#
# 一切都在重導向的環境裡跑：假的 HOME / LOCALAPPDATA / TEMP / ProgramFiles，
# 加上 mise 與 git 的 stub。SPEC Must NOT #1 禁止碰真實主機。

# ---------- 共用：組出一棵「使用者已經有東西」的既有 nvim 樹 ----------
_seed_nvim() { # config data state cache
    for _dir in "$@"; do
        mkdir -p "$_dir"
        printf 'USER-CONTENT\n' > "$_dir/user-marker.txt"
    done
}

_assert_backup() { # label original
    if [ -d "$2.bak" ] && [ "$(cat "$2.bak/user-marker.txt" 2>/dev/null)" = "USER-CONTENT" ]; then
        _pass "$1"
    else
        _fail "$1" "期待 $2.bak 存在且保留使用者內容" "$(ls -a "$(dirname "$2")" 2>&1)"
    fi
}

# ================= A. POSIX 的 50-neovim =================
_a="$TMP/l7a"
rm -rf "$_a"; mkdir -p "$_a/home" "$_a/stub"
# stub：brew shellenv 吐空字串，mise 什麼都不做，git clone 生出一棵假的 starter。
printf '#!/bin/sh\nexit 0\n' > "$_a/stub/brew"
printf '#!/bin/sh\necho "$@" >> "%s/mise-calls.log"\nexit 0\n' "$_a" > "$_a/stub/mise"
cat > "$_a/stub/git" <<'STUB'
#!/bin/sh
# git clone --depth 1 <url> <dest>
if [ "$1" = "clone" ]; then
    dest=$5
    mkdir -p "$dest/.git"
    printf 'starter\n' > "$dest/init.lua"
fi
exit 0
STUB
chmod +x "$_a/stub/"*
render_file linux .chezmoiscripts/run_onchange_before_50-neovim.sh.tmpl > "$_a/50-neovim.sh"

# 光把 stub 放進 PATH 不夠：腳本第一行是
#   eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
# 那會把「真實的」brew bin 目錄 prepend 到 PATH **最前面**，蓋掉 stub，於是測試
# 會去跑真的 mise、真的從網路抓 neovim、還會讀到使用者自己的 mise 設定。
# 這是獨立驗證抓到的：那個 brew stub 原本是死碼（腳本用絕對路徑呼叫 brew）。
#
# 解法是把真實的 brew prefix 從這個 process 的檔案系統視圖裡拿掉：開一個
# mount namespace，把一個空目錄 bind 到 /home/linuxbrew 上。brew 因此不存在、
# shellenv 吐空字串、PATH 不變，stub 才真的生效。
mkdir -p "$_a/emptybrew"
cat > "$_a/run.sh" <<RUNEOF
#!/bin/sh
mount --bind "$_a/emptybrew" /home/linuxbrew
export HOME="$_a/home"
export XDG_CONFIG_HOME="$_a/home/.config"
export XDG_DATA_HOME="$_a/home/.local/share"
export XDG_STATE_HOME="$_a/home/.local/state"
export XDG_CACHE_HOME="$_a/home/.cache"
export PATH="$_a/stub:\$PATH"
exec zsh "$_a/50-neovim.sh"
RUNEOF
chmod +x "$_a/run.sh"

_HAVE_NS=0
if unshare --map-root-user --mount true >/dev/null 2>&1; then _HAVE_NS=1; fi

_run_a() {
    unshare --map-root-user --mount "$_a/run.sh" 2>&1
}

if [ "$_HAVE_NS" = 0 ]; then
    skip "POSIX 50-neovim 的備份行為" \
        "需要 user namespace（unshare --map-root-user --mount）才能把真實的 brew prefix 蓋掉；沒有它這一段會去動真實的 mise 與網路"
else

_seed_nvim "$_a/home/.config/nvim" "$_a/home/.local/share/nvim" \
           "$_a/home/.local/state/nvim" "$_a/home/.cache/nvim"
if _out=$(_run_a); then _pass "POSIX 50-neovim 第一次執行成功"
else _fail "POSIX 50-neovim 第一次執行成功" "$_out"; fi

_assert_backup "POSIX: 既有 ~/.config/nvim 被備份而非刪除" "$_a/home/.config/nvim"
_assert_backup "POSIX: 既有 ~/.local/share/nvim 被備份"     "$_a/home/.local/share/nvim"
_assert_backup "POSIX: 既有 ~/.local/state/nvim 被備份"     "$_a/home/.local/state/nvim"
_assert_backup "POSIX: 既有 ~/.cache/nvim 被備份"           "$_a/home/.cache/nvim"
assert_eq "POSIX: starter 已放進 ~/.config/nvim" "starter" \
    "$(cat "$_a/home/.config/nvim/init.lua" 2>&1)"
assert_eq "POSIX: starter 的 .git 已刪除" "absent" \
    "$([ -e "$_a/home/.config/nvim/.git" ] && echo present || echo absent)"
assert_eq "POSIX: marker 已建立" "present" \
    "$([ -f "$_a/home/.config/nvim/.chezmoi-lazyvim-starter" ] && echo present || echo absent)"

# M3：重跑時，~/.config/nvim 裡是使用者自己的設定，不可以再被搬走重 clone。
printf 'MY-OWN-EDIT\n' > "$_a/home/.config/nvim/init.lua"
if _out=$(_run_a); then _pass "POSIX 50-neovim 第二次執行成功"
else _fail "POSIX 50-neovim 第二次執行成功" "$_out"; fi
assert_eq "POSIX: 重跑不會動使用者自己的設定（M3）" "MY-OWN-EDIT" \
    "$(cat "$_a/home/.config/nvim/init.lua" 2>&1)"
assert_eq "POSIX: 重跑不會多生一份備份" "1" \
    "$(ls -d "$_a"/home/.config/nvim.bak* 2>/dev/null | wc -l | tr -d ' ')"

# 已經有 .bak 時要改用時間戳，不可以把舊備份埋進新備份裡。
rm -f "$_a/home/.config/nvim/.chezmoi-lazyvim-starter"
if _out=$(_run_a); then _pass "POSIX 50-neovim 第三次執行成功"
else _fail "POSIX 50-neovim 第三次執行成功" "$_out"; fi
assert_eq "POSIX: 舊的 .bak 沒有被埋掉" "USER-CONTENT" \
    "$(cat "$_a/home/.config/nvim.bak/user-marker.txt" 2>&1)"
assert_eq "POSIX: 第二份備份用時間戳另存" "2" \
    "$(ls -d "$_a"/home/.config/nvim.bak* 2>/dev/null | wc -l | tr -d ' ')"

# 隔離是否真的生效，用可觀察的事實釘住：stub 的 mise 會留下記號，真的 mise 不會。
# 第四次：時間戳只到秒，同一秒內再備份一次必須另外命名，而不是塞進上一份備份裡。
rm -f "$_a/home/.config/nvim/.chezmoi-lazyvim-starter"
if _out=$(_run_a); then _pass "POSIX 50-neovim 第四次執行成功"
else _fail "POSIX 50-neovim 第四次執行成功" "$_out"; fi
assert_eq "POSIX: 三份備份彼此獨立" "3" \
    "$(ls -d "$_a"/home/.config/nvim.bak* 2>/dev/null | wc -l | tr -d ' ')"
assert_eq "POSIX: 沒有任何備份被塞進另一份備份裡" "" \
    "$(find "$_a/home/.config" -mindepth 2 -maxdepth 2 -name nvim -type d 2>/dev/null)"

assert_eq "POSIX: 跑到的是 stub 的 mise 而不是真實的 mise（隔離生效）" "4" \
    "$(wc -l < "$_a/mise-calls.log" 2>/dev/null | tr -d ' ')"

fi   # _HAVE_NS

# ================= B. Windows 的 50-neovim =================
_PWSH=$(command -v pwsh.exe 2>/dev/null || true)
_WT=""
if [ -n "$_PWSH" ]; then
    _WT=$("$_PWSH" -NoProfile -NonInteractive -Command '$env:TEMP' 2>/dev/null | tr -d '\r')
    _WU=$(wslpath -u "$_WT" 2>/dev/null || echo "")
    [ -n "$_WU" ] || _PWSH=""
fi

if [ -z "$_PWSH" ]; then
    skip "Windows 50-neovim 的備份行為" "找不到可用的 pwsh.exe"
else
    _id="l7b-$$"
    _bw="$_WU/$_id"; _bn="$_WT\\$_id"
    rm -rf "$_bw"; mkdir -p "$_bw/local" "$_bw/temp" "$_bw/pf" "$_bw/stub"
    printf '@echo off\r\nexit /b 0\r\n' > "$_bw/stub/mise.cmd"
    printf '@echo off\r\nif "%%1"=="clone" (\r\n  mkdir "%%~5" 2>nul\r\n  mkdir "%%~5\\.git" 2>nul\r\n  echo starter> "%%~5\\init.lua"\r\n)\r\nexit /b 0\r\n' > "$_bw/stub/git.cmd"
    render_file windows .chezmoiscripts/run_onchange_before_50-neovim.ps1.tmpl > "$_bw/50-neovim.ps1"

    # 假的 %LOCALAPPDATA% / %TEMP% / %ProgramFiles%：腳本算出來的每一條路徑都會
    # 落在這個沙盒裡，而 windows-path.ps1 想 prepend 的真實目錄都不存在，
    # 所以 stub 不會被真的 mise/git 蓋掉。
    cat > "$_bw/run.ps1" <<PSEOF
\$env:LOCALAPPDATA = '$_bn\\local'
\$env:TEMP = '$_bn\\temp'
\$env:TMP  = '$_bn\\temp'
\$env:ProgramFiles = '$_bn\\pf'
\$env:PATH = '$_bn\\stub;' + \$env:PATH
& '$_bn\\50-neovim.ps1'
exit \$LASTEXITCODE
PSEOF

    _seed_nvim "$_bw/local/nvim" "$_bw/local/nvim-data" "$_bw/temp/nvim"

    if _out=$("$_PWSH" -NoLogo -NoProfile -File "$_bn\\run.ps1" 2>&1); then
        _pass "Windows 50-neovim 第一次執行成功"
    else _fail "Windows 50-neovim 第一次執行成功" "$(printf '%s' "$_out" | tr -d '\r')"; fi

    _assert_backup "Windows: 既有 %LOCALAPPDATA%\\nvim 被備份而非刪除（M2）" "$_bw/local/nvim"
    _assert_backup "Windows: 既有 %LOCALAPPDATA%\\nvim-data 被備份（M2）"    "$_bw/local/nvim-data"
    _assert_backup "Windows: 既有 %TEMP%\\nvim 被備份（M2）"                 "$_bw/temp/nvim"
    # 備份出來的目錄集合必須「剛好」是這三個。Windows 上 state 與 log 就住在
    # nvim-data 裡，不是獨立路徑；如果有人照 POSIX 的四個路徑照抄、生出一個
    # nvim-state 之類的東西，這條會抓到 —— 那代表他對 Windows 的路徑理解是錯的，
    # 而錯的路徑意味著某個真的有資料的目錄沒有被備份。
    assert_eq "Windows: 備份出來的目錄剛好是 nvim / nvim-data / TEMP\\nvim" \
        "$(printf 'local/nvim-data.bak\nlocal/nvim.bak\ntemp/nvim.bak\n')" \
        "$(cd "$_bw" && ls -d local/*.bak temp/*.bak 2>/dev/null | LC_ALL=C sort)"
    assert_eq "Windows: starter 已放進 %LOCALAPPDATA%\\nvim" "starter" \
        "$(tr -d ' \r' < "$_bw/local/nvim/init.lua" 2>&1)"
    assert_eq "Windows: starter 的 .git 已刪除" "absent" \
        "$([ -e "$_bw/local/nvim/.git" ] && echo present || echo absent)"
    assert_eq "Windows: marker 已建立" "present" \
        "$([ -f "$_bw/local/nvim/.chezmoi-lazyvim-starter" ] && echo present || echo absent)"

    printf 'MY-OWN-EDIT\n' > "$_bw/local/nvim/init.lua"
    if _out=$("$_PWSH" -NoLogo -NoProfile -File "$_bn\\run.ps1" 2>&1); then
        _pass "Windows 50-neovim 第二次執行成功"
    else _fail "Windows 50-neovim 第二次執行成功" "$(printf '%s' "$_out" | tr -d '\r')"; fi
    assert_eq "Windows: 重跑不會動使用者自己的設定（M3）" "MY-OWN-EDIT" \
        "$(cat "$_bw/local/nvim/init.lua" 2>&1)"
    assert_eq "Windows: 重跑不會多生一份備份" "1" \
        "$(ls -d "$_bw"/local/nvim.bak* 2>/dev/null | wc -l | tr -d ' ')"

    rm -f "$_bw/local/nvim/.chezmoi-lazyvim-starter"
    if _out=$("$_PWSH" -NoLogo -NoProfile -File "$_bn\\run.ps1" 2>&1); then
        _pass "Windows 50-neovim 第三次執行成功"
    else _fail "Windows 50-neovim 第三次執行成功" "$(printf '%s' "$_out" | tr -d '\r')"; fi
    assert_eq "Windows: 舊的 .bak 沒有被埋掉" "USER-CONTENT" \
        "$(cat "$_bw/local/nvim.bak/user-marker.txt" 2>&1)"
    assert_eq "Windows: 第二份備份用時間戳另存" "2" \
        "$(ls -d "$_bw"/local/nvim.bak* 2>/dev/null | wc -l | tr -d ' ')"

    # ================= C. pwsh profile loader 的冪等性 =================
    # 真正的 $PROFILE 指向使用者的 Documents，不能拿來測。所以 loader 的邏輯被抽成
    # .chezmoitemplates/pwsh-profile-loader.ps1，由呼叫端先設好 $target；
    # 這裡把 $target 指到暫存檔就能測到同一份邏輯。
    _loader=$(render_file windows .chezmoitemplates/pwsh-profile-loader.ps1 2>&1)
    if printf '%s' "$_loader" | grep -q 'CurrentUserAllHosts'; then
        _fail "loader partial 不自己決定目標路徑" "partial 內不該出現 \$PROFILE，目標路徑由呼叫端注入"
    else
        _pass "loader partial 不自己決定目標路徑"
    fi

    _prof="$_bw/profile.ps1"
    printf 'Write-Output "PRE-EXISTING"\n' > "$_prof"
    printf '$target = %s\n%s\n' "'$_bn\\profile.ps1'" "$_loader" > "$_bw/runloader.ps1"
    for _i in 1 2 3; do
        "$_PWSH" -NoLogo -NoProfile -File "$_bn\\runloader.ps1" >/dev/null 2>&1 || true
    done
    # 比對整行而不是子字串：子字串計數對
    #   . "$HOME/.config/powershell/profile.ps1.disabled"
    # 這種變異照樣算 1，而那一行會讓每次開 shell 都報錯、且永遠載不到設定。
    assert_eq "profile loader 跑三次恰好留下一行、且內容逐字正確（M10）" "1" \
        "$(tr -d '\r' < "$_prof" | grep -cxF '. "$HOME/.config/powershell/profile.ps1"' | tr -d ' ')"
    assert_eq "profile loader 保留原本就有的內容" "1" \
        "$(grep -c 'PRE-EXISTING' "$_prof" 2>/dev/null | tr -d ' ')"

    rm -rf "$_bw"
fi

unset _a _out _dir _PWSH _WT _WU _id _bw _bn _loader _prof _i
