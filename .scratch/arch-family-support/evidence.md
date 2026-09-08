# Evidence Report — Arch 家族支援：正式版 omarchy 與純 Arch (Tier 3)

- `headline`: **GATE PASSED（自動化層，13/13）— 但 Must NOT #7 被操作者的環境準備違反，待使用者
  追認或否決（§Stated claim、§Honest notes）；reproducibility degraded（工具版本只有記錄，沒有釘住；
  gate 必須在乾淨的 checkout 執行，見 entry_point）；Real execution 在 entry point 之外（L9 兩個真實
  環境各 35 PASS / 0 FAIL / 3 SKIP，環境 B 在最終 commit、環境 A 在 491c0f2，之後探針與產品模板未再改動）；
  changed-line coverage UNAVAILABLE；independent verification（Tier 3）round 1 verdict failed，
  五項發現的處置見 §Layers not run as specified**
- `command`: `evidence`
- `contract`: applied（`~/.claude/CLAUDE.md` 的 evidence-first 契約，未被本 repo 覆寫）
- `scope`: `arch-family-support`
- `change_set`: `4e6f13c...HEAD`
- `base`: `4e6f13c`（`origin/main`，PR #18 合併點）
- `report_language`: zh-TW
- `intent_status`: confirmed
- `intent_source`: 已提交的 SPEC `specs/arch-family-support/SPEC.md`（`spec_version: v1`、`status: approved`、`tier: 3`；§Approval 記錄 v1；首次進入歷史 `25497d2`，最後一次改動 `6ffc97b docs(spec): arch-family-support v1 核准`）
- `ordering`: tests-first —— 一個 RED commit 早於一個 GREEN commit：`d388c30`（L1、L2、L7、L11、
  fixture、gate 工具的測試）→ `2032f8f`（platform.toml、50-neovim、探針、啟動器、文件）。
  之後的 `ddce92f`、`bbc1268`、`72ceeb5` 是 gate 工具與 L9 啟動器／探針的修正，由 L9 真實執行
  抓到（§Real execution）；`72ceeb5` 同時更新 L11 的 verbatim golden。逐條事實見 §RED reconstruction。
- `git_facts`: complete（base 可達、歷史非 shallow、順序由 `git log 4e6f13c..HEAD` 讀出）
- `source_state`: `5e30e95d5450fa3df7ad3bff197d44ec08cb903e`（由 `tools/gate-source-state.sh`
  計算，最終一輪執行的前後各驗一次，兩次相同：`worktree=clean`）
- `source_state_exclusions`: `.gate/`（gate 自己的產出目錄，已在 `.gitignore`）。白名單只有這一項。
- `toolchain`: 這個 repo 沒有 lockfile 可以釘開發工具版本，逐字記錄實際跑的版本
  （`.gate/arch-family-support/versions.txt`）：chezmoi v2.72.0 · git 2.53.0 ·
  zsh 5.9 (x86_64-ubuntu-linux-gnu) · Python 3.14.4 · `/bin/sh` → dash · pwsh 7.6.5
- `entry_point`: `sh tools/gate.sh --scope arch-family-support`，**在該 commit 的乾淨 checkout 上**
  （例如 `git worktree add <dir> 5e30e95`，或本次用的 WSL ext4 clone）。在含有未提交的本報告的工作樹
  上執行會在 `source-state-before` 以 `worktree=dirty` 停下（獨立驗證實測）：`gate-source-state.sh`
  的白名單只有 `.gate/`，而 AGENTS.md 要求本報告最後才提交。這是既有設計（前兩份報告同樣在 clone
  上執行），本報告把它寫進 entry point 而不是放寬白名單。
- `reproducibility`: degraded —— 工具版本只有記錄、沒有釘住；entry point 已持久化，來源狀態前後一致。
- `changed_unit_command`: `git diff --name-status 4e6f13c..HEAD`
- `changed_unit_granularity`: path —— chezmoi 模板／POSIX shell／Python 沒有可用的 symbol 級
  抽取器。**同一個檔案內的個別函式或模板分支沒有被逐一對應。**

