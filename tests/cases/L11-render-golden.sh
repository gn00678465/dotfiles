# L11 — Windows 側缺的那個 oracle。
#
# POSIX 的每一個產物都能跟 base ref 逐位元組比對（L10），那一個機制免費擋掉整類
# 「內容悄悄漂移」的問題。Windows 沒有 base ref 可比，於是原本只剩三個程序，而它們
# 結構上都不可能因為內容改變而失敗：
#   L2 比的是一份手列的子字串清單；
#   L7 把 %LOCALAPPDATA%/%ProgramFiles% 重導向到空沙盒，看不到 PATH 與套件清單；
#   L8 比的是「真實 Windows 渲染 vs 模擬渲染」——同一份來源的兩次渲染，內容改了
#      兩邊會一起改。
# 獨立驗證連續四輪都在這個缺口裡找到**第一次出現**的實例（不是既有問題的小變形），
# 那是「機制缺一塊」而不是「缺陷尾巴在收斂」的徵狀。
#
# 這一層補的是那個機制，分三種斷言，強度不同，各自標明：
#
#   A. 跨平台等價（真 oracle）：POSIX 與 Windows 的同一份共用內容必須逐位元組相同。
#   B. 跨 arch 等價（真 oracle）：腳本不依賴 arch，兩個 arch 的渲染必須相同。
#   C. golden 快照（**只是變更偵測器，不是正確性 oracle**）：Windows 專屬產物的
#      渲染結果釘在 tests/golden/render/ 下。它證明的是「沒有人在沒被看見的情況下
#      改了內容」，不證明內容是對的——正確性來自其他層。更新 golden 一定會出現在
#      diff 裡，那正是重點。

# ---------- A. 跨平台等價：同一份共用內容的兩個落點 ----------
# 這兩對各自是「一行 includeTemplate 同一個 partial」，所以內容本來就該一模一樣。
# 少了這條，Windows 那一份可以被整個換掉而不被任何測試發現。
# `|| true` 會讓 cm 失敗時留下一個空檔，而 cmp 認為兩個空檔相等 —— 斷言就恆真了。
# 所以這裡取完內容一定要檢查它非空；取不到就是失敗，不是「兩邊都沒有所以相等」。
_render_to() { # os target outfile label
    if ! cm "$1" cat "$TMP/dest-$1/$2" > "$3" 2>/dev/null; then
        _fail "$4：取得 $1 的 $2" "chezmoi cat 失敗"
        return 1
    fi
    if [ ! -s "$3" ]; then
        _fail "$4：$1 的 $2 非空" "取到的是空內容 —— 空比空會恆真"
        return 1
    fi
    return 0
}

_pair_check() { # label posix-target windows-target
    _render_to linux "$2" "$TMP/pair-posix" "$1" || return 0
    _render_to windows "$3" "$TMP/pair-win" "$1" || return 0
    assert_bytes_eq "$1：POSIX 與 Windows 的落點內容逐位元組相同" \
        "$TMP/pair-posix" "$TMP/pair-win"
}
_pair_check "nvim completion plugin" \
    ".config/nvim/lua/plugins/completion.lua" \
    "AppData/Local/nvim/lua/plugins/completion.lua"
_pair_check "uv 設定" \
    ".config/uv/uv.toml" \
    "AppData/Roaming/uv/uv.toml"

# ---------- B. 跨 arch 等價 ----------
# 安裝腳本與 profile 都不該依賴 arch。唯一依賴 arch 的是 external（asset 名稱），
# 那個由 L5 逐平台釘住。
_arch_pair() { # os-a os-b path label
    _render_to "$1" "$3" "$TMP/arch-a" "$4" || return 0
    _render_to "$2" "$3" "$TMP/arch-b" "$4" || return 0
    assert_bytes_eq "$4：$1 與 $2 的渲染相同（腳本不該依賴 arch）" "$TMP/arch-a" "$TMP/arch-b"
}
for _s in 30-install-winget-packages.ps1 35-install-ps-modules.ps1 \
          40-git-lfs.ps1 50-neovim.ps1 60-pwsh-profile.ps1; do
    _arch_pair windows windows-arm64 ".chezmoiscripts/$_s" "$_s"
done
_arch_pair windows windows-arm64 ".config/powershell/profile.ps1" "profile.ps1"
_arch_pair linux linux-arm64 ".chezmoiscripts/50-neovim.sh" "50-neovim.sh"

