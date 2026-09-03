# Splitting the implementor into a subagent（evidence-first TDD 的 orchestrator / implementor 分離可行性）

> 研究日期：2026-08-31。
> 研究動機：目前 evidence-first workflow（`.chezmoitemplates/evidence-first-contract.md` + `dot_agents/workflows/evidence-first.md`）由 main session 同時擔任 orchestrator 與 implementor，RED→GREEN→REFACTOR 迴圈的全部 tool output（測試輸出、檔案編輯、重跑）都燒在 main context。本文查證：把 implementor 拆成 subagent（main session 只做 orchestration）是否可行、合約五性質在拆分後各自如何存活、殘餘信任缺口在哪裡，並對照三個既有模式（swarm-forge、spec-kitty implement-review、old-coder）給出設計建議。
> 主要來源：本 repo `.chezmoitemplates/evidence-first-contract.md`、`dot_agents/workflows/evidence-first.md`、`dot_agents/skills/verification-gate/SKILL.md`、`.chezmoitemplates/verifier-protocol.md`；官方文件 code.claude.com/docs（sub-agents、how-claude-code-works、costs、worktrees、best-practices）；本機 `/mnt/wsl/DWSLWSLSharedevsharedvhdx/swarm-forge`（README + `origin/two-pack` role prompts）、`/home/madao/.claude/skills/spec-kitty-implement-review/SKILL.md`、`/home/madao/project/coder-gate-mesh/old-coder/skills/old-coder/SKILL.md`。
> 官方文件段落由背景 research agent 對 code.claude.com/docs 逐頁查證後回報；引文以該回報為準，來源 URL 逐條附上。

## TL;DR

**可行，而且合約在設計上已經預期了這件事** —— contract 明文寫著五性質「the repository must end up carrying these five properties, because the verification step reads them from git, never from this conversation」（`.chezmoitemplates/evidence-first-contract.md`），而 verification-gate 的 Acquisition 一節更直接點名 subagent 場景：「The gate runs at a point that may be far from where the code was written: a later session, a different agent, **a subagent whose context is gone**」（`dot_agents/skills/verification-gate/SKILL.md`）。換句話說，整個驗證面本來就不信任「誰在對話裡看到了什麼」，只信 git 事實；implementor 換成 subagent 不會弄壞任何一條驗證路徑。

但可行有三個前提條件：

1. **Commit cadence 必須升級為每 behavior「RED commit（只有測試）→ GREEN commit（只有實作）」的 per-step 承諾，寫進 SPEC 的 Setup plan 並由人核准**。這是唯一能把 anti-gaming rule 2（temporal 規則，git 預設留不下痕跡）轉成 git 可讀 invariant 的手段。
2. **Orchestrator 把 subagent 的回報一律當 narration（不可信敘述），驗證只走 gate**：handoff 物是 commit SHA，不是 subagent 的話——這正是 swarm-forge 的 git_handoff 模型與 verification-gate 的「Never from the conversation」規則。
3. **只在迴圈夠長時拆**（多 behavior、Tier 2/3）：subagent 有固定啟動成本（重讀 CLAUDE.md、spec、程式碼脈絡），總 token 用量上升，換到的是 main context 不被 tool output 灌爆。Tier 1 / 單一 behavior 不值得。

殘餘信任缺口誠實地說：**anti-gaming（性質 5）本來就是 contract 自己承認「the one property nothing can verify after the fact」**。拆分沒有製造這個缺口，只是把它從「orchestrator 信任自己」搬到「orchestrator 信任 subagent」——而 RED reconstruction、mutation layer、per-step commit 慣例能把可鑽的空間壓到只剩「commit 順序可被事後偽造」這一條，該條在單 session 模式下同樣存在。

---

## 1. 五性質存活分析

合約五性質（`.chezmoitemplates/evidence-first-contract.md` 第 24–44 行）與拆分後的存活狀態：

