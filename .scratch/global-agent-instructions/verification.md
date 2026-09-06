# Independent Verification — global-agent-instructions

Orchestrator-owned aggregate, written beside the gate's evidence report —
never into it. The per-round material below is the aggregate comparison
Codex and Fable produced and handed to the coordinator; the implementer
(Sonnet) was not given their raw per-round transcripts, only this comparison,
so it is reproduced here rather than a verbatim per-round log.

- `final_source_state`: `1a579af21cb091652404985c4b3182eaacf563f4`（原候選 `cb9552da53aadb8434522d954f527ed5ad174aa8`，兩者的 `git diff ... --stat` 為空——樹狀內容逐位元組相同，差異只在 commit 的 author/committer 身分；見 evidence.md 的 Honest notes「作者身分修正」。兩輪驗證實際執行於 `cb9552d`，本欄延續其結論到 `1a579af`，此延續在此明確揭露）
- `final_verdict`: passed
- `rounds_run`: 2 (cap 2)；未超過上限，未另外取得核准
- `verifier`: Codex 與 Fable，各自 fresh context: yes（各自獨立隔離 worktree，未讀對方報告即先各自產出結果）。相關性打斷：task context（各自隔離 worktree，未共用建構者對話）；未打斷：model family 與建構者不同（Sonnet 實作，Codex／Fable 驗證），但 Codex／Fable 彼此之間也是不同 model family，互為交叉檢查
- `inputs_given`: task contract（使用者在對話中逐次追加的授權與範圍調整）、approved SPEC @ v2（`specs/global-agent-instructions/SPEC.md`，`status: approved`）、source state（見上）、entry point（`uv run --no-project python tools/gate-agent-instructions.py --base e0d3e0e721dd6a01120a9b516f9c9fcfa57ab751`）——未提供建構者對話記錄；未發現污染
- `canary`: not run

## Rounds

| Round | Source state | Verdict | Behavioural findings | Description/mapping findings |
|---|---|---|---|---|
| 1 | `ec119fa`（gate 修正輪次 1 之後、輪次 2 之前的候選） | failed | Codex：不可達的 `--base` 被誤判為通過（無 rc=2、無層級驗證）。Fable：重現同一項並列為高風險；另找到 SKILL.md 五處無條件確認（scaffold 路徑、Inputs 清單、tier 推論、entry point 寫入、toolchain 安裝）尚未套用 S3 例外；S6 commit skill 留有與新拆分規則相反的舊句；S4 缺少 `intent_source` 帶 `` `spec_version: vN` `` 的明講；docs/evidence-first.md 未提及本 scope 的 gate 入口 | `docs/evidence-first.md` 第 48 行仍稱 `.scratch/` 為「本 repo 的慣例」，第 77 行才講清楚 ambiguous-path 規則，兩處用語不完全對齊 |
| 2 | `cb9552d`（內容與 `1a579af` 逐位元組相同，見上） | passed | 無未解決項目：Codex 與 Fable 各自在隔離 worktree 對 gate 修正輪次 2 的結果重新驗證，`--base` 不可達回傳 exit 2、不印通過標頭、未執行任何層；SKILL.md 五處、S6 舊句、S4 缺漏、docs 缺漏皆確認已修正；84 項不變量、16 項算繪檢查、20 項封存斷言、6 層 manifest 全部通過 | 第 1 輪的 docs 第 48/77 行用語落差仍在，接受為低風險、不影響機械行為，予以揭露而非新開一輪 |

## Grading record

The human grades material or disputed findings; the builder may propose.
Behavioural → fix, then re-verify in a NEW verifier context. Description /
mapping → fix and disclose, no new round.

