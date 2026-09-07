# Evidence Report — ArchLinux（omarchy）支援 (Tier 3)

- `headline`: **GATE PASSED — reproducibility degraded（工具版本只有記錄，沒有釘住）；
  Real execution SUBSTITUTED（L9 在 entry point 之外手動跑，且 run 2 的來源狀態早於最終 commit）；
  changed-line coverage UNAVAILABLE；independent verification（Tier 3）round 1 blocked，
  WSL 相依的層改由使用者接手，見 §Honest notes**
- `command`: `evidence`
- `contract`: applied（`~/.claude/CLAUDE.md` 的 evidence-first 契約，未被本 repo 覆寫）
- `scope`: `archlinux-support`
- `change_set`: `4ddc1b5...HEAD`
- `base`: `4ddc1b5`（`origin/main`，PR #16 合併點）
- `report_language`: zh-TW
- `intent_status`: confirmed
- `intent_source`: 已提交的 SPEC `specs/archlinux-support/SPEC.md`（`spec_version: v2`、`status: approved`、`tier: 3`；§Approval 記錄 v2；首次進入歷史 `12165a4`，最後一次改動 `887b4b4 spec(archlinux-support): v2 核准`）
- `ordering`: tests-first —— 五個行為各自的 RED commit 都早於 GREEN commit：
  `bf3d024`/`6fd6502`（L10、L1）→ `b3ab2c0`（platform.toml）；`3557ca4`（L2、L3）→
  `6d64b23`（腳本）；`42814b7`（L11 golden）→ `50ff72b`（zsh 檔案）；`8ae3ee5`（L11 探針
  義務）→ `52492d7`（探針、啟動器、gate）；`3f7e60d`（L2 default-shell）→ `51fc692`（修正）。
  之後的測試提交（`a9e69e6`、`90696bc`、`0a9ddcb`、`3ea61a7`、`e2f16ad`）都是測試結構修正，
  斷言不變；`0cae96d` 是 gate 工具的 fail-closed 修正。逐檔事實見 §RED reconstruction。
- `git_facts`: complete（base 可達、歷史非 shallow、baseline 在 base 的 worktree 實跑、
  順序由 `git log 4ddc1b5..HEAD` 讀出）
- `source_state`: `0cae96dba468c22f9eb21474083e14aee2068fe7`（由 `tools/gate-source-state.sh`
  計算，最終一輪執行的前後各驗一次，兩次相同：`worktree=clean`）
- `source_state_exclusions`: `.gate/`（gate 自己的產出目錄，已在 `.gitignore`）。白名單只有這一項。
- `toolchain`: 這個 repo 沒有 lockfile 可以釘開發工具版本，逐字記錄實際跑的版本
  （`.gate/archlinux-support/versions.txt`）：chezmoi v2.72.0 · git 2.53.0 ·
  zsh 5.9 (x86_64-ubuntu-linux-gnu) · Python 3.14.4 · `/bin/sh` → dash · pwsh 7.6.5
- `entry_point`: `sh tools/gate.sh --scope archlinux-support`
- `reproducibility`: degraded —— 工具版本只有記錄、沒有釘住；entry point 已持久化，來源狀態前後一致。
- `changed_unit_command`: `git diff --name-status 4ddc1b5..HEAD`
- `changed_unit_granularity`: path —— chezmoi 模板／POSIX shell／Python 沒有可用的 symbol 級
  抽取器。**同一個檔案內的個別函式或模板分支沒有被逐一對應。**

執行環境：閘門在 WSL `dev`（Ubuntu 26.04）內、對這個 repo 在 ext4 上的 clone
（`~/gate/dotfiles`，checkout 到與工作樹相同的 commit）執行。透過 `/mnt/d` 跑一輪
套件要約 30 分鐘，ext4 約 7 分鐘；clone 與工作樹的差異只有被 `.gitignore` 的
`.gate/` 與 `.claude/worktrees/`，兩者都不是 gate 的輸入。

## Baseline

**none —— base 是綠的。** 在 `4ddc1b5` 的 worktree（WSL `dev`、ext4）上跑它自己的
`sh tests/run.sh`：`# run 532, failed 0, skipped 0`，rc=0（`/tmp/base-suite.log`）。

