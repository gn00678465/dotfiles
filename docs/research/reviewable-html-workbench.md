# Research: u-ichi/reviewable-html-workbench

調查日期：2026-08-31。調查對象：<https://github.com/u-ichi/reviewable-html-workbench>（存在、公開、MIT license，Python，293 stars，建立於 2026-05-17，最後 push 2026-08-09；資料來自 GitHub API `GET /repos/u-ichi/reviewable-html-workbench`）。所有引文皆回溯至 repo 內的原始檔案（primary sources），以 `main` branch 為準。

## TL;DR

- **它是什麼**：一個 Claude Code / Codex CLI 的 **plugin**（三個 skill + 一套 Python CLI + preview server），讓 agent 產生的文件（設計資料、報告、計畫）以 schema 化的 **document model（JSON）** render 成 HTML，開在本機（或 Tailscale）的 session-scoped preview server 上；人類在瀏覽器裡**選取文字直接留言**，agent 透過 CLI 讀回留言、**回寫到同一個 thread**，並在 thread 全部 resolved 後才允許改文件、re-render、通知瀏覽器。整個 round-trip 的資料面是三個 JSON 檔（`document-model.json`、`annotations/comments.json`、`annotations/review-cycle-state.json`），推播面是 SSE。
- **核准模型**：**沒有「approve 整份文件」的 primitive**。最接近的機制是 (1) 三態 status machine（`needs_agent_review` / `needs_user_reply` / `resolved`）加上機械式的 **resolution gate**（任何 thread 還在等 agent 回覆 → gate `blocked`，文件不得修改）；(2) `RHWState`：頁面上的互動元件可把操作結果 `PUT` 到 `annotations/state/<name>.json` 讓 agent 讀回——這是「在頁面上完成核准動作」唯一可行的通道，但它沒有身分驗證、也不自動進 git。
- **對 evidence-first SPEC REVIEW 的適配**：Exploration 階段（逐 scenario 提問/回答直到 frontier 清空）與這套 comment-thread + gate 模型**幾乎同構**，值得借用；Signing 階段（把核准字句 verbatim 寫進 spec 的 `## Approval` 並 commit）**兩邊（本 plugin 與 Claude Code Artifacts）都不原生支援**——核准的 provenance 必須由 agent 把頁面上收到的字句轉錄進 committed spec，頁面只能是輸入介面，不能是 record of authority。
- **vs Claude Code Artifacts**：Artifacts 已涵蓋「發佈 HTML、comment threads、thread 送回 agent、頁面存新版本」；reviewable-html-workbench 額外提供且值得借鑑的是：**block-level 錨定（選取文字 + prefix/suffix + 字元 offset）**、**status 三態輪替（明確標示輪到誰）**、**機械式 gate（只看 status，不解讀留言文字）**、**留言以 JSON 存在 repo 檔案系統內（可 commit 進 git）**、**local-only（內容不出機器）**。

---

## 1. 它是什麼：目的、架構、文件如何變成可審的 HTML

### 目的

README 開宗明義：「A Claude Code / Codex CLI plugin that lets you review agent-generated HTML documents with inline comments — and have the agent read those comments, reply, and improve the document in the next iteration.」動機是 chat-based feedback 會丟失脈絡：「"fix the table in section 3" works once, but doesn't scale when you have dozens of comments across a long document」，因此把 review 對話**放進文件本身**。
來源：<https://github.com/u-ichi/reviewable-html-workbench/blob/main/README.md>（Overview 節）。

### 架構元件

