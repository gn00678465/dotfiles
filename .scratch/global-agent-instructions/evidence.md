# Evidence Report — global-agent-instructions (Tier 2)

- `headline`: GATE PASSED — reproducibility degraded (tool versions are recorded, not pinned; baseline/RED reconstruction were obtained manually by verifiers, not by the single entry point); ordering mixed; broad repository suite is substituted outside the scope gate; lint and suite health are substituted, narrower checks
- `command`: `evidence`
- `contract`: applied
- `scope`: global-agent-instructions
- `change_set`: `e0d3e0e721dd6a01120a9b516f9c9fcfa57ab751...1a579af21cb091652404985c4b3182eaacf563f4`
- `base`: `e0d3e0e721dd6a01120a9b516f9c9fcfa57ab751`
- `report_language`: zh-TW
- `intent_status`: confirmed
- `intent_source`: 使用者核准原文：「我核准 global-agent-instructions 的 SPEC v2，包括 S1S9、Must NOT 與 Setup plan。」；已提交的 SPEC `specs/global-agent-instructions/SPEC.md`（`spec_version: v2`、`status: approved`、`tier: 2`；Approval 記錄 v2，commit `8b1ce0b`）
- `ordering`: mixed — 新增測試先於主要實作；`f224ace` 與 `1a579af`（原 `cb9552d`，見 Honest notes 的作者修正）各有測試檔調整，詳見 RED reconstruction 與 Honest notes
- `git_facts`: complete — base 可達、非 shallow、SPEC provenance、commit ordering、base baseline 與 RED reconstruction 均已取得
- `source_state`: `1a579af21cb091652404985c4b3182eaacf563f4`
- `source_state_exclusions`: `.gate/` — gate 產物目錄；gate entry point 已提交，沒有其他豁免
- `toolchain`: `git version 2.53.0.windows.2`; `uv 0.11.14 (3fdfdc7d4 2026-05-12 x86_64-pc-windows-msvc)`; `chezmoi version v2.72.0, commit f81cb321789aa3df62871248f5e4d361a59e7cc1`; `Python 3.13.15`; `GNU bash 5.2.37(1)-release`
- `entry_point`: `uv run --no-project python tools/gate-agent-instructions.py --base e0d3e0e721dd6a01120a9b516f9c9fcfa57ab751`
- `reproducibility`: degraded — entry point、檢查程式與版本均可取得，但專案沒有釘住這些開發工具的 lockfile；上述版本是本次實際輸出。另外，baseline（`sh tests/run.sh` 於 base worktree）與 RED reconstruction（新測試複製到 base 執行）是驗證者在各自隔離 worktree 手動取得，不在 `tools/gate-agent-instructions.py` 這個單一入口的執行範圍內，重跑入口本身不會重新得到這兩組數字
- `changed_unit_command`: `git diff --name-status e0d3e0e721dd6a01120a9b516f9c9fcfa57ab751...1a579af21cb091652404985c4b3182eaacf563f4`
- `changed_unit_granularity`: path — 文件與模板沒有可用的 symbol extractor；個別段落與自然語言句子未逐一映射

## Baseline

Fable 在 base worktree 執行 `sh tests/run.sh`：exit 1，332 項通過；既有失敗為 L2 `05-wsl-user-runtime-dir` 的兩項（202、203）與 L4 的 `cp: Permission denied`。候選執行得到相同失敗集合，沒有新增失敗。這是廣泛專案套件的 baseline，不是本次 scope gate 的通過數字。此數字由 Fable 在其隔離 worktree `dotfiles-global-agent-instructions-verify-fable-final` 手動取得，不是 `tools/gate-agent-instructions.py` 這個入口自己執行的一層。

## Changed unit → Test

以下由 `git diff --name-status ...` 取得，採 path granularity。文件中的個別句子沒有 symbol-level 映射；每列指出涵蓋該檔案或行為的檢查。