| # | 性質 | 拆分後 orchestrator 還親眼見證嗎 | 事後從 git 可重建嗎 | 存活判定 |
|---|---|---|---|---|
| 1 | Intent on record（committed spec + approval record） | 是——SPEC / SPEC REVIEW 本來就是 orchestrator 與人的互動，不外包 | 是：spec 檔 + `## Approval` 段落 committed；gate 用 `git log --diff-filter=A -- <path>` 讀 provenance | **完整存活**，甚至更乾淨：subagent 收到的是已核准 spec 的路徑 |
| 2 | Tests committed before implementation | 否——commit 由 subagent 在自己的 worktree 做 | 是：gate 的 git-facts 表明列 Ordering =「whether test files were committed before the implementation they cover」（verification-gate SKILL.md, Acquisition） | **存活，條件是 cadence**：若 subagent 把 test+impl 混在一個 commit，ordering 事實消失，gate 記為 degraded（可見的降級，不是靜默） |
| 3 | 每個新測試 observed failing first（RED） | **否——這是拆分後 orchestrator 失去的最大直接見證** | 大部分是：見下方 RED reconstruction 分析 | **以「證據內容」論存活，以「時序宣稱」論不存活**——但時序宣稱在單 session 模式下人類同樣沒見證，只是自我回報 |
| 4 | Tier declared in spec | 是——tier 在 spec 裡，orchestrator 擁有 spec | 是：committed spec 的一個欄位 | **完整存活** |
| 5 | Anti-gaming held throughout | 否——rule 2「change one, run, then the other」發生在 subagent 的編輯序列裡 | 部分：見 §2 逐條分析 | **部分存活**；contract 原文即承認這是「the one property nothing can verify after the fact」，拆分不改變這個事實，只改變信任對象 |

### 性質 3 細看：RED reconstruction 補回了什麼

Verification-gate 的「Reconstructing RED」（`dot_agents/skills/verification-gate/SKILL.md`）：

> 1. Create a worktree at `base`. 2. Copy in the test files added by this change […] 3. Run those tests. **They must fail.** 4. Record which failed, and how.

這個重建**不依賴任何人「當時有沒有看著測試失敗」**——它直接回答 RED 想證明的命題：「這個測試對 base 而言不是 vacuous、行為在 base 確實不存在」。所以 subagent 謊稱看過 RED 但其實先寫實作再補測試，只要測試對 base 真的會失敗，證據價值等同；若測試對 base 不會失敗（vacuous 或行為已存在），reconstruction 當場抓到，且 skill 進一步要求「Don't just assert which — **prove it**: break the implementation with a one-off throwaway mutant」。

RED reconstruction 補不回的（skill 自己列的 caveats）：

- **Modified tests**：「Tests *modified* rather than added cannot be replayed this way」——改動既有測試的 RED 只能 case-by-case。
- **Collection-error 級的弱 RED**：import 失敗算 fail，但「a weaker RED than an assertion failure」，subagent 偷懶不寫 stub 會讓 RED 品質下降而 reconstruction 分不出「行為缺席」與「專案缺席」——skill 對整批 collection error 的處理是標成 `NOT EVIDENCE (base lacks the platform under test)`。
- **時序本身**：reconstruction 證明「此測試現在對 base 會失敗」，不證明「subagent 在寫實作前跑過它」。後者只剩紀律價值（防止 implementor 被自己的實作 anchoring 寫出順向測試），沒有證據價值——而這個紀律缺口在單 session 模式下對人類而言一樣是自我回報。

**結論：git facts + RED reconstruction 對「事後驗證」已經充分；拆分損失的是紀律的即時見證，不是證據。**

---

## 2. 殘餘信任缺口：什麼抓得到、什麼抓不到

情境：subagent 宣稱它全程守規，實際上沒有。

### 抓得到（機制與出處）

| 造假行為 | 抓到它的機制 |
|---|---|
| 測試 vacuous / 行為早已存在卻報成新行為 | RED reconstruction 對 base 重放，必須 fail（verification-gate SKILL.md, Reconstructing RED） |
| 測試 assert 不了東西（斷言空洞、斷言被放寬） | Mutation layer——「tests that assert nothing」正是它的目標欄位（同檔 The Layers 表） |
| Mock 掉 unit under test（anti-gaming rule 3） | 大多被 mutation 間接抓到：unit 被 mock 則其 mutants 存活；Tier 3 再由 verifier 的攻擊面 3 直接打「mocks swallowing the logic」（`.chezmoitemplates/verifier-protocol.md`, Attack order） |
| 改動行未被測試執行 | Changed-line coverage layer（同檔） |
| 謊報 gate 結果、編造層數字 | **報告根本不經 subagent 之手**：EVIDENCE 的每個數字必須來自 persisted entry point 的一次 fresh run（「Every number in the Gate table must come from one final fresh run of the entry point」），且報告要「reproducible from the repo alone」。subagent 的 narration 進不了證據鏈 |
| 把 subagent 回報當 intent | Skill 明文禁止：「Do not treat conversation history, a compaction summary, **or a subagent's return message** as the intent record」（verification-gate SKILL.md, Never from the conversation） |

