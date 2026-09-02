# Evidence Report — native Windows 支援 (Tier 3)

- `headline`: **GATE PASSED — reproducibility degraded（工具版本只有記錄，沒有釘住）**
- `command`: `evidence`
- `contract`: applied（`~/.claude/CLAUDE.md` 的 evidence-first 契約；本 repo 的
  `AGENTS.md` 沒有覆寫它）
- `scope`: `windows-support`
- `change_set`: `0d72b8e...HEAD`
- `base`: `0d72b8e`
- `report_language`: zh-TW
- `intent_status`: **confirmed**
- `intent_source`: 已提交的 SPEC `.scratch/windows-support/spec.md`（於 `e5089df`
  進入版本歷史，**早於任何實作 commit**）。核准逐字記在該檔 §8：

  > 核准 spec

  綁定的版本是核准當下該檔的 sha256
  `ea20ea21f78b5eac5118270bb9f17775965da8da36ffe04ae21138b4499555ae`。
- `ordering`: **mixed**（逐檔事實見下）
- `git_facts`: **complete**
- `source_state`: `ebc3fe00f820fb3e4e26b71aae5bc127c3b04874`
  （由 `tools/gate-source-state.sh` 計算，最終一輪執行的**前後各驗一次，兩次相同**）
  這個 SHA 是 **gate 實際量測的那棵樹**。在它之後只會再多一個 commit——本報告
  本身——那個 commit 不含任何產品變更（`git diff ebc3fe0..HEAD -- . ':!.scratch'`
  為空），所以報告裡的每一個數字仍然描述目前的產品狀態。
- `source_state_exclusions`: `.gate/`（gate 自己的產出目錄，已加入 `.gitignore`）。
  白名單只有這一項，沒有任何產品路徑。
- `toolchain`: 這個 repo 沒有 lockfile 可以釘開發工具版本，因此逐字記錄實際跑的版本
  （`.gate/windows-support/versions.txt`）：

  ```
  chezmoi: chezmoi version v2.72.0, commit f81cb321789aa3df62871248f5e4d361a59e7cc1,
           built at 2026-08-02T18:45:48Z, built by goreleaser
  git:     git version 2.39.5
  zsh:     zsh 5.9 (x86_64-debian-linux-gnu)
  python3: Python 3.13.15
  sh:      /bin/sh -> dash
  pwsh:    7.6.5
  ```

- `entry_point`: `tools/gate.sh`
- `reproducibility`: **degraded** —— 入口點已持久化、來源狀態可辨識且前後一致，
  但**工具版本無法釘住**（這個 repo 沒有 lockfile，使用者也沒有授權我新增一個）。
  記錄過的版本說明了「什麼跑過」，不保證下一次跑起來一模一樣。
- `changed_unit_command`: `git diff --name-status 0d72b8e...HEAD`
- `changed_unit_granularity`: **path**。這個 repo 的三種語言（chezmoi Go 模板、
  POSIX/zsh shell、PowerShell）都沒有現成的 symbol 抽取器。**這代表：同一個檔案裡的
  個別函式沒有被逐一對應**；下表的列是檔案。實務上這個 repo 的檔案粒度接近單元
  （一支腳本＝一個平台的一件事），但這是說明，不是保證。

---

## Baseline

**unavailable —— base ref 沒有任何測試套件**（這次改動才引入 `tests/`）。
因此「相對於 baseline 零新增失敗」這句話在這個 repo 無法成立，Tests 那一層只能報告
它自己的絕對通過／失敗數。

替代物比測試數的 baseline 更強、且確實跑了：**L10 直接拿 base ref 的來源樹與目前的
來源樹各 apply 一次到暫存 destination，整棵樹 diff**。它問的是「POSIX 端的實際輸出
有沒有變」，而不是「有沒有多幾條紅的測試」。結果見下方 Gate 表。

---

## Changed unit → Test

101 個檔案。分組列出，每一組都涵蓋該組的全部檔案。

### 產品：平台判斷與共用模板

