# SPEC — native Windows 支援

- `spec_version`: v7
- `status`: revised-pending-approval
- `tier`: 3
- `scope`: windows-support
- `base_ref`: `ccae9d8`（**Windows 支援併進 main 之前的最後一個 main 狀態**；原為分支起點 `0d72b8e`，更新理由見 §9）
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
| L9 | **E2E**：Windows Sandbox 內 `_probe.ps1` 自舉 winget → 跑完整 `init.ps1` → 斷言 11 個工具、profile、nvim 目錄、prompt 都到位。兩種模式：**本機**（`prepare.sh` 對應 `C:\src`，輸出到對應出去的 `C:\out`，可測未推送的分支）與**遠端**（`-Branch <分支>`，chezmoi 自己 clone，輸出退到桌面並在結尾把結果全文印到主控台；只能測已推送的分支）。**執行期間必須是可觀察的**：長時間步驟的子程序輸出邊收邊印，且每個長步驟開始前先印出「正在做什麼、預期多久」——操作者要能分辨「還在跑」與「卡死」。**套件是否安裝，以 `winget list --exact --id` 逐一確認** `30-install-winget-packages` 清單裡的九個套件——與產品腳本自己的判斷指令相同，不依賴 PATH。「工具在使用者新開的終端機 PATH 上」這件事**不再由 L9 宣稱**，見 §7 的具名已知限制 | Sandbox（由你按下啟動） |
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
| M14 | Git for Windows 預設 `core.autocrlf=true`，來源樹被 checkout 成 CRLF | 算繪結果帶進 `\r`，受管的設定檔出現混行尾；`modify_` 改寫器是逐行比對的，下一次 apply 會把 `key = value\r` 當成另一個 key | L6/L10 皆看不到（都從 LF 樹跑）；L9 第二次執行實際抓到 |
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

  **v5 更新：這個假設已被推翻，不再是「未證實」。** L9 第二次執行後，使用者在
  Sandbox 內開新終端機實跑 nvim，nvim-treesitter `main` 回報
  `Unmet requirements: C compiler ❌`（curl、tar、tree-sitter CLI 都 ✅），
  並建議 `winget install BrechtSanders.WinLibs.POSIX`。也就是說
  **nvim-treesitter 的偵測不接受 zig**，把 `zig.zig` 放進 winget 清單並不能滿足它。
  這一項的處置是產品層決定，選項與代價見 §9 的 v4 → v5。

  **zig 確實在 PATH 上**：使用者在同一個終端機跑 `zig version` 得到 `0.16.0`。
  所以這不是 A 那一類的觀察誤差 —— zig 裝好了、找得到，nvim-treesitter `main` 的
  需求檢查就是不接受它。這條假設的推翻是確定的，不需要再測一次 PATH。

  **處置（使用者選 (a)，見 §8 的決議記錄）**：winget 清單把 `zig.zig` 換成
  `BrechtSanders.WinLibs.POSIX.UCRT`（WinLibs 的 gcc / MinGW-w64）。
  `zig.zig` 一併移除 —— 它進清單的唯一理由就是當 treesitter 的 C compiler，
  那個理由已經不成立，留著只是體積。
  **這一項在 L9 再跑一次之前仍然沒有被證明**：換掉編譯器是依據 nvim-treesitter
  自己的建議，不是依據一次成功的 parser 編譯。M12 的狀態是「假設已被推翻、
  處置已選定、修法未證實」。
- **macOS 沒有實機**。macOS 的證據全部來自 `osOverride=darwin` 的渲染矩陣（L1–L6, L10），
  沒有任何一次真實 apply。這是明確的 downgrade，會寫進 evidence report。
- **Windows Sandbox 沒有 App Installer**，`_probe.ps1` 需要先自舉 winget；
  這段自舉程式碼只服務測試，不會進到 `init.ps1`。
