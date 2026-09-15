# Evidence Report — spec-version-bump (Tier 2)

- `headline`: BLOCKED at Mutation（38/44；六個存活的 mutant 全部依賴本機不存在的
  `pwsh.exe`，base ref 與本輪逐一相同。後四層與 manifest 稽核 NOT REACHED）
- `command`: `evidence`
- `contract`: applied（`~/.claude/CLAUDE.md` 的 evidence-first 契約 v0.8，未被本 repo 覆寫）
- `scope`: spec-version-bump
- `change_set`: `9a2e879`...`248c501`（gate 那一次執行的樹。本報告自己在這個範圍之外：
  它是這一輪最後才寫的，`changed_unit_command` 的輸出因此不含它）
- `base`: `9a2e879`
- `report_language`: zh-TW
- `intent_status`: confirmed
- `intent_source`: 已提交的 SPEC `specs/spec-version-bump/SPEC.md`（`spec_version: v2`、`status: approved`、`tier: 2`；§Approval 記錄 v1 v2；首次進入歷史 `5d7409a`，最後一次改動 `248c501 fix(spec-archive): 未閉合圍欄裡的紀錄不再算核准，SPEC 三處文字對回實測`）
- `ordering`: mixed —— 兩組是 tests-first（`2b6226a` RED → `4e1a8b5` GREEN；
  `085726d` RED → `58ab021` GREEN），**S11 是先實作後測試**：它涵蓋的
  `more than one Approval section` 由 `4e1a8b5` 引入，S11 本身由 10 個 commit 之後的
  `f4308d8` 引入，所以它從未被觀察到先紅（事後重建會紅，見 RED reconstruction）。
  同批的 CRLF guard 是真正的 GREEN-guard：在 base 就是綠的。
- `git_facts`: complete
- `source_state`: `248c50141a819b5613925fb4b3de4771820b27ca`（`tools/gate-source-state.sh`，
  `worktree=clean`）。**只有執行前那一次驗到**：gate 停在 mutation，`source-state-after`
  與 `tools/gate.sh:211` 的 `diff` 都沒有執行，記成 NOT REACHED。
- `source_state_exclusions`: `.gate/`（唯一的白名單；驗證腳本本身已進版控）
- `toolchain`: chezmoi v2.72.1 / git 2.55.0 / zsh 5.9.2 / Python 3.13.15 /
  `/bin/sh` → bash；**pwsh: ABSENT**（`versions.txt` 逐字）
- `entry_point`:
  `bwrap --dev-bind / / --ro-bind <ID=debian 的 os-release> /etc/os-release --chdir <HEAD 的乾淨 detached worktree> sh tools/gate.sh --scope spec-version-bump`
- `reproducibility`: degraded —— 入口需要兩個環境前提才跑得動，兩者都不是本次變更
  造成的，見 Honest notes 的 E1、E2。在裸主機上直接跑 `tools/gate.sh` 會更早停在
  suite 層。
- `changed_unit_command`: `git diff 9a2e879..248c501 --name-only`（17 個檔案）
- `changed_unit_granularity`: symbol（`spec-archive.py` 與 `gate-intent.sh` 以函式／
  常數名對應；文件類變更以檔案為單位，該檔內個別段落不逐一對應）

## Baseline

none — base 在同樣的執行條件下是綠的：`sh tests/run.sh` 於 `9a2e879` 的乾淨
worktree 內、同一個 namespace 下得 `# run 739, failed 0, skipped 16`。
`tests/spec_archive_test.py` 在 base 為 37 assertions、`check_agent_doc_invariants.py`
為 90 invariants，兩者在 base 皆 exit 0。

## Changed unit → Test

