# squad — after-implement cut — spec-version-bump

- cut：after-implement（evidence-squad SKILL.md 的第二個 point-cut）
- 受檢狀態：`5bea393`（HEAD），base `9a2e879`，SPEC v1（`884b5fb` 核准）
- 透鏡四個，平行、唯讀、各自新脈絡，四項輸入相同（任務契約／SPEC／來源狀態／透鏡簡報），
  都沒有拿到 orchestrator 的對話：contract-vs-implementation、live-evidence、
  input-space-at-code-level、diff-hygiene-and-scope
- 這一輪 gate 的狀態：`BLOCKED at mutation`（見 evidence report）。依 SKILL 的字面，
  after-implement cut 排在「gate 全綠之後」；這一輪在 gate 被環境擋住的狀態下先跑，
  理由是擋住 gate 的是本機沒有 `pwsh.exe`（base ref 同樣 38/44），不是本次變更的缺陷，
  而 squad 的四個透鏡都不依賴那一層。這個偏離記在這裡與 evidence report。

## 裁決（orchestrator）

透鏡之間沒有互相矛盾的判斷，但同一條發現出現三種 class。裁決的準則寫在這裡，
因為它決定了要不要多耗一個整數版號：

- **只有一個正確動作、且動作落在 SPEC 已授權的檔案裡 → class 1**，本版修掉。
  包含「本次變更自己寫進去的錯誤敘述」：留著一句實測不成立的註解不是選項。
- **需要人做選擇（擴充授權檔案清單、或改動已核准的 SPEC 內文）→ class 2**，
  批次成一個 v2 待審修訂，一次送審。
- **不屬於本次變更 → class 3**，只記進 evidence report 的 Honest notes。

`spec-archive.py:105` 的版號守衛（F-A）四個透鏡裡有兩個給 class 1、一個沒看到。
採 class 1：SPEC §2:117 明寫「完整版號 token，其後必須是欄位分隔符」，實作只擋
數字與點，`approves v1junk` 讓 R2 的連續性可以用非版號字串湊滿——這是違反 SPEC
明寫規則，不是規格缺口。

## class 1 —— 違反 SPEC 明寫的規則或本次變更造成的缺陷，本版修正