- 不可達 `--base` 被誤判為通過 — 判為 **behavioural**（human 認可 Codex/Fable 的判定）— 修正：`tools/gate-agent-instructions.py` 新增 `verify_base_reachable`（`git cat-file -e <base>^{commit}`），round 2 重新驗證通過。
- SKILL.md 五處無條件確認、S6 舊拆分句、S4 `spec_version` 明講缺漏、docs 入口缺漏 — 判為 **behavioural/description 混合**（前三項是文件契約行為本身，第四項是純描述缺漏）— 修正：round 2 的 84 項不變量涵蓋，重新驗證通過。
- M3（同時移除 layer 呼叫與其 manifest 項目仍回傳 0）— 判為 **description（已知結構性盲點）**，undisputed — 處置：在 evidence 的 Structural blind spot 揭露，不視為阻擋項，未新開一輪修正。
- `docs/evidence-first.md` 第 48/77 行用語落差 — 判為 **description**，undisputed — 處置：在 evidence 的 Dismissed concerns 揭露並接受，不影響機械行為，未新開一輪。**此為 `1a579af`（gate 驗證時的程式碼狀態）的歷史狀態**；現況：已在 gate 之後的文件修正 commit 中改正（第 48 行改為與第 77 行一致的措辭），屬純文件修正，未觸發重新驗證。
- 作者身分（`v <v@x>`）— 判為 **description/provenance**（不影響樹狀內容，`git diff --stat` 為空）— human 決定修正：`git rebase --exec 'git commit --amend --reset-author --no-edit'`；由 Sonnet 執行，Fable／Codex 事後審查驗證，不歸類為需要重新跑驗證回合的行為變更（內容未變），但在 evidence 與本檔明確揭露 SHA 對照與延續理由。

## Fixed after the last verified state (therefore unverified)

- 作者身分修正（`git commit --amend --reset-author`）不算「驗證後又改了程式碼」：樹狀內容逐位元組不變（`git diff --stat` 為空）。
- 在最後一次驗證回合（round 2，`cb9552d`／內容相同的 `1a579af`）之後，另有兩類非程式碼變更，逐一列出人工核對範圍與是否重跑 gate：
  1. `evidence.md`／`verification.md` 兩份報告的重寫與後續多輪描述修正——報告產出本身，由 Sonnet 撰寫、Fable／Codex 逐輪唯讀核對，不是被驗證的來源狀態，未重跑 gate。
  2. `docs/evidence-first.md` 三處描述性修正（Phase 4 產物欄措辭改為「workflow Phase 4 規定，CLOSE 前提交」、機械擋住表的 gate 入口措辭改為「各 scope 的 gate 入口」並新增 `gate-agent-instructions.py` 的 `--base` 控制一列、指令速查補上 `gate-agent-instructions.py` 的正式命令）——純文件描述，不改動任何程式碼或測試檔，由 Sonnet 在任務 worktree 完成，未重跑 gate。
  `source_state` 全程維持 `1a579af`（唯一實際跑過正式 gate 命令的程式碼狀態）；HEAD 比 `1a579af` 多出的檔案僅限上述兩類報告／文件，不代表最新 HEAD 已重新跑過 gate。

## Per-round reports (aggregate, not verbatim — see note above)

未取得逐輪原文，此處為彙整。逐輪原文可向協調者 Codex 索取；若後續取得，應逐字附於本節之下，不得改寫或摘要替代。

### Independent results

| Check | Codex | Fable |
|---|---|---|
| Scope diff and forbidden files | 13 changed paths, all in the approved Setup plan; no forbidden source changed | Same scope; all paths LF |
| Formal gate with approved base | exit 0; 84 invariants, 16 render checks, 20 archive assertions, 6 manifest layers, source state unchanged | exit 0; same layer results and source state |
| Unreachable `--base` | exit 2; no passing headline, no layer ran | exit 2; non-commit/tree object also refused |
| Dirty product source | exit 1 at source-state-before; later layers not reached | Same behavior |
| Missing manifest layer | exit 1 naming missing layer | Same behavior; removing call and manifest together remains a known blind spot |
| RED/GREEN history | Tests and implementation commits are ordered in the recorded sequence; test-file adjustments in GREEN commits require `mixed` | Same; found `f224ace` casing change and `cb9552d`（現 `1a579af`）`global CHECKS` fix |
| Full repository suite | 已啟動 `sh tests/run.sh`，未取得完整結果，不能判定通過 | Candidate and base both exit 1 with the same pre-existing L2/L4 failures; zero new failures |
| S1-S9 and Must NOT semantic review | No contrary finding | All scenarios and constraints accepted; natural-language model obedience remains unprovable by text checks |