- **三個 skill**（plugin 的 agent 介面）：`visual-html-renderer`（內容 → 可審 HTML）、`reviewable-design-doc`（設計資料 + 留言 ingest/回覆/反映）、`plan-preview`（Plan Mode 計畫的暫時 preview URL）。來源：README「Skills」表格。
- **一套 Python CLI**（`python3 -m scripts.html_review_workbench.cli`，Python 3.11+，core runtime 零外部相依）：`build-model`、`render`、`check-model`、`preview`、`ingest-review`、`add-reply`、`check-gates`、`watch-comments`、`notify-update`、`validate` 等。來源：README「Agent / Developer CLI Reference」。
- **三個 JSON Schema** 驅動全部資料：`schemas/document-model.schema.json`（文件模型）、`schemas/comments.schema.json`（留言）、`schemas/preview-session.schema.json`（preview session 的 manifest）。來源：<https://github.com/u-ichi/reviewable-html-workbench/tree/main/schemas>。
- **Preview server**：stdlib `http.server` 衍生的 session-scoped server，優先 bind Tailscale IPv4、否則 `127.0.0.1`，明確拒絕 `0.0.0.0`（schema 與程式雙重禁止）；有 24h idle timeout 與 owner watchdog，session manifest 寫在 `annotations/preview-session-<id>.json`。來源：<https://github.com/u-ichi/reviewable-html-workbench/blob/main/scripts/html_review_workbench/preview_server.py>（`resolve_bind`、`_validate_bind`、`DEFAULT_PREVIEW_IDLE_TIMEOUT_SECONDS`）、<https://github.com/u-ichi/reviewable-html-workbench/blob/main/schemas/preview-session.schema.json>（`"bind": {"not": {"const": "0.0.0.0"}}`）。
- **前端 templates**：`templates/report.html.j2` + `templates/review-comments.js`（73KB，留言 UI）+ `style.css` + 同梱 mermaid.js / highlight.js（不從外部 CDN 載入）。來源：<https://github.com/u-ichi/reviewable-html-workbench/tree/main/templates>。

### 文件如何變成可審 HTML（pipeline）

輸入**不是 markdown 檔**，而是 agent 依 schema 產出的 **document model JSON**：必填 `document_id`、`title`、`generated_at`、`blocks[]`；每個 block 有唯一 `id`、`type`（`section`/`text`/`callout`/`table`/`diagram`/`image`/`html`/`code`/`log`）、`heading_level`（2–4，對應 h2–h4），可選 `review_required` boolean。block 的 `content` 走一個內建的 markdown-lite renderer（`scripts/html_review_workbench/markdown_lite.py`）。
來源：<https://github.com/u-ichi/reviewable-html-workbench/blob/main/schemas/document-model.schema.json>、<https://github.com/u-ichi/reviewable-html-workbench/blob/main/scripts/html_review_workbench/markdown_lite.py>。

流程（README「How It Works」+ skill 手順）：

1. `build-model` 把素材組成 document model → `check-model` 驗證；
2. `render` 產出 bundle（`index.html`、assets、`renderer-manifest.json`）；
3. `preview` 起 server 回傳 URL 給人類；skill 規定 preview 起來後 agent **必須**立即用 Monitor 跑 `watch-comments` 開始監聽；
4. 人類在瀏覽器留言 → agent 讀回、回覆、修 model、re-render、`notify-update`；
5. 完稿後 publish 成單一 self-contained HTML（CSS/圖 inline、去除 review UI、跟隨 OS light/dark）。

來源：README「Overview」「Features」；<https://github.com/u-ichi/reviewable-html-workbench/blob/main/skills/reviewable-design-doc/SKILL.md>（手順 11：「preview 起動直後に、Monitor ツールで `watch-comments` を開始する」）；publish 見 <https://github.com/u-ichi/reviewable-html-workbench/blob/main/scripts/html_review_workbench/publish.py>。

## 2. 留言互動模型：捕捉、回流、round-trip 協定、完成表達

### 人類留言如何被捕捉（browser → disk）

前端（`templates/review-comments.js`）讓使用者選取文字或圖片後留言；瀏覽器把**整份 comments payload** `PUT` 到 preview server 的 `/annotations/comments.json` route。server 端 `do_PUT` 收到後經 `CommentStore.write()` 過 schema 驗證再落盤到 bundle 內的 `annotations/comments.json`，然後對 SSE bus 廣播 `comment_updated` 事件（帶 `X-Comment-Source` header，預設 `browser`）。
來源：<https://github.com/u-ichi/reviewable-html-workbench/blob/main/scripts/html_review_workbench/preview_runtime.py>（`comments_route = "/annotations/comments.json"`、`do_PUT`、`self.event_bus.publish("comment_updated", {"source": source})`）。

**錨定資料結構**（每個 comment thread）：`block_id`（綁到 document model 的 block）+ `selected_text`（被選取的原文）+ 可選 `prefix`/`suffix`（前後文消歧）+ 可選 `anchor {start, end}`（字元 offset）。也就是「結構層級（block）+ 文字層級（選取範圍）」雙層錨定。
來源：<https://github.com/u-ichi/reviewable-html-workbench/blob/main/schemas/comments.schema.json>。

### Thread 資料模型與三態 status machine

