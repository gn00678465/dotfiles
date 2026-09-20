# SPEC 模板可讀性研究

研究對象：`dot_agents/skills/stage-manager/templates/spec.md`（模板）與五份已封存
SPEC（`specs/archive/*/SPEC.md`）。目標：找出 AI slop，提出改進建議與改進後的模板。

## 1. 目前的問題

### 1.1 模板註解比填入內容長

模板第 3-11 行的 `spec_version` HTML 註解有 9 行，解釋版號規則、草稿慣例、
spec-archive 的拒絕條件。填入的值只有一個 `v1`。同樣的規則已經寫在 playbook
的 Versioning 條目和 spec-archive SKILL.md，三份副本內容微異。

`status` 註解（第 12-17 行）有 6 行解釋四個狀態的轉換擁有者。填入的值只有一個
`draft`。同樣的轉換規則在 playbook 的 Signing 段落。

讀者看到的是：一個需要填 `v0.1` 的欄位，旁邊跟著一大段 agent 才需要讀的流程說明。

### 1.2 真實 SPEC 完全不保留註解

五份已封存 SPEC 沒有一份保留模板的 HTML 註解。`windows-support` 第 3 行直接寫
`spec_version: v7`，沒有旁邊的 9 行解釋。`global-agent-instructions` 同樣。

結論：註解只在第一次填寫時有參考價值，之後就是噪音。但 agent 每次讀 SPEC 都會
讀到它（如果沒刪的話），浪費 token。

### 1.3 重複定義散布

| 定義 | 出現位置 |
|---|---|
| Tier 1/2/3 域名（money, auth, data loss...） | 模板第 18-20 行、stage-manager/SKILL.md 第 34 行、verification-gate/SKILL.md Calibration 段 |
| Anti-gaming 規則 | tdd/SKILL.md（1-4）、verification-gate/SKILL.md（5-6）、old-coder playbook（全六條） |
| 版號規則 | 模板第 3-11 行、old-coder playbook Versioning 條目 |
| 狀態轉換 | 模板第 12-17 行、old-coder playbook Signing 段 |

模板不需要重複定義這些。它是一份要填的表格，不是一份教學文件。

### 1.4 Approval 註解過度結構化

第 69-76 行的 Approval 註解有 8 行，描述兩種紀錄格式（清單式和分節式）、CLOSE
解析器認什麼、自主模式怎麼處理。agent 填寫時需要知道格式，但不需要知道 CLOSE
的解析邏輯。

真實 SPEC 的 Approval 段各有不同格式：`windows-support` 用分節式（18 行 per
版本），`spec-version-bump` 用清單式（1 行 per 版本）。模板應該展示一種就好。

### 1.5 被動語態和冗長解釋

模板第 24-28 行：

> Concrete inputs, concrete expected outputs, edge cases, error cases.
> "Handles bad input" is not a scenario; `divide(1, 0) raises
> ZeroDivisionError with message X` is. Each scenario maps 1:1 to at least one
> automated test named after it, so the evidence report's mapping is
> mechanical.

四句裡只有第一句是指令。第二句是反例教學。第三句是流程解釋（為什麼要這樣寫）。
第四句是 evidence report 的內部機制。填寫 SPEC 的人只需要第一句加反例。

### 1.6 真實 SPEC 的膨脹

`windows-support`（802 行）的 §9 Revisions 有 340 行，記錄 7 個版本的每一次修訂
細節。`spec-version-bump`（367 行）的 §1 依據有 100 行，論證為什麼要做這件事。
`global-agent-instructions`（124 行）最精簡，但 Setup plan 有 13 個項目符號。

真實 SPEC 的膨脹不完全是模板的錯，但模板的註解風格（每個欄位都附帶長解釋）暗示
「寫得詳細是好的」。

## 2. Unslop 規則摘要（適用於 SPEC）

從 poteto-mode 的 unslop skill 和 writing-the-reply 規則提取適用的部分：

| 規則 | 套用到 SPEC |
|---|---|
| 13: 不用長破折號 | 模板和真實 SPEC 都有 `—` |
| 14: 冒號不當連接詞 | 模板第 57 行 `checkpoint commit cadence: <e.g. ...>` 是表格欄位可以，但 `spec_version: <!-- 9 行解釋 -->` 不行 |
| 16: bold + colon 重述標題 | 模板的 `## Scenarios` 後面第一句重述「什麼是 scenario」 |
| 27: 寫做了什麼，不寫感覺 | 模板第 36 行 "A diff can never show what the code must not do" 是真的但不是填表指令 |
| 28: 長句拆開 | 模板第 27-28 行一句跨三行 |
| 29: 主動語態 | 模板第 35-37 行被動 |
| 31: 用簡單的詞 | "An unjustified package is a spec defect" 可以寫成 "justify every new package" |

## 3. ASD-STE100 相關原則

- 每句一個想法。
- 主動語態，具體動詞。
- 限制句長（目標 20 詞以內）。
- 指令用祈使句。
- 不解釋讀者已知的事。
- 描述用具體名詞，不用抽象概念。

## 4. 逐欄位建議

### 標頭 metadata

| 欄位 | 建議 | 理由 |
|---|---|---|
| `spec_version` 註解（9 行） | **DELETE** | 版號規則在 playbook 的 Versioning 條目。agent 讀 playbook 後填這個欄位不需要 9 行解釋 |
| `status` 註解（6 行） | **DELETE** | 狀態轉換在 playbook 的 Signing 段。agent 填 `draft` 不需要知道轉換擁有者 |
| `tier` 註解（3 行） | **SIMPLIFY** | 保留域名清單（invariant test 會檢查），刪除「same definitions as the gate's Calibration」 |
| `scope` | **KEEP**（真實 SPEC 有，模板沒有）| 每份真實 SPEC 都加了 scope 欄位。模板應該有 |
| `base_ref` | **KEEP**（同上）| 同上 |
| `contract` | **KEEP**（同上）| 同上 |

