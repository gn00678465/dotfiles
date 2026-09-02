# codex 設定改寫器：逐行改寫會把合法 TOML 改成不合法

Status: needs-triage
Origin: feat/windows-support 獨立驗證第三輪 F3（`.scratch/windows-support/evidence.md`）

## 問題

`dot_codex/modify_private_config.toml`（main 上是 `sh`+`awk` 版，`feat/windows-support`
移植為 modify-template）逐行改寫 `~/.codex/config.toml`，前提是受管的 key
各佔一行、寫成 bare key、且所在表頭是單純的 `[tui]`。合法 TOML 若不符這三個
前提，輸出就不是合法 TOML。

已知會踩到的形狀（不是窮舉，第五種是前四種寫成「完整清單」之後才被找到的）：

| 輸入形狀 | 結果 |
|---|---|
| `status_line` 排成多行陣列 | 續行變孤兒，輸出不是合法 TOML |
| `[[tui]]` | `tui` 被宣告兩次 |
| `["tui"]` | 同上 |
| `tui = { ... }` inline table | 同上 |
| `"status_line" = ...` 加引號的 key | 引號版與 bare 版並存，`Cannot overwrite a value` |

第一種最可能發生：受管的 `status_line` 本身就是八元素陣列，任何 formatter
把它換行排版就會觸發。

## 為什麼還沒修

- 五種形狀在移植前的 awk 版就存在，移植後逐位元組相同，是沿用的既有行為。
- 修它會改變 POSIX 端輸出，撞 `feat/windows-support` SPEC 的 Must NOT #2，
  所以那條分支明確不修，只把形狀釘進 `tools/gate-properties.py` 的
  `KNOWN_LIMITATION`，驗「與 awk 原版一致」。

## 修法方向

逐行改寫的三個前提本身就是問題。可行的路是不再逐行：用 chezmoi 的
`fromToml` / `toToml` 解析整份檔案、改受管的 key、再序列化。代價是輸出的
排版與註解可能不保留，需要先確認使用者接受這點。

## 完成條件

- 上表五種形狀各有一個 golden case，輸出經 TOML parser 驗證合法且受管 key 值正確。
- `KNOWN_LIMITATION` 清空或改成回歸案例。
- 研究筆記 §11.5 與 AGENTS.md 對應段落更新。

## 參考

- `docs/research/windows-native-support.md` §11.5（feat/windows-support）
- `tools/gate-properties.py` `KNOWN_LIMITATION`（feat/windows-support）
- `.scratch/windows-support/evidence.md` F3
