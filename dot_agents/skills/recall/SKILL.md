---
name: recall
description: >-
  從本機 Claude Code、Codex、Cursor 的 session 檔重建使用者最近的工作脈絡，
  回傳簡短的現況摘要 (目標、決策、未完成事項、下一步)。使用時機：使用者說
  「recall my work on X」、「catch me up」、「what was I working on」、
  「where did I leave off」、「我之前在做什麼」、「接續上次」、「上次做到哪」、
  「幫我回顧最近的工作」，或在開始或接續一項工作前需要先知道先前 session 的內容。
---

# Recall

從本機 session 檔抽出使用者的需求內容，整理成現況摘要。
所有資料只在本機讀取。不上傳任何內容。

## 流程

1. **鎖定範圍。** 先定三件事，再動手。
   - 視窗：預設最近 7 天。使用者說「全部」時用 `--days 0`。不要把「全部」偷偷縮成最近 N 天。
   - 專案：預設目前的 git 根目錄。使用者明說時才用 `--project <路徑>` 或 `--all`。
   - 主題：使用者有指名時加 `--grep <關鍵字>`，可重複。
   - 用一句話把範圍講回給使用者。
2. **跑腳本。** 腳本在本 skill 目錄的 `scripts/recall_sessions.py`。只用 Python 3 標準函式庫。

   ```sh
   python3 <skill-dir>/scripts/recall_sessions.py                      # 目前專案，近 7 天，三個來源
   python3 <skill-dir>/scripts/recall_sessions.py --days 30 --grep neovim
   python3 <skill-dir>/scripts/recall_sessions.py --source codex --all --format json
   ```

   輸出太長時先加 `--limit`、`--grep`，或改 `--format json` 再用工具篩。
3. **讀輸出。** 每個 session 一個區塊。
   - 跳過目前這個 session。它的內容就是現在這個請求。
   - 「使用者訊息」是需求的來源。「最後一則 assistant 文字」是該 session 結束時的狀態。
   - `ai-title` 是 Claude Code 產生的標題。用它快速分類，不要當成結論。
   - 一個 session 的最後一則使用者訊息沒有對應的完成回覆時，把它列為未完成事項。
4. **需要細節時讀原檔。** 輸出有每個 session 的檔案路徑。只讀相關區段。
   需要知道 agent 實際做了什麼 (跑了哪些工具、改了哪些檔) 時，讀原檔，不要只看摘要。
5. **回傳摘要。** 依下面的輸出格式。停在摘要，不要開始做事。

## 輸出格式

- **現況**：最多 5 條。這項工作是什麼，現在到哪裡。
- **決策**：已經定案的做法，每條一行。
- **未完成事項**：最多 5 條。
- **下一步**：一個具體動作。

每條引用來源與 session id 前 8 碼，例如 `[claude 5ac177cb]`。
沒有找到 session 時，直說沒有，並回報搜尋的範圍。

## 腳本參數

| 參數 | 說明 |
| --- | --- |
| `--source claude\|codex\|cursor\|all` | 來源，預設 `all` |
| `--project <路徑>` | 專案路徑，可重複；預設目前 git 根目錄或 cwd |
| `--all` | 不限專案 |
| `--days N` | 只看檔案 mtime 在最近 N 天內的 session；`0` 不限；預設 7 |
| `--grep <字串>` | 關鍵字過濾，可重複，不分大小寫，任一命中即保留 |
| `--format markdown\|json` | 輸出格式，預設 `markdown` |
| `--include-subagents` | 包含子代理 session |
| `--limit N` | 最多輸出幾個 session |
| `--max-messages N` | 每個 session 保留的使用者訊息數，超過時留頭尾 |
| `--claude-home` / `--codex-home` / `--cursor-home` | 覆寫來源目錄；預設讀 `CLAUDE_CONFIG_DIR`、`CODEX_HOME`、`~/.cursor` |

## 過濾規則

- 時間視窗用檔案 mtime，不用記錄內的時間戳。
- 子代理檔 (`subagents/agent-*.jsonl`) 與 `isSidechain` 記錄預設跳過。
- Claude Code 的 user 記錄含大量非使用者輸入的文字。腳本丟掉開頭是這些標籤的段落：
  `<command-message>`、`<command-args>`、`<local-command-caveat>`、
  `<local-command-stdout>`、`<task-notification>`、`<agent-message>`、`<system-reminder>`、
  `<tool-use-id>`、`<bash-stdout>`、`<bash-stderr>`，以及 `isMeta` 與 compact summary 記錄。
  黏在真正訊息後面的 `<system-reminder>` 段落會被剪掉，前面的文字保留。
- 含 `<command-name>` 的斜線指令段落還原成一則使用者訊息，例如 `/herdr <args>`。
  `<command-args>` 是使用者親手打的需求。args 為空時只留指令名稱。
- `<bash-input>` 與 `<pasted_content>` 是使用者親手的輸入，保留。
- 一次 assistant 回應在 Claude Code 會拆成多行並共用 `message.id`。回合數以它去重。

## 來源狀態

| 來源 | 路徑 | 狀態 |
| --- | --- | --- |
| Claude Code | `~/.claude/projects/<slug>/<sessionId>.jsonl` | 已在本機驗證 (2.1.278) |
| Codex | `$CODEX_HOME/sessions/**/rollout-*.jsonl`、`archived_sessions/` | 依 Codex 記錄格式實作，未在本機驗證 |
| Cursor | `~/.cursor/projects/<slug>/agent-transcripts/<uuid>/<uuid>.jsonl` | 只有路徑規則；欄位未驗證 |

Cursor 記錄格式對不上時，腳本不會當機。它輸出一條警告，列出實際看到的欄位。
把欄位回報給使用者，不要猜內容。
