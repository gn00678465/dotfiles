# L7 — 行為測試。真的把腳本跑起來，看它對既有檔案做了什麼。
#
# 這是 Tier 3 的核心：M2（Windows 上覆蓋或刪除既有的 nvim 設定）、
# M3（重跑時把使用者自己的設定當成外來設定搬走）、M10（profile loader 重複追加）。
# 這三條的傷害都是使用者資料，而且都不是靠讀模板渲染結果能看出來的。
#
# 一切都在重導向的環境裡跑：假的 HOME / LOCALAPPDATA / TEMP / ProgramFiles，
# 加上 mise 與 git 的 stub。這一層不得碰真實主機。

# 時間戳只到秒，所以「.bak 與 .bak.<秒> 同時已存在」這個形狀是有可能的，而它會走到
# 一條 accepted risk 的路徑：mv/Move-Item 把來源搬「進」那份既有備份裡。要觸發它得在
# 同一秒內跑完兩次含 git clone 的 bootstrap，實務上到不了，所以程式碼不處理它。
#
# 這裡把那條路徑釘成 characterization test：先把接下來幾秒的時間戳目錄全部建好，
# 腳本算出來的名字必然已被佔用。這樣做不是宣告它是對的行為，而是讓「有人改了備份
# 命名的形狀」不會無聲通過 —— 資料仍然沒有被刪，只是位置被埋深了一層。
# 撞名視窗要蓋過腳本從啟動到 mv 的整段時間。原本只種 0–6 秒，Windows 那一半經
# WSL interop 啟動 pwsh.exe 常常超過 6 秒，於是同一個 suite 連跑兩次時第二次撞不到
# （連跑兩次 suite 時實際抓到：753 條裡這兩條變紅）。
# 種到 30 秒只是讓撞名一定發生，斷言本身不變。
_seed_stamp_collisions() { # base-path
    _i=0
    while [ "$_i" -le 30 ]; do
        mkdir -p "$1.bak.$(date -d "+$_i second" +%Y%m%d%H%M%S 2>/dev/null || date +%Y%m%d%H%M%S)"
        _i=$((_i + 1))
    done
}

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
render_file linux .chezmoiscripts/run_before_50-neovim.sh.tmpl > "$_a/50-neovim.sh"

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

# 第四次：強制撞名，走到 accepted risk 那條路徑（見本檔開頭）。
rm -f "$_a/home/.config/nvim/.chezmoi-lazyvim-starter"
printf 'GEN4\n' > "$_a/home/.config/nvim/gen-marker.txt"
_seed_stamp_collisions "$_a/home/.config/nvim"
if _out=$(_run_a); then _pass "POSIX 50-neovim 第四次執行成功"
else _fail "POSIX 50-neovim 第四次執行成功" "$_out"; fi
assert_eq "POSIX: 撞名時來源被搬進既有備份裡（accepted risk，位置變深一層）" "1" \
    "$(find "$_a/home/.config" -mindepth 2 -maxdepth 2 -name nvim -type d 2>/dev/null | wc -l | tr -d ' ')"
assert_eq "POSIX: 即使撞名，使用者的內容仍然存在、沒有被刪" "GEN4" \
    "$(cat "$_a"/home/.config/nvim.bak.*/nvim/gen-marker.txt 2>&1)"
assert_eq "POSIX: 沒有產生序號備份（那個迴圈已依使用者決定還原掉）" "0" \
    "$(ls -d "$_a"/home/.config/nvim.bak.*.[0-9]* 2>/dev/null | wc -l | tr -d ' ')"

# 隔離是否真的生效，用可觀察的事實釘住：stub 的 mise 會留下記號，真的 mise 不會。

assert_eq "POSIX: 跑到的是 stub 的 mise 而不是真實的 mise（隔離生效）" "4" \
    "$(wc -l < "$_a/mise-calls.log" 2>/dev/null | tr -d ' ')"

fi   # _HAVE_NS

# ================= A2. Arch 家族的 50-neovim=================
# 同一支模板在 pacman 平台渲染成另一條路：沒有 brew shellenv、沒有 mise，改在執行期
# 以 `pacman -Q omarchy-nvim` 決定要不要 clone starter（D2）。這裡用 stub 的 pacman
# 兩種回答各跑一次。腳本不會呼叫 brew，所以不需要 A 段的 mount namespace。
_ar="$TMP/l7arch"
rm -rf "$_ar"; mkdir -p "$_ar/stub"
cp "$_a/stub/git" "$_ar/stub/git"
printf '#!/bin/sh\necho "$@" >> "%s/mise-calls.log"\nexit 0\n' "$_ar" > "$_ar/stub/mise"
printf '#!/bin/sh\nexit 0\n' > "$_ar/stub/brew"
# stub pacman：只認 `-Q omarchy-nvim`，答案由 STUB_OMARCHY 決定；其他呼叫一律失敗，
# 這樣腳本若多問了別的問題就會在這裡炸出來。
cat > "$_ar/stub/pacman" <<'STUB'
#!/bin/sh
echo "$@" >> "$STUB_PACMAN_LOG"
if [ "$1" = "-Q" ] && [ "$2" = "omarchy-nvim" ]; then
    [ "${STUB_OMARCHY:-0}" = 1 ] && exit 0
    exit 1
fi
exit 2
STUB
chmod +x "$_ar/stub/"*
render_file arch .chezmoiscripts/run_before_50-neovim.sh.tmpl > "$_ar/50-neovim.sh"

_run_arch() { # home omarchy(0|1)
    HOME="$1" XDG_CONFIG_HOME="$1/.config" XDG_DATA_HOME="$1/.local/share" \
    XDG_STATE_HOME="$1/.local/state" XDG_CACHE_HOME="$1/.cache" \
    STUB_OMARCHY="$2" STUB_PACMAN_LOG="$1/pacman-calls.log" PATH="$_ar/stub:$PATH" \
        zsh "$_ar/50-neovim.sh" 2>&1
}

if ! command -v zsh >/dev/null 2>&1; then
    skip "Arch 50-neovim 的執行期行為" "找不到 zsh"
elif [ ! -s "$_ar/50-neovim.sh" ]; then
    _fail "Arch 50-neovim 在 arch 上渲染成非空（S5）" "渲染結果是空的，沒有東西可以執行"
else

# S8：omarchy（pacman 回報 omarchy-nvim 已裝）——什麼都不動。
_h="$_ar/home-omarchy"
_seed_nvim "$_h/.config/nvim" "$_h/.local/share/nvim" "$_h/.local/state/nvim" "$_h/.cache/nvim"
printf 'OMARCHY-INIT\n' > "$_h/.config/nvim/init.lua"
if _out=$(_run_arch "$_h" 1); then _pass "Arch/omarchy 50-neovim 執行成功（exit 0）"
else _fail "Arch/omarchy 50-neovim 執行成功（exit 0）" "$_out"; fi
assert_eq "omarchy: pacman -Q omarchy-nvim 真的被問過" "-Q omarchy-nvim" "$(cat "$_h/pacman-calls.log" 2>&1)"
for _d in .config/nvim .local/share/nvim .local/state/nvim .cache/nvim; do
    assert_eq "omarchy: $_d 原地未動（S8）" "USER-CONTENT" "$(cat "$_h/$_d/user-marker.txt" 2>&1)"
    assert_eq "omarchy: 沒有產生 $_d.bak（S8）" "0" \
        "$(ls -d "$_h/$_d".bak* 2>/dev/null | wc -l | tr -d ' ')"
