# Windows 原生 PowerShell 7 與 Oh My Posh 研究

> 研究日期：2026-09-01。本檔只使用 Microsoft、chezmoi 與 Oh My Posh 的第一方
> 文件；「**已驗證**」是來源直接陳述的事實，「**推論**」是本 repo 應採取的設計結論。

## 結論

Windows 不是把現有的 zsh／Oh My Zsh／Powerlevel10k 設定搬過去，而是應新增一條獨立
的 **PowerShell 7 (`pwsh`) + Oh My Posh** 路徑：以 WinGet 安裝
`Microsoft.PowerShell` 和 `JanDeDobbeleer.OhMyPosh`，再管理 PowerShell 7 的 current-user
profile，加入能耐受套件升級的 Oh My Posh 初始化。

這項擴充不改變 Linux/macOS 的 zsh 與 Oh My Zsh 契約；它們是 Windows 支援的回歸保護
範圍。

## 1. 既有來源狀態與平台分界

### 已觀察到的現況（2026-09-01）

- `dot_zshrc.tmpl` 無 OS 外層條件，會產生 `~/.zshrc`；其內容載入 Oh My Zsh、
  Powerlevel10k 以及 `git`、`mise`、`fzf-tab`、`zsh-autosuggestions`、
  `zsh-syntax-highlighting`。
- `dot_p10k.zsh` 會管理 `~/.p10k.zsh`。
- `.chezmoiexternal.toml.tmpl` 目前無 Windows 條件地宣告 `.oh-my-zsh` 與其插件、
  Powerlevel10k theme archive。
- Linux 的 `run_after_default-shell.sh.tmpl` 已經以 `.chezmoi.os == "linux"` 防護；
  因此它不應成為 Windows 的「預設 shell」機制。

**推論：** Windows 目標狀態必須排除上述 zsh／Oh My Zsh／Powerlevel10k artifacts，不能只
新增 PowerShell profile 後任由 zsh artifacts 繼續部署。Linux/macOS 則必須繼續輸出既有
zsh artifacts，不得改成 Oh My Posh 或改動其 plugin 順序。

## 2. PowerShell 7 安裝與 profile 契約

