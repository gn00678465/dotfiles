# native Windows 支援研究

> 比照 `docs/research/chezmoi-templates-partial-config.md` 與
> `docs/research/nvim-treesitter-mise-lazyvim-debian-errors.md` 的體例。
>
> **這份筆記有實測環境。** 標「**實測**」的每一條都是在下面這組機器上真的跑出來的：
>
> - WSL2 Debian 12（distro 名 `agent`），Windows 11 **25H2** 主機
> - chezmoi **v2.72.0**（WSL 與 Windows 兩端同版本；Windows 端是 winget 裝的
>   `twpayne.chezmoi`）
> - PowerShell **7.6.5**、Windows PowerShell **5.1**、winget **v1.29.290**
> - Neovim **0.12.5**（Windows 端由 mise 安裝）、mise **2026.8.14 windows-x64**
>
> 沒有實測的地方會明講「未證實」或「查不到」。
> **本 repo 沒有 macOS 實機**，這份筆記完全不涉及 macOS。

---

## 0. 先講結論（Answer first）

| # | 主題 | 結論 |
|---|---|---|
| 1 | chezmoi 在 Windows 怎麼執行 `.ps1` | 預設 interpreter 就是 `pwsh -NoLogo -File`（**不是** Windows PowerShell 5.1）。所以 pwsh 7 必須在第一次 apply 之前就存在，這是自舉腳本的責任。 |
| 2 | 渲染成空的腳本 | **會被靜默跳過**，Linux 與 Windows 兩端皆然。這是這個 repo 唯一可行的跨平台隔離手段。 |
| 3 | 非空的 `.sh` 在 Windows | **硬失敗並中斷整個 apply**：`fork/exec ...: %1 is not a valid Win32 application`，exit 1。所以 `.sh` 在 Windows 上必須渲染成空，靠 `.chezmoiignore` 擋是不夠的（腳本被 ignore 就等於整支不存在，但那會讓「該跑的平台」也一起失去它）。 |
| 4 | `modify_` 腳本在 Windows | 同樣會被 exec，同樣失敗。要跨平台就必須寫成 **modify-template**（純模板），由 chezmoi 自己算繪，完全不 exec。 |
| 5 | Neovim 的 Windows 路徑 | config = `%LOCALAPPDATA%\nvim`；**data、state、log 三者是同一個目錄** `%LOCALAPPDATA%\nvim-data`；cache = `%TEMP%\nvim`。**官方文件與 0.12.5 實際行為在 cache 這一項不一致**（見 §2）。 |
| 6 | pwsh 的 `$PROFILE` | 落在 Documents 已知資料夾底下，**可能被 OneDrive 轉向**。chezmoi 的 target 路徑由來源檔名決定、不能用模板算，所以不能直接管它。 |
| 7 | winget 非互動安裝 | `--exact --id <ID> --source winget --silent --accept-package-agreements --accept-source-agreements --disable-interactivity`。`--source winget` 是必要的，否則同名套件會停在「選擇來源」的提示。 |
| 8 | mise 的全域設定檔 | Windows 上一樣是 `~/.config/mise/config.toml`（**不是** `%APPDATA%`）。 |
| 9 | uv 的使用者設定檔 | Windows 上是 `%APPDATA%\uv\uv.toml`（與 POSIX 的 `~/.config/uv/uv.toml` **不同**）。 |
| 10 | oh-my-posh 主題定位 | `$env:POSH_THEMES_PATH` **不可靠**（Store 版會指向一個不存在的目錄，實測）。主題應該自己釘版本抓下來。 |
| 11 | Windows PowerShell 5.1 的編碼 | 用 **ANSI 代碼頁**解無 BOM 的 `.ps1`。非 ASCII 註解會被解壞成**語法錯誤**。 |
| 12 | Windows 建 symlink | 需要 `SeCreateSymbolicLinkPrivilege`，一般帳號要開「開發人員模式」才有。 |
| 13 | nvim-treesitter 的 C compiler | `main` 分支用 `tree-sitter build` 編 parser，Windows 上預設找 MSVC 的 `cl.exe`。zig 是社群在用的替代路徑，**本 repo 未證實**。 |

---

## 1. chezmoi 在 Windows 的腳本語意

### 1.1 預設 interpreter（**實測**）