主機相關的例外，記錄但不算 baseline 失敗：在 **Windows 主機的 Git Bash** 上，L2 的兩條
`native-wsl` 斷言（`05-wsl-user-runtime-dir 在 isWSL = true 時非空` 與其 `loginctl`
斷言）在 base 與 HEAD 都失敗，因為 `native-wsl.toml` 不帶 `osOverride`，在 Windows
主機上 `.chezmoi.os` 是 `windows`。套件的設計前提是 Linux 主機；最終閘門在 WSL 內執行，
這兩條在那裡通過。

## Changed unit → Test

由 `git diff --name-status 4ddc1b5..HEAD` 導出，不是挑的。granularity 是 path，
所以同一檔案內的個別函式／模板分支不個別對應。

| Changed unit | Test | Status |
|---|---|---|
| `.chezmoitemplates/platform.toml`（distro、pkgManager、brewPrefix） | `L1`（S1–S4，13 條）；`L10`（六個既有 fixture 逐位元組不變）；mutant `platform-pkgmanager-swapped`；L9 的 M4 檢查（真實 chezmoi 在 omarchy 上算出 `arch|arch|pacman|`） | pass |
| `.chezmoiscripts/run_onchange_before_10-install-packages.sh.tmpl` | `L2` S7（分支內容、清單、無 `-Sy`）；`L10` S16（linux 渲染不變）；`L4`（arch 渲染過 zsh -n）；L9 四個前置套件 `pacman -Q` | pass |
| `.chezmoiscripts/run_onchange_before_30-install-pacman-packages.sh.tmpl`（新增） | `L2` S5/S6/S8；`L3` S11/S12；`L11` S18；mutant `pacman-list-drops-neovim`；gate `pacman-ids`（12 個名稱 `pacman -Si`）；L9 八個工具 `pacman -Q` | pass |
| `.chezmoitemplates/pacman-install.sh`（新增） | 經上面兩支腳本的渲染被 `L2`/`L4` 涵蓋；mutant `pacman-syu`；L9 實跑（omarchy 上實際安裝 zsh 與 git-lfs） | pass |
| `.chezmoiscripts/run_once_before_20-install-homebrew.sh.tmpl`、`run_onchange_before_30-install-brew-packages.sh.tmpl` | `L2` S5（arch 空）、S9；`L10` S16 | pass |
| `.chezmoiscripts/run_onchange_after_40-git-lfs.sh.tmpl` | `L2` S10；`L10` S16；L9 `git lfs env` | pass |
| `.chezmoiscripts/run_before_50-neovim.sh.tmpl` | `L2` S5（arch 空）；`L10` S16；mutant `neovim-guard-isposix`；L9 M2 檢查（omarchy 的 nvim 設定未被搬動） | pass |
| `.chezmoiscripts/run_after_default-shell.sh.tmpl` | `L2`（arch 含 readlink -f 對回 /etc/shells，linux 不含）；`L10` S16；L9 D3 檢查（`/usr/sbin/zsh` → `/bin/zsh` 在 /etc/shells，無 tty 時印出手動指令） | pass |
| `dot_zshrc.tmpl`、`dot_zprofile.tmpl` | `L11` S14 golden 與 M6/M7 斷言；`L2` S9；`L10` S15；`L4`（arch 渲染過 zsh -n）；mutant `zshrc-omarchy-block-gone`；L9 登入 zsh 解析 `omarchy-version` 且 `OMARCHY_PATH` 非空 | pass |
| `tests/lib.sh`（`ALL_OSES`/`POSIX_OSES` 加 arch） | 自身即測試基礎：L2–L5 的每個迴圈都多出 arch 欄（suite 753 條 vs base 532 條） | pass |
| `tests/fixtures/os-arch.toml`（新增）、`os-linux*.toml`（distroOverride） | `L1` S1/S2；`L10`（linux fixture 渲染仍與 base 相同） | pass |
| `tests/cases/L1`、`L2`、`L3`、`L10`（新增）、`L11`、`L7` | 自身即測試；有效性由 §RED reconstruction 與 §Negative controls 釘住 | pass |
| `tests/golden/managed-*.txt`、`tests/golden/render/arch/*`（新增）、`tests/golden/verbatim/_probe.sh` | `L3`、`L11` | pass |
| `tests/sandbox/_probe.sh`、`tests/sandbox/omarchy.sh`（新增）、`tests/sandbox/README.md` | `L11`（探針清單與義務，9 條）；L9 兩輪實跑（§Real execution） | pass |
| `tools/gate.sh`（--scope、pacman-ids 層）、`tools/gate-pacman-ids.sh`（新增）、`tools/gate-supply-chain.py`（os-arch、pacman）、`tools/gate-mutants.py`（五個 Arch mutant） | `tools/gate-manifest-audit.sh`（13/13 層留下記號）；pacman-ids 的負向對照（§Negative controls） | pass |
| `AGENTS.md`、`README.md` | `tests/check_agent_doc_invariants.py`（84 項） | pass |
| `docs/research/archlinux-omarchy-support.md`、`specs/archlinux-support/SPEC.md`、本檔 | `tools/gate-intent.sh`；`L3`（不得裝進 `$HOME`） | pass |
| 刪除 | 無 | n-a |