done
assert_eq "omarchy: init.lua 仍是 omarchy 的（沒有 clone starter）" "OMARCHY-INIT" "$(cat "$_h/.config/nvim/init.lua" 2>&1)"
assert_eq "omarchy: 沒有寫 marker" "absent" \
    "$([ -e "$_h/.config/nvim/.chezmoi-lazyvim-starter" ] && echo present || echo absent)"
assert_eq "omarchy: 沒有呼叫 mise" "absent" "$([ -e "$_ar/mise-calls.log" ] && echo present || echo absent)"

# S9：純 Arch（pacman 回報未裝）——與 Debian 相同的備份 + clone + marker，且重跑不再搬。
_h="$_ar/home-arch"
_seed_nvim "$_h/.config/nvim" "$_h/.local/share/nvim" "$_h/.local/state/nvim" "$_h/.cache/nvim"
if _out=$(_run_arch "$_h" 0); then _pass "純 Arch 50-neovim 第一次執行成功"
else _fail "純 Arch 50-neovim 第一次執行成功" "$_out"; fi
_assert_backup "純 Arch: 既有 ~/.config/nvim 被備份而非刪除（S9）" "$_h/.config/nvim"
_assert_backup "純 Arch: 既有 ~/.local/share/nvim 被備份" "$_h/.local/share/nvim"
_assert_backup "純 Arch: 既有 ~/.local/state/nvim 被備份" "$_h/.local/state/nvim"
_assert_backup "純 Arch: 既有 ~/.cache/nvim 被備份" "$_h/.cache/nvim"
assert_eq "純 Arch: starter 已放進 ~/.config/nvim" "starter" "$(cat "$_h/.config/nvim/init.lua" 2>&1)"
assert_eq "純 Arch: starter 的 .git 已刪除" "absent" \
    "$([ -e "$_h/.config/nvim/.git" ] && echo present || echo absent)"
assert_eq "純 Arch: marker 已建立" "present" \
    "$([ -f "$_h/.config/nvim/.chezmoi-lazyvim-starter" ] && echo present || echo absent)"
printf 'MY-OWN-EDIT\n' > "$_h/.config/nvim/init.lua"
if _out=$(_run_arch "$_h" 0); then _pass "純 Arch 50-neovim 第二次執行成功"
else _fail "純 Arch 50-neovim 第二次執行成功" "$_out"; fi
assert_eq "純 Arch: 重跑不會動使用者自己的設定（M4）" "MY-OWN-EDIT" "$(cat "$_h/.config/nvim/init.lua" 2>&1)"
assert_eq "純 Arch: 重跑不會多生一份備份（M4）" "1" \
    "$(ls -d "$_h"/.config/nvim.bak* 2>/dev/null | wc -l | tr -d ' ')"
assert_eq "純 Arch: 沒有呼叫 mise" "absent" "$([ -e "$_ar/mise-calls.log" ] && echo present || echo absent)"

fi
unset _ar _h _d

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
    # 跟 POSIX 那半一樣留下記號。隔離目前是靠 %LOCALAPPDATA%/%ProgramFiles% 被
    # 重導向而成立；沒有這個正面控制的話，哪天重導向失效，Windows 這半會安靜地
    # 開始驅動主機上的真工具 —— 而這一層正是不得碰真實主機。
    printf '@echo off\r\necho %%* >> "%s\\mise-calls.log"\r\nexit /b 0\r\n' "$_bn" > "$_bw/stub/mise.cmd"
    printf '@echo off\r\nif "%%1"=="clone" (\r\n  mkdir "%%~5" 2>nul\r\n  mkdir "%%~5\\.git" 2>nul\r\n  echo starter> "%%~5\\init.lua"\r\n)\r\nexit /b 0\r\n' > "$_bw/stub/git.cmd"
    render_file windows .chezmoiscripts/run_before_50-neovim.ps1.tmpl > "$_bw/50-neovim.ps1"

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

    # 第四次：與 POSIX 那半對稱地釘住撞名時的 accepted risk 行為。兩邊的備份命名
    # 形狀必須一致，否則同一條規則在兩個平台上代表不同的事。
    rm -f "$_bw/local/nvim/.chezmoi-lazyvim-starter"
    printf 'GEN4\n' > "$_bw/local/nvim/gen-marker.txt"
    # 撞名不靠牆上的時鐘：pwsh.exe 經 WSL interop 啟動的時間不可預測（6 秒的視窗
    # 在連跑兩次 suite 時撞不到，30 秒的視窗在使用者同時跑 L9 時也撞不到）。
    # 改成在 wrapper 裡用同名 function 蓋掉 Get-Date（function 優先於 cmdlet，子 scope
    # 看得到），腳本算出的時間戳固定為 20000101000000，測試只種這一個目錄。
    mkdir -p "$_bw/local/nvim.bak.20000101000000"
    { printf 'function Get-Date { param([string] $Format) "20000101000000" }\n'; cat "$_bw/run.ps1"; } > "$_bw/run4.ps1"
    if _out=$("$_PWSH" -NoLogo -NoProfile -File "$_bn\\run4.ps1" 2>&1); then
        _pass "Windows 50-neovim 第四次執行成功"
    else _fail "Windows 50-neovim 第四次執行成功" "$(printf '%s' "$_out" | tr -d '\r')"; fi
    assert_eq "Windows: 撞名時來源被搬進既有備份裡（accepted risk，位置變深一層）" "1" \
        "$(find "$_bw/local" -mindepth 2 -maxdepth 2 -name nvim -type d 2>/dev/null | wc -l | tr -d ' ')"
    assert_eq "Windows: 即使撞名，使用者的內容仍然存在、沒有被刪" "GEN4" \
        "$(cat "$_bw"/local/nvim.bak.*/nvim/gen-marker.txt 2>&1 | tr -d '\r')"
    assert_eq "Windows: 沒有產生序號備份（與 POSIX 對稱）" "0" \
        "$(ls -d "$_bw"/local/nvim.bak.*.[0-9]* 2>/dev/null | wc -l | tr -d ' ')"

    assert_eq "Windows: 跑到的是 stub 的 mise 而不是主機上的 mise（隔離生效）" "4" \
        "$(wc -l < "$_bw/mise-calls.log" 2>/dev/null | tr -d ' ')"

    # ---- mise 不存在時的行為：必須「跳過」，不是「中止整個 apply」 ----
    # POSIX 版是 `echo ... >&2; exit 0`。Windows 版原本寫 Write-Error，而在
    # $ErrorActionPreference = 'Stop' 之下 Write-Error 是**終止性**的 ——
    # 後面那行 exit 0 根本到不了，chezmoi 收到的是 1。這支是 run_before_，
    # 非零退出會在**任何檔案被寫出來之前**中止整個 apply：使用者連 PowerShell
    # profile 與 settings.json 都拿不到。比它想做的「跳過 neovim」嚴重得多。
    _nomise="$_bw/nomise"
    mkdir -p "$_nomise/local" "$_nomise/temp" "$_nomise/pf" "$_nomise/stub"
    cat > "$_bw/run-nomise.ps1" <<NOMISEEOF
