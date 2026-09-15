# SPEC — SPEC 核准紀錄的機械化檢查 (Tier 2)

- `spec_version`: v2
- `status`: revised-pending-approval
- `tier`: 2
- `scope`: spec-version-bump
- `base_ref`: `9a2e879`（`origin/main`，PR #22 合併點）
- `contract`: `~/.claude/CLAUDE.md` 的 evidence-first 契約 **v0.8**，未被本 repo 覆寫
- `governed_by`: 本 SPEC 自身依 **舊版號規則**（合約 v0.8）管理。它定義的新規則自本
  SPEC 封存後生效。Phase 6 封存時新檢查已上線，本 SPEC 必須通過自己定義的檢查。

Tier 2 的理由：不涉及金流、認證、資料遺失、併發或公開 API。兩條新增拒絕都排在
`spec-archive.py` 任何寫檔、`git mv` 與 commit **之前**，不新增資料遺失風險。

## 0. 這次買到什麼，沒買到什麼

核准者請先讀這一節。

**買到**：封存時機械檢查核准紀錄的**完整性**與**連續性**。

**沒買到**：
- 不驗證核准原話是否真的來自使用者。
- 不驗證升版當下是否合法——「什麼時候才可以開下一版」仍然只由散文規範。
- 不驗證核准紀錄的加入時間或先後順序。封存前補記的核准與即時核准無法區分。
- 不保證減少核准請求次數。
- R2 只對正整數版號執行，所以把版號寫成 `v01` 或 `v1.2` 就完全跳過連續性。
  這是 §2 正整數判定式的直接後果，記在這裡是因為它是一條可用的繞道。

因此：**原始事件（v3 待核准時被 v4 取代）若在封存前替 v3 補一段格式完整的核准
文字，本檢查會放行。** 這是已知且刻意的界線，不是疏漏。本檢查擋的是「缺紀錄」，
不是「假紀錄」。

## 1. 依據

三個來源要分開看，不可混為一談。

### 1.1 兩份 skill-doctor 報告觀察到的問題

evidence-first 的 SPEC 版號在核准後暴衝：一份 SPEC 3 小時內從 v1 走到 v6，只取得
4 次核准。兩份報告各自指出一個直接依據，**兩者並列，不是單一成因**：

- `dot_agents/skills/evidence-squad/SKILL.md` 的 **Finding classes** class 2 條目明文
  "the version is bumped"。同一條規則在
  `dot_agents/workflows/evidence-first.md` 的 **Revisions** 條目另有一份
  （"A revision invalidates prior approval: bump the version"）。
- `dot_agents/workflows/templates/spec.md` 的 `spec_version` 註解寫
  "bump on every content change"。開檔的 agent 讀的是這則註解。

兩份報告的 suggestions **全部是散文修改，都沒有提議改 `spec-archive.py`**。

### 1.2 repo 裡已經存在的漏洞

`tests/spec_archive_test.py` 的 `quux` fixture 是 `status: approved` ＋
空白 `## Approval`，斷言 exit 0 封存成功。缺口被測試釘成預期行為。

`tools/gate-intent.sh` 的 Approval 集合抽取段已經在做「目前版本有沒有核准紀錄」的判斷，只是不擋
（檔頭的退出碼契約明寫 unconfirmed 也 exit 0）。偵測早已存在，缺的是阻斷。

### 1.3 為回應「能機械化就要機械化」而新增的設計

連續性檢查（§3 的 R2）**不是兩份報告的建議**，是為回應使用者「只靠散文約束 LLM
沒有用」這項追加約束而新增。它的正當性來自三點，不來自報告：

1. 已選定的版號規則能推出這項必要條件：v1 是第一次核准；核准 vN 後修訂開 vN+1；
   待審期間沿用、退回不升版；CLOSE 要求目前版本已核准。因此合法走到已核准 vN 的
   SPEC，必然累積 v1…vN 的核准紀錄。
2. 它能拒絕明確的缺號輸入。
3. 不涵蓋事項已在 §0 揭露。

### 1.4 已否決的做法與理由

- **以 `git log --follow` 重建版號歷史再比對核准**：實測誤擊。
  `specs/archive/archlinux-support/SPEC.md:267` 的 v1 是明載的待決草稿，不該有核准；
  `global-agent-instructions` 同樣流程只因未 commit 中間草稿而通過。且 squash、
  cherry-pick、rebase 均可改變判決。