# ---------- C. Windows 專屬產物的 golden 快照 ----------
# 涵蓋的是「這個平台沒有 base ref 可比」的那些檔案。POSIX 專屬與跨平台共用的部分
# 分別由 L10 與上面的 A 負責，不重複。
_GOLDEN_RENDER="$GOLDEN/render/windows"
for _t in .chezmoiscripts/30-install-winget-packages.ps1 \
          .chezmoiscripts/35-install-ps-modules.ps1 \
          .chezmoiscripts/40-git-lfs.ps1 \
          .chezmoiscripts/50-neovim.ps1 \
          .chezmoiscripts/60-pwsh-profile.ps1 \
          .config/powershell/profile.ps1; do
    _name=$(basename "$_t")
    if [ ! -f "$_GOLDEN_RENDER/$_name" ]; then
        _fail "golden 存在：$_name" "$_GOLDEN_RENDER/$_name 不存在（新增 Windows 產物時要一起加 golden）"
        continue
    fi
    _render_to windows "$_t" "$TMP/render-$_name" "golden $_name" || continue
    assert_bytes_eq "golden：$_name 的 Windows 渲染沒有悄悄改變" \
        "$_GOLDEN_RENDER/$_name" "$TMP/render-$_name"
done

# golden 檔案不可以多也不可以少 —— 否則刪掉一支 Windows 腳本連同它的 golden 就沒人發現。
assert_eq "golden/render/windows 的檔案集合" \
    "$(printf '30-install-winget-packages.ps1\n35-install-ps-modules.ps1\n40-git-lfs.ps1\n50-neovim.ps1\n60-pwsh-profile.ps1\nprofile.ps1\n')" \
    "$(ls "$_GOLDEN_RENDER" 2>/dev/null | LC_ALL=C sort)"

unset _s _t _name _GOLDEN_RENDER

# ---------- D. 不經 chezmoi 算繪的兩支 Windows 檔案 ----------
# L11-C 只涵蓋「chezmoi 會渲染的東西」。init.ps1 是自舉腳本（使用者直接 irm | iex
# 執行，不經 chezmoi），sandbox 探針同理，兩者都落在這個機制的邊界之外，而它們正好
# 是最不受控的環境裡執行的程式碼。這裡不做 golden 快照（它們不是模板，git 本來就
# 追得到），改成把「它們必須做到的事」寫成斷言。
_init=$(cat "$REPO/init.ps1")

