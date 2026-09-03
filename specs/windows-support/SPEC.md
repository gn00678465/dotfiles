# SPEC — native Windows 支援

- `spec_version`: v4
- `status`: approved
- `tier`: 3
- `scope`: windows-support
- `base_ref`: `0d72b8e`（`feat/windows-support` 分支起點）
- `contract`: `~/.claude/CLAUDE.md` 的 evidence-first 契約 **v0.6**，未被本 repo 覆寫

Tier 3 的理由：會移動／改寫使用者既有的 nvim 設定、`~/.codex/config.toml`、
`~/.claude/settings.json`，任一步寫錯就是使用者資料遺失。

---

## 0. 目標

這個 repo 目前只產出 Linux/macOS 的環境。要讓同一份 source 也能在 **native Windows**
（不是 WSL）上 `chezmoi init --apply` 出一套等價的環境：

| 面向 | Linux / macOS（現況，不得改變行為） | Windows（本次新增） |
|---|---|---|
| 套件管理 | apt（僅 Linux 前置）+ Homebrew | **winget** |
| Shell | zsh + Oh My Zsh | **PowerShell 7** |
| Prompt | Powerlevel10k | **oh-my-posh，powerlevel10k_rainbow 主題** |
| 補全／建議 | zsh-autosuggestions + zsh-syntax-highlighting | **PSReadLine**（pwsh 7 內建） |
| 模糊搜尋 | fzf + fzf-tab | **fzf + PSFzf** |
| 版本管理 | mise（brew 裝） | **mise（winget 裝）** |
| 編輯器 | neovim（mise 釘 0.12.5）+ LazyVim starter | **同上，路徑不同** |

---

## 1. 已實測確立的事實（本次規劃的地基）

以下每一條都是在本機實測跑出來的，不是推論。環境：WSL2 Debian 12 (`agent`) +
Windows 11 25H2 主機、chezmoi v2.72.0（兩端同版）、pwsh 7.6.5、winget v1.29.290。

| # | 事實 | 怎麼測的 |
|---|---|---|
| F1 | chezmoi 在 **Linux 與 Windows 兩端**，`.ps1` 的預設 interpreter 都是 `pwsh -NoLogo -File` | `chezmoi dump-config --format json` 兩端各跑一次 |
| F2 | **渲染後為空的腳本會被靜默跳過**，兩端皆然 | 探針 source dir：`{{ if eq .chezmoi.os "linux" }}` 包住的 `.ps1.tmpl` 在 Linux 上沒被執行、apply exit 0 |
| F3 | **非空的 `.sh` 腳本在 Windows 上硬失敗並中斷整個 apply**：`fork/exec ...: %1 is not a valid Win32 application`，exit 1 | 同一個探針 source dir 在 Windows 端 apply |
| F4 | `.ps1` 腳本在 Windows 端由 pwsh 7.6.5 正常執行、exit 0 | 探針腳本寫出 marker 檔並驗證存在 |
| F5 | Windows 端 chezmoi 可以用 UNC 路徑 `\\wsl.localhost\agent\...` 直接讀 WSL 內的 source，`.chezmoi.os` = `windows`、`.chezmoi.arch` = `amd64`、`.chezmoi.homeDir` = `C:/Users/gn006` | `chezmoi execute-template --source <UNC>` |
| F6 | neovim 0.12.5 在 Windows 的 `stdpath()`：config=`%LOCALAPPDATA%\nvim`、data=state=log=`%LOCALAPPDATA%\nvim-data`、cache=`%LOCALAPPDATA%\Temp\nvim` | `nvim --headless -l probe.lua`，Windows 端實跑 |
| F7 | pwsh 7 的 `$PROFILE.CurrentUserAllHosts` = `C:\Users\gn006\Documents\PowerShell\profile.ps1`（本機 Documents 未被 OneDrive 轉向；別台機器可能會） | `pwsh.exe -NoProfile -Command '$PROFILE...'` |
| F8 | mise 的全域 config 在 Windows 上一樣是 `~/.config/mise/config.toml`（不是 `%APPDATA%`） | `mise config ls`，Windows 端 |
| F9 | `mise activate pwsh` 存在且可用（mise 2026.8.14 windows-x64） | 實跑並看輸出 |
| F10 | 本機 `$env:POSH_THEMES_PATH` 指向的目錄**不存在**（oh-my-posh 是 Store 版），所以主題不能靠這個變數定位 | `Get-ChildItem $env:POSH_THEMES_PATH` → `Cannot find path` |
| F11 | cc-statusline v2.0.1 **有** Windows release asset：`cc-statusline-win32-x64.zip`（內含 `cc-statusline.exe`）與 `win32-arm64.zip`，官方 `.sha256` 可取得 | GitHub API + 下載後 `sha256sum` 比對相符 |
| F12 | 全部要用的 winget package ID 都存在 | 逐一 `winget show --id <id> --exact` |

