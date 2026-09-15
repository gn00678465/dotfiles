# Evidence Report — spec-version-bump (Tier 2)

- `headline`: BLOCKED at Mutation（38/44；六個存活的 mutant 全部依賴本機不存在的
  `pwsh.exe`，base ref 逐一相同。後四層 NOT REACHED）
- `command`: `evidence`
- `contract`: applied（`~/.claude/CLAUDE.md` 的 evidence-first 契約 v0.8，未被本 repo 覆寫）
- `scope`: spec-version-bump
- `change_set`: `9a2e879`...`4110034`
- `base`: `9a2e879`
- `report_language`: zh-TW
- `intent_status`: confirmed
- `intent_source`: 已提交的 SPEC `specs/spec-version-bump/SPEC.md`（`spec_version: v2`、`status: approved`、`tier: 2`；§Approval 記錄 v1 v2；首次進入歷史 `5d7409a`，最後一次改動 `cde8508 docs(spec-version-bump): SPEC v2 核准`）
- `ordering`: tests-first（`2b6226a` RED → `4e1a8b5` GREEN；`085726d` RED → `58ab021` GREEN；`f4308d8` 是兩條 GREEN-guard，自述非 RED）
- `git_facts`: complete
- `source_state`: `41100345668cda54992786ec08f5f60827fc126c`（`tools/gate-source-state.sh`，執行前後各驗一次，兩次相同）
- `source_state_exclusions`: `.gate/`（唯一的白名單；驗證腳本本身已進版控）
- `toolchain`: chezmoi v2.72.1 / git 2.55.0 / zsh 5.9.2 / Python 3.13.15 /
  `/bin/sh` → bash；**pwsh: ABSENT**（`versions.txt` 逐字）
- `entry_point`:
  `bwrap --dev-bind / / --ro-bind <ID=debian 的 os-release> /etc/os-release --chdir <HEAD 的乾淨 detached worktree> sh tools/gate.sh --scope spec-version-bump`
- `reproducibility`: degraded —— 入口需要兩個環境前提才跑得動，兩者都不是本次變更
  造成的，見 Honest notes 的 E1、E2。在裸主機上直接跑 `tools/gate.sh` 會更早停在
  suite 層。
