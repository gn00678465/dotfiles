# L1 — .chezmoitemplates/platform.toml 是平台判斷的唯一來源。
# 這一層釘住它的輸出，以及「測試接縫在沒有 override 時會退回真實 OS」這個性質
# （SPEC M8：接縫本身若失準，上面每一層的證據都是假的）。

_platform_fields='{{- $p := includeTemplate "platform.toml" . | fromToml -}}
{{ $p.os }}|{{ $p.arch }}|{{ $p.isWindows }}|{{ $p.isPosix }}|{{ $p.brewPrefix }}'

assert_eq "linux/amd64 的平台事實" \
    'linux|amd64|false|true|/home/linuxbrew/.linuxbrew' \
    "$(render linux "$_platform_fields")"

assert_eq "darwin/arm64 的平台事實（Apple Silicon 的 brew prefix）" \
    'darwin|arm64|false|true|/opt/homebrew' \
    "$(render darwin-arm64 "$_platform_fields")"

assert_eq "darwin/amd64 的平台事實（Intel Mac 的 brew prefix）" \
    'darwin|amd64|false|true|/usr/local' \
    "$(render darwin-amd64 "$_platform_fields")"

# Windows 沒有 brew。brewPrefix 必須是空字串而不是某個 POSIX 路徑，
# 否則任何忘了守 isWindows 的呼叫端會拼出一條看似合理、實際不存在的路徑。
assert_eq "windows/amd64 的平台事實（沒有 brew prefix）" \
    'windows|amd64|true|false||' \
    "$(render windows "$_platform_fields")|"

# 接縫驗證：沒有 override 時，partial 必須回傳 chezmoi 自己看到的 OS/arch。
_native_os=$(cm native execute-template '{{ .chezmoi.os }}|{{ .chezmoi.arch }}')
_partial_os=$(render native '{{- $p := includeTemplate "platform.toml" . | fromToml -}}
{{ $p.os }}|{{ $p.arch }}')
assert_eq "沒有 osOverride 時 partial 退回 .chezmoi.os/.chezmoi.arch" \
    "$_native_os" "$_partial_os"

unset _platform_fields _native_os _partial_os