| Changed unit | Test | Status |
|---|---|---|
| `spec-archive.py::check_approval`（R1／R2） | `spec_archive_test.py::S1,S2,S5,S7,S8,S9a,S9b` | pass |
| `spec-archive.py::approved_versions`／`APPROVAL_LIST_RE`／`APPROVAL_SECTION_HEAD_RE` | `::S3`（含 `s3b` fixture）、`::S4,S6` | pass |
| `spec-archive.py::VERSION_END`（版號 token 結尾） | `::S4`（`approves v3junk` 誘餌） | pass |
| `spec-archive.py::_valid_date` | `::S4`（`2026-13-45` 誘餌） | pass |
| `spec-archive.py::_without_noise`（兩種圍欄、未閉合圍欄、HTML 註解） | `::S4`（```` ``` ````／`~~~`／未閉合／註解四個誘餌） | pass |
| `spec-archive.py::approval_section`（多章節 exit 2） | `::S11` | pass |
| `spec-archive.py` 檔頭拒絕清單、`_without_noise` docstring | — （說明文字） | n-a |
| `gate-intent.sh` 的 awk 解析器 | — 無測試；見 Honest notes H3 | unverified |
| `gate.sh`：manifest 加 `spec-archive-tests` 層 | `gate-manifest-audit.sh`（本輪未執行，NOT REACHED） | unverified |
| `check_agent_doc_invariants.py`：2 條 `forbid`、2 條 `require` | 自身 exit code；四條各自移除字面後逐一轉紅 | pass |
| `dot_agents/workflows/evidence-first.md`、`templates/spec.md`、`evidence-squad/SKILL.md`、`docs/evidence-first.md`、`spec-archive/SKILL.md` | `check_agent_doc_invariants.py` 的 94 條（只涵蓋字面，不涵蓋語意） | pass |
| `AGENTS.md` | — 該腳本讀不到這個檔（`grep -c AGENTS tests/check_agent_doc_invariants.py` → 0） | unverified |
| `.chezmoitemplates/evidence-first-contract.md` | — 本次唯一的變更是第 1 行 `v0.8` → `v0.9` 的 Go template 註解標記，沒有 invariant 讀它（見 H7） | unverified |
| `tests/spec_archive_test.py` | 自身 exit code（86 assertions）；新增誘餌的非空洞性見 Negative controls | pass |
| `specs/spec-version-bump/SPEC.md`、2 份 squad 紀錄 | — （紀錄與流程產物） | n-a |
| `.gitignore` | — 不在 SPEC 授權的 12 個檔案內，見 H10 | unverified |

## Stated claim → Test

| Claim | Test | Status |
|---|---|---|
| R1：目前版號沒有結構完整的紀錄 → exit 1 | `::S1,S2,S4,S5,S9b` | pass |
| R2：整數 `vN` 缺 v1…vN 任一 → exit 1 | `::S7,S8` | pass |
| 判定順序先 R1 後 R2 | 臨時 repo：v3＋只有 v2 → `no complete approval record for v3` | pass |
| 非正整數版不執行 R2 | `::S9a`（v0.2 ＋自己那筆 → exit 0） | pass |
| §2 的十條解析規則 | `::S3`（`s3b` fixture）、`::S4,S6,S11`；9 個 mutant 逐一轉紅 | partial —— 「章節邊界」那一條（層級 3 的 `### Approval` 裝不下分節式紀錄）沒有任何 fixture |
| Must NOT：不驗證原話真偽／加入時間／內容綁定 | 捏造紀錄實測放行；`reviewed_commit`／`hashlib` 出現 0 次 | pass |
| Must NOT：不讀 git 判定版號浪費 | `check_approval` 內 git 呼叫 0 次 | pass |
| Must NOT：不新增正整數限制 | `::S9a`（正向控制） | pass |
| Must NOT：不改 `--check` 行為 | 臨時 repo：CLOSE 拒絕的 SPEC 仍被 `--check` 列為 candidate（rc 0） | pass |
| Must NOT：不把 R2 搬進 gate、gate 保留 unconfirmed exit 0 | 待審 v2 時 `gate-intent.sh` 印 `unconfirmed`、`exit=0` | pass |
| Must NOT：拒絕路徑不改檔／不搬目錄／不 commit | `expect_refused()` 的四項斷言 × 9 個拒絕案例 | pass |
| Must NOT：不改 `specs/archive/` | `git diff 9a2e879..HEAD -- specs/archive/` 為空 | pass |
| Must NOT：不變更 metadata 儲存格式 | `templates/spec.md` 只改註解內容，`- \`key\`: value` 形狀未動 | pass |
| Must NOT：不使既有 invariant 失效、不改既有斷言的 rc／stderr | 94 invariants 綠；既有斷言的 diff 只有補核准紀錄 | pass |
| Must NOT：不新增第三方相依 | import 只有 `argparse datetime re subprocess sys pathlib` | pass |
| Must NOT：不把 `approval: not obtained` 視為核准 | 無測試（`grep -c "not obtained"` 在腳本與測試都是 0） | unverified |
| S10：擋住兩句已知壞措辭的復原 | `check_agent_doc_invariants.py` 兩條 `forbid`，各自轉紅 | pass |
| 「不保證減少核准請求次數」 | 無法機械驗證（SPEC §0 已就地標註） | unverified |