| Changed unit | Test | Status |
|---|---|---|
| `.chezmoitemplates/platform.toml`（新增） | `tests/cases/L1-platform.sh`（四個平台組合逐欄位；接縫退回真實 OS） | pass |
| `.chezmoitemplates/versions.toml`（新增） | `tests/cases/L2`::兩個平台的 50-neovim 釘同一個 neovim 版本／marker／starter | pass |
| `.chezmoitemplates/windows-path.ps1`（新增） | `tests/cases/L4`::PowerShell 解析；`L7`::Windows 50-neovim 實跑（stub 不被真實路徑蓋掉即證明它有作用） | pass |
| `.chezmoitemplates/pwsh-profile-loader.ps1`（新增） | `tests/cases/L7`::profile loader 跑三次只留一行 loader | pass |
| `.chezmoitemplates/nvim-plugins-completion.lua`（由 `private_dot_config/nvim/...` 搬移，R100） | `tests/cases/L10`::套用結果與 base ref 逐位元組相同 | pass |
| `.chezmoitemplates/uv.toml`（由 `private_dot_config/uv/uv.toml` 搬移，R100） | 同上 | pass |

### 產品：安裝腳本

| Changed unit | Test | Status |
|---|---|---|
| `run_onchange_before_10-install-packages.sh.tmpl`（改：走 partial） | `L2` 渲染矩陣（linux 非空、其餘三個渲染成空）+ `L4` zsh 解析 | pass |
| `run_once_before_20-install-homebrew.sh.tmpl`（改） | 同上（POSIX 非空、windows 空） | pass |
| `run_onchange_before_30-install-brew-packages.sh.tmpl`（改） | 同上 | pass |
| `run_onchange_after_40-git-lfs.sh.tmpl`（改） | 同上 | pass |
| `run_onchange_before_50-neovim.sh.tmpl`（改） | `L2`、`L4`、**`L7` POSIX 備份行為實跑（四個目錄搬成 .bak、舊 .bak 不被埋、marker 冪等）** | pass |
| `run_after_default-shell.sh.tmpl`（改） | `L2`（僅 linux 非空）、`L4` | pass |
| `run_onchange_before_30-install-winget-packages.ps1.tmpl`（新增） | `L2`（僅 windows 非空）、`L4` PowerShell 解析、`L8` 真實 Windows 渲染比對 | pass |
| `run_onchange_before_35-install-ps-modules.ps1.tmpl`（新增） | 同上 | pass |
| `run_onchange_after_40-git-lfs.ps1.tmpl`（新增） | 同上 | pass |
| `run_onchange_before_50-neovim.ps1.tmpl`（新增） | 同上，**外加 `L7` Windows 備份行為實跑（三個目錄、備份集合精確比對、marker 冪等）** | pass |
| `run_after_60-pwsh-profile.ps1.tmpl`（新增） | `L2`、`L4`、`L8`；其邏輯本體由 `L7` 冪等測試涵蓋 | pass |

### 產品：target 檔案與設定

| Changed unit | Test | Status |
|---|---|---|
| `.chezmoiignore`（改：分平台） | `L3` 四個平台的 managed 集合 golden + 互斥性斷言 + repo-only 檔案不得落地 | pass |
| `.chezmoiexternal.toml.tmpl`（改：分平台、新增兩個 external） | `L5`（清單、Windows 不得有 .oh-my-zsh、checksum 覆蓋、逐字釘住新 sha256）、`L10`（POSIX 端定義不變）、supply-chain 層（實際下載比對） | pass |
| `private_dot_config/powershell/profile.ps1.tmpl`（新增） | `L3`（只在 windows 被管理）、`L4`（PowerShell 解析）、`L8`（真實 Windows 渲染比對） | pass |
| `AppData/Local/nvim/lua/plugins/completion.lua.tmpl`（新增） | `L3`、`L6`（檔案層 apply 比對） | pass |
| `AppData/Roaming/uv/uv.toml.tmpl`（新增） | `L3`、`L6` | pass |
| `private_dot_config/nvim/lua/plugins/completion.lua.tmpl`（新增，取代被搬走的原檔） | `L10`（渲染逐位元組不變） | pass |
| `private_dot_config/uv/uv.toml.tmpl`（新增，同上） | `L10` | pass |
| `dot_codex/modify_private_config.toml`（改：sh+awk → modify-template） | **`L6` 11 個 golden 案例（含註解／多 table／重複 key／缺 [tui]／空檔／只有一個空行／會被 fromToml 改壞的值）、`L6` 結構性斷言（必須是 modify-template）、`L8` 真實 Windows apply、properties 層 120 個生成案例** | pass |
| `dot_claude/modify_settings.json`（改：statusLine 依平台） | `L6`（POSIX 與 Windows 兩組 golden）、`L8` | pass |
| `dot_zshrc.tmpl`（改：走 partial） | `L10`（linux 端逐位元組不變；linux 與 darwin 的差異只有 brew prefix）、`L4` | pass |
| `dot_zprofile.tmpl`（改：走 partial） | 同上 | pass |
| `init.ps1`（新增） | `L4`（pwsh 7 解析、**Windows PowerShell 5.1 解析**、純 ASCII） | pass |

