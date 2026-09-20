# Anti-slop skill 調查

調查目的：盤點現有的 anti-slop 與寫作品質 skill，找出缺口，提出新 skill 的設計方向。

## 1. 現有 skill 盤點

### 1.1 unslop（pstack）

- **做什麼。** 偵測並改寫 AI 文字模式。
- **規則。** 33 條（編號 3-33，部分跳號），分六大類：Content（虛假歸因）、Language（AI 詞彙、花式 is、三段式）、Style（長破折號、冒號、粗體、表情符號）、Communication artifacts（聊天機器人語氣）、Filler（填充句）、Jargon（抽象隱喻名詞）、Plain speech（說機制不說感覺、主動語態、刪副詞、用簡單詞、矯揉造作的散文、過度壓縮）。
- **觸發。** 任何散文表面（poteto-mode 的 "any prose surface" 觸發器）。
- **調用時機。** 寫完之後。
- **範圍。** 所有散文：回覆、PR 描述、commit 正文、文件。不覆蓋程式碼。

### 1.2 technical-writing（pstack）

- **做什麼。** 四層技術寫作標準：Diátaxis 結構、Google developer style 句法、STE 指令規則、Global English 語法。
- **規則。** 四層各自有 8-12 條具體規則，加上三條全域規則（刪除不工作的字、用短的日常詞、規則讓句子更糟時換方式修）。
- **觸發。** `/technical-writing` 或撰寫文件、RFC、readme、PR 描述、commit 訊息時。
- **調用時機。** 寫作過程中（即時適用）。
- **範圍。** 文件、RFC、readme、PR 描述、commit 訊息。不覆蓋 SPEC、playbook、SKILL.md。

### 1.3 no-comments（pstack）

- **做什麼。** 派遣 Comment Sicko 審查程式碼註解，刪掉不需要的，對聲稱的約束提出編碼替代方案。
- **規則。** 保留清單很短：授權標頭、公開 API 的 doc comment、解釋程式碼無法表達的外部依賴行為的連結。其餘刪除。
- **觸發。** `/no-comments`，在 review 之前。
- **調用時機。** 提交之後、review 之前。
- **範圍。** 只有程式碼註解。

### 1.4 deslop（cursor-team-kit，未安裝）

- **做什麼。** 清理程式碼中的 slop：敘事性註解、無依據的防禦性代碼、死的相容性路徑、無關的修改。
- **規則。** 未能直接讀取（plugin 未安裝），從 pstack 的文件描述推斷。
- **觸發。** `/deslop`，在 commit 之前。
- **調用時機。** 提交之前。
- **範圍。** 程式碼 diff。不覆蓋散文。

### 1.5 writing-for-agents（mattpocock-skills）

- **做什麼。** 撰寫 agent 消費的文件（skill、AGENTS.md、CLAUDE.md）的參考指南。
- **規則。** 不是 anti-slop 規則，而是結構設計原則：context pointer（觸發時機與措辭）、information hierarchy（in-file step → in-file reference → disclosed reference）、progressive disclosure、completion criteria、leading words（用預訓練裡已有的概念錨定行為）、pruning（single source of truth、不重述環境已有的資訊、刪 no-op 句子）。
- **觸發。** 建立或編輯 skill、修改 AGENTS.md/CLAUDE.md 時。
- **調用時機。** 寫作過程中。
- **範圍。** Agent 面向的文件。不覆蓋 SPEC、playbook、模板。

### 1.6 使用者的全域 CLAUDE.md 寫作規則

- **做什麼。** 兩條規則：(1) 用繁體中文寫作，遵循 ASD-STE100，用 zhtw-mcp 查不確定的台灣用語；(2) 刪除所有矯揉造作的散文。
- **規則。** 只有兩條，沒有具體的模式清單。
- **觸發。** 永遠適用。
- **調用時機。** 永遠。
- **範圍。** 所有產出。

### 1.7 anthropic-skills 的 skill-writer 和 skill-creator