### 抓不到（誠實清單）

1. **Anti-gaming rule 2 的時序**（「Never edit a test and the implementation in the same step」）：編輯順序不進 git。唯一的 git 痕跡是 commit 粒度——若 cadence 是 per-step（RED commit 只含測試、GREEN commit 只含實作），可以機械檢查「range 內沒有任何 commit 同時碰 test 與 impl 檔案」，把 temporal 規則轉成可讀 invariant。但要誠實：**commit 的先後與內容由作者掌控**，決心造假的 subagent 可以先寫完實作、再倒序編排 commits。per-step cadence 提高造假成本、並讓違規需要主動偽造而非順手發生，它不是證明。
2. **REFACTOR 期的 assertion 凍結**：test-structure refactor（合法）與 assertion 弱化（違規 rule 1）都表現為「test 檔被改」。Mutation rerun（workflow 要求 refactor 後重跑 mutation 確認「the restructured tests still kill」）是主要防線，但 mutation 的盲區（equivalent mutants、kill attribution）同檔已自承。
3. **RED 品質**（assertion failure vs collection error）在 reconstruction 中可見但無法回溯歸因——分不出「subagent 偷懶沒寫 stub」與「情境本來如此」。
4. **同質性風險**：implementor subagent 與跑 gate 的 orchestrator 是同一個 model，共享盲點。Anthropic 的 multiagent 研究記錄過極端案例：30 個 agent 有 18 個同時決定建立同名 branch「mvp-game-loop」（https://www.anthropic.com/research/multiagent-systems ）。這是 Tier 3 verifier（不同 context、blind-first）存在的理由，拆分不取代它。

**框架性結論**：單 session 模式下這些缺口一樣存在——人類同樣沒看著 main session 的編輯順序。拆分把信任邊界從「self-report 給人類」移到「subagent report 給 orchestrator」，而 contract 的整套設計（git-only facts、gate 重跑、downgrade 可見化）本來就是為了讓這條邊界上的敘述不需要被相信。

---

## 3. Claude Code subagent 機制事實（官方來源）

以下由背景 research agent 對官方文件查證回報，URL 逐條列出：

1. **Context 隔離**：subagent 拿到 fresh context——自己的 system prompt、專案 CLAUDE.md、git status snapshot、task message；**不繼承** parent 的 conversation history（fork 例外）、先前的 file reads。來源：https://code.claude.com/docs/en/sub-agents.md （Context Management 一節）。
2. **只有最終回報回到 parent**：「the subagent's tool calls stay out of your context, and Claude gets back a summary when the subagent finishes」（https://code.claude.com/docs/en/how-claude-code-works.md ）；best-practices 明示這是省 context 的手段：「Subagents run in separate context windows and report back summaries」（https://code.claude.com/docs/en/best-practices.md ）。**這正是本題的 token 動機成立的官方依據**：RED→GREEN 迴圈的測試輸出與編輯不進 main context。
3. **Token 成本**：省的是 main context window，不是總開銷——總 token 會上升。官方對 agent teams（多實例協作，非單 subagent）給過 ~7x 的量級：「Agent teams use approximately 7x more tokens than standard sessions when teammates run in plan mode」（https://code.claude.com/docs/en/costs.md ）。單一 implementor subagent 遠低於此，但「每次 dispatch 重載脈絡」的固定成本是真的。
4. **能力**：subagent 可配置 Bash / Read / Write / Edit 等工具（frontmatter `tools:` allowlist），Bash 在手即可 `git commit`——官方無任何 commit 限制（https://code.claude.com/docs/en/sub-agents.md ，Control Capabilities）。
5. **Worktree 隔離是一級功能**：「Subagents can run in their own worktrees so parallel edits don't conflict […] adding `isolation: worktree` to its frontmatter」（https://code.claude.com/docs/en/worktrees.md ）。
6. **可續談**：subagent 完成後可用 SendMessage 以同一 context 繼續（https://code.claude.com/docs/en/sub-agents.md ，Resume Subagents）——rejection loop 不必每輪重建脈絡。
7. **巢狀與並行**：預設可巢狀 3 層（`CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH`，同上）；官方未載明 subagent 並行硬上限，實際受 API quota 與系統資源限制（https://code.claude.com/docs/en/agent-view.md ）。
8. **時延**：官方無 per-spawn 時延數字；量級參考是 C compiler 案例（16 個並行實例、約 2,000 sessions、~$20,000；https://www.anthropic.com/engineering/building-c-compiler ）。