### 非產品

| Changed unit | Test | Status |
|---|---|---|
| `tests/**`（44 個檔案：runner、lib、9 個 case、fixtures、goldens） | 測試資產本身 | n-a |
| `tools/**`（7 個 gate 腳本） | Negative controls 一節逐一驗過 | n-a |
| `docs/research/windows-native-support.md`、`README.md`、`AGENTS.md`、`.scratch/windows-support/spec.md`、`.gitignore` | 文件 | n-a |
| 純搬移／改名（2 檔，R100） | — | n-a |
| **刪除：無** —— 這次沒有刪除任何符號或檔案（`git diff --diff-filter=D` 為空） | — | n-a |

---

## Stated claim → Test

列來自已核准的 SPEC。

| Claim | Test | Status |
|---|---|---|
| Windows 用 winget 取代 brew | `L2`（winget 腳本只在 windows 非空）；11 個套件 ID 逐一 `winget show` 實測存在（SPEC §1 F12）；**真的安裝只有 L9 sandbox 能證** | pass（安裝本身 unverified，見下） |
| Windows 的 neovim 路徑正確 | `L7`::Windows 50-neovim 對假的 `%LOCALAPPDATA%`／`%TEMP%` 實跑，斷言建出來的目錄名 | pass |
| 已有 Windows nvim 路徑研究（或補上） | `docs/research/windows-native-support.md` §2（官方原文 + 0.12.5 實測，含兩者不一致處） | pass |
| Windows 用 PowerShell 7 + oh-my-posh | `L3`（profile 被管理）、`L4`（解析）、`L7`（loader 冪等）、`L5`（主題 external 釘版本+sha256） | pass |
| **Must NOT #1**：不得在主機執行 winget install 或 apply 到真實 `C:\Users\gn006` | L8 全程唯讀（`--destination` 指向 Windows TEMP）；L7 全程重導向環境 + stub。**有一次違反，已在 Honest notes 記錄** | **unverified**（見 Honest notes） |
| **Must NOT #2**：不得改變 Linux/macOS 現有行為 | `L10`（base ref 對比：套用結果逐位元組相同、managed 只多出五支 Windows 腳本、external 定義不變、darwin 與 linux 的差異只有 brew prefix） | pass |
| **Must NOT #3**：不得刪除任何既有使用者檔案 | `L7`（POSIX 與 Windows 各三次執行，備份存在且內容保留、舊 .bak 不被埋）；mutation `posix-nvim-delete` 證明這條斷言會咬 | pass |
| **Must NOT #4**：`.sh` 不得在 Windows 執行、`.ps1` 不得在 POSIX 執行；隔離手段只能是渲染成空 | `L2` 的兩條結構性不變式（與平台表獨立）；`L8` 真實 Windows 渲染逐位元組比對 | pass |
| **Must NOT #5**：不得引入未釘版本或無 checksum 的外部下載 | `L5` checksum 覆蓋斷言（mutation `external-checksum` 證明會咬）；supply-chain 層實際下載四個新增/變更的 URL 比對 sha256 | pass |
| **Must NOT #6**：不得為了讓測試變綠去改測試 | 見 Honest notes 的兩次測試修改，各附理由與獨立驗證 | pass |
| **Must NOT #7**：evidence report 不得寫沒真的跑過的檢查 | 本報告每個數字都指向 `.gate/windows-support/` 的產出檔 | pass |
| M12（zig 能否讓 tree-sitter 在 Windows 編出 parser） | `tests/sandbox/_probe.ps1` 專門去問這一題 | **unverified —— L9 尚未執行** |