## Stated claim → Test

來自 SPEC v2（intent record），不是來自 diff。

| Claim | Test | Status |
|---|---|---|
| S1 arch 平台事實 `linux\|amd64\|false\|true\|\|arch\|pacman` | `L1` | pass |
| S2 既有平台七欄不變（linux `debian\|apt`、darwin/windows 兩欄空） | `L1` | pass |
| S3 無 distroOverride 時退回 `.chezmoi.osRelease.id` | `L1`（native fixture）；L9 M4（omarchy 內真實 chezmoi） | pass |
| S4 生產 config 沒有 distroOverride | `L1`（原始碼與渲染結果） | pass |
| S5 arch 渲染矩陣（10/30-pacman/40/default-shell 非空；05/20/30-brew/50/.ps1 空） | `L2` | pass |
| S6 pacman 腳本在六個既有 fixture 上為空 | `L2` | pass |
| S7 10 的 pacman 分支內容與清單 | `L2` | pass |
| S8 pacman 清單 = brew 清單 + neovim | `L2` | pass |
| S9 arch 渲染不含 linuxbrew / brew shellenv | `L2`（腳本、.zshrc、.zprofile）；L9 `/home/linuxbrew` 不存在 | pass |
| S10 40-git-lfs 兩發行版行為 | `L2` | pass |
| S11 arch managed 集合 = posix golden | `L3` | pass |
| S12 新腳本 eol=lf | `L3` | pass |
| S13 新腳本與 arch zsh 檔案通過語法檢查 | `L4`（WSL 內有 zsh、pwsh，52 條無 SKIP） | pass |
| S14 arch .zshrc/.zprofile golden | `L11` | pass |
| S15 六個既有 fixture 的檔案樹逐位元組相同 | `L10` | pass |
| S16 六個既有 fixture 的腳本／ignore／externals／config 渲染逐位元組相同 | `L10` | pass |
| S17 pacman 套件名可解析 | gate `pacman-ids`（12 個名稱，經 WSL `omarchy` 的 `pacman -Si`） | pass |
| S18 探針清單與腳本相同 | `L11` | pass |
| S19 omarchy 端到端 | L9 兩輪實跑（§Real execution）；「第二次 apply」一列見 Dismissed concerns | pass（run 1 全部；run 2 除第二次 apply） |
| Must NOT #1 六個既有 fixture 渲染不變；managed 只多一支 | `L10` | pass |
| Must NOT #2 不對 Windows 主機／dev／agent／ca apply | 程序約束：本次 apply 只在 WSL `omarchy`（探針）與測試用暫存 destination；`L1` S4 釘住生產 config | pass |
| Must NOT #3 omarchy 上不搬動 nvim 目錄 | `L2` S5（50-neovim 空）；L9 M2 與第二次 apply 無 `.bak` | pass |
| Must NOT #4 Arch 不裝 Homebrew | `L2` S9；L9 | pass |
| Must NOT #5 只用 `-S --needed --noconfirm` | `L2`（兩支腳本不含 `pacman -Sy`）；mutant `pacman-syu` | pass |
| Must NOT #6 不用 .chezmoiignore 做平台隔離 | `L10`（.chezmoiignore 渲染不變）；`L2` 結構性不變式 | pass |
| Must NOT #7 無未釘版本的外部下載 | `L5`（26 條）；gate `supply-chain`（11 個帶 checksum 的 external，0 個新增或變更） | pass |
| Must NOT #8 omarchy 內只做 init --apply | 啟動器只做 mkdir/chown、複製、tar；探針在 Arch 上 SKIP 移除 neovim（`L11` 釘住） | pass |
| Must NOT #9 不改測試求綠、不報未跑的檢查 | 每次測試改動的理由在 commit 訊息與本檔 Honest notes | pass |
| Must NOT #10 不在 main 提交 | 分支 `feat/archlinux-support`，`git log 4ddc1b5..HEAD` 全在此分支 | pass |
| M1 改壞既有平台 | `L10` | pass |
| M2 50-neovim 在 Arch 執行 | `L2` S5；mutant `neovim-guard-isposix`；L9 | pass |
| M3 brew 腳本在 Arch 執行 | `L2` S5/S9；L9 | pass |
| M4 接縫與真實 osRelease 不一致 | L9 第一列（`arch|arch|pacman|`） | pass |
| M5 套件名錯字 | gate `pacman-ids`（12/12 解析）+ 負向對照（§Negative controls） | pass |
| M6 zsh 失去 OMARCHY_PATH | `L11`；L9（`OMARCHY_PATH=/home/omarchy/.local/share/omarchy`、`omarchy-version` 可解析） | pass |
| M7 .zshrc 載入 bash 專用檔 | `L11`（不含 `default/bash/rc`）；`L4`；L9 登入 zsh 成功 | pass |
| M8 覆寫 omarchy 的 git config | 已接受（D4）；L9 記錄檔案等於 `chezmoi cat` | pass |
| M9 pacman 資料庫過期 | 腳本印出提示；未在 L9 重現（新建映像） | unverified（已知限制） |
| M10 新腳本忘了守衛 | `L2` S6 與 `_expect` 表 | pass |