# 自舉的三個套件缺一不可：沒有 git 就 clone 不了、沒有 pwsh 7 chezmoi 跑不了 .ps1、
# 沒有 chezmoi 就什麼都不會發生。supply-chain 那一層只驗「列出來的 ID 解析得到」，
# 少了一個它不會失敗。
for _pair in "Microsoft.PowerShell|pwsh" "Git.Git|git" "twpayne.chezmoi|chezmoi"; do
    _id=${_pair%%|*}; _cmd=${_pair##*|}
    assert_contains "init.ps1 會自舉 $_id" "$_init" "Install-IfMissing -Id '$_id'"
    assert_contains "init.ps1 用 $_cmd 判斷 $_id 是否已存在" "$_init" "-Command '$_cmd'"
done
assert_contains "init.ps1 clone 的是正確的 GitHub 帳號" "$_init" "chezmoiArgs += 'gn00678465'"
assert_contains "init.ps1 會在 symlink 權限不足時警告" "$_init" 'if (-not $symlinkOk)'
assert_contains "init.ps1 的 symlink 警告有指出開發人員模式" "$_init" "Developer"

# sandbox 探針是 M12 與 symlink 權限唯一的量測工具；它悄悄少掉一項檢查，
# 我們會拿到一份看起來通過、實際上沒問過那個問題的結果。
_probe=$(cat "$REPO/tests/sandbox/_probe.ps1")
assert_contains "sandbox 探針會問 M12（treesitter parser 編不編得出來）" "$_probe" "SPEC M12"
assert_contains "sandbox 探針會檢查 symlink" "$_probe" "claude skills symlinks"
assert_contains "sandbox 探針會檢查 zsh 專屬檔案沒有落地" "$_probe" "zsh-only files did NOT land"
# 「每個工具都要被檢查到」這條義務在 SPEC v6 換了形狀：不再逐一問「在不在 PATH 上」
# （那組檢查修不好，已移除），改成問「套件裝了沒」。清單的完整性由下面那條
# 「探針的套件清單與 30-install-winget-packages 完全相同」守住，比原本寫死十個名字強：
# 產品加了套件而探針漏掉，那一條會紅。

# 遠端模式：使用者要能在任何一台有 Sandbox 的機器上，不經 prepare.sh、不對應資料夾，
# 用一行 irm 跑完 L9。這幾條釘的是那條路徑上「少一項就整個模式失效」的義務。
assert_contains "sandbox 探針收 -Branch（名稱與 init.ps1 對齊）" "$_probe" 'param([string] $Branch)'
assert_contains "遠端模式讓 chezmoi 自己 clone 指定分支" "$_probe" "'--branch', \$Branch"
assert_contains "遠端模式 clone 的是正確的 GitHub 帳號" "$_probe" "'gn00678465'"
assert_contains "遠端模式改從 chezmoi source-path 取來源樹" "$_probe" 'chezmoi source-path'
assert_contains "沒有對應 C:\out 時輸出改寫到桌面" "$_probe" 'Desktop\chezmoi-probe'
assert_contains "結尾把 results.tsv 全文印到主控台（Sandbox 關掉就沒了）" "$_probe" 'results.tsv (full)'
# 寫死的輸出路徑只要留一個，桌面那條退路就有一半是假的：transcript 或 treesitter.log
# 會照樣寫去 C:\out，而那個目錄在遠端模式下根本不存在。
assert_not_contains "探針裡沒有寫死的 C:\out 輸出路徑" "$_probe" "'C:\out\\"

# 以下四條全部來自 L9 的第一次真實執行（見 evidence「L9 第一次執行」）。
#
# 最重的一條是 Get-Content：探針的 $ErrorActionPreference 是 'Continue'，所以
# 檔案不存在時 Get-Content 是**非終止**錯誤，變數拿到 $null；而 PowerShell 的
# $null -match 與 $null -notmatch **兩個都回 $false**。於是「codex config.toml 有
# 受管的 [tui] key」這條在整個 apply 一個檔案都沒落地的情況下回報 PASS。
# 那次執行裡它就是這樣騙過去的（本機以 5.1 實測重現）。這是 L9 最不該有的失效模式：
# 探針宣稱看到了它其實沒看到的東西。
_probe_unguarded=$(grep -n 'Get-Content' "$REPO/tests/sandbox/_probe.ps1" | grep -v -- '-ErrorAction Stop' || true)
assert_eq "探針裡每一處 Get-Content 都帶 -ErrorAction Stop（缺檔要炸，不是回 \$null）" \
    "" "$_probe_unguarded"

assert_contains "chezmoi 失敗時，FAIL 的 detail 要帶 chezmoi 輸出的尾段" "$_probe" 'Get-OutputTail'
assert_contains "結尾要印出 treesitter.log（遠端模式關掉就沒了）" "$_probe" 'treesitter.log (tail'
assert_contains "主控台編碼統一成 UTF-8（winget 的輸出是 UTF-8，5.1 預設用 ANSI 代碼頁解）" \
    "$_probe" '[Console]::OutputEncoding'

# SPEC v5 第 1、2 項：L9 執行期間必須是可觀察的，PATH 判定必須讀 registry。
# 兩者都來自遠端模式的實際操作 —— 前者讓操作者分不出「還在跑」與「卡死」，
# 後者讓十個裝好的工具全部被誤報成 not found。
assert_contains "子程序輸出邊收邊印，不是整段收完才印" "$_probe" 'Invoke-Streamed'
assert_contains "長步驟開始前先報「正在做什麼、預期多久」" "$_probe" 'probe: this usually takes'
assert_contains "treesitter 那段等待中要有心跳，不能整段靜止" "$_probe" 'still building'
assert_contains "PATH 判定用有 scope 的 GetEnvironmentVariable，不經 registry provider" \
    "$_probe" "[Environment]::GetEnvironmentVariable('Path', \$scope)"
assert_contains "Machine 與 User 兩個範圍都讀" "$_probe" "@('Machine', 'User')"

# L9 第三次執行：十個工具仍然全部 not found，但 M12 那條檢查必須真的跑起 nvim、
# tree-sitter 與 gcc 才會過 —— 它 PASS 了，所以工具都在、都能跑。也就是 PATH 重建
# 這段沒有生效，而**探針對此完全沉默**：detail 只有 'not found'，沒有說它搜了什麼，
# 也沒有說重建有沒有成功。沉默正是上一輪讓這件事讀不懂的原因。
assert_contains "PATH 重建的結果要記進 results，不能只留在主控台" "$_probe" 'ProbePathReport'
assert_contains "PATH 重建本身是一條可以 FAIL 的檢查（靜靜失敗就是這次的問題）" \
    "$_probe" "Check 'PATH rebuilt from Machine+User environment'"
# v5 第 2 項要求「記下實際找到的路徑」，是綁在那組 tool on PATH 檢查上的；v6 把整組
# 移除之後這條義務隨之消失。取而代之的是套件檢查失敗時要帶 winget 的輸出尾段。
assert_contains "套件檢查失敗時要帶 winget 的輸出尾段" "$_probe" 'winget list -> $LASTEXITCODE'

# SPEC v6：十條 tool on PATH 檢查已移除 —— 修了三輪都沒修好、根因未找到，而一條
# 已知會紅的檢查會讓人學會忽略 FAIL。整段子程序查找機制一併移除。
assert_not_contains "子程序查找機制已移除（SPEC v6）" "$_probe" 'Invoke-ToolLookup'
# 針對「那組 Check 不存在」，不是「這個詞不准出現」——註解裡解釋為什麼移除是合理的，
# 而且比默默刪掉有用。
assert_not_contains "tool on PATH 那組檢查已移除（SPEC v6）" "$_probe" 'Check "tool on PATH'

# 換上來的是「套件裝了沒」：用產品腳本自己的判斷指令，不依賴 PATH。
assert_contains "改用 winget list --exact --id 確認套件已安裝" "$_probe" 'winget list --exact --id'
assert_contains "套件檢查的名稱進得了 results" "$_probe" 'winget package installed:'

# 這一條才是真的 oracle：探針的清單必須**等於**產品腳本的清單。寫死兩份清單的話，
# 產品加了一個套件而探針沒加，L9 就會悄悄少驗一個 —— 而 L9 是唯一能驗它的地方。
_probe_ids=$(sed -n "/\$wingetPackages = @(/,/^)/p" "$REPO/tests/sandbox/_probe.ps1" \
    | sed -n "s/^ *'\([^']*\)'.*/\1/p" | LC_ALL=C sort)
_script_ids=$(render_file windows .chezmoiscripts/run_onchange_before_30-install-winget-packages.ps1.tmpl \
    | sed -n "/^\$packages = @(/,/^)/p" | sed -n "s/^ *'\([^']*\)'.*/\1/p" | LC_ALL=C sort)
assert_not_blank "探針讀得到 winget 套件清單" "$_probe_ids"
assert_eq "探針的套件清單與 30-install-winget-packages 完全相同" "$_script_ids" "$_probe_ids"
# 固定目錄清單就是上一輪誤報的機制本身。唯一保留的例外是 mise 的 shim 目錄，
# 它不在 registry PATH 上（是 profile 的 mise activate 加的），必須單獨補、單獨說明。
_probe_fixed=$(grep -c "Join-Path \$env:ProgramFiles" "$REPO/tests/sandbox/_probe.ps1" || true)
assert_eq "探針不再靠寫死的 ProgramFiles 目錄清單判定 PATH" "0" "$_probe_fixed"
# 上面那 22 條是 assert_contains —— 子字串在不在，跟那一行會不會執行是兩回事。
# 獨立驗證用四個變異證明了差別：把 Git 的自舉整行**註解掉**、把三行搬到 chezmoi
# 呼叫**之後**、在正確的那行**之後再賦值一次**別的帳號、把 M12 檢查的**內容**換掉 ——
# 四個都存活整套 458 個測試（其中兩個連 supply-chain 都過，因為它的正則會匹配到
# 註解裡的內容）。子字串斷言只抓得到「刪除」，抓不到「停用、改序、覆寫」。
#
# 這兩個檔案不是模板，git 本來就追得到；但 gate 是靠測試而不是靠人看 diff。
# 逐位元組比對是「golden pin」原本的意思。
for _pair in "init.ps1|$REPO/init.ps1" "_probe.ps1|$REPO/tests/sandbox/_probe.ps1"; do
    _name=${_pair%%|*}; _path=${_pair##*|}
    assert_bytes_eq "verbatim golden：$_name 沒有被改動（含註解掉、改序、覆寫）" \
        "$GOLDEN/verbatim/$_name" "$_path"
done

# 測試層自己也會被刪掉。gate 的 manifest 稽核管的是 **gate 的層**，不是測試層；
# 而 tests/run.sh 在指定的層檔案不存在時是 exit 0（`1..0`）。L1/L2/L3/L5/L6/L7/L10/L11
# 被刪掉會讓對應的 mutant 變成 SURVIVED 而讓 mutation 層變紅，但 **L4 與 L8 沒有任何
# mutant 指向它們** —— 獨立驗證實測：把這兩個檔案刪掉，整個 gate 照樣全綠。
# L8 是 SPEC 對 M8 唯一指名的程序（接縫與真實 Windows 行為是否一致），而這份報告
# 每一條 Windows 與 macOS 的主張都是經由那個接縫推導出來的。
assert_eq "測試層的檔案集合" \
    "$(printf '%s\n' L1-platform.sh L10-posix-regression.sh L11-render-golden.sh \
        L2-script-render-matrix.sh L3-managed-set.sh L4-syntax.sh L5-externals.sh \
        L6-file-golden.sh L7-behavior.sh L8-windows-seam.sh | LC_ALL=C sort)" \
    "$(ls "$REPO/tests/cases" | LC_ALL=C sort)"

unset _init _probe _probe_unguarded _probe_fixed _probe_ids _script_ids _pair _id _cmd _t _name _path