---

## 4. 既有模式比較

### 4.1 swarm-forge：handoff 是「被驗證的 commit」，不是敘述

來源：`/mnt/wsl/DWSLWSLSharedevsharedvhdx/swarm-forge/README.md`、`git show origin/two-pack:swarmforge/roles/coder.prompt`、`git show main:swarmforge/constitution/articles/handoffs.prompt`。

- **Coder 是獨立 agent、獨立 worktree**（startup「creates one git worktree per configured role under `.worktrees/`」），以 TDD 實作、commit、發 `git_handoff` 給 cleaner。
- **Handoff 物是 10 字元 commit SHA，由 helper 驗證**：「The commit abbreviation must be exactly 10 hexadecimal characters; `swarm_handoff.sh` validates that it resolves to a single commit and canonicalizes it」（README, Handoff Protocol）。SHA 甚至不是 agent 打的——「do not type a SHA」，helper 從 sender worktree 的 HEAD 填。**接收方 merge 該 commit，不讀 sender 的敘述**；敘述通道（note）被刻意餓死在 80 字元一行。
- **Audit gate**：第一次合法 git_handoff 回 `AUDIT_REQUIRED` 不入 queue，sender 必須整批重讀 task、trace 每個 requirement 到證據、修完再原封不動送第二次才放行——把「自我審查」做成協定步驟而非美德。
- **失敗回送**：`back-one` 是 merge-only copy（cleaner 的整理成果送回 coder 合併），「Merge-only copies […] do not move the card」——回饋以 git 狀態傳遞，不以對話傳遞。
- 對本題的啟示：**receiving role trusts the commit, not the sender's narration** 是可運作的成熟模式；orchestrator↔implementor 的 handoff 應該長這樣。

### 4.2 spec-kitty implement-review：orchestrator 永不碰程式碼

來源：`/home/madao/.claude/skills/spec-kitty-implement-review/SKILL.md`。

- Key Rules 第 6 條原文：「**The orchestrator does not implement** -- it dispatches and monitors」。
- **Dispatch 粒度是 work package（WP）**：claim workspace（建 worktree、產生 prompt file）→ 把 **workspace 路徑 + prompt file 路徑**交給 implementer subagent（`Task(subagent_type="general-purpose", …, run_in_background=True)`）。subagent 收到的是檔案路徑，不是 orchestrator 的對話。
- **Reviewer 是另一個 agent、對固定 diff 審**；rejection 走結構化回饋檔（`--review-feedback-file`），WP 退回 `planned`，re-dispatch 時 prompt file 已含回饋；**cycle 上限 3 次後進 arbiter mode**（approve with notes / escalate to human / accept and move on）。
- 平行紀律：claim 必須 sequential（動 git state），執行可全平行；「Parallel reviews are safe -- each WP operates in its own worktree」。
- 對本題的啟示：**prompt-file-as-handoff、rejection 有上限與升級路徑、orchestrator 只讀 state machine**——這是 rejection loop 的現成骨架。

### 4.3 old-coder：單 agent 原型假設了什麼

來源：`/home/madao/project/coder-gate-mesh/old-coder/skills/old-coder/SKILL.md`。