## RED reconstruction

在 `4ddc1b5` 的 worktree（WSL `dev`、ext4）放入 HEAD 的 `tests/`（含 fixtures 與 golden）
與 SPEC，逐層重放（`/tmp/red-L*.log`）。修改過的測試層不能逐條回放，這裡以層為單位
記錄；每條新增斷言在開發時的 RED 觀察寫在對應的 RED commit 訊息裡。

| Test | Result at base | Note |
|---|---|---|
| `L1` S1、S2（5 條七欄斷言） | failed (assertion) | partial 沒有 `distro`/`pkgManager` |
| `L1` S3 | failed (template error) | `map has no entry for key "distro"` 讓 run.sh 中止 —— 比斷言失敗弱的 RED |
| `L1` S4 | passed | 負向不變式，base 本來就沒有 distroOverride；以一次性 mutant（在 `.chezmoi.toml.tmpl` 加 `distroOverride = "arch"`）證明會紅，留作 regression armor |
| `L2`（S5–S7：腳本存在、20/30-brew/50 在 arch 應為空、pacman 分支 4 條） | failed (assertion) ×8，之後因新腳本不存在而中止（rc=2） | S8–S10 未回放到 —— 它們的 RED 見 commit `3557ca4` 的觀察 |
| `L2` default-shell 兩條 | 見 commit `3f7e60d`：在 HEAD^ 上觀察到 failed (assertion) | 由 L9 實跑發現後補的行為 |
| `L3` 七個 managed golden | failed (assertion) ×7 | 新腳本缺席 |
| `L10` S15、S16 | passed | 回歸護欄，設計上對 base 就要綠；以一次性 mutant（`dot_zshrc.tmpl` 守衛反轉）證明 S15 會紅 |
| `L10` managed 只多一支 | failed (assertion) ×6 | — |
| `L11` S14 六條、S18 兩條 | failed (assertion) ×8 | — |
| `L11` 探針義務五條（M2/M3/M4/M6/#8） | passed | 它們讀的是測試樹裡的探針檔案，回放時已帶 HEAD 的探針；這五條檢查的是測試基礎設施，不是產品，RED 不適用 |

## Gate (final fresh run)