winget ID 實測清單（版本為當下查到的）：

| ID | 名稱 | 版本 | 對應 POSIX |
|---|---|---|---|
| `Microsoft.PowerShell` | PowerShell | 7.6.5.0 | zsh |
| `Git.Git` | Git | 2.55.0.3 | git |
| `jdx.mise` | mise-en-place | 2026.8.5 | mise |
| `junegunn.fzf` | fzf | 0.74.3 | fzf |
| `GitHub.GitLFS` | Git LFS | 3.7.1 | git-lfs |
| `BurntSushi.ripgrep.MSVC` | RipGrep MSVC | 15.2.0 | ripgrep |
| `sharkdp.fd` | fd | 10.5.0 | fd |
| `JesseDuffield.lazygit` | lazygit | 0.64.1 | lazygit |
| `tree-sitter.tree-sitter-cli` | tree-sitter-cli | 0.26.12 | tree-sitter |
| `JanDeDobbeleer.OhMyPosh` | Oh My Posh | 31.1.2 | powerlevel10k |
| `zig.zig` | Zig | 0.16.0 | build-essential（C compiler） |

`tree-sitter-cli` 0.26.12 滿足 nvim-treesitter `main` 分支要求的 ≥ 0.26.1
（見 `docs/research/nvim-treesitter-mise-lazyvim-debian-errors.md` §6）。

---

## 2. 設計

### 2.1 平台判斷收斂到單一 partial（重構）

現況：`$brewPrefix` 那 6 行 OS/arch 判斷在 4 支腳本裡逐字複製貼上，`dot_zshrc.tmpl`
與 `dot_zprofile.tmpl` 又各有一份變體。再加上 Windows 會變成 3 份平台知識散在 8 個檔案。

改為單一來源 `.chezmoitemplates/platform.toml`：一個純函式 partial，吐 TOML，
呼叫端一律 `{{- $p := includeTemplate "platform.toml" . | fromToml -}}`，得到一個 dict：

```
os          = "linux" | "darwin" | "windows"
isWindows   = bool
brewPrefix  = "/home/linuxbrew/.linuxbrew" | "/opt/homebrew" | "/usr/local" | ""
nvimConfig  = "~/.config/nvim"        | "%LOCALAPPDATA%\nvim"
nvimData    = "~/.local/share/nvim"   | "%LOCALAPPDATA%\nvim-data"
nvimState   = "~/.local/state/nvim"   | "%LOCALAPPDATA%\nvim-data"
nvimCache   = "~/.cache/nvim"         | "%LOCALAPPDATA%\Temp\nvim"
ccStatuslineAsset / ccStatuslineSum   （含 win32-x64 / win32-arm64）
```

**測試接縫（deliberate seam）**：partial 內部第一行是
`{{- $os := .osOverride | default .chezmoi.os -}}`（arch 同理）。
`osOverride` 只有這一個檔案認得，正式環境的 config 不會有這個 key，
因此永遠退回 `.chezmoi.os`。測試用一份 `--config tests/fixtures/os-<name>.toml`
餵 `[data] osOverride = "darwin"`，就能在單一台 Linux 上渲染出三個 OS 的完整結果——
這是取得 **macOS 證據**的唯一手段（沒有 mac 機器）。這個接縫本身也要被驗證：
第 3.8 層會用 Windows 主機端的真實 chezmoi 跑一次，斷言
「`osOverride=windows` 模擬出來的結果」與「真實 `.chezmoi.os == windows`」逐字相同。

### 2.2 檔案配置