\$env:LOCALAPPDATA = '$_bn\\nomise\\local'
\$env:TEMP = '$_bn\\nomise\\temp'
\$env:TMP  = '$_bn\\nomise\\temp'
\$env:ProgramFiles = '$_bn\\nomise\\pf'
\$env:PATH = '$_bn\\nomise\\stub'
\$p = Start-Process -FilePath 'pwsh' -NoNewWindow -Wait -PassThru -ArgumentList @('-NoLogo','-File','$_bn\\50-neovim.ps1')
'EXITCODE=' + \$p.ExitCode
NOMISEEOF
    _nm=$("$_PWSH" -NoLogo -NoProfile -File "$_bn\\run-nomise.ps1" 2>&1 | tr -d '\r' | sed -n 's/^EXITCODE=//p')
    assert_eq "Windows: mise 不存在時退出碼是 0（跳過，不是中止整個 apply）" "0" "$_nm"
    assert_eq "Windows: mise 不存在時什麼都不建立" "" \
        "$(ls -A "$_nomise/local" 2>/dev/null)"

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

unset _a _out _dir _i _PWSH _WT _WU _id _bw _bn _loader _prof _i

# ================= D. WSL 的 05-wsl-user-runtime-dir =================
# 這支腳本的副作用是 `sudo loginctl enable-linger`，動的是主機的 logind 狀態，
# 所以 loginctl 與 sudo 都用 stub 換掉，只看它「在什麼狀態下呼叫了什麼」。
# `id` 與 /run/systemd/system 用真的：前者無害，後者在這台主機上本來就存在。
_d="$TMP/l7d"
rm -rf "$_d"; mkdir -p "$_d/stub"
render_file native-wsl .chezmoiscripts/run_onchange_before_05-wsl-user-runtime-dir.sh.tmpl > "$_d/05.sh"
# loginctl stub：show-user 的答案由 STUB_LINGER 決定（yes / no / absent＝logind 不認識這個使用者）
cat > "$_d/stub/loginctl" <<'STUB'
#!/bin/sh
echo "$@" >> "$STUB_LOG/loginctl.log"
case "$1:${STUB_LINGER:-absent}" in
    show-user:yes)    echo yes ;;
    show-user:no)     echo no ;;
    show-user:absent) echo "Failed to get user: User ID 1000 is not logged in or lingering" >&2; exit 1 ;;
esac
exit 0
STUB
cat > "$_d/stub/sudo" <<'STUB'
#!/bin/sh
echo "$@" >> "$STUB_LOG/sudo.log"
[ "$1" = "-v" ] && [ "${STUB_SUDO_FAIL:-0}" = 1 ] && exit 1
exit 0
STUB
chmod +x "$_d/stub/"*

_run_d() { # linger-state sudo-fail
    _log="$_d/log-$1-$2"; rm -rf "$_log"; mkdir -p "$_log"
    STUB_LOG="$_log" STUB_LINGER="$1" STUB_SUDO_FAIL="$2" PATH="$_d/stub:$PATH" sh "$_d/05.sh" 2>&1
}

if [ -d /run/systemd/system ]; then
    # 已經 linger：什麼都不做，尤其不能碰 sudo（每次 apply 都要密碼是不可接受的）。
    if _out=$(_run_d yes 0); then _pass "WSL linger 已開啟時腳本成功結束"
    else _fail "WSL linger 已開啟時腳本成功結束" "$_out"; fi
    assert_eq "WSL linger 已開啟時不呼叫 sudo" "absent" \
        "$([ -e "$_d/log-yes-0/sudo.log" ] && echo present || echo absent)"

    # logind 根本不認識這個使用者（沒有 session 也沒有 linger）＝這台機器實際的狀態：
    # 要走 sudo -v 再 enable-linger，而且對象是目前的使用者。
    if _out=$(_run_d absent 0); then _pass "WSL 無 linger 時腳本成功結束"
    else _fail "WSL 無 linger 時腳本成功結束" "$_out"; fi
    assert_eq "WSL 無 linger 時先 sudo -v 再 enable-linger 目前使用者" \
        "-v
loginctl enable-linger $(id -un)" "$(cat "$_d/log-absent-0/sudo.log" 2>&1)"
    assert_eq "WSL Linger=no 時同樣 enable-linger" "1" \
        "$(_run_d no 0 >/dev/null; grep -c 'enable-linger' "$_d/log-no-0/sudo.log" 2>/dev/null | tr -d ' ')"

    # sudo 拿不到密碼：要失敗（非零）、要說出該手動跑的指令、不能繼續呼叫 enable-linger。
    if _out=$(_run_d absent 1); then _fail "WSL sudo 認證失敗時腳本以非零結束" "$_out"
    else _pass "WSL sudo 認證失敗時腳本以非零結束"; fi
    assert_contains "WSL sudo 認證失敗時印出手動指令" "$_out" "sudo loginctl enable-linger $(id -un)"
    assert_eq "WSL sudo 認證失敗時不再呼叫 enable-linger" "1" \
        "$(wc -l < "$_d/log-absent-1/sudo.log" | tr -d ' ')"
else
    skip "WSL 05-wsl-user-runtime-dir 的行為" "這台主機不是 systemd 開機，腳本會在第一行退出"
fi

# 沒有 systemd 的 WSL（wsl.conf 沒開 systemd）：logind 不存在，腳本必須安靜退出，
# 連 loginctl 都不能碰。用 mount namespace 把 /run/systemd 蓋掉來模擬。
if [ "$_HAVE_NS" = 1 ] && [ -d /run/systemd ]; then
    mkdir -p "$_d/emptyrun" "$_d/log-nosystemd"
    cat > "$_d/run-nosystemd.sh" <<RUNEOF
#!/bin/sh
mount --bind "$_d/emptyrun" /run/systemd
export STUB_LOG="$_d/log-nosystemd" PATH="$_d/stub:\$PATH"
exec sh "$_d/05.sh"
RUNEOF
    chmod +x "$_d/run-nosystemd.sh"
    if _out=$(unshare --map-root-user --mount "$_d/run-nosystemd.sh" 2>&1); then
        _pass "沒有 systemd 時腳本安靜退出"
    else _fail "沒有 systemd 時腳本安靜退出" "$_out"; fi
    assert_eq "沒有 systemd 時不呼叫 loginctl" "absent" \
        "$([ -e "$_d/log-nosystemd/loginctl.log" ] && echo present || echo absent)"
else
    skip "沒有 systemd 時 05-wsl-user-runtime-dir 安靜退出" "需要 user namespace 才能蓋掉 /run/systemd"
fi
unset _d _out _log

