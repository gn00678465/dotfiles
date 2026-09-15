---
name: commit
description: 分析 git staged changes，根據 Conventional Commits (1.0.0-beta.4) 規範生成繁體中文 commit message，並在使用者要求提交時執行提交；在主分支 (main/master) 上只交付草稿與分支建議。使用時機包括：(1) 需要提交已暫存 (staged) 的變更、(2) 需要符合規範的提交訊息與正確的類型 (type) 與範圍 (scope)、(3) 需要根據變更內容建議一個有意義的分支名稱、(4) 變更含多個獨立目的需要原子化拆分、(5) 需要重寫或修剪既有的 commit message。適用於包含「commit this」、「create a commit」、「make a commit」、「commit staged changes」、「save my changes」、「幫我 commit」、「提交變更」、「產生 commit message」、「建立 branch」、「取個分支名」、「重寫 commit message」、「commit message 太長」、「amend commit message」、「修改提交訊息」等請求的情境。會依變更量與風險決定訊息的詳細程度，並對正文長度設上限。
---

# 慣例式提交與分支助手

根據 [Conventional Commits 1.0.0-beta.4](https://www.conventionalcommits.org/zh-hant/v1.0.0-beta.4/) 規範，分析 git staged changes 並自動生成繁體中文 commit message 與建議的分支名稱。

> **完整規範細節請參考 `references/conventional-commits-spec.md`**；本檔只保留 skill 的執行流程與本 skill 特有的格式約束。

## 核心功能

1. **分支建議 (Branch Suggestion)**：根據變更檔案內容自動生成語意化的 Git 分支名稱。
2. **提交訊息 (Commit Message)**：自動生成符合 Conventional Commits 規範的繁體中文提交訊息。
3. **主分支保護 (Main Branch Protection)**：在 `main`/`master` 上不執行提交，但照常交付訊息草稿與建議分支名。
4. **原子化拆分 (Atomic Split)**：變更含多個獨立目的且各自可建置與還原時分群提交；已授權時直接完成。

## 本 Skill 的格式約束

### 語言

- **描述、正文必須使用繁體中文**（台灣慣用技術詞彙對照見 `references/terminology.md`）

### 描述（Subject）

- 緊接在類型/作用範圍的冒號與空格之後
- 限制在 **50 字元以內**
- 使用**祈使句**（如：「新增」、「修正」、「更新」）
- **不加句號**
- 清楚描述變更的核心內容

### 正文（Body）- 可選

- 描述後一個空行之後開始
- **預設**用項目符號列表（`-` 開頭），每一行不是 `-` 開頭就是前一項的續行（縮排 2 格）；
  專案慣例有別的正文格式時照專案的來（見「長度上限（硬性）」的優先序）
- 每個項目描述一個具體變更
- **優先說明做了什麼，必要時補充原因**（原因寫一句話；完整論證見下方對照表）

#### 長度上限（硬性）

| 項目 | 上限 |
|------|------|
| 項目符號數 | 6 個 |
| 每個項目 | 2 行 |
| 每一行 | 76 字元 |
| 主旨 + 正文 | 15 個非空行 |
| `BREAKING CHANGE:` 段落 | 3 行（目標值，見下） |

計的是**非空行**：空白行是結構，不是內容。兩個數字都對齊專案既有的實踐——
以本 repo 近 30 筆 commit 量得：非空行中位數 9、第 90 百分位 13，只有 1 筆達 18；
行長最長 75、中位數 50。上限要容納常態、攔住離群值，不是憑感覺挑的。
沒有字元上限的話，一個項目可以寫成一行卻無限長。

不計入那 15 行的只有兩種：`BREAKING CHANGE:` 段落，以及 `Co-Authored-By:`、
`Refs:` 這類頁腳。

`BREAKING CHANGE:` 是規範要求的警告，**完整性優先於行數**：3 行是目標值，
說不完就超過，**絕不刪掉或截短**。完整的遷移步驟放 PR 或文件，但「破壞了什麼、
呼叫端要改什麼」必須留在提交裡。

**衝突時的優先序**（由上往下）：

1. 規範要求的內容——`BREAKING CHANGE:` 的完整性、type／subject 的格式
2. 本節的長度上限
3. 專案既有的 commit 慣例——用字、分段、頁腳、**正文格式**

**項目符號只是預設格式**：專案慣例若用別的正文形狀（編號、段落式條列、固定欄位），
照專案的來。慣例改的是形狀，不解除第 2 層的上限；上限不能刪掉第 1 層的內容。

寫入之後、`git commit` 之前先量主旨與正文。**用你所在通道的版本**（見
[寫入 `COMMIT_EDITMSG` 指引](#寫入-commit_editmsg-指引) 的通道對照表）：

POSIX shell：

```bash
GITDIR=$(git rev-parse --absolute-git-dir)
awk 'NR==1{n++; next} /^BREAKING CHANGE:/{exit} /^[A-Za-z][A-Za-z0-9-]*: /{exit} NF{n++}
     END{print n}' "$GITDIR/COMMIT_EDITMSG"
```

PowerShell（pwsh 6+ 與 Windows PowerShell 5.1 同一段）：

```powershell
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
$path = Join-Path (git rev-parse --absolute-git-dir) 'COMMIT_EDITMSG'
$n = 0; $i = 0
foreach ($l in Get-Content -Encoding utf8 $path) {
    $i++
    if ($i -eq 1) { $n++; continue }
    if ($l -match '^(BREAKING CHANGE:|[A-Za-z][A-Za-z0-9-]*: )') { break }
    if ($l.Trim()) { $n++ }
}
$n
```

兩者規則相同：第一行是主旨，一律計入並跳過樣式比對——否則 `fix: 修正…` 會被自己的
type 前綴誤判成頁腳。之後任何 `Xxx-Yyy: ` 開頭的行都視為頁腳並停止計數，所以
`Co-Authored-By:`、`Signed-off-by:`、`Claude-Session:`、`Refs:` 都不必逐一列舉。

超過上限就刪到符合，不是加一段說明為什麼超過。

#### 不寫進 commit message 的內容

commit message 回答「這次改了什麼」。下列內容有各自的位置：

| 內容 | 該去的地方 |
|------|-----------|
| 驗證數字、測試通過數、覆蓋率、mutation 結果 | evidence report／PR 內容 |
| 流程偏離紀錄（沒有事前 SPEC、測試與實作同一個 commit、違反隔離） | evidence report |
| 替代方案的比較、設計決策的完整論證、對自己選擇的辯護 | PR 內容／設計文件 |
| 過程回顧與敘事（「原本以為…後來發現…」） | session 報告 |
| 需要長期保存的非顯而易見原因 | 程式碼註解 |

單純重複的敘述**直接刪掉**，不需要另建文件。

只有**使用者或契約要求保留**的紀錄才需要去處，兩種處置擇一並在回覆中說明：

- **已有授權的保存位置** → 實際寫進去並回報路徑；沒有實際寫入就不算處理完畢。
- **沒有授權的位置**（外部 PR、他人的文件）→ 不自行建立或改寫，把內容原樣交還使用者。

### 作用範圍（Scope）- 可選

- 由描述程式區段的名詞組成，用括號包覆
- 範例：`feat(parser):`、`fix(api):`、`chore(eslint):`

### 類型速查表

| 類型 | 用途 | SemVer |
|------|------|--------|
| `feat` | 新增功能 | MINOR |
| `fix` | 修正臭蟲 | PATCH |
| `docs` | 文件更新 | — |
| `style` | 程式碼格式調整（不影響功能） | — |
| `refactor` | 重構程式碼 | — |
| `perf` | 效能優化 | — |
| `test` | 測試相關 | — |
| `build` | 建置系統或外部相依性 | — |
| `ci` | CI 設定檔案 | — |
| `chore` | 其他雜項 | — |
| `revert` | 撤銷先前的 commit | — |

### 重大變更（Breaking Changes）

兩種標示方式（擇一或合併使用）：

1. 類型後加 `!`：`feat(api)!: 變更使用者認證機制`
2. 頁腳標示：`BREAKING CHANGE: <描述>`（**`BREAKING CHANGE` 必須大寫**）

使用 `!` 時，正文或頁腳**必須**包含 `BREAKING CHANGE: description`。完整範例見 `references/examples.md`。

規範允許 `BREAKING CHANGE:` 放在正文或頁腳。本 skill 一律放在正文之後的頁腳區，
不夾在正文中間：長度上限的量測以第一個頁腳標記為界，位置不固定就會讓同一段文字
因為擺放位置不同而算進或算出。

## 執行步驟

### 步驟 0：判定這次要交付什麼

只交付使用者要的東西。**寫 commit message 不等於提交。**

| 使用者要的 | 交付 | 執行提交 |
|-----------|------|---------|
| 分析、複雜度、風險 | 分析結果 | 否 |
| commit message、訊息草稿 | 訊息文字 | 否 |
| 分支名稱建議 | 名稱 | 否 |
| 提交、commit、「幫我 commit」 | 訊息並提交 | 是 |

授權依**目前任務範圍**與對話中**仍有效**的授權判定；後續訊息是同一任務的延續時
沿用授權，不重複詢問。無關的新任務不沿用先前的提交授權。
要提交才走步驟 5b；只要訊息就停在步驟 5a，把訊息內容回報給使用者。

### 步驟 1：取得分析資訊

執行輔助腳本，輸出為單一 JSON 物件：

```bash
uv run <skill-dir>/scripts/analyze_git.py
# 或（無 uv 時）
python <skill-dir>/scripts/analyze_git.py
```

**輸出 JSON schema：**

```json
{
  "branch": "feature/foo",
  "is_main": false,
  "score": 7,
  "risk_factors": ["大量變更 (250 行)", "涉及認證或安全邏輯"],
  "files_changed": 4,
  "total_lines": 250,
  "insertions": 200,
  "deletions": 50,
  "files": {
    "new": ["src/login.tsx"],
    "modified": ["src/auth.ts"],
    "deleted": [],
    "renamed": []
  },
  "suggested_branches": ["feat/login", "feat/auth-logic"]
}
```

| 欄位 | 說明 |
|------|------|
| `files.new` | 新增的檔案（`git status` 顯示 `A`） |
| `files.modified` | 修改的現有檔案（顯示 `M`） |
| `files.deleted` | 刪除的檔案（顯示 `D`） |
| `files.renamed` | 重新命名或複製的檔案（`R`/`C`，格式 `"old -> new"`） |

若無 staged 變更，腳本會以非零 exit code 結束並於 stderr 輸出錯誤。

### 步驟 2：檢查分支

依 `is_main` 判斷：

**情況 A（安全分支）：** `is_main = false`
- 繼續執行步驟 3。

**情況 B（主分支）：** `is_main = true`

主分支保護**只限制提交**，不限制其他交付：

- 照常走完步驟 3 到 5a，產出完整的 commit message 草稿並交給使用者。
- 依 `suggested_branches` 建議符合規範的**新分支名稱**（例如：`feat/login-form-validation`、`fix/payment-bug`）。
- 建立或切換分支是另一個動作，依授權分兩條路：
  - **已有建立／切換分支的授權** → 執行切換，**回到步驟 2 重新檢查** `is_main`，
    然後照常繼續（已授權提交就走到 5b）。主分支保護到此解除，不是停在這裡。
  - **沒有分支授權** → 交付訊息草稿與建議分支名，回報：
    `目前在主分支，訊息已備妥；缺的是建立／切換分支的授權。`
    不從「他要提交」推定「他授權我開分支」。

### 步驟 3：分析複雜度與模式

`score` 只決定**分析深度**，不決定拆不拆：

| 分數 | 通常需要的深度 |
|------|--------------|
| `< 4` | 單行（type + subject）通常就夠 |
| `4 ≤ score ≤ 8` | 通常需要正文說明 |
| `> 8` | 需要正文，並依下方判準檢查是否該拆分 |

正文寫不寫，看**變更本身有沒有需要解釋的細節**；分數只是提示。沒有細節要解釋時，
分數落在中段也可以只寫一行，不必為了湊分數硬加正文。

**拆分判準看變更本身，不看分數：**

- 各群**有獨立目的**，且每一群的**相依性完整**（可各自建置、可各自還原）→ 進入步驟 4。
- **無法各自建置或獨立還原 → 留在同一個提交。** 硬拆會產生建置不過、或還原不了的
  中間狀態，比一個大提交更難處理。
- 提交型別不同**不是**拆分理由。分數高也不是——高分只代表要寫得清楚一點。

### 步驟 4：原子化拆分提交

只在步驟 3 的判準成立時進入。

1. **分群**：依獨立目的分群，每一群的相依性完整。**含部分暫存的檔案照樣納入所屬群**。
   只有某個檔案歸哪一群無法從變更內容判定時才澄清；分組明確且提交已授權就直接完成，
   不再詢問是否需要協助。未授權提交時只輸出各群的檔案清單與訊息。
2. 每一群先走步驟 5a 產出該群訊息，**再依步驟 5b 的寫入指引把「這一群」的訊息寫進
   `COMMIT_EDITMSG`**，然後用下面的指令提交（取代 5b 的 `git commit`）。**路徑逐一列出**，
   不要用變數展開——有些 shell 不對未加引號的展開分詞，整群會變成一個不存在的路徑：

```sh
(                                           # 子 shell：set -e 與 trap 不留在互動終端機
  set -e                                    # 任一步失敗即中止這一群
  GITDIR=$(git rev-parse --absolute-git-dir)
  IDX=$(mktemp); P=$(mktemp)
  trap 'rm -f "$IDX" "$P"' EXIT             # 清理不吃掉失敗的退出碼
  # 先依 5b 的寫入指引，把「這一群」的訊息寫進 "$GITDIR/COMMIT_EDITMSG"
  git diff --cached --binary -- path/one path/two > "$P"   # 原索引的內容
  GIT_INDEX_FILE="$IDX" git read-tree HEAD
  GIT_INDEX_FILE="$IDX" git apply --cached "$P"
  GIT_INDEX_FILE="$IDX" git commit -F "$GITDIR/COMMIT_EDITMSG"
)
```

   PowerShell（pwsh 7 與 5.1 同一段）。修補檔用 `--output=` 寫出：5.1 的 `>` 會把它轉成
   UTF-16，`git apply` 就失敗。`GIT_INDEX_FILE` 在 `finally` 清掉，否則同一個終端機之後的
   git 指令都會用到臨時索引：

```powershell
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
$path = Join-Path (git rev-parse --absolute-git-dir) 'COMMIT_EDITMSG'
# 先依 5b 的寫入指引，把「這一群」的訊息寫進 $path
$idx = [IO.Path]::GetTempFileName(); $p = [IO.Path]::GetTempFileName()
try {
    git diff --cached --binary --output=$p -- path/one path/two; if ($LASTEXITCODE) { throw 'git diff 失敗' }
    $env:GIT_INDEX_FILE = $idx
    git read-tree HEAD;    if ($LASTEXITCODE) { throw 'git read-tree 失敗' }
    git apply --cached $p; if ($LASTEXITCODE) { throw 'git apply 失敗' }
    git commit -F $path;   if ($LASTEXITCODE) { throw 'git commit 失敗' }
} finally {
    Remove-Item Env:GIT_INDEX_FILE -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $idx, $p -ErrorAction SilentlyContinue
}
```

   **失敗就停在這一群**，不要繼續下一群：已提交的群留著，未提交的群仍在原索引裡，
   回報停在哪一群與原因。**被 Ctrl+C 中斷時，先用 `git log -1` 確認這一群是否已提交**，
   再回報：Windows 上在 hook 執行中中斷，shell 顯示中斷，git 仍完成了提交。重跑已提交
   的群會因修補檔為空而失敗，不會重複提交。

   工作樹完全不碰，`git add` 一次都不用：未暫存的段落逐位元保留。真實索引保留尚未
   提交的群；已提交的群因 HEAD 追上而自然不再算 staged。
3. **審閱提交內容用 `git diff --cached`**，不要用 `git diff`——後者描述的是未暫存的部分。
4. **回報**：每一群的 SHA，以及工作樹剩下哪些未暫存變更。

#### 範例

```markdown
### 兩個獨立目的，各自可建置與還原

認證邏輯重構與套件更新彼此不相依，拆成兩個提交：

#### 第一步：重構認證邏輯
- 路徑：`src/auth.ts src/security.ts`（`src/security.ts` 為部分暫存，只取已暫存的段落）
- Commit Message：`refactor(auth): 重構認證模組安全性邏輯`

#### 第二步：更新套件
- 路徑：`pnpm-lock.yaml`
- Commit Message：`build: 更新相依性鎖定檔`

兩群都用上面的臨時 `GIT_INDEX_FILE` 指令提交。工作樹未動：`src/ui.tsx` 的未暫存變更、
以及 `src/security.ts` 未暫存的那段，都原樣留著。
```

### 步驟 5：生成 Commit Message（5a），必要時提交（5b）

#### 步驟 5a：產出訊息（一律執行）

1. **依檔案狀態決定 commit type**（優先使用，再搭配 diff 內容確認）：

   | 狀況 | 建議類型 |
   |------|---------|
   | `files.new` 為主，且為功能性程式碼 | `feat` |
   | `files.new` 為主，且為測試檔案（`*.test.*`, `*.spec.*`） | `test` |
   | `files.new` 為主，且為文件（`.md`, `.txt`） | `docs` |
   | 僅有 `files.modified`，修正問題邏輯 | `fix` |
   | 僅有 `files.modified`，程式碼重構（無功能變更） | `refactor` |
   | 僅有 `files.renamed` 或檔案搬移 | `refactor` |
   | 僅有 `files.deleted`（清理舊程式碼） | `chore` 或 `refactor` |
   | 混合多種狀態，涉及功能新增 | `feat`（並考慮拆分） |

2. 結合 `git diff --cached` 內容確認描述的精確性（`git diff` 描述的是未暫存的部分，不是要提交的）。
3. 依上方格式約束寫出訊息，並用「長度上限（硬性）」一節中**你所在通道**的量測指令
   量主旨與正文；超過 15 個非空行就刪短。量測對草稿文字直接做即可。
4. 步驟 0 判定**只要訊息**時**到此為止**：把訊息文字交給使用者，**不寫
   `COMMIT_EDITMSG`**、不碰索引，`git log` 的 HEAD 不變。

#### 步驟 5b：執行提交（僅在提交已授權時）

5. **寫入 `COMMIT_EDITMSG`**：依下方 [寫入 `COMMIT_EDITMSG` 指引](#寫入-commit_editmsg-指引)，先取 `GITDIR`／`$path` 再寫入。
6. **提交**：

```bash
GITDIR=$(git rev-parse --absolute-git-dir)      # POSIX
git commit -F "$GITDIR/COMMIT_EDITMSG"
```

```powershell
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)   # PowerShell
$path = Join-Path (git rev-parse --absolute-git-dir) 'COMMIT_EDITMSG'
git commit -F $path
```

7. **回報結果**：commit 已完成，附上 commit SHA 與訊息摘要；不再詢問是否需要協助執行同一命令。

#### 寫入 `COMMIT_EDITMSG` 指引

> 注意：以下表格、code block 故意對齊到第 0 欄，避免 list 縮排把 here-doc / here-string 的終止符也帶進 code block 內容，導致複製貼上時 `EOF` / `'@` 解析失敗。

⚠️ **先取絕對路徑，不要寫死 `.git/COMMIT_EDITMSG`**。在 git worktree 裡 `.git` 是**檔案**不是目錄，寫死的相對路徑會以 `not a directory: .git/COMMIT_EDITMSG` 失敗（exit 128）。子目錄下執行也一樣。每個通道都先取：

```bash
GITDIR=$(git rev-parse --absolute-git-dir)
```

⚠️ **每個區塊自己取路徑，整塊一次執行**。Claude Code 的 `Bash` 與 `PowerShell` 工具每次呼叫都是新的 shell，上一次呼叫設定的 `$GITDIR`、`$path`、`$BEFORE_TREE` 在下一次都是空值：`-F "$GITDIR/COMMIT_EDITMSG"` 會讀到 git 安裝目錄下的檔案，核對段會回報 tree 已變，但實際沒有變。所以本檔每個區塊都先取路徑，不要把一個區塊拆成多次呼叫。

⚠️ **PowerShell 區塊先把 `[Console]::OutputEncoding` 設成 UTF-8**。PowerShell 用主控台的 code page 解碼 `git` 的輸出，繁體中文 Windows 預設是 950。repo 路徑含中文時，`$path` 會變成亂碼，pwsh 7 與 5.1 都會寫入失敗。Claude Code 的 `PowerShell` 工具已經是 65001，但終端機的 pwsh 與 5.1 不是。

⚠️ **不要用標準輸入把腳本傳給 PowerShell**（`... | pwsh -Command -` 或 `powershell -Command -`）。在這個模式下，here-string 後面沒有空行時，整段會被丟棄，檔案沒有寫出，但 rc 仍是 0。中文也會以主控台 code page 解碼，寫出的位元組已經損毀。要傳腳本，請在主控台直接輸入、用 `-Command` 參數傳入，或用 `-File` 執行。

⚠️ **不要使用 Claude Code 的 `Write` 工具**。`COMMIT_EDITMSG` 在任何一次 commit 之後就已經存在，`Write` 會以 `File has not been read yet. Read it first before writing to it.` 失敗。

⚠️ **下方語法不可互換**。動手前先確認你的**執行通道**：

| 執行通道 | 用哪段範例 | 判斷依據 |
|---------|-----------|---------|
| Claude Code `Bash` 工具 | POSIX shell | 即使在 Windows 也是 git-bash (`/usr/bin/bash`)。**不要**用 PowerShell 語法 |
| Claude Code `PowerShell` 工具 | PowerShell Core (`pwsh`, 6+) | Claude Code 內建呼叫 `pwsh`（目前通常 7+），**不是** Windows 5.1 內建的 `powershell.exe` |
| 終端機：bash / zsh / sh | POSIX | `echo $SHELL` |
| 終端機：PowerShell | 看 `$PSVersionTable.PSEdition`：`Core` → pwsh 範例；`Desktop` → 5.1 fallback | `$PSVersionTable.PSEdition` |
| 其他 agent harness（Codex / Aider / 自訂） | 視該 harness 的 shell 而定；預設先試 POSIX，報 `Set-Content not found` 再切 PowerShell | 看 harness 文件或執行時觀察錯誤 |
| `cmd.exe` | 本節範例皆不適用 | 切到 bash 或 pwsh |

**常見誤用對照：**

- PowerShell 的 `@'...'@`、`Set-Content` 丟給 bash → `@: No such file or directory`、`Set-Content: command not found`
- bash 的 `<<'EOF'` 丟給 PowerShell → 被當成重新導向解析失敗
- ⚠️ **不要用 PowerShell 的 `>` / `>>`**：5.1 的 `>` 走 `Out-File` 預設 UTF-16LE，會直接污染 commit 檔案

##### POSIX shell (bash/zsh)

```bash
GITDIR=$(git rev-parse --absolute-git-dir)
cat > "$GITDIR/COMMIT_EDITMSG" <<'EOF'
<type>(<scope>): <subject>

- bullet 1
- bullet 2
EOF
```

##### PowerShell Core (`pwsh`, 6+)

⚠️ 閉合的 `'@` **必須在第 0 欄，不能有縮排**，否則 here-string 解析失敗。

```powershell
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
$path = Join-Path (git rev-parse --absolute-git-dir) 'COMMIT_EDITMSG'
@'
<type>(<scope>): <subject>

- bullet 1
- bullet 2
'@ | Set-Content -Encoding utf8NoBOM $path
```

必須用 `utf8NoBOM`（pwsh 6+ 才有此選項）。`Set-Content -Encoding utf8` 在 **Windows PowerShell 5.1** 會寫入 UTF-8 BOM (`EF BB BF`)，git 會把 BOM 當成 subject 首字元，破壞 commit 訊息。

##### Windows PowerShell 5.1 fallback

改用 .NET API 寫出無 BOM，並以 `git rev-parse --absolute-git-dir` 取得絕對路徑（支援 worktree 與子目錄；同時避免 .NET 與 PS 的 cwd 不同步）：

```powershell
$msg = @'
<type>(<scope>): <subject>

- bullet 1
- bullet 2
'@
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
$path = Join-Path (git rev-parse --absolute-git-dir) 'COMMIT_EDITMSG'
[System.IO.File]::WriteAllText($path, $msg, [System.Text.UTF8Encoding]::new($false))
```

把這段存成 `.ps1` 再用 `-File` 執行時，檔案必須有 UTF-8 BOM。5.1 用 ANSI code page 讀取無 BOM 的腳本，中文字元會吃掉 here-string 結尾的 `'@`，造成解析失敗（`字串遺漏結尾字元: '@`）。在主控台直接輸入，或用 `-Command` 參數傳入，都不受影響。

##### 退路（任何通道皆不可用時）

若上述寫法在你的執行環境都不可用（例如受限 shell 或沒有檔案系統存取的沙箱），才退回「先 `Read` `COMMIT_EDITMSG` 再 `Write`」的兩步流程，路徑一樣取自 `git rev-parse --absolute-git-dir`。

### 步驟 6：修改既有的 commit message

**先走步驟 0**：使用者要的是「改寫後的訊息文字」還是「改寫這個提交」。只要文字就
交付文字。出現「重寫」「太長」字樣不等於授權改寫歷史。主分支保護照樣適用：在
main／master 上不執行 amend。

1. **重寫並預覽**：`git log -1 --format=%B <sha>` 看現況，套用「長度上限（硬性）」與
   「不寫進 commit message 的內容」兩節，寫進 `COMMIT_EDITMSG`，再並排：

```sh
GITDIR=$(git rev-parse --absolute-git-dir)
OLD=$(mktemp); git log -1 --format=%B <sha> > "$OLD"
diff -u "$OLD" "$GITDIR/COMMIT_EDITMSG"; rm -f "$OLD"
```

2. **確認授權**：

   | 目標 | 需要 |
   |------|------|
   | 最新一筆、未分享 | 直接 amend |
   | 較早的提交（`git rebase -i`） | 明確批准改寫歷史 |
   | 已分享／已推送 | 明確批准；該批准**不含** `git push` |

   對話中已有**同範圍**批准就沿用，不重問。查不到遠端（`git branch -r` 無對應分支、
   `git ls-remote` 不通）只代表**證據不足**，不能當作沒分享——證據不足時當已分享處理。

3. **依目標分流**，不要一律 amend HEAD：

   - **目標就是最新一筆** → 做第 4 點。
   - **目標是更早的提交** → 取得明確批准後，用下面的區塊只改那一筆的訊息。**不要套用
     第 4 點的 amend 指令，那只適用於 HEAD**。

   Claude Code 的工具不能操作互動式編輯器，所以區塊用 `GIT_SEQUENCE_EDITOR` 把第一行的
   動作改成 `reword`，用 `GIT_EDITOR` 填入新訊息，讓 `git rebase -i` 不需要人操作。
   動作不寫死 `pick`：設定 `rebase.abbreviateCommands` 時第一行是 `p`。

   - 工作樹或索引有變更時 rebase 會拒絕執行。**不要自行 stash**，回報使用者。
     三個 `--no-*` 旗標蓋過使用者的 git 設定（本 repo 的 git config 就開了前兩項）：
     `rebase.autoStash` 會把已暫存的變更還原成未暫存，`rebase.autoSquash` 會併掉範圍內的
     `fixup!` 提交，`rebase.updateRefs` 會改寫指向範圍內的其他分支。`--no-update-refs` 需要
     git 2.38 以上；更舊的版本以 `unknown option` 停止，回報使用者升級 git。
   - 範圍內有合併提交時停止並回報：`git rebase -i` 會把合併攤平，改到的不只訊息。
   - 目標是根提交時沒有 `<sha>^` 可當基準，區塊會失敗並停止；回報使用者，不要自行改用 `--root`。
   - rebase 會覆寫 `COMMIT_EDITMSG`，所以區塊先把新訊息複製到暫存檔。
   - 核對範圍內**每一筆**提交的 tree，不只 HEAD。

```sh
GITDIR=$(git rev-parse --absolute-git-dir)
TARGET=$(git rev-parse --verify '<sha>^{commit}')
MSG=$(mktemp); cp "$GITDIR/COMMIT_EDITMSG" "$MSG"
BEFORE=$(git log --format=%T "$TARGET^..HEAD")
if [ -n "$(git rev-list --merges "$TARGET^..HEAD")" ]; then
  echo "範圍內有合併提交：停止並回報"
elif GIT_SEQUENCE_EDITOR="sed -i '1s/^[^ ]*/reword/'" GIT_EDITOR="cp '$MSG'" \
     git rebase -i --no-autostash --no-autosquash --no-update-refs "$TARGET^"; then
  if [ "$(git log --format=%T "$TARGET^..HEAD")" = "$BEFORE" ]; then echo "每一筆 tree 未變"
  else echo "tree 變了：回報這件事"; fi
else
  git rebase --abort 2>/dev/null; echo "rebase 失敗，分支已還原：回報這件事"
fi
rm -f "$MSG"
```

```powershell
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
$path   = Join-Path (git rev-parse --absolute-git-dir) 'COMMIT_EDITMSG'
$target = git rev-parse --verify '<sha>^{commit}'
$msg    = [IO.Path]::GetTempFileName(); Copy-Item -LiteralPath $path -Destination $msg
$before = (git log --format=%T "$target^..HEAD") -join ' '
try {
    if (git rev-list --merges "$target^..HEAD") { throw '範圍內有合併提交：停止並回報' }
    $env:GIT_SEQUENCE_EDITOR = "sed -i '1s/^[^ ]*/reword/'"
    $env:GIT_EDITOR = "cp '$msg'"
    git rebase -i --no-autostash --no-autosquash --no-update-refs "$target^"
    if ($LASTEXITCODE) { git rebase --abort 2>$null; throw 'rebase 失敗，分支已還原：回報這件事' }
    if (((git log --format=%T "$target^..HEAD") -join ' ') -eq $before) { '每一筆 tree 未變' } else { 'tree 變了：回報這件事' }
} finally {
    Remove-Item Env:GIT_SEQUENCE_EDITOR, Env:GIT_EDITOR -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $msg -ErrorAction SilentlyContinue
}
```

4. **執行 message-only amend 並核對**。`--only` 是關鍵，少了它索引內容會被吞進提交。
   記錄基準、amend、核對三段放在同一個區塊，**一次呼叫執行完**（原因見寫入指引）。
   核對失敗必須講出來：

```sh
GITDIR=$(git rev-parse --absolute-git-dir)
BEFORE_TREE=$(git rev-parse HEAD^{tree})
BEFORE_INDEX=$(git write-tree)   # 索引的完整內容；檔名清單證明不了內容沒變
git commit --amend --only -F "$GITDIR/COMMIT_EDITMSG"
if [ "$(git rev-parse HEAD^{tree})" = "$BEFORE_TREE" ]; then echo "tree 未變"
else echo "tree 變了：提交內容被改動，回報這件事"; fi
if [ "$(git write-tree)" = "$BEFORE_INDEX" ]; then echo "索引未變"
else echo "索引變了：回報這件事"; fi
```

```powershell
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
$path         = Join-Path (git rev-parse --absolute-git-dir) 'COMMIT_EDITMSG'
$BEFORE_TREE  = git rev-parse 'HEAD^{tree}'    # 引號：PS 會把 {} 當運算式
$BEFORE_INDEX = git write-tree
git commit --amend --only -F $path
if ((git rev-parse 'HEAD^{tree}') -eq $BEFORE_TREE) { "tree 未變" } else { "tree 變了：提交內容被改動" }
if ((git write-tree) -eq $BEFORE_INDEX) { "索引未變" } else { "索引變了" }
```

5. **SHA 引用**：只改**使用者授權你改的**檔案。歷史證據（evidence report、驗證報告、
   已送出的 PR）一律不改，加註「`<old>` 與 `<new>` 的 tree 相同」即可。未授權的檔案
   （含 README、待辦）把該改的位置列給使用者，不自行動手。
6. **回報**：新舊 SHA、行數變化、第 3 或第 4 點的核對結果、改了哪些引用、哪些沒改。

## 範例

詳細範例請參考 `references/examples.md`，涵蓋：

- **基礎範例**：feat、fix、docs、style、refactor、perf、test、build、ci、chore、revert
- **進階範例**：含作用範圍、破壞性變更、問題編號、共同作者、複雜變更
- **不良範例**：常見錯誤寫法與修正建議

**快速參考：**

```
feat: 新增使用者登入功能

- 實作 JWT 認證機制
- 新增登入表單驗證
```

```
fix(cart): 修正購物車金額計算錯誤

- 修正折扣碼套用順序問題
```

## 注意事項

- **僅 staged 狀態的變更會被考慮**；未 staged 的變更不會納入分析。建議先用 `git add` 選擇性地 stage 要提交的變更。
- **Lock 檔案偵測範圍**：`package-lock.json`、`yarn.lock`、`pnpm-lock.yaml`、`bun.lockb`、`Cargo.lock`、`go.sum`、`poetry.lock`、`Gemfile.lock`、`composer.lock`。
- 變更過於複雜時，優先拆分為多個獨立 commit；橫跨多種提交類型時的拆分判準見步驟 3，不單獨因型別不同而拆分。

## 參考資料

- `references/conventional-commits-spec.md` - 慣例式提交 1.0.0-beta.4 完整規範
- `references/examples.md` - 各類型 commit message 範例集
- `references/terminology.md` - 繁體中文（台灣慣用）技術詞彙對照
- [Conventional Commits 官方網站](https://www.conventionalcommits.org/zh-hant/v1.0.0-beta.4/)
- [SemVer 語意化版本](https://semver.org/lang/zh-TW/)
- [@commitlint/config-conventional](https://github.com/conventional-changelog/commitlint/tree/master/%40commitlint/config-conventional)