| Changed unit | Test | Status |
|---|---|---|
| `.chezmoitemplates/agent-instructions.md` | `tests/agent_instructions_test.py`；`tests/check_agent_doc_invariants.py` | pass |
| `.chezmoitemplates/evidence-first-contract.md` | `tests/check_agent_doc_invariants.py`；render layer | pass |
| `dot_agents/workflows/evidence-first.md` | `tests/check_agent_doc_invariants.py`；intent/evidence workflow review | pass |
| `dot_agents/skills/verification-gate/SKILL.md` | `tests/check_agent_doc_invariants.py`；Fable/Codex S3 review | pass |
| `dot_agents/skills/verification-gate/references/entry-point.md` | `tests/check_agent_doc_invariants.py` | pass |
| `dot_agents/skills/verification-gate/assets/templates/evidence.md` | `tests/check_agent_doc_invariants.py`; `tests/spec_archive_test.py` | pass |
| `dot_agents/skills/commit/SKILL.md` | `tests/check_agent_doc_invariants.py`；Fable S6 review | pass |
| `docs/evidence-first.md` | `tests/check_agent_doc_invariants.py` | pass |
| `specs/global-agent-instructions/SPEC.md` | `sh tools/gate-intent.sh global-agent-instructions`; `tests/spec_archive_test.py` | pass |
| `tests/agent_instructions_test.py` | gate render layer；`python -m py_compile`（語法） | pass |
| `tests/check_agent_doc_invariants.py` | gate invariant layer；RED reconstruction；`python -m py_compile`（語法） | mixed |
| `tests/spec_archive_test.py` | gate archive layer；RED reconstruction；`python -m py_compile`（語法） | pass |
| `tools/gate-agent-instructions.py` | gate itself；invalid-base、dirty-source、manifest negative controls；`python -m py_compile`（語法） | pass |

## Stated claim → Test

| Claim | Test | Status |
|---|---|---|
| S1：Linux、darwin、Windows 的 Codex/Claude 入口同平台相同、契約一次、每份 ≤600 詞 | `tests/agent_instructions_test.py`，16 checks；結果 597 詞 | pass |
| S2：高保證觸發、SPEC 核准、tests-first、RED、tier、anti-gaming、失敗不得宣稱完成與降級揭露保留 | `tests/check_agent_doc_invariants.py` 第 14 組；S2 語意審閱 | pass |
| S3：已核准 SPEC 的 intent、tier、setup 可重用，未授權工作仍詢問 | 同檔第 15、20、21 組；Fable 五處逐項審閱 | pass |
| S4：intent/version 從已提交 SPEC 導出，`intent_source` 使用 `` `spec_version: vN` ``，封存相容 | `gate-intent.sh`；`tests/spec_archive_test.py` 20 assertions；skill/template review | pass |
| S5：CLOSE 在 merge 前完成 | workflow invariant 第 17 組；archive tests | pass |
| S6：commit 成功後不重問；只在可各自建置與還原時拆分 | invariant 第 18、22 組；Fable review | pass |
| S7：耐久狀態與必要副作用有適用範圍；繁中與 zhtw-mcp fallback 明確 | agent template render；人工語意審閱 | pass |
| S8：可先跑受影響測試，最後 gate 跑全部適用層；移除主觀 Complexity budget | invariant 第 19 組；final gate | pass |
| S9：產物使用本 scope、來源狀態前後一致、失敗層不宣稱通過 | `tools/gate-agent-instructions.py`；manifest/source-state controls | pass |
| Must NOT：不 apply、不碰 main、不弱化既有高保證與測試、不改禁止元件、不宣稱模型行為 | diff scope、git state、84 invariants、雙方語意審閱 | pass，模型實際遵守仍無法由文字測試證明 |

## RED reconstruction

