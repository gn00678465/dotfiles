# SPEC 可讀性：模板與 playbook 的分工

## 問題

SPEC 模板 86 行，其中 24 行是 HTML 註解。這些註解是 agent 的流程說明，不是
給人讀的。五份已封存 SPEC 沒有一份保留它們。

真實 SPEC 的膨脹（windows-support 802 行）也不是模板能解決的。那是 agent 寫作
行為的問題，由 playbook 的步驟指引限制。

## 原則

模板是給人填的表格。它只放佔位符和最短的提示。

playbook 是給 agent 讀的指令。版號規則、狀態轉換、spec-archive 的解析要求都在
playbook，不在模板裡重複。

## 模板改法

### 刪除

| 刪什麼 | 行數 | 理由 |
|---|---|---|
| `spec_version` 的 HTML 註解 | 9 行 | 版號規則在 playbook Versioning 條目 |
| `status` 的 HTML 註解 | 6 行 | 狀態轉換在 playbook Signing 段 |
| `Approval` 的 HTML 註解 | 8 行 | 格式要求在 playbook Signing 段 |
| Scenarios 的 evidence report 映射機制說明 | 2 行 | 那是 gate 的內部邏輯 |
| Must NOT 的「diff can never show」解釋 | 2 行 | agent 的知識，不是填表指令 |
| Setup plan 的「authorization point」解釋 | 1 行 | 流程設計理由 |

### 新增

| 加什麼 | 理由 |
|---|---|
| `scope` 欄位 | 五份真實 SPEC 都手動加了 |
| `base_ref` 欄位 | 同上 |
| Scenario 表格三欄：行為、通過條件、證據類型 | skill-doctor 建議。現有模板只有文字描述 |

### 精簡

| 段落 | 原本 | 改成 |
|---|---|---|
| Scenarios 提示 | 5 行解釋 + 反例 | 2 行：反例 + 表格 |
| Must NOT 提示 | 3 行 | 1 行：「不得違反的約束」 |
| Approval 提示 | 2 行 + 8 行註解 | 1 行 + 範例行 |
| Revisions 提示 | 3 行 | 1 行 |

### 改後的模板

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

86 行 → 42 行。

## Playbook Step 1 的寫法指引（新增）

在 old-coder playbook 的 `## 1. SPEC` 段落末尾加上：

```markdown
### 寫法

寫給核准者讀，不是寫給跑 gate 的 agent 讀。

- 模板的佔位符是提示，不是內容。替換它，不要在它後面附加。
- SPEC 不超過 150 行（Revisions 和 Approval 不計）。Tier 1 不超過 50 行。
  超過代表設計還沒收斂，拆 scope 或刪細節。
- Revisions 是變更日誌，不是敘事。每條一行：日期、改了什麼、為什麼。
- 不重複 playbook 已有的定義（版號規則、狀態轉換、anti-gaming）。SPEC 引用
  它們的結果，不解釋它們的機制。
```

## Invariant test 影響

三個檢查引用模板（`spec_t`）：

| 行 | 檢查什麼 | 新模板是否通過 | 需要改嗎 |
|---|---|---|---|
| 238 | `## Approval` | 通過（標題保留） | 不用 |
| 255 | `shipped` | **不通過**（status 註解已刪） | 改為檢查 playbook（playbook 第 242 行有 `shipped`） |
| 284 | `revised-pending-approval` | **不通過**（status 註解已刪） | 改為檢查 playbook（playbook 第 62 行有） |

改法：在 `check_agent_doc_invariants.py` 把這兩個 `require` 的目標從 `spec_t`
改成 `workflow`（指向 playbook）。playbook 本來就有這兩個值，不需要新增。
