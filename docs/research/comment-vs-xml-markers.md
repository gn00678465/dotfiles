# HTML comment markers vs XML-style tags in agent instruction files (CLAUDE.md / AGENTS.md)

> 研究日期：2026-08-31。
> 目錄說明：repo 原本沒有 research 目錄；依「docs/ 放文件、docs/agents/ 放 agent 慣例」的既有結構，新建 `docs/research/` 存放研究筆記，本文件是第一份。
> 研究動機：`.chezmoitemplates/evidence-first-contract.md` 會被 include 進產生的 `~/.claude/CLAUDE.md` 與 `~/.codex/AGENTS.md`。內容已有 `<workflow name="evidence-first" role="contract">` XML-style 包裝，計畫再在外層加上成對 comment markers `<!-- evidence-first:contract -->` … `<!-- /evidence-first:contract -->`。本文查證這個組合在整條 pipeline（chezmoi → 生成檔 → Claude Code / Codex 注入 → markdown renderer → 區段同步工具）中是否會出問題。

## TL;DR（回答四個子問題）

1. **LLM 是否忽略 comment 內容？** 模型本身不會「忽略」HTML comment——它收到的是 raw text，comment 也是 token；Anthropic 的 prompt 文件從未宣稱模型會跳過 comment。但關鍵事實是：**Claude Code 在把 CLAUDE.md 注入 context 之前，會先剝除 block-level HTML comments**（官方文件明載）。所以：(a) 單一 comment 內的內容，Claude 在 CLAUDE.md 管道中根本看不到；(b) 兩個各自完整、各佔一行的 comment markers **之間**的內容不是 comment，是普通 markdown，會完整送達模型（只有 marker 兩行被剝掉）。Codex 的 AGENTS.md 則是「just standard Markdown」原文照讀，comment 會進 context、佔 token、且模型讀得到。
2. **工具鏈會不會動這些 markers？** chezmoi（Go `text/template`）對 action 以外的文字「copied to the output unchanged」，不會碰 HTML comment 也不會碰未知 tag。Markdown renderers（CommonMark/GFM）把兩者都當 HTML block 原樣傳遞：comment 在瀏覽器中不可見，`<workflow>` 這種未知 tag 在 GFM tagfilter 層「left untouched」，但 GitHub.com 下游的 sanitizer 會把不在白名單的 tag 移除（內文文字保留）。區段同步工具（doctoc、markdown-magic、terraform-docs 這一類）**擁有並重寫**成對 BEGIN/END comment markers 之間的所有內容——所以若有任何工具認得你的 marker 名稱，markers 之間的手寫內容就是它的地盤。spec-kitty 的 `charter sync` 經查是 charter.md → YAML 的單向抽取（以 SHA-256 判斷 staleness），不是 marker-region 重寫器，不會碰這對 markers。
3. **comment markers 外層 + XML tag 內層會不會出事？** 不會，**前提是空行**。實測（commonmark.js 0.31.2 reference implementation）：`<!-- marker -->` 是 CommonMark type 2 HTML block，同一行內 `-->` 即終結；`<workflow …>` 單獨一行是 type 7 HTML block，**吃掉後面所有內容直到空行**。所以 `<workflow …>` 開標籤之後若不空一行，緊接的 `## 標題`、`- 清單` 會被當 raw HTML 原樣輸出（markdown 不解析、GitHub 上還會被 sanitizer 拔掉 tag 只剩帶 `##`/`**` 的裸文字）。開標籤後、閉標籤前各留一行空行，內容就是正常 markdown。另外 type 7 不能打斷段落——tag 若緊貼在文字行後面會被吸進段落當 inline raw HTML。兩者組合（G 案例）實測輸出完全正確。
4. **單一跨段 comment vs 成對 markers：** 已證實。`<!-- name` +多行+ `-->` 是一個 type 2 block，直到出現 `-->` 的那行才結束——整段在 rendered HTML 中不可見，且在 Claude Code 中整段被剝除、Claude 完全看不到（雙重消失）。成對、各自完整、各佔一行的 markers 則各自是一行就結束的 comment block，之間的內容維持普通 markdown：renderer 正常渲染、Claude Code 只剝掉 marker 兩行、模型收到全部實質內容。**結論：計畫中的組合（成對 comment markers 外層 + `<workflow>` tag 內層 + 空行分隔）在整條 pipeline 中安全，且兩層互補：markers 給工具與人看（Claude Code 會剝掉、不花 token），XML tag 給模型看（符合 Anthropic 的 XML tag 建議）。**