- **「工具在新終端機的 PATH 上」不再自動驗證（具名已知限制，v6）**：L9 原本有十條
  `tool on PATH` 檢查，**修了三輪都沒修好，而且根因始終沒有找到**（經過見 §9 的
  v5 → v6 與 evidence report）。已知會紅的檢查會讓人學會忽略 FAIL，所以整組移除，
  不是留著標記為預期失敗。
  **改由誰證明**：
  - *套件有沒有裝* —— 由 v6 新增的 `winget list --exact --id` 九條檢查證明（自動）。
  - *nvim / gcc / tree-sitter 能不能執行* —— 由既有的 M12 檢查證明（自動）：
    它必須真的跑起這三支才會產出 lua parser。
  - *其餘工具在使用者新開的終端機 PATH 上* —— **只有手動驗證**。使用者在 L9 第三次
    執行後於 Sandbox 內開新終端機逐一確認 mise、nvim 可用，並確認 `zig version`
    回報 0.16.0。**這一項沒有自動化程序，L9 不再宣稱它。**

- **既有的 CRLF 設定檔（具名已知限制，M14 選 (c) 的殘留風險）**：`.gitattributes`
  管得到的是**來源樹**。使用者機器上**已經存在**的 `~/.codex/config.toml` 若本身是
  CRLF（Windows 上的程式寫出來的常態），`modify_` 改寫器是逐行比對的，行尾的 `\r`
  會讓它把 `key = value\r` 看成與 `key = value` 不同的東西，可能重複寫入或漏改。
  **不修**：改寫器被 `gate-properties.py` 的 P0 釘在「與移植前的 awk 逐位元組相同」，
  而 awk 原版不處理 CR；動它就是刻意脫離那個 parity，並且會改變 POSIX 端在含 CR
  輸入上的輸出。這與 §「`modify_` 的一行一個 key 前提」屬同一類：沿用自原實作、
  已揭露、未修。
- ~~`core.autocrlf = input` 維持不變（Windows 上 checkout 為 LF）。這是刻意不動，不是遺漏。~~
  **v5 更正：這一條的推論是錯的。** `core.autocrlf = input` 是**這台機器上使用者自己的
  git 設定**，不是 repo 的性質。Git for Windows 的預設是 `core.autocrlf=true`，而這個
  repo **沒有 `.gitattributes`**，所以任何一台全新 Windows 都會把來源樹 checkout 成
  CRLF。後果見 §6 的 M14 與 §9 的 v4 → v5。
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

### v7 — 待核准

- **approval: pending**
- version bound: v7（見 §9 的變更清單）
- 這一版尚未取得核准。契約規定核准綁定單一版本，v6 的核准不自動延伸到 v7。
- 需要核准的實質變更：**Must NOT #2 的驗證方式降級**。詳見 §9 的 v6 → v7；
  這一項與上一次的 `base_ref` 更新**不同性質**，上一次不縮小覆蓋範圍，這一次會。
  **核准之前不實作。**

### v6 — 2026-09-03

- **approval: confirmed**
- version bound: v6 — 核准當下 `specs/windows-support/SPEC.md` 的 sha256
  （即本節被改寫成核准狀態**之前**、`status` 仍為 `revised-pending-approval` 的檔案內容）
  = `bc63af9a27287cff32c40fb6eebfe5d949925bdaa7d106b313a6af9d84f93940`
- date: 2026-09-03
- approver: repo owner（Madao）
- verbatim words（使用者原話，逐字）:

  > Approval V6

- 範圍：v6 全文。實質變更為 §3 的 L9 移除十條 `tool on PATH` 檢查、改為九條
  `winget list --exact --id`，以及 §7 新增具名已知限制（「工具在新終端機 PATH 上」
  改由手動驗證，L9 不再宣稱）。完整清單見 §9 的 v5 → v6。

### v5 的兩項選擇 — 2026-09-03

v5 本文把兩件事明寫成「待你決定」並列出選項。以下是那兩題的答案，逐字記錄。
**不另起版本**：這不是對 SPEC 要求的修改，而是 v5 自己委派出去的選擇被填回來；
被填回的內容（§7 的 M12 處置與新增的 CRLF 具名已知限制）正是 v5 所要求的產物。

