# Evidence Report — native Windows 支援 (Tier 3)

- `headline`: **GATE PASSED — reproducibility degraded（工具版本只有記錄，沒有釘住）。
  L9 已首次真實執行並 FAIL：根因已定位並修好（M13，ExecutionPolicy），但修好之後
  沒有再跑過一次 L9 —— 這份報告仍然沒有任何一個數字來自一台裝成功的 Windows**
  · 獨立驗證跑了**六輪**，六輪都判 failed；共 47 條 findings 全部已處置，見 §獨立驗證。
  **最後兩輪在產品程式碼裡找不到任何缺陷**；第六輪明確建議不要再跑第七輪，
  把剩下的風險預算花在還沒跑過的 Windows Sandbox 上
- `command`: `evidence`
- `contract`: **applied**（`~/.claude/CLAUDE.md` evidence-first v0.6，無覆寫）。

  先前這一欄記的是 `overridden by docs/agents/issue-tracker.md`。**該主張已撤回。**
  使用者裁定：那份文件規範的是 **issue** 的位置，不是 spec；兩者不是同一種產物，
  拿它來覆寫契約的 SPEC 路徑不成立。SPEC 已搬到契約指定的
  `specs/windows-support/SPEC.md`，CLOSE 步驟的 `spec-archive` 因此讀得到。

  該文件本身的用字在 `feat/evidence-first-contract` 的 `bfcdc9a` 已另行處理，
  不在本分支改動。
- `scope`: `windows-support`
- `change_set`: `0d72b8e...HEAD`
- `base`: `0d72b8e`
- `report_language`: zh-TW
- `intent_status`: **unconfirmed**（v1–v4 已核准；**v5 待核准，尚未實作**）
- `intent_source`: 已提交的 SPEC `specs/windows-support/SPEC.md`，`spec_version: v5`。
  v1 於 `e5089df` 進入版本歷史（當時路徑 `.scratch/windows-support/spec.md`），
  **早於任何實作 commit**；核准逐字記在該檔 §8：

  > 核准 spec

  v2 的實質變更只有一項（§7 新增「備份撞名（accepted risk）」），其餘為路徑與
  標頭的形式變更 —— 完整清單在 SPEC §9 Revisions。契約規定核准綁定單一版本，
  v1 的核准不延伸到 v2，因此 v2 另行取得核准，同樣逐字記在 SPEC §8：

  > 核准 SPEC v2

  v3 同理另行核准，唯一的實質變更是 §3 的 L9 一列新增遠端模式（`_probe.ps1 -Branch`），
  屬驗證程序擴充，不動 §5 Must NOT、§6 失效模型或任何產品需求（詳見 SPEC §9）：

  > 核准 SPEC v3

  v4 同理另行核准（§6 新增失效模式 **M13**，§7 更正 M12 的狀態；M13 是 L9 第一次
  真實執行找出來的，是原本整個漏掉的一種失效模式）：

  > 核准 SPEC v4

  **v5 待核准，而且刻意停在這裡**：本輪是「修訂中停下來等」——SPEC 已寫好、已提交，
  但**產品與探針一行都沒動**。v5 有四項，其中 M12 的處置與 CRLF 改寫器那一項需要
  使用者在選項之間做決定，見 SPEC §9 的 v4 → v5。

- `ordering`: **mixed**（逐檔事實見 §RED reconstruction）
- `git_facts`: **complete**
- `source_state`: `1e94ff8e091fdf22ec4d2fd5f673f67808c16ac4`
  （由 `tools/gate-source-state.sh` 計算，最終一輪執行的**前後各驗一次，兩次相同**）

  這個 SHA 是 gate 實際量測的那棵樹。在它之後只有一個 commit：把 v3 的核准逐字
  寫進 SPEC §8、並把本報告更新到這一輪數字的那一個。它只動 `.scratch/` 與
  `specs/windows-support/SPEC.md`，**不含任何產品、測試或 gate 檔案**
  （可用 `git diff --stat 1e94ff8..HEAD` 核對）。SPEC 那個檔案確實會被 L3 與 L10
  讀到（前者斷言它不得被裝進 `$HOME`，後者從中取 base ref），所以最終那棵樹
  另外跑了一次完整測試套件確認 **489/489**；mutation、property、supply-chain
  三層的結論不可能被一段 markdown 核准記錄影響，沒有重跑。**上一輪報告在這裡踩過一次坑**：
  寫完報告後又提交了一個產品檔（`tests/sandbox/prepare.sh`），使得報告的自我描述
  在下一秒就過期。這次改成「報告是最後一個 commit」。
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

- `entry_point`: `sh tools/gate.sh`
- `reproducibility`: **degraded** —— 入口點已持久化、來源狀態可辨識且前後一致，
  但**工具版本無法釘住**（這個 repo 沒有 lockfile，使用者也沒有授權我新增一個）。
  記錄過的版本說明了「什麼跑過」，不保證下一次跑起來一模一樣。
- `changed_unit_command`: `git diff --name-status 0d72b8e...HEAD`
- `changed_unit_granularity`: **path**。這個 repo 的三種語言（chezmoi Go 模板、
  POSIX/zsh shell、PowerShell）都沒有現成的 symbol 抽取器。**這代表：同一個檔案裡的
  個別函式沒有被逐一對應**；下表的列是檔案。

---

## Baseline

**unavailable —— base ref 沒有任何測試套件**（這次改動才引入 `tests/`）。
因此「相對於 baseline 零新增失敗」在這個 repo 無法成立，Tests 那一層只能報告
它自己的絕對通過／失敗數。

替代物比測試數的 baseline 更強、且確實跑了：**L10 直接拿 base ref 的來源樹與目前的
來源樹各 apply 一次到暫存 destination，用 `diff -r` 整棵樹比對**。

---

## Changed unit → Test

139 個檔案，其中 137 個在 `.scratch/` 之外（另兩個是 SPEC 與本報告）。
分組列出，每一組涵蓋該組全部檔案。

> 這個數字由 `changed_unit_command` 直接產生。**上一版寫 101，是舊的**：
> 第一輪修補加了約 25 個檔案而我沒有更新分母 —— 那正是獨立驗證第二輪的 F5(a)。

### 產品：平台判斷與共用模板

| Changed unit | Test | Status |
|---|---|---|
| `.chezmoitemplates/platform.toml`（新增） | `L1`（四個平台組合逐欄位；無 override 時退回真實 OS） | pass |
| `.chezmoitemplates/versions.toml`（新增） | `L2`（兩個平台的 50-neovim 釘同一個版本／marker／starter）、`L5`（PSFzf 版本） | pass |
| `.chezmoitemplates/windows-path.ps1`（新增） | **`L11-C`（渲染 golden，涵蓋整個 partial）**、`L2`（PATH 條目斷言）、`L4`。~~`L7`~~ 對這個單元結構上是盲的（它把 `%ProgramFiles%` 重導向到空沙盒），已從對應中移除 | pass |
| `.chezmoitemplates/pwsh-profile-loader.ps1`（新增） | `L7`（跑三次恰好留下一行、**內容逐字比對**） | pass |
| `.chezmoitemplates/nvim-plugins-completion.lua`（搬移 R100） | `L10`（`diff -r` 與 base ref 相同） | pass |
| `.chezmoitemplates/uv.toml`（搬移 R100） | 同上 | pass |

### 產品：安裝腳本

| Changed unit | Test | Status |
|---|---|---|
| `run_onchange_before_10-install-packages.sh.tmpl`（改） | `L2` 渲染矩陣 + `L4` zsh 解析 | pass |
| `run_once_before_20-install-homebrew.sh.tmpl`（改） | 同上 | pass |
| `run_onchange_before_30-install-brew-packages.sh.tmpl`（改） | 同上 | pass |
| `run_onchange_after_40-git-lfs.sh.tmpl`（改） | 同上 | pass |
| `run_onchange_before_50-neovim.sh.tmpl`（改） | `L2`、`L4`、**`L7` POSIX 備份行為實跑（四次執行；三份備份彼此獨立、無巢狀；在 mount namespace 裡隔離）** | pass |
| `run_after_default-shell.sh.tmpl`（改） | `L2`（僅 linux 非空）、`L4` | pass |
| `run_onchange_before_30-install-winget-packages.ps1.tmpl`（新增） | **`L11-C`（渲染 golden —— supply-chain 只驗「列出來的 ID 解析得到」，少一個它不會失敗）**、`L2`、`L4`、`L8`、supply-chain | pass |
| `run_onchange_before_35-install-ps-modules.ps1.tmpl`（新增） | **`L11-C`**、`L2`、`L4`、`L8`、`L5`「Install-PSResource 必須帶 -Version」 | pass |
| `run_onchange_after_40-git-lfs.ps1.tmpl`（新增） | **`L11-C`**、`L2`、`L4`、`L8` | pass |
| `run_onchange_before_50-neovim.ps1.tmpl`（新增） | **`L11-C`**、**`L7` Windows 備份行為實跑（三個目錄、備份集合精確比對、marker 冪等、**mise 不存在時的退出碼**）**、`L2`、`L4`、`L8` | pass |
| `run_after_60-pwsh-profile.ps1.tmpl`（新增） | **`L11-C`（渲染 golden —— 這是唯一能抓到「腳本不再呼叫 loader」的層）**、`L2`（`$target` 那一行）、`L4`、`L8` | pass |

### 產品：target 檔案與設定