所有數字來自 `sh tools/gate.sh --scope archlinux-support` 在最後一次程式碼修改之後的一次執行
（WSL `dev`，ext4 clone，commit `0cae96d`，2026-09-07 18:10–19:5x）。產出在
`.gate/archlinux-support/`（git 忽略；本 repo 的工作樹內有一份複本）。

| Layer | Command | Threshold (what makes this pass) | Result |
|---|---|---|---|
| versions | `versions()` | 記錄每個工具的版本 | 見 toolchain |
| source-state-before | `tools/gate-source-state.sh` | 工作樹乾淨，未追蹤只有白名單 | `commit=0cae96db… worktree=clean untracked_whitelist=.gate/` |
| intent | `tools/gate-intent.sh archlinux-support` | 從 git 裡的 SPEC 導出 | confirmed，`spec_version: v2` |
| agent-doc-invariants | `python3 tests/check_agent_doc_invariants.py` | 全部不變式成立 | `OK: 84 invariants hold` |
| Tests | `sh tests/run.sh` | 0 new failures vs baseline（baseline 532/0） | `# run 753, failed 0, skipped 0`（L1 13、L2 210、L3 61、L4 52、L5 26、L6 100、L7 53、L8 19、L10 120、L11 99） |
| Suite health (repeat) | 同一 suite 重跑並逐行 diff | 逐行相同 | 重跑結果與第一次逐行相同；`# run 753, failed 0, skipped 0` |
| Suite health (shuffle) | `TESTS_SHUFFLE=1 sh tests/run.sh` | 總數與失敗數不變 | 隨機順序下總數與失敗數不變；`# run 753, failed 0, skipped 0` |
| Property-based | `tools/gate-properties.py --cases 30 --base 4ddc1b5` | P0–P5 全部成立 | 7 seeds ×（30 生成 + 12 敵意 + 5 已知限制）= 329 個案例，P0–P5 全部成立 |
| Mutation | `tools/gate-mutants.py`（每個 mutant 兩輪） | 0 存活 | **39/39 killed**，每個 2/2 輪皆致死；五個 Arch mutant：`platform-pkgmanager-swapped`（L1，2 條）、`neovim-guard-isposix`（L2，2 條）、`pacman-syu`（L2，2 條）、`pacman-list-drops-neovim`（L2，1 條）、`zshrc-omarchy-block-gone`（L11，3 條） |
| Supply chain | `tools/gate-supply-chain.py --base 4ddc1b5` | 0 secret；新增／變更的 external 下載後 checksum 相符；winget ID 可解析 | 11 個帶 checksum 的 external，0 個新增或變更；secrets 掃 2236 行新增內容 0 命中；capability diff：新增外部 host `pkgs.omarchy.org`（研究文件引述 omarchy 的 pacman repo，非本 repo 的下載來源）、新增外部命令 `pacman`；winget 12/12 OK |
| pacman ids | `tools/gate-pacman-ids.sh` | 每個名稱 `pacman -Si` 成功 | 12/12 解析（base-devel、curl、fd、fzf、git、git-lfs、lazygit、mise、neovim、ripgrep、tree-sitter-cli、zsh；core/extra） |
| Changed-line coverage | `tools/gate-changed-lines.py --base 4ddc1b5` | 只報告不設閘（見 Layers not run） | set 1 = 0；set 2（非可執行）= 1549；**set 3（可執行但無覆蓋率對應）= 687**；total 2236 —— UNAVAILABLE |
| source-state-after | `tools/gate-source-state.sh` | 與 before 相同 | 相同（`diff` 空） |
| manifest audit | `tools/gate-manifest-audit.sh` | 13/13 層留下記號 | `13 層全部留下執行記號`；`gate: 全部通過` |

## Real execution（L9，在 entry point 之外）

`tests/sandbox/omarchy.sh` 在 WSL distro `omarchy`（Arch rolling `20260830`，omarchy dev
`f0020448`，tag v4.0.0）內以使用者 `omarchy` 執行 `_probe.sh`，local 模式。這一層不在
entry point 裡（需要那個 distro，且會變更它），所以數字不屬於上表。