新增：

| 路徑 | target | 說明 |
|---|---|---|
| `.chezmoitemplates/platform.toml` | — | §2.1 |
| `.chezmoitemplates/nvim-plugins-completion.lua` | — | nvim plugin 內容的唯一來源 |
| `.chezmoitemplates/uv.toml` | — | uv 設定的唯一來源 |
| `private_dot_config/powershell/profile.ps1.tmpl` | `~/.config/powershell/profile.ps1` | Windows shell 設定本體（chezmoi 全管） |
| `AppData/Local/nvim/lua/plugins/completion.lua.tmpl` | `%LOCALAPPDATA%\nvim\lua\plugins\completion.lua` | 一行 `includeTemplate` |
| `AppData/Roaming/uv/uv.toml.tmpl` | `%APPDATA%\uv\uv.toml` | uv 官方文件：Windows 使用者層設定在 `%APPDATA%\uv\uv.toml` |
| `.chezmoiscripts/run_onchange_before_30-install-winget-packages.ps1.tmpl` | — | §2.3 |
| `.chezmoiscripts/run_onchange_after_40-git-lfs.ps1.tmpl` | — | Windows 版 `git lfs install --skip-repo` |
| `.chezmoiscripts/run_onchange_before_50-neovim.ps1.tmpl` | — | §2.4 |
| `.chezmoiscripts/run_after_60-pwsh-profile.ps1.tmpl` | — | §2.5 |
| `init.ps1` | — | Windows 自舉腳本 |
| `docs/research/windows-native-support.md` | — | 研究筆記（§4） |
| `tests/` | — | §3 |

改動：

- `private_dot_config/nvim/lua/plugins/completion.lua` → `.tmpl`，改成一行 `includeTemplate`
  （**渲染結果必須與現況逐位元組相同**）
- `private_dot_config/uv/uv.toml` → 同上
- `.chezmoiignore`：加入 per-OS 區塊
- `.chezmoiexternal.toml.tmpl`：Oh My Zsh 全區塊只在 POSIX 輸出；新增 oh-my-posh 主題 external；
  cc-statusline 擴充到 win32
- 4 支既有 `.sh.tmpl` 腳本 + 2 支 zsh dotfile：改用 `platform.toml` partial
- `dot_codex/modify_private_config.toml`：sh+awk → 跨平台 modify-template（§2.6）
- `dot_claude/modify_settings.json`：`statusLine.command` 依 OS 產生
- `README.md` / `AGENTS.md`：補 Windows 章節

`.chezmoiignore` 規則（兩邊互斥，測試會斷言 managed 集合）：

```
非 Windows 忽略：AppData/、.config/powershell/
Windows 忽略：  .zshrc .zprofile .p10k.zsh .oh-my-zsh/ .config/nvim/ .config/uv/
共同忽略：      README.md init.sh init.ps1 AGENTS.md CLAUDE.md docs/ tests/ .scratch/ .git
```

### 2.3 winget 安裝腳本

`winget install --exact --id <ID> --silent --accept-package-agreements
--accept-source-agreements --disable-interactivity`，逐一檢查
`winget list --exact --id <ID>` 已安裝就跳過（對應 brew 腳本的 `brew list || brew install`）。

`Microsoft.PowerShell` 與 `Git.Git` 不在這支腳本裡——它們是 `init.ps1` 的自舉責任
（chezmoi 要有 git 才能 clone，要有 pwsh 才能跑 `.ps1` 腳本，見 F1）。

### 2.4 Windows neovim 腳本

與 POSIX 版逐條對稱，只有路徑不同（F6）：

1. `mise use --global neovim@0.12.5`（同一個釘版，理由見 POSIX 腳本裡的註解）
2. marker 檔 `<nvimConfig>\.chezmoi-lazyvim-starter` 不存在時：
   把既有的 config / data / state / cache **四個目錄 mv 成 `.bak`**（已存在 `.bak` 就加時間戳），
   **一律不刪**，再 `git clone --depth 1 https://github.com/LazyVim/starter` 進 config、
   刪掉 `.git`、`touch` marker
3. 有 marker 就整段跳過（re-run 時使用者自己的設定不會被搬走）

### 2.5 PowerShell profile（依你選的方案）