| Changed unit | Test | Status |
|---|---|---|
| `.chezmoiignore`（改） | `L3` 四個平台的 managed 集合 golden + 互斥性 + repo-only 不得落地 | pass |
| `.chezmoiexternal.toml.tmpl`（改） | `L5`、`L10`、supply-chain（實際下載比對 sha256） | pass |
| `private_dot_config/powershell/profile.ps1.tmpl`（新增） | **`L11-C`**、`L2`（主題檔名與 external 一致等四條）、`L3`、`L4`、`L8` | pass |
| `AppData/Local/nvim/lua/plugins/completion.lua.tmpl`（新增） | **`L11-A`（與 POSIX 落點逐位元組相同）**、`L3`。~~`L6`~~ 從不讀這個檔案，已從對應中移除 | pass |
| `AppData/Roaming/uv/uv.toml.tmpl`（新增） | **`L11-A`**、`L3`。~~`L6`~~ 同上 | pass |
| `private_dot_config/nvim/lua/plugins/completion.lua.tmpl`（新增） | `L10` | pass |
| `private_dot_config/uv/uv.toml.tmpl`（新增） | `L10` | pass |
| `dot_codex/modify_private_config.toml`（改：sh+awk → modify-template） | **`L6` 16 個 golden 案例（`cmp` 逐位元組）、`L6` 結構性斷言、`L8` 真實 Windows apply、properties 層 329 個案例含 P0 差分** | pass |
| `dot_claude/modify_settings.json`（改） | `L6`（POSIX 與 Windows 兩組 golden，`cmp` 比對）、`L8` | pass |
| `dot_zshrc.tmpl` / `dot_zprofile.tmpl`（改） | `L10`、`L4` | pass |
| `init.ps1`（新增） | **`L11-D`（三個自舉套件與其偵測命令、GitHub 帳號、symlink 警告）**、`L4`（pwsh 7 與 WPS 5.1 解析、純 ASCII）、supply-chain（ID 解析）。它不經 chezmoi 算繪，所以在 `L11-C` 的邊界外 —— 這是第五輪指出的 | pass |

### 非產品

| Changed unit | Test | Status |
|---|---|---|
| `tests/**`（runner、lib、**10 個 case**、fixtures、goldens、sandbox 探針） | 測試資產；探針的義務由 `L11-D` 釘住 | n-a |
| `tools/**`（**7 個** gate 腳本） | §Negative controls 逐一驗過 | n-a |
| `docs/`、`README.md`、`AGENTS.md`、`.scratch/`、`.gitignore` | 文件 | n-a |
| 純搬移／改名（2 檔，R100） | — | n-a |
| **刪除：無**（`git diff --diff-filter=D` 為空） | — | n-a |

---

## Stated claim → Test

| Claim | Test | Status |
|---|---|---|
| Windows 用 winget 取代 brew | `L2`；**supply-chain 逐一 `winget show --exact` 解析 12 個 ID**；真正的安裝只有 L9 能證 | pass（安裝本身 unverified） |
| Windows 的 neovim 路徑正確 | `L7`（對假的 `%LOCALAPPDATA%`／`%TEMP%` 實跑，斷言建出來的目錄名與備份集合） | pass |
| 補上 Windows nvim 路徑研究 | `docs/research/windows-native-support.md` §2 | pass |
| Windows 用 PowerShell 7 + oh-my-posh | `L2`（AllHosts 選擇）、`L3`、`L4`、`L7`（loader 逐字）、`L5`（主題 external 釘版本+sha256） | pass |
| **Must NOT #1**：不得在主機執行 winget install 或 apply 到真實 `C:\Users\gn006` | 已提交的來源樹裡沒有任何會動主機的路徑（獨立驗證逐一確認）。**過程中有一次違反，見 Honest notes 1** | **unverified** |
| **Must NOT #2**：不得改變 Linux/macOS 現有行為 | `L10`（`diff -r` 逐位元組；managed 只多出五支 Windows 腳本；external 定義不變） | pass |
| **Must NOT #3**：不得刪除任何既有使用者檔案 | `L7`（POSIX 四次、Windows 三次執行；備份內容保留、彼此獨立、無巢狀）；mutant `posix-nvim-delete` 與 `backup-timestamp-collision` 證明會咬 | pass |
| **Must NOT #4**：`.sh` 不得在 Windows 執行、`.ps1` 不得在 POSIX 執行 | `L2` 的兩條結構性不變式；`L8` 真實 Windows 渲染比對 | pass |
| **Must NOT #5**：不得引入未釘版本或無 checksum 的外部下載 | `L5`（**六個平台組合**全部渲染過；checksum 必須是 64 個十六進位字元，空值不算 —— 實測 chezmoi 對空 checksum 是「不驗證就安裝」 + **Install-PSResource 必須帶 -Version**）；supply-chain 實際下載比對。**兩項具名豁免**：(1) `.oh-my-zsh` 本體追 `master.tar.gz`、無 checksum，是 base ref 就有的設計，`L5` 明文豁免；(2) `50-neovim` 的 `git clone` LazyVim starter 沒有釘 ref 也沒有 checksum —— POSIX 端早於 base ref，Windows 端是這次新增的（第三輪 V7） | pass（含兩項具名豁免） |
| **Must NOT #6**：不得為了讓測試變綠去改測試 | 四次測試修改，各附理由與獨立驗證，見 Honest notes 2 | pass |
| **Must NOT #7**：報告不得寫沒真的跑過的檢查 | 每個數字都指向 `.gate/windows-support/` 的產出檔 | pass |
| M1（`.sh` 在 Windows 被 exec） | `L2` 的結構性不變式（每支 `.sh` 在兩個 Windows 組合上都必須渲染成空）、`L8`；mutant `apt-script-guard`、`seam-leaks-into-production-config` | pass |
| M2（Windows 覆蓋或刪除既有 nvim 設定） | `L7` Windows 備份行為實跑；mutant `windows-nvim-data-backup`、Windows 版的 `Move-Item`→`Remove-Item` 鏡像（獨立驗證自己寫的，也被殺） | pass |
| M3（重跑把使用者設定當外來設定搬走） | `L7` marker 冪等（兩平台）；mutant `windows-nvim-marker` | pass |
| M4（codex 設定毀損） | `L6` 16 個 golden、properties 329 案例含與原版的差分；mutant `codex-duplicate-keys`、`codex-trailing-blank`、`codex-empty-tui-crash` | pass |
| M5（claude settings.json 洗掉未管理的 key） | `L6` 兩組 golden（含既有 key 的種子檔）；獨立驗證另以九種敵意輸入確認與 base ref 行為相同 | pass |
| M6（Oh My Zsh 的 `exact=true` external 在 Windows 被求值） | `L5` 清單斷言 + 「Windows 上不得有任何 .oh-my-zsh external」 | pass |
| M7（`.chezmoiignore` 寫反） | `L3` 四／六個平台的 managed golden 與互斥性；mutant `ignore-windows-block`、`seam-leaks-into-production-config` | pass |
| M8（接縫與真實 Windows 行為不一致） | `L8` 真實 Windows chezmoi 逐位元組比對；**`L1` 生產 config 不得含 override**（第五輪補上的入口守衛） | pass |
| M10（profile loader 重複追加） | `L7` 跑三次恰好一行、內容逐字；mutant `loader-idempotency`、`loader-line-content` | pass |
| M11（順手改壞 POSIX） | `L10` 對 base ref 的整棵樹 `diff -r` 加逐支腳本渲染比對；mutant `posix-script-content-drift` | pass（含一項具名偏離） |
| M9（winget ID 打錯） | **supply-chain 第四項**：抽出實際會安裝的 12 個 ID 逐一解析；抽取規則對不上程式碼就直接失敗 | pass |
| M12（zig 能否讓 tree-sitter 在 Windows 編出 parser） | `tests/sandbox/_probe.ps1` | **unverified —— L9 尚未執行** |

---

## RED reconstruction

在 `0d72b8e` 開 worktree，把目前的 `tests/` 整個複製進去，**逐層**執行
（runner 的 `set -e` 會讓第一個結構性失敗中斷後面所有層）。

| 層 | 在 base 上的結果 | 說明 |
|---|---|---|
| L1 | **4/4 失敗**，之後中斷 | 斷言失敗（值不符），`platform.toml` 不存在 |
| L2 | 53 條裡 **27 條失敗**，之後中斷 | Windows 腳本不存在 + 既有腳本沒有平台守衛 |
| L3 | 44 條裡 **20 條失敗**，跑完 | managed 集合與互斥性 |
| L4 | 47 條裡 **1 條失敗**，之後中斷 | 失敗的是「init.ps1 存在」。其餘 46 條在 base 上就通過 —— 既有 POSIX 腳本的語法檢查，是 regression armor 不是 RED |
| L5 | 15 條裡 **5 條失敗**，之後中斷 | Windows external 清單、新 sha256、PSFzf 版本、asset↔arch 對應 |
| L6 | 100 條裡 **18 條失敗**，跑完 | Windows settings.json golden、modify-template 結構性斷言、敵意輸入案例。**codex 的 golden 在 base 上通過** —— 設計如此，它們就是從 base 的 awk 產生的 |
| L7 | 19 條裡 **3 條失敗**，之後中斷 | 備份唯一化與隔離的正面控制。POSIX 備份的其餘部分在 base 上就是綠的 —— 既有功能，regression armor。Windows 那半因為腳本不存在而中斷 |
| L8 | 5 條裡 **3 條失敗**，之後中斷 | 真實 Windows 的 managed 與腳本渲染比對 |
| L10 | **skip** | L10 從 SPEC 讀 base ref，而 SPEC 在 base 上不存在 |
| L11 | 16 條裡 **14 條失敗**，之後中斷 | 跨平台等價、跨 arch 等價、Windows golden 快照 —— base 上沒有任何 Windows 產物。**上一版寫「8 條失敗、跑完」，兩處都錯**：8 是 R5-3 修好之前的數字（那個 `\|\| true` 正是讓六條取不到內容的斷言變成靜默通過的原因），而 L11-D 的第一行就是 `cat init.ps1`，在 base 上不存在 → `set -e` 中止 → **L11-D 的 22 條斷言一條都沒被跑到**。也就是說 L11-D 在這個重建裡結構上取得不到 RED，如實記在這裡（第六輪 Finding 3） |

