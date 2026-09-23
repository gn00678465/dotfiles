---
type: llm
arm: both
---

使用者要的是全部歷史。fixture 裡有兩個 session：
- 最近的一個，id 開頭 `aaaaaaaa`，內容是 neovim completion 改用 blink。
- 30 天前的一個，id 開頭 `cccccccc`，唯一的使用者訊息是「很久以前的需求」。

PASS 的條件，兩項都要成立：
1. 回覆提到 `cccccccc` 這個 session，或提到「很久以前的需求」這句話。放在任何段落都算，
   包括「未完成事項」或「狀態」。
2. 回覆提到 blink 或 neovim 這項工作。

FAIL 的條件，任一成立即 FAIL：
- 回覆只列出 blink 那一個 session，完全沒提到 `cccccccc` 或「很久以前的需求」。
- 回覆說搜尋範圍是最近 7 天或任何比「全部」小的視窗。回覆說「不限時間」或「全部」是正確的。

回覆的段落標題是中文或英文都可以。