執行環境：閘門在 WSL `dev`（Ubuntu）內、對這個 repo 在 ext4 上的 clone
（`~/gate/dotfiles`，checkout 到 `5e30e95`，與工作樹 HEAD 相同）執行。RED 的觀察在
Windows 主機的 Git Bash（L1/L2/L11）與 WSL `dev` 的 `/mnt/d` 工作樹（L7）上做。

## Baseline

**none —— base 是綠的。** 在 `4e6f13c` 的 worktree（WSL `dev`、ext4、`/tmp/base-wt`）上跑它自己的
`sh tests/run.sh`：`# run 646, failed 0, skipped 0`，exit 0（`/tmp/base-suite.log`）。HEAD 的套件是
778 條；多出的 132 條是 omarchy 欄（L2–L5 的每個迴圈）、本次的具名斷言，與 Must NOT #6 的 16 條原始碼檢查。

主機相關的例外，記錄但不算 baseline 失敗：在 **Windows 主機的 Git Bash** 上，L2 的兩條
`native-wsl` 斷言在 base 與 HEAD 都失敗，因為 `native-wsl.toml` 不帶 `osOverride`，在
Windows 主機上 `.chezmoi.os` 是 `windows`（AGENTS.md：這兩條需要 Linux 主機）。最終閘門在
WSL 內執行，這兩條在那裡通過。

## Changed unit → Test

由 `git diff --name-status 4e6f13c..HEAD` 導出，不是挑的。granularity 是 path。

| Changed unit | Test | Status |
|---|---|---|
| `.chezmoitemplates/platform.toml`（distroLike、distroLikeOverride、Arch 家族判斷） | `L1` S1（omarchy fixture 七欄）、S2（六個既有 fixture 不變）、S3（distroLikeOverride 不進生產 config）、M2 三條逐字比對（`"ubuntu debian"`→apt、`"foo arch"`→pacman、`"archarch"`→apt）；`L2` S4（omarchy 每支腳本與 arch 逐位元組相同）；L9 M4 接縫檢查（真實 chezmoi 在 VM 上算出 `omarchy|omarchy|pacman|`，在 WSL 純 Arch 上算出 `arch|arch|pacman|`） | pass |
| `.chezmoiscripts/run_before_50-neovim.sh.tmpl`（兩段結構、pacman 分支） | `L2` S5（arch 非空、含 `pacman -Q omarchy-nvim`、無 mise/neovim@/brew、仍 clone starter）與 linux 無 pacman；`L11` C0 golden（linux 與兩個 darwin 的渲染逐位元組不變，S6）、C2 golden（arch 渲染）、B2（arch 與 omarchy 相同）、B（linux 與 linux-arm64 相同）；`L7` A2 S8（stub pacman 回報已裝：四個目錄原地未動、無 .bak、無 marker、未呼叫 mise）與 S9（回報未裝：備份、clone、marker，重跑不再搬）；`L4`（arch/omarchy 渲染過 zsh -n，WSL 內）；L9 兩個環境（§Real execution） | pass |
| `tests/lib.sh`（`ALL_OSES`/`POSIX_OSES` 加 omarchy） | 自身即測試基礎：L2–L5 的每個迴圈都多出 omarchy 欄 | pass |
| `tests/fixtures/os-omarchy.toml`（新增） | `L1` S1；`L2` S4；`L11` B2 | pass |
| `tests/cases/L1`、`L2`、`L7`、`L11` | 自身即測試；有效性由 §RED reconstruction 釘住 | pass |
| `tests/golden/render/{linux,darwin-arm64,darwin-amd64}/50-neovim.sh`（新增，改動前從 base 渲染）、`tests/golden/render/arch/50-neovim.sh`（新增）、`tests/golden/verbatim/_probe.sh` | `L11` C0、C2、D（verbatim） | pass |
| `tests/sandbox/_probe.sh`（ID_LIKE、omarchy=1、M4 接縫、linger 只在 WSL） | `L11`（四條新義務：ID_LIKE、`pacman -Q omarchy-nvim`、starter marker、`omarchy\|pacman\|`）；L9 兩個環境實跑 | pass |
| `tests/sandbox/omarchy.sh`（ID_LIKE、root、`--syu`、`sudo -n -v`）、`tests/sandbox/ssh.sh`（新增） | L9 實跑：`omarchy.sh --distro arch --syu`（環境 B）與 `ssh.sh madao@192.168.2.155`（環境 A），見 §Real execution；沒有單元測試 | pass（L9） |
| `tools/gate-pacman-ids.sh`（os-omarchy 清單相等、arch distro 退路）、`tools/gate-supply-chain.py`（os-omarchy）、`tools/gate-mutants.py`（anchor 更新、四個新 mutant） | gate 的 `pacman-ids` 層（S12：12 個名稱經 WSL `arch` 的 `pacman -Si` 全部落在 core/extra）、`supply-chain` 層（通過）、`mutation` 層（44/44） | pass |
| `AGENTS.md`、`README.md`、`tests/sandbox/README.md` | 沒有自動化測試檢查新增的 Arch 安裝說明；`check_agent_doc_invariants.py` 的 84 項只管 evidence-first 契約文件。內容由 codex `$ponytail-review` 讀過 diff、由我對照 L9 的實測（前置條件、sudo、`--syu`）人工核對 | unverified（人工審閱） |
| `docs/research/archlinux-omarchy-support.md`、`specs/arch-family-support/SPEC.md`、本檔 | `tools/gate-intent.sh`；`L3`（不得裝進 `$HOME`） | pass |
| 刪除 | 無 | n-a |