- **decision: confirmed**
- bound to: v5（sha256 `051a98b1a4302bb6f4e95af647c394637b32975edd8a502dda0109526bb9da8a`）
- date: 2026-09-03
- decider: repo owner（Madao）
- verbatim words（使用者原話，逐字）:

  > M14 選 c，M12 選 a

- 解讀：**M14 → (c)**：加 `.gitattributes` 強制 LF，改寫器**不動**（保住與 awk 的
  逐位元組 parity），既有 CRLF 設定檔的殘留風險寫成具名的已知限制。
  **M12 → (a)**：winget 清單把 `zig.zig` 換成 WinLibs 的 gcc。
- **實作時發現的一項偏差，據實記在這裡而不是默默選掉**：nvim-treesitter 建議的
  `BrechtSanders.WinLibs.POSIX` **不是一個存在的 winget ID**（`winget show --exact`
  找不到），實際存在的是四個變體。選定
  **`BrechtSanders.WinLibs.POSIX.UCRT`**（16.1.0-14.0.0-r4）：POSIX threads 對應
  建議的那一支，UCRT 是 Windows 10/11 的現行 C runtime（MSVCRT 是舊的），
  不取 `.LLVM` 變體 —— 需要的是 gcc，多帶一套 LLVM 只是體積。仍在 (a) 的範圍內。

### v5 — 2026-09-03

- **approval: confirmed**
- version bound: v5 — 核准當下 `specs/windows-support/SPEC.md` 的 sha256
  （即本節被改寫成核准狀態**之前**、`status` 仍為 `revised-pending-approval` 的檔案內容）
  = `051a98b1a4302bb6f4e95af647c394637b32975edd8a502dda0109526bb9da8a`
- date: 2026-09-03
- approver: repo owner（Madao）
- verbatim words（使用者原話，逐字）:

  > Approval V5

- 範圍：v5 全文，四項實質變更見 §9 的 v4 → v5。
- **核准的是修訂本身，不是選項的選擇。** §9 的第 3 項（既有 CRLF 設定檔要不要正規化，
  三個選項）與第 4 項（M12 的處置，四個選項）在這份核准裡**仍然沒有被選定**。
  第 1、2 項（探針的可觀察性與 registry PATH）已完整指定，可以直接實作；
  第 3、4 項在使用者選定之前不動產品。

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

### v6 → v7（待核准）：Must NOT #2 的驗證方式降級

**這一項是降級，不是維護。** 上一次動 `base_ref`（見下一節）我判定為非實質變更，
理由之一是「不會讓覆蓋範圍變窄」。**那個理由這次不成立**，所以這次走修訂與核准。

#### 事實

`base_ref` 目前是 `ccae9d8`＝**Windows 支援併進 main 之前**的最後一個 main 狀態。
main 之後又前進了三次：#7（Windows 支援本身）、#8（`agent-instructions.md` 的維護
註解從 HTML 註解改成 Go template 註解，於是不再被算繪進 `~/.claude/CLAUDE.md` 與
`~/.codex/AGENTS.md`）、#9（`dot_agents/workflow` → `workflows`）。本分支已合併 main，
所以 #8 與 #9 的**POSIX 輸出變更**現在也在本分支裡。

於是 L10 對 `ccae9d8` 比對時紅了三條，而那三條**全部是 main 自己的變更**，
不是這次 Windows 移植造成的 —— 以 Must NOT #2 要問的問題而言，這是假陽性。

#### 兩難

`ccae9d8` 之後，main 上**不存在**「有 #8/#9、但沒有 Windows 移植」的commit：
#8 與 #9 都排在 #7 之後。所以沒有一個基準能同時滿足兩件事。

| 選項 | 結果 |
|---|---|
| (a) 維持 `ccae9d8` | 三條永久紅。這正是上一輪拿掉十條 `tool on PATH` 的理由：**已知會紅的檢查會讓人學會忽略 FAIL** |
| (b) `base_ref` → `origin/main`（`59ebb87`） | 紅燈消失，但 main **已經含有這份移植**，L10 變成拿它自己比它自己。**Must NOT #2 不再被 L10 重新驗證**，L10 只剩下「本分支相對 main 的剩餘差異沒有改變 POSIX」 |
| (c) 維持 `ccae9d8`，但排除 main 事後改過的路徑 | 每次 main 動就要維護一份排除清單，而清單會靜靜地把覆蓋範圍吃掉 —— 與這份工作一路上拒絕的「固定清單」是同一種東西 |