> 這組數字是用**目前**的 `tests/` 重跑出來的。上一版報告裡的那組描述的是修補前
> 的舊版測試（獨立驗證第四輪 R4-4），已作廢。

**這不是「base 缺少被測平台」的情形**：base ref 有 chezmoi、有 sh、有既有腳本，
失敗是因為被測行為不存在，多數是斷言層級（值不符）而非收集期錯誤。

**在 base 上就通過的那些（regression armor）**，斷言力由 mutation 層在 HEAD 上證明：
`posix-nvim-delete`、`codex-duplicate-keys`、`codex-trailing-blank`、
`backup-timestamp-collision` 分別讓對應斷言變紅。這是比 RED 弱的主張（證明測試「能」
紅，不是「曾經」紅），如實標示。

**commit ordering**：`469256f`→`f2c072a`（L1）、`59e4c1d`→`d5a7123`（L2）、
`d2cdc9f`→`6ea9ef9`（L3）、`2d57b56`→`cfb19dc`（L6）都是測試先於實作。
L4／L5／L7／L8／L10 的測試與實作在同一個或之後的 commit，故整體記為 `mixed`。

---

## Gate (final fresh run)

以下每一個數字都來自 `sh tools/gate.sh` 的**同一次**執行，時間在最後一次程式碼
修改之後。產出在 `.gate/windows-support/`。

| Layer | Command | Threshold（什麼算通過） | Result |
|---|---|---|---|
| Versions | gate 的 versions 層 | 全部工具版本可取得 | 六項全部記錄 |
| Source state (before) | `sh tools/gate-source-state.sh` | 非淺 clone；工作樹乾淨（白名單只有 `.gate/`） | `commit=1e94ff8…`, `worktree=clean` |
| Tests | `sh tests/run.sh` | 0 失敗（**無 base 測試套件可比，只能報絕對數**） | **489 passed, 0 failed, 0 skipped** |
| Suite health（重跑） | `sh tests/run.sh` 第二次 | 與第一次逐行相同 | 逐行相同，489/489 |
| Suite health（隨機順序） | `TESTS_SHUFFLE=1 sh tests/run.sh` | 總數與失敗數不變 | 489 passed, 0 failed |
| Property-based | `python3 tools/gate-properties.py --cases 30 --base 0d72b8e` | P0–P5 在每個案例上成立 | **7 個 seed ×（30 生成 + 12 固定敵意輸入 + 5 已知限制形狀）= 329 個案例，P0–P5 全部成立**（已知限制那 5 種只驗 P0，見 F3／V6） |
| Mutation | `python3 tools/gate-mutants.py`（手寫，無現成工具） | 0 個存活、0 個不穩定的 mutant（每個跑兩輪） | **34/34 killed，0 survivors**。runner 現在**每個 mutant 跑兩輪**，任一輪沒紅就記成 UNSTABLE 並視同失敗 —— 單跑一輪分不出「一定會被殺」與「這次剛好被殺」 |
| Supply chain + secrets + winget ID | `python3 tools/gate-supply-chain.py --base 0d72b8e` | 新增/變更的 external sha256 全部相符；0 機密命中；全部 winget ID 可解析 | **11** 個釘住下載（六個平台組合全部渲染過），**6 個新增/變更全部下載比對相符**；掃過 7321 行（**不含本報告為 6643 行**，引用這一份）、**0 命中**；**12 個 winget ID 全部解析成功** |
| Changed-line accounting | `python3 tools/gate-changed-lines.py --base 0d72b8e` | 只報告（見下方 UNAVAILABLE） | **不含本報告**（可重現的那一份）：set1 0 / set2 3781 / set3 3540 / 共 6643 行 |
| Source state (after) | `sh tools/gate-source-state.sh` | 與 before **完全相同** | 相同 |
| Manifest audit | `sh tools/gate-manifest-audit.sh` | 10 層全部留下執行記號且無多餘 | **10/10** |

Suite health 排在 property、mutation、行數會計**之前**，因為那三者的結論都是從這個
suite 的行為推出來的。

---

## 獨立驗證（第一輪）

Tier 3 依契約派了一個獨立的 `verifier`，只給四項輸入（任務契約、已核准的 SPEC、
確切的來源狀態、gate 入口點），**不給建置者的對話**。判定 **failed**，11 條 findings。
以下逐條記錄處置，全部可從 git 追。

| # | 嚴重度 | Finding | 處置 |
|---|---|---|---|
| 1 | CRITICAL | codex modify-template 在「`[tui]` 是空 table」時 nil pointer，`chezmoi apply` 以非零結束（`[tui]` 後直接接表頭或檔尾是平常的 TOML）。awk 原版正確。報告當時把該單元標成 `pass` | **已修**（`8dea126`）。加 nil 守衛；新增 5 個 golden 案例（golden 取自 awk 原版）；新增 mutant `codex-empty-tui-crash` |
| 2 | HIGH | property 層寫死單一 seed，而它自己的生成器在 seed 2/3/4 會找到 Finding 1。「另一個 seed 也綠」這句真話被用來支撐它撐不起的推論 | **已修**（`8dea126`）。改跑 7 個 seed，並加入 12 個固定敵意輸入，不靠生成器碰運氣 |
| 3 | HIGH | 「逐位元組比對」是假的：`assert_eq "$(cat f)"` 會吃掉全部結尾換行，193 與 194 bytes 被判相同 | **已修**（`8dea126`）。新增 `assert_bytes_eq`（用 `cmp`），L6 全面改用 |
| 4 | HIGH | L7 的 POSIX 段不隔離：腳本的 `brew shellenv` 把真實 brew bin prepend 到 PATH 最前，蓋掉 stub，測試去跑真的 mise、真的下載 neovim、還讀使用者的 mise 設定 | **已修**。改在 mount namespace 裡把空目錄 bind 到 `/home/linuxbrew`；新增「stub 的 mise 被呼叫四次」證明隔離生效；沒有 user namespace 就 skip 而非假裝跑過 |
| 5 | MEDIUM | `$PROFILE.CurrentUserAllHosts` 的**選擇**沒有任何測試涵蓋，改成 CurrentUserCurrentHost 可存活 | **已修**。L2 新增對賦值那一行的斷言 + mutant `pwsh-profile-target` |
| 6 | MEDIUM | L7 的 M10 斷言只數子字串，loader 改成 `profile.ps1.disabled` 可存活 | **已修**。改成整行比對（先去 CRLF）+ mutant `loader-line-content` |
| 7 | MEDIUM | Must NOT #5 標 `pass`，但檢查器只覆蓋一種拼法：`Install-PSResource` 沒釘版本、`.oh-my-zsh` 無 checksum，兩項都沒揭露 | **已修 + 已揭露**。PSFzf 釘到 2.7.12（版本在 `versions.toml`），L5 新增「必須帶 -Version」；`.oh-my-zsh` 的豁免現在寫在 Must NOT #5 那一列 |
| 8 | MEDIUM | 來源狀態漂移：報告寫完後又提交了一個產品檔，報告的自我描述當場過期 | **已修**。這次報告是最後一個 commit，且只動 `.scratch/`。事件記在 `source_state` 欄位 |
| 9 | LOW | 備份時間戳只到秒，同一秒內第三次 bootstrap 會把上一份備份埋進新的裡（不遺失資料，但正是程式碼註解說要避免的那件事） | **accepted risk**（使用者決定，v2）。曾修過（唯一化迴圈），但那是對 Must NOT #2 的偏離，代價大於收益，已還原 —— 理由與現況見下面「已宣告的 Must NOT #2 偏離」一節 |
| 10 | LOW | M9 沒有自動檢查；`twpayne.chezmoi` 不在 SPEC F12 的 11 個 ID 表裡 | **已修**。supply-chain 新增第四項，逐一解析 12 個 ID（含 `twpayne.chezmoi`），抽取規則對不上程式碼就失敗 |
| 11 | LOW | SPEC §2.4 說備份四個目錄、實作備份三個（實作是對的，SPEC 自己前後不一致）但沒揭露；核准綁定的 sha256 無法從 git 驗證 | **已揭露**，見 Honest notes 4 與 9。程式碼不改：SPEC F6 自己記載 Windows 的 state 與 data 是同一個路徑 |

### 第六輪

判定仍是 **failed**，3 條 findings —— **全部在驗證裝置與報告裡，產品一條都沒有**。
這是連續第二輪產品零缺陷。它同時給出了明確的建議：**不要跑第七輪**。