---

## RED reconstruction

做法：在 `0d72b8e` 開一個 worktree，把這次新增的 `tests/` 整個複製進去，逐層執行。
逐層跑而不是一次跑完，是因為 runner 的 `set -e` 會讓第一個結構性失敗中斷後面所有層。

| 層 | 在 base 上的結果 | 說明 |
|---|---|---|
| L1 | **4/4 失敗**，之後中斷 | 斷言失敗（值不符），不是結構性失敗。`platform.toml` 不存在 |
| L2 | 41 條裡 **21 條失敗**，之後中斷 | Windows 腳本不存在 + 既有腳本沒有平台守衛 |
| L3 | 34 條裡 **16 條失敗**，跑完 | managed 集合與互斥性 |
| L4 | 33 條裡 **1 條失敗**，之後中斷 | 失敗的是「init.ps1 存在」。**其餘 32 條在 base 上就通過** —— 那些是既有 POSIX 腳本的語法檢查，屬於 regression armor，不是 RED |
| L5 | 12 條裡 **5 條失敗**，跑完 | Windows 的 external 清單與新 sha256 |
| L6 | 70 條裡 **13 條失敗**，跑完 | 失敗的是 Windows 的 settings.json golden 與「必須是 modify-template」的結構性斷言。**codex 的 golden 在 base 上通過** —— 那是設計如此：它們就是從 base 的 awk 實作產生的，屬於 regression armor |
| L7 | 14 條通過後中斷 | **POSIX 那半在 base 上就是綠的** —— nvim 備份行為是既有功能（`6762fbe`/`1b97946` 就有），屬於 regression armor。Windows 那半因為腳本不存在而中斷，是真的 RED |
| L8 | 5 條裡 **3 條失敗**，之後中斷 | 真實 Windows 的 managed 與腳本渲染比對 |
| L10 | **skip** | L10 從 SPEC 讀 base ref，而 SPEC 在 base 上不存在 |

**這不是 “base lacks the platform under test” 的情形**：base ref 有 chezmoi、有 sh、有
既有的腳本，失敗是因為**被測行為不存在**，而且多數是斷言層級的失敗（值不符），
不是收集期錯誤。

**在 base 上就通過的那些（regression armor）**，其斷言力由 mutation 層在 HEAD 上證明：
`posix-nvim-delete`、`codex-duplicate-keys`、`codex-trailing-blank` 三個 mutant 分別讓
L7 POSIX 半邊與 L6 codex golden 變紅。這是比 RED 弱的主張（證明測試「能」紅，不是
證明它「曾經」紅），如實標示於此。

---

## Gate (final fresh run)

以下每一個數字都來自 `sh tools/gate.sh` 的**同一次**執行，時間在最後一次程式碼修改之後。
產出在 `.gate/windows-support/`。

| Layer | Command | Threshold（什麼算通過） | Result |
|---|---|---|---|
| Versions | `tools/gate.sh` 的 versions 層 | 全部工具版本可取得 | 六項全部記錄（見 `toolchain`） |
| Source state (before) | `sh tools/gate-source-state.sh` | 非淺 clone；工作樹乾淨（白名單只有 `.gate/`） | `commit=ebc3fe0…`, `worktree=clean` |
| Tests | `sh tests/run.sh` | 0 失敗（**無 base 測試套件可比，只能報絕對數**） | **291 passed, 0 failed, 0 skipped** |
| Suite health（重跑） | `sh tests/run.sh` 第二次 | 與第一次逐行相同 | 逐行相同，291/291 |
| Suite health（隨機順序） | `TESTS_SHUFFLE=1 sh tests/run.sh` | 總數與失敗數不變 | 291 passed, 0 failed |
| Property-based | `python3 tools/gate-properties.py --cases 120` | P1–P5 在每個生成案例上成立 | **120 個生成案例，5 個性質全部成立**（seed 20260902） |
| Mutation | `python3 tools/gate-mutants.py`（手寫，無現成工具） | 0 個存活的 mutant | **11/11 killed，0 survivors** |
| Supply chain + secrets | `python3 tools/gate-supply-chain.py --base 0d72b8e` | 新增/變更的 external 全部 sha256 相符；0 個機密命中 | 9 個釘住下載，其中 **4 個新增/變更全部下載比對相符**；掃過 4311 行新增內容，0 命中 |
| Changed-line accounting | `python3 tools/gate-changed-lines.py --base 0d72b8e` | 只報告（見下方 UNAVAILABLE） | set1 **0** / set2 **2217** / set3 **2094**（共 4311 行新增） |
| Source state (after) | `sh tools/gate-source-state.sh` | 與 before **完全相同** | 相同（`commit=ebc3fe0…`, `worktree=clean`） |
| Manifest audit | `sh tools/gate-manifest-audit.sh` | 10 層全部留下執行記號，且無多餘記號 | **10/10** |