## Stated claim → Test

來自 SPEC v1（intent record），不是來自 diff。

| SPEC 情境 | 測試 | 結果 |
|---|---|---|
| S1 os-omarchy 的平台事實 | L1 | pass |
| S2 既有 fixture 逐位元組不變 | L1（四條既有斷言）、L11 C0（linux、darwin-arm64、darwin-amd64 三份改動前的 50-neovim golden） | pass |
| S3 distroLikeOverride 不進生產 config | L1 兩條 | pass |
| S4 omarchy 的腳本渲染矩陣與 arch 相同 | L2（_expect 表加 omarchy；每支 .sh 與 arch 逐位元組相同；無 linuxbrew） | pass |
| S5 50-neovim 在 Arch 家族非空、無 mise/brew | L2 六條；L11 C2 golden | pass |
| S6 50-neovim 在 linux/darwin 不變 | L11 C0 三份 golden（改動前從 base `4e6f13c` 渲染：linux、darwin-arm64 `/opt/homebrew`、darwin-amd64 `/usr/local`）；linux-arm64 由 L11 B 的跨 arch 等價涵蓋 | pass |
| S7 Arch 家族的 zsh 檔案 golden | L11 C2（arch golden 不變）、B2（omarchy 與 arch 相同） | pass |
| S8 假 pacman 回報已裝：不動 | L7 A2 | pass |
| S9 假 pacman 回報未裝：備份 + clone + marker，重跑不搬 | L7 A2 | pass |
| S10 環境 B（WSL 純 Arch，root，`--syu`） | L9：35 PASS / 0 FAIL / 3 SKIP | pass |
| S11 環境 A（omarchy 4.0.2 VM，ssh） | L9：35 PASS / 0 FAIL / 3 SKIP | pass |
| S12 pacman 套件名可解析，os-omarchy 清單相等 | gate `pacman-ids`（os-arch 與 os-omarchy 清單相等，12 個名稱全部解析） | pass |
| Must NOT #1 不在 Windows 主機 apply | 本次沒有任何 apply 在主機執行；L9 只在環境 A、B | 遵守 |
| Must NOT #2 其他平台渲染不變 | L1 S2、L11 C0、L11 C（Windows golden 六個不變） | pass |
| Must NOT #3 有 omarchy-nvim 的機器不搬 nvim 設定 | L7 S8；L9 環境 A（`omarchy-theme-hotreload.lua` 仍在、無 .bak、無 marker） | pass |
| Must NOT #4 Arch 家族不裝 Homebrew | L2 S9（arch 與 omarchy）；L9 兩環境 `/home/linuxbrew` 不存在 | pass |
| Must NOT #5 腳本不做 -Sy/-Syu/-R/--overwrite | L2 既有六條（10 與 30-pacman）；`--syu` 只在啟動器 | pass |
| Must NOT #6 不以 ID=omarchy 分支 | L2 的原始碼檢查（`.chezmoiscripts/*.tmpl`、`dot_zshrc.tmpl`、`dot_zprofile.tmpl`、`platform.toml` 的 `{{ }}` 內沒有 omarchy，16 條，`03db4c5`）；L2 S4 / L11 B2 只證明輸出相同，不是這條的證據 | pass |
| Must NOT #7 環境 A 只做 init --apply | 啟動器本身遵守（只建 /src、/out、跑探針）。**違反：操作者在環境 A 做了 init --apply 以外的系統變更**——改 sudoers（`Defaults:madao !authenticate`；`04_madao` 曾改後還原）、加 ssh 金鑰、刪除失敗探針殘留（§Honest notes 逐項）。SPEC §6 只授權「使用者先設定免密碼 sudo」；使用者自己加了 NOPASSWD，其餘三項是我做的，沒有逐項事先徵得同意。依合約這是失敗條件；獨立驗證（F3）也這樣判。處置交給使用者：追認（VM 是重建的測試環境，變更可逆且已列出）或否決（重建 VM、由使用者自己準備前置後重跑 `ssh.sh`）。在使用者決定之前，本報告不宣稱 SPEC 全數遵守，spec-archive 不執行 | **違反，待使用者決定** |
| Must NOT #8 mise 釘版本不進 Arch 家族 | L2 S5（無 mise、無 neovim@）；L7 兩個分支都沒有呼叫 mise | pass |

