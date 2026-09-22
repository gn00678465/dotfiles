---
type: llm
arm: both
---

使用者要的是全部歷史。fixture 裡有兩個 session：一個最近的 (neovim completion 改用 blink)，
一個 30 天前的，唯一的使用者訊息是「很久以前的需求」。

PASS 的條件：回覆同時提到這兩個 session 的內容，而且沒有把範圍縮成「最近 7 天」或
任何比「全部」小的視窗。回覆若說只找到最近的一個、或只列出 blink 那一個，就 FAIL。