- chezmoi 全管 `~/.config/powershell/profile.ps1`（內容：oh-my-posh init、PSReadLine 選項、
  PSFzf、`mise activate pwsh`、WSL 無關的 alias）
- `run_after_60-pwsh-profile.ps1` 在**執行期**由 pwsh 自己解析 `$PROFILE.CurrentUserAllHosts`
  （因此 OneDrive 轉向 Documents 的機器也正確，見 F7），確保檔案存在且**恰好含有一行** loader
  `. "$HOME\.config\powershell\profile.ps1"`；已經有了就是 no-op（冪等）

oh-my-posh 主題：**powerlevel10k_rainbow**，但不靠 `$env:POSH_THEMES_PATH`（F10 證明它不可靠），
改成 `.chezmoiexternal.toml.tmpl` 釘住 tag `v31.1.2` + sha256
`d55074433400c2a532ab883986f4e2ebd2b35d9f5d61f355f27eeb1243a78713` 抓到
`~/.config/oh-my-posh/powerlevel10k_rainbow.omp.json`。這與 repo 既有慣例一致
（zsh 的每一個 plugin/theme 都是釘版本 + checksum 的 external）。

### 2.6 `~/.codex/config.toml` 的 modify_ 移植（依你選的方案）

把現有 awk 的逐行改寫演算法，原樣改寫成 chezmoi modify-template（純 Go template，零外部相依），
三個 OS 共用一份實作。行為契約與 awk 版**完全相同**，並由 §3.6 的 golden 測試釘住：
只替換 `[tui]` 內受管的 key，其餘位元組原樣輸出（註解、空行、key 順序、其他 table、
重複 key 的處理、整檔沒有 `[tui]` 時補在檔尾）。

---

## 3. 驗證計畫（每一層都會被實際執行並記錄）

執行入口：`tests/run.sh`（純 POSIX sh + chezmoi，無其他相依）。
每個 case 先在實作前跑出 **RED**。

| 層 | 內容 | 在哪跑 |
|---|---|---|
| L1 | `platform.toml` partial：linux/darwin(arm64,amd64)/windows 逐欄位斷言 | 任何機器 |
| L2 | 渲染矩陣：三個 OS 各渲染全部 `.chezmoiscripts/*`，斷言「該跑的非空、不該跑的**渲染成空**」（F2/F3 是這層存在的理由） | 任何機器 |
| L3 | `chezmoi managed` / `ignored` 三 OS 集合斷言（Windows 上沒有 `.zshrc`、POSIX 上沒有 `AppData/`…） | 任何機器 |
| L4 | 語法檢查：非空 `.sh` 過 `sh -n`；非空 `.ps1` 過 pwsh `Parser::ParseInput`（無 pwsh 時標 SKIP） | WSL |
| L5 | `.chezmoiexternal.toml.tmpl` 三 OS 渲染後解析 TOML：Windows 不得出現任何 `.oh-my-zsh` 條目；每個條目都要有 checksum | 任何機器 |
| L6 | **檔案層 golden**：`chezmoi apply --exclude=scripts,externals` 到預先塞好內容的暫存 destination，比對整棵樹。含 codex/claude 的資料保全案例（有註解、多 table、重複 key、缺 `[tui]`、空檔） | 任何機器 |
| L7 | **行為測試**：50-neovim 兩個版本各自實跑（HOME/LOCALAPPDATA 指向暫存目錄，`mise`/`git` 用 stub），斷言備份不覆寫、不刪除、marker 冪等；60-pwsh-profile 連跑兩次只有一行 loader | WSL（`.ps1` 經 pwsh.exe） |
| L8 | **接縫驗證**：Windows 主機端真實 `chezmoi.exe`（`.chezmoi.os == windows`）跑 `managed` + `apply --dry-run`，與 L3 的 `osOverride=windows` 結果逐字比對 | Windows 主機（唯讀） |
| L9 | **E2E**：Windows Sandbox 內 `_probe.ps1` 自舉 winget → 跑完整 `init.ps1` → 斷言 11 個工具、profile、nvim 目錄、prompt 都到位。兩種模式：**本機**（`prepare.sh` 對應 `C:\src`，輸出到對應出去的 `C:\out`，可測未推送的分支）與**遠端**（`-Branch <分支>`，chezmoi 自己 clone，輸出退到桌面並在結尾把結果全文印到主控台；只能測已推送的分支） | Sandbox（由你按下啟動） |
| L10 | **回歸**：對 base ref `0d72b8e` 跑同一份 L3/L6，斷言 Linux 與 macOS 的 target 集合與檔案內容**沒有任何改變** | 任何機器 |