- **整份 metadata 改 frontmatter（YAML 或 TOML）**：`spec-archive.py` 的 `check_squad()` 以
  `git log -S'`status`: approved'` 搜尋散文字面字串找核准 commit；搬移格式會使它
  在 Tier 2+ 直接 exit 2（Tier 1 因該函式的早退而不執行）。
- **共用驗證模組**：`tools/gate-intent.sh` 在 repo 內，`spec-archive.py` 經 chezmoi
  安裝到 `~/.agents/skills/` 並跨 repo 執行，共用模組沒有合適的安裝位置。
- **跨解析器一致性 fixture（要求 gate 與 CLOSE 判決相等）**：兩者回答不同問題。
  gate 的 `confirmed` 答「目前版本有核准」，CLOSE 答「可以封存」。目前 v2、有完整
  v2 核准但缺 v1 時，gate 應 confirmed 而 CLOSE 應拒絕，這不是矛盾。強迫一致會把
  新連續性政策套到 gate 仍須讀取的舊封存 SPEC。
- **`vN.1`／`vN.2` 小數子版號**（另一份報告的核心機制）：與既有 `v0.N` 草稿慣例
  衝突，且「請求再核准當下才取整數」會讓被退回的版本也耗掉一個整數。選「整數沿用」。
- **「補記的核准須在 Revisions 標記 backfilled」**：仍要求 agent 自行承認，程式不
  檢查；且分不出「確實核准過、事後補登」與「從未核准、為過檢查而編造」。
- **「送審必須記入 commit」**：只驗 SHA 存在收益不足，真正驗證要處理核准綁定哪份
  內容、哪些差異可接受、rebase 後怎麼算。
- **「送審前先完成已知且屬於本次 SPEC 的審查回合」**：「已知」只在 agent 腦裡，
  無法驗證。

### 1.5 四份已封存 SPEC 對 R2 的實測

依 §2 的解析規則量測：`windows-support`（目前 v7，紀錄 v1–v7）通過；
`arch-family-support`（v1/v1）通過；`global-agent-instructions`（v2，僅 v2）與
`archlinux-support`（v2，僅 v2）不通過——兩者為舊編號規則的產物，已封存，
`archive()` 與 `--check` 都不會再讀它們。除本 SPEC 外，`specs/` 底下沒有其他
作用中的 SPEC；本 SPEC 於 `status` 轉 `approved` 後會被 `--check` 列為 candidate。

## 2. 核准紀錄的解析規則

R1 與 R2 共用這一組規則。規則不明確，scenario 就寫不出 fixture。

**章節定位**：標題列符合 `^##+\s*(?:\d+\.\s*)?Approval\b` 者為核准章節。
`## Approval` 與 `## 8. Approval record` 都成立。不得用「包含 Approval」的寬鬆
比對。出現多個核准章節：exit 2（結構歧義）。

**章節邊界**：自該標題起，到下一個「同級或更高」標題為止，層級以核准標題自身
為準。`## Approval` 的章節內 `###` 屬於章節內部；`### Approval` 的章節在下一個
`###` 就結束，因此裝不下任何分節式紀錄。兩種讀法只在後者分岔，寫下來以免再猜。

**不算紀錄的內容**：圍欄程式碼區塊內的文字、HTML 註解內的文字、其他章節
（含 `## Revisions`）內的文字。

**清單式紀錄**，一行一筆，必須同時具備：
- 日期，`YYYY-MM-DD`，且為有效曆日；
- 字面 `approves`；
- 完整版號 token，其後必須是欄位分隔符；
- 非空的引號原話，與版號同一行。引號形式接受 `「」` 與 ASCII 雙引號；
  blockquote `>` 只在分節式成立——清單式是一行一筆，`>` 在同一行會多出一個
  誤判面（`-> merged` 這種字串會被當成原話）。

**分節式紀錄**，以 `### <完整版號> — <日期>` 起始，必須同時具備：
- `approval: confirmed`（`decision: confirmed` 不算）；
- `version bound` 與標題版號完整相等；
- `date` 與標題日期相同；
- 其下有非空的逐字引文：blockquote `>` 或 `「」`／ASCII 雙引號皆可。

**同版多筆**：任一筆完整即滿足。`specs/archive/windows-support/SPEC.md:379` 的
`### v5 的兩項選擇 — 2026-09-03` 帶 `decision: confirmed`，排在真正的
`### v5 — 2026-09-03`（同檔 :403）之前，不得因此拒絕該檔。

**順序**：紀錄解析成集合，排列順序不影響判定。`windows-support` 的實際順序是
v1、v7、v6、v5決策、v5、v4、v3、v2。