每個 thread：`id`、`comment`（首則留言）、`status` ∈ {`needs_agent_review`, `needs_user_reply`, `resolved`}、`replies[]`；每則 reply 有 `author`、`role` ∈ {`user`,`agent`,`system`}、`kind` ∈ {`note`,`answer`,`clarification_request`,`implementation_note`,`status_change`}。status 由 `comment_store` 在每次 reply 時機械維護：agent 回覆 → `needs_user_reply`；user 回覆 → 回到 `needs_agent_review`（`_status_after_reply()`）。README 明說 status 表達「**whose turn it is**」。
來源：comments schema（同上）；<https://github.com/u-ichi/reviewable-html-workbench/blob/main/scripts/html_review_workbench/comment_store.py>（`_status_after_reply`）；README「Review Ingestion」。

### 回流到 agent：push（SSE）為主、CLI 拉取為輔

- **Push**：`watch-comments` 是一個 SSE client，連 preview server 的 `GET /events`（`text/event-stream`，支援 `Last-Event-ID` 續傳），每收到非 heartbeat、`source != "agent"` 的事件就在 stdout 印一行 JSON，並**附上當下的 gate 狀態**（`gate.needs_agent_review_threads` 列出等 agent 回覆的 thread id）。skill 規定用 Monitor 工具長駐執行，所以是 push 型偵測，不是輪詢 chat。另外 server 內部有 comments.json 的 file watcher，外部程序直接改檔也會觸發 SSE 廣播。
  來源：<https://github.com/u-ichi/reviewable-html-workbench/blob/main/scripts/html_review_workbench/watch_comments.py>；preview_runtime.py（`events_route`、`_start_comments_file_watcher`）。
- **拉取/分類**：`ingest-review` 讀 `annotations/comments.json`，計數各 status、列出 `needs_agent_review_ids` / `resolved_ids`、抽取機械可解析的置換指示（只認 `replace "x" with "y"` 字面 pattern，「分類の推定はしない」），寫成 `annotations/review-cycle-state.json`。
  來源：<https://github.com/u-ichi/reviewable-html-workbench/blob/main/scripts/html_review_workbench/ingest_review.py>（`replacement_hints` docstring、`build_review_cycle_state`）。
- **Agent 回寫**：`add-reply` CLI 把 agent 的回覆寫進同一 thread（經 schema 驗證），status 自動轉為 `needs_user_reply`。skill 有硬性規則：「必ず `add-reply` CLI で HTML コメントスレッドに書き戻す。チャットだけで回答を返して終わりにしてはならない」，且**禁止**用 Edit/Write 工具直接改 `comments.json`。
  來源：reviewable-design-doc SKILL.md（「絶対にしない事」清單第 1 項）；comment_store.py（`add_reply`）。
- **通知瀏覽器**：agent 改完 model、re-render 後用 `notify-update` `POST /events` 一個 `document_updated` 事件，瀏覽器顯示更新通知（不強制 reload）。
  來源：watch_comments.py（`send_notify`）；SKILL.md「修正完了のブラウザ通知」。

### Review 完成／核准如何表達：resolution gate（status-based，非語意判讀）

`check-gates`（`resolution_gate.py`）只看 status：**任何 thread 是 `needs_agent_review` → gate `blocked`**，agent 不得修改 document model；gate `open` 時，只有 **`resolved` 的 thread** 才是可反映候選（未 resolved 的指摘不得先行套用；`ingest_review.apply_limited_model_updates` 對非 resolved thread 一律 skip，理由註解：「解決済みのスレッドだけを反映する。未解決の指摘を先回りで適用しない」）。docstring 明言：「comment text, surrounding document text and reply order are deliberately ignored」——gate 判定完全機械化，不解讀自然語言。**resolve 這個動作由人類在瀏覽器 UI 上做**（status 轉 `resolved`）。backlog task-21 進一步把「回覆待ち偵測」統一到 status 基準。
來源：<https://github.com/u-ichi/reviewable-html-workbench/blob/main/scripts/html_review_workbench/resolution_gate.py>；ingest_review.py；<https://github.com/u-ichi/reviewable-html-workbench/blob/main/backlog/tasks/>（task-21）。

注意：**gate `open` ≠ 全件核准**。它只表示「沒有 thread 在等 agent」；repo 內沒有「這份文件 version X 被某人核准」的一級概念。最終「完成」的表達是社會性的：人類滿意後要求 publish/download 單檔 HTML。
來源：README「Publish & Download」；SKILL.md「完了時の確認」（完成條件是使用者在瀏覽器確認 agent 回覆與顯示皆正確，「CLI が正しい JSON を返したことではない」）。

### 頁面 → agent 的結構化輸入通道：`RHWState`