- 整條 `SPEC → RED → GREEN → REFACTOR → GAUNTLET → EVIDENCE` 由**同一個 context** 走完：寫測試、看它失敗、寫實作、跑 gauntlet、寫 EVIDENCE 的是同一人。它對「作者相關性」的唯一結構性破壞是**人類的 SPEC 核准**（「the one artifact that breaks the everything-authored-by-the-same-agent correlation」），Tier 3 再加 fresh-context verifier。
- 也就是說 old-coder 的信任模型從未依賴「implementor 的過程被第三方見證」——它依賴 spec 核准（事前）+ gauntlet（事後）+ verifier（事後、獨立）。**本 repo 的 verification-gate 已經把 old-coder 的事後半段改寫成「可以離作者很遠地跑」**（Acquisition 一節直接列了 subagent 場景），等於分離手術的下半身已經完成；本研究只是在問上半身（實作迴圈）能不能也搬出去，答案是機制上沒有剩餘阻礙。

---

## 5. 建議設計

### 5.1 角色切分

- **Orchestrator（main session）擁有**：Phase 1 SPEC、Phase 2 SPEC REVIEW（人類互動不可外包）、dispatch、Phase 4 invoke `verification-gate`（`gate` 迭代、`evidence` 最終一次）、Tier 3 verifier 調度、對人的最終交付。
- **Implementor subagent 擁有**：Phase 3 全部（per behavior 的 RED→GREEN→REFACTOR）、在自己 worktree 內 commit、回報一個 SHA。
- Orchestrator **永不編輯程式碼**（借 spec-kitty Key Rule 6），也**永不把 subagent 回報寫進任何證據artifact**（verification-gate 的 Never-from-the-conversation 規則）。

### 5.2 Dispatch 粒度

**Per work-package（一次 dispatch 涵蓋 spec 的一組相鄰 scenarios），內部強制 per-behavior commit cadence**——而不是 per-behavior dispatch：

- Per-behavior dispatch 的每輪固定成本（重讀 CLAUDE.md、spec、既有程式碼）乘上 behavior 數，總 token 失控且拿不到額外保證——保證來自 commit cadence，不來自 dispatch 邊界。
- Per-WP dispatch + per-behavior commits 讓 gate 仍能逐 behavior 讀 ordering 與 RED，等同 swarm-forge coder 的「own focused behavior slices」與 spec-kitty 的 WP 粒度。
- 相依 behaviors 進同一個 WP、循序；無共享檔案的 WPs 才考慮平行（各自 worktree，借 spec-kitty 的 lane 紀律：claim sequential、execute parallel）。

### 5.3 Subagent 的輸入（鏡射 verifier 的 four-inputs 紀律）

交給 implementor 的封包，全部是路徑與 ref，**絕不含 orchestrator 的對話**：

1. 已核准並 committed 的 **SPEC 路徑** + 本次負責的 scenario 清單；
2. **base ref** 與 worktree 路徑（`isolation: worktree` 或 SPEC Setup plan 宣告的隔離機制——workflow 的 Discipline notes 本來就要求「do not mutate the user's working tree」）;
3. 測試指令 / gate entry point 路徑；
4. commit cadence 指令（見 5.4）。

Rejection 輪再加：**gate 的失敗輸出原文**（git/檔案可讀的 artifact，非 orchestrator 轉述）。這與 verifier-protocol 的原則同構：「You are expected to know how to attack; you are not expected to know anything about this task the four items do not carry」——implementor 亦然，四件輸入之外它不需要也不該知道任何事。

### 5.4 Commit cadence：把 temporal 規則變成 git invariant

SPEC 模板的 Setup plan 已有欄位（`dot_agents/workflows/templates/spec.md`：「checkpoint commit cadence: <e.g. at spec approval and each GREEN/REFACTOR>」）。拆分模式下該欄位應宣告並由人核准：

```text
每 behavior：
  RED commit    — 只含新測試（與其 fixtures/stubs），訊息標 red(<scenario>)
  GREEN commit  — 只含實作，訊息標 green(<scenario>)
  REFACTOR      — impl-only 或 test-structure-only，永不混合
```

效果：