**版號比對**：完整 token 比對。`v1.2` 不得讀成 `v1`；`v0.10` 不得與 `v0.1` 相符。

**正整數判定式**：`^v[1-9][0-9]*$`。`v0`、`v01`、`v0.2` 皆不是正整數版。

**`approval: not obtained`**：不視為核准。無人模式的 SPEC 其 `status` 仍為 `draft`，
於 `archive()` 既有的 status 檢查即被拒，不會進入本層。

## 3. 拒絕規則

**R1（完整性）**：目前 `spec_version` 沒有一筆依 §2 解析得出的完整核准紀錄 → exit 1。
不分 tier。核准章節完全不存在 → exit 1（與空章節同路徑）。

**R2（連續性）**：目前版號為正整數 `vN` 時，核准集合必須含 v1…vN 全部，起點一律
v1 → 缺任一版 exit 1。非正整數版號不執行 R2，只受 R1 約束——`v0.x` 的 SPEC 只要
有自己那一筆完整紀錄就能封存，S9(a) 是它的正向控制。

**判定順序**：先 R1，後 R2。兩者同時成立時訊息指向 R1。

**插入點**：`spec-archive.py` 的 `archive()` 中，`TIER_RE` 解析之後、`check_verdict()`
呼叫之前。這個位置使 `corge`、`garply`、`grault` 第一段先被 evidence 版號
不符拒絕，`plugh` 先被缺 tier 拒絕，四者的既有斷言不受影響。

## Scenarios

`<repo>` 指測試建立的臨時 git repo。除被測條件外，每個 fixture 都有乾淨且已提交的
來源、版號相符的 evidence，以及必要的 tier 與 verdict 資料。每個拒絕案例除退出碼與
stderr 片段外，另斷言 **HEAD 未變、SPEC 內容未變、來源目錄仍在、`specs/archive/<scope>/`
未建立**。

- **S1 只有樣板沒有紀錄**：目前 v3、`status: approved`，核准章節內容直接取
  `dot_agents/workflows/templates/spec.md` 的 `## Approval` 一節原文（說明散文 ＋
  佔位項目 ＋ HTML 註解行）→ exit 1，stderr 指出目前版本 v3 缺核准紀錄。
- **S2 只有舊版核准**：目前 v3，核准章節只有一筆完整的 v2 清單式紀錄 → exit 1，
  stderr 指出缺 v3。
- **S3 版號前綴不得截斷**：目前 v1，核准章節只有一筆完整的
  `### v1.2 — 2026-09-15` 分節式紀錄 → exit 1。防禦對象是被否決的 `vN.1`／`vN.2`
  方案（§1.4）；現行規則不產生這種版號，此案例為防止該方案日後被重新引入。
- **S4 分節式缺原話，同節另帶誘餌集合**：目前 v3，分節式紀錄有
  `### v3 — 2026-09-15`、`approval: confirmed`、`date:`，但無非空逐字引文；
  同一節另有七個都不該算數的東西，釘住 §2 的六條規則——``` 圍欄內與 `~~~` 圍欄內
  的完整紀錄（圍欄）、HTML 註解內的（註解）、`decision: confirmed` 的、
  `version bound` 與標題不符的、日期不是有效曆日的、版號 token 帶後綴的
  → exit 1。任一個被算成紀錄，這個 fixture 就會通過 R1 而死在 R2，斷言的
  stderr 因此轉紅。誘餌的順序有意義：`###` 紀錄的本文延伸到下一個標題，帶引號的
  清單行放在上面會把原話送給那筆「必須沒有原話」的紀錄。
- **S5 核准不得取自章節外**：目前 v3，核准章節只有樣板，但 `## Revisions` 底下有
  一筆格式完整的 v3 核准文字 → exit 1。
- **S6 分節式與帶數字標題的成功路徑**（GREEN-guard，**非 RED**）：目前 v3，章節
  標題為 `## 8. Approval record`，內含 v1、v2、v3 三筆分節式紀錄且順序為 v1、v3、
  v2，另有一筆 `### v3 的兩項選擇` 帶 `decision: confirmed` → exit 0，stdout 含
  `archived`。此案例在 base ref 即為綠（base ref 的 `archive()` 不解析核准章節），
  故不列入 RED 重建表。實測它只釘得住「帶數字標題」一條：放寬另外三條之後 80 個
  斷言仍然全綠。非遞增順序、同版多筆與 decision 誘餌改由 S4 的誘餌集合承載。
