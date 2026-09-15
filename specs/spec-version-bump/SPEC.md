# SPEC — SPEC 版號規則與核准紀錄的機械化 (Tier 2)

- `spec_version`: v0.1
- `status`: draft
- `tier`: 2
- `scope`: spec-version-bump
- `base_ref`: `9a2e879`（`origin/main`，PR #22 合併點）
- `contract`: `~/.claude/CLAUDE.md` 的 evidence-first 契約 **v0.8**，未被本 repo 覆寫
- `governed_by`: 本 SPEC 自身依 **舊版號規則**（合約 v0.8）管理。它定義的新規則自本
  SPEC 封存後生效。Phase 6 封存時新檢查已上線，本 SPEC 必須通過自己定義的連續性檢查。
- `evidence`: 兩份 skill-doctor 報告（`report.json`、`analysis.md`）與 8 輪
  codex 獨立審查；關鍵量測見 §1。

Tier 2 的理由：不涉及金流、認證、資料遺失、併發或公開 API。兩條新增拒絕都排在
`spec-archive.py` 任何寫檔、`git mv` 與 commit **之前**，不新增資料遺失風險。

## 1. 依據

- **已證實的缺口**：`tests/spec_archive_test.py:192-202` 的 `quux` fixture 是
  `status: approved` ＋ **空白 `## Approval`**，斷言 exit 0 封存成功。缺口被測試
  釘成預期行為。
- **已證實的成因**：`dot_agents/skills/evidence-squad/SKILL.md:42-44` 的 class 2
  明文 "the version is bumped"。agent 照做，這是版號暴衝的直接依據，不是規則未被
  遵守。
- **散文不構成約束**：`docs/evidence-first.md:106`「要加約束，加在左欄——preflight
  目前全在右欄，沒有任何一項會擋住流程」。
- **已否決的做法**：以 `git log --follow` 重建版號歷史再比對核准。實測誤擊——
  `specs/archive/archlinux-support/SPEC.md:267` 的 v1 是明載的待決草稿，不該有核准；
  `global-agent-instructions` 同樣流程只因未 commit 中間草稿而通過。且 squash、
  cherry-pick、rebase 均可改變判決。
- **四份已封存 SPEC 對連續性檢查的實測**：`windows-support`（v7，紀錄 v1–v7）通過；
  `arch-family-support`（v1/v1）通過；`global-agent-instructions`（v2，僅 v2）與
  `archlinux-support`（v2，僅 v2）不通過——兩者為舊編號規則產物，已封存，
  `archive()` 與 `--check` 都不會再讀它們。`specs/` 底下目前沒有任何作用中的 SPEC。

## Scenarios

`<repo>` 指測試建立的臨時 git repo。除被測條件外，每個 fixture 都有乾淨且已提交的
來源、版號相符的 evidence、以及必要的 tier 與 verdict 資料。每個拒絕案例除退出碼
外，另斷言 **HEAD 未變、SPEC 內容未變、來源目錄仍在、`specs/archive/<scope>/` 未
建立**。

- **S1 空白核准**：SPEC 為 `spec_version: v3`、`status: approved`、`## Approval`
  章節為空 → `spec-archive.py v3scope` exit 1，stderr 指出目前版本 v3 缺核准紀錄。
- **S2 只有舊版核准**：目前 v3，`## Approval` 只有一筆完整的 v2 清單式紀錄 →
  exit 1，stderr 指出缺 v3。
- **S3 版號前綴不得截斷**：目前 v1，`## Approval` 只有一筆完整的
  `### v1.2 — 2026-09-15` 分節式紀錄 → exit 1。`v1.2` 不得被讀成 `v1`。
- **S4 分節式缺原話**：目前 v3，分節式紀錄有 `### v3 — 2026-09-15`、
  `- **approval: confirmed**`、`date:`，但沒有非空的逐字引文 → exit 1。
- **S5 核准不得取自 Revisions**：目前 v3，`## Approval` 為空，但 `## Revisions`
  底下有一筆格式完整的 v3 核准文字 → exit 1。
- **S6 分節式成功**：目前 v3，`## Approval` 為分節式且 v1、v2、v3 三筆齊全，各有
  `approval: confirmed`、`date:` 與非空逐字引文 → exit 0，stdout 含 `archived`。
- **S7 連續性缺中間版**：目前 v4，`## Approval` 有完整的 v1、v2、v4 → exit 1，
  stderr 指出缺 v3。
- **S8 連續性起點為 v1**：目前 v2，`## Approval` 只有一筆完整的 v2 → exit 1，
  stderr 指出缺 v1。
- **S9 文件不得各說各話**：`tests/check_agent_doc_invariants.py <root>` 在
  `dot_agents/skills/evidence-squad/SKILL.md` 含有字串 `the version is bumped` 時
  exit 1；在本 SPEC 定案的措辭下 exit 0。同樣地，`evidence-first.md` 或
  `templates/spec.md` 任一缺少 `approval baseline` 時 exit 1。

既有預期變更（非新增 scenario）：