`chezmoi dump-config --format json` 在 **Linux 與 Windows 兩端**吐出的 `interpreters`
完全一樣：

```json
"ps1": { "command": "pwsh", "args": ["-NoLogo", "-File"] }
```

兩個直接的後果：

- **`pwsh` 是 PowerShell 7，不是 Windows PowerShell 5.1**（5.1 的執行檔叫
  `powershell.exe`）。Windows 11 內建的是 5.1，7 要另外裝。所以自舉腳本必須先把
  pwsh 7 裝起來，chezmoi 才跑得動任何 `.ps1`。
- **Linux 端也有這個對應**。也就是說，一支非空的 `.ps1` 放進 `.chezmoiscripts/`，
  chezmoi 在 Linux 上也會嘗試用 `pwsh` 執行它。跨平台隔離不能只靠「副檔名不同」。

### 1.2 渲染成空的腳本會被跳過（**實測**）

探針來源樹裡放一支被 `{{ if eq .chezmoi.os "linux" }}` 包住的 `.ps1.tmpl`，在 Linux 上
`chezmoi apply`：腳本沒有被執行、沒有錯誤訊息、`apply` exit 0。反過來在 Windows 上放
被 `{{ if eq .chezmoi.os "linux" }}` 包住的 `.sh.tmpl`，結果相同。

**這是本 repo 的跨平台隔離手段。** 每一支平台專屬的腳本都整支包在平台守衛裡，
在別的平台上渲染成空，chezmoi 就當它不存在。

### 1.3 非空的 `.sh` 在 Windows 上會中斷整個 apply（**實測**）

同一個探針來源樹，放一支**沒有**平台守衛的 `.sh`，在 Windows 上 `chezmoi apply`：

```
chezmoi: .chezmoiscripts/15-always.sh: fork/exec C:\Users\...\Temp\2686758162.15-always.sh:
%1 is not a valid Win32 application.
```

exit code 1，而且**它後面的腳本一支都沒跑**（同一次 apply 裡排在它後面的 `.ps1`
沒有留下任何痕跡）。這不是「跳過一支腳本」，是整個 apply 停在那裡。

### 1.4 `modify_` 也是腳本（**實測 + 文件**）

`modify_` 的來源檔預設會被當成**腳本**：chezmoi 先把它當模板算繪，再把算繪結果當成
可執行檔跑起來，把 target 現有內容從 stdin 餵進去、收 stdout 當新內容。副檔名決定
interpreter，跟 `run_` 腳本同一套規則。

所以 `dot_codex/modify_private_config.toml` 這種 `#!/bin/sh` + awk 的寫法在 Windows 上
一定失敗（副檔名 `.toml` 沒有對應的 interpreter，chezmoi 直接 exec，得到 §1.3 那個錯誤）。

