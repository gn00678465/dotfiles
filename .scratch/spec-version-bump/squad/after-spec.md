# evidence-squad — after-spec cut — spec-version-bump

- 來源狀態：`5d7409a`（SPEC v0.1，base_ref `9a2e879`）
- Tier 2，四個 lens：scope、input space、repo reality、test mapping
- 四個 lens 各自只取得四項輸入（任務契約、SPEC、來源狀態、lens brief），未取得 orchestrator 的對話

## 裁決摘要（每個 lens 一句）

- **scope**：用「存檔那一刻的文件狀態」取代了「時間序列上的行為」，機械化火力集中在收尾稽核而非問題發生的當下。
- **input space**：判定寫清楚了，解析整個留白——章節定位、章節邊界、清單式完整性、同版多筆與順序，四項全缺。
- **repo reality**：既有程式引用幾乎全數正確且可重現，但三處結論撐不住 repo 的實際形狀。
- **test mapping**：量測與行號紮實，但一個 scenario 不是 RED、兩個寫不出 fixture，且與第二個 Approval 解析器直接衝突。

## Orchestrator 的裁決（lens 之間的分歧）

- **插入點波及範圍**：三個 lens 各給一份不同的受影響 fixture 清單。從原始碼重數（`tests/spec_archive_test.py`）：`status: approved` ＋ 空白 `## Approval` 者為 quux:194、corge:206、grault:229、garply:237、plugh:277、waldo:293。插入點若在 `spec-archive.py:232`（tier 解析）之後、`check_verdict`（:233）之前，則 corge、garply、grault 第一段、plugh 都先死在更早的檢查，不受影響；翻掉的是 quux:202、grault:269，並搶先 waldo:293。**SPEC 的 Setup plan fixture 清單正確，缺陷是插入點未寫明。**
- **F1 的 class**：repo reality 記 class 2，test mapping 記 class 1。採 class 1——SPEC §1:31 宣稱 windows-support 通過，而 S1/S5 寫死 `## Approval`，是 SPEC 內部自相矛盾。
- **F6 的 class**：repo reality 記 class 1，test mapping 記「接近 class 1」。採 class 1——SPEC:68 宣稱「解析回歸測試全數保留」，與翻掉 grault:269 直接衝突。

## Findings

### class 1 —— 違反本 SPEC 自己寫的規則，在目前版本修正，不需重新核准

- [HIGH] specs/spec-version-bump/SPEC.md:31 — §1 宣稱 windows-support 通過連續性檢查，但其章節標題為 `## 8. Approval record`，與 S1/S5 寫死的 `## Approval` 矛盾 — `specs/archive/windows-support/SPEC.md:324`；`tools/gate-intent.sh:55` 用寬鬆比對才讀得到 — class 1 — 明寫章節比對規則（標題含 Approval，到下一個 `##` 為止），並以此真實標題為 fixture 重新量測。 — status: fixed（v0.2 §2 章節定位＋S6 改用真實的帶數字標題）
- [HIGH] specs/spec-version-bump/SPEC.md:66-68 — 把 grault 翻成 exit 1 會消滅唯一一條「小數版號可以封存」的正向控制，與同句「解析回歸測試全數保留」衝突 — `tests/spec_archive_test.py:269-270` 是四條小數版斷言中唯一的 exit 0 — class 1 — 給 grault 補一筆完整 v0.2 核准紀錄使其維持 exit 0，另建空白 Approval 的 v0.N fixture 承載 S1。 — status: fixed（v0.2 S9a/S9b 取代單向翻掉 grault）
- [MEDIUM] specs/spec-version-bump/SPEC.md:34 — 「`specs/` 底下目前沒有任何作用中的 SPEC」在它自己的 commit 上就不成立 — `5d7409a` 建立了 `specs/spec-version-bump/SPEC.md`（status draft） — class 1 — 改寫為「除本 SPEC 外沒有其他作用中的 SPEC」，並補 `--check` 在本分支的預期輸出。 — status: fixed（v0.2 §1.5 改寫為「除本 SPEC 外」）
- [MEDIUM] specs/spec-version-bump/SPEC.md:84-85 — Must NOT 的理由與實際行為不符：`git log -S` 找不到時是 `die(2)` 大聲失敗，不是靜默失效；且 tier 1 根本不會走到該行 — `spec-archive.py:166-171` — class 1 — 結論保留，理由改寫為實測行為（Tier 2+ exit 2、Tier 1 不執行）。 — status: fixed（v0.2 §1.4 改寫為實測行為）
- [LOW] specs/spec-version-bump/SPEC.md:25-26 — `docs/evidence-first.md:106` 的引文跨到 :107 — class 1 — 引用改為 :106-107。 — status: fixed（v0.2 §1.1 引用改為 :106-107）
- [LOW] specs/spec-version-bump/SPEC.md:22-24 — 成因單點歸因不足，`dot_agents/workflows/evidence-first.md:66` 也明寫 bump，兩份 skill-doctor 報告另指 `templates/spec.md` 的註解為直接依據 — class 1 — §1 補上並列來源，否則 S9 只擋一半。 — status: fixed（v0.2 §1.1 補並列來源，S10 涵蓋 evidence-first.md:66）