| # | 嚴重度 | Finding | 處置 |
|---|---|---|---|
| R6-1 | MEDIUM | `L11-D` 用的是 22 條 `assert_contains` —— 子字串在不在，跟那一行會不會執行是兩回事。四個變異存活整套 458 個測試：把 Git 的自舉整行**註解掉**（連 supply-chain 都過，它的正則會匹配到註解裡的 ID）、把三行搬到 chezmoi 呼叫**之後**、在正確那行**之後再賦值**別的 GitHub 帳號、把 M12 檢查的**內容**換掉 | **已修**。改成對 `init.ps1` 與 `_probe.ps1` 做逐位元組 golden —— 那才是「golden pin」原本的意思。新增三個對應的 mutant |
| R6-2 | MEDIUM | gate 的 manifest 稽核管的是 **gate 的層**不是測試層，而 `tests/run.sh` 在層檔案不存在時是 exit 0。其他層被刪會讓對應 mutant 變成 SURVIVED，但 **L4 與 L8 沒有任何 mutant 指向**，把這兩個檔案刪掉整個 gate 照樣全綠。L8 是 SPEC 對 M8 唯一指名的程序 | **已修**。runner 改成記錄每一層貢獻的斷言數，被選到卻是零就失敗。**我第一次的修法犯了 R6-1 的同一個錯**（只檢查檔案在不在，抓不到「檔案還在但被停用」），mutant 因此存活，已改正 |
| R6-3 | LOW-MEDIUM | RED 表的 `L11` 一列寫「8 條失敗、跑完」，兩處都錯 | **已修**。重新量測為 14 條失敗、之後中斷；並如實記下 `L11-D` 在這個重建裡結構上取得不到 RED |

第六輪的**收斂建議**（逐字要旨）：它確實又找到三條，但每一條都是第五輪已經指名的兩種
形狀的又一個實例，而且沒有一條是產品缺陷 —— 七項獨立的產品層攻擊全部乾淨。
再一輪只會找到同樣兩種形狀的第七個實例，成本相同、對使用者的影響為零。
**剩下的風險應該花在 Windows Sandbox 上**：六輪驗證共同建立的是「這會在 Windows 上
產生哪些檔案、內容是什麼、腳本對既有檔案做什麼」；至於 12 個 winget ID 裝不裝得起來、
裝完的工具鏈能不能開出一個可用的 shell、M12 是否可行，以及**一個沒開開發人員模式的
乾淨 Windows 11 帳號碰到那兩個 symlink 會發生什麼**（它認為這是真實首跑最可能的失敗原因），
六輪驗證一條都答不了，一次沙箱開機四條全答。

### 第五輪

判定仍是 **failed**，8 條 findings。它找到第一輪之後**唯一一個真正的產品缺陷**，
並第一次給出可執行的收斂條件：「未收斂，但距離收斂只剩一步」。

| # | 嚴重度 | Finding | 處置 |
|---|---|---|---|
| R5-2 | MEDIUM-HIGH | **產品缺陷**：`50-neovim.ps1` 在 mise 找不到時寫 `Write-Error` 再 `exit 0`，但 `$ErrorActionPreference = 'Stop'` 之下 `Write-Error` 是**終止性**的 —— `exit 0` 到不了，chezmoi 收到的是 1。這是 `run_onchange_before_`，非零退出會在**任何檔案被寫出來之前**中止整個 apply，使用者連 PowerShell profile 都拿不到。比它想做的「跳過 neovim」嚴重得多，而 repo 裡有三處把「exit 0」當成實測事實寫著 | **已修**。改用 `Write-Warning`（受 `$WarningPreference` 管，非終止性），與 POSIX 版對稱。已在完全隔離的環境實測確認修正前後的退出碼；`L7` 新增退出碼斷言，mutant `neovim-skip-aborts-apply` |
| R5-1 | MEDIUM-HIGH | **接縫的生產端入口沒有任何守衛**。整個 Windows 與 macOS 的證據都建立在「正式 config 沒有 `osOverride`」上，而那個前提只寫在 partial 的註解裡；沒有一層檢查 `chezmoi init` 真正產生使用者 config 的那個檔案。在它的 `[data]` 加一行 → 全套 413 個測試全綠，而真實 Windows 上 apply 會中止（M1、Must NOT #4），managed 也變成 POSIX 那一組（M7） | **已修**。`L1` 補上「原始碼與渲染結果都不得含 `osOverride`/`archOverride`」；mutant `seam-leaks-into-production-config` |
| R5-3 | MEDIUM | **L11 的 A、B 兩層在兩邊都取不到內容時恆真**：helper 用 `\|\| true`，失敗留下空檔，`cmp` 判兩個空檔相等。證據是它自己的 RED 表 —— tier B 的七條在完全沒有 Windows 產物的 base ref 上「全部通過」 | **已修**。取不到或取到空內容一律硬失敗 |
| R5-4 | MEDIUM | `init.ps1` 的行為沒有任何東西釘住（它不經 chezmoi 算繪，落在 L11-C 的邊界外）。刪掉 Git 的自舉、換掉 GitHub 帳號、拿掉 symlink 警告，三個都存活整套測試 | **已修**。`L11-D` 把它的義務寫成斷言；mutant `init-drops-git-bootstrap` |
| R5-5 | MEDIUM | 報告的 Table 1 為第四輪指出的**每一個**單元列的仍是那些結構上盲的層，從來沒提過補進來的 L11 | **已修**。Table 1 已改列 L11 並標明哪些層對該單元是盲的 |
| R5-6 | LOW | 兩個計數過期（case 數、gate 腳本數） | **已修** |
| R5-7 | LOW | SPEC 宣告 M1–M12，claim 表只有 M9 與 M12 有列 | **已修**。M1–M11 全部補上對應的可失敗程序 |
| R5-8 | LOW | sandbox 探針的內容漂移不會被發現，而它是 M12 與 symlink 問題唯一的量測工具 | **已修**。`L11-D`；mutant `probe-drops-m12-check` |

**它的收斂判斷**：L11 確實把「chezmoi 會渲染的 Windows 產物」這一類關上了 ——
它自己發明的每一個內容變異都死了，包含三個我沒有寫的。剩下的殘留第一次是
**可列舉的清單**而不是「機制缺一塊」的症狀，它並且直接寫出了關閉條件（四項，
全部已完成）。它預估再一輪之後報酬轉負。

### 第四輪

判定仍是 **failed**，8 條 findings。但這一輪最重要的不是它找到什麼，而是它的**根因診斷**，
以及一句話：

> Nothing here is above LOW only in the sense of "the shipped code is wrong" —
> **I found no defect in the product code itself.** All three surviving mutants
> describe verification gaps, not current bugs.

根因是：**Windows 平台沒有外部 oracle**。POSIX 的每個產物都能跟 base ref 逐位元組比對
（L10），那一個機制免費擋掉整類內容漂移；Windows 只有三個程序，而它們結構上都不可能
因為內容改變而失敗 —— L2 比一份手列的子字串、L7 把環境重導向到空沙盒、L8 比的是同一份
來源的兩次渲染。四輪都在這個缺口裡找到「第一次出現」的實例而不是既有問題的小變形，
那是機制缺一塊的徵狀，不是缺陷尾巴在收斂。它的建議是「補機制，不要補實例」。

| # | 嚴重度 | Finding | 處置 |
|---|---|---|---|
| R4-1 | HIGH | `60-pwsh-profile` 可以整個不呼叫 loader 而沒有任何測試變紅。後果：`$PROFILE` 永遠拿不到那一行，oh-my-posh／PSReadLine／PSFzf／mise 全部不載入 —— **整個 Windows shell 設定靜靜地不存在**。Table 1 為這個單元列的三層，沒有一層能因為它失敗 | **已修**（機制）。L11-C 的 golden 快照；mutant `pwsh-profile-loader-not-called` |
| R4-2 | MEDIUM-HIGH | 兩個 Windows 專屬 target（`AppData/` 下的 nvim plugin 與 uv 設定）內容沒有任何東西釘住，而 Table 1 為它們列的 `L6` **從來不讀那兩個檔案** | **已修**（機制）。L11-A 跨平台等價：那兩對各是「一行 includeTemplate 同一個 partial」，內容必須逐位元組相同；mutant `windows-nvim-plugin-content` |
| R4-3 | MEDIUM | 第三輪 V2 的修法結構上只能覆蓋 POSIX（它逐支比對 base ref 的腳本，Windows 沒有 base）。四個獨立的 Windows 腳本內容變更各自存活整套測試，包含把 `tree-sitter.tree-sitter-cli` 拿掉 —— AGENTS.md 明文禁止修剪的那一項 | **已修**（機制）。L11-C golden；mutant `winget-drop-tree-sitter` |
| R4-4 | MEDIUM | 報告數字不重現：RED 表描述的是舊版 `tests/`；另有 294／5522 兩個過期數字 | **已修**。RED 表用目前的 `tests/` 重跑（見上表的說明）；兩個過期數字已更正；不穩定的那一個改成引用不含 `.scratch/` 的版本 |
| R4-5 | MEDIUM | 「每一個都在 5 次獨立重複裡穩定致死」沒有任何 artifact 支撐 —— 被引用的處置只重複了**一個** mutant，而 runner 一輪只跑一次 | **已修**（機制）。runner 現在**每個 mutant 跑兩輪**，任一輪沒紅就記成 UNSTABLE 並視同失敗。這句話現在由 `.gate/windows-support/mutants.json` 的 `rounds` 欄位支撐 |
| R4-6 | LOW-MEDIUM | 行數分類器把整類 `.json` 當資料，但 chezmoi 的 modify-template 不能有 `.tmpl` 後綴 —— `modify_settings.json` 副檔名是 `.json`、內容是模板程式碼，六行會被求值的 action 被記進「不可執行」，違反腳本自己的政策 | **已修**。`.json` 移出資料副檔名清單 |
| R4-7 | LOW | L10 的具名例外過寬：濾條含「任何註解行」與「任何含 done 的行」，刪掉兩行註解也能躲進例外 | **已修**。改成與一份寫死的預期 diff 逐行比對；negative control 確認刪註解現在會紅 |
| R4-8 | LOW | `windows-path.ps1` 只有四個 PATH 條目中的兩個被釘住；Table 1 仍為它列了結構上盲的 `L7` | **已修**。L11-C golden 涵蓋整個 partial 的渲染結果；mutant `windows-path-drop-git` |