## RED reconstruction

| Test | Result at base | Note |
|---|---|---|
| S1,S2,S3,S4,S5,S7,S8,S9b（8 個拒絕案例 × 5 斷言） | failed（40 of 79） | 在 `2b6226a` 的抽出樹上以 base 的 `archive()` 跑，逐一 `got rc 0` |
| S6, S9a | passed | GREEN-guard：base 的 `archive()` 根本不解析核准章節 |
| S4 新增的六個誘餌 | failed（1 of 80） | 對 `2a93375` 的實作跑，誘餌被當成 v3 紀錄，R1 放行後死在 R2 |
| S4 第七個誘餌（未閉合圍欄） | failed（1 of 86） | 只把 `_without_noise` 還原成成對圍欄版，S4 轉紅 |
| S3 的 `s3b` fixture（`v1.2` 正向控制） | failed | 標題版號截斷 mutant → 轉紅；未突變時綠 |
| S11 | failed（5 斷言） | **測試晚於實作**（`f4308d8` 在 `4e1a8b5` 之後 10 個 commit），所以這是事後重建，不是當時觀察到的 RED。以 base 的 `spec-archive.py` 跑當前測試檔得 `45 of 86`，其中 5 條是 S11 的 `got rc 0` |
| CRLF guard | passed | 真正的 GREEN-guard：同一次 base 執行裡它是 `ok:`；非空洞性見 Negative controls |
| S10 第二條 `forbid` | failed | 本輪補觀察：把 `bump the version, set` 放回 workflow → rc 1 |

## Gate (final fresh run)

`248c501` 的一次完整執行。

| Layer | Command | Threshold | Result |
|---|---|---|---|
| versions | `tools/gate.sh:103` 的內嵌 `versions()` | 逐字記錄 | chezmoi v2.72.1 / git 2.55.0 / Python 3.13.15 / **pwsh ABSENT** |
| source-state-before | `tools/gate-source-state.sh` | 工作樹乾淨 | `commit=248c501 worktree=clean` |
| intent | `tools/gate-intent.sh` | 從 git 裡的 SPEC 導出 | `confirmed`，`spec_version: v2`，§Approval 記錄 v1 v2 |
| agent-doc-invariants | `python3 tests/check_agent_doc_invariants.py` | 0 條失效 | **94 invariants hold** |
| spec-archive-tests | `python3 tests/spec_archive_test.py` | 0 條失敗 | **86 assertions hold** |
| suite | `sh tests/run.sh` | 相對 baseline 0 條新失敗 | **739 run, 0 failed, 16 skipped**（baseline: 0） |
| suite-health-repeat | 重跑一次比對 | 逐行相同 | 739 run, 0 failed；與第一次逐行相同 |
| suite-health-shuffle | 隨機順序 | 總數與失敗數不變 | 739 run, 0 failed |
| properties | `python3 tools/gate-properties.py` | P0–P5 全部成立 | 7 seed × 47 = **329 案例**，P0–P5 全成立 |
| **mutation** | `python3 tools/gate-mutants.py` | 0 個非等價 mutant 存活 | **38/44 killed；6 存活 → FAIL** |
| supply-chain | — | — | **NOT REACHED** |
| pacman-ids | — | — | **NOT REACHED** |
| changed-lines | — | — | **NOT REACHED** |
| source-state-after | — | — | **NOT REACHED** |
| manifest audit | — | — | **NOT REACHED**（`tools/gate.sh:218`，在所有 `run_layer` 之後） |