#### 建議：(b)，並且明寫它是降級

Must NOT #2 對**這份移植本身**的驗證**已經完成，而且留在 git 歷史裡**：
evidence 在 `777b122` 那一輪（以及更早的每一輪）都是對 `ccae9d8` 逐位元組比對過的，
`.gate/` 的產出與報告都在。結束的不是「曾經證明過」，而是「每一次執行都能重新證明」——
因為已經沒有一個夠新、又不含這份移植的 main 可以當基準。

採 (b) 之後 L10 還會驗什麼：本分支相對 main 的**剩餘差異**（目前是測試與文件修正）
不改變 POSIX 輸出。這仍然有價值，但**比原本弱**，必須寫清楚。

連帶要調整的斷言（核准後才動）：
- 「managed 只多出五支 Windows 腳本」→ 期望值改成**空集合**（main 已經有那五支）。
- 逐支腳本的逐位元組比對仍然保留，但對那五支 Windows 腳本而言變成自己比自己。
- 「managed 沒有任何 target 消失」不變，仍然有效。

如果你選 (a) 或 (c)，或有第四種做法，這一節就照你的決定改寫。

### base_ref 更新 — 2026-09-04（**非實質變更，未重新請求核准**）

`base_ref` 由 `0d72b8e`（分支起點）改為 `ccae9d8`（`origin/main`，也是合併後的
merge-base）。main 上的 #3（evidence-first 合約）已合併進本分支。

**依合約判定為非實質變更，理由逐條寫在這裡以便日後稽核：**

1. `base_ref` 記錄的是 **Must NOT #2 的比較基準**，不是要求本身。要求
   （「Linux/macOS 現有的 target 集合與檔案內容不得因為這次 Windows 支援而改變」）
   一個字都沒有動。§0–§7 的其他部分也都沒有動。
2. **不改反而會讓檢查說謊。** main 在 `0d72b8e` 之後自己前進了（合約升到 v0.6、
   verification-gate skill 改版、`commit-message` 更名為 `commit`、新增
   `spec-archive` skill 與 verifier agent）。以 `0d72b8e` 為基準，L10 會把
   **main 自己的變更**報成本分支造成的回歸 —— 那是假陽性。把基準移到 merge-base，
   L10 才是在量它一直想量的那件事：**本分支有沒有弄壞 POSIX**。
3. **不會讓覆蓋範圍變窄。** 兩個基準之間的差異全部是 main 的工作；已逐一稽核
   managed 清單的每一項新增，全部能追到 `origin/main`（`spec-archive`、
   `.agents/workflow/`、`.claude/agents/verifier.md`、`.codex/agents/verifier.toml`、
   `commit-message` → `commit`），沒有一項來自本分支。
   換基準反而**加驗了一件事**：合併時 `.chezmoiignore` 與 `.gitignore` 的衝突解法
   （取聯集）現在也被 L10 對著 main 的現況比對。
4. **property 層的差分沒有受影響。** P0 是拿 `dot_codex/modify_private_config.toml`
   的移植前 awk 原版做逐位元組比對；已驗證該檔在 `0d72b8e` 與 `ccae9d8` 之間
   **完全相同**，所以 P0 的比較對象不變。

如果你認為這仍算實質變更，那它就是一次 v7 修訂，需要重新核准 —— 這裡只記錄我的
判定與理由，不代替你的判斷。