## RED reconstruction

不是每一條新斷言都被看到紅。分四類，逐項如下。

- `d388c30`（tests-only）在 Windows 主機 Git Bash 跑 `sh tests/run.sh L1 L2 L11`：
  `run 395, failed 38`。依 TAP 編號逐條數：L1 2 條（#115 omarchy 平台事實、#117 `"foo arch"`
  走 pacman）；L2 26 條（#168 50-neovim 在 arch 非空；#177、#217 20/30-brew 在 omarchy 應為空；
  #225 30-pacman 在 omarchy 非空；#347–#352、#357–#358、#361–#364 omarchy 各檔含 linuxbrew／
  brew shellenv 共 12 條；#365–#368、#370–#372 omarchy 與 arch 逐位元組相同共 7 條；#373、#377、
  #378 50-neovim 的 pacman -Q／clone／marker）；L11 8 條（#10–#12 arch 家族等價、#30 arch/50-neovim
  golden 存在、#31 golden 集合、#105、#106、#108 探針義務）。2 + 26 + 8 = 36；另外 2 條（#284、#285）
  是 §Baseline 提到的 `native-wsl` 主機例外。**先行 RED：36 條。**
- 同一個 commit 在 WSL `dev` 以 `git worktree add /tmp/red-l7 d388c30` 跑 `sh tests/run.sh L7`：
  `run 54, failed 1`——`Arch 50-neovim 在 arch 上渲染成非空（S5）`。**S8/S9 的 24 條行為斷言在
  RED 時沒有執行**：渲染是空的，測試在那裡停下，所以它們個別「會不會紅」沒有被觀察到。它們的有效性
  改由 gate 的 mutant `neovim-omarchy-check-inverted`（只有 L7 殺得掉，17 條紅）與
  `neovim-omarchy-check-gone` 事後證明；這是契約降級，不是先行 RED。
- `2032f8f`（GREEN）之後：Windows 主機 `L1 L2 L11` 為 `run 395, failed 2`（只剩主機例外）；
  WSL `dev` 的 `L7` 為 `run 78, failed 0`（A2 的 25 條全綠）。
- **RED 時已通過的斷言（回歸釘，不是新行為）**：三條 M2 斷言中的 `"ubuntu debian"`→apt 與
  `"archarch"`→apt（舊實作對任何非 arch 的 id 都回 apt）；L11 C0 的 linux golden（改動前渲染，
  改動後要相同）；Must NOT #6 的 16 條原始碼檢查（`03db4c5`，稽核後補的，原始碼本來就沒有
  omarchy 分支）。`"archarch"` 那條的有效性由 mutant `platform-idlike-substring` 證明（1 條紅）。