- `f28da54` 的 `tests/agent_instructions_test.py` 複製到 base 執行：exit 1；base render 為 793 詞，超過 600。
- `0108005` 的 invariant 測試複製到 base 執行：exit 1；第 15 組首先失敗，因 gate skill 尚未有已核准 SPEC 重用措辭。
- `0108005` 的 `spec_archive_test.py` 在 base 為 exit 0、20 assertions；這是既有 archive 行為的回歸防護，不是新 RED。
- `92f8971`（原 `1c2bf0c`，作者身分修正後 SHA 改變，見 Honest notes）的 invariant 測試在 base 為 exit 1（第 15 組首先失敗）；在前一候選 `ec119fa` 為 exit 1（第 20 組首先失敗），證明本輪變異可被抓到。
- `92f8971` 在最終候選（原 `cb9552d`，現 `1a579af`）首次執行時到第 24 組出現 `UnboundLocalError: CHECKS`；該候選在實作提交中加入 `global CHECKS` 修正測試本身。此項造成 ordering=mixed，不能記為乾淨 tests-first。
- 第 21–24 組未在同一個最初 RED 執行中逐一到達；第 24 組的行為另由前一候選的不可達 base 控制及最終候選的 rc=2 控制確認，報告不把它改寫成逐一 RED。

## Gate (final fresh run)

所有數字來自最終程式碼提交 `1a579af`（原 `cb9552d`，經 `git rebase --exec 'git commit --amend --reset-author --no-edit'` 修正作者身分後的 SHA；`git diff cb9552d 1a579af --stat` 為空，樹狀內容逐位元組相同）上的同一次 entry point 執行；報告檔在該次 gate 後才提交。

| Layer | Command | Threshold | Result |
|---|---|---|---|
| Source state before | `sh tools/gate-source-state.sh` | clean worktree、非 shallow | `commit=1a579af21cb091652404985c4b3182eaacf563f4`; clean; `.gate/` only |
| Intent | `sh tools/gate-intent.sh global-agent-instructions` | committed SPEC, approved matching version | `intent_status: confirmed`; `spec_version: v2`; `status: approved`; `tier: 2` |
| Agent-doc invariants | `uv run --no-project python tests/check_agent_doc_invariants.py` | all invariants pass | 84 invariants hold |
| Agent-instructions render | `uv run --no-project python tests/agent_instructions_test.py` | all platforms, identical entries, one contract, ≤600 words | 16 checks hold; 597 words per rendered entry |
| Spec-archive tests | `uv run --no-project python tests/spec_archive_test.py` | valid template evidence archives; invalid/missing/mismatch remains refused | 20 assertions hold |
| Source state after | `sh tools/gate-source-state.sh` | byte-for-byte report identical to before | same commit and clean state as before |
| Manifest audit | `sh tools/gate-manifest-audit.sh .gate/global-agent-instructions/layers-manifest .gate/global-agent-instructions/layers-ran` | every expected layer recorded exactly | 6 layers recorded; PASS |

## Negative controls

每條標明執行者與執行位置；「本任務 worktree」指實作者（Sonnet）單一寫入的 `D:/Projects/dotfiles-dev/dotfiles-global-agent-instructions`，「隔離 worktree」指驗證者各自的最終驗證副本（Codex: `dotfiles-global-agent-instructions-verify-codex-final`；Fable: `dotfiles-global-agent-instructions-verify-fable-final`）。