**機制補在哪裡**：新增 `tests/cases/L11-render-golden.sh`，三種強度分明的斷言 ——
(A) 跨平台等價與 (B) 跨 arch 等價是**真 oracle**（陳述的是必然成立的性質）；
(C) 是 Windows 專屬產物的 **golden 快照，明確標示為變更偵測器而非正確性 oracle**：
它證明的是「沒有人在沒被看見的情況下改了內容」，正確性來自其他層。第四輪存活的
四個 mutant 現在全部被殺。

### 第三輪

判定仍是 **failed**，8 條 findings（兩條 HIGH）。它對前兩輪 19 條的裁決是
**14 FIXED、4 PARTIALLY FIXED、5 DISCLOSED-accurate**（部分重疊）。

| # | 嚴重度 | Finding | 處置 |
|---|---|---|---|
| V1 | HIGH | **gate 是不決定性的**。Windows 撞名 mutant 的 kill 需要第三、第四次執行落在同一個 wall-clock 秒內，而跨 WSL→pwsh.exe 大約要一秒 —— 等於擲硬幣。驗證者的**第一次** gate 執行就紅了（16/17，後續四層 NOT REACHED），7 次獨立重複裡存活 2 次。報告的「17/17、逐一檢查、沒有一個是碰巧」描述的是一次幸運抽樣 | **已修**。改成強制撞名：先把接下來幾秒的時間戳目錄全部建好，唯一化迴圈必然被走到。帶 mutant 連跑 5 次，每次都紅 3 條。**v2 後續**：使用者決定還原唯一化迴圈，這兩個 mutant 隨之退場（換成 `backup-timestamp-fallback{,-windows}`）；強制撞名的做法保留下來，改去釘 accepted risk 的行為，因此決定性這一點沒有回退 |
| V2 | HIGH | **Must NOT #2 對應到 L10，但 L10 的 apply 帶 `--exclude=scripts`** —— 四支被改寫的既有 POSIX 腳本，內容從來沒有跟 base 比對過。把 `tree-sitter` 從 brew 清單拿掉（AGENTS.md 明文禁止修剪的那一項）能存活整套 387 個測試 | **已修**。L10 現在逐支比對渲染結果。**這同時暴露出一件我沒宣告的事**，見下方「已宣告的 Must NOT #2 偏離」 |
| V3 | MEDIUM-HIGH | 哪個平台拿哪一個 cc-statusline asset **沒有被任何東西釘住**。supply-chain 天生看不到：sum 是按 asset 名稱查的，把 darwin 的 arm64/x64 對調之後 URL 與 pin 仍然一致、雜湊也仍然相符。實際後果是 Intel Mac 拿到 arm64 執行檔 | **已修**。L5 補上逐平台的預期 asset；mutation 新增 `cc-statusline-arch-swap` |
| V4 | MEDIUM | PowerShell profile 的**內容完全沒被釘住**。把主題檔名改掉 → external 裝的與 profile 讀的不一致 → profile 的 `Test-Path` 守衛**靜靜跳過** oh-my-posh 初始化，使用者只看到沒有主題的提示字元、沒有任何錯誤 | **已修**。L2 補上「profile 讀的主題檔名要與 external 裝的一致」加四條關鍵行；mutation 新增 `pwsh-profile-theme-name` |
| V5 | MEDIUM | `windows-path.ps1` 被拿掉不會被任何測試發現，而 L7 因為重導向了 `%LOCALAPPDATA%`／`%ProgramFiles%`，**結構上不可能偵測到它**。後果是 50-neovim 走「mise not found, skipping neovim」那條路並以 **exit 0** 結束 —— 整個安裝靜靜地沒發生 | **已修**。L2 補斷言；mutation 新增 `windows-path-not-included`。這個失效模式在 SPEC 的 M1–M12 表裡沒有對應列 —— SPEC 已核准不改，記在這裡 |
| V6 | MEDIUM | 已知限制的形狀被當成**窮舉**寫進三處文件，但還有第五種（加引號的 key `"status_line" =`） | **已修**。第五種加進 `KNOWN_LIMITATION`；三處文件都改成「這是目前已知的，不是窮舉」，並改為描述那三個前提而不是列表長度 |
| V7 | MEDIUM-LOW | Must NOT #5 的豁免只列了 `.oh-my-zsh` 一項；LazyVim starter 的 `git clone` **沒有釘 ref 也沒有 checksum**，抓的是 nvim 會執行的 Lua，而 Windows 這支腳本是這次新增的 | **已揭露**，寫進 AGENTS.md 與下方 Must NOT #5 那一列。釘住它會改變 POSIX 機器抓到的東西，因此記錄而不改 |
| V8 | LOW | 第一輪 Finding 4 的隔離正面控制只有 POSIX 有；Windows 的 stub 不留記號，沒有任何斷言證明跑到的是 stub 而不是主機上的真工具 | **已修**。Windows stub 也留記號，補上對稱的斷言 |
| V9 | LOW/INFO | L8 的十一條「逐位元組」裡有五條是 0 bytes 比 0 bytes | **不需處置**。驗證者自己的結論：另外六條非空的比對是正面控制，`_cm_win` 壞掉會讓它們變紅，所以攻不破 |

### 已宣告的 Must NOT #2 偏離 —— **已還原（v2）**

修第一輪 Finding 9（備份時間戳撞名）時，我在 **POSIX** 腳本裡也加了唯一化迴圈。
那**改變了 POSIX 端的渲染輸出**，而 SPEC 的 Must NOT #2 要求逐位元組不變。
當時我沒有宣告它 —— 是第三輪 V2 補上腳本內容比對之後才顯現出來的。曾經的處置是把它
留成 `tests/cases/L10` 裡的**具名例外**，形狀釘死，並把去留交給使用者決定。

**使用者的決定是還原。** 理由（使用者原話的重點）：那個迴圈要在**同一秒內完成兩次含
`git clone` 的 bootstrap** 才會被走到，實務上到不了；為此讓 POSIX 腳本多六行、L10 多
一段寫死的預期 diff，不划算。

現況：

- `run_onchange_before_50-neovim.sh.tmpl` 的 `backup_dir` 與 base ref `0d72b8e`
  **逐位元組相同**（本輪以 `diff` 直接比對函式本體確認）。
- Windows 端 `Backup-NvimDirectory` 的迴圈一併拿掉，維持兩邊對稱。Windows 不受
  Must NOT #2 約束，這一項純粹是對稱性的決定：同一份 SPEC 不該在兩個平台上
  代表不同的行為。
- L10 移除唯一的具名例外，**POSIX 腳本全部回到嚴格逐位元組比對**。
- 這條路徑沒有被藏起來：它記進 SPEC §7 成為具名的 accepted risk，並由 L7 的第四次
  執行釘成 characterization test —— 強制撞名，斷言「來源被搬進既有備份裡、內容仍在、
  沒有產生序號備份」。有人改動備份命名的形狀，這三條會紅。
- mutation：`backup-timestamp-collision{,-windows}` 換成
  `backup-timestamp-fallback{,-windows}`（刪掉時間戳退路 → 第二份備份被埋掉）。

**因此 Must NOT #2 現在無偏離。** 這項變更本身是對已核准 SPEC 的實質修改，
已依契約記入 SPEC §9 Revisions，並重新請求核准（見 `intent_status`）。

### 第二輪

修完第一輪之後又派了一次，這次額外要求它攻「我對第一輪的處置」。判定仍是 **failed**，
8 條 findings。它同時對第一輪的 11 條逐條給了裁決：**7 條 FIXED、3 條 PARTIALLY FIXED、
1 條 DISCLOSED**。三條 partial 的殘留就是下面的 F1／F2／F4。