### Agreement

- The final candidate is acceptable for the approved SPEC after the two gate-fix rounds.
- The final formal gate passes with `intent_status: confirmed`, SPEC v2, tier 2, clean source state before and after, and a complete six-layer manifest.
- The gate rejects an unreachable base, dirty product state, and a missing manifest layer.
- The diff does not touch main, platform selection, install lists, modify-template algorithms, spec-archive implementation, verifier protocol, or commit analyzer.
- S1 renders both global entry points identically for Linux, darwin, and Windows; each render is 597 words with one evidence-first contract.
- Text checks do not prove model behavior, prompt count, latency, or token reduction.

### Differences and disposition

1. Codex first found that an invalid explicit base was accepted. Fable reproduced it and marked it high severity. Sonnet fixed it in the code commit now at `1a579af`; both final verifiers reproduced exit 2.
2. Fable found five remaining unconditional S3 confirmation phrases, an S6 stale split sentence, the missing S4 `spec_version` guidance, and docs synchronization gaps. Codex did not independently report these before Fable's report; Sonnet fixed them in the same commit, and Codex's final invariant run plus Fable's semantic review accepted the result.
3. Fable identified `M3`: removing a layer call and its entry from the same static manifest survives with exit 0. Both reports classify this as a structural blind spot; it is disclosed in evidence and does not alter the approved scope.
4. Both verifiers identify process ordering as `mixed`: `f224ace` changed the invariant's case while changing the workflow, and the final code commit added `global CHECKS` to make the RED test executable. The assertions were not weakened; the evidence report records the exact causes and does not claim strict tests-first for those edits.
5. Fable found a low-risk wording difference in `docs/evidence-first.md`: line 48 calls `.scratch/` a repository convention while line 77 explains the ambiguity rule. It is accepted and disclosed because the gate and archive behavior are unaffected. **This describes `1a579af` (the gated code state).** Current HEAD status: fixed in a later documentation-only commit (line 48 now reads consistently with line 77) — a post-gate doc fix, not itself re-verified by a gate rerun.
6. The broad `tests/run.sh` suite has existing environment-dependent failures on both base and candidate. It is recorded as substituted corroboration, never as a passing scope-gate layer. Codex's own run of it did not reach a complete result and is recorded as such (see the Independent results row above), rather than folded into a pass.
7. （本次新增）三個 commit 的作者身分被發現是 `v <v@x>`，根因是 Fable 的 scratch worktree 在 `extensions.worktreeConfig` 未啟用下寫入了共用 `.git/config`。以 `git rebase --exec 'git commit --amend --reset-author --no-edit'` 修正，樹狀內容證明不變；SHA 從 `cb9552d`／`1c2bf0c` 改為 `1a579af`／`92f8971`，原 evidence commit `158fe12` 被捨棄並以本次重寫的兩份報告取代。

## Final verdict

`final_verdict`: passed, for SPEC v2 on `fix/global-agent-instructions` at `1a579af`（內容與兩輪驗證時的 `cb9552d` 逐位元組相同，僅作者身分經修正）, with the disclosed limits recorded above and in evidence.md（Structural blind spot、Layers not run as specified、Honest notes）— those limits are disclosed, not folded into a non-template verdict label. No unresolved blocking finding remains. The branch is ready for human review or a later CLOSE/merge workflow; no merge, apply, or push was performed. `spec-archive` was not invoked.