# ================= E. 55-cc-statusline =================
# mise 用 stub：`use` 只記錄，`where` 回答一個測試目錄，裡面放假的 binary。
# 重點是「Claude Code 正在執行目標 binary 時仍能替換」：先用控制組證明直接寫入
# 會失敗，再看腳本能不能換掉它。
_e="$TMP/l7e"
rm -rf "$_e"; mkdir -p "$_e/stub" "$_e/mise-dir" "$_e/empty" "$_e/nomise"
_cc_tool="github:gn00678465/StatusLine@$(sed -n 's/^ccStatusline = "\(.*\)"$/\1/p' "$REPO/.chezmoitemplates/versions.toml")"
cat > "$_e/stub/mise" <<'STUB'
#!/bin/sh
echo "$@" >> "$STUB_LOG"
[ "$1" = "where" ] && echo "$STUB_MISE_DIR"
exit 0
STUB
chmod +x "$_e/stub/mise"
# 用 arch 的渲染：它與 linux 只差 brew shellenv 那一行，而那一行會把真實 brew 的
# mise 放到 stub 前面（見 A 段）。複製與替換的部分兩者相同。
render_file arch .chezmoiscripts/run_after_55-cc-statusline.sh.tmpl > "$_e/55.sh"

_run_e() { # home mise-dir
    HOME="$1" STUB_LOG="$_e/mise-calls.log" STUB_MISE_DIR="$2" PATH="$_e/stub:$PATH" \
        zsh "$_e/55.sh" 2>&1
}
_ebin="$_e/home/.claude/cc-statusline/cc-statusline"

if ! command -v zsh >/dev/null 2>&1; then
    skip "POSIX 55-cc-statusline 的行為" "找不到 zsh"
else

printf 'V1\n' > "$_e/mise-dir/cc-statusline"
if _out=$(_run_e "$_e/home" "$_e/mise-dir"); then _pass "POSIX 55-cc-statusline 第一次執行成功"
else _fail "POSIX 55-cc-statusline 第一次執行成功" "$_out"; fi
assert_eq "POSIX 55-cc-statusline: 目標內容是 mise 裝的那一份" "V1" "$(cat "$_ebin" 2>&1)"
assert_eq "POSIX 55-cc-statusline: 目標可執行" "yes" "$([ -x "$_ebin" ] && echo yes || echo no)"
assert_eq "POSIX 55-cc-statusline: 目錄裡沒有留下暫存檔" "cc-statusline" \
    "$(ls -A "$(dirname "$_ebin")" 2>&1)"
assert_contains "POSIX 55-cc-statusline: mise use --global 釘 versions.toml 的版本" \
    "$(cat "$_e/mise-calls.log" 2>&1)" "use --global $_cc_tool"

# 內容相同時不替換：inode 不變。
_ino=$(ls -i "$_ebin" | awk '{print $1}')
if _out=$(_run_e "$_e/home" "$_e/mise-dir"); then _pass "POSIX 55-cc-statusline 第二次執行成功"
else _fail "POSIX 55-cc-statusline 第二次執行成功" "$_out"; fi
assert_eq "POSIX 55-cc-statusline: 內容相同時不替換" "$_ino" "$(ls -i "$_ebin" | awk '{print $1}')"

# 目標正在執行：換上一份 zsh，讓它阻塞在 fifo 上。不用 sleep：coreutils 的
# 多功能 binary 依 argv[0] 分派，改名後不會執行。
cp "$(command -v zsh)" "$_ebin"
chmod 755 "$_ebin"
mkfifo "$_e/fifo"
"$_ebin" -fc "read x < '$_e/fifo'" &
_epid=$!
_i=0
while [ "$(readlink "/proc/$_epid/exe" 2>/dev/null)" != "$_ebin" ] && [ "$_i" -lt 50 ]; do
    sleep 0.1; _i=$((_i + 1))
done
printf 'V2\n' > "$_e/mise-dir/cc-statusline"
if [ "$(readlink "/proc/$_epid/exe" 2>/dev/null)" != "$_ebin" ]; then
    _fail "POSIX 55-cc-statusline: 替換測試的目標行程在執行" "$(readlink "/proc/$_epid/exe" 2>&1)"
elif cp "$_e/mise-dir/cc-statusline" "$_ebin" 2>/dev/null; then
    skip "POSIX 55-cc-statusline 替換執行中的 binary" "控制組：直接寫入沒有 ETXTBSY，這個檔案系統測不到"
else
    _pass "控制組：直接寫入執行中的 binary 會失敗（ETXTBSY）"
    if _out=$(_run_e "$_e/home" "$_e/mise-dir"); then _pass "POSIX 55-cc-statusline 在目標執行中時成功"
    else _fail "POSIX 55-cc-statusline 在目標執行中時成功" "$_out"; fi
    assert_eq "POSIX 55-cc-statusline: 執行中的目標被換成新版" "V2" "$(cat "$_ebin" 2>&1)"
fi
kill "$_epid" 2>/dev/null || true
wait "$_epid" 2>/dev/null || true

# mise where 的目錄裡沒有 binary：要失敗，不能留下空的目標。
if _out=$(_run_e "$_e/home-empty" "$_e/empty"); then
    _fail "POSIX 55-cc-statusline: mise 目錄沒有 binary 時以非零結束" "$_out"
else _pass "POSIX 55-cc-statusline: mise 目錄沒有 binary 時以非零結束"; fi
assert_eq "POSIX 55-cc-statusline: mise 目錄沒有 binary 時不建立目標" "absent" \
    "$([ -e "$_e/home-empty/.claude/cc-statusline/cc-statusline" ] && echo present || echo absent)"

# 沒有 mise：跳過（exit 0），不中止整個 apply。
if _out=$(HOME="$_e/home-nomise" PATH="$_e/nomise" "$(command -v zsh)" "$_e/55.sh" 2>&1); then
    _pass "POSIX 55-cc-statusline: mise 不存在時退出碼是 0"
else _fail "POSIX 55-cc-statusline: mise 不存在時退出碼是 0" "$_out"; fi
assert_eq "POSIX 55-cc-statusline: mise 不存在時什麼都不建立" "absent" \
    "$([ -e "$_e/home-nomise" ] && echo present || echo absent)"

fi

# ---- Windows ----
_PWSH=$(command -v pwsh.exe 2>/dev/null || true)
_WT=""
if [ -n "$_PWSH" ]; then
    _WT=$("$_PWSH" -NoProfile -NonInteractive -Command '$env:TEMP' 2>/dev/null | tr -d '\r')
    _WU=$(wslpath -u "$_WT" 2>/dev/null || echo "")
    [ -n "$_WU" ] || _PWSH=""
fi

if [ -z "$_PWSH" ]; then
    skip "Windows 55-cc-statusline 的行為" "找不到可用的 pwsh.exe"