未在本環境安裝。從 skill 清單描述推斷：
- **skill-writer。** 引導使用者建立 SKILL.md，處理 frontmatter 和結構。
- **skill-creator。** 從頭建立 skill、修改既有 skill、跑 eval 測試效果。
- 兩者都不是 anti-slop skill。

## 2. 重疊分析

| 關注點 | unslop | technical-writing | no-comments | deslop | writing-for-agents | CLAUDE.md |
|---|---|---|---|---|---|---|
| AI 詞彙 | ✅ 主要 | ✅ 引用 unslop | — | — | — | ✅「mannered prose」 |
| 句法規則 | ✅ 部分 | ✅ 主要（STE + Global English） | — | — | — | ✅ ASD-STE100 |
| 程式碼註解 | — | — | ✅ 主要 | ✅ 包含 | — | — |
| 程式碼結構 | — | — | — | ✅ 主要 | — | — |
| 文件結構 | — | ✅ Diátaxis | — | — | ✅ information hierarchy | — |
| Agent 文件設計 | — | — | — | — | ✅ 主要 | — |
| 繁體中文 | — | — | — | — | — | ✅ 但無規則細節 |
| SPEC/playbook | — | — | — | — | — | — |

## 3. 缺口分析

### 3.1 沒有任何 skill 覆蓋 SPEC、playbook、SKILL.md 的散文品質

- `unslop` 處理通用散文，但不知道 SPEC 的結構（哪些欄位是給人讀的，哪些是機器解析的）。
- `technical-writing` 適用文件，但沒有 SPEC 特有的規則（例如「scenario 要帶通過條件」、「模板註解不複製進 SPEC」）。
- `writing-for-agents` 處理 agent 文件的結構設計，但不處理內容品質。

### 3.2 繁體中文寫作沒有具體規則

CLAUDE.md 只說「遵循 ASD-STE100，用繁體中文」。但 ASD-STE100 是英文簡化規範，套用到中文需要轉譯（例如「一句一個想法」通用，但「限制句長 20 詞」不直接對應中文字數）。沒有 skill 做這個轉譯。

### 3.3 「模板膨脹」的行為問題沒有守衛

spec-template-readability.md 的研究指出 `windows-support` SPEC 有 802 行。這不是模板的問題，是 agent 寫 SPEC 時的行為問題。沒有 skill 在寫 SPEC 時限制長度或在寫完後審查膨脹。

### 3.4 deslop 未安裝，程式碼 slop 缺守衛

pstack 的流程在 commit 前跑 `/deslop`，但它來自 cursor-team-kit，本環境沒有。fallback 描述是「用白話要求同樣的結果」，不是 skill。

## 4. 需要新 skill 嗎？

### 選項 A：組合既有 skill

在 old-coder playbook 的步驟裡加上：
- Step 1 寫 SPEC 後跑 `/unslop`
- 最終文件跑 `/technical-writing`
- 程式碼提交前跑 `/no-comments`

**問題。** 這能處理通用 slop，但不能處理 SPEC 特有的問題（模板註解殘留、重複定義、機器 metadata 偽裝成人類內容）。每次跑 `/unslop` 都需要手動補充「還要刪掉模板註解」、「scenario 要三欄位」，這些規則沒有持久化。

### 選項 B：建立新 skill（推薦）

一個專門處理 evidence-first 工作流產出的散文品質 skill。它不重寫 unslop 或 technical-writing 的規則，而是在它們之上加一層領域規則。

**原因。**
1. SPEC 的問題是結構性的（哪些欄位要填、哪些是機器解析的、模板註解要不要保留），不只是措辭。unslop 看不到這層結構。
2. 規則需要持久化。每次寫 SPEC 都手動補充同一組規則違反 encode-lessons-in-structure 原則。
3. 範圍有邊界。只覆蓋 evidence-first 工作流的產出（SPEC、evidence report、playbook、squad findings），不覆蓋通用散文。