### class 2 —— 規格缺口，折回草稿；仍有分歧者進核准請求

**解析規則（全部缺席）**

- [HIGH] SPEC.md:43-58 — Approval 章節的定位規則未定義 — 四份已封存 SPEC 有 `## Approval` 與 `## 8. Approval record` 兩種標題 — class 2 — 明寫匹配規則。
- [HIGH] SPEC.md:49-54 — 章節結尾未定義；以「下一個任意層級標題」結尾會把分節式章節切在第一個 `###` 之前 — `windows-support:324-328` — class 2 — 明定到下一個 `##` 為止。
- [HIGH] SPEC.md:45-46 — 清單式紀錄的「完整」從未定義，S2/S8 的 fixture 寫不出來；S4 只為分節式定義欄位 — 三份已封存的清單式紀錄無 `approval: confirmed` 也無 `date:` 標籤 — class 2 — 為清單式獨立寫出必要欄位與可接受引號形式（`「」`、ASCII 雙引號、blockquote 三種並存）。
- [HIGH] SPEC.md:43-44 — S1 的「章節為空」是錯的輸入描述；真實形狀是「有樣板散文、沒有紀錄」 — `templates/spec.md:57-64` 的佔位行、本 SPEC 自己的 :119-123 — class 2 — S1 改述為「沒有解析得出的、綁定目前版本的完整紀錄」，fixture 直接取範本原文。
- [MEDIUM] SPEC.md:55-58 — 同版多筆未規定，且 repo 裡有 `decision: confirmed` 誘餌 — `windows-support:379-391` 的 `### v5 的兩項選擇` 排在真正的 `### v5`（:403）之前 — class 2 — 明定「任一筆完整即滿足」。
- [MEDIUM] windows-support:329,344,363,403,421,436,451 — 紀錄排列非遞增（v1,v7,v6,v5決策,v5,v4,v3,v2），逐行遞增比對的實作會拒絕 §1 宣稱通過的檔案 — class 2 — 明寫解析成集合，順序不影響判定。
- [MEDIUM] SPEC.md:43-58 — `## Approval` 完全缺席時的退出碼未說；既有程式對必要結構解析不到一律 rc 2 — `spec-archive.py:96,225,232` — class 2 — 明定並加 scenario。
- [MEDIUM] SPEC.md:51-52 — S5 只排除 Revisions，未排除程式碼區塊與 HTML 註解 — class 2 — 加一條 Must NOT 並以範本那一行為 fixture。
- [MEDIUM] SPEC.md:77-78 — 「正整數 vN」沒有判定式；既有解析接受 `v0` 與 `v01` — class 2 — 明寫 `^v[1-9]\d*$`。
- [LOW] SPEC.md:77-78 — 後果是 v0.x SPEC 永遠無法封存，但這個永久性質沒被寫成規則 — class 2 — 寫進 Must NOT 或 scenario，讓它成為被核准過的性質而非副作用。

**與既有機制的衝突**