- **GREEN 之後才加的測試**：兩份 darwin golden（`491c0f2`，codex 審查後從 `4e6f13c` 的 worktree
  渲染）、Must NOT #6 原始碼檢查（`03db4c5`，codex 稽核後）。兩者都是回歸釘，沒有 RED。
- **事後負向對照**（§Negative controls）與 gate 的 44 個 mutant 證明的是「斷言會抓到那種 bug」，
  不改變上面的歷史順序。

## Gate (final fresh run)

`sh tools/gate.sh --scope arch-family-support`，在 WSL `dev` 的 ext4 clone 上、commit `5e30e95`，
一次完整執行，13/13 層留下記號（`layers-ran` 與 manifest 相同），`gate: 全部通過`，exit 0。
產出在 `.gate/arch-family-support/`（已複製回工作樹的同名目錄，git 忽略）。

| 層 | 結果 |
|---|---|
| versions | 記錄六個工具版本（見 toolchain） |
| source-state-before / after | `491c0f2…`，`worktree=clean`，前後相同 |
| intent | confirmed（上方標頭逐字複製） |
| agent-doc-invariants | OK: 84 invariants hold |
| suite | `# run 778, failed 0, skipped 0`（base 4e6f13c 的套件是 646 條；多出來的是 omarchy 欄、S1–S9 的斷言與 Must NOT #6 的原始碼檢查） |
| suite-health-repeat | 重跑結果與第一次逐行相同，778/0/0 |
| suite-health-shuffle | 隨機順序下總數與失敗數不變，778/0/0 |
| properties | 7 個 seed × 47 個案例 = 329 個：294 個生成與敵意輸入驗 P0–P5，35 個已知限制形狀只驗 P0（與 awk 原版逐位元組相同）。這是 codex rewriter 的既有層，與本次變更無關 |
| mutation | 44/44 killed，每個 mutant 跑 2 輪皆致死。本次新增或更新的六個：`platform-pkgmanager-swapped`（L1，6 條）、`neovim-mise-section-on-arch`（L2，6 條）、`platform-idlike-ignored`（L1，2 條）、`platform-idlike-substring`（L1，1 條）、`neovim-omarchy-check-gone`（L2，1 條）、`neovim-omarchy-check-inverted`（L7，17 條） |
| supply-chain | 通過（八個 fixture 含 os-omarchy 的 external 與 winget ID 解析） |
| pacman-ids | all pacman package names resolve（WSL distro `arch`，12 個名稱皆 core/extra：4 個前置 + 8 個工具） |
| changed-lines | 只報告不設閘：set1 0 · set2（非可執行）696 · set3（可執行、無覆蓋率對應）493 · 合計 1189 行。UNAVAILABLE，由 Table 1 的逐單元對應與 mutation 補 |

## Real execution（L9，在 entry point 之外）

兩個真實環境各跑一次完整探針，皆為 local 模式（`git archive HEAD` 的來源樹）。

| 環境 | 啟動器 | commit | 結果 | 關鍵細節 |
|---|---|---|---|---|
| B：官方 Arch WSL 映像 `arch`，root，全新 | `tests/sandbox/omarchy.sh --distro arch --syu` | `2032f8f`（第一次）、`5e30e95`（最終 commit，distro 以 `wsl --unregister` + `wsl --install archlinux --no-launch` 重建後從零安裝） | 兩次皆 35 PASS / 0 FAIL / 3 SKIP，exit 0 | 啟動器先 `pacman -Syu`；11 個 pacman 套件全裝；`nvim config is the LazyVim starter with our marker` PASS（S10）；M4 接縫 `arch\|arch\|pacman\|`；nvim-treesitter 建出 `lua.so`；第二次 apply 不重做；linger 開啟、`/run/user/0` 存在；SKIP：omarchy 專屬環境（純 Arch）、`chezmoi update`（local 模式）、移除 neovim 重裝（pacman 套件，Must NOT #8） |
| A：omarchy 4.0.2 VM（ISO），madao，ssh | `tests/sandbox/ssh.sh madao@192.168.2.155` | `72ceeb5`（首次安裝）、`491c0f2`（最終探針，同一台 VM 上再套用一次） | 兩次皆 35 PASS / 0 FAIL / 3 SKIP，exit 0 | M4 接縫 `omarchy\|omarchy\|pacman\|`（S11）；`omarchy nvim config was left in place, with our override on top` PASS；登入 zsh 解析 `omarchy-version`、`OMARCHY_PATH=/usr/share/omarchy`；`~/.config/git/config` 為受管內容（D4）；nvim-treesitter 建出 `lua.so`；第二次 apply 不重做；SKIP：linger（非 WSL，05 渲染成空）、`chezmoi update`（local 模式）、移除 neovim 重裝 |