- **S7 連續性缺中間版**：目前 v4，核准集合為 v1、v2、v4 → exit 1，stderr 指出缺 v3。
- **S8 連續性起點為 v1**：目前 v2，核准集合只有 v2 → exit 1，stderr 指出缺 v1。
- **S9 小數版號的兩側**：目前 v0.2、`status: approved`、evidence 版號相符——
  (a) 核准章節有一筆完整的 v0.2 紀錄 → exit 0（證明未新增正整數限制，R2 不適用）；
  (b) 核准章節只有樣板 → exit 1（R1 適用於所有版號）。
- **S10 擋住已知的壞措辭復原**：`tests/check_agent_doc_invariants.py <root>` 在
  `dot_agents/skills/evidence-squad/SKILL.md` 含 `the version is bumped`、或
  `dot_agents/workflows/evidence-first.md` 含 `bump the version, set` 時 exit 1。此檢查**只宣稱擋住這兩句已知
  壞措辭的復原**，不宣稱證明三份文件語意一致；改寫措辭可繞過，此限制寫入 Honest
  notes。RED 以 `python3 tests/check_agent_doc_invariants.py <base-ref 工作樹>`
  人工觀察。
- **S11 兩個核准章節無法評估**：目前 v1，SPEC 內有兩個 `## Approval` 標題 →
  exit 2，stderr 含 `more than one Approval section`。這是本次唯一新增的 rc 2
  路徑；沒有它，結構歧義這條規則被刪掉不會有任何案例轉紅。

## Must NOT

- Must NOT 驗證核准原話是否真的來自使用者。
- Must NOT 驗證核准紀錄的加入時間或先後順序。
- Must NOT 驗證核准與 SPEC 內容的綁定（`reviewed_commit` 或雜湊）。
- Must NOT 讀取 git 歷史來判定版號是否被浪費。
- Must NOT 新增「目前版號必須是正整數」的拒絕條件。S9(a) 是它的正向控制。
- Must NOT 把 `approval: not obtained` 視為核准。
- Must NOT 改動 `spec-archive.py --check` 的行為。其後果是 `--check` 的 candidate
  清單自此不再蘊含「可封存」，寫入 Honest notes。
- Must NOT 把 R2 的連續性條件搬進 `tools/gate-intent.sh`，也不得要求 gate 與 CLOSE
  的判決相等。gate 保留 unconfirmed 仍 exit 0 的既有契約。
- Must NOT 在任何拒絕路徑上修改檔案、搬移目錄或 commit。
- Must NOT 改動 `specs/archive/` 底下任何已封存 SPEC 的內容。
- Must NOT 變更 SPEC 的 metadata 儲存格式。
- Must NOT 使任何既有的 doc invariant 失效，或改變 `tests/spec_archive_test.py`
  既有案例的退出碼與 stderr 斷言。補核准紀錄以維持原斷言不算改變。
- Must NOT 新增任何第三方相依。

## Setup plan

核准本 SPEC 即一次授權以下全部內容。

- **要安裝的工具**：無。
- **Git 隔離**：沿用現有 worktree `fix-spec-version-bump`。checkpoint commit：
  RED 一次、GREEN 一次、文件一次。
- **gate 入口與它拉進的層腳本**（Tier 2 = 每一個 always-on 層；路徑逐一確認存在，
  非猜測）：入口 `tools/gate.sh`；層腳本 `tools/gate-intent.sh`、
  `tests/check_agent_doc_invariants.py`、`tests/run.sh`、`tools/gate-properties.py`、
  `tools/gate-mutants.py`、`tools/gate-supply-chain.py`、`tools/gate-pacman-ids.sh`、
  `tools/gate-changed-lines.py`。全部已存在，本次不新增層腳本；唯一的變更是在
  `tools/gate.sh` 的 manifest 加一層跑 `tests/spec_archive_test.py`。
- **gate 產出**：`.gate/spec-version-bump/`（git 已忽略）。evidence 於
  `.scratch/spec-version-bump/evidence.md`，squad 紀錄於
  `.scratch/spec-version-bump/squad/<cut>.md`。