| 輪次 | source commit | 結果 | 備註 |
|---|---|---|---|
| run 1（乾淨的 omarchy，第一次安裝） | `52492d7` | PASS=34 FAIL=2 SKIP=2 | 兩個 FAIL：(a) `zsh is a valid login shell`：`command -v zsh` 回 `/usr/sbin/zsh`，不在 `/etc/shells`（產品缺陷，`51fc692` 修正）；(b) `tree-sitter CLI is pacman's`：探針用 `/usr/bin/*` 比對路徑，omarchy 回 `/usr/sbin/*`（探針缺陷，`0a9ddcb` 修正）。其餘全部通過，含 M4 接縫、M2 nvim 未搬動、`/home/linuxbrew` 不存在、OMARCHY_PATH、git config、git lfs、treesitter 編出 lua parser、第二次 apply 無提示、`chezmoi git`、linger。SKIP：`chezmoi update`（local 模式無 remote）、移除 neovim 再裝回（Arch 不移除套件）。 |
| run 2（同一台，已裝過一次） | `0a9ddcb` | PASS=35 FAIL=1 SKIP=2 | 上述兩條改為 PASS（`/bin/zsh` 在 /etc/shells、`/usr/bin/tree-sitter is owned by tree-sitter-cli`）。新的 FAIL：`second chezmoi apply completes without a prompt`，見 Dismissed concerns。 |

| run 3（使用者重建 omarchy 後、乾淨機器；使用者自行執行） | `f2bb435`（產品檔案與 `0cae96d` 相同） | PASS=36 FAIL=0 SKIP=2 | 使用者回報的 SUMMARY 行；SKIP 仍是 `chezmoi update`（local 模式）與移除 neovim。這是 S19 表十四列在同一輪全部成立的那一次。 |
| run 4（remote 模式 `--branch feat/archlinux-support`，分支已推上 GitHub；使用者自行執行） | 推送時的分支 HEAD（`09ac0b7` 或之後；產品檔案同上） | PASS=36 FAIL=0 SKIP=1 | 使用者回報：`chezmoi update completes  ok`，即 `init.sh --branch` 從 GitHub 安裝、`chezmoi update` 在 omarchy 上可用（05-wsl-user-runtime-dir 的路徑）。唯一 SKIP 是移除 neovim（Must NOT #8）。 |

run 2 之後到最終 commit 之間的變更只有測試與 gate 工具（`3ea61a7`、`e2f16ad`、`0cae96d`），
產品檔案（`.chezmoiscripts/`、`.chezmoitemplates/`、`dot_*`）與 run 2 相同。
結果檔：`.gate/l9-omarchy/results.tsv`（run 2；run 1 的表在執行時印到主控台，本檔引用的
數字取自該輸出）。

## Negative controls

- `tests/cases/L10`（S15）—— 在工作樹把 `dot_zshrc.tmpl` 的守衛反轉，L10 對六個 fixture 的
  S15 變紅（`linux：套用結果與 base ref 逐位元組相同` 等）；還原後綠。
- `tests/cases/L1`（S4）—— 在 `.chezmoi.toml.tmpl` 的 `[data]` 加 `distroOverride = "arch"`，
  兩條 S4 斷言變紅；還原後綠。
- `tools/gate-pacman-ids.sh` —— 在拋棄式 worktree 把清單塞入 `no-such-pkg-zz`。**第一次對照
  沒有紅**（`ok no-such-pkg-zz`、exit 0）：`pacman_si | tr` 管線回的是 tr 的狀態，這個檢查層
  原本 fail-open。修正（`0cae96d`）後同一對照 `FAIL no-such-pkg-zz error: package ... was not
  found`、exit 1；正向 12 個名稱仍全部解析。
- `tools/gate-manifest-audit.sh` —— 既有的負向對照（餵缺項的 ran-file 會紅），本次未改。
- Mutation baseline —— `gate-mutants.py` 先在未突變的 worktree 跑所有涉及層的基線，紅則整輪作廢；
  runner 逐一、非並行地套用 mutant（無共用 build 狀態），並斷言 patch 真的改了檔案、事後還原。
  每個 mutant 跑兩輪，兩輪都致死才算 KILLED。
