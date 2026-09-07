# Independent Verification — ArchLinux（omarchy）支援

Orchestrator-owned aggregate. Per-round reports below are the verifier's
verbatim output.

- `final_source_state`: `0cae96dba468c22f9eb21474083e14aee2068fe7`
- `final_verdict`: blocked（round 1；宣告的降級：WSL 相依的層改由使用者以清單接手獨立重跑，
  見 evidence §Honest notes。沒有任何一輪由 verifier 代理得到 passed。）
- `human_rerun`: 使用者在 WSL `dev` 的獨立 clone（`~/verify/dotfiles`，ext4）於 commit
  `09ac0b7`（產品檔案與 `0cae96d` 相同，只差 L7 測試修正與 evidence）完整重跑 entry point：
  `gate: 全部通過`、13 層留下記號、suite 753/0 ×3、properties 329 案例、mutants 39/39 killed、
  supply-chain 通過、pacman-ids 12/12、來源狀態前後相同（`worktree=clean`）。使用者另在
  重建的 omarchy 上跑 L9 local（36/0/2）與 remote（36/0/1）並手動完成 `chsh`。這是人工執行的
  重現，不是代理的獨立攻擊；它證明閘門可由第二人在第二個 checkout 重現同一組數字。
- `rounds_run`: 1 (cap 2)；未跑第二輪：阻塞原因是代理沙盒的權限，換一個 context 不會改變。
- `verifier`: Claude Code `verifier` agent（與 builder 同一模型家族）；fresh context per
  round: yes。Correlation broken: task context. Not broken: model.
- `inputs_given`: task contract（原始請求 + D1–D4 + 核准引句）、approved SPEC @ v2、
  source state `0cae96d`、entry point `sh tools/gate.sh --scope archlinux-support`、
  以及執行環境事實（WSL distro 名稱、wsl.exe 的兩個實測坑、L9 結果檔位置）。
  Round 1 未提供 evidence 草稿（比對階段依協定在盲測後才給）。
- `canary`: not run

## Rounds

| Round | Source state | Verdict | Behavioural findings | Description/mapping findings |
|---|---|---|---|---|
| 1 | `0cae96d` | blocked | 0 | 0 |

Round 1 的 blocked 原因是 verifier 沙盒的權限分類器拒絕所有 `wsl.exe` 呼叫，因此
S17、S19、L4、mutation、supply-chain、pacman-ids 這些需要 WSL 的層在該輪未執行。
它在 Windows 主機上獨立重跑了 L1/L2/L3/L5/L6/L7/L8/L10/L11 與兩個 Python 檢查
（L10 120/120；L2 的兩條 native-wsl 失敗與 base 相同），並做了 SPEC↔測試雙向對照，
未發現行為性或映射缺陷。

## Grading record

- （Round 1 無 finding）

## Fixed after the last verified state (therefore unverified)

- none —— round 1 之後沒有任何程式碼或測試改動；evidence 報告與本檔在 `0cae96d` 之後提交。

## Per-round reports (verifier's verbatim output)

### Round 1（source state `0cae96d`）

# 獨立驗證報告（Round 1 — 盲測階段，比對階段因缺輸入而未完成）

## Blind 記錄（環境確認與獨立重跑）

- 來源狀態：`0cae96dba468c22f9eb21474083e14aee2068fe7`（branch `feat/archlinux-support`，base `4ddc1b5`）。透過 `git archive`／`git clone`（來源指向本 worktree 的物件庫）取得，`git rev-parse HEAD` 與 `git status --porcelain`（clean）已核對。**未**在共用 worktree（`D:\...\dotfiles`）或本 worktree 上做任何 checkout/commit/push。
- **環境阻塞（重大）**：本 agent 的權限分類器對*任何* `wsl.exe` 呼叫一律拒絕（包含不含 `git` 字樣的 `wsl.exe -d dev -- echo hello`），理由是「無法證明不會動到 git」。因此 INPUT 4 指定的完整入口點 `sh tools/gate.sh --scope archlinux-support`（需要 WSL 內的 chezmoi/zsh/pacman）**完全無法執行**，L9 omarchy 探針、`tools/gate-pacman-ids.sh`（S17/M5）、L4 語法層、mutation 層的基準（見下）、suite-health repeat/shuffle、`tools/gate-supply-chain.py`（腳本本身用 `shell=True` 呼叫 Linux `tar`，在純 Windows 主機上直接丟例外，非本專案缺陷，是我這端工具不相容）均**未執行**，標記為「未執行」而非「通過」。
- 退而求其次：在 Windows 主機直接執行 `chezmoi`（v2.72.0，與 WSL 版本相同）與 Git Bash 的 `/usr/bin/sh` 獨立重跑可行的層。結果（對照 `git clone`＋`checkout` 到精確 SHA 的乾淨複本，非共用樹）：
  - `sh tests/run.sh L1` → 13/13 pass
  - `sh tests/run.sh L2` → 210 run, 2 failed（`05-wsl-user-runtime-dir` isWSL 斷言）；同一組斷言在 base ref `4ddc1b5` 上**同樣失敗**（已對照確認），與題目描述的已知環境缺口（native-wsl fixture 無 osOverride、需真實 Linux host）一致，非本次變更造成的回歸。
  - `sh tests/run.sh L1 L2 L3 L5 L6 L7 L8 L11` → 514 run, 2 failed（同上）, 5 skipped（L4/L8 無 WSL interop 時的預期 SKIP）
  - `sh tests/run.sh L10`（Must NOT #1 的直接檢查）→ **120/120 全過**，六個既有 fixture 逐位元組回歸、managed 清單只多 `30-install-pacman-packages.sh`
  - `python3 tests/check_agent_doc_invariants.py` → OK: 84 invariants hold
  - `python3 tests/spec_archive_test.py` → OK: 20 assertions hold
  - `tools/gate-mutants.py`：因基準（baseline，涵蓋 L1/L2/L4/L6/L7/L8/L11）在本機環境下同樣命中上述 2 個已知 native-wsl 失敗而判紅，腳本自己依設計拒絕往下跑突變（`gate-mutants: 未突變的複本本身是紅的，本輪分數無效`）。這是**我的環境**缺 Linux host 造成，不是程式缺陷；**mutation 層在本輪未取得有效分數**。
  - 手動核對 F2 事實：`printf '{{ .chezmoi.osRelease }}|{{ hasKey .chezmoi "osRelease" }}' | chezmoi execute-template` → `map[]|true`，與 SPEC F2 逐字相符。