### Scenarios

| 元素 | 建議 | 理由 |
|---|---|---|
| 段落解釋（5 行） | **SIMPLIFY** → 2 行 | 保留反例（「"Handles bad input" 不是 scenario」），刪除 evidence report 的映射機制 |
| 項目格式 | **SIMPLIFY** | 加上 skill-doctor 建議的三欄位：行為、通過條件、證據類型 |

### Must NOT

| 元素 | 建議 | 理由 |
|---|---|---|
| 段落解釋（3 行） | **SIMPLIFY** → 1 行 | 「A diff can never show what the code must not do」是 agent 的知識，不是填表指令 |

### Failure model

| 元素 | 建議 | 理由 |
|---|---|---|
| 現有內容 | **KEEP** | 已經精簡，表格格式好 |
| "Delete this section at Tier 1–2" | **SIMPLIFY** → 移到標題旁邊的括號 | 刪除指令不是內容 |

### Setup plan

| 元素 | 建議 | 理由 |
|---|---|---|
| "The spec is the authorization point" 解釋（2 行） | **DELETE** | 這是流程設計的理由，不是填表指令 |
| 項目清單 | **KEEP** | 已經是清單格式，每項有佔位 |
| "an unjustified package is a spec defect" | **SIMPLIFY** → "justify every new package" | 祈使句比判語更清楚 |

### Approval

| 元素 | 建議 | 理由 |
|---|---|---|
| 段落解釋（2 行） | **SIMPLIFY** → 1 行 | 保留「An entry you cannot quote is an approval you do not have」（精簡且有用）|
| HTML 註解（8 行） | **DELETE** | 格式說明由 playbook 的 Signing 段負責。模板只需要一個範例行 |
| 兩種格式並列 | **SIMPLIFY** → 只展示清單式 | `spec-version-bump` 的清單式最精簡（1 行 per 版本）。分節式的模板讓人以為必須寫 18 行 per 版本 |

### Revisions

| 元素 | 建議 | 理由 |
|---|---|---|
| 段落解釋（3 行） | **SIMPLIFY** → 1 行 | 保留 "never silently drift"，刪除 exploration rounds 的說明（那是 playbook 的事） |
| 範例行 | **KEEP** | 已經精簡 |

## 5. 改進後的模板

```markdown
# SPEC — <task name> (Tier <1|2|3>)

- `spec_version`: v0.1
- `status`: draft
- `tier`: <!-- 1 trivial / 2 normal / 3 high stakes (money, auth, data loss, concurrency, public API) -->
- `scope`: <feature-slug>
- `base_ref`: <commit SHA>

## Scenarios

具體輸入、具體預期輸出。「處理錯誤輸入」不是 scenario；`divide(1, 0) raises ZeroDivisionError` 才是。

| scenario | 行為 | 通過條件 | 證據類型 |
|---|---|---|---|
| <name> | given <input>, does <action> | <assertion> | <test / real execution / manual> |

## Must NOT

不得違反的約束。測試、API 簽章、效能預算。

- Must NOT: <constraint>

## Failure model (Tier 3 only)

| 失效模式 | 對應檢查 |
|---|---|
| <e.g. race condition on X> | <e.g. stress test Y under -race> |

## Setup plan

- Tools to install: <list | none>
- Git isolation: <worktree | branch | none (Tier 1 only)>
- Commit cadence: <e.g. RED then GREEN per behavior>
- Gate files by path: <e.g. `tools/gate.sh`>
- New dependencies (justify each): <list | none>

## Approval

逐字引文。不能引述的不算核准。

- <date> — approves <spec_version> — "<verbatim words>"

## Revisions

改了什麼、為什麼改。不靜默偏移。

- <date> — <what changed and why>
```

### 與現有模板的差異摘要

| 改了什麼 | 行數變化 |
|---|---|
| 刪除 spec_version 的 9 行 HTML 註解 | -9 |
| 刪除 status 的 6 行 HTML 註解 | -6 |
| tier 註解縮到 1 行 | -2 |
| 新增 scope、base_ref 欄位 | +2 |
| Scenarios 段落從 5 行改為 2 行 + 表格 | -1 |
| 加上三欄位表格（行為、通過條件、證據類型） | +3 |
| Must NOT 段落從 3 行改為 1 行 | -2 |
| Setup plan 刪除授權點解釋 | -2 |
| Approval 刪除 8 行 HTML 註解，只留範例行 | -8 |
| Revisions 段落從 3 行改為 1 行 | -2 |
| **合計** | **86 → 42 行（-44）** |

### invariant test 影響

`check_agent_doc_invariants.py` 第 231 行檢查模板裡有 `money, auth, data`。
新模板的 tier 註解保留了這段文字，不受影響。

第 238 行檢查 `## Approval`。新模板保留了這個標題。不受影響。

第 255 行檢查 `shipped`。新模板刪除了 status 註解裡的 `shipped`。**需要更新
invariant test**，改為檢查 playbook 或 spec-archive 裡的 `shipped`（那裡本來就有）。

第 284 行檢查 `revised-pending-approval`。同上，新模板刪除了這個值。**需要更新。**

## 6. 不在模板改的東西

真實 SPEC 的膨脹（`windows-support` 的 802 行）不是模板能解決的。那是 agent
在寫 SPEC 時的行為問題，需要 playbook 的步驟指引來限制。建議在 old-coder
playbook 的 Step 1 加一句上限：「SPEC 不超過 200 行（Tier 3 的 Revisions 與
Approval 不計），超過代表設計還沒收斂」。