- `changed_unit_command`: `git diff 9a2e879..4110034 --name-only`
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
| `spec-archive.py::approved_versions`／`APPROVAL_LIST_RE`／`APPROVAL_SECTION_HEAD_RE` | `::S3,S3b,S4,S6` | pass |
| `spec-archive.py::VERSION_END`（版號 token 結尾） | `::S4`（`approves v3junk` 誘餌） | pass |
| `spec-archive.py::_valid_date` | `::S4`（`2026-13-45` 誘餌） | pass |
| `spec-archive.py::_without_noise`（兩種圍欄、HTML 註解） | `::S4`（``` ／`~~~` ／註解三個誘餌） | pass |
| `spec-archive.py::approval_section`（多章節 exit 2） | `::S11` | pass |
| `spec-archive.py` 檔頭拒絕清單、`_without_noise` docstring | — （說明文字） | n-a |
| `gate-intent.sh` 的 awk 解析器 | — 無測試；見 Honest notes H3 | unverified |
| `gate.sh`：manifest 加 `spec-archive-tests` 層 | `gate-manifest-audit.sh`（本輪未執行，NOT REACHED） | unverified |
| `check_agent_doc_invariants.py`：2 條 `forbid`、2 條 `require` | 自身 exit code；四條各自移除字面後逐一轉紅 | pass |
| `dot_agents/workflows/evidence-first.md`、`templates/spec.md`、`evidence-squad/SKILL.md`、`docs/evidence-first.md`、`evidence-first-contract.md`、`spec-archive/SKILL.md`、`AGENTS.md` | `check_agent_doc_invariants.py` 的 94 條（只涵蓋字面，不涵蓋語意） | pass |
| `specs/spec-version-bump/SPEC.md`、2 份 squad 紀錄、`.gitignore` | — （紀錄與流程產物） | n-a |

## Stated claim → Test

| Claim | Test | Status |
|---|---|---|
| R1：目前版號沒有結構完整的紀錄 → exit 1 | `::S1,S2,S4,S5,S9b` | pass |
| R2：整數 `vN` 缺 v1…vN 任一 → exit 1 | `::S7,S8` | pass |
| 判定順序先 R1 後 R2 | 臨時 repo：v3＋只有 v2 → `no complete approval record for v3` | pass |
| 非正整數版不執行 R2 | `::S9a`（v0.2 ＋自己那筆 → exit 0） | pass |
| §2 的十條解析規則 | `::S3,S3b,S4,S6,S11`；8 個 mutant 逐一轉紅 | pass |
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
| S10：擋住兩句已知壞措辭的復原 | `check_agent_doc_invariants.py` 兩條 `forbid`，各自轉紅 | pass |
| 「不保證減少核准請求次數」 | 無法機械驗證（SPEC §0 已就地標註） | unverified |

## RED reconstruction

| Test | Result at base | Note |
|---|---|---|
| S1,S2,S3,S4,S5,S7,S8,S9b（8 個拒絕案例 × 5 斷言） | failed（40 of 79） | 在 `f3f6b2d` 的抽出樹上以 base 的 `archive()` 跑，逐一 `got rc 0` |
| S6, S9a | passed | GREEN-guard：base 的 `archive()` 根本不解析核准章節 |
| S4 新增的六個誘餌 | failed（1 of 80） | 對 `5bea393` 的實作跑，誘餌被當成 v3 紀錄，R1 放行後死在 R2 |
| S3b（`v1.2` 正向控制） | failed | 標題版號截斷 mutant → 轉紅；未突變時綠 |
| S11、CRLF guard | passed | 兩條都是 GREEN-guard，自述非 RED；非空洞性見 Negative controls |
| S10 第二條 `forbid` | failed | 本輪補觀察：把 `bump the version, set` 放回 workflow → rc 1 |

## Gate (final fresh run)

`4110034` 的一次完整執行。

| Layer | Command | Threshold | Result |
|---|---|---|---|
| versions | `tools/gate-versions.sh` | 逐字記錄 | chezmoi v2.72.1 / git 2.55.0 / Python 3.13.15 / **pwsh ABSENT** |
| source-state-before | `tools/gate-source-state.sh` | 工作樹乾淨 | `commit=4110034 worktree=clean` |
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

六個存活的 mutant：`windows-nvim-marker`、`windows-nvim-data-backup`、
`loader-idempotency`、`loader-line-content`、`backup-timestamp-fallback-windows`、
`neovim-skip-aborts-apply`。六個都只由 L7 的 Windows 分支證偽，而 L7 因
`command -v pwsh.exe` 找不到而 skip。**在 base ref `9a2e879` 上以同一個指令跑，
結果是同樣的 38/44、同樣這六個，存活清單 `diff` 為空。** 這一層的失敗與本次變更
無關，但它仍是失敗：本報告的 headline 因此是 BLOCKED，後四層是 NOT REACHED。

## Negative controls

- `check_approval` —— 8 個手工 mutant 各自單獨套用（放寬版號 token 結尾、拿掉日期
  驗證、拿掉兩種圍欄剝除、拿掉 HTML 註解剝除、接受 `decision: confirmed`、不比對
  `version bound`、截斷標題版號），**8/8 讓 `spec_archive_test.py` 轉紅**。
- `approval_section` 的結構歧義檢查 —— 拿掉 `len(heads) > 1` 的 `die` → S11 的 5 條
  斷言轉紅。
- CRLF guard —— 把 `spec.read_text()` 換成 `read_bytes().decode()` → 該斷言轉紅。
- 四條 doc invariant（2 `forbid` ＋ 2 `require`）—— 各自移除其字面後逐一轉紅。
- 正整數限制的反向控制 —— 對 `check_approval` 加上「目前版號必須是正整數」後
  39 個斷言轉紅，證明 Must NOT 那一條有守住。
- 兩支解析器的集合比對 —— `spec-archive.py` 與 `gate-intent.sh` 的 awk 對 git 裡
  5 份真實 SPEC ＋ 27 個對抗性輸入得到同一個集合，0 不一致。（此為診斷量測，
  不是 gate 的一層，也沒有進 repo。）

## Layers not run as specified

- **UNAVAILABLE**：L4／L7／L8 的 PowerShell 部分 —— 本機沒有 `pwsh` 也沒有
  `pwsh.exe`（WSL interop 不存在），16 個斷言 skip。沒有任何東西代跑。
- **DEPENDENCY UNMET**：mutation —— 它跑了，但六個 mutant 的唯一證偽者 L7 是
  UNAVAILABLE。這一層的 38/44 因此不能解讀成「suite 對 Windows 腳本的防護力」，
  只能解讀成「在沒有 pwsh.exe 的主機上可測到的部分全部殺掉」。
- **NOT REACHED**：supply-chain、pacman-ids、changed-lines、source-state-after ——
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
mutation 的分數也帶著同一個洞。要補只能換一台有 WSL interop 的主機重跑入口。

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
  不加 fixture 是 SPEC §1.4 的既有決定（跨解析器一致性 fixture 已被否決），且該腳本
  的失效方向是 `unconfirmed` 仍 exit 0 的誠實降級。本輪以一次性比對確認兩支解析器對
  5 份真實 SPEC ＋27 個對抗性輸入得到同一個集合；比對腳本沒有進 repo。
  已知差異面：awk 的 `[[:alnum:]_.-]` 在 C locale 不涵蓋 CJK 後綴，Python 的 `\w` 涵蓋。
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
- **H9**：本次為修正 after-spec squad 紀錄的六個 `status: fixed` 標記改寫過一次歷史
  （`5928595` → `63c0208`，其後 9 個 commit 重放）。`check_squad` 要求 after-spec 的
  最後一次 commit 早於核准 commit，另開新 commit 會弄破該條件。備份 ref
  `backup/pre-marker-rebase`；樹的差異只有那六行。