收尾：`verification-gate` skill（`gate` 迭代、`evidence` 一次），Tier 3 再派 `verifier` agent 獨立驗證。

## 4. 研究筆記

新增 `docs/research/windows-native-support.md`，比照既有兩篇的體例
（先講結論、逐條標「實測」或引官方原文、查不到就寫查不到）。至少涵蓋：
neovim Windows standard-path（官方 `starting.txt` 原文 + 本機實測，含**兩者不一致**的
cache 路徑：文件寫 `Temp/nvim-data`、0.12.5 實際吐 `Temp\nvim`）、pwsh `$PROFILE` 與
OneDrive 轉向、chezmoi 在 Windows 的腳本／interpreter 語意（F1–F5）、winget 非互動旗標、
uv/mise 在 Windows 的設定檔位置、nvim-treesitter 在 Windows 的 C compiler 現況。

---

## 5. Must NOT（違反任一條即視為失敗）

1. **不得**在 Windows 主機上執行任何 `winget install`、或 `chezmoi apply` 到真實的
   `C:\Users\gn006`。真實安裝只准在 Windows Sandbox 或 CI。
2. **不得**改變 Linux/macOS 現有的 target 集合與檔案內容。nvim/uv 改走共用 template
   屬等價重構，渲染結果必須**逐位元組相同**（L10 釘住）。
3. **不得**刪除任何既有使用者檔案或目錄。既有 nvim 設定一律 `mv` 到 `.bak`，
   且不得覆蓋已存在的 `.bak`。
4. **不得**讓 `.sh` 在 Windows 被執行，或 `.ps1` 在 POSIX 被執行。跨平台的隔離手段
   只有一種：**渲染成空**（F2），不是靠 `.chezmoiignore` 兜。
5. **不得**引入未釘版本或無 checksum 的外部下載。
6. **不得**為了讓測試變綠去改測試。測試看起來不對 → 回來討論 SPEC。
7. **不得**在 evidence report 裡寫沒有真的跑過的檢查。

---

## 6. Tier 3 失效模型

| # | 失效模式 | 實際傷害 | 對應檢查 |
|---|---|---|---|
| M1 | `.sh` 腳本在 Windows 被 exec | apply 中斷（F3 已實測），使用者拿到半套環境 | L2、L8 |
| M2 | 50-neovim 在 Windows 覆蓋或刪除既有 `%LOCALAPPDATA%\nvim` | **使用者 nvim 設定與外掛資料永久遺失** | L7 |
| M3 | 重跑 apply 時 marker 判斷失效，把使用者自己的設定當成外來設定搬走 | 同 M2 | L7（冪等案例） |
| M4 | codex modify-template 移植走樣：吃掉註解、丟掉其他 table、重排 key | `~/.codex/config.toml` 毀損 | L6 golden |
| M5 | claude modify-template 洗掉未受管的 key | `~/.claude/settings.json` 狀態遺失 | L6 golden |
| M6 | Oh My Zsh external（`exact = true`）在 Windows 仍被求值 | 誤刪 `~/.oh-my-zsh` 下的東西 | L5 |
| M7 | `.chezmoiignore` 寫反 → Windows 落下 zsh 檔／POSIX 落下 `AppData/` | 環境汙染 | L3 |
| M8 | `osOverride` 接縫與真實 Windows 行為不一致 → 整個渲染矩陣的證據失效 | 假綠 | L8 |
| M9 | winget ID 錯字 → 靜默沒裝到 | 環境不完整 | F12 逐一實測 + L9 |
| M10 | pwsh profile loader 重複 append | profile 每次 apply 長一行 | L7 |
| M11 | 這次重構順手改壞 POSIX 端 | 現有機器壞掉 | L10 |
| M12 | zig 無法讓 tree-sitter CLI 在 Windows 編出 parser | LazyVim 在 Windows 上 treesitter 半殘 | L9；**這條目前未證實**，只有社群資料，見 §7 |
| M13 | Windows 的 ExecutionPolicy 擋掉 chezmoi 寫到 `%TEMP%` 的 `.ps1` | **第一支 `before` 腳本就拒載，整個 apply 在任何檔案落地前中止** —— 全新 Windows 一律如此，使用者拿到的是一台什麼都沒發生的機器 | L2（`.chezmoi.toml.tmpl` 的 `[interpreters.ps1]`）+ L10（POSIX 不受影響）+ L9 |

