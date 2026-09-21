# 通用 Anti-AI-Slop Skill 設計研究

目的：設計一個獨立的、通用的 anti-AI-slop skill，可套用在任何散文產出上。
與 SPEC 可讀性無關——那是 playbook 和模板的責任。

## 1. 現有 skill 已覆蓋什麼

### unslop（pstack, 33 條規則）

完整規則清單：

| 編號 | 類別 | 規則 |
|---|---|---|
| 3 | Content | 空洞的 -ing 短語（highlighting, ensuring, showcasing...） |
| 5 | Content | 模糊歸因（Experts believe, Industry reports suggest） |
| 7 | Language | AI 詞彙清單（delve, enhance, pivotal, tapestry, vibrant...） |
| 8 | Language | 花式 is（serves as, stands as, boasts, features） |
| 9 | Language | Not just X, but Y 句型 |
| 10 | Language | 強迫三項一組 |
| 11 | Language | 同義詞輪替 |
| 12 | Language | 虛假範圍（from X to Y） |
| 13 | Style | 長破折號濫用 |
| 14 | Style | 冒號當連接詞 |
| 15 | Style | 粗體濫用 |
| 16 | Style | 粗體標籤＋冒號重述內容 |
| 17 | Style | 標題用 Title Case |
| 18 | Style | 裝飾性表情符號 |
| 19 | Style | 彎引號 |
| 20 | Chatbot | 聊天機器人語氣（I hope this helps, Let me know if...） |
| 22 | Chatbot | 奉承語氣（Great question!） |
| 23 | Filler | 填充短語（In order to, Due to the fact that...） |
| 24 | Filler | 過度避險（could potentially possibly...） |
| 25 | Filler | 空洞結論（The future looks bright） |
| 26 | Jargon | 抽象隱喻名詞（substrate, wedge, nexus, paradigm...） |
| 27 | Plain | 說機制不說感覺 |
| 28 | Plain | 拆分密句 |
| 29 | Plain | 主動語態 |
| 30 | Plain | 砍副詞或換更強的動詞 |
| 31 | Plain | 用簡單的詞 |
| 32 | Plain | 矯揉造作的散文 |
| 33 | Plain | 過度壓縮 |

unslop 的優勢：規則精確，每條帶偵測模式和修正方式。穩定編號讓其他 skill 引用。

### technical-writing（pstack, 四層）

- Diátaxis：文件分四種模式（tutorial, how-to, reference, explanation）
- Google developer style：對讀者說 you，指令用祈使句，條件在指令前
- STE：一句一個想法，指令句 ≤20 詞，描述句 ≤25 詞
- Global English：消歧義（only 的位置、noun string、代詞指向）

覆蓋範圍：文件、RFC、readme、PR 描述、commit 訊息。

### writing-for-agents（mattpocock-skills）

不是 anti-slop skill。是 agent 文件的結構設計指南：context pointer、
information hierarchy、progressive disclosure、completion criteria、
leading words、pruning（single source of truth、不重述環境、刪 no-op 句子）。

### 使用者的 CLAUDE.md 寫作規則

兩條：
1. 用繁體中文寫，遵循 ASD-STE100，用 zhtw-mcp 查不確定的台灣用語
2. 刪除所有矯揉造作的散文

### deslop（cursor-team-kit）

未安裝。處理程式碼 diff 的 slop（敘事性註解、無依據的防禦性代碼）。

## 2. 缺口：unslop 不覆蓋什麼

### 2.1 繁體中文特有的 AI slop

| 中文 slop 模式 | 例子 | 修正 |
|---|---|---|
| 「值得注意的是」系列 | 「值得注意的是，這個函式會回傳 null」 | 「這個函式回傳 null」 |
| 「進行 X」代替動詞 | 「進行測試」「進行修改」 | 「測試」「修改」 |
| 「相關的」「相應的」空洞修飾 | 「修改相關的設定檔」 | 「修改設定檔」 |
| 「的」字鏈 | 「使用者的帳號的設定的頁面」 | 「使用者帳號設定頁面」 |
| 「確保 X 被 Y」被動化 | 「確保所有測試通過」 | 「跑測試，全部通過才繼續」 |
| 句末總結陳詞 | 「這樣就完成了基本的設定。」 | 刪掉整句 |
| 敬語填充 | 「建議可以考慮使用」 | 「用」 |
| 「透過 X 來 Y」迂迴 | 「透過修改設定檔來調整行為」 | 「改設定檔」 |
| 「在 X 的情況下」冗長 | 「在沒有安裝的情況下」 | 「沒裝時」 |
| 列舉尾的「等」 | 已列完卻加「等」 | 刪掉「等」 |

### 2.2 ASD-STE100 中文適配

| STE 英文規則 | 中文適配 |
|---|---|
| 指令句 ≤20 詞 | 指令句 ≤30 字 |
| 描述句 ≤25 詞 | 描述句 ≤40 字 |
| 一句一個想法 | 同。中文更容易用逗號串連，需要主動斷句 |
| 主動語態 | 偵測「被」字句和「確保 X 被 Y」 |
| 用簡單的詞 | 「使用」→「用」、「進行」→ 刪除 |

### 2.3 Coding agent 特有的模式

| 模式 | 例子 | 修正 |
|---|---|---|
| 敘述自己的過程 | 「首先我會分析，然後找根因，接著修正」 | 直接做，不敘述 |
| 過度解釋程式碼 | 用散文重述每一步 | 只說程式碼看不出來的事 |
| 防禦性免責 | 「可能不適用於所有情況」 | 寫出具體限制，或刪掉 |
| 重複使用者的問題 | 「你問的是 X。X 是…」 | 直接回答 |
| 列舉後總結 | 「以上就是需要修改的五個地方。」 | 刪掉總結句 |