- [HIGH] spec-archive.py::APPROVAL_LIST_RE — 版號 token 之後只擋 `[0-9.]`，`approves v1junk`／`v2-draft` 被截成合法版號，R2 的連續性可用非版號字串湊滿 — 端對端實測 `rc=0 archived=True`；SPEC §2:117 明寫「其後必須是欄位分隔符」 — class 1 — 收成 `(?![\w.-])`，`gate-intent.sh` 的 awk 同一個洞一起收 — status: fixed（`58ab021`）
- [HIGH] tests/spec_archive_test.py::TEMPLATE_APPROVAL — S1 的輸入是 base ref 範本的凍結複本，`585d2c2` 已把該節的佔位行整段包進 HTML 註解 — `lit == real_section` → False；SPEC S1 寫的是「直接取範本原文」；同檔 `real_evidence_header()` 對 evidence 範本已是讀真檔 — class 1 — 改為從 `templates/spec.md` 讀出 — status: fixed（`085726d`）
- [MED] spec-archive.py::APPROVAL_LIST_RE — 日期只比對形狀，`2026-13-45`、`2026-02-29` 都算核准；SPEC §2:115 明寫「且為有效曆日」 — 實測該日期可讓 v1 封存 — class 1 — `datetime.date.fromisoformat()` — status: fixed（`58ab021`）
- [MED] spec-archive.py::_without_noise — 只剝除 ``` 圍欄，`~~~` 也是 CommonMark 圍欄，§2:111 說圍欄內不算紀錄 — 實測 `~~~` 內的紀錄 `rc=0 archived=True` — class 1 — 兩種圍欄都剝且要求成對 — status: fixed（`58ab021`）
- [MED] spec-archive.py 檔頭 — SPEC Setup plan:229-231 授權並宣告要改「檔頭拒絕清單說明」，實際完全沒動（反向漏失）；rc 1 清單沒有 R1／R2，rc 2 清單沒有 `more than one Approval section` — `git diff` 第一個 hunk 起點是 `@@ -86,6 +86,88 @@` — class 1 — 補上 — status: fixed（`58ab021`）
- [MED] tests/check_agent_doc_invariants.py::forbid — 兩條 desc 宣稱語意性質（「class 2 不會下令升版」），而 SPEC S10:186 明寫此檢查「只擋這兩句已知壞措辭的復原」；且 desc 與它們守著的文件現行內容相反 — 使用者對 S10 的指示原話是「改名為擋住已知壞措辭復原」 — class 1 — desc 改成它實際證明的事 — status: fixed（`4f4e201`）
- [MED] docs/evidence-first.md — 同一份文件兩處列舉 `spec-archive` 的拒絕集合，這次只更新了機械擋住表，Phase 6 表格列仍是舊集合 — class 1 — 同步 — status: fixed（`4f4e201`）
- [MED] docs/evidence-first.md — 改寫時刪掉「SPEC 改過就回到 `revised-pending-approval`，要重新核准才能繼續實作」整句，該詞現在整份 docs 查不到 — `grep -n revised-pending-approval` 只剩範本與 workflow — class 1 — 那是核准閘門規則不是版號規則，補回 — status: fixed（`4f4e201`）
- [MED] dot_agents/workflows/evidence-first.md::Approval — 該段教 agent 寫「原話、日期、版本」，照抄寫出的紀錄 CLOSE 解析不到（清單式要字面 `approves`，分節式要 `approval: confirmed`） — 實測兩種照抄形狀皆被拒 — class 1 — 補一句指向範本的兩種形狀與關鍵字 — status: fixed（`4f4e201`）
- [LOW] dot_agents/workflows/evidence-first.md::Revisions — 首句「A revision invalidates prior approval」沒有「對已核准契約的修訂」這個限定，與同檔 Versioning 讀起來像兩條規則 — class 1 — 首句補上限定 — status: fixed（`4f4e201`）
- [LOW] tools/gate-intent.sh 新註解 — 宣稱兩種假陽性「都在 git 裡踩得到」，實測兩者都不成立：`global-agent-instructions:117` 的散文是 `approves <spec_version>`，沒有數字，舊式樣不命中；`### v5 的兩項選擇` 確實命中但被去重吃掉，五份真實 SPEC 的輸出改寫前後逐位元組相同 — class 1 — 改寫為實測行為 — status: fixed（`4f4e201`）
- [LOW] tools/gate.sh 新註解 — 宣稱 AGENTS.md 那條要求「沒有接進入口」，但 `tools/gate-agent-instructions.py:53` 的 manifest 早就有 `spec-archive-tests` — class 1 — 縮到 gate.sh 自己的 manifest — status: fixed（`4f4e201`）
- [HIGH] .scratch/spec-version-bump/squad/after-spec.md — 六筆 class 1 發現都沒有 `status: fixed`，`check_squad` 會在 CLOSE 退 1，本 scope 封存不了 — 兩個透鏡各自用 `spec-archive.py` 自己的 `FINDING_RE`/`CLASS_RE`/`FIXED_RE` 掃出 `class1 without status: fixed: 6`，其中一個另外建臨時 repo 跑到真的 `check_squad` 得 `FAIL: … class-1 finding still open` — class 1 — 補標記；`check_squad` 另要求 after-spec 的最後一次 commit 是核准 commit 的祖先，所以標記必須折進「當初修掉它們」的那個 commit（`63c0208`，SPEC v0.2），不能另開新 commit — status: fixed（`63c0208`，rebase；備份在 `backup/pre-marker-rebase`）

## class 2 —— SPEC 沒寫的行為或需要擴充授權，批次成 v2 一次送審