六個存活的 mutant：`windows-nvim-marker`、`windows-nvim-data-backup`、
`loader-idempotency`、`loader-line-content`、`backup-timestamp-fallback-windows`、
`neovim-skip-aborts-apply`。六個都只由 L7 的 Windows 分支證偽，而 L7 因
`command -v pwsh.exe` 找不到而 skip。**在 base ref `9a2e879` 上以同一個指令跑，
結果是同樣的 38/44、同樣這六個，存活清單 `diff` 為空；本輪在 `248c501` 重跑一次，
六個名稱再次逐字相同。** 這一層的失敗與本次變更
無關，但它仍是失敗：本報告的 headline 因此是 BLOCKED，後四層是 NOT REACHED。

## Negative controls

- `check_approval` —— 9 個手工 mutant 各自單獨套用，**9/9 讓
  `spec_archive_test.py` 轉紅**：放寬版號 token 結尾、拿掉日期驗證、拿掉 ``` 圍欄
  剝除、拿掉 `~~~` 圍欄剝除、把圍欄剝除還原成只認成對圍欄（未閉合圍欄那一條，
  單獨還原得 `1 of 86`）、拿掉 HTML 註解剝除、接受 `decision: confirmed`、不比對
  `version bound`、截斷標題版號。
- `approval_section` 的結構歧義檢查 —— 拿掉 `len(heads) > 1` 的 `die` → S11 的 5 條
  斷言轉紅。
- CRLF guard —— 把 `spec.read_text()` 換成 `read_bytes().decode()` → 該斷言轉紅。
- 四條 doc invariant（2 `forbid` ＋ 2 `require`）—— 各自移除其字面後逐一轉紅。
- 正整數限制的反向控制 —— 在 `check_approval` 的 R2 守衛
  （`if POSITIVE_INTEGER_VERSION_RE.fullmatch(version):`）之前插入
  `if not POSITIVE_INTEGER_VERSION_RE.fullmatch(version): die(1, …)`，**3 個斷言
  轉紅**（`S3 the same ### v1.2 record does archive a v1.2 spec`、
  `S9a a dotted version with its own record archives`、`a dotted version that
  matches archives`），證明 Must NOT 那一條有守住。**更正**：本報告先前寫 39，
  重現不出來；before-archive cut 的兩個透鏡各試四種插入點得 3／4／7／8，都不是 39。
  這裡填的是上面那個逐字 mutant 的實測值。
- 兩支解析器的集合比對 —— `spec-archive.py` 與 `gate-intent.sh` 的 awk 對 git 裡
  5 份真實 SPEC ＋ 這 27 個對抗性輸入得到同一個集合。**「0 不一致」只對這 32 個
  輸入成立，不是普遍性宣稱**：before-archive cut 另造 10 個輸入，其中 2 個不一致
  （未閉合圍欄；紀錄本文中一行裸 `#`）。未閉合圍欄那一條已由 `_without_noise` 的
  修正收斂（awk 原本就得空集合）；裸 `#` 那一條仍不一致，記在 H11。（此為診斷
  量測，不是 gate 的一層，也沒有進 repo。）

## Layers not run as specified

- **UNAVAILABLE**：L4／L7／L8 的 PowerShell 部分 —— 本機沒有 `pwsh` 也沒有
  `pwsh.exe`（WSL interop 不存在），16 個斷言 skip。沒有任何東西代跑。