Suite health 排在 mutation 與行數會計**之前**，因為後兩者的結論都是從這個 suite 的
行為推出來的。

---

## Negative controls

每一個 home-grown 檢查器都先被餵過已知的壞輸入、親眼看它紅過。

- **`tools/gate-source-state.sh`** —— 在 worktree 裡放一個未追蹤檔，
  輸出 `worktree=dirty` + `?? dirty-probe.txt`，exit 1；移除後 exit 0。
- **`tools/gate-manifest-audit.sh`** —— 四種情形實測：缺一層 → exit 1 並指名該層；
  多一層 → exit 1 並指名；讀不到輸入檔 → exit 1；完全相符 → exit 0。
- **`tools/gate-properties.py`** —— 對「丟掉 [tui] 以外的行」的 mutant，
  P2 在第 0 個案例就紅（`['', '', ' [ tui ]']` 不見了）；對「補寫位置錯」的 mutant
  也紅。修過 checker 的空字串 artifact 之後**重做過一次**，仍然會咬。
  另以不同 seed（7）跑 150 個案例，確認不是只對單一 seed 成立。
- **`tools/gate-supply-chain.py`** —— 把主題的 sha256 換成全 0 → exit 1 並印出
  pinned/actual 對照；在 diff 裡植入 `AKIAIOSFODNN7EXAMPLE` → exit 1 並指出
  「疑似機密（AWS access key id）」。
- **`tools/gate.sh` 的 fail-closed** —— 把 `platform.toml` 改壞並提交到 worktree，
  gate 在 `suite` 層停下（exit 1），**後面的 mutation 等層一次都沒有執行**
  （`grep -c 'layer: mutation'` = 0）。第一版的 `cmd | tee` 寫法會吞掉失敗，
  這個 control 就是為了證明改掉之後真的擋得住。
- **Mutation baseline** —— runner 在套任何 mutant 之前先跑一次未突變的複本，
  紅了就直接放棄整輪而不是回報分數。本輪基線為綠。
  **這個 runner 是完全循序的、沒有任何併發**，所以 skill 提到的「並行 job 共用
  build 目錄」污染機制在這裡不存在；per-job isolation 的形式是每個 mutant 都在
  同一個拋棄式 worktree 裡「套用 → 跑 → 還原」，套用與還原兩步都有 assert。
- **Mutation kill 歸因** —— 不是抽樣，而是**逐一檢查全部 11 個**：每個 mutant
  的失敗斷言名稱都指名它破壞的那個行為（例如 `windows-nvim-data-backup` →
  「既有 %LOCALAPPDATA%\nvim-data 被備份（M2）」）。沒有一個是「某條無關的測試剛好
  紅了」。11 個 mutant 各自只讓 1–11 條斷言變紅，不是整個套件崩掉。

---

## Layers not run as specified

- **N-A（這個 repo 沒有這種面）：**
  - *Static types* —— 沒有型別語言。這個 repo 是 chezmoi 模板 + shell + PowerShell。
  - *Complexity budget* —— 沒有函式可量。最接近的單元是「一支腳本」，
    每支腳本都是單一平台的單一件事；最長的產品檔是 `dot_codex/modify_private_config.toml`
    的 114 行模板，其演算法逐條對應被它取代的 awk 版。