- **grault**：`tests/spec_archive_test.py:265-270` 目前斷言 v0.2 的小數版與 evidence
  相符即可封存（exit 0）。改為 exit 1——它的 `## Approval` 為空，被 S1 的規則拒絕。
  既有「`v0.1`、`v0.2`、`v0.10` 不得互相混淆」的解析回歸測試全數保留。

## Must NOT

- Must NOT 驗證核准原話是否真的來自使用者。這一層只檢查紀錄存在且結構完整。
- Must NOT 驗證核准紀錄的加入時間或先後順序。目前 v4 而 v3 紀錄是事後補上的，
  仍會通過；這是明確不涵蓋的事項，須寫入 evidence 的 Honest notes。
- Must NOT 驗證核准與 SPEC 內容的綁定（`reviewed_commit` 或雜湊）。
- Must NOT 讀取 git 歷史來判定版號是否被浪費。
- Must NOT 新增「目前版號必須是正整數」的拒絕條件。目前版號為正整數 `vN` 時才執行
  連續性檢查；其他可完整解析的版號只受 S1 的規則約束。
- Must NOT 把 `approval: not obtained` 視為核准。
- Must NOT 改動 `spec-archive.py --check` 的行為或 `tools/gate-intent.sh`。
- Must NOT 在任何拒絕路徑上修改檔案、搬移目錄或 commit。
- Must NOT 遷移或改寫 `specs/archive/` 底下四份已封存的 SPEC。
- Must NOT 變更 SPEC 的 metadata 儲存格式（不引入 YAML 或 TOML frontmatter）。
  `spec-archive.py:168` 以 `git log -S'\`status\`: approved'` 搜尋散文字面字串，
  搬移格式會使它靜默失效。
- Must NOT 破壞既有的 90 條 doc invariant，或 `tests/spec_archive_test.py` 既有
  案例（`grault` 的一項預期變更除外）。
- Must NOT 新增任何第三方相依。

## Setup plan

核准本 SPEC 即一次授權以下全部內容。

- **要安裝的工具**：無。
- **Git 隔離**：沿用現有 worktree `fix-spec-version-bump`（branch 同名）。
  checkpoint commit 時機：SPEC 核准時、每個 GREEN 之後、散文變更之後。
- **gate 會產生的檔案**：`tools/gate.sh` 已存在；本 scope 的產出寫入
  `.gate/spec-version-bump/`（git 已忽略）。evidence 提交於
  `.scratch/spec-version-bump/evidence.md`，squad 紀錄於
  `.scratch/spec-version-bump/squad/<cut>.md`。
- **新增相依**：無。全部使用 Python 標準函式庫。
- **授權修改的檔案**（共 8 個）：
  - `dot_agents/skills/spec-archive/scripts/spec-archive.py` — 核准紀錄解析函式、
    兩條拒絕條件、檔頭拒絕清單說明（約 4 處）。
  - `tests/spec_archive_test.py` — S1–S8 案例、fixture 輔助函式、`quux` 補齊
    v1–v3、`foo`／`waldo`／`fred` 補上核准紀錄以維持原測試目的、`grault` 預期變更
    （約 8 處）。
  - `tests/check_agent_doc_invariants.py` — `evidence-squad/SKILL.md` 的檔案句柄
    1 行、2 條 `require`、1 條 `forbid`（共 4 行）。
  - `dot_agents/workflows/evidence-first.md` — 5 處：`:56` Versioning 改為核准
    基準、`:64` Revisions 改為開下一個待審版並沿用、`:109` 刪除 Exploration 的
    bump once at the end、`:114` Squad 涵蓋整數待審修訂、`:166` 退回沿用同版號。
  - `dot_agents/workflows/templates/spec.md` — 2 處：`:3` 版號註解、`:7` status 註解。
  - `dot_agents/skills/evidence-squad/SKILL.md` — 2 處：`:27` cut 表、`:42` class 2
    改為引用工作流程的 Versioning 規則。
  - `.chezmoitemplates/evidence-first-contract.md` — 1 處：第 1 行標記 v0.8 → v0.9。
  - `docs/evidence-first.md` — 4 處：`:34`、`:48`、`:101`、`:145`。

## Approval

Append-only。每一版一筆：核准原話逐字、日期、綁定的 `spec_version`。

<!-- 尚未送審 -->

## Revisions

- 2026-09-15 — v0.1 草稿。依兩份 skill-doctor 報告與 8 輪 codex 獨立審查撰寫。
  過程中被否決並已移除的方案：整份 metadata 改 frontmatter（`git log -S` 會靜默
  失效）、共用驗證模組（`tools/` 與 `~/.agents/` 兩處安裝位置無共同家）、
  git 歷史版號檢查（實測誤擊且可被 rebase 改變）、跨解析器一致性 fixture
  （攔不住本次故障）、送審 commit 要求（只驗 SHA 存在收益不足）、
  「送審前完成已知審查回合」（無法驗證）、「非契約修改保持核准」（anti-gaming 出口）。