- **新增相依**：無。全部使用 Python 標準函式庫。
- **授權修改的檔案（12 個）**：v2 新增最後兩個，理由見 Revisions。
  - `dot_agents/skills/spec-archive/scripts/spec-archive.py` — §2 解析函式、R1、R2、
    檔頭拒絕清單說明。v2 另加：分節式標題的行尾容許 `\r`（CRLF 的 SPEC.md 目前會
    整批漏掉分節式紀錄；本腳本經 chezmoi 跨 repo 執行，而這個 repo 家族含 native
    Windows）。
  - `tests/spec_archive_test.py` — S1–S11 案例、核准 fixture 輔助函式、**`expect()`
    的擴充或新增 `expect_refused()`** 以承載四項額外斷言。既有 fixture 補核准紀錄，
    使其繼續測到原本的拒絕理由：`quux`（v3）補 v1–v3；`foo`（v2，建立時為 draft，
    其後翻為 approved）補 **v1 與 v2 兩筆**；`fred`（v1，同樣後翻）補 v1；
    `waldo`（v1）補 v1；`grault`（v0.2）補一筆完整 v0.2 紀錄，維持其最後一段的 exit 0。
    v2 另加：S4 的誘餌集合、S3 的正向控制、`TEMPLATE_APPROVAL` 改為從
    `templates/spec.md` 讀出、S11。
  - `tests/check_agent_doc_invariants.py` — `evidence-squad/SKILL.md` 的檔案句柄、
    兩條 `forbid`（涵蓋 `SKILL.md:43` 與 `evidence-first.md:66` 兩份壞措辭）。
    v2 另加：一條 `require`，對應 `spec-archive/SKILL.md` 新增的拒絕條目。
  - `tools/gate-intent.sh` — 完整解析版號（消除其版號截斷註解自述的 `### v1.2` 截斷）、
    只把依 §2 結構完整的紀錄列入集合。**不改其 unconfirmed 仍 exit 0 的契約。**
  - `tools/gate.sh` — manifest 加 `spec-archive-tests`，以 `run_layer`
    執行 `python3 tests/spec_archive_test.py`。
  - `dot_agents/workflows/evidence-first.md` — **Versioning** 條目改為核准基準；
    **Revisions** 條目改為「開下一個待審版並撤回核准；待審期間的修改與退回均沿用
    該版號」；刪 **Exploration** 段尾的 "Bump the spec version once at the end"；
    **Squad** 段涵蓋整數待審修訂；**If the spec is rejected** 條目改為沿用同版號。
  - `dot_agents/workflows/templates/spec.md` — `spec_version` 註解、`status` 註解、
    `## Approval` 一節的佔位行（改為不會被誤認為紀錄的形式）。
  - `dot_agents/skills/evidence-squad/SKILL.md` — point-cut 表的 **after spec** 列、
    **Finding classes** 的 class 2 改為引用工作流程的 Versioning 規則。
  - `.chezmoitemplates/evidence-first-contract.md` — 第 1 行標記 v0.8 → v0.9。
  - `dot_agents/skills/spec-archive/SKILL.md`（v2 新增）— 「Refuses」清單補上 R1、
    R2 與新的 rc 2；`tests/check_agent_doc_invariants.py` 補一條 `require`，維持
    該 repo 既有的「skill 說一次、script 說一次」成對釘法。
  - `AGENTS.md`（v2 新增）— `check_agent_doc_invariants.py` 的觸發條件補上
    `dot_agents/skills/evidence-squad/`。
  - `docs/evidence-first.md` — 「核准 SPEC」條目、Phase 1 表格列、機械檢查與自律的
    對照表、合約版本段，四處敘述同步。
- **不改**：`AGENTS.md`（既有觸發條件已涵蓋 `dot_agents/workflows/` 的修改）。

## Approval

Append-only。每一版一筆：核准原話逐字、日期、綁定的 `spec_version`。

- 2026-09-15 — approves v1 — 「核准 SPEC v1」

## Revisions