- **DEPENDENCY UNMET**：mutation —— 它跑了，但六個 mutant 的唯一證偽者 L7 是
  UNAVAILABLE。這一層的 38/44 因此不能解讀成「suite 對 Windows 腳本的防護力」，
  只能解讀成「在沒有 pwsh.exe 的主機上可測到的部分全部殺掉」。
- **NOT REACHED**：supply-chain、pacman-ids、changed-lines、source-state-after、
  manifest audit（`tools/gate.sh:218`，在所有 `run_layer` 之後）——
  入口停在 mutation。四層另外單獨跑過都通過（supply-chain 通過、pacman 名稱全部
  解析、changed-lines 列出 16 個檔案、source-state-after 與 before 相同），**但那
  不是本輪同一次執行的數字，不得填進上表，也不得用來把 NOT REACHED 升級。**

## Dismissed concerns

- 「CRLF 的 SPEC.md 會整批漏掉分節式紀錄」（SPEC v2 授權修正）—— 實測**不可達**：
  把 CRLF 字串直接餵給正規式確實得 `[]`，但封存腳本四處讀檔（:200/:228/:262/:291）
  全走 `Path.read_text()`，universal newlines 在正規式看到之前就去掉了 `\r`；經檔案
  讀入得 `['v1']`。因此**授權了但沒有行使**，改為加一條 GREEN-guard 釘住現況。
- 「gate 與 CLOSE 的判決應該一致」—— 兩者回答不同問題（SPEC §1.4）。實測：v2＋只有
  v2 核准時 gate `confirmed`／exit 0，CLOSE 以 R2 拒絕。這是設計，不是矛盾。

## Structural blind spot

這個 repo 的 suite 在沒有 `pwsh.exe` 的主機上完全不執行 Windows 腳本的行為層（L7）
與 Windows 主機端接縫（L8）。因此本報告對「Windows 上的實際行為」沒有任何證據，
mutation 的分數也帶著同一個洞。

這個洞不是整塊的。逐一量過 16 條 skip 之後：

- **12 條 L4 的 PowerShell 解析檢查**只要裝 Linux 的 `pwsh` 就會執行。
  `tests/cases/L4-syntax.sh:6` 已經寫成
  `command -v pwsh.exe || command -v pwsh`，而且 `:16-25` 的 Windows TEMP 轉換只對
  `*.exe` 生效，非 Windows 的 pwsh 走本機 `$TMP`。**不需要 Windows 主機。**
- **2 條 L4 的 Windows PowerShell 5.1 檢查**要 `powershell.exe`，換不掉：它測的就是
  5.1 用 ANSI code page 讀 BOM-less 腳本這件事。
- **1 條 L7 的 Windows 行為檢查**（`tests/cases/L7-behavior.sh:240-241` 一條 skip 蓋住
  整個 Windows 區塊）。該區塊裡的 C 段（loader 的兩個 mutant）是直譯器無關的——
  loader 已抽成 `.chezmoitemplates/pwsh-profile-loader.ps1`，由呼叫端設 `$target`——
  所以它的門檻（`:232` 只認 `pwsh.exe`）**可以改**，改完 mutation 會多殺 2 個。
  B 段的隔離手法是 `.cmd` stub ＋ `%TEMP%` ＋ `wslpath` ＋ `%LOCALAPPDATA%` 重導向，
  那 4 個 mutant 需要 Windows 語意。
- **1 條 L8** 需要 WSL interop ＋ Windows 端 chezmoi ＋ UNC 存取，換不掉。

所以天花板是：裝 `pwsh` ＋ 改 L7 的 C 段門檻 → 40/44，**仍然失敗**。真正要讓
mutation 轉綠只能換一台有 WSL interop 的主機。這兩項都在 SPEC 授權的 12 個檔案
之外，是另一個 scope，本輪不做。

## Honest notes