- Mutation kill sample —— 五個 Arch mutant 的死因與突變內容逐一相符（`mutants.txt`）：
  `platform-pkgmanager-swapped` 殺於 L1 的 linux 與 arch 七欄斷言（2 條）；`neovim-guard-isposix`
  殺於 L2「50-neovim 在 arch 上渲染成空」與 S9（2 條）；`pacman-syu` 殺於 L2 兩條「沒有 pacman -Sy」；
  `pacman-list-drops-neovim` 殺於 L2「pacman 清單 = brew 清單 + neovim」（1 條）；
  `zshrc-omarchy-block-gone` 殺於 L11 的 golden 與兩條 env-bootstrap 斷言（3 條）。
  runner 不並行、每個 mutant 兩輪，所以這裡沒有共用 build 狀態的歸因問題；抽樣範圍是五個新
  mutant（39 個中的 5 個），其餘 34 個沿用 windows-support 的記錄。

## Layers not run as specified

- **N-A (this project has no such surface):** Types —— chezmoi 模板與 POSIX shell 沒有型別檢查器。
- **UNAVAILABLE (tool missing):** Changed-line coverage —— 三種語言在這個環境沒有覆蓋率工具；
  `gate-changed-lines.py` 只報告變更行數，不設閘。
- **SUBSTITUTED:** Lint —— 沒有 shellcheck；以 `L4`（`zsh -n`、`sh -n`、pwsh Parser）代替，
  只能抓語法錯誤，抓不到語意層的 lint 問題。Real execution —— L9 在 entry point 之外手動執行
  （見上表），且 run 2 的來源狀態早於最終 commit（產品檔案相同，測試檔案不同）。
- **NOT REACHED:** none —— 13 層全部執行。
- **DEPENDENCY UNMET:** none —— suite health 兩層都通過，mutation 與 changed-lines 的前提成立。

## Dismissed concerns

- L9 run 2 的 `second chezmoi apply completes without a prompt` 失敗 —— 不是本次變更造成，也不是
  Arch 專屬。訊息是 `.oh-my-zsh/custom/themes/powerlevel10k/gitstatus/gitstatus.plugin.zsh.zwc has
  changed since chezmoi last wrote it`：powerlevel10k 的 external 是 `exact = true`，zsh 第一次
  互動載入時會在該目錄編譯出 `.zwc`（tarball 內沒有 `.zwc`，`curl | tar -tz` 計數 0）；
  apply 把它們刪掉並記入 state，zsh 再編一次，下一次 `apply --no-tty` 就對「chezmoi 寫過、
  現在又變了」的檔案要求互動。同一狀況在使用者現有的 Ubuntu `dev` distro 上也存在
  （`chezmoi status` 列出 9 個 `AD ... .zwc`）。run 1（乾淨機器）的第二次 apply 通過，因為
  當時 state 裡還沒有這些檔案。修法會改到 `.chezmoiexternal.toml.tmpl` 的所有 POSIX 渲染，
  違反 Must NOT #1，列為後續工作。
- Windows 主機上 L2 的兩條 `native-wsl` 斷言 —— base 與 HEAD 同樣失敗，原因是主機 OS；
  最終閘門在 WSL 內執行，那裡 210 條 L2 全綠。
- suite-health-repeat 第一次在 WSL 跑到 2 條 L7 Windows 撞名案例失敗 —— 既有的計時脆弱性
  （撞名視窗只種 0–6 秒，pwsh.exe 經 interop 啟動常超過）；`e2f16ad` 把視窗種到 30 秒，
  斷言不變；之後三輪 suite 逐行相同。

## Structural blind spot

- 只驗證了 WSL 變體、dev 模式（`OMARCHY_PATH=~/.local/share/omarchy`）的 omarchy。裸機
  Hyprland 桌面與正式安裝（`/usr/share/omarchy`、`/etc/profile.d/omarchy.sh`）沒有實測；
  `.zshrc` 的 env-bootstrap 區塊同時涵蓋兩條路徑，但只有 dev 路徑被 L9 證明。
- 純 Arch（沒有 omarchy）不在本次範圍：50-neovim 在 Arch 上是空的，不會 clone LazyVim starter。
- macOS 仍無實機；darwin 的證據全部經由 `osOverride` 接縫。
- `chezmoi update`（remote 模式）在 omarchy 上沒有跑（local 模式無 remote）。
- omarchy 的 migrations 是否會改動本 repo 管理的檔案：未逐一讀取。

