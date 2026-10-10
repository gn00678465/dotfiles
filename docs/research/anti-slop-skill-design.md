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

## 8. 第一手來源查核：Karpathy 貼文與 ASD-STE100 Issue 9

查核日期：2026-10-10。用途：決定 `.chezmoitemplates/agent-instructions.md`
的 Writing 規則是否移到 `dot_agents/skills/anti-slop/SKILL.md`。
本節只記錄來源和比對，不改這兩個檔案。

### 8.1 來源和取得方式

| 來源 | 版本或日期 | 取得方式 | 狀態 |
|---|---|---|---|
| Karpathy 貼文 <https://x.com/karpathy/status/2105819303471976479> | 2026-10-02 00:37 UTC | `x.com` 回 HTTP 402，無法直接讀取 | 未直接讀取 |
| X 的 syndication 端點 <https://cdn.syndication.twimg.com/tweet-result?id=2105819303471976479&token=a> | 同上 | curl，讀 JSON | 第一手，但 `text` 只有前 279 字元 |
| FxTwitter API <https://api.fxtwitter.com/karpathy/status/2105819303471976479> | 同上 | curl，讀 JSON | 第三方轉送，有全文 |
| 貼文附圖 <https://pbs.twimg.com/media/HTlaHqgbwAAS1lv.png?name=orig> | 同上 | curl，讀圖 | 第一手（X 的媒體主機） |
| ASD-STE100 Issue 9 PDF <https://www.asd-ste100.org/assets/files/ASD-STE100_ISSUE9.pdf> | Issue 9，2025-01-15 | curl 加瀏覽器 User-Agent，`pdftotext -layout` | 第一手 |
| STEMG 網站 FAQ <https://www.asd-ste100.org/STE_faq.html>、About <https://www.asd-ste100.org/about_STE.html>、Downloads <https://www.asd-ste100.org/STE_downloads.html> | 2026-10-10 讀取 | 同上 | 第一手 |
| STEMG AI 白皮書 <https://www.asd-ste100.org/assets/files/WhitePaper-ASD-STE100_and_AI.pdf> | 2026-06 | 同上 | 第一手 |

官方 Downloads 頁只提供申請表單，不列出 PDF 連結。上表的 PDF 網址來自搜尋結果，
主機是官方網域。PDF 內文每頁標示 `Issue 9` 和 `2025-01-15`。
WebFetch 對 `asd-ste100.org` 得到 HTTP 403；curl 加瀏覽器 User-Agent 得到 200。

### 8.2 Karpathy 貼文

- 作者：`karpathy`。時間：`2026-10-02T00:37:00.000Z`。不是回覆，沒有引用貼文。
  附一張 3200×1600 的圖。（syndication 端點和 FxTwitter API 的值相同。）
- syndication 端點的 `text` 在「originally developed for」之後截斷。
  所以下方全文在這個位置之後的部分只有 FxTwitter 一個來源，**未經第一手驗證**。
  「80% of the way to ASD-STE100」這一句在未驗證的部分。

全文（FxTwitter API 的 `tweet.text`，逐字）：

