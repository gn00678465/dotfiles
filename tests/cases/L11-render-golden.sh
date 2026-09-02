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
_pair_check() { # label posix-target windows-target
    cm linux  cat "$TMP/dest-linux/$2"    > "$TMP/pair-posix" 2>/dev/null || true
    cm windows cat "$TMP/dest-windows/$3" > "$TMP/pair-win"   2>/dev/null || true
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
    cm "$1" cat "$TMP/dest-$1/$3" > "$TMP/arch-a" 2>/dev/null || true
    cm "$2" cat "$TMP/dest-$2/$3" > "$TMP/arch-b" 2>/dev/null || true
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
    cm windows cat "$TMP/dest-windows/$_t" > "$TMP/render-$_name" 2>/dev/null || true
    assert_bytes_eq "golden：$_name 的 Windows 渲染沒有悄悄改變" \
        "$_GOLDEN_RENDER/$_name" "$TMP/render-$_name"
done

# golden 檔案不可以多也不可以少 —— 否則刪掉一支 Windows 腳本連同它的 golden 就沒人發現。
assert_eq "golden/render/windows 的檔案集合" \
    "$(printf '30-install-winget-packages.ps1\n35-install-ps-modules.ps1\n40-git-lfs.ps1\n50-neovim.ps1\n60-pwsh-profile.ps1\nprofile.ps1\n')" \
    "$(ls "$_GOLDEN_RENDER" 2>/dev/null | LC_ALL=C sort)"

unset _s _t _name _GOLDEN_RENDER