---

## 7. 已知限制與未證實項目

- **M12（C compiler）**：nvim-treesitter `main` 分支用 `tree-sitter build` 編 parser，
  在 Windows 上預設走 MSVC `cl.exe`。社群做法是改用 zig，本 SPEC 因此把 `zig.zig`
  放進 winget 清單，**但我沒有辦法在主機上驗證**（Must NOT #1），只有 L9 sandbox 能證實。
  若 L9 證明不行，備案是 `Microsoft.VisualStudio.2022.BuildTools`（體積大很多）；
  evidence report 會如實記錄這條的狀態。
  **v4 更新**：L9 已經真的跑過一次（遠端模式），但那一次死在 M13，apply 在任何檔案
  落地前就中止，nvim 根本沒被裝起來 —— **M12 仍然未證實**，只是現在知道它為什麼沒被
  問到。
- **macOS 沒有實機**。macOS 的證據全部來自 `osOverride=darwin` 的渲染矩陣（L1–L6, L10），
  沒有任何一次真實 apply。這是明確的 downgrade，會寫進 evidence report。
- **Windows Sandbox 沒有 App Installer**，`_probe.ps1` 需要先自舉 winget；
  這段自舉程式碼只服務測試，不會進到 `init.ps1`。
- `core.autocrlf = input` 維持不變（Windows 上 checkout 為 LF）。這是刻意不動，不是遺漏。
- **備份撞名（accepted risk，v2 決定）**：`backup_dir` /
  `Backup-NvimDirectory` 的時間戳只到秒。若 `dir.bak` 與 `dir.bak.<當秒>` 同時已存在，
  `mv` / `Move-Item` 會把來源搬「進」那份既有備份裡（`dir.bak.<秒>/nvim`）。
  資料不會被刪也不會被覆蓋，只是位置深了一層，Must NOT #3 仍然成立。
  觸發條件是同一秒內跑完兩次含 `git clone` 的 bootstrap，實務上到不了。
  v1 曾為此加序號迴圈，但那會改變 POSIX 端的渲染輸出（Must NOT #2），
  代價是六行程式碼加一段寫死的預期 diff，不划算，v2 還原。
  這條路徑由 L7 的第四次執行釘成 characterization test：形狀被改動不會無聲通過。

---

## 8. Approval record

核准是綁定在**某一版 SPEC** 上的結構化行為，不是對話裡的一句話。這一節只增不改：
每一版各留一筆，逐字記錄。

### v1 — 2026-09-02

- **approval: confirmed**
- version bound: v1 — 核准當下 SPEC（當時路徑為 `.scratch/windows-support/spec.md`）
  的 sha256（即本節被改寫成核准狀態**之前**的檔案內容）
  = `ea20ea21f78b5eac5118270bb9f17775965da8da36ffe04ae21138b4499555ae`
- date: 2026-09-02
- approver: repo owner（Madao）
- verbatim words（使用者原話，逐字）:

  > 核准 spec

- 範圍：v1 的 §0–§7 全文，含 §5 Must NOT 七條、§6 Tier 3 失效模型 M1–M12、
  §7 已宣告的兩個缺口（macOS 無實機、M12 未證實）。

### v4 — 2026-09-03

- **approval: confirmed**
- version bound: v4 — 核准當下 `specs/windows-support/SPEC.md` 的 sha256
  （即本節被改寫成核准狀態**之前**、`status` 仍為 `revised-pending-approval` 的檔案內容）
  = `77649099c92b9d50c16fa2351caffc248a6e058874e969e28c7648b978c77c49`