- **UNAVAILABLE（工具不存在，也沒有替代品跑）：**
  - *Lint* —— `shellcheck`、`shfmt`、`PSScriptAnalyzer` 這台機器上都沒有。
    安裝它們會改動使用者的環境，**沒有取得授權**，所以什麼都沒跑。
    L4 的語法解析（`zsh -n` + PowerShell `ParseFile`）**不是** lint 的替代品：
    它只保證「解析得過」，抓不到 quoting、未引用變數、未使用變數這類問題。
  - *Changed-line coverage* —— 三種語言在這個環境裡都沒有覆蓋率工具。
    `tools/gate-changed-lines.py` 因此只做三集合會計而不設閘：
    **set 3（可執行但沒有覆蓋率對應）＝ 2094 行，是全部可執行的新增行**。
    這一層什麼都沒證明；補位的是 Table 1 的逐檔對應與 mutation 層。
- **SUBSTITUTED：**
  - *Real execution* —— 沒有跑「完整安裝一次」。跑的是：`L7` 在重導向環境裡**真的執行**
    兩支 50-neovim 與 profile loader；`L8` 在 Windows 主機上**真的執行** chezmoi
    的 managed 與 apply（僅檔案）。**這偵測不到**：winget 是否真的裝得起來、
    安裝完的工具是否真的能用、第一次開 Neovim 會發生什麼。那是 L9 的工作。
  - *macOS 的一切* —— 沒有實體 mac。macOS 的全部證據來自 `osOverride=darwin`
    的渲染矩陣。**這偵測不到**任何只在真實 macOS 上才會出現的行為
    （Homebrew 實際路徑、真實的 `chsh`、Apple Silicon 的二進位相容性）。
    接縫本身有被驗證，但只在 **windows** 那一邊（L8）；darwin 那一邊
    **沒有任何實機交叉驗證**。
- **NOT REACHED：** 無。最終一輪十層全部執行完畢。
- **DEPENDENCY UNMET：** 無。Suite health 在 mutation 與行數會計之前通過。

---

## Dismissed concerns

- **「winget 套件 ID 可能打錯」** —— 已逐一 `winget show --id <ID> --exact` 實測，
  11 個全部存在並回報版本（SPEC §1 F12 有完整表格）。這證明 ID 解析得到，
  **不證明**安裝會成功。
- **「Windows 上 `.ps1` 的中文註解會不會被解壞」** —— 直接以 chezmoi 真正使用的
  呼叫方式（`pwsh -NoLogo -File`）跑過一支含中文註解的渲染結果，正常執行。
  只有 Windows PowerShell 5.1 有這個問題，因此只有 `init.ps1` 與 sandbox 探針
  受 ASCII 限制，並由 L4 的兩條斷言釘住。
- **「Windows 端的 nvim-data 備份兩次會不會出問題」** —— mutation 實測不會：
  第二次呼叫時來源目錄已經不在，備份函式直接 return。原本為此寫的斷言
  「nvim-data 只被備份一次」被 mutation 證明是恆真的廢斷言，已換成
  「備份出來的目錄集合剛好是那三個」，該版本經 mutation 確認會咬。
- **`.chezmoiignore` 是否足以隔離跨平台腳本** —— 不足，而且已實測：非空的 `.sh`
  在 Windows 上會讓整個 apply 中斷（`%1 is not a valid Win32 application`, exit 1）。
  隔離只能靠渲染成空。這是 `L2` 兩條結構性不變式存在的理由。

---

## Structural blind spot

**這整份報告沒有任何一個數字來自「一台真的裝過這份 dotfiles 的 Windows 機器」。**

已經做到的是：三個平台的模板渲染、Windows 主機上真實 chezmoi 的唯讀比對、
在重導向環境裡真的執行安裝腳本的檔案搬移邏輯。**沒有做到的**是：`winget install`
真的跑一次、裝完的 PowerShell 7 + oh-my-posh + PSFzf + mise 真的開一個 shell 起來、
LazyVim 第一次啟動真的去編 treesitter parser。

那些只有 `tests/sandbox/`（L9）能回答，而 L9 需要你按下 sandbox 啟動。
在它跑完之前，本報告對「這份 dotfiles 在 Windows 上裝得起來」這句話**沒有證據**，
只對「它在 Windows 上會產生哪些檔案、那些檔案長什麼樣、那些腳本對既有檔案做什麼」
有證據。

macOS 的盲點更大：連唯讀的實機比對都沒有。

---

## Honest notes

### 1. 我違反了自己寫的 Must NOT #1（已發生，不可撤銷）