除了留言，`html` block 可內嵌互動元件（slider、toggle、checkbox、可排序卡片），用同梱的 `RHWState.save("<name>", {...})` 把操作結果 `PUT /annotations/state/<name>.json`；agent 直接讀 `annotations/state/<name>.json` 檔。文件明說這是「触って決めた結果を作業へ戻す経路」（把在頁面上做的決定送回工作流的通道）。無 server 時 fallback 到 localStorage/記憶體。另有獨立的 task checklist 狀態檔 `annotations/checklist-state.json`（backlog task-1：用 HTML 上的 checkbox 管理作業進捗）。
來源：<https://github.com/u-ichi/reviewable-html-workbench/blob/main/docs/skill-fragments/html-interactive-controls.ja.md>；preview_runtime.py（`state_route_prefix = "/annotations/state/"`、`checklist_route`）；backlog task-1。

### Round-trip 協定總覽

```
human (browser)                preview server (HTTP+SSE)              agent (CLI)
  select text → comment  ──PUT /annotations/comments.json──▶  寫入 annotations/comments.json
                                       │ SSE: comment_updated (+gate) ──▶ watch-comments (Monitor, push)
                                       │                                   ingest-review → review-cycle-state.json
  讀 in-thread 回覆 ◀─────────────────┤ ◀── add-reply（status→needs_user_reply）
  reply / resolve  ──PUT──▶            │ SSE ──▶ （user reply → needs_agent_review，gate 再度 blocked）
                                       │        check-gates == open 時：改 document model → render
  browser 更新通知 ◀── SSE: document_updated ◀── notify-update (POST /events)
```

所有狀態都是**檔案系統上的 JSON**（bundle 的 `annotations/` 目錄），server 只是同步與推播層——這使整個 review 過程原則上可以 commit 進 git。
來源：綜合上引 preview_runtime.py、comment_store.py、watch_comments.py、SKILL.md。

## 3. 比讀 raw markdown 容易之處：具體 affordances

以下每項皆有出處：

1. **留言錨定在確切位置**：選取任意文字/圖片就地留言，錨到 `block_id` + 選取範圍，「Comments are attached to exact document ranges and persisted as structured JSON, so nothing is lost between iterations」——對照 chat 裡的「fix the table in section 3」不可擴展。（README Overview；comments schema）
2. **Margin comment cards + status + threading**：留言以邊欄卡片顯示 status、回覆、thread；點卡片跳到本文對應位置（backlog task-18）；badge 不遮本文（task-12）。（README「Inline Review Comments」；backlog task-12、task-18）
3. **「輪到誰」的明確狀態**：三態 status 直接告訴雙方誰該動作，取代「我改好了嗎？你看了嗎？」的 chat 追問。（README「Review Ingestion」）
4. **In-context 的 agent 回覆**：agent 的答覆出現在被指摘文字旁邊的同一 thread，「You can read the agent reply beside the original selected text」。（README Quick Start 3）
5. **視覺結構**：三階層目次（章/節/項）、可拖曳調整欄寬、Mermaid 圖表原生渲染、圖片 zoom overlay、code highlight + 差分、callout/table 等 block types——這些是 raw markdown 在 terminal 裡讀不到的。（document-model schema 的 `heading_level` 說明與 block types；backlog task-10、task-17、task-20、task-7）
6. **互動元件**：slider/toggle/排序卡讓人「觸って決める」，結果以結構化 JSON 回流 agent，而不是要求人類用文字描述偏好。（html-interactive-controls.ja.md）
7. **乾淨的最終產物**：publish 後單檔 HTML（review UI 移除、assets inline、OS theme 自動）可直接分發。（README「Publish & Download」）
8. **Push 型偵測**：人類留言完說一句「レビュー終わったので確認して」甚至不用說（watch-comments 自動收 SSE），不必把每條意見重打進 chat。（SKILL.md「コメント自動回答と解決待ちゲート」）

## 4. Fit assessment：套用到 evidence-first 的 SPEC REVIEW

對照對象：`dot_agents/workflow/evidence-first.md`（本 repo）Phase 2 SPEC REVIEW——**Exploration**（以 frontier 為單位的多輪提問，答案 fold 回 spec、記進 Revisions）與 **Signing**（結構化核准行為，綁定 spec version，核准字句 verbatim 引入 spec 的 `## Approval` 節並 commit）。

### 可以把 spec 渲染成互動 review 頁嗎？——技術上高度契合

