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