---

## 1. 模型與 harness 如何對待 comment 與 XML tag

### 1.1 Claude Code 會在注入前剝除 block-level HTML comments（決定性事實）

Claude Code 官方 memory 文件（"How CLAUDE.md files load" 一節）：

> "Block-level HTML comments (`<!-- maintainer notes -->`) in CLAUDE.md files are stripped before the content is injected into Claude's context. Use them to leave notes for human maintainers without spending context tokens on them. Comments inside code blocks are preserved. When you open a CLAUDE.md file directly with the Read tool, comments remain visible."

含義：

- 成對 markers `<!-- evidence-first:contract -->` / `<!-- /evidence-first:contract -->` 各自是一個 block-level comment：**兩行 marker 被剝除、之間的內容保留**。marker 對 Claude 不可見、零 token 成本；若你希望 Claude 看到區段邊界，靠的必須是內層的 `<workflow>` tag，不能靠 comment markers。
- 單一 comment 跨越整段（`<!-- evidence-first:contract` … `-->`）＝整段是一個 block-level comment，**全部被剝除**，Claude 在 CLAUDE.md 管道中完全看不到這份 contract。這正是問題 4 的陷阱在 Claude Code 端的體現。
- 剝除發生在「注入 context」時，不是改寫磁碟檔案；磁碟上的檔案（以及用 Read tool 直接開檔）comment 都還在，所以依賴 marker 的外部工具不受影響。
- 注意文件只說 CLAUDE.md files；`@AGENTS.md` import 是 "expanded and loaded into context at launch alongside the CLAUDE.md that references them"，被當同一批 memory 內容處理，合理推定 import 進來的內容同樣適用剝除規則（文件未逐字明說 imported file 的 comment，此點標記為「文件推定、未逐字驗證」）。

同一份文件也回答了「raw text 還是 rendered」：

> "CLAUDE.md content is delivered as a user message after the system prompt, not as part of the system prompt itself."

即：除了上述 comment 剝除之外，內容以 raw markdown 文字送進模型，不經 markdown rendering。`<workflow name="…">` 會以原始文字形式抵達模型。

來源：<https://code.claude.com/docs/en/memory>

### 1.2 Anthropic 對 XML tag 的官方立場

Prompt engineering 文件（"Structure prompts with XML tags"）：

> "XML tags help Claude parse complex prompts unambiguously, especially when your prompt mixes instructions, context, examples, and variable inputs. Wrapping each type of content in its own tag (for example, `<instructions>`, `<context>`, `<input>`) reduces misinterpretation."

Best practices："Use consistent, descriptive tag names across your prompts." 並建議有層級時巢狀使用（如 `<documents>` 內含 `<document index="n">`）。tag 名稱是任意的、無固定 schema（文件通篇以自訂名稱示例，含帶 attribute 的 `<document index="1">`），所以 `<workflow name="evidence-first" role="contract">` 完全符合官方建議的用法。文件**沒有任何**「Claude 會忽略 HTML comment」的陳述——模型層面 comment 就是普通文字。

來源：<https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/claude-prompting-best-practices>（舊網址 `docs.anthropic.com/en/docs/build-with-claude/prompt-engineering/use-xml-tags` 已 301 轉址併入此頁）

### 1.3 Codex / AGENTS.md：原文照讀，沒有 comment 剝除

agents.md 官方網站：

> "AGENTS.md is just standard Markdown. Use any headings you like; the agent simply parses the text you provide."
> FAQ: "Are there required fields? No."

沒有任何預處理／剝除機制的記載。含義：在 `~/.codex/AGENTS.md` 這一端，comment markers **會**進入模型 context（花 token、模型讀得到）；單一跨段 comment 的內容也照樣送達模型——與 Claude Code 行為相反。marker 短小（兩行），token 成本可忽略；但不要假設「comment 裡的字模型看不到」在 Codex 成立。