- `tests/agent_instructions_test.py` 內建 word-count 控制 — 對合成字串（601 個 `"x"`）呼叫 `word_count()`，只驗證這個函式本身會回報超過上限；**不是**對真實算繪內容的驗證，且是程式碼本身的一部分，實作者與兩位驗證者各自執行入口時都會自動觸發，不是單一一方的手動操作。
- Fable 的 M5（模板刻意加 10 個詞、算繪成 609 詞）— 執行者：Fable，位置：隔離 worktree `dotfiles-global-agent-instructions-verify-fable-final`；結果：`tests/agent_instructions_test.py` 的 render 層 rc 1，是走到「真實超字數會被攔下」失敗路徑的控制，補足上面內建控制只驗證函式回傳值的缺口。
- 移除一個 S2 必要契約措辭（`Tier declared in the spec`）— 執行者：Sonnet（實作者），位置：本任務 worktree（非隔離，於實作階段完成，早於任一驗證回合）；結果：invariant 第 14 組失敗，還原後恢復綠燈。
- Missing manifest layer — 執行者：Codex 與 Fable 各自在隔離 worktree 重現；結果：`gate-manifest-audit.sh` 回傳 exit 1 並指名缺少的層。
- 只移除 `run_layer("agent-instructions-render")` 但保留 manifest 項目 — 執行者：Fable，位置：隔離 worktree `dotfiles-global-agent-instructions-verify-fable-final`；結果：audit 回傳 exit 1。
- 同時移除該呼叫與其 manifest 項目（M3）— 執行者：Fable，位置：同上；結果：gate 回傳 0，這是結構性盲點（manifest 是同一個入口檔案裡的靜態清單），已列入 Structural blind spot。
- 把 manifest 檔案還原成 CRLF — 這不是刻意注入的負向控制，是 Sonnet 在 gate 修正輪次 1（本任務 worktree）實際遇到的紅燈：Windows 上 `Path.write_text` 預設寫入 CRLF，`gate-manifest-audit.sh` 的 `read -r`／`grep -qxF` 逐位元組比對因而全數對不上，audit 回傳 exit 1；修正為顯式 `newline="\n"` 後，Codex 與 Fable 各自在隔離 worktree 重跑最終候選，確認不再出現這個失敗。Fable 另外在其隔離 worktree 對兩輪候選都各自刻意執行了這項負向控制：把 `tools/gate-agent-instructions.py` 裡的 `newline="\n"` 移除，讓 `layers-manifest`／`layers-ran` 回到平台預設換行（Windows 上即 CRLF）並提交，重跑 gate；結果：gate 回傳 rc 1，`gate-manifest-audit` 的輸出裡指名 `source-state-before` 對不上（manifest 與 ran 兩邊逐位元組比對失效，症狀與 Sonnet 原本遇到的紅燈一致）。移除控制後的候選未提交進分支，只用於驗證。
- 未追蹤的產品檔案 — 執行者：Sonnet，位置：本任務 worktree（提交 `tools/gate-agent-instructions.py` 前，該檔本身未追蹤觸發此控制）；Codex 與 Fable 在各自隔離 worktree 對最終候選重現同一行為；結果：`source-state-before` 回傳 exit 1，後續層未執行。
- 不可達的 `--base`（`0` × 40）— 原始缺口由 Codex 在隔離 worktree `dotfiles-global-agent-instructions-verify-codex-final` 先發現（候選誤判為通過），Fable 在其隔離 worktree重現並列為高風險；Sonnet 於 gate 修正輪次 2 修正後，Codex 與 Fable 各自在隔離 worktree 重新驗證，結果：gate 回傳 exit 2、不印通過標頭、未執行任何層。
- S3 五處無條件確認的 mutant — 執行者：Fable 於隔離 worktree 提出、Sonnet 於本任務 worktree 修正並跑出綠燈，Codex 於隔離 worktree 以最終 84 項不變量重跑確認。Fable 另外在其隔離 worktree 對修正後的候選實際執行了還原控制：把 `dot_agents/skills/verification-gate/SKILL.md:53` 還原成 `always confirm first`（移除 S3 例外措辭）並提交，重跑 gate；結果：`agent-doc-invariants` 層 rc 1。
- S6 舊拆分規則字句的 mutant — 執行者同上（Fable 提出、Sonnet 修正、Codex 確認）。Fable 同樣在隔離 worktree 執行了還原控制：把 `dot_agents/skills/commit/SKILL.md` 補回被移除的舊拆分句（「當提交符合一或多種提交類型時，應盡可能切成多個提交」）並提交，重跑 gate；結果：`agent-doc-invariants` 層 rc 1。
- 最終候選的廣泛套件重跑 — 執行者：Fable，位置：隔離 worktree `dotfiles-global-agent-instructions-verify-fable-final`；Fable 在 base 與候選各完整跑完一次 `sh tests/run.sh`；結果：exit 1，與 base 相同的三項既有失敗，沒有新增失敗；這是輔助佐證，不是本 scope gate 的一層。Codex 已啟動 `sh tests/run.sh`，但未取得完整結果，不能判定通過（與 verification.md 的 Independent results 一致）。