**基準不會再往前追（2026-09-04 補記）。** Windows 支援已經併進 main（merge commit
`cbbdafc`），所以 `ccae9d8` 已經不是 `origin/main` 的頂端了 —— 原本那句「`origin/main`，
本分支與 main 的 merge-base」現在會誤導人，已改成「Windows 支援併進 main 之前的最後
一個 main 狀態」。**SHA 不變，而且不該變**：Must NOT #2 問的是「這次 Windows 支援有
沒有改變 POSIX 的既有行為」，比較對象必須是**還沒有這份移植的 main**。改成追 main
的頂端會變成拿它自己比它自己，這條不變量就等於沒有了。

### v5 → v6

| # | 變更 | 性質 |
|---|---|---|
| 1 | §3 的 L9 移除十條 `tool on PATH` 檢查與整段子程序查找機制（`Invoke-ToolLookup`、`tool lookup ran in a fresh process`） | **實質**（移除一項驗證） |
| 2 | §3 的 L9 新增九條 `winget list --exact --id`，逐一確認 `30-install-winget-packages` 清單裡的套件已安裝 | **實質**（新增一項驗證） |
| 3 | §7 新增具名已知限制：「工具在新終端機的 PATH 上」改由手動驗證，L9 不再宣稱 | **實質**（揭露少證了什麼） |

#### 為什麼拿掉

`tool on PATH` 這十條在 L9 的第二、三、四、五次執行都是紅的，**修了三輪都沒修好，
而且根因始終沒有找到**：

| 輪次 | 改法 | 本機驗證 | Sandbox 結果 |
|---|---|---|---|
| 1 | 固定四個目錄的 PATH 補強 → 重讀 registry 的 Machine+User | 通過 | 仍然十條全紅 |
| 2 | 改用 `[Environment]::GetEnvironmentVariable`，並讓重建過程留下報告 | 通過 | 仍然十條全紅（報告顯示 PATH 裡確實有 `WinGet\Links`、`mise\shims`、`mingw64\bin`） |
| 3 | 查找改到新程序裡做（子程序自己從 Machine+User 組 PATH） | 通過 | 子程序啟動成功、繼承 13 條 PATH，但父程序解析不到任何一條結果 |

本機以 Windows PowerShell 5.1 逐一實驗排除了七種機制，全部無法重現：負向查找快取、
檔案在程序啟動後才建立、`REG_EXPAND_SZ` 未展開、PATH 項目尾端反斜線、PATH 目錄裡是
symlink、子程序用絕對路徑啟動、以及最後一輪指出的父程序 console 強制 UTF-8 之後的
子程序回報通道（在主機上完整重現該條件，通道正常、三行輸出、tab 都在）。
使用者另外確認此問題**與 PowerShell 5 或 7 無關**。

也就是說：**本機不是那個 Sandbox 的可靠模型，本機綠燈對這一條而言是弱證據。**
這正是連續三輪「本機驗證通過、Sandbox 仍然失敗」的原因。

決定性的理由不是修不動，而是：**一條已知會紅的檢查會讓人學會忽略 FAIL。**
留著它並標記為「預期失敗」會侵蝕整份 results.tsv 的可讀性——那正是這一層唯一的產出。

#### 換成什麼

- **九條 `winget list --exact --id <id>`**，對象是 `30-install-winget-packages` 清單裡
  的九個套件。用的是**產品腳本自己的判斷指令**（那支腳本就是用同一條指令決定要不要
  安裝），在 Sandbox 內已證明可執行，而且**完全不依賴 PATH**。
- 搭配**既有的 M12 檢查**：它必須真的跑起 `nvim`、`gcc`、`tree-sitter` 才會產出
  lua parser，所以那三支「能不能執行」是被證明的。

兩條合起來覆蓋原本那十條想證明的大部分：套件裝了沒、關鍵工具能不能跑。

#### 少證了什麼（明寫）

**「其餘工具在使用者新開的終端機 PATH 上」不再有任何自動化程序。**
現有的證據只有手動驗證：使用者在 L9 第三次執行後於 Sandbox 內開新終端機，
逐一確認 mise、nvim 可用，並確認 `zig version` 回報 0.16.0。
這一項寫進 §7 的具名已知限制，L9 不再宣稱它。

### v4 → v5

全部來自 L9 遠端模式的兩次真實執行。