來源：<https://agents.md/>

---

## 2. 工具鏈是否剝除／重寫 markers

### 2.1 chezmoi（Go text/template）：不碰

chezmoi 模板用 Go 的 `text/template`；`.chezmoitemplates/` 內的檔案以 `template`/`includeTemplate` include 時整檔作為 template 執行。Go `text/template` 文件明載：

> "all text outside actions is copied to the output unchanged."

`text/template` 對 HTML 語法零感知（HTML 感知的是另一個套件 `html/template`）：HTML comment 與 `<workflow>` tag 都是 "text outside actions"，原樣輸出。反向注意事項：**`{{ }}` 出現在 HTML comment 內也照樣被當 action 執行**——comment 不能用來「註解掉」template 語法（template 自己的註解語法是 `{{/* … */}}`）。目前的 marker 與 tag 都不含 `{{`，安全。

來源：<https://pkg.go.dev/text/template>、<https://www.chezmoi.io/reference/templates/>、<https://www.chezmoi.io/reference/special-directories/chezmoitemplates/>

### 2.2 Markdown renderers（CommonMark / GFM / GitHub.com）

- CommonMark 把兩種寫法都當 HTML block 原樣傳遞（"passed through as-is"，不解析 block 內的 markdown）；細節見第 3 節。來源：<https://spec.commonmark.org/0.31.2/#html-blocks>
- GFM 的 tagfilter extension 只過濾九個 tag（`<title> <textarea> <style> <xmp> <iframe> <noembed> <noframes> <script> <plaintext>`，把 `<` 換成 `&lt;`），並明言："All other HTML tags are left untouched."（GFM spec §6.11）— `<workflow>` 不在名單，comment 也不受影響。來源：<https://github.github.com/gfm/#disallowed-raw-html-extension->（引文取自 spec 原始檔 <https://raw.githubusercontent.com/github/cmark-gfm/master/test/spec.txt> "Disallowed Raw HTML (extension)" 一節）
- GitHub.com 網站顯示層另有下游 sanitization：github/markup README 描述其 pipeline 第二步 "aggressively removing things that could harm you and your kin—such as `script` tags, inline-styles, and `class` or `id` attributes"，且 "markup itself does no sanitization … it expects that to be covered by whatever pipeline is consuming the HTML"。實務結果：白名單外的未知 tag（如 `<workflow>`）在 GitHub 頁面上會被 sanitizer 移除，**tag 消失但內部文字內容保留**；HTML comment 依 HTML 語意在瀏覽器中不可見。也就是說：在 GitHub 上看生成檔時，markers 與 `<workflow>` 包裝都隱形，中間的 markdown 內容正常顯示——這是無害的顯示行為，檔案本身不被改寫。來源：<https://github.com/github/markup>

### 2.3 區段同步工具：markers 之間是工具的地盤

「成對 comment markers 界定一塊由工具重寫的區域」是一個成熟的工具模式，凡是認得該 marker 名稱的工具，都會**整塊覆寫**兩個 marker 之間的內容：

- **doctoc**：`<!-- START doctoc -->` … `<!-- END doctoc -->`；"doctoc locates the TOC by the `<!-- START doctoc -->` and `<!-- END doctoc -->` comments"，重跑時整塊重寫，marker 內建警語 "DON'T EDIT THIS SECTION, INSTEAD RE-RUN doctoc TO UPDATE"。來源：<https://github.com/thlorenz/doctoc>
- **markdown-magic**：`<!-- docs transformName … -->` … `<!-- /docs -->`（與本 repo 計畫的 `<!-- name -->`…`<!-- /name -->` 同款式），每次執行以 transform 輸出取代兩 marker 之間內容；README 並指出這些 comment "are hidden in markdown and when viewed as HTML"。來源：<https://github.com/DavidWells/markdown-magic>
- **terraform-docs**：`<!-- BEGIN_TF_DOCS -->` … `<!-- END_TF_DOCS -->`，inject 模式 "Partially replace the `output-file` content with generated output"，每次執行取代區間內容。來源：<https://terraform-docs.io/user-guide/configuration/output/>