- 性質 2（ordering）逐 behavior 成為 git 事實；
- Anti-gaming rule 2 獲得一個機械檢查面：「range 內不存在同時觸碰 test 與 impl 的 commit（spec revision commits 除外）」——gate 或 evidence 可以列出違例；
- RED reconstruction 可以逐 behavior 對位（哪個測試在哪個 RED commit 進來、對 base 是否 fail）。

誠實註記：這是**提高造假成本**，不是證明——commit 順序可被事後編排（見 §2）。

### 5.5 Handoff 與 rejection loop

- **回程 handoff = commit SHA（+ branch 名）**。Orchestrator 收到後的動作不是「讀回報」而是「對該 SHA 跑 `gate`」——swarm-forge 的 trust-the-commit 模型。Subagent 的文字回報只作調度參考（例如「卡在 X」），永不入證據。
- **Gate 失敗 → 回送**：把失敗層的原文輸出 + 未變的 SPEC 交回 implementor。優先用 SendMessage **resume 同一個 subagent**（官方支援，脈絡還在、成本最低）；升級到 fresh dispatch 的時機是懷疑 implementor 已被自己的錯誤 anchoring。
- **上限與升級**：借 spec-kitty——3 輪後不再自動循環，orchestrator 升級為人類決策（arbiter：帶註記收下 / 退回 SPEC 修訂 / 換方法重做）。Cap 的意義同 verifier 的 two-round cap：「The cap does not limit the spending; it makes the spending someone's decision」。
- **SPEC 發現有錯時 implementor 不得自行修 spec**：停下、回報、由 orchestrator 走 Revisions + re-approval（workflow Phase 2：「A revision invalidates prior approval」）。鏡射 verifier 的「It fixes nothing」原則在 spec 維度的版本。

### 5.6 Worktree

要。三個既有理由疊加：官方一級支援（`isolation: worktree`）；workflow Discipline notes 的「do not mutate the user's working tree」；verifier 的 input-hygiene 論證（隔離副本「enforces "fixes nothing" by construction」——對 implementor 則是把爆炸半徑限制在 worktree）。注意 verification-gate 已載明的坑：「A fresh worktree contains no gitignored content」——dispatch 封包要含依賴重建指令，否則 implementor 的第一輪會浪費在環境考古。

---

## 6. 開放風險

1. **Commit 順序可偽造**（§2、§5.4）：per-step cadence 是威懾不是證明。可再加碼的方向：orchestrator 在收到每個 RED commit 時即刻（增量地）對 base 重放該 commit 的新測試——把 RED reconstruction 從一次性搬成逐 commit 的 check，縮短造假窗口；成本是每 behavior 一次 worktree 測試執行。
2. **Anti-gaming rule 2 的殘餘不可驗證性**：contract 原文已承認事後無法驗證；本設計把它壓縮到「需要主動偽造 commit 序列」的程度即為極限。
3. **同質性 / 作者相關性**：implementor 與 orchestrator 同 model，spec 的盲點兩者共享（Anthropic multiagent 研究的同名 branch 案例，https://www.anthropic.com/research/multiagent-systems ）。拆分**不是**獨立驗證，Tier 3 verifier 照舊必要。
4. **Token 經濟只在迴圈長時成立**：省 main context、花總 token（agent teams 的 ~7x 是上界錨點，https://code.claude.com/docs/en/costs.md ）。Tier 1、單 behavior、或 spec 本身還在震盪的任務，拆分是純虧損。
5. **人類互動的繞路**：implementor 無法直接問人（spec 疑義要 bounce 回 orchestrator → 人 → re-dispatch），每次繞路都是一輪 latency。Spec 寫得越可執行（concrete inputs/outputs），這條路徑觸發越少——這反而是對 Phase 1 品質的正向壓力。
6. **官方無 subagent 並行硬上限的正式數字**：平行多 WP 時的實際上限由 API quota 與檔案衝突決定（https://code.claude.com/docs/en/agent-view.md ）；平行的先決條件是 WP 間檔案不相交（spec-kitty 的 lane staleness 問題即是前車之鑑，見其 SKILL.md Troubleshooting「Lane staleness on merge」）。
7. **~7x 數字的適用範圍**：該數字官方語境是 agent teams（多實例、plan mode），不是單 implementor subagent——引用時勿當作本設計的成本預測，僅為量級上界。