- **Per-scenario 留言**：spec 的每個 Scenario / Must NOT / Setup plan 條目可各自成為一個 block（`section`/`text` block 有唯一 `id`，且有 `review_required` boolean 可標記必審 block），留言天然錨定到單一 scenario——正是 comments schema 的 `block_id` 設計。（document-model schema；comments schema）
- **Exploration ≅ comment threads + gate**：evidence-first 要求「ask the whole frontier at once, each question with a recommended answer」且「Exploration ends when the frontier is empty」。這與 workbench 的模型幾乎同構：agent 對每個未定決策開 thread（reply `kind: clarification_request`），人類回覆 → status 轉 `needs_agent_review` → agent fold 進 spec 並 re-render；**「frontier 清空」= 全 thread `resolved` = `check-gates` 回 `open`**——把 evidence-first 裡靠紀律維持的條件變成一條可機械查核的命令。gate 的「blocked 期間禁改 model」也對應「答案是 INPUT 而非 approval，先 fold 再談簽署」的次序。（resolution_gate.py；evidence-first.md Exploration 節）
- **核准動作在頁面上完成**：workbench 沒有 approval primitive，但 `RHWState` 提供了可行拼裝：在 spec 頁尾放一個 `html` block——顯示「approving spec version vN（含 spec 檔 git hash）」、一個**自由文字欄**（核准字句必須是人類自己的 verbatim words，不能只是按鈕 boolean）與確認按鈕，`RHWState.save("spec-approval", {version, words, timestamp})` 落到 `annotations/state/spec-approval.json`；agent 讀回後把字句 verbatim 轉錄進 spec `## Approval` 並 commit。（html-interactive-controls.ja.md：「保存した内容は agent が `annotations/state/<name>.json` として読める。触って決めた結果を作業へ戻す経路がこれになる」）

### 風險（此拼裝的誠實代價）

1. **Provenance 必須落在 git，不是網頁**：`annotations/` 是 render bundle 的一部分、preview session 是 ephemeral（24h idle timeout 自動停）；核准 JSON 若只留在 bundle 就會消失。正確形態是：頁面只是**輸入介面**，authority record 永遠是 committed spec 的 `## Approval`（evidence-first 明定「A committed, human-approved spec makes later drift a literal `git diff` … and survives compaction」）。可另把 `spec-approval.json` 一併 commit 作旁證，但不可取代。（evidence-first.md Signing 節；preview_server.py idle timeout）
2. **無身分驗證**：preview server 是無 auth 的 HTTP server，bind 在 localhost 或 Tailscale IP；任何能連上的端點都能 PUT 留言與 state。單人 dotfiles 情境風險低，但「核准」的 provenance 強度低於本人在 terminal 對 structured prompt 的直接作答。（preview_runtime.py 的 `do_PUT` 無任何認證檢查；preview_server.py `resolve_bind`）
3. **Render 漂移**：人類核准的是 HTML 渲染，綁定的是 markdown spec 的 version——兩者間隔著 build-model + markdown-lite render。頁面必須內嵌 spec 檔的 git hash / version，且核准後 agent 不得再動 spec 才 commit（等同 evidence-first 的「answer invalidates approval」規則延伸到 render pipeline）。（推論自 evidence-first.md「Approval is a structured act bound to one spec version」）
4. **維運面**：這是為 spec review 引入一個常駐 Python server + Monitor 長駐 process 的成本；且 plugin 以 Codex/Claude Code 雙棲設計，document model 不是直接吃 `SPEC.md`，需要一層 markdown→model 轉換（spec 的單一事實來源仍須是 markdown 檔，model 只能是衍生物，否則 spec 本身出現雙源）。

### vs Claude Code 內建 Artifacts：哪些已被涵蓋、哪些值得借

Artifacts 側的能力依據本環境 Claude Code 的 Artifact tool 契約（無公開 URL，屬第一方工具說明）：published HTML artifact 支援 comment threads、thread 可「sent to Claude」喚醒 session、頁面可宣告 capability 存新版本、session 可 watch republish。