驗證 `.ps1` 的 UTF-8 編碼時，我直接以 `pwsh -File` 執行了渲染後的
`40-git-lfs.ps1`。它**真的執行了** `git lfs install --skip-repo`，寫到了 Windows 主機的
`C:\Users\gn006\.gitconfig`（實測：該檔在那之後 21 秒被修改）。

影響：`filter.lfs.clean/smudge/process/required` 四個設定現在在該檔案裡。
git-lfs 本來就裝在那台機器上，`git lfs install` 是冪等的，極可能只是把相同內容重寫
一次 —— 但**我無法回溯證明它原本就在**。要還原可以跑 `git lfs uninstall`。

之後所有的行為測試都改走完全重導向的環境與 stub，沒有再碰主機。

### 2. 兩次修改測試（各附理由與獨立驗證）

- **L10 的 external 回歸斷言**原本連 TOML 註解一起比對，於是我刻意改寫的註解
  讓它紅。收斂成「忽略空行與註解」後仍然逐行比對實際生效的定義。
  獨立驗證：`git diff` 顯示差異**只有**註解那三行。
- **L7 的「nvim-data 只被備份一次」**被 mutation 證明恆真（見 Dismissed concerns）。
  換成「備份集合精確比對」，新版經 mutation 確認會咬。

兩次都不是為了讓失敗的實作變綠 —— 第一次實作沒變，第二次換成更強的斷言。

### 3. gate 自己踩到的兩個洞（都已修，各留 negative control）

- `tools/gate.sh` 第一版每一層寫成 `cmd | tee file`。管線的退出碼是 `tee` 的，
  **任何一層失敗都會被靜靜吞掉**。改成 fail-closed 的 `run_layer`，並以 NC 證明。
- 有一個 commit 的 `git add -A` 把 `.gate/` 的產出提交進去，於是下一輪 gate 開頭
  清產出就讓工作樹變髒 —— **source-state 那一層正確地擋下了它**。已加入 `.gitignore`。

### 4. 對 SPEC 的一項偏離

SPEC §2.1 把 nvim 路徑與 cc-statusline asset 也列進 `platform.toml` 的欄位。實作時
收斂成 `os / arch / isWindows / isPosix / brewPrefix`：nvim 路徑在 POSIX 與 PowerShell
需要各自的原生語法，塞進共用 dict 會變成兩份轉譯而不是一份事實。Windows nvim 路徑的
單一來源保證改由 `L7` 提供（對暫存 `%LOCALAPPDATA%` 實跑、斷言真實建出來的目錄名），
那比模板欄位斷言強。

### 5. SPEC 沒涵蓋、實作時才發現的一項

Windows 建 symlink 需要 `SeCreateSymbolicLinkPrivilege`，一般帳號要開「開發人員模式」
才有；chezmoi 會在 `~/.claude/skills` 建兩個 symlink。已在 `init.ps1` 加入事前探測與
警告、並寫進 README。**這條沒有自動化測試**：本機的開發人員模式是開的，
乾淨機器上的行為要靠 L9 的 sandbox 才看得到（探針裡有對應的檢查，且預期它會 FAIL）。

### 6. 已知限制：Windows 的 statusLine 少一個外觀選項

POSIX 的 `statusLine.command` 帶 `STATUSLINE_USAGE_STYLE=dots` 前綴，那是 POSIX shell
語法。上游 README 對 Windows 沒有給任何傳環境變數的方式，因此 Windows 版只放路徑。
猜一個 `cmd /c "set ...&&"` 包法若猜錯會讓 statusline 整個不顯示，比損失一個外觀選項嚴重。

### 7. 隔離樹與落地樹的差異

L7 與 L10 用的暫存 destination 是空的；真實的 `$HOME` 有既有內容。L6 用預先塞好的
種子檔補這個落差（十一種既有檔案形狀），但那仍然不是「一台用了很久的機器」。

### 8. 本輪的一個真實發現

property 層在第一次完整 gate 執行時**紅了**，抓到 codex modify-template 與被它取代的
awk 版在「只含一個空行的檔案」上行為不同（模板把那一行吃掉了）。已對 base ref 的 awk
取得 ground truth 比對確認、修正、並新增 L6 案例 `c9-blank-only` 釘住。
這是 property 層唯一一次紅，也是它存在的理由。