**例外是 modify-template**：算繪結果若以 `chezmoi:modify-template` 這個標記開頭，
chezmoi 就把算繪結果**直接當成新內容**，完全不執行任何東西。
（[target-types → Modify file](https://www.chezmoi.io/reference/target-types/#modify-file)）
這是唯一一種三個平台共用同一份實作的寫法。

### 1.5 從 WSL 用 UNC 路徑當 source（**實測**）

Windows 端的 chezmoi 可以直接把 WSL 裡的目錄當來源樹：

```powershell
chezmoi --source '\\wsl.localhost\agent\home\madao\...\windows-support' execute-template '{{ .chezmoi.os }}'
# -> windows
```

`.chezmoi.sourceDir` 會變成 `//WSL.LOCALHOST/AGENT/home/...`。這讓「在 WSL 裡改、在
Windows 上驗」不需要任何同步步驟，本 repo 的 L8 測試層就是靠這個做的。

---

## 2. Neovim 在 Windows 的 standard-path

### 2.1 官方文件（逐字）

`runtime/doc/starting.txt`（v0.12.5 tag）的 `*standard-path*` 一節：

```
CONFIG DIRECTORY (DEFAULT) ~
    Windows:      ~/AppData/Local             ~/AppData/Local/nvim
DATA DIRECTORY (DEFAULT) ~
    Windows:      ~/AppData/Local             ~/AppData/Local/nvim-data
STATE DIRECTORY (DEFAULT) ~
    Windows:      ~/AppData/Local             ~/AppData/Local/nvim-data
CACHE DIRECTORY (DEFAULT) ~
    Windows:      ~/AppData/Local/Temp        ~/AppData/Local/Temp/nvim-data
LOG FILE (DEFAULT) ~
    Windows:      ~/AppData/Local/nvim-data   ~/AppData/Local/nvim-data/nvim.log
```

同段另有一句：「Note that `stdpath("log")` is currently an alias for `stdpath("state")`.」

### 2.2 實際跑出來的值（**實測**，nvim 0.12.5 Windows）

用 `nvim --headless -l probe.lua` 直接問 `vim.fn.stdpath()`：

```
config = C:\Users\gn006\AppData\Local\nvim
data   = C:\Users\gn006\AppData\Local\nvim-data
state  = C:\Users\gn006\AppData\Local\nvim-data
cache  = C:\Users\gn006\AppData\Local\Temp\nvim
log    = C:\Users\gn006\AppData\Local\nvim-data
```

### 2.3 兩者不一致的地方

**cache**：文件寫 `~/AppData/Local/Temp/nvim-data`，0.12.5 實際吐 `...\Temp\nvim`。
本 repo 依實測值（`%TEMP%\nvim`）。查不到這個差異對應的 issue 或 commit，所以不知道是
文件沒跟上程式碼、還是相反；只知道 0.12.5 這個版本的行為是什麼。

### 2.4 對安裝腳本的直接影響

POSIX 端要備份**四個**目錄（config / data / state / cache 各自獨立），
Windows 端只有**三個**：`nvim`、`nvim-data`、`%TEMP%\nvim`。
state 與 log 就住在 `nvim-data` 裡，不是獨立路徑。照 POSIX 抄成四個並不會壞
（多出來那個目錄不存在，備份函式直接 return），但代表寫的人對 Windows 的路徑理解是錯的，
而錯的理解遲早會變成「某個真的有資料的目錄沒被備份」。

---

## 3. PowerShell profile

### 3.1 `$PROFILE` 的實際值（**實測**）

```
$PROFILE.CurrentUserCurrentHost = C:\Users\gn006\Documents\PowerShell\Microsoft.PowerShell_profile.ps1
$PROFILE.CurrentUserAllHosts    = C:\Users\gn006\Documents\PowerShell\profile.ps1
[Environment]::GetFolderPath("MyDocuments") = C:\Users\gn006\Documents
```

### 3.2 為什麼不能讓 chezmoi 直接管這個檔案

`$PROFILE` 的位置是從 **Documents 已知資料夾**算出來的，而 Documents 可以被 OneDrive
「備份資料夾」功能轉向到 `~\OneDrive\Documents`。轉向之後 `$PROFILE` 會跟著變成
`~\OneDrive\Documents\PowerShell\profile.ps1`。

chezmoi 的 target 路徑**由來源檔名決定，不能用模板計算**。所以來源樹裡放
`Documents/PowerShell/profile.ps1.tmpl` 只能對上「沒有被轉向」的機器；被轉向的機器上
那個檔案會被寫出來、然後靜靜地沒有人載入它。

本機目前**沒有**被轉向（實測，見 §3.1），但這是機器層級的設定，不是可以假設的。

### 3.3 本 repo 的做法

chezmoi 全權管理 `~/.config/powershell/profile.ps1`（一個 chezmoi 自己說了算的路徑），
另一支 `run_after_` 腳本在**執行期**問 pwsh 自己 `$PROFILE.CurrentUserAllHosts` 是什麼，
再往那裡寫一行 loader。一條路徑同時涵蓋兩種機器。

用 `CurrentUserAllHosts`（`profile.ps1`）而不是 `CurrentUserCurrentHost`
（`Microsoft.PowerShell_profile.ps1`）：Windows Terminal、VS Code 的整合終端機、
裸 `pwsh.exe` 是不同的 host，只有 AllHosts 三者都會載入。

### 3.4 `Add-Content` 會把陣列併成一行（**實測**）

寫那一行 loader 時踩到的：

```powershell
$prefix + @('# comment', $loader) | Add-Content -LiteralPath $target
```

預期寫出三行，實際寫出**一行**，內容是把元素用空白接起來：

```
# Added by chezmoi (dotfiles). The real config lives in the file below. . "$HOME/.config/powershell/profile.ps1"
```

`Add-Content -Value <多元素陣列>` 的直接形式也一樣。後果不只是難看：下一次執行時
「這一行已經在了嗎」的比對永遠不成立，於是**每次 apply 都再追加一次**，profile 無限長大。

可靠的寫法是一行一次呼叫。單行的 `$a + @('X','Y') | Add-Content` 在同一台機器上測試
時**又是正常的三行**，所以觸發條件跟多行陣列字面值的剖析有關；查不到官方說明，
這裡只記錄「什麼寫法可靠」，不宣稱知道確切原因。

---

## 4. winget

### 4.1 非互動安裝的旗標

```
winget install --exact --id <ID> --source winget --silent
               --accept-package-agreements --accept-source-agreements --disable-interactivity
```

- `--exact`：關掉前綴/模糊比對。
- `--source winget`：把來源釘在社群 repo。同名套件同時存在於 `msstore` 時，
  不指定來源會停在「需要選擇來源」的互動提示上，而 chezmoi 是無人值守跑腳本的。
- `--silent`：把安裝程式本身的 UI 關掉。
- 兩個 `--accept-*`：第一次使用來源與有授權條款的套件時的確認。
- `--disable-interactivity`：任何殘留的提示一律當失敗，而不是卡住等人。

檢查是否已安裝用 `winget list --exact --id <ID>`，找不到時退出碼非零（**實測**）。

### 4.2 套件 ID（**逐一 `winget show --id <ID> --exact` 實測存在**）

| ID | 名稱 | 當時版本 | 對應 POSIX |
|---|---|---|---|
| `Microsoft.PowerShell` | PowerShell | 7.6.5.0 | zsh |
| `Git.Git` | Git | 2.55.0.3 | git |
| `twpayne.chezmoi` | chezmoi | 2.72.1 | get.chezmoi.io |
| `jdx.mise` | mise-en-place | 2026.8.5 | mise |
| `junegunn.fzf` | fzf | 0.74.3 | fzf |
| `GitHub.GitLFS` | Git LFS | 3.7.1 | git-lfs |
| `BurntSushi.ripgrep.MSVC` | RipGrep MSVC | 15.2.0 | ripgrep |
| `sharkdp.fd` | fd | 10.5.0 | fd |
| `JesseDuffield.lazygit` | lazygit | 0.64.1 | lazygit |
| `tree-sitter.tree-sitter-cli` | tree-sitter-cli | 0.26.12 | tree-sitter |
| `JanDeDobbeleer.OhMyPosh` | Oh My Posh | 31.1.2 | powerlevel10k |
| `zig.zig` | Zig | 0.16.0 | build-essential |

`tree-sitter-cli` 0.26.12 滿足 nvim-treesitter `main` 分支要求的 ≥ 0.26.1
（見 `nvim-treesitter-mise-lazyvim-debian-errors.md` §6）。

**PowerShell Gallery 的模組不在 winget 裡**（例如 PSFzf），要用
`Install-PSResource -Scope CurrentUser -TrustRepository`。`-TrustRepository` 是必要的：
PSGallery 的 `Trusted` 預設是 `False`（**實測**），沒有這個旗標會停在確認提示上。
`Install-PSResource` 隨 PSResourceGet 一起出貨，PowerShell 7.4 以後內建
（本機實測 pwsh 7.6.5 帶 PSResourceGet 1.2.0）。

### 4.3 PATH 是 process 啟動時的快照（**實測**）

winget 剛裝好的東西不會出現在目前這個 process 的 `$env:PATH` 裡。這對 chezmoi 特別要命：
同一次 apply 裡「前一支腳本剛裝好的 mise」在後一支腳本裡是找不到的。

對應的補救是在每支 Windows 腳本開頭把幾個已知目錄補進 `$env:PATH`：

- `%LOCALAPPDATA%\Microsoft\WinGet\Links`（winget 的 shim 目錄，**實測**：
  `chezmoi.exe` 就在這裡）
- `%LOCALAPPDATA%\mise\shims`（**實測**：Windows 端的 `nvim.exe` 就在這裡）
- `%ProgramFiles%\PowerShell\7`、`%ProgramFiles%\Git\cmd`

這正是 POSIX 端 `eval "$(brew shellenv)"` 的對應物（`AGENTS.md` 已經記過那一條）。

---

## 5. 各工具的設定檔位置

| 工具 | POSIX | Windows | 依據 |
|---|---|---|---|
| mise（全域） | `~/.config/mise/config.toml` | **一樣** `~/.config/mise/config.toml` | `mise config ls` 實測 |
| uv（使用者層） | `~/.config/uv/uv.toml` | **`%APPDATA%\uv\uv.toml`** | uv 官方文件 |
| git（跨機器） | `~/.config/git/config` | 一樣 | git 在 Windows 上把 `%USERPROFILE%` 當 `$HOME` |
| Claude Code | `~/.claude/settings.json` | 一樣 | |
| Codex | `~/.codex/config.toml` | 一樣 | |

uv 的部分，官方文件（[Configuration files](https://docs.astral.sh/uv/concepts/configuration-files/)）
明列使用者層設定在 macOS/Linux 是 `~/.config/uv/uv.toml`、Windows 是
`%APPDATA%\uv\uv.toml`。**沒有實測**（實測需要在主機上放檔案，違反本次的操作限制）。

`core.autocrlf = input` 在 Windows 上維持不變，是刻意的：checkout 出來是 LF。
這是既有設定，本次沒有動它。

---

## 6. oh-my-posh

### 6.1 `$env:POSH_THEMES_PATH` 不可靠（**實測**）

本機的 oh-my-posh 是 Store / WindowsApps 版（`...\AppData\Local\Microsoft\WindowsApps\oh-my-posh.exe`）。
`$env:POSH_THEMES_PATH` 有值（`...\AppData\Local\Programs\oh-my-posh\themes\`），
但那個目錄**不存在**：

```
Get-ChildItem: Cannot find path 'C:\Users\gn006\AppData\Local\Programs\oh-my-posh\themes\'
because it does not exist.
```

winget 版（`JanDeDobbeleer.OhMyPosh`）會把主題放到那裡，Store 版不會。也就是說
「`oh-my-posh init pwsh --config "$env:POSH_THEMES_PATH\x.omp.json"`」這個到處都看得到的
寫法，在使用者從別的管道裝過 oh-my-posh 的機器上會直接壞掉。

**本 repo 的做法**：把主題當成一個釘住版本 + sha256 的 external 抓下來，
跟 zsh 那邊每一個 plugin/theme 的做法一致，完全不依賴那個環境變數。

### 6.2 主題檔的取得

`powerlevel10k_rainbow.omp.json`（v31.1.2 tag）sha256
`d55074433400c2a532ab883986f4e2ebd2b35d9f5d61f355f27eeb1243a78713`（**實測**：
下載後自己算過）。

### 6.3 zsh 外掛在 PowerShell 的對應物

| zsh | PowerShell | 說明 |
|---|---|---|
| powerlevel10k | oh-my-posh | 主題另抓（§6.1） |
| zsh-autosuggestions | **PSReadLine**（pwsh 7 內建） | `Set-PSReadLineOption -PredictionSource History -PredictionViewStyle InlineView` |
| zsh-syntax-highlighting | **PSReadLine**（同上，內建著色） | 不需要額外安裝 |
| fzf-tab | **PSFzf** | `Set-PsFzfOption -TabExpansion` 是對應核心行為的那個旗標 |
| Oh My Zsh 的 mise plugin | `mise activate pwsh` | **實測**可用（mise 2026.8.14 windows-x64） |

PSReadLine 本機實測版本 2.4.5。

---

## 7. cc-statusline 的 Windows 版（**實測**）

`gn00678465/StatusLine` v2.0.1 的 release **有** Windows asset：

- `cc-statusline-win32-x64.zip`，sha256 `d55e2baee3dd6378ee7256574b5104737cfcffbe15228c9a3f50ee32f2ee8bd6`
- `cc-statusline-win32-arm64.zip`，sha256 `dd4fd5ea2811f91031953f806e0a65855c1d623fae4732d554f6489db33f7abd`

（官方 `.sha256` 檔的值，且下載回來自己算過一次，相符。）
zip 裡面只有一個檔案：`cc-statusline.exe`。

**環境變數前綴的問題**：POSIX 端的 `statusLine.command` 是

```
STATUSLINE_USAGE_STYLE=dots ~/.claude/cc-statusline/cc-statusline
```

「環境變數前綴 + 命令」是 POSIX shell 的語法，cmd 與 PowerShell 都不吃。上游 README
對 Windows 只寫到「use `~/.claude/cc-statusline/cc-statusline.exe`（or the equivalent
expanded `%USERPROFILE%` path accepted by the Claude Code host）」，**沒有給任何傳環境
變數的方式**。

所以本 repo 在 Windows 上只放路徑、不帶那個前綴，Windows 端使用預設樣式。
`cmd /c "set VAR=val&& exe"` 這種包法是可行的 cmd 語法，但 Claude Code 在 Windows 上
究竟用哪個 shell 執行 `statusLine.command`，**查不到權威說明**；猜錯的後果是
statusline 整個不顯示，比損失一個外觀選項嚴重得多。

---

## 8. Windows PowerShell 5.1 的檔案編碼（**實測**）

**5.1 用 ANSI 代碼頁解讀沒有 BOM 的 `.ps1`。** 一個含中文註解的 UTF-8 檔案丟給 5.1 的
剖析器，中文會被解成亂碼，而亂碼**會吃掉換行**，於是註解後面那一行被併進註解裡，
變成語法錯誤（實測訊息：`缺少陳述式區塊或型別定義中的 '}'`）。pwsh 7 沒有這個問題
（7 預設把無 BOM 的檔案當 UTF-8）。

這對本 repo 只影響**一個檔案**：`init.ps1`。它的前提就是「機器上只有 5.1」。
兩個可行的修法：

1. 給檔案加 UTF-8 BOM。5.1 就會正確解碼 —— 但 BOM 會破壞
   `irm ... | iex` 這個用法（字串開頭會多一個 U+FEFF）。
2. **整個檔案只用 ASCII**（註解與訊息都是）。

本 repo 選 2，也跟既有的 `init.sh`（註解本來就是英文）一致。
`.chezmoiscripts/` 底下那些 `.ps1` 不受這個限制：它們由 chezmoi 用 pwsh 7 執行，
中文註解實測沒問題（已直接以 `pwsh -NoLogo -File` 跑過一支含中文註解的渲染結果驗證）。

**另一個相關的坑**：`pwsh.exe` 從 **stdin** 讀進來的內容也不是用 UTF-8 解碼的
（實測：中文被解成亂碼且換行被吃掉）。所以要在 WSL 裡對 Windows 的 pwsh 做語法檢查，
必須把內容**寫成檔案**再讓 pwsh 去讀，不能用管線餵進去。

---

## 9. Windows 的 symlink 權限（**實測**）

chezmoi 會在 `~/.claude/skills/` 底下建兩個 symlink（`symlink_commit-message`、
`symlink_verification-gate`）。Windows 上建立 symlink 需要
`SeCreateSymbolicLinkPrivilege`，一般使用者帳號**只有在開啟「開發人員模式」之後才有**。

本機 `HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock` 的
`AllowDevelopmentWithoutDevLicense = 1`，實測 `New-Item -ItemType SymbolicLink` 成功。
但這是機器層級的設定，新機器預設是關的。

本 repo 的處理：`init.ps1` 在跑 `chezmoi init --apply` 之前先探測一次，探不到就
`Write-Warning` 明講原因與開啟方式，讓使用者不用從一個 apply 的失敗訊息去反推。
**沒有**自動改註冊表（那需要系統管理員權限，而且是機器層級的行為改變）。

---

## 10. nvim-treesitter 在 Windows 的 C compiler（**未證實**）

nvim-treesitter 的 `main` 分支（LazyVim 現在追的那一支）用 `tree-sitter build` 編每一個
parser，而 `tree-sitter` CLI 底層走 Rust 的 `cc` crate，在 Windows 上預設找 MSVC 的
`cl.exe`。社群回報的現象是「幾乎所有 parser 都編不起來，因為它去找 cl.exe」，
常見解法是改用 **zig** 當 C compiler。

（[nvim-treesitter#8147](https://github.com/nvim-treesitter/nvim-treesitter/issues/8147)、
[Windows support wiki](https://github.com/nvim-treesitter/nvim-treesitter/wiki/Windows-support)、
[tree-sitter#5610](https://github.com/tree-sitter/tree-sitter/issues/5610)）

本 repo 因此把 `zig.zig` 放進 winget 清單，位置對應 Debian 那邊的 `build-essential`。
**但這條沒有被證實**：驗證需要真的裝 zig、真的開一次 Neovim 讓 LazyVim 去編 parser，
而本次的操作限制不允許在主機上安裝任何東西。唯一能證實它的地方是 Windows Sandbox 的
end-to-end 執行（`tests/sandbox/`）。

若證明不行，備案是 `Microsoft.VisualStudio.2022.BuildTools`（權威但體積大得多）。

---

## 11. Go text/template 的一個剖析限制（**實測**）

寫 modify-template 時踩到，記在這裡免得下一個人再踩：

**`{{-` 後面必須「剛好一個空白」緊接 `/*`，chezmoi 才會把它當註解。**

```
{{- /* 這是註解，OK */ -}}
{{-   /* 多幾個空白就不是註解了 */ -}}   ← template: unexpected "/" in command
```

原因是 Go 的 lexer 在吃掉左界定符與 trim marker（`- ` 兩個字元）之後，
就地檢查後面是不是 `/*`；多出來的空白讓這個檢查失敗，於是 `/` 被當成一個運算式的開頭。

想縮排註解就把空白放到 `{{` **之前**（前一個 action 的 `-}}` 或本 action 的 `{{-`
會把它吃掉）。

**另外**：模板字串裡要放特殊字元請用 Go 的轉義寫法（例如 `"\u0000"`），
不要真的把那個位元組寫進來源檔 —— 那會讓來源檔變成二進位檔，`grep` 之類的工具
會直接跳過它，很難查。

---

## 11.5 codex 設定改寫的「一行一個 key」前提（**實測**）

`~/.codex/config.toml` 的 modify-template 是逐行改寫，前提是**受管的 key 各佔一行**。
四種形狀會讓這個前提失效，合法的 TOML 進去、不合法的 TOML 出來：

| 輸入形狀 | 結果 |
|---|---|
| `status_line` 排成多行陣列 | 續行變成孤兒（`"a",` `"b",` `]`），輸出不是合法 TOML |
| `[[tui]]`（array of tables） | 輸出宣告了兩次 `tui` |
| `["tui"]`（加引號的表頭） | 同上 |
| `tui = { ... }`（inline table） | 同上 |

**這四種與移植前的 `sh`+`awk` 實作逐位元組相同**，也就是說它是沿用下來的既有行為，
不是這次移植引入的；修掉它會改變 POSIX 端的輸出。

第一種最值得注意：受管的 `status_line` 值本身就是一個八元素陣列，任何把它換行排版的
工具或人都會踩到。目前的緩解只有「不要那樣排版」。

這四種形狀釘在 `tools/gate-properties.py` 的 `KNOWN_LIMITATION`，只驗「與原版逐位元組
相同」；哪天輸出與原版不一致了，那就是真的回歸，gate 會擋下來。

---

## 12. 引用來源

- chezmoi：[target-types](https://www.chezmoi.io/reference/target-types/)、
  [source-state-attributes](https://www.chezmoi.io/reference/source-state-attributes/)、
  [chezmoiignore](https://www.chezmoi.io/reference/special-files/chezmoiignore/)
- Neovim：[`runtime/doc/starting.txt` @ v0.12.5](https://github.com/neovim/neovim/blob/v0.12.5/runtime/doc/starting.txt)（`*standard-path*` 一節）
- uv：[Configuration files](https://docs.astral.sh/uv/concepts/configuration-files/)
- winget：[Microsoft Learn — winget](https://learn.microsoft.com/windows/package-manager/winget/)
- nvim-treesitter：[issue #8147](https://github.com/nvim-treesitter/nvim-treesitter/issues/8147)、
  [Windows support wiki](https://github.com/nvim-treesitter/nvim-treesitter/wiki/Windows-support)
- tree-sitter：[issue #5610](https://github.com/tree-sitter/tree-sitter/issues/5610)
- cc-statusline：[gn00678465/StatusLine](https://github.com/gn00678465/StatusLine)
- oh-my-posh：[JanDeDobbeleer/oh-my-posh @ v31.1.2](https://github.com/JanDeDobbeleer/oh-my-posh/tree/v31.1.2/themes)