- **[已驗證]** Microsoft 將 WinGet 列為 Windows client 安裝 PowerShell 的建議方式；穩定版
  ID 是 `Microsoft.PowerShell`，安裝後的 command 是 `pwsh`。PowerShell 7 與內建
  Windows PowerShell 5.1 並存，而不是取代它。
  [Microsoft：Install PowerShell on Windows](https://learn.microsoft.com/en-us/powershell/scripting/install/install-powershell-on-windows?view=powershell-7.5)
- **[已驗證]** 從 PowerShell 7.6 起，`winget install --id Microsoft.PowerShell` 預設選
  MSIX；該安裝是單一使用者範圍，不能建立／修改 all-users profile，且不能
  `Set-ExecutionPolicy -Scope LocalMachine`。
  [Microsoft：MSIX limitations](https://learn.microsoft.com/en-us/powershell/scripting/install/install-powershell-on-windows?view=powershell-7.5#limitations-of-a-msix-based-installation)
- **[已驗證]** PowerShell 不會自行建立 profile。Windows PowerShell console 的 PowerShell 7
  current-user/current-host 預設路徑是
  `$HOME\Documents\PowerShell\Microsoft.PowerShell_profile.ps1`，亦即 `pwsh` 裡的
  `$PROFILE`；current-user/all-hosts 是
  `$HOME\\Documents\\PowerShell\\Profile.ps1`。`$PROFILE` 的值依 host 而變，應在目標
  `pwsh` host 取得／驗證，不應拿 Windows PowerShell 5.1 的 profile 當作 PowerShell 7
  profile。
  [Microsoft：about_Profiles](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_profiles?view=powershell-7.5)

**推論：** 本 repo 應管理 PowerShell 7 的** current-user profile**，不能依賴 all-users
profile 或修改 machine-wide execution policy。若產品範圍只含 Windows Terminal 的 `pwsh`，
目標為 `Microsoft.PowerShell_profile.ps1`；若要求同一設定套用到所有 `pwsh` hosts，必須
明確選擇 `Profile.ps1`。兩者是不同契約，不能同時偷偷寫入。

## 3. Oh My Posh 安裝與初始化

- **[已驗證]** Oh My Posh 官方 Windows 安裝文件指定的 WinGet package ID 是
  `JanDeDobbeleer.OhMyPosh`。
  [Oh My Posh：Windows installation](https://ohmyposh.dev/docs/installation/windows)
- **[已驗證]** 官方 PowerShell 初始化行為是將
  `oh-my-posh init pwsh | Invoke-Expression` 放在偏好的 PowerShell 版本之 `$PROFILE`
  最後；若 profile 不存在，官方範例用
  `New-Item -Path $PROFILE -Type File -Force` 建立。
  [Oh My Posh：PowerShell prompt initialization](https://ohmyposh.dev/docs/installation/prompt)
- **[已驗證]** 預設 init script 多數會嵌入執行檔絕對路徑；套件管理器升級時若刪除舊版，
  既有 profile 可能指向不存在的位置。官方以 `--strict` 改由 `PATH` 解析可避免此問題。
  [Oh My Posh：package-manager initialization](https://ohmyposh.dev/docs/installation/prompt#package-managers)
- **[已驗證]** Oh My Posh 文件指出 execution policy 阻擋 unsigned scripts 時，可使用
  `oh-my-posh init pwsh --eval | Invoke-Expression`，但這會使 shell 初始化變慢；它也列出
  改成 `RemoteSigned`（machine scope）或簽署 profile 的替代方案。
  [Oh My Posh：execution-policy behavior](https://ohmyposh.dev/docs/installation/prompt)

**推論：** 預設 profile content 應為：

```powershell
oh-my-posh init pwsh --config 'powerlevel10k_rainbow' --strict | Invoke-Expression
```

`powerlevel10k_rainbow` 的 theme-pointer 與 cache-miss 行為見第 7 節；`--strict` 把
package-manager upgrade 的失效風險納入初始化設計。不要未經明確同意改動 execution policy；
若實機的有效 policy 擋住標準初始化，應明確失敗／報告，或由 SPEC 明確選擇較慢的 `--eval`
fallback，而不是在 bootstrap 中悄悄做 machine-wide 改動。

Oh My Posh 官方建議 Windows Terminal 與 Nerd Font 以正確顯示 icon，但兩者是建議，不是
安裝 `oh-my-posh` 或載入 profile 的硬性前置。
[Oh My Posh：Windows terminal and font guidance](https://ohmyposh.dev/docs/installation/windows)

## 4. 可重跑、非互動的 WinGet 安裝

**[已驗證]** `--id` 限定 ID、`--exact` 要求精確比對、`--source winget` 解決多來源歧義。
`--silent` 抑制 installer UI；`--accept-package-agreements` 與
`--accept-source-agreements` 分別接受 package 與 source 條款；`--disable-interactivity`
停用 WinGet 的 prompts。Microsoft 明確說明要完全非互動，agreement flag 應與
`--silent` 合用。
[Microsoft：winget install options](https://learn.microsoft.com/en-us/windows/package-manager/winget/install)

**推論：** 每一個 package 的非互動呼叫應採取以下固定形狀，並以已安裝版本為 no-op
或明確升級策略，確保重跑行為由 tests 約束：

```powershell
winget install --id Microsoft.PowerShell --exact --source winget --silent `
  --accept-package-agreements --accept-source-agreements --disable-interactivity
winget install --id JanDeDobbeleer.OhMyPosh --exact --source winget --silent `
  --accept-package-agreements --accept-source-agreements --disable-interactivity
```

WinGet 不是所有 Windows 都保證可用：Microsoft 文件指出 `winget` 內建於 Windows 11 與
Windows Server 2025，Windows Server 2022 或更早版本沒有它；App Installer 的首次註冊也可能
非同步。因此腳本應在安裝前驗證 `winget` 可用，失敗時說明此先決條件，而不是假裝
PowerShell 7／Oh My Posh 已成功配置。
[Microsoft：PowerShell with WinGet availability](https://learn.microsoft.com/en-us/powershell/scripting/install/install-powershell-on-windows?view=powershell-7.5)

## 5. 首次 bootstrap 的 interpreter 邊界

**[已驗證]** chezmoi 對 `.ps1` 預設先使用 `pwsh -NoLogo -File`，`pwsh` 不存在時退回
Windows PowerShell `powershell`；`.ps1.tmpl` 在 template rendering 後仍以 `.ps1` 判定
interpreter。
[chezmoi：Interpreters](https://www.chezmoi.io/reference/configuration-file/interpreters/)

**推論：** 首次安裝情境中，Windows 安裝 script 可能在 Windows PowerShell 5.1 執行，然後才
安裝 PowerShell 7。因此 provisioning `.ps1.tmpl` 必須避免尚未被保證存在的 `pwsh` 與
PowerShell 7-only syntax；profile 本身才是只由 PowerShell 7 載入的配置。套件完成後的
驗證必須在**新開的** `pwsh` session 執行，因為現有 process 的 PATH／app-execution alias
不一定已更新。

## 6. SPEC 必須新增的可驗證行為

| 行為 | 自動驗證名稱（建議） | 實機驗證 |
| --- | --- | --- |
| Windows source state 不輸出 zsh、Oh My Zsh、Powerlevel10k artifacts，Linux/macOS 保持輸出 | `test_windows_renders_powershell_not_zsh_shell_config` | `chezmoi managed` 與 `chezmoi diff` |
| Windows install script 精確安裝兩個 package ID，並含無互動 flag | `Test-WingetShellPackageContract` | 新 Windows x64 machine 的 `winget` log |
| PowerShell 7 profile 的路徑與 content 是 `pwsh` + Oh My Posh `powerlevel10k_rainbow` + `--strict` init | `Test-PwshProfileManagedBlockPreservesUserContent`, `Test-OhMyPoshThemeContract` | 新 pwsh session；隔離帳戶的 cache-miss theme resolution |
| 不以 bootstrap 修改 machine-wide execution policy，且 policy 阻擋時不誤報成功 | `Test-ProfilePolicyFailureIsVisible` | 受限 policy Windows machine |

上述測試名稱是本研究對 Tier 3 SPEC 的建議，不是已存在的測試或已完成的實作。實機檢查不取代
RED/GREEN 自動測試；兩者都須在 evidence report 中各自留下命令與結果。

## 7. `powerlevel10k_rainbow` theme pointer

- **[已驗證]** Oh My Posh 的 `--config` 可接受三種值：本機設定檔路徑、沒有副檔名的
  theme pointer、或遠端 URL。因此使用者指定的
  `--config powerlevel10k_rainbow` 是有效的 theme-pointer 形式；官方 bundled themes
  清單也包含 `powerlevel10k_rainbow`。
  [Oh My Posh：Customize](https://ohmyposh.dev/docs/installation/customize)
  [Oh My Posh：Themes](https://ohmyposh.dev/docs/themes)
- **[已驗證]** 使用 theme 名稱或遠端 URL 時，Oh My Posh 在 shell 啟動會下載設定，必須有
  active internet connection；雖有 cache，官方為效能建議使用本機設定檔。
  [Oh My Posh：theme-name and URL behavior](https://ohmyposh.dev/docs/installation/customize)
- **[已驗證]** `--strict` 是官方針對 package-manager 升級後舊 absolute executable path
  的保護，且官方要求對各 shell 使用等價的 init command。
  [Oh My Posh：package-manager initialization](https://ohmyposh.dev/docs/installation/prompt#package-managers)
- **[已驗證]** 官方只明確說名稱包含 `minimal` 的 theme 不需要 Nerd Font；
  `powerlevel10k_rainbow` 不屬於此類。因此本 repo 不將字型當成 bootstrap dependency，
  但 README 必須告知使用者：若 glyph 顯示異常，選用 Nerd Font。
  [Oh My Posh：Themes and fonts](https://ohmyposh.dev/docs/themes)

**推論：** 選擇使用者要求的 theme pointer，而非改成儲存本機副本，故受管理區塊應是：

```powershell
oh-my-posh init pwsh --config 'powerlevel10k_rainbow' --strict | Invoke-Expression
```

這保留指定 theme，又延續既有 `--strict` 升級安全性。Tier 3 實機 acceptance 必須以隔離
帳戶在 cache miss 與網路可用的情況新開 `pwsh` 驗證 theme 可解析；快取命中只能驗證後續
啟動，不能替代首次下載證據。

## 8. Windows Sandbox 初始狀態量測（使用者提供）

> 量測日期：2026-09-01；以下為使用者在可拋棄、乾淨的 Windows Sandbox 量得的結果，
> 並非本 agent 在該 Sandbox 的獨立重跑。

| 量測項目 | 結果 |
| --- | --- |
| OS / architecture | Windows build 26100、AMD64 |
| 初始 PowerShell | Windows PowerShell Desktop 5.1.26100.9168 |
| `LOCALAPPDATA` | `C:\\Users\\WDAGUtilityAccount\\AppData\\Local` |
| `USERPROFILE` | `C:\\Users\\WDAGUtilityAccount` |
| `winget`, `pwsh`, `chezmoi`, `git`, `nvim` | 均不存在 |
| App Installer | 不存在 |
| network | HTTP 200 |

**已觀察到：** 即使網路可用，首次 bootstrap 在這個 image 只有 Windows PowerShell
5.1，且 README 原本直接執行 `winget install` 時沒有前置檢查。這證實「先在 5.1 解釋
`.ps1`、再安裝 pwsh」不是假設；也提供了缺 WinGet 的實際失敗案例。

**限制：** Windows Sandbox 刻意排除 Store 應用，因而沒有 App Installer。它比一般乾淨
Windows 11 更精簡，不能外推為「所有 Windows 11 都缺 WinGet」。此量測應用來驗證可操作的
preflight failure，而不是收窄 Windows 10/11 x64 的支援宣告。

**推論：** README 在第一次 `winget` 使用前，及 Windows package script 在第一個 package
install 前，都必須檢查 `Get-Command winget -ErrorAction SilentlyContinue`。失敗訊息須明說
App Installer、要求安裝或修復後重跑，並確保尚未開始任何 package install。所有這個時點可
執行的 provisioning `.ps1.tmpl` 都必須維持 Windows PowerShell 5.1 相容語法。

## 9. 可重跑與不可重跑的 Windows 證據邊界

使用者另確認：相鄰的 Windows 11 AMD64 主機有 pwsh 7.6.5、WinGet 1.29.290 與
chezmoi 2.72.0，且 Windows chezmoi 已能透過 WSL UNC source 對本 worktree 執行
`--dry-run --destination <temp> apply`，並成功 render `10-install-packages.ps1`。這是
source rendering evidence，不是 package-install evidence。

目前 agent 執行環境對 `pwsh.exe` 的唯讀 WSL interop 探測在 vsock bind 失敗，故無法獨立
重跑主機端命令。依使用者限制，不得在該主機執行真實 `winget install`；此項驗收只能在
Windows Sandbox 或 CI 進行。最終 evidence report 必須分開記錄：本機 source rendering、
Windows PowerShell 5.1 的 CI/Sandbox 前置條件測試、以及真實安裝 health check；其中任何
一項未執行都不能表述為已通過。
