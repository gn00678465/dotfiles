# L8 — 用 Windows 主機上真實的 chezmoi 驗證測試接縫本身。
#
# 上面每一層（L1-L6）的 Windows 證據都是在 Linux 上用 osOverride 模擬出來的。
# 如果那個接縫跟真實的 .chezmoi.os == "windows" 有任何出入，那些綠燈全部是假的
# （SPEC M8）。這一層把兩邊逐位元組比對，讓那個假設變成被驗證過的事實。
#
# Windows 端的 chezmoi 以 UNC 路徑（\\wsl.localhost\...）直接讀這個 repo 當 source，
# 用的是不帶 osOverride 的 native.toml，destination 是 Windows 自己的 TEMP。
# 全程唯讀真實的 $HOME（SPEC Must NOT #1）。

_PWSH=$(command -v pwsh.exe 2>/dev/null || true)
_UNC=""
_WT=""
_WU=""
if [ -n "$_PWSH" ]; then
    _UNC=$(wslpath -w "$REPO" 2>/dev/null || echo "")
    _WT=$("$_PWSH" -NoProfile -NonInteractive -Command '$env:TEMP' 2>/dev/null | tr -d '\r')
    _WU=$(wslpath -u "$_WT" 2>/dev/null || echo "")
    if [ -z "$_UNC" ] || [ -z "$_WT" ] || [ -z "$_WU" ]; then _PWSH=""; fi
fi
if [ -n "$_PWSH" ]; then
    "$_PWSH" -NoProfile -NonInteractive -Command 'if (-not (Get-Command chezmoi -ErrorAction SilentlyContinue)) { exit 1 }' >/dev/null 2>&1 || _PWSH=""
fi

if [ -z "$_PWSH" ]; then
    skip "Windows 主機端的接縫驗證" "需要 WSL interop + Windows 端的 chezmoi + UNC 存取"