## Layers not run as specified

- **N-A:** static type checking, changed-line coverage, mutation testing, property-based tests, and supply-chain audit have no applicable implementation/dependency surface for this documentation/template change.
- **N-A:** application real-execution layer; the product is instruction text. The `chezmoi execute-template` render check is the applicable real interface.
- **SUBSTITUTED (Lint):** this scope's entry point has no lint layer, and no linter (`ruff`, `pyflakes`, `flake8`) is installed on this host (checked: `command -v ruff|pyflakes|flake8` and `python -m ruff/pyflakes` all report absent). Substituted with `python -m py_compile tests/agent_instructions_test.py tools/gate-agent-instructions.py tests/check_agent_doc_invariants.py tests/spec_archive_test.py` at `1a579af`, run by Sonnet in the task worktree: exit 0 for all four files. This catches syntax errors only — it cannot detect unused imports, style violations, or other issues a real linter would flag.
- **SUBSTITUTED (Suite health):** this scope's entry point has no suite-health layer (no randomized-order or repeat-run check). Substituted with running each of the three check scripts (`check_agent_doc_invariants.py`, `agent_instructions_test.py`, `spec_archive_test.py`) twice in immediate succession at `1a579af`, run by Sonnet in the task worktree: byte-identical stdout and exit 0 both times for all three. This shows repeat-run stability only — it is not a randomized-order check and cannot detect cross-case ordering dependence the way `tests/run.sh`'s `TESTS_SHUFFLE=1` mode does for the broader suite.
- **SUBSTITUTED:** broad `sh tests/run.sh` was run to completion independently on candidate and base by Fable, in `dotfiles-global-agent-instructions-verify-fable-final`; it is not a layer in this scope-specific persisted entry point. It produced the same pre-existing L2/L4 failures and cannot replace the six scope layers. Codex started `sh tests/run.sh` but did not obtain a complete result, so its run cannot be judged pass or fail and is not counted as corroboration.
- **none:** no layer was NOT REACHED or DEPENDENCY UNMET in the final gate.

## Dismissed concerns

- Natural-language tests proving model obedience — dismissed as an intentionally stated limit in SPEC Intent and Must NOT; the checks prove file contracts only.
- Reuse of `.gate/windows-support/` or its awk baseline — dismissed by the fixed scope, artifact path, and diff review; no such path was read or written.
- Unreachable or decorative base ref — the final invalid-base control returns exit 2 before any layer; the remaining limitation that no scope layer compares outputs against base is recorded below, not hidden.
- CRLF manifest accounting — dismissed by the final LF write and negative control; final manifest and ran files are bytewise LF.
- S3 unconditional confirmation and S6 contradictory split rule — dismissed by final 84 invariant result and Fable/Codex rechecks.
- `docs/evidence-first.md` line 48 called `.scratch/` a repository convention while line 77 described the ambiguity rule, as of `1a579af` (the gated code state) — accepted at that time as a low-risk wording inconsistency; it did not alter the persisted gate or archive behavior. **Current HEAD status: fixed** in a later documentation-only commit — line 48 now reads 「workflow Phase 4 規定，CLOSE 前提交」, matching line 77's rule. That fix is a post-gate doc change, not itself re-verified by a gate rerun.

## Structural blind spot

- The gate validates that `--base` resolves to a commit, but no scope layer uses that ref to execute a base comparison. Baseline and RED reconstruction were performed by the independent Fable verifier; rerunning the entry point alone cannot reproduce those base-relative numbers.
- Removing a layer call and its static manifest entry together is not detected (M3 survived); the entry point has no independently declared manifest outside that file.
- There is no lint or suite-health layer built into this scope's entry point; both are substituted with narrower manual checks (syntax-only compile, repeat-run only) — see Layers not run as specified.
- Instruction text checks cannot prove an agent will obey the instructions, reduce prompts, latency, or token use.
- Native WSL/macOS execution was not available in this Windows host; S1 uses chezmoi's three platform fixture renders instead.