else
    _id="l7e-$$"
    _ew="$_WU/$_id"; _en="$_WT\\$_id"
    rm -rf "$_ew"; mkdir -p "$_ew/local" "$_ew/pf" "$_ew/stub" "$_ew/mise-dir" "$_ew/nomise"
    printf '@echo off\r\necho %%* >> "%s\\mise-calls.log"\r\nif "%%1"=="where" echo %s\\mise-dir\r\nexit /b 0\r\n' \
        "$_en" "$_en" > "$_ew/stub/mise.cmd"
    render_file windows .chezmoiscripts/run_after_55-cc-statusline.ps1.tmpl > "$_ew/55.ps1"
    # $HOME 在 pwsh 啟動時由 USERPROFILE 決定，所以腳本要在設好環境的子 pwsh 裡跑。
    # 參數：USERPROFILE、放在 PATH 最前面的 stub 目錄；-OnlyStub 時 PATH 只剩 stub，
    # 主機 PATH 上真的 mise 就不會被找到。
    cat > "$_ew/run.ps1" <<PSEOF
param([string] \$UserProfile, [string] \$Stub, [switch] \$OnlyStub)
\$pwsh = (Get-Command pwsh).Source
\$env:LOCALAPPDATA = '$_en\\local'
\$env:ProgramFiles = '$_en\\pf'
\$env:USERPROFILE = \$UserProfile
\$env:PATH = \$OnlyStub ? \$Stub : (\$Stub + ';' + \$env:PATH)
& \$pwsh -NoLogo -NoProfile -File '$_en\\55.ps1'
exit \$LASTEXITCODE
PSEOF
    _edir="$_ew/home/.claude/cc-statusline"

    printf 'V1\n' > "$_ew/mise-dir/cc-statusline.exe"
    if _out=$("$_PWSH" -NoLogo -NoProfile -File "$_en\\run.ps1" "$_en\\home" "$_en\\stub" 2>&1); then
        _pass "Windows 55-cc-statusline 第一次執行成功"
    else _fail "Windows 55-cc-statusline 第一次執行成功" "$(printf '%s' "$_out" | tr -d '\r')"; fi
    assert_eq "Windows 55-cc-statusline: 目標內容是 mise 裝的那一份" "V1" \
        "$(cat "$_edir/cc-statusline.exe" 2>&1)"
    assert_eq "Windows 55-cc-statusline: 目錄裡沒有留下暫存檔" "cc-statusline.exe" \
        "$(ls -A "$_edir" 2>&1)"
    assert_contains "Windows 55-cc-statusline: mise use --global 釘 versions.toml 的版本" \
        "$(tr -d '\r' < "$_ew/mise-calls.log" 2>&1)" "use --global $_cc_tool"

    # 內容相同時不替換：Copy-Item 保留來源的修改時間，所以看有沒有換下來的 .old-*。
    if _out=$("$_PWSH" -NoLogo -NoProfile -File "$_en\\run.ps1" "$_en\\home" "$_en\\stub" 2>&1); then
        _pass "Windows 55-cc-statusline 第二次執行成功"
    else _fail "Windows 55-cc-statusline 第二次執行成功" "$(printf '%s' "$_out" | tr -d '\r')"; fi
    assert_eq "Windows 55-cc-statusline: 內容相同時不替換" "cc-statusline.exe" "$(ls -A "$_edir" 2>&1)"

    # 目標正在執行：換上一份 PING.EXE 讓它跑著，同一個 wrapper 裡先做控制組再跑腳本。
    printf 'V2\n' > "$_ew/mise-dir/cc-statusline.exe"
    cat > "$_ew/run-busy.ps1" <<PSEOF
\$exe = '$_en\\home\\.claude\\cc-statusline\\cc-statusline.exe'
Copy-Item "\$env:SystemRoot\\System32\\PING.EXE" \$exe -Force
\$p = Start-Process -FilePath \$exe -ArgumentList '-n','30','127.0.0.1' -WindowStyle Hidden -PassThru
Start-Sleep -Milliseconds 500
'STARTED=' + (-not \$p.HasExited)
try { Copy-Item '$_en\\mise-dir\\cc-statusline.exe' \$exe -Force -ErrorAction Stop; 'CONTROL=written' }
catch { 'CONTROL=busy' }
& '$_en\\run.ps1' '$_en\\home' '$_en\\stub'
'EXITCODE=' + \$LASTEXITCODE
'RUNNING=' + (-not \$p.HasExited)
Stop-Process \$p -ErrorAction SilentlyContinue
\$p.WaitForExit()
PSEOF
    _out=$("$_PWSH" -NoLogo -NoProfile -File "$_en\\run-busy.ps1" 2>&1 | tr -d '\r')
    if [ "$(printf '%s\n' "$_out" | sed -n 's/^STARTED=//p')" != True ]; then
        _fail "Windows 55-cc-statusline: 替換測試的目標行程在執行" "$_out"
    elif [ "$(printf '%s\n' "$_out" | sed -n 's/^CONTROL=//p')" != busy ]; then
        skip "Windows 55-cc-statusline 替換執行中的 exe" "控制組：直接寫入執行中的 exe 沒有失敗（$_out）"
    else
        _pass "控制組：直接寫入執行中的 exe 會失敗"
        assert_eq "Windows 55-cc-statusline: 替換時目標仍在執行" "True" \
            "$(printf '%s\n' "$_out" | sed -n 's/^RUNNING=//p')"
        assert_eq "Windows 55-cc-statusline 在目標執行中時成功" "0" \
            "$(printf '%s\n' "$_out" | sed -n 's/^EXITCODE=//p')"
        assert_eq "Windows 55-cc-statusline: 執行中的目標被換成新版" "V2" \
            "$(cat "$_edir/cc-statusline.exe" 2>&1)"
        assert_eq "Windows 55-cc-statusline: 換下來的舊檔改名為 .old-*" "1" \
            "$(ls -d "$_edir"/cc-statusline.exe.old-* 2>/dev/null | wc -l | tr -d ' ')"
        # 舊檔的行程已結束，下一次執行要把它刪掉。
        if _out=$("$_PWSH" -NoLogo -NoProfile -File "$_en\\run.ps1" "$_en\\home" "$_en\\stub" 2>&1); then
            _pass "Windows 55-cc-statusline 替換後再執行成功"
        else _fail "Windows 55-cc-statusline 替換後再執行成功" "$(printf '%s' "$_out" | tr -d '\r')"; fi
        assert_eq "Windows 55-cc-statusline: 下一次執行刪掉 .old-*" "cc-statusline.exe" "$(ls -A "$_edir" 2>&1)"
    fi

    # 沒有 mise：跳過（exit 0），不中止整個 apply。
    if _out=$("$_PWSH" -NoLogo -NoProfile -File "$_en\\run.ps1" "$_en\\home-nomise" "$_en\\nomise" -OnlyStub 2>&1); then
        _pass "Windows 55-cc-statusline: mise 不存在時退出碼是 0"
    else _fail "Windows 55-cc-statusline: mise 不存在時退出碼是 0" "$(printf '%s' "$_out" | tr -d '\r')"; fi
    # 只看 .claude：子 pwsh 自己會在 USERPROFILE 底下寫 AppData\Local\Microsoft\PowerShell。
    assert_eq "Windows 55-cc-statusline: mise 不存在時不建立 ~/.claude" "absent" \
        "$([ -e "$_ew/home-nomise/.claude" ] && echo present || echo absent)"

    rm -rf "$_ew"