- [MED] dot_agents/skills/spec-archive/SKILL.md:39-54 — CLOSE 執行者讀的「Refuses」清單逐條列出每一種拒絕，唯獨缺本次新增的兩條 rc 1 與一條 rc 2；`docs/evidence-first.md` 與 workflow 都更新了，只有它沒有 — 三個透鏡各自獨立指出；`check_agent_doc_invariants.py:210-222` 對既有每一個 gate 都有「skill 說一次、script 說一次」的成對釘住，新 gate 兩邊皆無 — class 2 — SKILL.md 不在授權的 10 個檔案內
- [MED] AGENTS.md:39-41 — `check_agent_doc_invariants.py` 的觸發條件沒有列 `evidence-squad`，而新 invariant 讀的正是該 skill — SPEC:253「不改 AGENTS.md」的理由只涵蓋兩條 forbid 的其中一條 — class 2 — 補一個觸發來源
- [MED] specs/spec-version-bump/SPEC.md::S6 — S6 宣稱釘住 §2 的四條解析規則、「任一條寫錯即轉紅」，實測只有「帶數字標題」一條成立（其餘三條各自放寬後 80 個斷言全綠） — class 2 — 縮到它實際擋住的東西；六條規則現已由 S4 的誘餌釘住，S6 的敘述要跟著改
- [MED] specs/spec-version-bump/SPEC.md::§3 — 「其後果是 `v0.x` 的 SPEC 永遠無法封存——這是刻意的性質」與同一份 SPEC 的 S9(a)（v0.2 ＋完整紀錄 → exit 0）、Must NOT 以及實作行為直接矛盾 — `s9a` 實測封存成功 — class 2 — 刪掉或改寫該句
- [MED] specs/spec-version-bump/SPEC.md::§2 清單式 — 「引號形式接受 `「」`、ASCII 雙引號、以及 blockquote `>`」與同條的「一行一筆」互相牴觸，`>` 只在分節式成立也只在分節式實作 — 實測清單式帶 `>` 被拒 — class 2 — 把 `>` 子句移到分節式那一項（改 SPEC 文字，不改程式：清單式接受 `>` 會多出一個誤判面）
- [LOW] specs/spec-version-bump/SPEC.md::§0 — R2 只對正整數版執行，把版號寫成 `v01` 或 `v1.2` 就完全跳過連續性；§2/§3 確實這樣規定，但 §0 的「沒買到」清單沒有把它列為已知繞道 — 實測 `rc=0 archived=True` — class 2 — §0 補一句
- [LOW] specs/spec-version-bump/SPEC.md::§2 章節邊界 — 「到下一個 `##`（同級或更高）為止」與「`###` 屬於章節內部」在 `### Approval` 這個標題上分岔：實作會在第一個 `### vN` 就結束章節 — 實測該形狀被拒 — class 2 — §2 補一句釐清，不必改程式
- [LOW] spec-archive.py::APPROVAL_SECTION_HEAD_RE — 分節式標題以 `[ \t]*$` 收尾，`\r` 不在其中，CRLF 的 SPEC.md 會整批漏掉分節式紀錄（清單式照常）；此腳本經 chezmoi 跨 repo 執行，本 repo 的平台目標含 native Windows — 實測 CRLF fixture 清單式通過、分節式被拒 — class 2 — 一個字元 `[ \t\r]*$`；失效方向是誤拒（fail closed），不是誤放
- [LOW] tools/gate-intent.sh::awk — 約 90 行的第二支解析器，repo 內沒有任何測試引用它；commit 宣稱的對抗性輸入比對沒有進 repo — class 2 — 建議不新增 fixture：SPEC §1.4 已否決跨解析器一致性 fixture，且該腳本的失效方向是 `unconfirmed` 仍 exit 0（誠實降級），真正的閘門是 CLOSE 的 80 個斷言。比對數字寫進 evidence report
- [LOW] spec-archive.py::approval_section — 「出現多個核准章節 → exit 2」是本次唯一新增的 rc 2 路徑，已實作且可觸發，但沒有 scenario 也沒有斷言 — 實測 `rc=2`、訊息正確 — class 2 — 建議只記進 Honest notes

## class 3 —— 不屬於本次變更，只記進 Honest notes

- [MED] tests/fixtures/os-linux.toml、os-linux-arm64.toml — 兩個 fixture 釘了 `distroOverride = "debian"` 但沒有釘 `distroLikeOverride`，所以在 Arch 家族的渲染主機上 `$distroLike` 退回主機的 `ID_LIKE=arch`，「linux」fixture 會走 pacman 分支 — 本機 `/etc/os-release` 是 `ID=omarchy`、`ID_LIKE=arch`，裸主機上 suite 有 12 條斷言失敗，base ref `9a2e879` 逐條相同 — class 3
- [MED] .chezmoiignore — 沒有排除 `CLAUDE.local.md`（`.gitignore` 自 `2bd80e6` 起有），來源根目錄存在該檔時 L3 的八條 managed 清單斷言失敗 — class 3
- [MED] tools/gate-mutants.py 與本機環境 — 六個 mutant 全部針對 L7 的 Windows 分支，本機沒有 `pwsh.exe`（`versions.txt` 自己記著 `pwsh: ABSENT`），L7 skip，mutation 層停在 38/44；base ref 逐一相同（存活清單 `diff` 為空） — class 3
- [LOW] .chezmoitemplates/evidence-first-contract.md:1 與 docs/evidence-first.md — 合約版號寫在兩處、靠手維護、沒有機械比對；且第 1 行是 Go template 註解，渲染後 `~/.claude/CLAUDE.md` 裡看不到版號 — class 3
- [LOW] tests/check_agent_doc_invariants.py::forbid — `forbid` 是 fail-fast，第一條 `die` 之後第二條不執行；`585d2c2` 當時只觀察到第一條轉紅 — 本輪補觀察第二條（把 `bump the version, set` 放回 workflow → `FAIL: … rc=1`） — class 3 —寫進 evidence 的 RED 重建表

## 每個透鏡承認的不適用之處

- contract-vs-implementation：只比對 scenario 與斷言；散文正確性、三份文件的語意一致、
  新版號規則是否真的解決灌水，不在其範圍。手挑的 mutant 不是完整掃描。
- live-evidence：刻意不讀單元測試，所以 S1–S10 的 fixture 是否編碼了各該 scenario 沒有意見；
  沒跑 gate、沒重建 RED；樣本只有這棵樹的五份 SPEC，跨 repo 的語料看不到。
- input-space：只量「輸入字串 → 判定」；不碰 `check_squad`／`check_verdict`／`--check`，
  不判斷升版時機是否正當，不判斷兩條 forbid 是否足以擋改寫。
- diff-hygiene：沒有構造對抗性 fixture 驗 §2 解析器，沒有從 git 重建 S1–S9 的 RED，
  不評價 R2 這個設計本身，沒有兩份 skill-doctor 報告所以 §1.1 對報告的引述無法查證。