## Honest notes

- 工作樹整理：開始時 repo 根目錄有一個 4 GB 的 `WSLomarchy-snapshot-20260907.tar`（未追蹤，
  使用者的 WSL 匯出）。chezmoi 會把它當成受管檔案複製到每個測試 destination（L10 第一次跑
  時六份），已移到上一層目錄 `D:\Projects\dotfiles-dev\`，內容未動。另外十個受
  `.gitattributes` 管的檔案在 Windows 工作樹是 CRLF（`git ls-files --eol` 顯示 `w/crlf`），
  導致 L10 的 apply 結果帶 `\r`；以 `rm` + `git checkout --` 重新 checkout 為 LF，
  提交內容未變。
- 閘門第一次在 WSL 執行時 L1 的 S2 失敗：linux fixture 沒有 `distroOverride`，在 Ubuntu
  主機上讀到 `ubuntu`。`3ea61a7` 把兩個 linux fixture 釘 `debian`，斷言不隨主機而變。
- 透過 `/mnt/d`（DrvFs）跑一輪 suite 約 30 分鐘，改在 ext4 clone 上跑約 7 分鐘；閘門因此
  重啟了三次（S2、L7 脆弱性、pacman-ids fail-open），每次都在新的 commit 上從頭跑。
- omarchy 啟動器踩到兩個 wsl.exe 的坑：`wsl.exe -- sh -c '...'` 會先經 distro 的登入 shell
  展開 `$ID`/`$@`（改走 stdin）；Git Bash 會把 `/src/dotfiles` 改寫成 Windows 路徑
  （`MSYS_NO_PATHCONV` 只套在 wsl.exe 那一層，export 會弄壞 `git -C /d/...`）。
- L9 的 run 1 在 omarchy 上實際安裝了 `zsh` 與 `git-lfs`（其餘套件出廠已有），寫入
  `$HOME` 的受管檔案，並開啟 linger；該 distro 供驗證使用、將重建（SPEC §6）。
- 五個 Arch mutant 對應的層各自單獨執行；mutation 的 kill 歸因給第一個失敗的測試，
  所以分數證明的是整個 suite，不是每一層。
- 獨立驗證（Tier 3，`verifier` 代理，round 1，source state `0cae96d`）：verdict **blocked**。
  代理的沙盒拒絕所有 `wsl.exe` 呼叫，S17、S19、L4、mutation、supply-chain、pacman-ids 無法由它
  重跑；它在 Windows 側獨立重跑 L1/L2/L3/L5/L6/L7/L8/L10/L11（L10 120/120；L2 的兩條 native-wsl
  與 base 相同）與兩個 Python 檢查，並做 SPEC↔測試雙向對照，未發現行為性或映射缺陷。
  完整報告在 `.scratch/archlinux-support/verification.md`。WSL 相依層的獨立重跑改由使用者接手
  （清單已交付：在 WSL `dev` 的乾淨 clone 重跑 entry point；重建 omarchy 後跑
  `tests/sandbox/omarchy.sh`；推送後以 `--branch` 驗 `chezmoi update`；互動式 `chsh`；
  裸機／正式安裝的 omarchy）。這是宣告的降級，不是通過。
- CLOSE 之後的一個測試修正：使用者在 WSL `dev` 獨立重跑 entry point（`0cae96d`），suite 層在
  L7 的 Windows 撞名案例再次失敗（與 L9 同時執行、pwsh.exe 啟動超過 30 秒的視窗）。改成在
  wrapper 裡以同名 function 蓋掉 `Get-Date`，時間戳固定、不再依賴牆上時鐘；L7 在 WSL 連跑兩次
  53/53。這個 commit 只動 `tests/cases/L7-behavior.sh` 與本檔，產品檔案不變；上表的數字仍是
  `0cae96d` 那一輪，使用者的獨立重跑應改用這個 commit。
- 已知的既有缺陷（未修，見 Dismissed concerns）：`.zwc` 讓已使用過 zsh 的機器第二次以後的
  `chezmoi apply --no-tty` 中止；修法會動到所有 POSIX 平台的 externals，超出本 SPEC 範圍。