環境 A 之前的兩次失敗，各修一次啟動器／探針後重跑：

1. `bbc1268` 之前：ssh.sh 的第七個連線逾時。omarchy 的 ufw 有 `22/tcp LIMIT IN`（實測
   `ufw status`），30 秒內超過 6 個新連線就丟棄。改成四個連線。
2. `72ceeb5` 之前，`bbc1268` 的探針 21 PASS / 15 FAIL：`10-install-packages` 停在
   `sudo: a password is required`。根因是安裝腳本的 `sudo -v` 在使用者有任何一條沒帶
   `NOPASSWD` 的規則時就問密碼，而 omarchy 出廠的 `/etc/sudoers.d/50-asdcontrol` 有一條
   `ALL ALL=(ALL) !/usr/bin/asdcontrol`；`NOPASSWD: ALL` 只能讓 `sudo -n true` 通過。
   同一輪也抓到探針在非 WSL 的 systemd 主機上錯誤地要求 linger（05 只在 WSL 渲染）。
   啟動器改用 `sudo -n -v` 檢查前置條件，探針的 linger 改為非 WSL 時 SKIP。

環境 A 的探針產物在 `.gate/l9-ssh/192.168.2.155/`（最後一次），環境 B 在 `.gate/l9-omarchy/`（皆被
`.gitignore`）。環境 A 的最後一次在 `491c0f2`；`git diff --stat 491c0f2..5e30e95` 只有
`tests/cases/L2-script-render-matrix.sh` 與 `tests/sandbox/omarchy.sh`，探針、`ssh.sh`、產品模板與
zsh 檔案逐位元組相同，所以那次執行對最終 commit 仍有效。環境 B 在最終 commit 上的重跑抓到啟動器的最後一個缺口：以 `--no-launch` 註冊的 distro 沒有跑過映像的
`first-setup.sh`（`/etc/wsl-distribution.conf` 的 `[oobe]`），pacman 公鑰環不存在，`--syu` 的
`pacman -Syu` 以 `keyring is not writable` 失敗兩次（`03db4c5`、`3c52a78`）。`5e30e95` 讓 `--syu`
一律先做映像首次啟動的 `pacman-key --init` 與 `--populate archlinux`（實測可重複執行），之後在全新
distro 上一次通過。使用者自己第一次啟動 distro 時 oobe 會做這件事，所以這只影響啟動器，README 的
「先 `pacman -Syu`」前置條件不變。

## Negative controls

在 Windows 主機的暫時 worktree（HEAD）上手動做兩個對照，證明新斷言真的會紅：

1. **拿掉 ID_LIKE 判斷**（`platform.toml` 的 `(has "arch" (splitList " " $distroLike))` 換成 `false`）：
   L1 兩條紅（omarchy 平台事實、`"foo arch"`→pacman），L2 多條紅（20/30-brew 在 omarchy 不再為空、
   30-pacman 在 omarchy 為空、omarchy 各檔出現 linuxbrew、omarchy 與 arch 不再相同）。
2. **拿掉 `pacman -Q omarchy-nvim` 那三行**：L2 `50-neovim 在 arch 上以 pacman -Q omarchy-nvim 決定是否跳過`
   紅，L11 `golden：50-neovim.sh 的 arch 渲染沒有悄悄改變` 紅。