| # | 嚴重度 | Finding | 處置 |
|---|---|---|---|
| F1 | HIGH | 第一輪 Finding 9 的**修法只落在一個平台**：同一秒撞名的防護兩邊都有程式碼，但只有 POSIX 有能證偽它的測試與 mutant。驗證者把鏡像 mutant 套到 Windows 腳本上，**整個套件 387/387 全綠**，並實際做出「新備份埋掉舊備份」的目錄結構 | **已修**。L7 的 Windows 段補第四次執行與「三份備份彼此獨立／無巢狀」；mutation 新增 `backup-timestamp-collision-windows` |
| F2 | HIGH | cc-statusline 有六個 release asset，但只有四個平台組合被渲染過 —— `win32-arm64` 與 `linux-arm64-musl` 的 pin **從來沒有被任何檢查看過**。而且 L5 只檢查「有沒有 checksum 那一行」，**空字串照樣過**；實測 chezmoi 對空 checksum 是「不驗證就安裝」，比錯的值更危險。把 `win32-arm64` 的 pin 清空 → 全套 328/328 全綠 | **已修**。新增 `os-linux-arm64` / `os-windows-arm64` 兩個 fixture（矩陣四組 → 六組）；L5 改成要求 64 個十六進位字元；supply-chain 現在下載驗證全部六個 asset；mutation 新增 `external-checksum-empty` |
| F3 | MEDIUM | codex 改寫的「受管 key 各佔一行」前提有四種形狀會讓**合法 TOML 變成不合法**（多行 `status_line` 陣列、`[[tui]]`、`["tui"]`、inline table）。P4 的宣稱涵蓋不到它們，而生成器結構上也產不出來 | **已揭露，程式碼不改**。四種都與 awk 原版**逐位元組相同**，是沿用的既有缺陷；修它會改變 POSIX 輸出（Must NOT #2）。P4 的宣稱已明文縮小範圍；四種形狀進 `KNOWN_LIMITATION` 只驗 P0（哪天與 awk 不一致就是回歸，會被擋）；並寫進 AGENTS.md 與研究筆記 §11.5。**這一條需要你決定要不要另外開一件事去修** |
| F4 | MEDIUM | 第一輪 Finding 3 的類別在 L8 存活：它仍用會吃掉結尾換行的字串比對、還先 `tr -d '\r'`，卻宣稱「逐位元組」 | **已修**。改用 `assert_bytes_eq` 比原始位元組。改完仍然全過，印證真實與模擬渲染確實原始位元組相同 |
| F5 | LOW | 三個數字不重現：檔案數 101（實際 127）、secrets 5079（實際 5107）、set2 2746（實際 2774）。根因是報告自己也在 diff 裡 | **已修**。檔案數改成由命令直接產生的 130／128；changed-lines 與 secrets 兩層現在同時報「不含 `.scratch/`」的數字，報告引用那一份 |
| F6 | LOW | NUL 哨兵字串若真的出現在檔案裡，輸出會與 awk 不同 | **已揭露**。只在檔案含 NUL 位元組時可達；P0 的「與 awk 逐位元組相同」因此是有範圍的宣稱，不是絕對 |
| F7 | LOW | `.chezmoiignore` 的 Windows 區塊少了 SPEC §2.2 列的 `.oh-my-zsh/`（結果等價：M6 由 external 整段不輸出處理，L5 有斷言），但沒揭露 | **已揭露**，見 Honest notes 4 |
| F8 | LOW | 五個 fixture 全部把 `isWSL` 釘成 false，`isWSL = true` 的渲染從來沒被驗證過 | **已修**。新增 `native-wsl` fixture；L10 補三條斷言（與 base ref 相同、true 時真的輸出 WSL alias、false 時不輸出） |

第二輪「攻不破」的部分（原文摘要）：gate 重跑 exit 0、10/10 層，**每一個產品衍生的
數字都完全重現**；接縫沒有繞過路徑，真實與模擬渲染原始位元組相同（4101 bytes、`cmp`
乾淨）；五個 pin 逐一對上游重算全部相符；codex 移植在**額外 42 種敵意形狀**下（含無效
UTF-8、行中 NUL、一萬行結尾空白、一千個 `[tui]` 表頭）**沒有崩潰、沒有非零退出、
全部與 awk 逐位元組相同**；gate 確實 fail closed（它自己留下的 `__pycache__` 讓
mutation 層擋下並中止後續）；Must NOT #1 在已提交的來源樹裡沒有任何違反路徑。

### 第一輪

驗證者「攻不破」的部分（原文摘要）：gate 的每一個數字重跑後完全相符；RED 產出與報告
逐位元組相符；`osOverride` 接縫找不到繞過的呼叫點；`~/.claude/settings.json` 在九種
敵意輸入下與 base ref 行為完全相同；codex 移植在 30 個敵意輸入中 27 個與 awk 逐位元組
相同（其餘 3 個即 Finding 1 與空白行正規化，均已修）；mutation runner 無法被誘導回報
沒跑過的 kill。

---

## Negative controls

每一個 home-grown 檢查器都先被餵過已知的壞輸入、親眼看它紅過。

- **`tools/gate-source-state.sh`** —— 未追蹤檔 → `worktree=dirty` + exit 1；移除後 exit 0。
- **`tools/gate-manifest-audit.sh`** —— 缺一層 / 多一層 / 讀不到輸入 → 各自 exit 1 並指名；完全相符 → exit 0。
- **`tests/lib.sh` 的 `cm()`** —— 打錯 OS 名稱 → exit 2 並指名試過哪兩個檔名。
  （原本會把不存在的 `--config` 交給 chezmoi，而 chezmoi 對此不報錯、安靜地用預設值算繪。）
- **`tests/cases/L5`（空 checksum）** —— 把某個 pin 換成空字串 → 該條紅。空值比錯值危險：
  實測 chezmoi 對空 checksum 是「不驗證就安裝」而不是「驗證失敗」。
- **`tools/gate-properties.py`（KNOWN_LIMITATION 只驗 P0）** —— 讓多行陣列那種形狀與
  awk 不一致 → P0 立刻紅，證明「只驗 P0」不等於「不驗」。
- **`tools/gate-properties.py`（P1–P5）** —— 對「丟掉 [tui] 以外的行」的 mutant，P2 在第 0 個案例就紅。
- **`tools/gate-properties.py`（P0 差分）** —— 對「結尾空白行不正規化」的 mutant：
  **只跑 P1–P5 全綠（16 案例），加上 P0 立刻紅**。這證明 P0 不是既有性質的重複。
- **`tools/gate-supply-chain.py`（checksum）** —— 主題 sha256 換成全 0 → exit 1 並印出 pinned/actual 對照。
- **`tools/gate-supply-chain.py`（secrets）** —— 在 diff 裡植入一個 AWS 文件用的範例
  access key（`AKIA` 開頭、共 20 碼；這裡刻意不逐字寫出來，否則本檔自己就會觸發這個
  掃描器 —— 而它那樣做是對的）→ exit 1 並指出類別。
- **`tools/gate-supply-chain.py`（winget ID）** —— ID 打成 `zig.zigg` → exit 1 並指名它
  出現的檔案；把 `$packages` 改名讓抽取規則脫節 → exit 1 且訊息明講「這是失敗不是略過」。
- **`tests/cases/L5`（版本釘住）** —— 拿掉 `-Version` → 該條立刻紅。
- **`tools/gate.sh` 的 fail-closed** —— 把 `platform.toml` 改壞並提交到 worktree，
  gate 停在 `suite` 層（exit 1），後面的層一次都沒執行（`grep -c 'layer: mutation'` = 0）。
- **Mutation baseline** —— 套任何 mutant 前先跑一次未突變的複本；紅了就放棄整輪而非
  回報分數。**runner 完全循序、沒有併發**，所以「並行 job 共用 build 目錄」的污染機制
  在這裡不存在；每個 mutant 在同一個拋棄式 worktree 裡「套用 → 跑 → 還原」，
  套用與還原都有 assert。
- **Mutation kill 歸因** —— 不是抽樣，而是**逐一檢查全部 33 個**：每個 mutant 的失敗
  斷言名稱都指名它破壞的那個行為，沒有一個是無關測試剛好紅了。

---

## Layers not run as specified

- **N-A（這個 repo 沒有這種面）：**
  - *Static types* —— 沒有型別語言。
  - *Complexity budget* —— 沒有函式可量；最接近的單元是「一支腳本」，各自單一平台單一件事。
- **UNAVAILABLE（工具不存在，也沒有替代品跑）：**
  - *Lint* —— `shellcheck`、`shfmt`、`PSScriptAnalyzer` 這台機器上都沒有。安裝會改動
    使用者環境，**沒有取得授權**，所以什麼都沒跑。L4 的語法解析**不是** lint 的替代品：
    它只保證「解析得過」，抓不到 quoting、未引用變數這類問題。
  - *Changed-line coverage* —— 三種語言都沒有覆蓋率工具。set 3（可執行但無覆蓋率對應）
    ＝ 3405 行，是全部可執行的新增行。這一層什麼都沒證明；補位的是 Table 1 的逐檔對應、
    mutation 與 property 三層。
- **SUBSTITUTED：**
  - *Real execution* —— **L9 已經真的跑過一次，結果是 FAIL**（見下方「L9 第一次執行」）。
    在那之前補位的是 `L7`（重導向環境裡真的執行腳本）與 `L8`（Windows 主機上真的執行
    chezmoi 的 managed 與 apply，僅檔案；比對走 `cmp` 原始位元組）。
    那一次執行證明了這兩層**偵測不到**什麼：整個 apply 因為 ExecutionPolicy 而在第一支
    腳本就中止，L1–L8 十層全綠，沒有任何一層看得到。
    根因已修（M13），但**修好之後沒有再跑過一次 L9**，所以「winget 是否真的裝得起來、
    裝完的工具是否能用、第一次開 Neovim 會怎樣」到現在仍然沒有證據。
  - *macOS 的一切* —— 沒有實體 mac，全部證據來自 `osOverride=darwin` 的渲染矩陣。
    **偵測不到**任何只在真實 macOS 上才會出現的行為。接縫本身只在 **windows** 那一邊被
    交叉驗證（L8），darwin 那一邊**沒有任何實機驗證**。
- **NOT REACHED：** 無。最終一輪十層全部執行完畢。
- **DEPENDENCY UNMET：** 無。

---

## L9 第一次執行（2026-09-03，遠端模式，`9f44752`）

**狀態：已執行 · FAIL · 根因已定位並修好 · 修後未重跑。**

使用者在另一台機器的乾淨 Windows Sandbox 裡，用遠端模式一行 `irm` 跑完整支探針，
分支 `feat/windows-support @ 9f44752`。結果 **PASS=5 FAIL=19**。