## 5. 新 skill 設計提案

### 名稱

`clear-writing`（對齊 stage-manager 的非描述性命名風格可能更好，但這個 skill 的職責是具體的「讓文件清楚」，描述性名稱比較自然）。

或者 `spec-hygiene`，如果範圍限定在 SPEC 和 evidence report。

### 範圍

evidence-first 工作流的文件產出：
- SPEC（`specs/<scope>/SPEC.md`）
- evidence report（`.scratch/<scope>/evidence.md`）
- squad findings（`.scratch/<scope>/squad/*.md`）
- playbook 和 SKILL.md 的散文段落（維護時）

不覆蓋：程式碼（deslop/no-comments 的事）、通用文件（technical-writing 的事）、回覆（unslop 的事）。

### 調用時機

1. Step 1 寫完 SPEC 之後、送審之前
2. Step 4 evidence report 寫完之後
3. 維護 playbook 或 SKILL.md 的散文時（手動觸發）

### 規則（只列不在 unslop/technical-writing 裡的）

**SPEC 結構規則：**
1. 模板的 HTML 註解不複製進 SPEC。它們是首次填寫的提示，寫完就刪。
2. 不重複定義。Tier 的域名清單、anti-gaming 規則、版號規則在 playbook 和其他 skill 已有權威副本。SPEC 引用，不複製。
3. 每個 scenario 帶三欄位：行為、通過條件、證據類型。
4. SPEC 不超過 150 行（Tier 3 的 Revisions 與 Approval 不計在內）。超過代表設計還沒收斂。Tier 1 的上限是 50 行。
5. 機器解析的欄位（spec_version、status、tier）和人類內容分開。前者是 metadata，不需要解釋。

**散文規則（在 unslop 之上）：**
6. 先跑 `/unslop`，再套用本 skill 的規則。
7. 祈使句寫填表指令（「列出工具」而非「應該列出需要的工具」）。
8. 用繁體中文寫內容，用英文寫 metadata 欄位名（spec_version、status、tier）。
9. 每個段落的第一句是指令或結論。解釋放後面，可以被刪掉而不丟失核心資訊。
10. ASD-STE100 的中文適配：一句一個想法，不超過 30 個字（中文的 20 詞對應）。主動語態。具體動詞。

**evidence report 規則：**
11. 數字用實測值，不用形容詞（「47 項通過」而非「測試看起來不錯」）。
12. 每個層的結果獨立成行，不合併成一段描述。
13. 跳過的層說原因和狀態（N-A / UNAVAILABLE / SUBSTITUTED），不只說「跳過」。

### SKILL.md 結構草稿

```
---
name: spec-hygiene
description: >-
  Clean SPEC, evidence report, and squad findings for human readability.
  Runs after /unslop. Removes template artifacts, enforces structure rules,
  and applies ASD-STE100 in Traditional Chinese. Use after writing a SPEC
  (before review), after writing an evidence report, or when maintaining
  playbook prose.
---

# Spec Hygiene

Run /unslop first. This skill adds domain rules on top.

## SPEC rules
(rules 1-5 above)

## Prose rules
(rules 6-10 above)

## Evidence report rules
(rules 11-13 above)

## Process
1. Run /unslop on the target file.
2. Apply the rules above in order.
3. Measure: count lines, check scenario table has three columns,
   verify no HTML comments remain, verify no repeated definitions.
4. Report what changed.
```

## 6. 與 writing-for-agents 的關係

`writing-for-agents` 教你怎麼設計 agent 文件的結構（information hierarchy, progressive disclosure, leading words）。`spec-hygiene` 教你怎麼清理已經寫好的 evidence-first 文件的內容。前者是設計指南，後者是品質守衛。它們不重疊。

如果未來要維護 playbook 或 SKILL.md 的散文品質，`spec-hygiene` 的散文規則（6-10）加上 `writing-for-agents` 的結構原則一起適用。