fi
unset _e _ebin _epid _ino _i _out _cc_tool _PWSH _WT _WU _id _ew _en _edir

# ================= F. 90-neovim-update-check =================
# git 與通知器都是 stub：git 依 STUB_TAGS 吐 ls-remote 的輸出（STUB_GIT_FAIL 時失敗），
# 通知器把收到的參數記下來（STUB_NOTIFY_FAIL 時失敗）。要釘的是噪音上限：網路查詢
# 一天一次、通知每個上游版本一次、任何失敗都 exit 0。
_f="$TMP/l7f"
rm -rf "$_f"; mkdir -p "$_f/stub"
_f_pin=$(sed -n 's/^neovim = "\(.*\)"$/\1/p' "$REPO/.chezmoitemplates/versions.toml")
cat > "$_f/stub/git" <<'STUB'
#!/bin/sh
echo "$@" >> "$STUB_GIT_LOG"
[ -n "${STUB_GIT_FAIL:-}" ] && exit 128
for t in $STUB_TAGS; do printf '0000\trefs/tags/%s\n' "$t"; done
STUB
cat > "$_f/stub/notify-send" <<'STUB'
#!/bin/sh
[ -n "${STUB_NOTIFY_FAIL:-}" ] && exit 1
echo "$@" >> "$STUB_NOTIFY_LOG"
STUB
cp "$_f/stub/notify-send" "$_f/stub/osascript"
# WSL：把 -EncodedCommand 解回來存檔，順便證明它是合法的 UTF-16LE base64。
cat > "$_f/stub/powershell.exe" <<'STUB'
#!/bin/sh
[ -n "${STUB_NOTIFY_FAIL:-}" ] && exit 1
[ "$3" = "-EncodedCommand" ] || exit 2
printf '%s' "$4" | base64 -d | iconv -f UTF-16LE -t UTF-8 > "$STUB_NOTIFY_LOG.payload" || exit 3
echo "$*" >> "$STUB_NOTIFY_LOG"
STUB
chmod +x "$_f/stub/"*
render_file linux .chezmoiscripts/run_after_90-neovim-update-check.sh.tmpl > "$_f/linux.sh"
render_file darwin-arm64 .chezmoiscripts/run_after_90-neovim-update-check.sh.tmpl > "$_f/darwin.sh"
render_file native-wsl .chezmoiscripts/run_after_90-neovim-update-check.sh.tmpl > "$_f/wsl.sh"

_run_f() { # script home tags [VAR=value...]
    _fs=$1; _fh=$2; _ft=$3; shift 3
    env HOME="$_fh" XDG_STATE_HOME= STUB_TAGS="$_ft" STUB_GIT_LOG="$_fh/git.log" \
        STUB_NOTIFY_LOG="$_fh/notify.log" PATH="$_f/stub:$PATH" "$@" zsh "$_fs" 2>&1
}
_lines() { if [ -f "$1" ]; then wc -l < "$1" | tr -d ' '; else echo 0; fi; }
_fstate() { cat "$1/.local/state/chezmoi-neovim-check/$2" 2>/dev/null || echo absent; }

if ! command -v zsh >/dev/null 2>&1; then
    skip "POSIX 90-neovim-update-check 的行為" "找不到 zsh"
else

# 上游比 pin 新：印一行、跳一次通知、兩個狀態檔都記下最新版。順便釘數字排序：
# 0.12.10 必須勝過 0.12.9，nightly/stable/rc 不算版本。
_h="$_f/home-new"
_tags="v0.11.7 v99.12.9 v99.12.10 nightly stable v99.13.0-rc1"
if _out=$(_run_f "$_f/linux.sh" "$_h" "$_tags"); then _pass "90-neovim-update-check: 有新版時 exit 0"
else _fail "90-neovim-update-check: 有新版時 exit 0" "$_out"; fi
assert_contains "90-neovim-update-check: apply 輸出提到新版與 pin" "$_out" \
    "neovim 99.12.10 is available (pinned $_f_pin in .chezmoitemplates/versions.toml)"
assert_eq "90-neovim-update-check: 跳了一次通知" "1" "$(_lines "$_h/notify.log")"
assert_contains "90-neovim-update-check: 通知內容有新版與 pin" "$(cat "$_h/notify.log" 2>&1)" \
    "neovim 99.12.10 is out; dotfiles pin $_f_pin"
assert_eq "90-neovim-update-check: 快取記下最新版（數字排序，0.12.10 > 0.12.9）" "99.12.10" "$(_fstate "$_h" latest)"
assert_eq "90-neovim-update-check: notified 記下最新版" "99.12.10" "$(_fstate "$_h" notified)"

# 同一天再 apply：不連網路、不再跳通知，但輸出那一行還在。
_out=$(_run_f "$_f/linux.sh" "$_h" "$_tags")
assert_eq "90-neovim-update-check: 24 小時內不再查詢網路" "1" "$(_lines "$_h/git.log")"
assert_eq "90-neovim-update-check: 同一個版本不再跳通知" "1" "$(_lines "$_h/notify.log")"
assert_contains "90-neovim-update-check: 同一個版本仍在輸出裡提醒" "$_out" "neovim 99.12.10 is available"

# 快取過期且上游又出了新版：再查一次、再跳一次。
touch -t 200001010000 "$_h/.local/state/chezmoi-neovim-check/latest"
_run_f "$_f/linux.sh" "$_h" "$_tags v99.14.0" >/dev/null
assert_eq "90-neovim-update-check: 快取過期後重新查詢" "2" "$(_lines "$_h/git.log")"
assert_eq "90-neovim-update-check: 新的上游版本再跳一次通知" "2" "$(_lines "$_h/notify.log")"
assert_eq "90-neovim-update-check: notified 換成新的上游版本" "99.14.0" "$(_fstate "$_h" notified)"

# 已是最新：什麼都不印、不通知。
_h="$_f/home-current"
_out=$(_run_f "$_f/linux.sh" "$_h" "v$_f_pin v0.11.7")
assert_eq "90-neovim-update-check: pin 就是最新版時沒有輸出" "" "$_out"
assert_eq "90-neovim-update-check: pin 就是最新版時不通知" "0" "$(_lines "$_h/notify.log")"

# 網路不通：exit 0、沒有輸出、不寫快取。
_h="$_f/home-offline"
if _out=$(_run_f "$_f/linux.sh" "$_h" "v99.0.0" STUB_GIT_FAIL=1); then
    _pass "90-neovim-update-check: 網路不通時 exit 0"
else _fail "90-neovim-update-check: 網路不通時 exit 0" "$_out"; fi
assert_eq "90-neovim-update-check: 網路不通時沒有輸出" "" "$_out"
assert_eq "90-neovim-update-check: 網路不通時不寫快取" "absent" "$(_fstate "$_h" latest)"

