---
name: anti-slop
description: >-
  Remove AI writing patterns from any prose output. Covers English AI
  vocabulary, conversation-residue leakage, agent narration, Traditional
  Chinese filler, and ASD-STE100 sentence discipline. Fully self-contained.
  Use after writing any prose the human will read, or as a review pass on
  existing documents.
---

# Anti Slop

Scan prose for AI tells, rewrite them, self-audit. Five groups of rules.

## When to use

- After writing any prose a human will read.
- As a review pass on existing documents.
- Before sending a document for human review.

## Process

1. Read the target text.
2. Apply each rule below. Rewrite in place. Preserve meaning.
3. Self-audit: read the result as a human would. If any sentence sounds like
   an AI wrote it, find the pattern and fix it.
4. Measure: count sentences over the length limit. Zero is the target.

## A. English AI vocabulary

1. **Kill AI-favorite words.** Replace or delete: delve, enhance, pivotal,
   tapestry, vibrant, landscape, foster, leverage, comprehensive, paramount,
   intricate, streamline, furthermore, notably, robust.

2. **Kill fancy-is.** "serves as" → "is". "stands as" → "is". "boasts" →
   "has". "features" → "has".

3. **Kill Not-just-X-but-Y.** Say what it is. Drop the contrast structure.

4. **Kill forced triplets.** Three adjectives, three benefits, three pillars.
   Keep only what earns its place.

5. **Kill vague attribution.** "Experts believe" → name the expert or delete.
   "Industry reports suggest" → cite or delete.

6. **Kill filler phrases.** "In order to" → "to". "Due to the fact that" →
   "because". "It is important to note that" → delete.

7. **Kill hedging stacks.** "could potentially possibly" → pick one or delete.
   "It might be worth considering" → say it or don't.

## B. Conversation-residue leakage

8. **No production-context leakage.** The conversation is production context,
   not content. Remove or rewrite anything that exposes prompts, intermediate
   reasoning, constraints, avoided approaches, or corrective feedback.
   - "As requested..." → delete
   - "Based on your instruction..." → delete
   - "We will not use X..." → just don't use X
   - "Unlike the previous version..." → describe the current version
   - "This was changed to..." → describe what it is now

9. **Constraints become design, not disclaimers.**
   - Before: "This guide does not use Git or CLI tools."
   - After: describe the approach that was chosen, omit what was excluded.

10. **Examples from conversation are not content.** User examples communicate
    intent. Use them to infer tone, scope, and audience. Do not copy them into
    the deliverable unless the deliverable itself needs them.

11. **No patchwork voice.** Multiple rounds of feedback produce inconsistent
    tone. Read the whole artifact and unify.

## C. Agent narration patterns

12. **No process narration.** Delete sentences about what you will do or did.
    - Before: 「首先我會分析目前的狀態，然後找出根因。」
    - After: (deleted; write the analysis directly)

13. **No question echo.** Start from the answer.
    - Before: 「你問的是如何設定 X。要設定 X，編輯 config.yaml。」
    - After: 「編輯 config.yaml。」

14. **No post-list summary.** The reader just read the list.
    - Before: 「以上就是需要修改的五個地方。」
    - After: (deleted)

15. **No vague disclaimers.** Name the specific limitation or delete.
    - Before: 「這個方案可能不適用於所有情況。」
    - After: 「輸入超過 2GB 時會失敗。」(or deleted)

16. **No code paraphrasing.** Only say what the code cannot show.
    - Before: 「這段程式碼讀取設定檔，解析 JSON，存入變數。」
    - After: (deleted; the code says this)

17. **No transition filler.** Headings do this job.
    - Before: 「接下來讓我們看看第二部分。」
    - After: (deleted)

18. **No value judgments without evidence.** Name the measurable benefit.
    - Before: 「這個設計非常優雅！」
    - After: 「省掉中間複製，記憶體用量減半。」(or deleted)

## D. Traditional Chinese patterns

19. **Delete「值得注意的是」and siblings.**
    「需要特別說明的是」「需要強調的是」「有趣的是」
    - Before: 「值得注意的是，這個函式會回傳 null。」
    - After: 「這個函式回傳 null。」

20. **Replace「進行 X」with the verb.**
    - Before: 「進行測試」「進行修改」「進行部署」
    - After: 「測試」「修改」「部署」

21. **Cut hedging politeness.** Instructions use imperatives.
    - Before: 「建議可以考慮使用 X」
    - After: 「用 X」

22. **Break「的」chains.** Three or more consecutive 的: split or remove.
    - Before: 「使用者的帳號的設定的頁面」
    - After: 「使用者帳號設定頁面」

23. **Flatten「透過 X 來 Y」.** The point is Y.
    - Before: 「透過修改設定檔來調整行為」
    - After: 「改設定檔」

24. **Shorten「在 X 的情況下」.**
    - Before: 「在沒有安裝的情況下」
    - After: 「沒裝時」

25. **Drop trailing「等」after a complete list.**
    - Before: 「測試、lint、型別檢查等」(list is complete)
    - After: 「測試、lint、型別檢查」

26. **Delete closing summaries.**
    - Before: 「這樣就完成了基本的設定。」
    - After: (deleted)

27. **Delete「根據/依據你的要求」.**
    - Before: 「根據你的要求，這裡使用 TypeScript。」
    - After: (deleted; or just state the choice if it matters)

## E. Sentence discipline (ASD-STE100 for Traditional Chinese)

28. **One thought per sentence.** A comma is not a period. More than two
    commas in one sentence: split it.

29. **Length limits.** Imperatives: 30 characters. Descriptions: 40
    characters. Over the limit: split.

30. **Imperatives for instructions.**
    「應該 X」→「X」.「需要 X」→「X」.

31. **Active voice.**
    「被 X」→ the actor does X.「確保 X 被 Y」→「Y X」.

32. **Explicit actor.** When the subject is omitted and the actor is
    ambiguous, name it.

33. **Mixed-language rule.** English for: terms, commands, file paths, API
    names, identifiers. Traditional Chinese for everything else.