## Honest notes

- First gate run at `ec959f3` failed manifest audit because Windows Python wrote CRLF. `ec119fa` added explicit LF writes; the rerun passed. The final fresh gate at the code commit (`1a579af`, originally `cb9552d`) passed on the first attempt both before and after the author-identity fix.
- The final test file fix (`global CHECKS`) was made in the code commit now at `1a579af`; this is why ordering is `mixed`, and why the report does not claim all new assertions had independently observed RED.
- Codex and Fable used separate final worktrees at `cb9552d` (content-identical to `1a579af`; see the author-identity fix below); both independently observed normal gate exit 0, invalid-base exit 2, dirty-source exit 1, and missing-manifest exit 1. Their coverage differed, listed honestly rather than glossed as symmetric: Fable additionally ran the semantic S1-S9/Must NOT review, reconstructed the base-suite baseline and RED, ran the CRLF/S3/S6 revert controls above, and completed `sh tests/run.sh` on both base and candidate; Codex started `sh tests/run.sh` but did not obtain a complete result (not counted as corroboration) and did not independently run the CRLF/S3/S6 revert controls. There was no conflicting verdict on any check both of them actually completed.
- **作者身分修正（本次新增揭露）：** `1c2bf0c`、`cb9552d`、`158fe12` 三個 commit 的 author/committer 原本都是 `v <v@x>`。根因：Fable 在其 scratch worktree 執行 `git config user.name`/`user.email` 時，因三個 worktree（`dotfiles`、`dotfiles-global-agent-instructions`、Fable 的 scratch worktree）共用同一個 `D:/Projects/dotfiles-dev/dotfiles/.git/config`、且 `extensions.worktreeConfig` 未啟用，該設定寫進了共用檔案而非 Fable 自己的 worktree-local config，污染了之後在任何一個 worktree（包含本任務 worktree）新建 commit 的身分。該設定現已從共用 `.git/config` 移除（已核實：檔案只剩 `[core]`／`[remote "origin"]`／`[branch "main"]`），全域身分核實回到 `Madao <gn00678465@gmail.com>`（`git config --show-origin --get user.name` → `file:C:/Users/gn006/.gitconfig  Madao`）。修正方式：`git rebase ec119fa --exec 'git commit --amend --reset-author --no-edit'`。SHA 對照：

  | 舊 SHA | 新 SHA | 說明 |
  |---|---|---|
  | `1c2bf0ce6b03215a7f039b8a1c2d128f608c74f2` | `92f8971` | test commit（gate 修正輪次 2/2 RED） |
  | `cb9552da53aadb8434522d954f527ed5ad174aa8` | `1a579af21cb091652404985c4b3182eaacf563f4` | 本報告的 `source_state`（下稱 C'） |
  | `158fe12f65f4f2e36ed1d5a8f78db228a1391be7` | （已捨棄，`c122d21`） | 原本的 evidence commit；分支已 reset 到 C'，本報告是它的替代 |

  樹狀內容逐位元組不變：`git diff cb9552da53aadb8434522d954f527ed5ad174aa8 1a579af --stat` 與 `git diff 1c2bf0ce6b03215a7f039b8a1c2d128f608c74f2 92f8971 --stat` 皆為空輸出（已實測）。Codex／Fable 兩輪驗證實際執行於作者修正前的 `cb9552d`；因樹狀內容證明逐位元組相同，本報告延續其結論到 `1a579af`，但這個延續本身在此明確揭露，不是沉默的身分置換。
- The evidence source state is the code commit `1a579af`（原 `cb9552d`，作者身分修正後）measured before this report commit. No merge, apply, or push was performed; main remains at `e0d3e0e`. No `spec-archive` action was run.