# 通知器失敗（ssh、沒有 session bus）：exit 0，而且不記 notified，下一次 apply 再試。
_h="$_f/home-headless"
if _out=$(_run_f "$_f/linux.sh" "$_h" "v99.0.0" STUB_NOTIFY_FAIL=1); then
    _pass "90-neovim-update-check: 通知失敗時 exit 0"
else _fail "90-neovim-update-check: 通知失敗時 exit 0" "$_out"; fi
assert_eq "90-neovim-update-check: 通知失敗時不記 notified" "absent" "$(_fstate "$_h" notified)"
_run_f "$_f/linux.sh" "$_h" "v99.0.0" >/dev/null
assert_eq "90-neovim-update-check: 通知恢復後補跳一次" "1" "$(_lines "$_h/notify.log")"

# 快取被改成奇怪的東西：不可以進到通知的指令列。
_h="$_f/home-tampered"
mkdir -p "$_h/.local/state/chezmoi-neovim-check"
printf '99.0.0"; touch %s/pwned; "\n' "$_h" > "$_h/.local/state/chezmoi-neovim-check/latest"
_out=$(_run_f "$_f/linux.sh" "$_h" "" STUB_GIT_FAIL=1)
assert_eq "90-neovim-update-check: 不合格的快取內容被忽略" "" "$_out"
assert_eq "90-neovim-update-check: 不合格的快取內容沒有被執行" "absent" \
    "$([ -e "$_h/pwned" ] && echo present || echo absent)"

# macOS 與 WSL 只有通知器不同。
_h="$_f/home-darwin"
_run_f "$_f/darwin.sh" "$_h" "v99.0.0" >/dev/null
assert_contains "macOS: 通知交給 osascript" "$(cat "$_h/notify.log" 2>&1)" \
    '-e display notification "neovim 99.0.0 is out'
_h="$_f/home-wsl"
if command -v iconv >/dev/null 2>&1 && command -v base64 >/dev/null 2>&1; then
    _run_f "$_f/wsl.sh" "$_h" "v99.0.0" >/dev/null
    assert_eq "WSL: 通知交給 powershell.exe 一次" "1" "$(_lines "$_h/notify.log")"
    assert_contains "WSL: 解碼後的 toast 腳本帶著標題與內容" "$(head -1 "$_h/notify.log.payload" 2>&1)" \
        "\$ToastTitle = 'Neovim update available'; \$ToastBody = 'neovim 99.0.0 is out; dotfiles pin $_f_pin"
    assert_eq "WSL: notified 記下版本" "99.0.0" "$(_fstate "$_h" notified)"
else
    skip "WSL 90-neovim-update-check 的 toast 編碼" "找不到 iconv 或 base64"
fi

fi

# ---- Windows ----
# 腳本本身沒有 Windows 專屬的路徑邏輯（狀態目錄來自 $env:LOCALAPPDATA），所以用
# Linux 的 pwsh 加上 stub 跑。pwsh.exe 那條路要把 git 與 powershell.exe 換成 .cmd
# stub，而 powershell.exe 是以檔名解析的，換不掉。只有 pwsh.exe 時跳過。
_FPWSH=$(command -v pwsh 2>/dev/null || true)
if [ -z "$_FPWSH" ]; then
    skip "Windows 90-neovim-update-check 的行為" "找不到 Linux 的 pwsh"
else
    render_file windows .chezmoiscripts/run_after_90-neovim-update-check.ps1.tmpl > "$_f/win.ps1"
    _run_fw() { # local tags [VAR=value...]
        _fl=$1; _ft=$2; shift 2
        mkdir -p "$_fl" "$_f/pf"
        env LOCALAPPDATA="$_fl" ProgramFiles="$_f/pf" STUB_TAGS="$_ft" STUB_GIT_LOG="$_fl/git.log" \
            STUB_NOTIFY_LOG="$_fl/notify.log" PATH="$_f/stub:$PATH" "$@" \
            "$_FPWSH" -NoLogo -NoProfile -File "$_f/win.ps1" 2>&1
    }
    _wstate() { cat "$1/chezmoi-neovim-check/$2" 2>/dev/null || echo absent; }

    _l="$_f/win-new"
    if _out=$(_run_fw "$_l" "v0.11.7 v99.12.9 v99.12.10 nightly"); then _pass "Windows 90-neovim-update-check: 有新版時 exit 0"
    else _fail "Windows 90-neovim-update-check: 有新版時 exit 0" "$_out"; fi
    assert_contains "Windows 90-neovim-update-check: apply 輸出提到新版與 pin" "$_out" \
        "neovim 99.12.10 is available (pinned $_f_pin"
    assert_eq "Windows 90-neovim-update-check: 跳了一次通知" "1" "$(_lines "$_l/notify.log")"
    assert_contains "Windows 90-neovim-update-check: toast 腳本帶著標題與內容" \
        "$(head -1 "$_l/notify.log.payload" 2>&1)" "\$ToastBody = 'neovim 99.12.10 is out; dotfiles pin $_f_pin"
    assert_eq "Windows 90-neovim-update-check: 快取記下最新版（[version] 排序）" "99.12.10" "$(_wstate "$_l" latest)"
    _run_fw "$_l" "v99.12.10" >/dev/null
    assert_eq "Windows 90-neovim-update-check: 24 小時內不再查詢網路" "1" "$(_lines "$_l/git.log")"
    assert_eq "Windows 90-neovim-update-check: 同一個版本不再跳通知" "1" "$(_lines "$_l/notify.log")"

    _l="$_f/win-current"
    _out=$(_run_fw "$_l" "v$_f_pin")
    assert_eq "Windows 90-neovim-update-check: pin 就是最新版時沒有輸出" "" "$_out"

    _l="$_f/win-offline"
    if _out=$(_run_fw "$_l" "v99.0.0" STUB_GIT_FAIL=1); then
        _pass "Windows 90-neovim-update-check: 網路不通時 exit 0"
    else _fail "Windows 90-neovim-update-check: 網路不通時 exit 0" "$_out"; fi
    assert_eq "Windows 90-neovim-update-check: 網路不通時沒有輸出" "" "$_out"

    _l="$_f/win-headless"
    if _out=$(_run_fw "$_l" "v99.0.0" STUB_NOTIFY_FAIL=1); then
        _pass "Windows 90-neovim-update-check: 通知失敗時 exit 0"
    else _fail "Windows 90-neovim-update-check: 通知失敗時 exit 0" "$_out"; fi
    assert_eq "Windows 90-neovim-update-check: 通知失敗時不記 notified" "absent" "$(_wstate "$_l" notified)"
fi
unset _f _f_pin _h _l _tags _out _fs _fh _ft _fl _FPWSH