### 根因（已定位）

```
File C:\Users\WDAGUtilityAccount\AppData\Local\Temp\4051484889.30-install-winget-packages.ps1
cannot be loaded because running scripts is disabled on this system.
chezmoi: .chezmoiscripts/30-install-winget-packages.ps1: exit status 1
```

chezmoi 把算繪後的 `.ps1` 寫到 `%TEMP%` 再交給直譯器，而 Windows 用戶端的預設
ExecutionPolicy 是 `Restricted`。`before` 腳本跑在所有檔案目標之前，所以**整個 apply
在任何一個檔案落地前中止** —— 19 條 FAIL 裡有 17 條只是這一件事的下游。

這**不是 Sandbox 特有的**。每一台全新 Windows 11 的真實使用者都會死在同一個位置，
拿到一台什麼都沒發生的電腦。SPEC §6 的 M1–M12 **沒有任何一條涵蓋它**，所以它同時是
一個產品缺陷與一個失效模型的缺口（SPEC v4 補為 M13）。

三項實測（本機 pwsh 7.6.5，只用 `-ExecutionPolicy` 開關，不動機器原則）：
pwsh 7 **一樣**受 ExecutionPolicy 管；`-ExecutionPolicy Bypass` 能解；
`.chezmoi.toml.tmpl` 的 `[interpreters.ps1]` **在同一次 `init --apply` 就生效**
（第三項是修法可不可行的關鍵，因為要救的正是「第一次安裝」）。
修法與不採用 `Set-ExecutionPolicy` 的理由見 `docs/research/windows-native-support.md` 1.6。

### 這一次執行同時揭穿了探針自己的三個缺陷

| # | 缺陷 | 為什麼重要 |
|---|---|---|
| P1 | **`codex config.toml has the managed [tui] keys` 回報 PASS，而當時一個檔案都沒落地** | 探針宣稱看到了它其實沒看到的東西 —— L9 最不該有的失效模式。原因：`$ErrorActionPreference` 是 `Continue`，缺檔時 `Get-Content` 是非終止錯誤、變數拿到 `$null`，而 PowerShell 的 `$null -match` 與 `$null -notmatch` **兩個都回 `$false`**，於是兩個 `throw` 都不會觸發。本機以 5.1 實測重現（同一段程式碼、指向不存在的檔案 → `PASS ok`） |
| P2 | **失敗細節讀不到** | chezmoi 的輸出只進 transcript，而遠端模式沒有對應資料夾，Sandbox 一關就沒了。`FAIL chezmoi init --apply -> 1` 這一行不含任何線索；根因是使用者第二次進 Sandbox 手抄 transcript 才拿到的 |
| P3 | **winget 的輸出在 results.tsv 裡是亂碼** | `?曉 PowerShell [Microsoft.PowerShell] ? 7.6.5.0 甇斗??函?撘歇?勗?...`。winget 吐 UTF-8，5.1 用主機的 ANSI 代碼頁（這台是 CP950）解。與本輪稍早修掉的 gate mutation runner UTF-8 崩潰**是同一類**：一個只在失敗路徑上才看得見的編碼假設 |

三條都已修（`Get-Content` 一律 `-ErrorAction Stop` 並先 `Test-Path`；失敗細節帶 chezmoi
輸出的尾段 30 行；`treesitter.log` 結尾印出尾段 200 行；主控台統一 UTF-8），
並各由 L11 的斷言釘住 —— 其中 P1 那條是機械檢查（探針裡每一處 `Get-Content` 都必須帶
`-ErrorAction Stop`），不是子字串比對。

### 這一次執行**沒有**回答的

- **M12（treesitter parser）仍然 unverified。** apply 在 nvim 被裝起來之前就中止，
  那條檢查跑到了、但它問的問題從來沒有被實際問到。
- **winget 的 9 個套件是否真的裝得起來**：一個都沒試到。supply-chain 那層證明的是
  12 個 ID 解析得到，不是安裝會成功。
- **symlink 權限**那條 FAIL 是預期的（乾淨機器沒開開發人員模式），但在這次執行裡它
  和其他 17 條一樣是 apply 中止的下游，不算獨立證據。

### 這個修法本身被什麼看著

- **L2**：Windows 的設定必須有 `[interpreters.ps1]`、`command = "pwsh"`、
  `"-ExecutionPolicy", "Bypass"`、`"-NoProfile"`、以 `"-File"]` 收尾（5 條）；
  四個 POSIX 組合都不得出現 `interpreters`（4 條）。
- **L10**：`.chezmoi.toml.tmpl` 的 POSIX 渲染與 base ref 逐位元組相同（`sourceDir`
  那一行必然不同，濾掉，再單獨斷言那一行仍然存在）。**這個檔案在此之前完全沒有任何
  程序在看** —— 它產生的是 chezmoi 自己的設定、不是 target，整棵樹的 diff 看不到它，
  而 Must NOT #2 明明管得到。
- **negative control（實跑）**：把平台守衛換成 `{{ if true }}` → L2 的四條 POSIX
  斷言與 L10 那條同時變紅；還原後全綠。
- **mutant `interpreter-execution-policy-dropped`**：拿掉 `-ExecutionPolicy Bypass`
  這兩個參數。加它的理由是這個 repo 自己的教訓 —— 子字串斷言抓不到註解掉、改序、
  之後再覆寫，而上面那 9 條全是子字串斷言；L10 也救不了，因為整段包在 `isWindows`
  裡，POSIX 的渲染一個位元組都沒變。這是唯一能機械證明「L2 那條真的會紅」的東西。

### 誠實的結論

修好的是**已知的那一個**根因。M13 之後還有沒有第二個、第三個障礙，只有再跑一次 L9
才知道。在那之前，這份報告對「這份 dotfiles 在 Windows 上裝得起來」**仍然沒有證據**。

**後續（第二次執行）證明這個保留是對的：M13 之後確實還有東西。** 見下一節。

---

## L9 第二次執行（2026-09-03，遠端模式，`1e94ff8`）

**狀態：已執行 · PASS=12 FAIL=12 · M13 已證實修好 · 又找出兩個新問題與一個被推翻的假設
· 依合約停在 SPEC 修訂，尚未實作。**

`1e94ff8` 正是 gate 最後一次完整執行所量測的那棵樹。

### 修好的

- **M13 已證實**：`chezmoi init --apply completes` PASS。第一次執行時整個 apply
  在任何檔案落地前中止，這一次檔案全部落地（profile、oh-my-posh 主題、cc-statusline、
  settings.json、nvim starter 全部 PASS）。
- **P3（編碼）已證實**：winget 的中文輸出這一次是正常的，不再是 CP950 亂碼。
- **P1（空過的檢查）已證實**：`codex config.toml` 這條上一輪在一個檔案都沒落地時
  回報 PASS，這一輪**第一次真的讀到檔案，並且抓到了受管 key 缺失** —— 修好的檢查
  立刻付了它的房租。
- symlink 那條這次是 PASS（該台機器有 symlink 權限），與第一次的預期 FAIL 不同；
  兩次都不是獨立證據，第一次是 apply 中止的下游。

### 新找出來的（皆已量測到根因，處置寫進 SPEC v5，**尚未實作**）

| # | 現象 | 根因 | 層級 |
|---|---|---|---|
| A | 十個工具全部 `tool on PATH: not found`，但 apply exit 0 | **探針的觀察錯誤，不是沒裝。** 探針的 `Update-ProbePath` 只塞四個寫死的目錄，而 Windows 的 PATH 是 process 啟動時的快照 —— 探針在任何安裝發生前就啟動了，winget 對 registry PATH 的更新它看不到 | 探針 |
| B | `codex config.toml` 缺 `status_line_use_colors` | **Git for Windows 預設 `core.autocrlf=true`**，來源樹被 checkout 成 CRLF，算繪結果把一個 `\r` 帶進受管設定檔，探針那條 `$` 錨定的 .NET 正則因此不 match（SPEC v5 的 M14） | 產品 |
| C | M12 仍未證實 | 是 A 的下游（nvim 由 mise 裝）。但使用者事後實跑 nvim，得到比「未證實」更強的結果 —— 見下 | — |

**A 的判定不是猜的。** 這個 repo 只管一個 nvim 檔案
（`AppData/Local/nvim/lua/plugins/completion.lua`）；`init.lua` 與
`.chezmoi-lazyvim-starter` 只可能來自 `50-neovim.ps1` 的 clone，而那支腳本在 `mise`
找不到時會**在 clone 之前 `exit 0`**。那條檢查是 PASS，所以 mise 對腳本是可見的，
套件真的裝了。使用者事後在新終端機實測 mise / nvim 正常，與這條推論一致。

**B 的四項量測**：.NET `(?m)^...$` 對 LF match、對 CRLF 不 match；LF 來源樹產生的
config 全 LF；CRLF 來源樹產生的同一個檔**只有那一行帶 CR**，其餘逐位元組相同 ——
正好就是失敗的那一個 key。POSIX 端結構上看不到：L6 的 golden 與 329 個 property case
全部從 LF 樹跑。

### 被推翻的假設：M12

使用者在 Sandbox 內開新終端機實跑 nvim：nvim-treesitter `main` 回報
`Unmet requirements: C compiler ❌`（curl / tar / tree-sitter CLI 都 ✅），
並建議 `winget install BrechtSanders.WinLibs.POSIX`。