> We'll be spending a lot more time trying to understand the outputs of language models. A few thoughts, tips & tricks:
>
> Writing. Something I've had success with: Ask your LLM to explain something in ASD-STE100, it's a controlled language specification originally developed for aerospace maintenance documentation. LLMs well-versed in this language and it comes with heavy constraints on clean writing style that I often find a lot more readable. Sometimes I've tried to soften it a bit e.g. ask for "80% of the way to ASD-STE100" because the spec is quite stringent. But even better:
>
> Diagrams / images. Instead of writing, ask your LLM to create a diagram. These can be a lot easier to process, parse, and understand. But even better:
>
> Web pages. Ask for output "in HTML" to get a beautiful, interactive webpage. LLMs are getting really good at frontend and can create beautiful experiences, animations, etc. But even better:
>
> Explainer videos. The output format I am most bullish on is fully custom / bespoke explainer videos generated on any arbitrary topic. Experiment with things like "Create a 3b1b style video explainer on X. Use my ElevenLabs API key for audio narration". (you'd need an API key for the latter or you can ask your LLM to find you decent free alternatives that use your local compute). This is actually starting to work!
>
> In summary:
> - As LLMs get better, they will do more and more of the legwork autonomously, and a lot more of our work will rise up the abstractions into oversight and understanding.
> - Luckily, LLMs can help here too because as intelligence and code are increasingly abundant, you can ask for large, custom, discardable software artifacts (e.g. web apps, video explainers) that would have never made sense to create before. Push the boundaries here and you'll be surprised.

貼文對 STE 的說明只有 Writing 這一段：

- 指令是一行：「explain something in ASD-STE100」。貼文沒有提供規則清單或 prompt 範本。
- 理由有兩個：LLM 熟悉這個規範；規範對寫作風格的限制多，他覺得結果較容易讀。
- 限制有一個：規範很嚴格，所以他有時改成「80% of the way to ASD-STE100」。
- 貼文把文字排在四種輸出形式的最低一級，後面依序是圖、HTML 網頁、解說影片。
- 貼文談的是讓 LLM 用英文解釋事情。貼文沒有提到其他語言。

Karpathy 本人的後續回覆：

- 找到一則：<https://x.com/karpathy/status/2105913472295063841>，2026-10-02 06:51 UTC，
  回覆 `@CorvusCrypto`，內容是「Extremely sorry to disappoint Clifford」。
  這則沒有 STE 的細節。（來源：FxTwitter API。）
- 沒有登入就無法列出整個討論串。是否有其他回覆是**未知**。

附圖是一頁速查表，標題「Simplified Technical English: overview」。圖上沒有作者。
圖上的數字和 Issue 9 相符：程序句 20 詞、描述句 25 詞、段落 6 句、名詞組 3 詞、每句一個指令。
圖上有下列項目和 Issue 9 不符，所以不要把這張圖當成規格：

| 圖上的內容 | Issue 9 的內容 |
|---|---|
| `approximately (adv)` 不核准，改用 ABOUT | `APPROXIMATELY` 是核准詞；`ABOUT (prep)` 只核准「Concerned with」這個意思，並指向 `APPROXIMATELY (adv)`（PDF Part 2 字典；FAQ「How were the words for the STE dictionary selected?」） |
| `TEST (v)` 核准 | `test (v)` 不核准，改用 `TEST (n)`（PDF Part 2 字典） |
| 描述文可以在「necessary」時用被動語態 | 只有在行為者未知時可以用（Rule 3.6） |
| 「Noun clusters」「specification」 | Issue 9 用「multi-word nouns」（Rule 2.1），並且已經是 standard（PDF General introduction，修訂紀錄 2025-01-15） |

第三方文章 <https://max.nardit.com/articles/karpathy-understanding-llm-outputs>
先指出這些差異。上表四列已經用 PDF 重新確認。該文另外說圖上的「in order to」
不是字典條目；這一項沒有重新確認。

### 8.3 ASD-STE100 Issue 9 的規定

結構：Part 1 有 9 節共 53 條寫作規則，Part 2 是字典
（PDF「Guide to the writing rules」；About 頁）。字典約有 900 個核准詞和約 1200 個不核准詞（About 頁）。
下表的規則文字取自 PDF 各節第一頁的「Summary of the rules」。

| 規則 | 內容 |
|---|---|
| 1.1 | 只用三種詞：字典核准詞、technical noun、technical verb |
| 1.2 | 核准詞只用指定的詞性 |
| 1.3 | 核准詞只用核准的意思 |
| 1.4 | 動詞和形容詞只用核准的形式 |
| 1.5–1.10 | technical noun 的範圍和選擇：用公司或領域核准的詞，選短而易懂的詞，不用地區用語、俚語、行話，不把 technical noun 當動詞 |
| 1.11 | 同一個東西不用不同的 technical noun |
| 1.12–1.13 | technical verb 的範圍；不把 technical verb 當名詞 |
| 1.14 | 用美式拼字 |
| 2.1 | multi-word noun 不超過 3 個詞 |
| 2.2 | 超過 3 個詞的 technical noun 先寫全名，再用較短的形式或連字號 |
| 3.1–3.2 | 只用字典列出的動詞形式；只用不定式、祈使式、簡單現在式、簡單過去式、簡單未來式、過去分詞（當形容詞） |
| 3.3–3.5 | 過去分詞只當形容詞；不用助動詞組成複雜動詞結構；`-ing` 只用在 technical noun 內 |
| 3.6 | 用主動語態。描述文只有在行為者未知時可以用被動語態 |
| 3.7 | 用核准的動詞描述動作，不用名詞或其他詞性 |
| 4.1 | 句子要短而清楚 |
| 4.2 | 不省略詞，不用縮寫式（don't、isn't）來縮短句子。說明文字另外要求不省略名詞和動詞 |
| 4.3 | 複雜的內容用直列清單 |
| 4.4 | 用連接詞和連接片語連接主題相關的句子 |
| 4.5 | 名詞前要有冠詞（the、a、an）或指示形容詞（this、these） |
| 5.1 | 程序句最多 20 個詞。警告和注意事項也適用 |
| 5.2 | 每句只寫一個指令，除非兩個以上的動作同時發生 |
| 5.3 | 指令用祈使式 |
| 5.4 | 讀者必須先知道的條件放在指令前面，用逗號和指令分開 |
| 5.5 | Note 只提供資訊，不寫指令 |
| 6.1 | 逐步提供資訊。說明文字要求每句只有一個主題 |
| 6.2 | 用關鍵詞和關鍵片語建立邏輯結構 |
| 6.3 | 描述句最多 25 個詞 |
| 6.4–6.5 | 用段落放相關的資訊；每段只有一個主題 |
| 6.6 | 每段不超過 6 句 |
| 7.1–7.3 | 安全指示：用 warning、caution 這類詞標示風險等級；用清楚的命令或條件開頭；說明風險或可能的結果 |
| 8.1 | 可以用所有標準英文標點，但不可以用分號 |
| 8.2–8.3 | 連字號連接直接相關的詞；括號的七種允許用途 |
| 8.4–8.7 | 算詞數的方法：直列清單的冒號等於句號；括號內文字算 1 個詞；數字、數字加單位、縮寫、識別碼、引文、標題和標籤、專有名詞各算 1 個詞；有連字號的詞算 1 個詞 |
| 9.1 | 逐詞替換不夠時，改用不同的句子結構 |
| 9.2–9.3 | 正確使用核准詞；不組成片語動詞 |
| 9.4 | 用詞和句型保持一致：同一種步驟每次用相同的寫法 |
| GR-1–GR-8 | 一般建議（不是規則）：連接詞 that、介系詞 with、代名詞、this、false friends、拉丁縮寫、包容性用語、所有格 |

適用範圍：

- STE 是為維修文件的程序文和描述文而設計的。FAQ 說它不是為一般用途的寫作而設計的，
  但是短句、每句一個主題、主動語態這些原則可以用在其他寫作
  （FAQ「Who needs to write in STE?」）。
- STE 不規定縮寫、排版格式、計量單位，也不可以單獨使用（PDF General introduction, Page i）。
- STE 的核准意思和拼字以美式英文和 Merriam-Webster 字典為準（PDF General introduction, Page i）。
- STEMG 的 AI 白皮書說，AI 產生的文字可以看起來符合 STE，但實際上沒有正確使用規則和詞彙；
  「看起來合理」不等於「已驗證符合」（Downloads 頁的白皮書摘要；白皮書 2026-06）。

### 8.4 哪些規則只適用英文

規格沒有討論中文。下表是依規則文字做的**推論**，不是規格的陳述。

| 規則 | 不能轉移到繁體中文的原因 |
|---|---|
| Part 2 字典，以及 1.1–1.4、9.2 的查字典部分 | 字典是約 900 個英文詞，各有一個詞性和一個意思。沒有官方的中文字典 |
| 1.14 | 美式拼字 |
| 3.1–3.5 | 規定英文的動詞時態、分詞、`-ing`、助動詞結構。中文動詞沒有這些詞形變化 |
| 4.2 的縮寫式部分 | don't、isn't 是英文的縮寫式 |
| 4.5 | 中文沒有冠詞 |
| 8.2、8.7 | 連字號複合詞是英文的寫法 |
| 5.1、6.3、2.1、8.4–8.6 的「詞」單位 | 英文用空格分詞。中文沒有空格，「詞」的界線要靠斷詞。數字 20、25、3 不能直接使用 |
| 9.3 | 片語動詞是英文的結構 |
| GR-1、GR-2、GR-6、GR-8 | 處理英文的 that、with、拉丁縮寫、`'s` 所有格。GR-1 和 GR-8 的說明文字本身提到其他語言沒有對應的形式 |

下列規則的內容和語言無關，可以轉移（同樣是推論）：
1.11 和 9.4（一個東西一個名稱，同一種步驟同一種寫法）、3.6（主動語態）、
3.7（用動詞表示動作）、4.1、4.2 的不省略名詞和動詞、4.3（清單）、4.4（連接詞）、
5.2–5.5、6.1、6.2、6.4–6.6、7.1–7.3、9.1。
2.1 和 8.1 可以轉移概念（限制名詞串的長度；不用分號），但是中文的界線要另外定義。

### 8.5 和 repository 現況的比對

Template 的寫法只有一句：「Write in Traditional Chinese following ASD-STE100」
（`.chezmoitemplates/agent-instructions.md:17`）。這和 Karpathy 的一行指令是同一種做法：
只給規範的名稱，讓模型自己套用。差別是 Karpathy 的對象是英文輸出。
Template 沒有採用他的「80%」放寬寫法。

Skill 的 E 組標題是「Sentence discipline (ASD-STE100 for Traditional Chinese)」
（`dot_agents/skills/anti-slop/SKILL.md:143`）。

| Skill 規則 | 對應的 STE 規則 | 差異 |
|---|---|---|
| 28 一句一個想法；超過兩個逗號就拆（`SKILL.md:145`） | 5.2、6.1 | 「兩個逗號」的門檻不在 STE 內，是 repository 自己定的 |
| 29 祈使句 30 字、描述句 40 字（`SKILL.md:148`） | 5.1（20 詞）、6.3（25 詞） | 20→30、25→40 的換算來自本檔 2.2 節，沒有外部來源。Skill 沒有說明程式碼、路徑、英文術語怎麼算；STE 用 8.4–8.6 規定這些各算 1 個詞 |
| 30 指令用祈使句（`SKILL.md:151`） | 5.3 | 相符 |
| 31 主動語態（`SKILL.md:154`） | 3.6 | Skill 沒有寫例外：描述文在行為者未知時可以用被動語態 |
| 32 主詞省略而行為者不明確時要寫出來（`SKILL.md:157`） | 4.2（不省略名詞） | 相符。STE 的要求較嚴：一律不省略 |
| 33 中英混用規則（`SKILL.md:160`） | 沒有對應 | 不是 STE 規則。最接近的是 1.5–1.12 允許保留領域術語 |
| 20「進行 X」改成動詞（`SKILL.md:111`，D 組） | 3.7 | 內容相符，但 skill 沒有把它歸在 STE |
| 6 刪除 filler phrases（`SKILL.md:46`，A 組） | 沒有條文對應 | STE 靠字典排除這些詞，不是靠寫作規則 |

Skill 沒有寫的 STE 規則（都屬於 8.4 的可轉移部分）：

- 1.11、9.4：同一個東西只用一個名稱；同一種步驟用同一種寫法。
- 5.4：條件放在指令前面。
- 5.5：Note 只提供資訊，不寫指令。
- 6.4–6.6：每段一個主題，每段不超過 6 句。
- 4.3：複雜的內容用清單。
- 4.4、6.2：用連接詞表示句子之間的關係。
- 7.1–7.3：警告先寫命令或條件，再寫風險。
- 8.1：不用分號。
- 2.1：名詞串不超過 3 個詞。

兩個需要擁有者決定的衝突：

- Skill 規則 22 把「使用者的帳號的設定的頁面」改成「使用者帳號設定頁面」（`SKILL.md:119`）。
  改後是四個名詞相連。STE 2.1 把 multi-word noun 限制在 3 個詞。
  兩者方向相反。這是推論；中文的「詞」界線沒有官方定義。
- 本檔 2.2 節把「用簡單的詞」列為 STE 規則，並舉「使用→用」為例。
  STE 的機制是 Part 2 字典，不是一條「用簡單的詞」的寫作規則。
  中文沒有對應的字典，所以這一列是 repository 自己的規則，不是 STE 的轉譯。

### 8.6 未解問題和未驗證項目

- **未驗證**：貼文在「originally developed for」之後的文字（包含「80% of the way to ASD-STE100」）
  只有 FxTwitter API 一個來源。`x.com` 回 HTTP 402。
- **未知**：Karpathy 在同一個討論串是否有其他回覆。只找到一則，內容和 STE 無關。
- **未知**：貼文附圖的作者。圖不是 ASD 的出版品，並且有 8.2 節列出的錯誤。
- **未驗證**：max.nardit.com 文章說圖上的「in order to」不是字典條目。沒有重新確認。
- **未驗證**：Issue 9 PDF 的網址來自搜尋結果，官方 Downloads 頁沒有列出這個連結。
  主機是官方網域，內文標示 Issue 9。沒有和申請表單取得的檔案比對。
- **推論，不是來源的陳述**：8.4 節的全部分類，以及 8.5 節的兩個衝突。
- **沒有來源**：30 字和 40 字的中文句長上限。沒有找到官方或研究來源支持這個換算。
- **沒有測試**：「following ASD-STE100」一行指令對繁體中文輸出的實際效果。
  Karpathy 的說法只涵蓋英文解釋，並且是個人經驗。
- **未解**：中文句長的計算單位（字或詞），以及程式碼、路徑、英文術語是否計入。