- date: 2026-09-03
- approver: repo owner（Madao）
- verbatim words（使用者原話，逐字）:

  > 核准 SPEC v4

- 範圍：v4 全文。實質變更為 §6 新增失效模式 M13（ExecutionPolicy 擋掉所有 `.ps1`）
  與 §7 更正 M12 的狀態。完整清單見 §9。

### v3 — 2026-09-03

- **approval: confirmed**
- version bound: v3 — 核准當下 `specs/windows-support/SPEC.md` 的 sha256
  （即本節被改寫成核准狀態**之前**、`status` 仍為 `revised-pending-approval` 的檔案內容）
  = `25bfd94b62305152a5cbc15cdba7ad6f88ba6642214a89dbd8d133c89e3befe3`
- date: 2026-09-03
- approver: repo owner（Madao）
- verbatim words（使用者原話，逐字）:

  > 核准 SPEC v3

- 範圍：v3 全文。實質變更只有一項 —— §3 的 L9 一列新增遠端模式（驗證程序擴充），
  不動 §5 Must NOT、§6 失效模型或任何產品需求。完整清單見 §9。

### v2 — 2026-09-03

- **approval: confirmed**
- version bound: v2 — 核准當下 `specs/windows-support/SPEC.md` 的 sha256
  （即本節被改寫成核准狀態**之前**、`status` 仍為 `revised-pending-approval` 的檔案內容）
  = `7e47539c186d5bc97eee19aa89e9001fdc4f9e3394dabbdc4d46cf981405d2e3`
- date: 2026-09-03
- approver: repo owner（Madao）
- verbatim words（使用者原話，逐字）:

  > 核准 SPEC v2

- 範圍：v2 全文。實質變更只有一項 —— §7 新增「備份撞名（accepted risk）」；
  路徑搬遷、標頭格式、override 撤回為形式變更，不改變 §0–§6 的任何要求。
  完整清單見 §9。

---

## 9. Revisions

### v3 → v4

| # | 變更 | 性質 |
|---|---|---|
| 1 | §6 新增 **M13**：Windows 的 ExecutionPolicy 擋掉 chezmoi 寫到 `%TEMP%` 的 `.ps1`，第一支 `before` 腳本就拒載，整個 apply 在任何檔案落地前中止 | **實質**。這是原本整個漏掉的失效模式 |
| 2 | §7 的 M12 更新為「L9 已執行過一次，但死在 M13 之前，M12 仍未證實」 | **實質**（狀態更正） |

M13 是 L9 第一次真實執行找出來的，也是這份 SPEC 最嚴重的一個缺口：§6 列了 M1–M12，
沒有任何一條涵蓋「腳本根本不被允許執行」。它不是 Sandbox 特有的環境問題 ——
Windows 用戶端的預設 ExecutionPolicy 就是 `Restricted`，**每一台全新機器都會死在
同一個地方**，而使用者看到的是一台什麼都沒發生的電腦。

修法（見 `docs/research/windows-native-support.md` 1.6，三項都是實測）：
`.chezmoi.toml.tmpl` 的 Windows 分支加上

```toml
[interpreters.ps1]
    command = "pwsh"
    args = ["-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File"]
```

- pwsh 7 **一樣**受 ExecutionPolicy 管（實測），所以「chezmoi 用的是 pwsh 不是 5.1」
  不構成豁免。
- `[interpreters.ps1]` 在**同一次** `init --apply` 裡就生效（實測）—— 這是修法可不可行
  的關鍵，因為要救的正是「第一次安裝」。
- 不採用在 `init.ps1` 裡 `Set-ExecutionPolicy`：那會改變使用者機器的安全設定並留在
  機器上，而且對不經 `init.ps1` 的人無效。`Bypass` 只作用在 chezmoi 為自己的腳本開的
  那個 process。
- 一併補 `-NoProfile`：chezmoi 的預設 args 沒有它，安裝腳本因此會載入使用者的 pwsh
  profile —— 也就是這個 repo 自己裝的那一份。

Must NOT #2 不受影響：`[interpreters.ps1]` 包在 `{{ if $p.isWindows }}` 裡，POSIX 的
設定渲染與 base ref 逐位元組相同（L10 新增了這條比對 —— 在此之前
`.chezmoi.toml.tmpl` **完全沒有任何程序在看**，因為它產生的是 chezmoi 自己的設定，
不是 target，整棵樹的 diff 看不到它）。