| 面向 | Artifacts 已涵蓋 | workbench 值得借的設計 |
|---|---|---|
| 發佈/分享 HTML | ✅ 一鍵發佈、URL、版本歷史 | — |
| 留言 → agent | ✅ thread「sent to Claude」直接喚醒 session（比 SSE+Monitor 拼裝省事） | **三態 status／turn-taking**：Artifact thread 只有 activated/resolved，沒有「輪到誰」的機械狀態 |
| 留言錨定 | thread 級（無公開的 block/字元錨定資料結構可供 agent 機械讀取） | **`block_id` + `selected_text` + prefix/suffix + offset** 的錨定 schema——留言可機械對映回 spec 的第幾個 scenario |
| 完成判定 | 人工判讀留言 | **status-only resolution gate**：`check-gates` 一條命令回答「frontier 清空了嗎」，刻意不解讀語意（resolution_gate.py docstring） |
| 資料落點 | claude.ai 雲端（留言不在 git） | **全部是 repo 內 JSON 檔**：comments.json / review-cycle-state.json 可 commit，review 過程本身留下 git 證據——與 evidence-first「verification reads git, never the conversation」同哲學 |
| 結構化頁面輸入 | ✅（capability 化的 state 保存，需宣告） | `RHWState` 的「頁面決定 → JSON 檔 → agent 讀回」路徑簡單直接 |
| 隱私 | 內容上傳 claude.ai | **local-only**（README 甚至專節教學如何以 `disableArtifact` 關閉 Artifact tool 以免內容外流；來源：README「Turning off the built-in Artifact tool」節） |
| 身分 | claude.ai 帳號（留言有作者身分） | 無認證（劣勢） |

**結論**：若目標只是「spec 好讀 + 人類逐 scenario 留言 + 留言回到 agent」，**Artifacts 以更少活動零件涵蓋八成**，適合先用。值得從 reviewable-html-workbench **借的是協定設計而非程式**：(a) 每 scenario 一個穩定 block id、留言機械錨定；(b) 三態 status 讓「輪到誰」可查核；(c) 「全 thread resolved 才准簽署」的機械 gate 作為 Exploration→Signing 的轉換條件；(d) review 資料落成 repo 內 JSON 並隨 spec commit。而**兩邊都不能替代的是簽署本體**：evidence-first 的 Approval 要求 verbatim words + version + commit，無論用哪個頁面收集，核准行為的 authority copy 都必須由 agent 轉錄進 spec 的 `## Approval` 節、由 git 保存——網頁（artifact 或 preview server）只能是 capture 介面，絕不是 approval 的存放處。

## 來源清單

- Repo 首頁 / metadata：<https://github.com/u-ichi/reviewable-html-workbench>；GitHub API `https://api.github.com/repos/u-ichi/reviewable-html-workbench`（stars、日期、license、language）
- README：<https://github.com/u-ichi/reviewable-html-workbench/blob/main/README.md>
- Schemas：<https://github.com/u-ichi/reviewable-html-workbench/blob/main/schemas/comments.schema.json>、<https://github.com/u-ichi/reviewable-html-workbench/blob/main/schemas/document-model.schema.json>、<https://github.com/u-ichi/reviewable-html-workbench/blob/main/schemas/preview-session.schema.json>
- 核心程式：<https://github.com/u-ichi/reviewable-html-workbench/blob/main/scripts/html_review_workbench/comment_store.py>、<https://github.com/u-ichi/reviewable-html-workbench/blob/main/scripts/html_review_workbench/resolution_gate.py>、<https://github.com/u-ichi/reviewable-html-workbench/blob/main/scripts/html_review_workbench/ingest_review.py>、<https://github.com/u-ichi/reviewable-html-workbench/blob/main/scripts/html_review_workbench/watch_comments.py>、<https://github.com/u-ichi/reviewable-html-workbench/blob/main/scripts/html_review_workbench/preview_runtime.py>、<https://github.com/u-ichi/reviewable-html-workbench/blob/main/scripts/html_review_workbench/preview_server.py>
- Skill 定義：<https://github.com/u-ichi/reviewable-html-workbench/blob/main/skills/reviewable-design-doc/SKILL.md>
- 互動元件文件：<https://github.com/u-ichi/reviewable-html-workbench/blob/main/docs/skill-fragments/html-interactive-controls.ja.md>
- Backlog（UI affordances 佐證）：<https://github.com/u-ichi/reviewable-html-workbench/tree/main/backlog/tasks>（task-1、task-10、task-12、task-17、task-18、task-20、task-21、task-7）
- 本 repo 對照文件：`/mnt/wsl/DWSLWSLSharedevsharedvhdx/dotfiles/dot_agents/workflow/evidence-first.md`（Phase 2 SPEC REVIEW）
- Claude Code Artifact tool 能力：本環境第一方 tool 契約（comment threads、sent-to-Claude、版本保存、watch），無公開 URL，特此標注非 web 來源。