- 2026-09-15 — v0.1 草稿。依兩份 skill-doctor 報告與 8 輪 codex 獨立審查撰寫。
- 2026-09-15 — v0.2：折入 after-spec squad cut 的發現（`.scratch/spec-version-bump/squad/after-spec.md`，
  commit `98e6f8c`；6 class 1、26 class 2、5 class 3）與第 9 輪 codex 第二意見。
  主要變更：新增 §0（買到什麼／沒買到什麼）與 §2（解析規則，原草稿只寫判定未寫解析）；
  §1 拆成報告觀察／既有漏洞／為回應約束新增的設計三段；R1/R2 明寫判定順序與插入點；
  S6 標為 GREEN-guard 並改用真實的帶數字標題與非遞增順序；新增 S9 兩側案例取代原本
  單向翻掉 `grault` 的做法（保住唯一的小數版正向控制）；S10 改名為「擋住已知的壞措辭
  復原」並涵蓋 `evidence-first.md:66`；授權清單加入 `tools/gate-intent.sh` 與
  `tools/gate.sh`，不加 `AGENTS.md`。採納的四項決定與否決理由見 §1.4。
  同一版另跑 durability preflight 三項並折入其發現：(1) 從 `verification-gate` 解析
  Tier 2 實際拉進的八個層腳本並逐一確認存在（原草稿未列，且我起初猜錯三個檔名）；
  (2) 兩條寫成計數的 Must NOT（「90 條 invariant」「四份已封存 SPEC」）改寫為行為；
  (3) 所有指向本次會修改檔案的 `file:line` 改為符號名——本次變更自己就會移動那些行，
  行號必然過期。指向已封存 SPEC 的行號保留，因為 Must NOT 禁止改動它們。
  每個計數當場量測：doc invariants 90、spec_archive assertions 37、已封存 SPEC 4 份、
  gate manifest 13 層。
- 2026-09-15 — v1：內容與 v0.2 相同，依舊版號規則（合約 v0.8）在送到人面前的當下
  取整數版號。provenance：來自 v0.2，自 v0.2 起無內容變更。
- 2026-09-15 — v2 待審：折入 after-implement squad cut 的 class 2
  （`.scratch/spec-version-bump/squad/after-implement.md`，commit `d86b3dd`；
  四個透鏡，class 1 十二條、class 2 十一條、class 3 五條）。class 1 已全部在
  `085726d`／`58ab021`／`4f4e201`／`63c0208` 修掉，不需要新核准；本版承載的是
  十一條 class 2。provenance：來自 v1，v1 的核准內容沒有被推翻，是被補正與擴充。

  **本版改了什麼**（六項，全部是 v1 內文被實測證明寫錯或寫漏）：
  1. §0 補上 R2 的已知繞道：版號寫成 `v01` 或 `v1.2` 完全跳過連續性。
  2. §2 清單式的 blockquote `>` 子句移到分節式：`>` 只在分節式成立也只在分節式
     實作，清單式接受 `>` 會把 `-> merged` 這種字串當成原話。
  3. §2 章節邊界補一句：`### Approval` 的章節在下一個 `###` 就結束，裝不下分節式
     紀錄。兩種讀法只在這個標題上分岔。
  4. §3 刪掉「`v0.x` 的 SPEC 永遠無法封存」——該句與 S9(a)、Must NOT 以及實作行為
     三者矛盾，`s9a` 實測封存成功。
  5. S6 的宣稱縮到實測結果：它只釘得住「帶數字標題」一條，另外三條放寬後 80 個
     斷言仍全綠。那三條改由 S4 的誘餌集合承載。
  6. S4 改為誘餌集合，一個既有的 `expect_refused` 釘住 §2 的六條規則；新增 S11
     覆蓋本次唯一新增的 rc 2 路徑。

  **本版新授權什麼**（三項，核准即授權）：
  1. 授權檔案清單 10 → 12：加入 `dot_agents/skills/spec-archive/SKILL.md`
     （CLOSE 執行者實際讀的「Refuses」清單，唯獨缺本次新增的三條拒絕）與
     `AGENTS.md`（`check_agent_doc_invariants.py` 的觸發條件沒有列 evidence-squad，
     而新 invariant 讀的正是該 skill）。
  2. `spec-archive.py` 的分節式標題行尾容許 `\r`：CRLF 的 SPEC.md 目前會整批漏掉
     分節式紀錄，清單式照常。失效方向是誤拒，不是誤放。
  3. `check_agent_doc_invariants.py` 補一條 `require`，維持「skill 說一次、
     script 說一次」的成對釘法。

  **審完仍不做的三件**（記入 evidence report 的 Honest notes，不進本版）：
  `tools/gate-intent.sh` 的 awk 不加 fixture（§1.4 已否決跨解析器一致性 fixture，
  且該腳本失效方向是 `unconfirmed` 仍 exit 0 的誠實降級）；不改 `tests/fixtures/
  os-linux*.toml` 的 `distroLikeOverride` 缺口與 `.chezmoiignore` 的
  `CLAUDE.local.md` 缺口（都是 class 3，base ref 逐條相同）；不為了讓 mutation
  層轉綠而改 `tools/gate-mutants.py`（存活的六個 mutant 全針對本機沒有的
  `pwsh.exe`，base ref 同樣 38/44）。