| # | 變更 | 性質 | 動到什麼 |
|---|---|---|---|
| 1 | §3 的 L9 一列新增「執行期間必須是可觀察的」 | 實質（可操作性） | 探針 |
| 2 | §3 的 L9 一列新增「PATH 判定以重讀 registry 為準」 | 實質（正確性） | 探針 |
| 3 | §6 新增 **M14**：Git for Windows 預設 `core.autocrlf=true` 把來源樹 checkout 成 CRLF；§7 更正原本「autocrlf 刻意不動」的推論 | 實質（失效模型缺口） | 產品 |
| 4 | §7 的 **M12 從「未證實」改為「假設已被推翻」**，處置待你決定 | 實質（需要決定） | 產品 |

**第 3、4 項的選擇已於 2026-09-03 決定**（`M14 選 c，M12 選 a`，逐字記在 §8）：
M14 → (c) 只加 `.gitattributes`、改寫器不動、殘留寫成具名已知限制；
M12 → (a) `zig.zig` 換成 `BrechtSanders.WinLibs.POSIX.UCRT`。

---

#### 1. L9 執行期間必須是可觀察的

探針有兩段會讓主控台長時間完全靜止：`PASS winget is available` 到
`PASS init.ps1 installs pwsh 7, git and chezmoi` 之間（三個 `winget install`，好幾分鐘），
以及 `probe: chezmoi init --apply ...` 之後（整個 apply 期間）。

原因是探針把子程序輸出**整段收進變數、跑完才印**。操作者因此分不出「還在跑」與
「卡死」，唯一的判斷依據是等待時間。遠端模式特別要命：Sandbox 一關什麼都沒有，
強制關閉等於整輪重來二三十分鐘。

要求：子程序輸出改成**邊收邊印**（`Tee-Object`，或逐行 `ForEach-Object` 同時寫主控台
與變數）；**FAIL detail 的內容維持不變**（仍是輸出尾段，格式不動）；每個長步驟開始前
印一行「正在做什麼、預期要多久」。**不得改變任何檢查的判定邏輯** —— 這是這一項的邊界。

不進 §6：它不會讓任何錯誤被發現或被漏掉，只影響操作者當下能不能判斷該等還是該中止。

---

#### 2. PATH 判定改讀 registry

L9 第二次執行回報十個工具全部 `not found`，但 `chezmoi init --apply` exit 0。
**這是探針的觀察錯誤，不是產品沒裝。** 兩條獨立證據：

- 這個 repo 只管一個 nvim 檔案（`AppData/Local/nvim/lua/plugins/completion.lua`）。
  `init.lua` 與 `.chezmoi-lazyvim-starter` 只可能來自 `50-neovim.ps1` 的 clone，
  而那支腳本在 `mise` 找不到時會**在 clone 之前 `exit 0`**。
  `nvim config is the LazyVim starter with our marker` 是 PASS，
  所以 mise 對那支腳本是可見的 —— 套件真的裝了。
- 使用者事後在 Sandbox 內開新終端機實測：mise、nvim 都正常。

根因：探針的 `Update-ProbePath` 只把**四個寫死的目錄**塞進 `$env:PATH`，而 Windows
的 PATH 是 process 啟動時的快照；探針程序在任何安裝發生之前就啟動了，winget 對
registry PATH 的更新它永遠看不到。

要求：改成重讀 registry 的 **Machine + User** PATH 再合成，而不是維護一份固定清單
（清單今天少哪一個目錄不是重點，機制本身就是錯的）。每一條 `tool on PATH` 的結果
一併記下**實際找到的路徑**，下一次失敗才讀得懂。

---

#### 3. M14：CRLF checkout（產品）

L9 第二次執行：`FAIL codex config.toml has the managed [tui] keys —
status_line_use_colors missing`。這條檢查在第一次執行時是空過的（見 evidence 的 P1），
這是它第一次真的讀到檔案。

根因已完整量測：

