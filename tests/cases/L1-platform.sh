# L1 — .chezmoitemplates/platform.toml 是平台判斷的唯一來源。
# 這一層釘住它的輸出，以及「測試接縫在沒有 override 時會退回真實 OS」這個性質
# （SPEC M8：接縫本身若失準，上面每一層的證據都是假的）。

# 七欄：前五欄是 windows-support 時期就有的；distro 與 pkgManager 是
# archlinux-support 加的（SPEC §2.1）。發行版判斷只在這個 partial 裡。
_platform_fields='{{- $p := includeTemplate "platform.toml" . | fromToml -}}
{{ $p.os }}|{{ $p.arch }}|{{ $p.isWindows }}|{{ $p.isPosix }}|{{ $p.brewPrefix }}|{{ $p.distro }}|{{ $p.pkgManager }}'

# S2：既有平台。linux fixture 在這台主機上沒有 .chezmoi.osRelease.id（Windows
# 主機的 osRelease 是空 map，SPEC F2），distro 為空、pkgManager 退回 apt ——
# 與 Arch 支援之前的行為等價。darwin/windows 兩欄皆空。
assert_eq "linux/amd64 的平台事實" \
    'linux|amd64|false|true|/home/linuxbrew/.linuxbrew||apt' \
    "$(render linux "$_platform_fields")"

assert_eq "darwin/arm64 的平台事實（Apple Silicon 的 brew prefix）" \
    'darwin|arm64|false|true|/opt/homebrew||' \
    "$(render darwin-arm64 "$_platform_fields")"

assert_eq "darwin/amd64 的平台事實（Intel Mac 的 brew prefix）" \
    'darwin|amd64|false|true|/usr/local||' \
    "$(render darwin-amd64 "$_platform_fields")"

# Windows 沒有 brew。brewPrefix 必須是空字串而不是某個 POSIX 路徑，
# 否則任何忘了守 isWindows 的呼叫端會拼出一條看似合理、實際不存在的路徑。
assert_eq "windows/amd64 的平台事實（沒有 brew prefix）" \
    'windows|amd64|true|false|||' \
    "$(render windows "$_platform_fields")"

# S1：Arch。brewPrefix 必須是空字串（Arch 不裝 Homebrew，SPEC Must NOT #4），
# 讓 `ne $p.brewPrefix ""` 成為「這個平台用 brew」的唯一訊號。
assert_eq "arch（linux/amd64 + distroOverride=arch）的平台事實：pacman、沒有 brew prefix" \
    'linux|amd64|false|true||arch|pacman' \
    "$(render arch "$_platform_fields")"

# S3：沒有 distroOverride 時，distro 必須退回 chezmoi 自己讀到的
# .chezmoi.osRelease.id；非 Linux 主機上那個 map 是空的，退回空字串。
_native_distro=$(cm native execute-template '{{ if hasKey .chezmoi "osRelease" }}{{ if hasKey .chezmoi.osRelease "id" }}{{ .chezmoi.osRelease.id }}{{ end }}{{ end }}')
_partial_distro=$(render native '{{- $p := includeTemplate "platform.toml" . | fromToml -}}
{{ $p.distro }}')
assert_eq "沒有 distroOverride 時 partial 退回 .chezmoi.osRelease.id（不存在時為空）" \
    "$_native_distro" "$_partial_distro"
unset _native_distro _partial_distro

# 接縫驗證：沒有 override 時，partial 必須回傳 chezmoi 自己看到的 OS/arch。
_native_os=$(cm native execute-template '{{ .chezmoi.os }}|{{ .chezmoi.arch }}')
_partial_os=$(render native '{{- $p := includeTemplate "platform.toml" . | fromToml -}}
{{ $p.os }}|{{ $p.arch }}')
assert_eq "沒有 osOverride 時 partial 退回 .chezmoi.os/.chezmoi.arch" \
    "$_native_os" "$_partial_os"

unset _platform_fields _native_os _partial_os

# 接縫的生產端入口。整個 Windows 與 macOS 的證據都建立在「正式環境的 config
# 沒有 osOverride/archOverride」這個前提上，而那個前提原本只寫在 partial 的註解裡
# ——沒有任何一層檢查真正產生使用者 config 的那個檔案。
#
# 實測後果（獨立驗證在真實 Windows 主機上做過）：在 .chezmoi.toml.tmpl 的 [data]
# 底下加一行 osOverride = "linux"，Windows 上的 10-install-packages 會渲染成
# 1091 個非空位元組 → chezmoi 拿 .sh 去 exec → apply 中止（M1、Must NOT #4），
# 且 managed 會多出 .zshrc、少掉 AppData/（M7）。
_cfg_src=$(cat "$REPO/.chezmoi.toml.tmpl")
assert_not_contains "生產用的 .chezmoi.toml.tmpl 原始碼沒有 osOverride" "$_cfg_src" "osOverride"
assert_not_contains "生產用的 .chezmoi.toml.tmpl 原始碼沒有 archOverride" "$_cfg_src" "archOverride"
# 原始碼沒有還不夠：它是模板，值也可能是算出來的。連渲染結果一起釘。
_cfg_out=$(render_file native .chezmoi.toml.tmpl 2>&1)
assert_not_contains "渲染後的生產 config 沒有 osOverride" "$_cfg_out" "osOverride"
assert_not_contains "渲染後的生產 config 沒有 archOverride" "$_cfg_out" "archOverride"
# S4：distroOverride 同理。生產 config 一旦帶這個 key，Debian 機器會走 pacman
# 分支、或 Arch 機器會走 apt 分支，10-install-packages 在第一支腳本就中止。
assert_not_contains "生產用的 .chezmoi.toml.tmpl 原始碼沒有 distroOverride" "$_cfg_src" "distroOverride"
assert_not_contains "渲染後的生產 config 沒有 distroOverride" "$_cfg_out" "distroOverride"
unset _cfg_src _cfg_out