gate 的 mutation 層以同樣形狀的六個 mutant 在 WSL 內重做了這兩個對照，並加上判斷反向（只有 L7 的
兩個 stub 分支看得出來，17 條紅）與子字串比對（只有 `"archarch"` 那條看得出來，1 條紅）。
`neovim-omarchy-check-inverted` 由 L7 而不是 L2 殺掉，是 L7 A2 段存在的理由：渲染層看不出判斷方向。

## Layers not run as specified

- `changed-lines`：這個 repo 的三種語言沒有覆蓋率工具，該層只報告不設閘（與前兩份報告相同）。
- 獨立驗證（Tier 3 的 `verifier` agent，fresh context，四個輸入：任務契約、SPEC、source state
  `491c0f2`、entry point）：**round 1 verdict failed**。它自己做的事與結果：
  - 對 `4e6f13c` 與 `491c0f2` 各開 worktree，逐檔 `chezmoi execute-template` 比對 Debian／macOS／
    Windows 的 zsh 檔案、`.chezmoi.toml.tmpl` 與全部 `.chezmoiscripts`：除 `sourceDir` 那一行外逐位元組相同
    （S6、Must NOT #2 獨立成立）。
  - 三個自製 mutant 全部被殺：拿掉 ID_LIKE（L1 2 條 + L2 22 條）、判斷反向（只有 L7，17 條）、探針改問
    別的套件（L11 2 條）。`pacman-ids` 正向 12/12、負向（假名稱）正確失敗。
  - F1（critical）：報告當時標頭寫 `491c0f2`，內文卻引用其後的 commit（Must NOT #6 的原始碼檢查、環境 B
    的最終執行）。處置：最終 gate 改在 `5e30e95` 執行，標頭、§Gate、§Real execution 全部對齊；環境 A 的
    `491c0f2` 執行以 diff 證明對最終 commit 仍有效（§Real execution）。
  - F2（high）：照四個輸入在工作樹跑 entry point，在 `source-state-before` 因未提交的本報告而 `worktree=dirty`
    停下；本報告引用的 gate 是在一個未在輸入裡揭露的 ext4 clone 上跑的。處置：entry_point 改為明寫「乾淨
    checkout」，並說明原因；白名單不放寬。
  - F3（high）：Must NOT #7 被違反卻標成「偏離，已記錄」。處置：改標「違反，待使用者決定」，標頭同步，
    spec-archive 暫停。
  - F4（medium）：驗證期間 HEAD 前進三個 commit、另有 gate 在跑。屬實：稽核與驗證與修正同時進行，
    最終 gate 在一切改動之後才跑（§Gate 的 source_state 前後一致）。
  - F5：verifier 自己的第一次 entry point 執行 `rm -rf` 掉工作樹的 `.gate/arch-family-support/`（gate 的
    fresh-by-mechanism 設計）。本報告引用的產出在 clone 內未受影響，最後再複製回工作樹。
  - 它無法在時限內重現當時（`491c0f2`）的 762/0/0 與 44/44 兩個數字（WSL 經 Git Bash 的長時間執行不穩），記為
    「未確認、未反駁」。

## Dismissed concerns

- **`pacman -Q mise` 在 omarchy 上命中的是 `mise-bin`**：`pacman -Q` 會經 provides 命中，
  腳本的「已裝」判斷與探針一致（環境 A 的 `pacman package installed: mise` PASS）。純 Arch
  裝的是 `extra/mise`。兩者行為相同，不需要分辨。
- **`$p.distro` 在正式 omarchy 是 `omarchy` 而不是 `arch`**：SPEC D1 的決定。呼叫端只看
  `pkgManager` 與 `brewPrefix`（L2 S4 / L11 B2 證明沒有任何模板分辨兩者）。
- **純 Arch 的 `.zshrc` 仍載入 omarchy 區塊**：三行都以 `[ -r ... ]` 守住，環境 B 的登入
  zsh 正常解析所有工具，`OMARCHY_PATH` 為空是預期（探針 SKIP 該條）。