- [HIGH] tools/gate-intent.sh:49-68 — repo 已有第二個 Approval 解析器，且語意相左：它已抽出核准版號集合並判斷目前版本有無核准，只是不擋（檔頭 :12-13 明寫 unconfirmed 也 exit 0）；:52-54 自述 `### v1.2` 讀成 v1，而 S3 要求不得截斷。實跑 S3 fixture：gate-intent 輸出 `intent_status: confirmed`，實作後 spec-archive 對同一檔案 exit 1。AGENTS.md 要求 evidence 標頭逐字複製 gate-intent 輸出 — class 2 — **本輪最重要的決定**：改 gate-intent.sh（需擴充授權清單，違反現行 Must NOT），或加一條 scenario 釘住兩支解析器判決一致，或明列為 Honest note。
- [HIGH] tools/gate.sh:69-83 — SPEC 選定的 gate 入口從不執行 `tests/spec_archive_test.py`；manifest 13 層皆無，`tests/run.sh:29-45` 只載入 `tests/cases/L*.sh` 9 個檔；唯一有該層的是 `tools/gate-agent-instructions.py:140`，其 SCOPE 於 :45 寫死 — class 2 — 把 `tools/gate.sh` 加進授權清單（manifest ＋ 一個 run_layer），或宣告本 scope 的 sidecar 入口。
- [HIGH] SPEC.md:14-15 — 插入點未指定，而既有斷言把它卡死成唯一解 — 見上方 orchestrator 裁決表 — class 2 — 寫明插入點為 `spec-archive.py:232` 之後、`check_verdict`（:233）之前，並說明 corge/garply/plugh 為何不需改動。
- [HIGH] SPEC.md:79 — `approval: not obtained` 只有否定規則、沒有正面出口；字面在 repo 有三種寫法（contract:30、templates/spec.md:64、evidence-first.md:171） — class 2 — 明寫「無人模式的 SPEC 因 status 仍為 draft，於既有 status 檢查即被拒，不進入本層」，並指定比對字面。
- [HIGH] SPEC.md:105 — tier 與新檢查的交叉未說；同程式已有 tier 1 跳過的先例（`check_squad` 對 tier 1 直接 return） — class 2 — 明寫「核准紀錄檢查不分 tier」。
- [MEDIUM] AGENTS.md:39-41 — 必跑檢查的觸發清單不含 evidence-squad，而 AGENTS.md 不在授權清單 — class 2 — 加入授權清單。
- [MEDIUM] SPEC.md:80 — 禁止改 `--check` 的後果是兩條路徑各說各話：`spec-archive.py:275-281` 仍把永遠無法封存的 SPEC 印成 candidate — class 2 — 保留 Must NOT，寫入 Honest notes。
- [MEDIUM] SPEC.md:102-117 — `templates/spec.md` 只授權 :3 與 :7，但 :63-64 的佔位行正是新檢查的直接輸入 — class 2 — 加入授權清單。

**測試與 scenario**

- [HIGH] SPEC.md:53-54 — S6 在 base ref 就是綠的，不是有效 RED。lens 抽出 base ref archiver 實跑 S1–S8：S1–S5、S7、S8 皆 base rc=0 vs 預期 1（RED 成立），僅 S6 base rc=0 = 預期 0，因 base ref 的 `archive()` 完全不解析 Approval — class 2 — 明寫 S6 是 GREEN-guard 而非 RED，或改寫成可殺變異的形式。
- [MEDIUM] SPEC.md:39-41 — 四項額外斷言在既有 `expect()`（:53-71）無處可放，而 Setup plan 只授權「fixture 輔助函式」 — class 2 — 明寫可修改 `expect()` 或新增 `expect_refused()`，並界定套用範圍。
- [MEDIUM] SPEC.md:64-68 — grault 被放在 Scenarios 之外，但它與 S1–S8 同性質；evidence 範本的對應表是 `## Stated claim → Test` 與 `## RED reconstruction`，照 Scenarios 標題建表會漏掉它 — class 2 — 升格為 S10 或在前言明寫它必須進 RED reconstruction 表。
- [MEDIUM] SPEC.md:59-62 — S9 的 forbid 是字面子字串（`forbid()` 實作為 `pattern not in read(file)`，非 regex），換句話即失效；同一條規則在 `evidence-first.md:66` 另有一份未被涵蓋 — class 2 — 改用同檔 `agree()`（:54-71），其 docstring 正是為此而寫。
- [MEDIUM] SPEC.md:59-62 — S9 寫「evidence-first.md」但 repo 有兩個同名檔（`dot_agents/workflows/` 與 `docs/`），且合約檔被改卻無對應 require — class 2 — 指名完整路徑並納入合約檔。
- [MEDIUM] SPEC.md:47-48 — S3 測的 `v1.2` 是新規則不會產生的輸入；全庫搜尋無真實案例，它防的是被否決的 `vN.1`/`vN.2` 方案 — class 2 — 註明其防禦對象，或併入既有 v0.1/v0.10 回歸。
- [LOW] SPEC.md:110-117 — 文件類的「處數」是對尚不存在的 diff 的預測；`evidence-first.md:56` 的 Versioning 是橫跨 :56-63 的八行條目卻算 1 處 — class 2 — 改成「N 個條目」或不給數字。