# ================= G. 56-apm-go =================
# mise 是 stub：minimum_release_age_excludes 存在一個檔案裡（一行一個），
# `settings get` 照真 mise 的格式印成 TOML 陣列，`settings add` 附加一行，
# 每次呼叫都依序記在 log 裡。要釘的是：既有的清單保留、已存在的值不重複加、
# 排除要在 mise use 之前生效。
_g="$TMP/l7g"
rm -rf "$_g"; mkdir -p "$_g/stub" "$_g/nomise"
_g_pin=$(sed -n 's/^apmGo = "\(.*\)"$/\1/p' "$REPO/.chezmoitemplates/versions.toml")
cat > "$_g/stub/mise" <<'STUB'
#!/bin/sh
echo "$*" >> "$STUB_LOG"
if [ "$1 $2 $3" = "settings get minimum_release_age_excludes" ]; then
    printf '['; sep=''
    while IFS= read -r x; do printf '%s"%s"' "$sep" "$x"; sep=', '; done < "$STUB_EXCLUDES"
    printf ']\n'
elif [ "$1 $2 $3" = "settings add minimum_release_age_excludes" ]; then
    printf '%s\n' "$4" >> "$STUB_EXCLUDES"
fi
exit 0
STUB
chmod +x "$_g/stub/mise"
# arch 的渲染：與 linux 只差 brew shellenv 那一行（理由見 E 段）。
render_file arch .chezmoiscripts/run_after_56-apm-go.sh.tmpl > "$_g/56.sh"

_run_g() { # dir initial-excludes...
    _gd=$1; shift
    mkdir -p "$_gd"; : > "$_gd/excludes"; : > "$_gd/mise.log"
    for _x in "$@"; do printf '%s\n' "$_x" >> "$_gd/excludes"; done
    STUB_LOG="$_gd/mise.log" STUB_EXCLUDES="$_gd/excludes" PATH="$_g/stub:$PATH" \
        zsh "$_g/56.sh" 2>&1
}
# 第二次執行沿用同一份 excludes，模擬下一次 apply。
_rerun_g() { # dir
    STUB_LOG="$1/mise.log" STUB_EXCLUDES="$1/excludes" PATH="$_g/stub:$PATH" zsh "$_g/56.sh" 2>&1
}
_g_tool="github:gn00678465/apm-go[prerelease=true]@$_g_pin"

if ! command -v zsh >/dev/null 2>&1; then
    skip "POSIX 56-apm-go 的行為" "找不到 zsh"
else

_d="$_g/empty"
if _out=$(_run_g "$_d"); then _pass "POSIX 56-apm-go: 執行成功"
else _fail "POSIX 56-apm-go: 執行成功" "$_out"; fi
assert_eq "POSIX 56-apm-go: 空清單時加入 apm-go" "github:gn00678465/apm-go" "$(cat "$_d/excludes")"
assert_eq "POSIX 56-apm-go: 先加排除、再 mise use（版本解析時排除已生效）" \
    "$(printf 'settings get minimum_release_age_excludes\nsettings add minimum_release_age_excludes github:gn00678465/apm-go\nuse --global %s' "$_g_tool")" \
    "$(cat "$_d/mise.log")"
_rerun_g "$_d" >/dev/null
assert_eq "POSIX 56-apm-go: 重跑不重複加入" "github:gn00678465/apm-go" "$(cat "$_d/excludes")"

# 使用者原本就有別的值：保留，並附加在後面。
_d="$_g/claude"
_run_g "$_d" claude >/dev/null
assert_eq "POSIX 56-apm-go: 既有的 claude 保留，apm-go 附加在後" \
    "$(printf 'claude\ngithub:gn00678465/apm-go')" "$(cat "$_d/excludes")"
_rerun_g "$_d" >/dev/null
assert_eq "POSIX 56-apm-go: 有既有值時重跑也不重複" \
    "$(printf 'claude\ngithub:gn00678465/apm-go')" "$(cat "$_d/excludes")"

# 已經在清單裡（不論位置）：不呼叫 settings add。
_d="$_g/present"
_run_g "$_d" claude github:gn00678465/apm-go npm:* >/dev/null
assert_not_contains "POSIX 56-apm-go: 已存在時不呼叫 settings add" "$(cat "$_d/mise.log")" 'settings add'
assert_contains "POSIX 56-apm-go: 已存在時仍執行 mise use" "$(cat "$_d/mise.log")" "use --global $_g_tool"

# 只是前綴相同的值不算已存在。
_d="$_g/prefix"
_run_g "$_d" github:gn00678465/apm-go-fork >/dev/null
assert_eq "POSIX 56-apm-go: 前綴相同的別的 tool 不算已存在" \
    "$(printf 'github:gn00678465/apm-go-fork\ngithub:gn00678465/apm-go')" "$(cat "$_d/excludes")"

if _out=$(PATH="$_g/nomise" "$(command -v zsh)" "$_g/56.sh" 2>&1); then
    _pass "POSIX 56-apm-go: mise 不存在時退出碼是 0"
else _fail "POSIX 56-apm-go: mise 不存在時退出碼是 0" "$_out"; fi

fi

# ---- Windows ----
# 同 F 段：腳本沒有 Windows 專屬的路徑邏輯，用 Linux 的 pwsh 加 stub 跑。
_GPWSH=$(command -v pwsh 2>/dev/null || true)
if [ -z "$_GPWSH" ]; then
    skip "Windows 56-apm-go 的行為" "找不到 Linux 的 pwsh"
else
    render_file windows .chezmoiscripts/run_after_56-apm-go.ps1.tmpl > "$_g/56.ps1"
    mkdir -p "$_g/local" "$_g/pf"
    _run_gw() { # dir
        LOCALAPPDATA="$_g/local" ProgramFiles="$_g/pf" STUB_LOG="$1/mise.log" STUB_EXCLUDES="$1/excludes" \
            PATH="$_g/stub:$PATH" "$_GPWSH" -NoLogo -NoProfile -File "$_g/56.ps1" 2>&1
    }
    _d="$_g/win-claude"
    mkdir -p "$_d"; printf 'claude\n' > "$_d/excludes"
    if _out=$(_run_gw "$_d"); then _pass "Windows 56-apm-go: 執行成功"
    else _fail "Windows 56-apm-go: 執行成功" "$_out"; fi
    assert_eq "Windows 56-apm-go: 既有的 claude 保留，apm-go 附加在後" \
        "$(printf 'claude\ngithub:gn00678465/apm-go')" "$(cat "$_d/excludes")"
    assert_eq "Windows 56-apm-go: 先加排除、再 mise use" \
        "$(printf 'settings get minimum_release_age_excludes\nsettings add minimum_release_age_excludes github:gn00678465/apm-go\nuse --global %s' "$_g_tool")" \
        "$(cat "$_d/mise.log")"
    _run_gw "$_d" >/dev/null
    assert_eq "Windows 56-apm-go: 重跑不重複加入" \
        "$(printf 'claude\ngithub:gn00678465/apm-go')" "$(cat "$_d/excludes")"
    _d="$_g/win-prefix"
    mkdir -p "$_d"; printf 'github:gn00678465/apm-go-fork\n' > "$_d/excludes"
    _run_gw "$_d" >/dev/null
    assert_eq "Windows 56-apm-go: 前綴相同的別的 tool 不算已存在" \
        "$(printf 'github:gn00678465/apm-go-fork\ngithub:gn00678465/apm-go')" "$(cat "$_d/excludes")"
fi
unset _g _g_pin _g_tool _d _out _gd _x _GPWSH