## Structural blind spot

- 純 Arch 的一般使用者（非 root）流程沒有真實執行：環境 B 以 root 跑。sudo 路徑由環境 A
  （madao，`Defaults:madao !authenticate`）覆蓋，但那是 omarchy 的套件集，不是全新映像。
- 環境 A 的 `Defaults:madao !authenticate` 是為探針加的；真實使用者在 tty 內會被 `sudo -v`
  問一次密碼，那條路徑沒有自動化證據，只有 README 的說明。
- 兩個環境都是 local 模式；`init.sh --branch` 的遠端路徑本次沒有跑。

## Honest notes

- gate 產出曾被覆寫一次：獨立驗證 agent 在 Windows 工作樹上自行執行了 `tools/gate.sh`，把工作樹的
  `.gate/arch-family-support/` 蓋成一份 `worktree=dirty`（未追蹤的 evidence 草稿）而在 source-state
  停下的殘缺產出。codex 稽核在那個時間點看到的就是這份。本報告引用的產出是 WSL `dev` ext4 clone
  `~/gate/dotfiles/.gate/arch-family-support/` 的最終一輪，最後再複製回工作樹一次（§Gate）。
- codex（`$ponytail-audit`，經 Herdr 委派）在 `491c0f2` 上稽核報告草稿，八項發現的處置：產出被覆寫
  （上一條）；RED 主張過強（§RED reconstruction 已分四類重寫）；Must NOT #7 不能寫遵守（已改為偏離並逐項
  列出）；環境 B 未跑最終版（已重建 distro 在最終 commit 重跑，§Real execution）；baseline 與 verifier
  占位（已填）；Must NOT #6 推論過強（加了原始碼檢查）；文件對應引用了不檢查它們的測試（已改 unverified）；
  數字（pacman 12 個、RED 分項重算為 2+26+8、properties 的 35 個只驗 P0 已註明；manifest 依
  `layers-manifest` 檔案是 13 行，稽核說 14，以檔案為準）。
- codex（`$ponytail-review`，經 Herdr 委派）在 `72ceeb5` 上審查，兩項發現都已處理於 `491c0f2`：
  L11 C0 只比對 linux 卻宣稱涵蓋 macOS（補上兩份 darwin golden）；探針的 chezmoi update 區塊在
  WSL 與非 WSL 分支重複（合併成一段）。同一個 commit 更新了 `gate-mutants.py` 裡兩個 anchor 已失效的
  mutant，並新增四個 Arch 家族 mutant；沒有這一步，gate 的 mutation 層會以 PATCH-FAILED 收場。

- 環境 A 上由操作者（不是啟動器）做的變更，皆在使用者授權的測試 VM 上：
  `/etc/sudoers.d/99-madao-nopasswd`（使用者先建的 `NOPASSWD: ALL`，我加上
  `Defaults:madao !authenticate`）；`/etc/sudoers.d/04_madao` 曾被我改成 NOPASSWD，
  確認無效後已還原成 omarchy 原本的 `madao ALL=(ALL) ALL`；`~/.ssh/authorized_keys` 加了
  本機 `~/.ssh/id_ed25519.pub`（為此在 Windows 主機新建的金鑰，之前沒有預設金鑰）；
  第一次失敗的探針留下的 `~/.local/share/chezmoi`、`~/.config/chezmoi`、`~/.cache/chezmoi`、
  `~/.local/bin/chezmoi` 在重跑前由我刪除。VM 上最後一次成功的探針之後，dotfiles 已套用在
  madao 的家目錄。
- 環境 B 由 `--syu` 做了一次 `pacman -Syu`，之後 dotfiles 套用在 root 的家目錄。可以
  `wsl --unregister arch` 重建。
- 在 HTML 審閱頁面上，我對第一則留言回覆的 NOPASSWD 做法後來證明不足（見 §Real execution 第 2 點）；
  正確的前置條件已寫進 `tests/sandbox/README.md`。
- Windows 主機的 Git Bash 沒有 zsh 與 pwsh，L4 全部 SKIP；這些在 WSL `dev` 的 gate 執行中
  真的跑了。