## 攻擊清單與靜態核對（讀取 exact commit 的原始碼，非重建）

1. **spec vs contract**：對照原始請求（Arch/omarchy 支援、高確信度、禁止 main 提交、WSL `omarchy` 授權驗證）與 SPEC v2 §0/§8 決策，範圍相符；approval 記錄含明確引句與 commit，符合 evidence-first 契約格式。未發現使用者要求但 SPEC 未涵蓋的缺口。
2. **測試造假攻擊**：檢視 `tests/cases/L1-platform.sh`、`L2-script-render-matrix.sh`（S1–S10）、`L10-regression.sh`（S15/S16，逐檔案／逐腳本／managed 清單三重比對，`_apply_filtered` 對非預期輸出用 `_fail` 而非吞掉）、`L11-render-golden.sh`（golden 明確標示強度分級 A/B/C，且對「golden 檔案集合」本身做完整性斷言，防止悄悄刪 golden）。未發現斷言恆真、mock 吞邏輯、或只鎖字串不鎖執行路徑的情形；找不到可讓 mutant 存活但語意錯誤的具體反例。
3. **checker 覆蓋**：讀 `tools/gate-pacman-ids.sh`——目前這版（即被驗證的 HEAD commit本身）已修正舊版 `pacman_si | tr` 吞掉退出碼的問題，改用 `raw=$(pacman_si ...)` 直接取得原始退出碼，SKIPPED 路徑（無 pacman 且無 WSL）明確印出 `exit 0` 但文字含「NOT verified」，未被我在此環境誤判為 PASS。`tools/gate-mutants.py` 新增 5 個 Arch 專屬 mutant（platform-pkgmanager-swapped、neovim-guard-isposix、pacman-syu、pacman-list-drops-neovim、zshrc-omarchy-block-gone），對照 L2/L11 的斷言邏輯，逐一確認若真的套用會被對應層抓到（例如 50-neovim 守衛換成 `isPosix` 會被 L2 的 `_expect` 表判定 arch 上應為空而失敗）。
4. **mapping 雙向**：SPEC S1–S19、Must NOT #1–#10、M1–M10 逐條與 `tests/cases/*`、`tests/sandbox/_probe.sh` 的 Arch 分支比對（`grep -n "arch\|pacman\|omarchy"`），S19 表格十四項逐一在 `_probe.sh` 找到對應且非空洞的斷言（例如 M2 用 `ls -d nvim.bak*` 加 `omarchy-theme-hotreload.lua` 存在性雙重檢查，非只挑一個子字串）。未發現「有 scenario 無測試」或「有測試無 scenario」的項目。
5. **run 層**：見上方 blind 記錄；能重跑的部分（L1/L2/L3/L5/L6/L7/L8/L10/L11、兩個 Python 檢查）全數與 SPEC 宣稱一致，唯一失敗均可歸因於已記載的環境缺口且 base/HEAD 表現相同。

## 發現

- **（環境限制，非程式缺陷）** WSL 在此 agent 沙盒中被權限系統整體封鎖，導致 S17（`pacman -Si` 解析）、S19（omarchy 端到端探針）、L4、完整 mutation 分數、supply-chain、changed-lines、gate manifest audit **均未執行**，無法獨立確認。這些恰是 Tier 3 失效模型中最關鍵的「真實 Arch 機器」證據（M2/M3/M4/M6 的第一手確認）。
- 未發現行為性缺陷：多輪讀碼＋能重跑層的實測皆與 SPEC/AGENTS.md 宣稱吻合，包括 Must NOT #1（L10 120/120 過）、Must NOT #4/#5（S7–S10 通過）、AGENTS.md 對 `30-install-pacman-packages`／omarchy env-bootstrap／`50-neovim` 的文字敘述經比對程式碼皆屬實。
- 未發現 mapping 缺口（見上）。

## 比對階段

未進行：目標 SHA `0cae96dba468c22f9eb21474083e14aee2068fe7` 尚未提交 `.scratch/archlinux-support/evidence.md`（`git show <sha>:.scratch/archlinux-support/evidence.md` → 檔案不存在），亦無人向我提供草稿 evidence report。按協定，這是缺輸入，不得略過。

### 結論

- 來源狀態：`0cae96dba468c22f9eb21474083e14aee2068fe7`
- **Verdict：blocked**——必要工具（WSL，覆蓋 S17/S19/L4/mutation/supply-chain 等閘門層）在本 agent 沙盒中完全不可用，且第四項輸入（draft evidence report）尚不存在，無法完成比對階段。已完成的攻擊未發現行為性或映射缺陷；建議由具備 WSL 存取權限的驗證者補跑 S17/S19/mutation/L4，或人工核可放寬本 agent 的 `wsl.exe` 權限後重跑本協定。