SPEC 從 v1 就把 `zig.zig` 放進 winget 清單，理由是「社群做法是改用 zig」。
**那個假設在真機上不成立** —— 至少 nvim-treesitter 的需求檢查不認 zig。
這條因此從「未證實」升級為「已被推翻」，處置是產品層決定，四個選項與各自的代價
寫在 SPEC §9 的 v4 → v5，等使用者選。

### 這一輪為什麼停在這裡

使用者要求走一遍「修訂中停下來等」：**SPEC 寫好、提交、請求核准，核准之前不碰產品
也不碰探針**。所以上面每一項都只有診斷與處置方案，沒有任何實作。這份報告的
`intent_status` 因此是 `unconfirmed`。

---

## Dismissed concerns

- **winget 套件 ID 可能打錯** —— 現在有自動檢查（12 個全部解析成功）。這證明 ID 解析
  得到，**不證明**安裝會成功。
- **Windows 上 `.ps1` 的中文註解會不會被解壞** —— 以 chezmoi 真正的呼叫方式
  （`pwsh -NoLogo -File`）實跑過含中文註解的渲染結果，正常。只有 Windows PowerShell 5.1
  有這個問題，因此只有 `init.ps1` 與 sandbox 探針受 ASCII 限制，由 L4 兩條斷言釘住。
- **Windows 端 nvim-data 備份兩次** —— mutation 實測無害（第二次呼叫時來源已不在）。
  原本為此寫的「只被備份一次」被 mutation 證明是恆真的廢斷言，已換成「備份出來的目錄
  集合剛好是那三個」，新版經 mutation 確認會咬。
- **`.chezmoiignore` 是否足以隔離跨平台腳本** —— 不足，已實測：非空的 `.sh` 在 Windows
  上會讓整個 apply 中斷。隔離只能靠渲染成空。

---

## Structural blind spot

**這整份報告沒有任何一個數字來自「一台真的裝過這份 dotfiles 的 Windows 機器」。**

做到的是：三個平台的模板渲染、Windows 主機上真實 chezmoi 的唯讀比對、在重導向的環境
裡真的執行安裝腳本的檔案搬移邏輯、以及對 codex 設定改寫的 329 個案例差分。
**沒做到的**是：`winget install` 真的跑一次、裝完的 PowerShell 7 + oh-my-posh + PSFzf
+ mise 真的開一個 shell 起來、LazyVim 第一次啟動真的去編 treesitter parser。

那些只有 `tests/sandbox/`（L9）能回答，而 L9 需要你按下 sandbox 啟動。在它跑完之前，
本報告對「這份 dotfiles 在 Windows 上裝得起來」**沒有證據**，只對「它在 Windows 上會
產生哪些檔案、那些檔案長什麼樣、那些腳本對既有檔案做什麼」有證據。

macOS 的盲點更大：連唯讀的實機比對都沒有。

---

## Honest notes

### 1. 我違反了自己寫的 Must NOT #1（已發生，不可撤銷）

驗證 `.ps1` 的 UTF-8 編碼時，我直接以 `pwsh -File` 執行了渲染後的 `40-git-lfs.ps1`。
它**真的執行了** `git lfs install --skip-repo`，寫到了 Windows 主機的
`C:\Users\gn006\.gitconfig`（實測：該檔在那之後 21 秒被修改）。

影響：`filter.lfs.clean/smudge/process/required` 四個設定現在在該檔案裡。git-lfs 本來
就裝在那台機器上、`git lfs install` 是冪等的，極可能只是把相同內容重寫一次 ——
但**我無法回溯證明它原本就在**。要還原可以跑 `git lfs uninstall`。

之後所有行為測試都改走重導向環境與 stub。獨立驗證另外確認了：**已提交的來源樹裡沒有
任何會動主機的路徑**。

### 2. 四次修改測試（各附理由與獨立驗證）

- **L10 的 external 回歸斷言**原本連 TOML 註解一起比對。收斂成「忽略空行與註解」後
  仍逐行比對實際生效的定義；`git diff` 證明差異只有註解那三行。
- **L7 的「nvim-data 只被備份一次」**被 mutation 證明恆真，換成「備份集合精確比對」，
  新版經 mutation 確認會咬。
- **`gate-properties.py` 的 `outside_tui("")`** 修掉 Python `"".split("\n")` 的 artifact。
  修完後重做 negative control，仍然會咬。
- **L5 的「Install-PSResource 必須帶 -Version」**原本連註解行一起數，濾掉註解行後重做
  negative control（拿掉 `-Version` → 立刻紅）。

四次都不是為了讓失敗的實作變綠。

### 3. gate 自己踩到的四個洞（都已修，各留 negative control）

- `tools/gate.sh` 第一版每一層寫成 `cmd | tee file`；管線的退出碼是 `tee` 的，
  **任何一層失敗都會被靜靜吞掉**。改成 fail-closed 的 `run_layer`。
- 有一個 commit 的 `git add -A` 把 `.gate/` 的產出提交進去，下一輪 gate 開頭清產出就讓
  工作樹變髒 —— **source-state 那一層正確地擋下了它**。已加入 `.gitignore`。
- gate 的機密掃描咬到**本報告自己**：它記錄 negative control 時逐字寫了那個範例 AWS
  key。掃描器沒有錯，改的是文件。
- **（本輪新增）** `tools/gate-mutants.py` 的 `run()` 用嚴格 UTF-8 解碼子行程輸出。
  L7 的 Windows 半邊用 `pwsh.exe` 跑腳本，而 `pwsh.exe` 的工作目錄是 UNC 路徑
  （`\\wsl.localhost\...`，mutant 的 worktree 就在那裡）時，`cmd.exe` 會先吐一行
  「不支援 UNC 路徑」的警告，用主機的 ANSI 代碼頁編碼（這台是 CP950）。那一行**只在
  斷言失敗、`_fail` 把 pwsh 的輸出印進診斷時**出現 —— 也就是**只在 mutant 被殺掉的
  那一刻**。於是 `windows-nvim-marker` 被正確殺死的同時 runner 拋 `UnicodeDecodeError`，
  mutation 層中止，後面四層 NOT REACHED。本輪 gate 實際這樣壞過一次（那次中斷就是
  這條的 negative control：修好之前必然壞、修好之後 33/33），已改成 `errors="replace"`。
  這是**只在成功偵測的路徑上才會爆**的一類缺陷，單看綠燈永遠看不到。

### 4. 對 SPEC 的兩項偏離

- **§2.1**：`platform.toml` 的欄位收斂成 `os / arch / isWindows / isPosix / brewPrefix`。
  nvim 路徑在 POSIX 與 PowerShell 需要各自的原生語法，塞進共用 dict 會變成兩份轉譯。
  Windows nvim 路徑的單一來源保證改由 `L7` 提供。
- **§2.4**：SPEC 說備份四個目錄，實作備份三個。原因是 SPEC 自己的 F6 就記載了 Windows
  的 `state` 與 `data` 是同一個路徑 —— SPEC 內部不一致，實作照 F6。
  （這一條是獨立驗證指出我漏了揭露的。）
- **§2.2**：SPEC 列的 Windows 忽略清單含 `.oh-my-zsh/`，`.chezmoiignore` 沒有列它。
  結果等價 —— M6 是靠「Oh My Zsh 那組 external 整段只在 POSIX 輸出」處理的，L5 有斷言 ——
  但清單本身確實與 SPEC 不同。（第二輪 F7。）

### 5. SPEC 沒涵蓋、實作時才發現的一項

Windows 建 symlink 需要 `SeCreateSymbolicLinkPrivilege`，一般帳號要開「開發人員模式」；
chezmoi 會在 `~/.claude/skills` 建兩個 symlink。已在 `init.ps1` 加入事前探測與警告、並
寫進 README。**這條沒有自動化測試**：本機的開發人員模式是開的，乾淨機器上的行為要靠
L9 才看得到（探針裡有對應檢查，且預期它會 FAIL）。

### 6. 已知限制：Windows 的 statusLine 少一個外觀選項

POSIX 的 `statusLine.command` 帶 `STATUSLINE_USAGE_STYLE=dots` 前綴，那是 POSIX shell
語法。上游 README 對 Windows 沒有給任何傳環境變數的方式，因此 Windows 版只放路徑。
猜一個 `cmd /c "set ...&&"` 包法若猜錯會讓 statusline 整個不顯示。

### 7. 隔離樹與落地樹的差異

L7 與 L10 用的暫存 destination 是空的；真實的 `$HOME` 有既有內容。L6 用 16 個預先塞好
的種子檔補這個落差，但那仍然不是「一台用了很久的機器」。

### 8. property 層在本次工作中紅過兩次，都是真的發現

- 第一次完整 gate 執行時抓到 codex 模板與 awk 版在「只含一個空行的檔案」上行為不同。
- 獨立驗證用它自己的生成器在別的 seed 上抓到 Finding 1 的崩潰。

第二次是它**應該**自己抓到卻沒抓到的（寫死單一 seed），這件事本身就是 Finding 2。

### 9. 核准綁定的一項限制

SPEC §8 把核准綁在「§8 被改寫成核准狀態之前」的檔案 sha256 上。歷史裡只存在一個版本的
`spec.md`，所以**那個綁定無法從 git 單獨驗證** —— 只能驗到「核准文字在 git 裡」。
這是這個綁定機制的實際強度，如實記錄。

### 10. lint 是可以補的

`shellcheck` 與 `PSScriptAnalyzer` 都裝得起來，只是那會改動這台機器的環境而我沒有授權。
補上之後這個 gate 會多一層真正的 lint（目前只有語法解析）。