**證據敘述的誠實性**

- [HIGH] SPEC.md:17-34,36-62 — 把「版號暴衝」重新定義成「存檔時核准紀錄的形狀」，是問題的代理指標而非問題本身；原始請求的原話是時間序列上的行為 — class 2 — 明文承認代理關係的落差。
- [HIGH] SPEC.md:72-74 — 兩條 Must NOT（不驗真偽、不驗順序）合起來就是原事件的重演路徑：封存前替 v3 補一段格式正確的核准文字即可通過 — `/tmp/skill-doctor-fmzszh6j/analysis.md:23`、ZfC3FfT1 `top_findings[0]` — class 2 — **決定**：是否要求補記的核准在 Revisions 顯式標記為 backfilled。
- [MEDIUM-HIGH] SPEC.md:11-12,102-117 — 兩份 skill-doctor 報告的 suggestions 全是散文，**都沒有提議改 `spec-archive.py`**，也沒有提議連續性檢查；此機制是起草者為回應「能機械化就要機械化」而新增，§1 卻寫得像從既有缺口直接推導 — class 2 — §1 明說這是為滿足該約束而新增。
- [MEDIUM] evidence-first.md:56,64,109,166 — 真正決定「什麼時候才可以 bump」的規則仍是純散文，S1–S9 沒有一條測試 bump 時機是否正當 — class 2 — **決定**：是否評估即時機制（commit-time 檢查 status/spec_version 轉移合法性）。
- [MEDIUM] SPEC.md:102-117 — 8 檔中只有 3 檔帶新增的機械邏輯，5 檔是純散文同步 — class 2 — **決定**：是否拆成兩個 PR。
- [LOW] SPEC.md:125-132 — 已否決清單缺少 ZfC3FfT1 報告的核心機制（`vN.1`/`vN.2` 小數子版號），未交代為何選「整數沿用」 — class 2 — 補一條。

### class 3 —— 本次變更以外，記入 Honest notes，不在此修

- [LOW] dot_agents/skills/spec-archive/scripts/spec-archive.py:53 — 尾隨垃圾被 `\b` 回溯靜默截斷成合法版號：實測 `v1.2junk`→`v1`、`v1-rc1`→`v1`、`v1.`→`v1`（`v1junk` 正確無匹配） — class 3。
- [LOW] spec-archive.py — 重複的 `spec_version` 行取第一筆，使用者看到的可能是第二筆 — class 3。
- [LOW] tools/gate-agent-instructions.py:4-9 — 對 gate.sh 的描述已過時（稱其寫死 windows-support，但 gate.sh:30-53 已接受 --scope） — class 3。
- [LOW] .gitignore — 工作樹有一筆與本 scope 無關的已暫存變更（新增 `CLAUDE.local.md`），非本 session 產生；封存與 gate 的 source-state 層都要求乾淨樹 — class 3 — 第一個 checkpoint 之前需單獨處理。
- [LOW] docs/evidence-first.md:1-6 — 人讀文件與 workflow 的雙文件同步負擔是 repo 既有結構成本 — class 3。

## 各 lens 的讓步（逐字保留）

- **input space**：沒有實作可測，所有「某某實作會怎樣」都是從既有 regex 與 fixture 推論；未建立臨時 repo 跑假想 fixture；不涵蓋機制有效性、散文措辭是否足夠、tier 取捨；未查證擬議新措辭是否自洽（Setup plan 只給行號未給措辭）。
- **test mapping**：5d7409a 無任何實作，RED/GREEN 判斷是預測；S1–S8 的 fixture 內文自行推定；未跑 `tools/gate.sh` 或 `tests/run.sh`；未驗證「共用模組不可行」的否決理由；未檢查文件改動是否破壞既有 90 條 invariant 中的哪幾條。
- **repo reality**：兩份 skill-doctor 報告與 8 輪 codex 審查不在 repo 內，無法查證；§1 的「實測」用哪套解析規則無法重現，故章節與多節兩項記為規格歧義而非算錯；未執行 `tools/gate.sh`；插入點波及範圍為推論；未查證 `~/.agents/` 已安裝副本與 repo 是否一致。
- **scope**：未查證 `spec-archive.py` 的實際結構；未查證 §1 的四份 SPEC 實測；對 8 輪 codex 審查一無所知；未逐條驗證 S1–S9 的程式邏輯；Tier 2 的裁定只從「治理機制擴散半徑」提出邊界觀察，非對 SPEC 規則的裁決。