### v2 → v3

| # | 變更 | 性質 |
|---|---|---|
| 1 | §3 的 L9 一列改寫：`_probe.ps1` 新增**遠端模式**（`-Branch <分支>`），使用者可在任何一台有 Windows Sandbox 的機器上，不經 `prepare.sh`、不對應資料夾，用一行 `irm` 跑完 L9 | **實質**（驗證程序擴充）。這是唯一需要重新核准的一項 |

遠端模式的形狀：

- `param([string] $Branch)`，名稱與 `init.ps1` 對齊。
- 有 `-Branch` → `chezmoi init --apply --branch <分支> gn00678465`，讓 chezmoi
  自己 clone；沒有 `-Branch` → 維持 `--source C:\src\dotfiles` 的本機模式。
  要讀來源樹取預期值的檢查，遠端模式改讀 `chezmoi source-path`。
- `C:\out` **不存在時**（先探測再建立，否則會憑空造出一個對應不出去的目錄）
  輸出改寫到 `%USERPROFILE%\Desktop\chezmoi-probe\`，並在結尾把 `results.tsv`
  全文印到主控台 —— Sandbox 一關檔案就沒了，主控台是唯一會活下來的副本。
- winget 自舉那段不動：它本來就是「找不到才裝」。
- 仍然是 ASCII、無 BOM、相容 Windows PowerShell 5.1，否則 `irm` 這條路走不通。

代價與限制（寫進 `tests/sandbox/README.md`）：遠端模式測的是 **GitHub 上**的分支，
不是本機工作樹；未推送的變更只能用本機模式測。兩種模式並存，不是取代。

L11-D 新增 7 條斷言釘住上述義務（含「不得留下寫死的 `C:\out` 輸出路徑」，
因為只要漏一個，桌面那條退路就有一半是假的），全部先觀察到 RED。

### v1 → v2

| # | 變更 | 性質 |
|---|---|---|
| 1 | SPEC 從 `.scratch/windows-support/spec.md` 搬到 `specs/windows-support/SPEC.md` | 形式。契約 v0.6 第 1 條明定此路徑，理由是 CLOSE 步驟的 `spec-archive` 只讀那裡 |
| 2 | 標頭改成 `spec_version` / `status` / `tier` / `scope` / `base_ref` / `contract` 的清單形式 | 形式。`spec-archive` 的 `STATUS_RE` 需要能解析 `status`，已實測可解析 |
| 3 | **撤回**先前宣告的契約 override | 形式，但更正了一項錯誤主張。原本引用 `docs/agents/issue-tracker.md` 作為「本 repo 覆寫契約」的依據；使用者指出該文件規範的是 **issue** 的位置，不是 spec，兩者不是同一種產物，override 不成立。標頭的 `contract` 欄位因此改記為「未被本 repo 覆寫」。該文件本身的用字在 `feat/evidence-first-contract` 的 `bfcdc9a` 另行處理，不在本分支改動 |
| 4 | §7 新增「備份撞名（accepted risk）」；v1 為此加的序號迴圈在兩個平台上都還原 | **實質**。這是唯一需要重新核准的一項 |

第 4 項的連帶改動（都在測試與工具側，不改變產品行為）：

- `.chezmoiscripts/run_onchange_before_50-neovim.sh.tmpl` 的 `backup_dir`
  與 base ref `0d72b8e` 逐位元組相同。
- `.chezmoiscripts/run_onchange_before_50-neovim.ps1.tmpl` 的
  `Backup-NvimDirectory` 同步還原，維持兩邊對稱（Windows 端不受 Must NOT #2
  約束，這是對稱性的決定）。
- L10 移除唯一的具名例外，POSIX 腳本全部回到嚴格逐位元組比對。
- L7 第四次執行改成釘 accepted risk 的行為（資料仍在、只是深一層），兩個平台對稱。
- mutation：`backup-timestamp-collision{,-windows}` 換成
  `backup-timestamp-fallback{,-windows}`（刪掉時間戳退路 → 第二份備份被埋）。