含義：`<!-- evidence-first:contract -->` 這對 markers 本身不會被任何通用工具動到（沒有工具認得這個名稱），但它的**語意慣例**就是「之間的內容由某個 sync 程序擁有」——這正是你要的：讓未來的同步腳本能定位並整塊替換 contract 區段。反過來說，任何人手改 markers 之間的內容，都應預期會被下一次 sync 蓋掉。

- **spec-kitty charter sync**（本機安裝的 skill 文件查證）：`spec-kitty charter sync` 是把 `charter.md` 抽取成 `.kittify/charter/` 下的 `governance.yaml`/`directives.yaml`/`metadata.yaml`，staleness 以 charter.md 的 SHA-256 對比 metadata.yaml 判斷——是 markdown→YAML 的單向抽取，**不是** marker-region 重寫器，文件中沒有任何 comment-marker 區段機制，不會與本計畫的 markers 互動。來源（本機）：`~/.claude/skills/spec-kitty-charter-doctrine/references/charter-command-map.md`（"sync" 一節）

---

## 3. CommonMark HTML block 規則與「組合寫法」的空行敏感性

CommonMark 0.31.2 §4.6 HTML blocks 的相關規則（來源：<https://spec.commonmark.org/0.31.2/#html-blocks>）：

- **Type 2（comment）**：start condition "line begins with the string `<!--`"；end condition "line contains the string `-->`"。可跨多行（含空行）直到出現 `-->` 的那一行——這就是問題 4 陷阱的規範依據。若 `<!--` 與 `-->` 在同一行（自足 marker），block 一行即終結，下一行從頭解析。
- **Type 6**：僅限固定清單中的已知 HTML tag 名（address、div、section、table…）；**`workflow` 不在清單中**，所以 `<workflow>` 走不了 type 6。
- **Type 7**：start condition "line begins with a complete open tag (with any tag name other than `pre`, `script`, `style`, or `textarea`) or a complete closing tag, followed by zero or more spaces and tabs, followed by the end of the line"；end condition "line is followed by a blank line"；限制 "Blocks of type 7 may not interrupt a paragraph"。`<workflow name="…" role="…">` 單獨一行正是 type 7 的開頭。
- HTML block 內的 markdown **不解析**，原樣輸出（"passed through as-is"）。

### 實測驗證（commonmark.js 0.31.2，reference implementation，本機執行）

| 案例 | 輸入 | 結果 |
|---|---|---|
| A | 成對 markers，前後空行，中間放 `## 標題` + 清單 | 內容正常渲染為 `<h2>`/`<ul>`；markers 原樣輸出為 HTML comment（瀏覽器不可見） |
| B | 單一 comment 跨整段 | 整段包在一個 comment 內輸出——rendered 頁面上**整段消失** |
| C | `<workflow …>` 開標籤後**不空行**直接接 markdown | 標題與清單被吸進 type 7 block，原樣輸出 raw text，**markdown 不解析**（GitHub 上再被 sanitizer 拔 tag，只剩帶 `##`/`**` 的裸文字） |
| D | `<workflow …>` 開標籤後空一行、閉標籤前空一行 | 內容正常渲染；tag 原樣傳遞（GitHub 上被 sanitizer 隱去，內容不受影響） |
| E | `<!-- marker -->` 下一行直接接 `## 標題`（無空行） | 正常：type 2 在含 `-->` 的同一行終結，標題照常渲染（不過為了可讀性與工具穩健仍建議留空行） |
| F | 文字段落後緊接 `<workflow …>`（無空行） | type 7 不能打斷段落：tag 被吸進段落成為 inline raw HTML——tag 失去 block 身份 |
| G | **計畫中的完整組合**：marker → `<workflow>` → 空行 → markdown → 空行 → `</workflow>` → marker | 全部正確：markers 為 comment、tag 原樣傳遞、中間 markdown 正常渲染 |

「未知 XML tag 吞掉後續內容」的已知問題即案例 C/F 的機制：type 7 block 一路吃到**下一個空行**為止，並非吃到閉標籤或檔尾。所以只要維持「開標籤後空一行、閉標籤自成一行且前面空一行」，就不存在吞內容問題；渲染污染的爆炸半徑最多到下一個空行。

---