- **E1（執行條件一）**：入口必須在 HEAD 的乾淨 detached worktree 內跑。來源根目錄
  有未追蹤的 `CLAUDE.local.md`（`.gitignore` 自 `2bd80e6` 起忽略它）時，`.chezmoiignore`
  沒有排除它，L3 的 8 條 managed 清單斷言失敗。base ref 逐條相同。class 3。
- **E2（執行條件二）**：入口必須在 `/etc/os-release` 報 `ID=debian` 的 namespace 內跑。
  本機是 omarchy（`ID=omarchy`、`ID_LIKE=arch`），而 `tests/fixtures/os-linux.toml`
  與 `os-linux-arm64.toml` 只釘了 `distroOverride` 沒釘 `distroLikeOverride`，
  「linux」fixture 因此走 pacman 分支，12 條斷言失敗。base ref 逐條相同。class 3。
- **E3**：mutation 的 38/44 在 base ref 完全相同，存活清單 `diff` 為空。class 3。
- **H1**：R1／R2 不驗證核准原話的真偽、不驗證紀錄的加入時間與先後順序、不驗證核准
  與 SPEC 內容的綁定。封存前替缺的版本補一段格式完整的文字即可通過（實測放行）。
  SPEC §0 已把這一段列為「沒買到」。
- **H2**：`--check` 的 candidate 清單自此**不再蘊含「可封存」**。實測：一份 v2／只有
  v2 核准的 SPEC，`--check` 仍把它列為 candidate（rc 0），`archive()` 則以 R2 拒絕。
- **H3**：`tools/gate-intent.sh` 的 awk 解析器（約 100 行）在 repo 內沒有任何測試引用。
  不加 fixture 是 SPEC §1.4 的既有決定（跨解析器一致性 fixture 已被否決）。
  **更正**：本報告先前寫「該腳本的失效方向是 `unconfirmed` 仍 exit 0 的誠實降級」，
  這句被實測推翻。把 `gate-intent.sh:67-153` 的 awk 抽出來單獨跑：`LC_ALL=C` 下
  `- 2026-09-15 — approves v1版 — 「核准」` 使 awk 印出 `v1`，Python 得 `[]`；
  `gate-intent.sh:157-162` 會據此設 `recorded=yes`，配上 `status: approved` 就成為
  `intent=confirmed`。**那是 fail-open，不是誠實降級。** 原因是 awk 的
  `[[:alnum:]_.-]` 版號結尾守衛在 C locale 不涵蓋 CJK，Python 的 `\w` 涵蓋。
  不加 fixture 的決定仍然成立，但它現在只靠 §1.4 那一條腿；SPEC 已就地標註。
- **H4**：`spec-archive.py` 的 `CLASS_RE` 取一行裡**第一個** `class N`，所以一條 class 1
  的 squad 發現只要內文提到 `class 2`／`class 3`，就會被讀成該類而繞過
  「class-1 finding still open」的檢查。本輪實際踩到（`d86b3dd` 的計數因此錯了一條，
  於 `9205bd3` 更正）。這是 CLOSE 的 fail-open 洞，不屬於本 scope。
- **H5**：S10 的兩條 `forbid` 只擋兩句已知壞措辭的**逐字**復原，改寫措辭即可繞過；
  它們不證明三份文件語意一致。SPEC S10 已自述此限制。
- **H6**：`tools/gate-agent-instructions.py:4-9` 的說明已過期（宣稱 `tools/gate.sh`
  的 artifact 目錄與 manifest 寫死在 windows-support scope，該腳本現在接受 `--scope`）。
  不屬於本 scope。
- **H7**：`.chezmoitemplates/evidence-first-contract.md` 的合約版號標記與
  `docs/evidence-first.md` 的版本段是兩處手維護、沒有機械比對；且該標記是 Go template
  註解，渲染後在 `~/.claude/CLAUDE.md` 裡看不到。class 3。