## 3. 與 unslop 的關係

**獨立運作，可與 unslop 組合。**

- unslop 是 pstack 的 plugin，不一定安裝
- 新 skill 不複製 unslop 的 33 條規則
- 有 pstack 時：先 `/unslop` 再 `/clear-text`
- 沒 pstack 時：`/clear-text` 獨立覆蓋 agent 模式和中文模式

## 4. 完整 SKILL.md 草稿

```markdown
---
name: clear-text
description: >-
  Remove AI writing patterns from any prose output. Covers agent narration,
  Chinese-specific filler, and ASD-STE100 sentence discipline for Traditional
  Chinese. Works standalone; composes with /unslop when pstack is installed.
  Use after writing any prose the human will read, or as a review pass on
  existing documents.
---

# Clear Text

Scan prose for AI tells, rewrite them, then self-audit. Three groups of rules:
general agent patterns, Traditional Chinese patterns, and sentence discipline.

## When to use

- After writing any prose a human will read.
- As a review pass on existing documents.
- Before sending a document for human review.

When pstack is installed, run /unslop first (it owns the 33-rule English slop
catalog), then this skill. Without pstack, this skill covers agent and Chinese
patterns on its own.

## Process

1. Read the target text.
2. Apply each rule below. Rewrite in place. Preserve meaning.
3. Self-audit: read the result as a human would. If any sentence sounds like
   an AI wrote it, find the pattern and fix it.
4. Measure: count sentences over the length limit. Zero is the target.

## General agent patterns

1. **No process narration.** Delete sentences that describe what you will do
   or just did. The reader wants the result.
   - Before: 「首先我會分析目前的狀態，然後找出根因，接著提出修正。」
   - After: (deleted; write the analysis directly)

2. **No question echo.** Start from the answer.
   - Before: 「你問的是如何設定 X。要設定 X，編輯 config.yaml。」
   - After: 「編輯 config.yaml。」

3. **No post-list summary.** The reader just read the list.
   - Before: 「…第五項。以上就是需要修改的五個地方。」
   - After: 「…第五項。」

4. **No vague disclaimers.** Name the specific limitation or delete.
   - Before: 「這個方案可能不適用於所有情況。」
   - After: 「輸入超過 2GB 時會失敗。」(or deleted)

5. **No code paraphrasing.** Only say what the code cannot show.
   - Before: 「這段程式碼讀取設定檔，解析 JSON，存入變數。」
   - After: (deleted; the code says this)

6. **No transition filler.** Headings do this job.
   - Before: 「接下來讓我們看看第二部分。」
   - After: (deleted)

7. **No value judgments without evidence.** Name the benefit or delete.
   - Before: 「這個設計非常優雅！」
   - After: 「省掉中間複製，記憶體用量減半。」

## Traditional Chinese patterns

8. **Delete「值得注意的是」and siblings.**
   「需要特別說明的是」「需要強調的是」「有趣的是」
   - Before: 「值得注意的是，這個函式會回傳 null。」
   - After: 「這個函式回傳 null。」

9. **Replace「進行 X」with the verb.**
   - Before: 「進行測試」「進行修改」「進行部署」
   - After: 「測試」「修改」「部署」

10. **Cut hedging politeness.** Instructions use imperatives.
    - Before: 「建議可以考慮使用 X」
    - After: 「用 X」

11. **Break「的」chains.** Three or more consecutive 的: split the sentence
    or remove unnecessary 的.
    - Before: 「使用者的帳號的設定的頁面」
    - After: 「使用者帳號設定頁面」

12. **Flatten「透過 X 來 Y」.** The point is Y.
    - Before: 「透過修改設定檔來調整行為」
    - After: 「改設定檔」

13. **Shorten「在 X 的情況下」.**
    - Before: 「在沒有安裝的情況下」
    - After: 「沒裝時」

14. **Drop trailing「等」after a complete list.**
    - Before: 「測試、lint、型別檢查等」(when complete)
    - After: 「測試、lint、型別檢查」

15. **Delete closing summaries.**
    - Before: 「這樣就完成了基本的設定。」
    - After: (deleted)

## Sentence discipline (ASD-STE100 for Traditional Chinese)

16. **One thought per sentence.** A comma is not a period. More than two
    commas: split.

17. **Length limits.** Imperatives: 30 characters. Descriptions: 40 characters.
    Over the limit: split.

18. **Imperatives for instructions.** 「應該 X」becomes「X」.
    「需要 X」becomes「X」.

19. **Active voice.** 「被 X」becomes the actor doing X.
    「確保 X 被 Y」becomes「Y X」.

20. **Explicit actor.** When the subject is omitted, the actor must be
    unambiguous. If ambiguous, name it.

21. **Mixed-language rule.** English for terms, commands, file paths, API
    names, identifiers. Traditional Chinese for everything else.
```

## 5. 命名

`clear-text`。描述職責，不綁定工作流，不和 pstack 的 skill 混淆。

## 6. 調用方式

- 手動：`/clear-text`
- Playbook 步驟：任何 playbook 在產出散文後呼叫
- 和 unslop 組合：有 pstack → `/unslop` 先，`/clear-text` 後。沒有 → 獨立

## 7. 不做的事

- 不處理程式碼（deslop / no-comments 的事）
- 不處理文件結構（technical-writing / writing-for-agents 的事）
- 不複製 unslop 的 33 條英文規則（組合，不複製）
- 不強制特定的文件格式或模板（playbook 的事）
- 不決定 SPEC 該有哪些欄位（old-coder playbook 的事）