## 4. 問題 4：單一跨段 comment vs 成對自足 markers（總結對照）

| | 單一 comment 跨整段（`<!-- name` … `-->`） | 成對自足 markers（`<!-- name -->` … `<!-- /name -->`） |
|---|---|---|
| CommonMark 解析 | 一個 type 2 block，整段是 comment（spec：end condition "line contains the string `-->`"） | 兩個各一行的 type 2 block；之間是普通 markdown |
| GitHub 顯示 | 整段不可見 | 內容正常顯示，markers 不可見 |
| Claude Code 注入 | **整段被剝除，Claude 看不到**（memory 文件：block-level comments stripped before injection） | 只剝 marker 兩行，內容完整送達 |
| Codex / AGENTS.md | 內容仍送達模型（原文照讀），但語意上「被註解掉」，模型可能降低遵循權重 | 內容以正常 markdown 送達 |
| 區段同步工具 | 無法定位區間（只有一個 comment，沒有 BEGIN/END 對） | 正是 doctoc/markdown-magic/terraform-docs 同款的區間定位模式 |
| chezmoi | 原樣輸出 | 原樣輸出 |

## 5. 對本 repo pipeline 的結論

1. **計畫可行**：成對 `<!-- evidence-first:contract -->` markers 外層 + `<workflow name="evidence-first" role="contract">` 內層，在 chezmoi、CommonMark/GFM/GitHub、Claude Code、Codex 全鏈路都不會誤動作（實測案例 G）。
2. **兩層各司其職**：markers 是給工具（未來的 sync 腳本）與人看的——Claude Code 注入時會把它剝掉、零 token；`<workflow>` tag 才是模型實際看到的區段邊界，且符合 Anthropic 的 XML tag 官方建議。不要把「模型需要看到的語意」寫進 comment。
3. **空行紀律**：`<workflow …>` 開標籤後、`</workflow>` 閉標籤前各留一行空行；markers 前後也留空行。否則緊鄰的 markdown 會被 type 7 HTML block 吞成 raw text（僅影響 GitHub 等 rendered 檢視，不影響送給模型的 raw text——但生成檔會被人在 GitHub 上讀，值得守住）。
4. **絕對避免**單一 comment 跨整段的寫法（`<!-- evidence-first:contract` 換行 … `-->`）：GitHub 上整段消失，且 Claude Code 會把整份 contract 從 context 剝除——等於 contract 對 Claude 靜默失效。
5. 若日後在 template 內容中出現字面 `{{`（如示範 Go template 的程式碼），chezmoi 會把它當 template action 執行——HTML comment 包不住它，需用 `{{ "{{" }}` 逃逸或 `{{/* */}}`；與 marker 本身無關，僅記錄為 pipeline 已知邊界。

## 來源清單

- Claude Code memory / CLAUDE.md 載入與 comment 剝除：<https://code.claude.com/docs/en/memory>
- Anthropic prompt engineering（XML tags）：<https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/claude-prompting-best-practices>
- AGENTS.md 格式定義：<https://agents.md/>
- CommonMark 0.31.2 HTML blocks：<https://spec.commonmark.org/0.31.2/#html-blocks>
- GFM Disallowed Raw HTML (tagfilter)：<https://github.github.com/gfm/#disallowed-raw-html-extension->（引文自 <https://raw.githubusercontent.com/github/cmark-gfm/master/test/spec.txt>）
- GitHub 渲染 pipeline 與 sanitization：<https://github.com/github/markup>
- doctoc：<https://github.com/thlorenz/doctoc>
- markdown-magic：<https://github.com/DavidWells/markdown-magic>
- terraform-docs inject 模式：<https://terraform-docs.io/user-guide/configuration/output/>
- chezmoi templating：<https://www.chezmoi.io/reference/templates/>、<https://www.chezmoi.io/reference/special-directories/chezmoitemplates/>
- Go text/template：<https://pkg.go.dev/text/template>
- spec-kitty charter sync（本機 skill 文件）：`~/.claude/skills/spec-kitty-charter-doctrine/references/charter-command-map.md`
- 實測：commonmark.js 0.31.2（CommonMark reference implementation），七組案例本機渲染驗證（2026-08-31）