| 量測 | 結果 |
|---|---|
| .NET `(?m)^status_line_use_colors = true$` 對 LF | **match** |
| 同一條對 CRLF | **不 match**（`$` 落在 `\r` 之後） |
| 從 LF 來源樹產生的 `~/.codex/config.toml` | 全部 LF |
| 從 CRLF 來源樹產生的同一個檔 | 只有 `status_line_use_colors = true\r` 這一行帶 CR，其餘相同 |

也就是：Git for Windows 預設 `core.autocrlf=true` → 來源樹被 checkout 成 CRLF →
算繪結果把一個 `\r` 帶進受管的設定檔 → 探針那條 `$` 錨定的正則失敗。
**POSIX 端看不到**：L6 的 golden 與 329 個 property case 全部從 LF 樹跑。

修法（待核准後實作）：repo 加 `.gitattributes` 強制 LF checkout。這是 repo 端的性質，
不依賴使用者的 git 設定，而且一次關掉整類問題（每一份模板、每一支算繪出來的腳本），
不是只補這一個 key。

**一併需要你決定的一個附帶問題**：使用者**既有的** `~/.codex/config.toml` 如果本身是
CRLF（Windows 上的程式寫出來的常態），`modify_` 改寫器是逐行比對的，行尾的 `\r`
會讓它把 `key = value\r` 看成另一個東西。要不要讓改寫器正規化 CR？代價是它目前被
`gate-properties.py` 的 P0 釘在「與移植前的 awk 逐位元組相同」上，而 awk 原版不處理
CR —— 動它就是刻意脫離那個 parity。三個選項：

- **(a) 只加 `.gitattributes`，改寫器不動。** 成本最低，關掉來源端整類問題。
  殘留風險：使用者既有的 CRLF 設定檔仍可能被錯誤解析。
- **(b) `.gitattributes` + 改寫器正規化 CR。** 把殘留風險也關掉。
  代價：脫離 awk parity，P0 要重新定義，POSIX 端的輸出在含 CR 的輸入上會改變。
- **(c) 只加 `.gitattributes`，並把「既有 CRLF 設定檔」寫成具名的 known limitation。**
  誠實、成本低，但風險留著。

---

#### 4. M12：zig 當 C compiler 的假設已被推翻（產品，需要決定）

使用者在 Sandbox 內實跑 nvim：nvim-treesitter `main` 回報
`Unmet requirements: C compiler ❌`，curl / tar / tree-sitter CLI 都 ✅，
並建議 `winget install BrechtSanders.WinLibs.POSIX`。

SPEC 從 v1 就把 `zig.zig` 放進 winget 清單，理由是「社群做法是改用 zig」。
**那個假設在真機上不成立** —— 至少 nvim-treesitter 的需求檢查不認 zig。
這不再是 §7 的「未證實」，而是一條被推翻的假設。

選項（各自的代價都寫出來，請你選）：

- **(a) winget 清單把 `zig.zig` 換成 `BrechtSanders.WinLibs.POSIX`（gcc）。**
  這是 nvim-treesitter 自己建議的那一個，最可能一次過。
  代價：下載體積比 zig 大很多（數百 MB 級），安裝時間拉長；`zig` 本身若沒有別的用途
  就從清單移除。
- **(b) 保留 zig，另外設法讓 nvim-treesitter 認它**（例如設 `CC`，或在 LazyVim 設定裡
  指定 compiler）。代價：依賴 nvim-treesitter 的內部行為，脆弱，而且要另外找一個能
  在 L9 證明它有效的方式；在證明之前 M12 仍然是未解。
- **(c) 兩個都裝**（zig 保留給其他用途，另外加 WinLibs）。代價：安裝體積最大，
  且多一個要維護的 winget ID。
- **(d) 宣告 Windows 上不支援 treesitter parser 編譯**，把 M12 從失效模型移到具名的
  已知限制，LazyVim 在 Windows 上 treesitter 半殘。代價：功能缺口，但誠實且零成本。

SPEC §7 原本寫的備援是 `Microsoft.VisualStudio.2022.BuildTools`；依實測結果，
WinLibs 是更小也更直接的那一個，所以列在 (a) 而不是原備援。

**這四項在核准之前都不會實作。**

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