- **H8**：SPEC §0「不保證減少核准請求次數」無法機械驗證。送審前的逐條掃描把規則段落
  52 條宣稱逐一對到指令或 scenario，只有這一條驗不了；依核准者裁決保留並就地標註。
- **H10**：`.gitignore` 進了變更集（`2bd80e6`，一行 `CLAUDE.local.md`），但它不在
  SPEC「授權修改的檔案（12 個）」之內，SPEC 全文也沒提到這個檔。commit 時間早於
  v1 核准。**不自行補進授權清單**：補進去要升版與再核准，而這一行與本次行為無關。
  交給核准者定價。
- **H11**：兩支解析器仍有一個已知不一致：紀錄本文中出現一行裸 `#` 時，Python 得
  `['v1']`、awk 得 `[]`。方向是 gate 比 CLOSE 嚴，不是 fail-open。未修，因為修它要
  動 awk 的章節邊界判定，超出本次授權。
- **H12**：SPEC v2「本版新授權什麼」第 3 項寫「補一條 `require`」，實作補了兩條
  （`require(archiver_skill, …)` 與 `require(archiver, …)`）。同一句給的理由是
  「維持成對釘法」，成對就是兩條，所以計數與理由本身不一致，實作跟了理由。
  淨增 4 條（90 → 94）：2 `forbid` ＋ 2 `require`，0 移除。記在這裡讓核准者知道
  實作比核准的字面多了一條。
- **H13**：`spec-archive.py` 讀 front matter 版號的 `SPEC_VERSION_RE` 用 `\b` 結尾，
  所以 `v1.2junk` → `v1`、`v1-rc1` → `v1`、`v1.` → `v1`。本次把**核准紀錄**的版號
  token 收成 `VERSION_END`，但沒收這一個；base ref 的同一個常數逐字相同。class 3。
- **H14**：`tools/gate.sh:218` 的 manifest 稽核不經 `run_layer`，所以它自己不會進
  `layers-ran`，也就無法稽核自己。class 3。
- **H15（憑據保存）**：Gate 表的數字出自入口的一次執行，產出落在暫存 detached
  worktree 的 `.gate/` 內。那個 worktree 在跑完後被移除，**`.gate/` 產出目錄因此
  不復存在**（`.gate/` 本來就被 git 忽略，不進版控）。存下來的只有該次執行的完整
  stdout；它落在本次作業的暫存目錄，同樣不是長期憑據。所以這份 Gate 表現在**無法
  從磁碟佐證，只能重跑**。
  緩和事實：before-archive cut 的 evidence-vs-git 透鏡在 `248c501` 的乾淨 detached
  worktree、同形 `bwrap` ＋ `ID=debian` 環境下獨立重跑，除 mutation 外逐項相符
  （`commit=248c501 worktree=clean`、intent 逐字、94、86、739/0/16、329）。
  這是重現，不是同一次。
- **H16**：`spec-archive.py` 不讀本報告的 `headline`。它檢查報告存在、已提交、
  `spec_version` 與 SPEC 相同，但 gate 是綠是紅它一概不看，所以「A failing gate
  blocks done」在 CLOSE 這一端原本只是散文。本輪因此寫了
  `.scratch/spec-version-bump/verification.md` 並填 `final_verdict: blocked`——
  那一欄是 `check_verdict`（`:254-270`）唯一會讀的東西，填了就讓 CLOSE 以 exit 1
  拒絕。沒有新增任何檢查，只是把既有的那一個接上。要解除封鎖必須動這個檔，
  而它在版控裡，改動留得下痕跡。CLOSE 自己不看 headline 這個洞仍然存在，
  不屬於本 scope。
- **H9**：本次為修正 after-spec squad 紀錄的六個 `status: fixed` 標記改寫過一次歷史
  （`5928595` → `63c0208`，其後 9 個 commit 重放）。`check_squad` 要求 after-spec 的
  最後一次 commit 早於核准 commit，另開新 commit 會弄破該條件。備份 ref
  `backup/pre-marker-rebase`；樹的差異只有那六行。