else
    _ID="l8-$$"
    _DEST_WIN="$_WT\\$_ID-dest"; _DEST_WSL="$_WU/$_ID-dest"
    _APPLY_WIN="$_WT\\$_ID-apply"; _APPLY_WSL="$_WU/$_ID-apply"
    _OUT_WIN="$_WT\\$_ID"; _OUT_WSL="$_WU/$_ID"
    rm -rf "$_DEST_WSL" "$_APPLY_WSL" "$_OUT_WSL"
    mkdir -p "$_DEST_WSL" "$_APPLY_WSL" "$_OUT_WSL"

    # Start-Process 把子行程的 stdout 原封不動寫進檔案。不透過 pwsh 的管線接輸出：
    # pwsh 會用自己的 console 編碼重新解碼，這些檔案裡的中文會變成亂碼
    # （L4 已經被這件事咬過一次）。
    _win_chezmoi() { # outname args...
        _o=$1; shift
        _al=""
        for _a in "$@"; do _al="$_al,'$_a'"; done
        _al=${_al#,}
        "$_PWSH" -NoProfile -NonInteractive -Command "\$p = Start-Process -FilePath 'chezmoi' -NoNewWindow -Wait -PassThru -RedirectStandardOutput '$_OUT_WIN\\$_o.out' -RedirectStandardError '$_OUT_WIN\\$_o.err' -ArgumentList @($_al); exit \$p.ExitCode" >/dev/null 2>&1
    }
    _cm_win() { # outname dest subcommand-args...
        _o=$1; _d=$2; shift 2
        _win_chezmoi "$_o" --source "$_UNC" --config "$_UNC\\tests\\fixtures\\native.toml" \
            --destination "$_d" --persistent-state "$_OUT_WIN\\state.boltdb" --no-tty "$@"
    }
    _win_out() { tr -d '\r' < "$_OUT_WSL/$1.out"; }
    _win_err() { tr -d '\r' < "$_OUT_WSL/$1.err" | grep -v 'config file template has changed' || true; }

    # 先確認 Windows 端真的認為自己是 windows —— 這是整層的前提。
    # 不用 execute-template 直接問：它的模板引數會被 Start-Process 重新加引號而
    # 走樣。改用 managed 的結果間接確認：只有 windows 會產出 AppData/ 這棵樹。
    _cm_win mg "$_DEST_WIN" managed --exclude=externals
    _mg=$(_win_out mg | LC_ALL=C sort)
    assert_contains "Windows 主機端確實以 windows 身分算繪（managed 有 AppData/）" "$_mg" "AppData/Local/nvim"
    assert_eq "Windows 主機端的 managed 清單與 golden 相同" \
        "$(cat "$GOLDEN/managed-windows.txt")" "$_mg"

    # 逐支腳本：真實 Windows 的渲染結果 vs Linux 上 osOverride 模擬的結果。
    # 兩者必須逐位元組相同，否則模擬出來的證據不成立。
    _scripts=$(grep '^\.chezmoiscripts/' "$GOLDEN/managed-windows.txt")
    # 比對走原始位元組（cmp），兩邊都不做 tr -d '\r'。用 $(...) 拿字串會吃掉結尾
    # 換行，再 tr 掉 CR 更是直接抹平行尾差異 —— 那樣宣稱「逐位元組」是假的。
    # 這裡真的比位元組，所以「Windows 端寫出 CRLF」這種差異也會被抓到。
    for _t in $_scripts; do
        _name=$(basename "$_t")
        _cm_win "s-$_name" "$_DEST_WIN" cat "$_DEST_WIN\\.chezmoiscripts\\$_name"
        cm windows cat "$TMP/dest-windows/.chezmoiscripts/$_name" > "$_OUT_WSL/sim-$_name" 2>/dev/null || true
        assert_bytes_eq "接縫：$_name 的真實 Windows 渲染 == 模擬渲染（逐位元組）" \
            "$_OUT_WSL/sim-$_name" "$_OUT_WSL/s-$_name.out"
    done

    _cm_win prof "$_DEST_WIN" cat "$_DEST_WIN\\.config\\powershell\\profile.ps1"
    cm windows cat "$TMP/dest-windows/.config/powershell/profile.ps1" > "$_OUT_WSL/sim-profile.ps1"
    assert_bytes_eq "接縫：profile.ps1 的真實 Windows 渲染 == 模擬渲染（逐位元組）" \
        "$_OUT_WSL/sim-profile.ps1" "$_OUT_WSL/prof.out"

    # 真的在 Windows 上跑一次 apply（只套檔案，不執行腳本、不抓 external）。
    # 這是「codex 的 modify_ 移植成 modify-template 之後在 Windows 上真的能用」
    # 的唯一直接證據 —— 之前那些 apply 都是在 Linux 上跑的，sh 腳本在那裡本來就能動。
    # cp -a 在 DrvFs（/mnt/c）上會因為保留時間戳失敗；這裡只需要內容。
    cp -r "$REPO/tests/fixtures/l6/c2-comments-and-tables/home/." "$_APPLY_WSL/"
    _cm_win ap "$_APPLY_WIN" apply --exclude=scripts,externals
    assert_eq "Windows 主機端 apply 無錯誤" "" "$(_win_err ap)"
    assert_bytes_eq "Windows 主機端產生的 ~/.codex/config.toml 與 golden 逐位元組相同" \
        "$GOLDEN/l6/c2-comments-and-tables/.codex/config.toml" \
        "$_APPLY_WSL/.codex/config.toml"
    assert_bytes_eq "Windows 主機端產生的 ~/.claude/settings.json 與 golden 逐位元組相同" \
        "$GOLDEN/l6/c2-comments-and-tables/settings.windows.json" \
        "$_APPLY_WSL/.claude/settings.json"

    rm -rf "$_DEST_WSL" "$_APPLY_WSL" "$_OUT_WSL"
fi

unset _PWSH _UNC _WT _WU _ID _DEST_WIN _DEST_WSL _APPLY_WIN _APPLY_WSL _OUT_WIN _OUT_WSL _mg _scripts _t _name _real _sim _o _d _a _al
