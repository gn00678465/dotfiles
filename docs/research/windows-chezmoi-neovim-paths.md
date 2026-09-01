# Windows chezmoi、Neovim 與 Winget 研究

> 研究日期：2026-09-01。本文只採用各專案的官方文件、原始碼與 Microsoft
> WinGet 預設來源的 manifest。**[已驗證]** 表示來源直接陳述或宣告了該事實；
> **[推論]** 表示由已驗證事實導出的本 repo 實作結論。

---

## 0. 結論

- **[已驗證]** Windows 上 chezmoi 依副檔名選擇腳本執行方式；`.ps1` 預設由
  `pwsh -NoLogo -File` 執行，沒有 `pwsh` 時才退回 Windows PowerShell
  `powershell`。`.sh` 不是內建對應的副檔名。
  [chezmoi Interpreters](https://www.chezmoi.io/reference/configuration-file/interpreters/)
- **[推論]** 現有 Unix `.sh.tmpl` 安裝腳本不能在 Windows 直接重用；Windows
  應有獨立、以 `.ps1.tmpl` 結尾的腳本，或明確設定 `interpreters.sh` 並安裝其
  shell。前者不依賴 Git Bash／WSL，較符合 Windows 原生安裝路徑。
- **[已驗證]** 本 repo 釘定的 Neovim 0.12.5 在未設定 XDG 覆寫時，設定目錄是
  `%LOCALAPPDATA%\nvim`，資料與 state 都是 `%LOCALAPPDATA%\nvim-data`，cache
  是 `%TEMP%\nvim`。
  [Neovim v0.12.5 `stdpaths.c`](https://github.com/neovim/neovim/blob/v0.12.5/src/nvim/os/stdpaths.c#L29-L62)
- **[推論]** 首次安裝／重置 LazyVim 時，`nvim-data` 只能備份一次：它同時是
  `stdpath('data')` 和 `stdpath('state')` 的預設目錄。Tree-sitter parser 的預設位置
  因此是 `%LOCALAPPDATA%\nvim-data\site\parser`。
- **[已驗證]** `nvim-treesitter` 的 `main` 分支需要 `tree-sitter-cli >= 0.26.1`
  （不可用 npm 版）與 PATH 上的 C compiler；LazyVim 目前也明確使用該 `main`
  分支。
  [nvim-treesitter requirements](https://github.com/nvim-treesitter/nvim-treesitter#requirements)
  [LazyVim tree-sitter 設定](https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/plugins/treesitter.lua)
- **[已驗證]** `nvim-treesitter` 實際執行的是 `tree-sitter build`；該 CLI 在
  Windows MSVC target 透過 `cc-rs` 尋找 Visual Studio。因此若要宣稱「完整
  原生 Windows bootstrap」，必須安裝 C++ Build Tools，而非只安裝
  `tree-sitter-cli`。
  [nvim-treesitter install source](https://github.com/nvim-treesitter/nvim-treesitter/blob/main/lua/nvim-treesitter/install.lua#L304-L315)
  [tree-sitter loader source](https://github.com/tree-sitter/tree-sitter/blob/master/crates/loader/src/loader.rs#L1240-L1325)
  [cc-rs Windows requirements](https://docs.rs/cc/latest/cc/#compile-time-requirements)

---

## 1. chezmoi Windows script 契約

### 1.1 副檔名與 PowerShell

- **[已驗證]** Windows 原生可直接執行的副檔名只有 `.bat`、`.cmd`、`.com`、`.exe`；
  其他副檔名需要 PATH 上的 interpreter。chezmoi 內建 `.ps1` 對應 `pwsh`，參數為
  `-NoLogo -File`；可在 chezmoi 設定覆寫 interpreter。
  [chezmoi Interpreters](https://www.chezmoi.io/reference/configuration-file/interpreters/)
- **[已驗證]** `.ps1.tmpl` 會先移除 `.tmpl`，再以剩餘 `.ps1` 副檔名判斷 interpreter；
  所以它是 Windows 專用 template script 的正確命名形式。
  [chezmoi Interpreters](https://www.chezmoi.io/reference/configuration-file/interpreters/)
- **[已驗證]** `.tmpl` 算繪為空白時，chezmoi 不會執行該 script；`run_onchange_`
  只有在內容相較上次「成功執行」後變更才會跑，且所有 script（包括 `run_onchange_`
  與 `run_once_`）都必須 idempotent。
  [chezmoi scripts](https://www.chezmoi.io/user-guide/use-scripts-to-perform-actions/)
- **[推論]** Windows script 的 template 外層應以
  `{{ if eq .chezmoi.os "windows" }}` 篩選；相反地，現有 Unix script 也必須在
  Windows 算繪為空，避免 chezmoi 嘗試用未設定的 `.sh` interpreter 執行它。

### 1.2 權限與等待

- **[已驗證]** 若 PowerShell script 自我提升權限，必須等待提升後的 process 結束；
  否則 chezmoi 會在它尚未完成時往下一步走。官方範例使用
  `Start-Process -Wait`。
  [chezmoi Windows guide](https://www.chezmoi.io/user-guide/machines/windows/)
- **[已驗證]** 既有工具對應的 `GitHub.GitLFS` manifest 是 `Scope: machine`；完整
  Tree-sitter 支援所需的 Visual Studio Build Tools 也需系統管理員權限。不能把
  Windows 的本次安裝流程一概假定為 user scope 或無需 elevation。
  [Git LFS manifest](https://github.com/microsoft/winget-pkgs/blob/master/manifests/g/GitHub/GitLFS/3.7.1/GitHub.GitLFS.installer.yaml)
  [Microsoft C++ Build Tools acquisition](https://learn.microsoft.com/en-us/cpp/overview/acquire-msvc)
- **[推論]** Windows 安裝 script 必須把任何 machine-scope 的 WinGet 呼叫放進已
  提升、且以 `Start-Process -Wait` 等待完成的程序；否則 chezmoi 可能在套件仍在安裝
  時繼續跑後續步驟。使用者拒絕提升時，應使完整 Nvim bootstrap 失敗並明確指出
  原因，不能把它誤報成成功。

---

## 2. Neovim 0.12.5 Windows 路徑

### 2.1 實作應使用的值

下表假定 `NVIM_APPNAME` 未設定且對應 `XDG_*_HOME` 未覆寫。Neovim 會以
`LOCALAPPDATA` 與 `TEMP` 作為 Windows 的 fallback；Windows 對 data 與 state 加上
`-data` 後綴，但 config 與 cache 不加。
[v0.12.5 source: fallback variables](https://github.com/neovim/neovim/blob/v0.12.5/src/nvim/os/stdpaths.c#L29-L62)
[v0.12.5 source: app-specific suffixes](https://github.com/neovim/neovim/blob/v0.12.5/src/nvim/os/stdpaths.c#L152-L221)

| `stdpath()` | Windows default | PowerShell 表示式 | 首次 LazyVim bootstrap 的處理（推論） |
| --- | --- | --- | --- |
| `config` | `%LOCALAPPDATA%\nvim` | `Join-Path $env:LOCALAPPDATA 'nvim'` | 備份；clone starter 到此處；marker 也在此處。 |
| `data` | `%LOCALAPPDATA%\nvim-data` | `Join-Path $env:LOCALAPPDATA 'nvim-data'` | 備份一次。 |
| `state` | `%LOCALAPPDATA%\nvim-data` | 同 `data` | 不可再備份一次，因為與 `data` 是同一路徑。 |
| `cache` | `%TEMP%\nvim` | `Join-Path $env:TEMP 'nvim'` | 備份。 |

- **[已驗證]** `NVIM_APPNAME` 可將以上路徑中的 `nvim` 子目錄改成另一個名稱／相對
  路徑；若使用者設定它，硬編碼的預設路徑不再正確。
  [Neovim standard paths](https://neovim.io/doc/user/starting/#standard-path)
- **[推論]** bootstrap script 應先以 `nvim --headless` 查詢實際 `stdpath()`，或至少
  清楚宣告只支援未設定 `NVIM_APPNAME`／`XDG_*_HOME` 的預設情況；否則會備份錯誤目錄。

### 2.2 官方文件與 runtime 的 cache 矛盾

- **[已驗證]** Neovim 現行線上 `:help standard-path` 的 Windows 表格將 cache 列為
  `~/AppData/Local/Temp/nvim-data`。
  [Neovim standard paths](https://neovim.io/doc/user/starting/#standard-path)
- **[已驗證]** 但本 repo 安裝的 0.12.5 原始碼只對 data 與 state 加 `-data`，cache
  的 fallback 是 `TEMP`；其實際結果是 `%TEMP%\nvim`。
  [Neovim v0.12.5 `get_xdg_home`](https://github.com/neovim/neovim/blob/v0.12.5/src/nvim/os/stdpaths.c#L152-L221)
- **[推論]** 此 repo 的實作與測試必須以前者的 runtime 版本 0.12.5 為準，而不能照現行
  線上 help 備份 `%TEMP%\nvim-data`。升級 Neovim pin 時需重新驗證這一點。

### 2.3 LazyVim 與 parser 的落點

- **[已驗證]** LazyVim 的 Windows installation instructions 以
  `$env:LOCALAPPDATA\nvim` 與 `$env:LOCALAPPDATA\nvim-data` 作為清理／備份的兩個
  路徑，並將 starter clone 到前者。
  [LazyVim installation](https://www.lazyvim.org/installation)
- **[已驗證]** `nvim-treesitter` 預設把 parser 與 query 裝進
  `vim.fn.stdpath('data') .. '/site'`。據 §2.1 的 v0.12.5 runtime，Windows 預設根目錄
  為 `%LOCALAPPDATA%\nvim-data\site`。
  [nvim-treesitter setup](https://github.com/nvim-treesitter/nvim-treesitter#setup)

---

## 3. Winget package IDs 與 executable identity

**[已驗證]** 以下是 Microsoft WinGet 預設來源於研究日期所列的 canonical `PackageIdentifier`；Windows
script 應使用 `winget install --id <ID> --exact --source winget`，不要以顯示名稱
比對。非互動 script 還需要 `--silent`、`--accept-package-agreements` 與
`--accept-source-agreements`：前者抑制 installer UI，兩個 agreement flag 分別處理
package EULA 與 source terms；`--disable-interactivity` 不能取代 `--silent`。
[WinGet install command](https://learn.microsoft.com/en-us/windows/package-manager/winget/install)

| 既有 brew formula | WinGet ID | 發行檔／預期 command | manifest 證據 |
| --- | --- | --- | --- |
| `mise` | `jdx.mise` | `mise.exe`，明確 portable alias：`mise` | [manifest](https://github.com/microsoft/winget-pkgs/blob/master/manifests/j/jdx/mise/2026.8.5/jdx.mise.installer.yaml) |
| `fzf` | `junegunn.fzf` | `fzf.exe` | [manifest](https://github.com/microsoft/winget-pkgs/blob/master/manifests/j/junegunn/fzf/0.74.3/junegunn.fzf.installer.yaml) |
| `git-lfs` | `GitHub.GitLFS` | `git-lfs.exe`；現有 repo 的後續設定契約是 `git-lfs install --skip-repo`；此 manifest 為 machine scope | [manifest（並宣告相依 `Git.Git`）](https://github.com/microsoft/winget-pkgs/blob/master/manifests/g/GitHub/GitLFS/3.7.1/GitHub.GitLFS.installer.yaml) |
| `ripgrep` | `BurntSushi.ripgrep.MSVC` | `rg.exe`，明確 portable alias：`rg` | [manifest](https://github.com/microsoft/winget-pkgs/blob/master/manifests/b/BurntSushi/ripgrep/MSVC/15.2.0/BurntSushi.ripgrep.MSVC.installer.yaml) |
| `fd` | `sharkdp.fd` | `fd.exe` | [manifest](https://github.com/microsoft/winget-pkgs/blob/master/manifests/s/sharkdp/fd/10.5.0/sharkdp.fd.installer.yaml) |
| `lazygit` | `JesseDuffield.lazygit` | `lazygit.exe` | [manifest](https://github.com/microsoft/winget-pkgs/blob/master/manifests/j/JesseDuffield/lazygit/0.64.1/JesseDuffield.lazygit.installer.yaml) |
| `tree-sitter` | `tree-sitter.tree-sitter-cli` | `tree-sitter.exe`，明確 portable alias：`tree-sitter` | [manifest](https://github.com/microsoft/winget-pkgs/blob/master/manifests/t/tree-sitter/tree-sitter-cli/0.26.12/tree-sitter.tree-sitter-cli.installer.yaml) |
| `git`（Windows 額外 prerequisite） | `Git.Git` | manifest 明確宣告 command：`git` | [manifest](https://github.com/microsoft/winget-pkgs/blob/master/manifests/g/Git/Git/2.55.0.3/Git.Git.installer.yaml) |

- **[已驗證]** 上表的 ID、nested executable 與明確標示的
  `PortableCommandAlias` 來自各 manifest；WinGet schema 定義
  `PortableCommandAlias` 為 portable package 的呼叫 alias。
  [WinGet manifest schema](https://github.com/microsoft/winget-cli/blob/master/schemas/JSON/manifests/latest/manifest.singleton.latest.json)
- **[已驗證]** `GitHub.GitLFS` manifest 本身宣告 `Git.Git` 套件相依性，故即使
  script 先安裝 LFS，WinGet 仍知道它需要 Git。
  [Git LFS manifest](https://github.com/microsoft/winget-pkgs/blob/master/manifests/g/GitHub/GitLFS/3.7.1/GitHub.GitLFS.installer.yaml)
- **[已驗證]** `fzf`、`fd` 與 `lazygit` 的目前 manifests 只列出發行檔，沒有
  `PortableCommandAlias`；因此表中的 command 是檔名身份，並非 manifest 宣告的 alias。
  [fzf](https://github.com/microsoft/winget-pkgs/blob/master/manifests/j/junegunn/fzf/0.74.3/junegunn.fzf.installer.yaml)
  [fd](https://github.com/microsoft/winget-pkgs/blob/master/manifests/s/sharkdp/fd/10.5.0/sharkdp.fd.installer.yaml)
  [lazygit](https://github.com/microsoft/winget-pkgs/blob/master/manifests/j/JesseDuffield/lazygit/0.64.1/JesseDuffield.lazygit.installer.yaml)
- **[推論]** 包裝安裝完成後必須以新 PowerShell session 的
   `Get-Command mise,fzf,git-lfs,rg,fd,lazygit,tree-sitter,git` 驗證，而非只依賴
  `winget install` 成功。WinGet 對 portable aliases 的連結／PATH 處理仍有已公開的
  client 問題。
  [WinGet portable alias issue](https://github.com/microsoft/winget-cli/issues/6058)
- **[已驗證]** 現代 Windows 內建 `tar` 與 `curl`，這兩個亦是
  `nvim-treesitter` 必要項。Windows PowerShell 5.1 的 `curl` 是
  `Invoke-WebRequest` alias；若 PowerShell script 本身需呼叫真正的 curl，必須寫成
  `curl.exe`。而 nvim-treesitter 對外部 process 的需求是可解析的 `curl`／`tar`
  executable，不會經過這個 PowerShell alias。
  [tar on Windows](https://learn.microsoft.com/en-us/windows/tar/)
  [curl on Windows](https://learn.microsoft.com/en-us/windows/curl/)
  [nvim-treesitter requirements](https://github.com/nvim-treesitter/nvim-treesitter#requirements)

---

## 4. LazyVim／Tree-sitter 的 Windows C compiler 決策

- **[已驗證]** `nvim-treesitter` `main` 要求 Neovim 0.12+、`tar`、`curl`、
  版本至少 0.26.1 的 package-manager 安裝版 `tree-sitter-cli`，以及 PATH 上 C compiler；
  parser 版本與 plugin 版本必須同步，升級 plugin 後要執行 `:TSUpdate`。
  [nvim-treesitter requirements and update contract](https://github.com/nvim-treesitter/nvim-treesitter#requirements)
- **[已驗證]** LazyVim 將 `nvim-treesitter` 設為 `branch = "main"`，關閉 release
  version，註解明示最後的 release 在 Windows 不可用；它在 build 時執行更新，並拒絕
  `nvim-treesitter.install.compilers` 的舊式設定。
  [LazyVim tree-sitter source](https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/plugins/treesitter.lua)
- **[已驗證]** 該 compiler 不是 tree-sitter CLI 或 WinGet 自動提供的：`cc-rs` 對
  Windows MSVC target 要求 Visual Studio；若自動尋找失敗，`cl.exe` 必須在 PATH
  （通常透過 Developer Tools shell）。Windows MinGW target 則要求 `cc` 在 PATH。
  [cc-rs compile-time requirements](https://docs.rs/cc/latest/cc/#compile-time-requirements)
- **[已驗證]** `tree-sitter build` 的 loader 使用 `cc::Build`，沒有
  nvim-treesitter 的 compiler 設定欄位可將它改成另一套工具；`cc-rs` 會嘗試自行
  定位 Visual Studio。在成功定位的情況，正常（非 Developer）PowerShell 開啟的
  Nvim 不需要 `cl.exe` 在 PATH，也不需要持久化的 Nvim 設定或 `CC` 環境變數。
  [tree-sitter loader compile path](https://github.com/tree-sitter/tree-sitter/blob/master/crates/loader/src/loader.rs#L1240-L1325)
  [cc-rs environment configuration](https://docs.rs/cc/latest/cc/#external-configuration-via-environment-variables)
  [cc-rs Windows requirements](https://docs.rs/cc/latest/cc/#compile-time-requirements)
- **[推論]** 本 repo 的完整原生 Windows 策略應選擇 **Visual Studio 2022 Build Tools**
  （WinGet ID `Microsoft.VisualStudio.2022.BuildTools`）加上 **Desktop development
  with C++** workload（`Microsoft.VisualStudio.Workload.VCTools`），而不是依賴使用者
  每次從 Developer PowerShell 啟動 Nvim。該 workload 的官方說明明確涵蓋 MSVC。
  [Build Tools manifest](https://github.com/microsoft/winget-pkgs/blob/master/manifests/m/Microsoft/VisualStudio/2022/BuildTools/17.14.21/Microsoft.VisualStudio.2022.BuildTools.installer.yaml)
  [VCTools workload ID](https://learn.microsoft.com/en-us/visualstudio/install/workload-component-id-vs-build-tools?view=vs-2022)
- **[推論]** 適用於首次安裝的命令形狀是：

  ```powershell
  winget install --id Microsoft.VisualStudio.2022.BuildTools --exact --source winget `
    --accept-package-agreements --accept-source-agreements `
    --override "--quiet --wait --norestart --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended"
  ```

  `--override` 會原封不動交給 Visual Studio installer，因此 `--quiet`、`--wait` 與
  workload 參數必須放在 override 字串內；Visual Studio 官方也明確指定：未加
  override 時 WinGet 只安裝 core workload，且 installer 操作需要 elevation。
  [Visual Studio command-line parameters](https://learn.microsoft.com/en-us/visualstudio/install/use-command-line-parameters-to-install-visual-studio?view=vs-2022)
- **[推論]** 這個選擇仍必須有實機 health gate：在**新的普通 PowerShell session** 依序
  執行 `tree-sitter --version`、`nvim --headless "+TSUpdate" +qa`，再跑
  `nvim --headless "+checkhealth nvim-treesitter" +qa`。任一步失敗表示此 machine
  沒有達成完整 Tree-sitter 支援，不能以「已裝 tree-sitter CLI」宣告成功。若不願加入
  machine-scope Build Tools／elevation，應把 Windows 支援範圍明確降為「Nvim 與
  LazyVim 可啟動，但 parser build 不受支援，health check 預期失敗」。
- **[推論]** `CC` 是 `cc-rs` 支援的替代 compiler hook，但它只是 process environment
  variable，不該成為本 repo 的隱性使用者前提；若未來選擇非 MSVC toolchain，必須讓
  script 以可驗證的方式 provision 它、在新 session 驗證，並重新做 x64／ARM64 實機
  相容性測試。
  [cc-rs `CC` contract](https://docs.rs/cc/latest/cc/#external-configuration-via-environment-variables)
- **[推論]** 上游維護者對 Windows `main` 的建議是 Visual Studio Build Tools 的「Desktop
  development with C++」，不要再設定已失效的 `nvim-treesitter.install.compilers`。
  [nvim-treesitter maintainer answer](https://github.com/nvim-treesitter/nvim-treesitter/discussions/7920)
- **[推論]** C compiler 與 Neovim 必須為同一架構；特別是 Windows on ARM 若使用 x64
  Neovim，編出的 ARM64 parser 無法被 x64 Neovim 載入。這個 repo 應先把 Windows
  支援範圍限定為 x64，或在 ARM64 加入實機驗證後才宣稱支援。
  [nvim-treesitter Windows-on-ARM discussion](https://github.com/nvim-treesitter/nvim-treesitter/discussions/8063)

---

## 5. 實作前後檢查清單

1. **[推論]** 用 `.ps1.tmpl` 寫 Windows 安裝流程，且讓非目標 OS 的 scripts 算繪為空。
2. **[推論]** 安裝第 3 節所有 canonical IDs，重新開啟 PowerShell，再以
   `Get-Command` 逐一驗證 executable identity。
3. **[推論]** 以提升權限且有限等待的程序安裝 VCTools；在新的普通 PowerShell
   session 跑 §4 的 `tree-sitter`／Nvim health gate。拒絕 elevation 或 gate 失敗時，
   不得宣稱完整 Windows Nvim bootstrap 成功。
4. **[推論]** 只在不存在 repo marker 時備份 `%LOCALAPPDATA%\nvim`、
   `%LOCALAPPDATA%\nvim-data`、`%TEMP%\nvim`；不把 data 與 state 視為兩個目錄。
5. **[推論]** 在實際 Windows 環境跑 `nvim --headless` 查詢四個 `stdpath()`，確認沒有
   `NVIM_APPNAME`／XDG 覆寫；之後首次互動式開啟 Nvim，執行 `:checkhealth
   nvim-treesitter` 驗證 `tree-sitter` 與 compiler。
