# chezmoi 模板與「部分管理」設定檔研究

> **本檔位置是新的慣例。** 這個 repo 先前沒有 research notes 的放置慣例（`docs/` 底下只有
> `docs/agents/`）。本檔開啟 `docs/research/` 作為研究筆記的存放處。
>
> **`.chezmoiignore` 不需要改。** 現有 `.chezmoiignore` 已經有 `docs/` 這一行，而 chezmoi 在
> 來源狀態掃描時遇到被忽略的目錄就不會往下走，整個子樹（含 `docs/research/`）都不會進入
> target state。已實測驗證：在 `docs/research/probe.md` 放一個探針檔後，
> `chezmoi --source . --destination /tmp/fakehome_probe managed` 沒有任何 `docs` 開頭的項目，
> 而 `chezmoi ignored` 列出 `docs`。
>
> 驗證環境：`chezmoi version v2.72.0, commit f81cb321789aa3df62871248f5e4d361a59e7cc1,
> built at 2026-08-02`（本機實際安裝版本）。文中標記「**實測**」的段落都是在這個版本上跑出來的結果。

---

## 0. 先講結論（Answer first）

| 目標檔案 | 建議機制 | 來源檔名 |
|---|---|---|
| `~/.claude/settings.json` | **`modify_` + modify-template（純模板，無外部二進位）** | `dot_claude/modify_settings.json` |
| `~/.codex/config.toml` | **`modify_` shell script（awk 逐行改寫）**；若不在意註解與排序，才用純模板 | `dot_codex/modify_config.toml` |

**為什麼是 `modify_`：** chezmoi 對「只管檔案的一部分」只有兩個一級機制——`create_`（只在檔案不存在時建立，
之後永不更新）與 `modify_`（把來源檔當成腳本，收 target 現有內容、吐出新內容）。使用者的需求是
「工具會持續寫入、chezmoi 只固定幾個 key」，`create_` 做不到（它在第一次之後就完全放手），
所以唯一的答案是 `modify_`。
（[target-types → Create file / Modify file](https://www.chezmoi.io/reference/target-types/#create-file)）

**為什麼 JSON 用純模板：** chezmoi 內建 `fromJson` / `setValueAtPath` / `toPrettyJson`，可以完全在
模板裡做 merge，**不需要 jq**。JSON 沒有註解，`fromJson → toPrettyJson` 的往返只會改變排版與 key 順序
（會變成字典序），語意完全保留。本機目前 `jq`、`dasel`、`yq`、`toml-cli` **全都沒有安裝**（實測），
所以「零外部相依」是實質優勢，不是理論優勢。

**為什麼 TOML 不建議用純模板：** `fromToml | toToml` 往返是**語意保留但語法有損**，而且有一個會**改壞資料**的陷阱：

- 註解全部消失（實測：`# my codex config` 被吃掉）
- top-level key 重排成字典序、table 被重新縮排、`[mcp_servers.foo]` 被拆成 `[mcp_servers]` + `[mcp_servers.foo]`
- multi-line string `"""..."""` 被壓成 `"multi\nline"`
- **不帶 offset 的 TOML local date/time 會被本機時區位移**：`ld = 2024-01-01` 在 `TZ=Asia/Taipei`
  下往返後變成 `2023-12-31`（實測；`TZ=UTC` 下才不變）。這是實質的資料毀損。

`~/.codex/config.toml` 是手寫、有註解、有 `[mcp_servers.*]` 區塊的檔案，全檔重排會讓
`chezmoi diff` 每次都是一大片雜訊，也會弄丟使用者自己的註解。所以 TOML 這半邊用
**shell-mode `modify_` + awk 逐行改寫**：只替換指定的 top-level key、其餘位元組原封不動。
細節與可直接使用的腳本見 §4.2。

---

## 1. 模板基礎（Template fundamentals）

### 1.1 `.tmpl` 後綴：什麼時候會被當成模板

- 來源狀態裡「檔名以 `.tmpl` 結尾」的檔案會被當成模板算繪。
  （[source-state-attributes → Suffixes](https://www.chezmoi.io/reference/source-state-attributes/)：
  `.tmpl` = "Treat the contents of the source file as a template"）
- 例外（無條件當模板，不需要 `.tmpl`）：
  - `.chezmoiignore` — 「`.chezmoiignore` is interpreted as a template, whether or not it has a
    `.tmpl` extension」（[chezmoiignore](https://www.chezmoi.io/reference/special-files/chezmoiignore/)）
  - `.chezmoi.$FORMAT.tmpl` — config 檔模板，`chezmoi init` 專用
    （[.chezmoi.$FORMAT.tmpl](https://www.chezmoi.io/reference/special-files/chezmoi-format-tmpl/)）
  - `modify_` 檔案裡含有 `chezmoi:modify-template` 字串時（見 §2.1）——**而且這種檔案不可以有 `.tmpl`**。
- 這個 repo 現有的用法都符合：`dot_zshrc.tmpl`、`dot_zprofile.tmpl`、
  `.chezmoiscripts/run_onchange_before_10-install-packages.sh.tmpl` 等。

### 1.2 `.chezmoi` 模板變數

官方清單見 [templates/variables](https://www.chezmoi.io/reference/templates/variables/)。與本題相關的：

| 變數 | 說明 |
|---|---|
| `.chezmoi.os` | `darwin` / `linux` / `windows` |
| `.chezmoi.arch` | `amd64` / `arm64` … |
| `.chezmoi.hostname` | 第一個 `.` 之前的主機名 |
| `.chezmoi.fqdnHostname` | 完整網域主機名 |
| `.chezmoi.username` / `.chezmoi.uid` / `.chezmoi.gid` / `.chezmoi.group` | 執行者身分 |
| `.chezmoi.homeDir` | 家目錄（一律用 `/` 分隔） |
| `.chezmoi.sourceDir` / `.chezmoi.destDir` / `.chezmoi.workingTree` | 路徑 |
| `.chezmoi.sourceFile` | 模板相對於 source dir 的路徑 |
| `.chezmoi.targetFile` | target 檔案的絕對路徑 |
| `.chezmoi.kernel` | Linux 專用，來自 `/proc/sys/kernel`（本 repo 的 `.chezmoi.toml.tmpl` 就用它判 WSL） |
| `.chezmoi.osRelease` | Linux 專用，來自 `/etc/os-release` |
| `.chezmoi.config` | 目前 config 檔的內容 |
| `.chezmoi.version` | `version` / `commit` / `date` / `builtBy` |
| **`.chezmoi.stdin`** | **只在 modify-template 執行期間存在**，見 §2.1 |

`.chezmoi.stdin` 在上面那份 reference 頁面**沒有被列出來**（實測抓頁面確認），它只記在
[target-types → Modify file](https://www.chezmoi.io/reference/target-types/#modify-file) 與
[manage-different-types-of-file](https://www.chezmoi.io/user-guide/manage-different-types-of-file/#manage-part-but-not-all-of-a-file)。
在原始碼中，它是在 modify 這條路徑上**臨時**塞進 template data 的：

```go
// internal/chezmoi/sourcestate.go, newModifyTargetStateEntryFunc
// Temporarily set .chezmoi.stdin to the current contents and
// .chezmoi.sourceFile to the name of the template.
templateData := s.TemplateData()
if chezmoiTemplateData, ok := templateData["chezmoi"].(map[string]any); ok {
    chezmoiTemplateData["stdin"] = string(currentContents)
    chezmoiTemplateData["sourceFile"] = sourceRelPath.RelPath().String()
}
```

（[sourcestate.go `newModifyTargetStateEntryFunc`](https://github.com/twpayne/chezmoi/blob/master/internal/chezmoi/sourcestate.go)）

在一般模板裡引用 `.chezmoi.stdin` 會直接報 `map has no entry for key "stdin"`（實測，見 §5.3）。

### 1.3 config 裡的 user-defined `data`

`~/.config/chezmoi/chezmoi.toml` 的 `[data]` 區塊會被展平成模板的頂層變數。本 repo 的
`.chezmoi.toml.tmpl` 就是這樣做的：

```toml
[data]
    isWSL = {{ $isWSL }}
```

然後 `dot_zshrc.tmpl` 直接用 `{{ if .isWSL }}`（不需要 `.data.` 前綴）。
（[manage-machine-to-machine-differences](https://www.chezmoi.io/user-guide/manage-machine-to-machine-differences/)）

### 1.4 `.chezmoi.toml.tmpl` 與 `prompt*Once`

- `.chezmoi.$FORMAT.tmpl` 由 `chezmoi init` 執行來產生／更新 config 檔。它「在讀取 source state
  **之前**」執行，因此：config 檔資料 ✅、`.chezmoidata.*` 🚫、`.chezmoitemplates` 🚫、
  一般模板函式 ✅、init 函式 ✅。
  （[.chezmoi.$FORMAT.tmpl](https://www.chezmoi.io/reference/special-files/chezmoi-format-tmpl/)）
- 也會在支援 `--init` 的指令（例如 `chezmoi update --init`）時被重跑。同上頁。
- `promptStringOnce` *map* *path* *prompt* [*default*]：「returns the value of *map* at *path* if
  it exists and is a string value, otherwise it prompts the user」。官方範例：

  ```
  {{ $email := promptStringOnce . "email" "What is your email address" }}
  ```

  （[promptStringOnce](https://www.chezmoi.io/reference/templates/init-functions/promptStringOnce/)）
- 同系列還有 `promptBoolOnce` / `promptIntOnce` / `promptChoiceOnce` / `promptMultichoiceOnce`，
  以及不帶 `Once` 的 `promptString` / `promptBool` / `promptInt` / `promptChoice` / `promptMultichoice`
  與 `exit` / `writeToStdout`。
  （[init-functions 目錄](https://www.chezmoi.io/reference/templates/init-functions/)）
- 傳給 `promptXxxOnce` 的第一個參數 `.`，在 config 模板脈絡下就是「現有 config 的 data」，
  所以第二次 `chezmoi init` 不會再問。

**本 repo 現況：** `.chezmoi.toml.tmpl` 目前**完全沒有用 prompt**，`isWSL` 是自動偵測的。
若之後要為 Claude/Codex 加入需要人工輸入的值（例如 API base URL），`promptStringOnce` 是既有慣例的自然延伸。

### 1.5 `chezmoi execute-template`：不套用就能測模板

（[execute-template](https://www.chezmoi.io/reference/commands/execute-template/)）

```sh
chezmoi execute-template '{{ .chezmoi.os }}'          # 字面模板
chezmoi execute-template < dot_zshrc.tmpl              # 無參數時從 stdin 讀整個檔
chezmoi execute-template --file dot_zshrc.tmpl         # 把參數當檔名
chezmoi execute-template --init --promptString email=me@home.org < .chezmoi.toml.tmpl
```

關鍵旗標（本題會用到）：

- `--with-stdin`：「If run with arguments, then set `.chezmoi.stdin` to the contents of the standard
  input.」——**這就是測 modify-template 的正確方式**。注意文件明講「if run with arguments」，
  所以必須搭配 `--file <path>` 或字面模板參數，單純 `chezmoi execute-template --with-stdin < file`
  是無效的（實測會噴 `map has no entry for key "stdin"`）。
- `--init` / `-p, --promptString` / `--promptBool` / `--promptChoice` / `--promptInt` /
  `--promptMultichoice`：模擬 init 函式。
- `--stdinisatty` *bool*：模擬 `stdinIsATTY`。

---

## 2. 部分管理的各種機制

### 2.1 `modify_`（主角）

官方定義，逐字（[target-types → Modify file](https://www.chezmoi.io/reference/target-types/#modify-file)）：

> Files with the `modify_` prefix are treated as scripts that modify an existing file.
>
> If the file contains the string `chezmoi:modify-template`, then all lines containing that string
> will be removed, and the rest of the file will be interpreted as a template. The template is
> executed with the existing file's contents passed as a string in `.chezmoi.stdin`. The result of
> the template execution becomes the new contents of the file.
>
> Otherwise, the script receives the current contents of the target file on standard input and must
> write the new contents to standard output. If the target file does not exist, the script's
> standard input will be empty, and the script is responsible for generating the complete file contents.

#### 命名：`modify_` 與 `dot_` 怎麼組合

**`modify_` 是「檔案」屬性，不是「目錄」屬性。** 目錄只支援 `exact_` / `private_` / `readonly_`
（外加 `external_` / `remove_` / `literal_`）——
[target-types → Directories](https://www.chezmoi.io/reference/target-types/#directories) 只列了這幾個。

因此：

| 想要的 target | ✅ 正確來源路徑 | ❌ 錯誤 |
|---|---|---|
| `~/.claude/settings.json` | `dot_claude/modify_settings.json` | `modify_dot_claude/settings.json` |
| `~/.codex/config.toml` | `dot_codex/modify_config.toml` | `modify_dot_codex/config.toml` |

**實測驗證：** 用錯誤形式 `modify_dot_claude/settings.json` 時，`chezmoi diff` 顯示它要建立一個
**字面名為 `modify_dot_claude` 的目錄**、裡面放一個未經處理的 `settings.json`（模板原始碼直接被當內容）。
改成 `dot_claude/modify_settings.json` 後，`chezmoi managed` 才正確列出 `.claude/settings.json`。

「The order of prefixes is important」——
[source-state-attributes](https://www.chezmoi.io/reference/source-state-attributes/)。這裡沒有順序問題，
因為 `dot_` 在目錄那一層、`modify_` 在檔案那一層，兩者不在同一個檔名上。

#### target 不存在時

「the script's standard input will be empty, and the script is responsible for generating the
complete file contents」。對 modify-template 而言，`.chezmoi.stdin` 會是空字串 `""`——
所以模板一定要先判空，否則 `fromJson ""` / `fromToml ""` 會炸。§4 的範例都有做這件事。

**實測：** 刪掉 `~/.codex/config.toml` 後 `chezmoi apply`，chezmoi 依模板輸出建立了全新的檔案。

#### 可以是 `.tmpl` 嗎？

**不行（在 modify-template 模式下）。** 官方警告逐字：

> Modify templates **must not** have a `.tmpl` extension.

（[manage-different-types-of-file](https://www.chezmoi.io/user-guide/manage-different-types-of-file/#manage-part-but-not-all-of-a-file)）

原始碼解釋了原因：`newModifyTargetStateEntryFunc` 先呼叫
`s.readContentsAndExecuteTemplate(...)`（這一步才處理 `.tmpl`），**之後**才檢查
`chezmoi:modify-template` 並注入 `.chezmoi.stdin`。所以 `.tmpl` 的那一輪算繪根本還沒有 `stdin`。

**實測**（把 `modify_config.toml` 改名成 `modify_config.toml.tmpl`）：

```
chezmoi: .codex/config.toml: template: dot_codex/modify_config.toml.tmpl:3:15:
executing "dot_codex/modify_config.toml.tmpl" at <.chezmoi.stdin>: map has no entry for key "stdin"
```

**但 shell-mode 的 `modify_` 可以是 `.tmpl`：** `modify_foo.tmpl` 會先被算繪成腳本、再被執行，
腳本本身仍然從 stdin 收 target 內容。這是「想在腳本裡嵌入 `.chezmoi.os` 之類的值」時的做法。
（依 §1.1 的 `.tmpl` 規則 + 上述原始碼順序推得；官方文件沒有明寫這個組合，此處為**原始碼推論**。）

#### 執行契約：exit code / stderr / 執行位元

- **不需要在來源檔上設執行位元。** chezmoi 把腳本內容寫進一個暫存檔並自己 `chmod 0700`：

  ```go
  // internal/chezmoi/realsystem.go, prepareScriptCmd
  // Make the script private before writing it in case it contains any secrets.
  if runtime.GOOS != "windows" {
      if err := f.Chmod(0o700); err != nil { ... }
  }
  ```

  **實測：** 來源檔 `chmod 644` 的 shell-mode `modify_` 腳本照樣正常執行。
  （注意：`executable_` 屬性是給 **target** 加執行位元的，跟這裡無關。）
- **stdin / stdout / stderr：**

  ```go
  preparedScript.cmd.Stdin = bytes.NewReader(currentContents)
  preparedScript.cmd.Stderr = os.Stderr
  return chezmoilog.LogCmdOutput(s.logger, preparedScript.cmd)
  ```

  stdout 被擷取成新內容；**stderr 直接透傳到終端**（所以腳本可以往 stderr 印診斷訊息而不污染輸出）。
- **exit code：** 非零 exit 會讓 `LogCmdOutput` 回傳 error，該 target 的算繪失敗，
  `chezmoi apply` 會報錯中止。官方 reference 沒有專章寫 exit code 契約
  （**此處為原始碼推論**，來源同上 `newModifyTargetStateEntryFunc`）。
- **modifier 內容為空 → 保留原檔：**

  ```go
  // If the modifier is empty then return the current contents unchanged.
  if isEmpty(modifierContents) { return currentContents, nil }
  ```

  注意這是檢查「**來源檔**（算繪後）是否為空」，不是「模板輸出是否為空」。模板輸出為空是另一回事，見 §5.2。

#### 與 `chezmoi diff` / `apply` / `cat` 的互動

- `chezmoi cat <target>` 會把 modify 的結果印出來（會實際讀取目前的 target 內容）。
  （[cat](https://www.chezmoi.io/reference/commands/cat/)）
- `chezmoi diff` 顯示的是「modify 之後的結果 vs 目前 target」，也就是**真正會被改動的部分**。
  （[diff](https://www.chezmoi.io/reference/commands/diff/)）
- **`modify_` 的 target 永遠不會觸發「檔案被別人改過」的確認提示。** `newModifyTargetStateEntryFunc`
  回傳的 `TargetStateFile` 帶 `overwrite: true`，而 `defaultPreApplyFunc` 的第一個豁免就是
  `case targetEntryState.Overwrite(): mode = promptNone`
  （`internal/cmd/config.go`）。這正是我們要的：Claude Code / Codex 天天在寫這兩個檔，
  chezmoi 不該每次都停下來問。
- **實測：** 先 `apply` 一次，再手動把 `settings.json` 改成
  `{"keep":"me","toolAdded":true,"model":"sonnet"}`，再 `apply` → 沒有任何提示，
  結果是 `{"keep":"me","model":"opus","toolAdded":true}`：受管的 key 被拉回、工具寫的 key 原封不動。
  接著 `chezmoi status` 輸出為空（已收斂）。

### 2.2 `.chezmoitemplates/` 與 `template` action

（[.chezmoitemplates/](https://www.chezmoi.io/reference/special-directories/chezmoitemplates/)）

> If any directory called `.chezmoitemplates/` exists in the source state, then all files in this
> directory are available as templates with a name equal to the relative path to the
> `.chezmoitemplates/` directory.
>
> The `template` action or `includeTemplate` function can be used to include these templates in
> another template. The context value (`.`) must be set explicitly if needed, otherwise the template
> will be executed with `nil` context data.

```
# .chezmoitemplates/foo
{{ if true }}bar{{ end }}

# dot_file.tmpl
{{ template "foo" . }}
```

`includeTemplate` *filename* [*data*]：「Relative paths are first searched for in `.chezmoitemplates`
and, if not found, are interpreted relative to the source directory.」
（[includeTemplate](https://www.chezmoi.io/reference/templates/functions/includeTemplate/)）

**與本題的關係：** 這是「共用片段」機制，**不是**部分管理機制。它可以用來把兩個 modify 模板共用的
merge 邏輯抽出來，但本題規模還不需要。**注意 `.` 一定要傳**，否則子模板拿不到 `.chezmoi.stdin`。

### 2.3 `create_`（只在不存在時建立）

（[target-types → Create file](https://www.chezmoi.io/reference/target-types/#create-file)）

> Files with the `create_` prefix will be created in the target state with the contents of the file
> in the source state if they do not already exist. If the file in the destination state already
> exists then its contents will be left unchanged.

`create_` vs `modify_`：

| | `create_` | `modify_` |
|---|---|---|
| 檔案不存在 | 用來源內容建立 | 執行腳本／模板（stdin 空），用輸出建立 |
| 檔案已存在 | **完全不碰內容** | 每次 apply 都重跑，內容被腳本／模板輸出取代 |
| 能否強制某些 key 的值 | ❌ 只有第一次 | ✅ 每次 |
| 權限屬性仍會套用 | ✅ | ✅ |

**不適合本題。** 使用者的兩個檔案「已經存在於 target 機器上」，`create_` 會直接放手，
受管的 key 永遠不會被寫入或維持。`create_` 真正的用途是官方講的另一件事：
「chezmoi's `create_` attributes allows you to tell chezmoi to create a file if it does not already
exist. chezmoi, however, will apply any permission changes from the `executable_`, `private_`, and
`readonly_` attributes. This can be used to control a file's permissions without altering its contents.」
（[manage a file's permissions, but not its contents](https://www.chezmoi.io/user-guide/manage-different-types-of-file/#manage-a-files-permissions-but-not-its-contents)）

### 2.4 `.chezmoiexternal.toml`

本 repo 已經在用它抓 Oh My Zsh 與外掛。它管的是「從網路抓下來的檔案／壓縮檔／git repo」，
每個 external 都是**整體**取代 target，沒有 merge 概念。

**與本題無關**，唯一沾邊的觀察：本 repo 在 `.oh-my-zsh` 上用 `exact = true`，
並靠 `.chezmoiignore` 的 `.oh-my-zsh/cache/**` / `.oh-my-zsh/log/**` 把執行期狀態排除在外——
這是「用 ignore 保護工具寫入的狀態」的另一種模式。但它只能保護**整個檔案／目錄**，
沒辦法保護「同一個檔案裡的某些 key」，所以在 `settings.json` / `config.toml` 上用不上。

### 2.5 chezmoi 有沒有一級的 JSON/TOML merge？

**沒有「merge 檔案」這種一級功能。** chezmoi 沒有任何「把來源檔與 target 檔做結構化合併」的
內建 target 型別。有的是**模板函式**層級的工具：`fromJson` / `fromJsonc` / `fromToml` / `fromYaml` /
`fromIni` 解析成 dict，`setValueAtPath` / `deleteValueAtPath` / `pruneEmptyDicts` 操作 dict，
`toPrettyJson` / `toToml` / `toYaml` / `toIni` 序列化回去；再加上 sprig 的 `merge` / `mustMerge` /
`deepCopy` / `dig`。**merge 一定得在 `modify_` 裡自己組。**

官方在 modify-template 段落給的正是這個組法：

```text
{{- /* chezmoi:modify-template */ -}}
{{ fromJson .chezmoi.stdin | setValueAtPath "key.nestedKey" "value" | toPrettyJson }}
```

（[manage-different-types-of-file](https://www.chezmoi.io/user-guide/manage-different-types-of-file/#manage-part-but-not-all-of-a-file)）

文件另外提到第三方工具 `chezmoi_modify_manager`：「For managing ini files with a mix of settings and
state (such as recently used files or window positions), there is a third party tool called
`chezmoi_modify_manager` that builds upon `modify_` scripts.」
（同上；連結指向
[related-software](https://www.chezmoi.io/links/related-software/#vorpalblade/chezmoi_modify_manager)）。
它的定位是 **INI**，不是 JSON/TOML，本題不採用。

---

## 3. 在 `modify_` 裡真的做 merge

### 3.1 chezmoi 原生模板函式（無外部二進位）

以下函式名稱與簽章都對照
[templates/functions](https://www.chezmoi.io/reference/templates/functions/) 逐一確認，
並在本機 v2.72.0 上**實測**跑過。

| 函式 | 簽章／說明 | 來源 |
|---|---|---|
| `fromJson` *jsontext* | 解析 JSON。「JSON numbers that can be represented exactly as 64-bit signed integers are returned as such. Otherwise, if the number is in the range of 64-bit IEEE floating point values, it is returned as such. Otherwise, the number is returned as a string.」 | [fromJson](https://www.chezmoi.io/reference/templates/functions/fromJson/) |
| `fromJsonc` *jsonctext* | 解析帶註解的 JSON | [fromJsonc](https://www.chezmoi.io/reference/templates/functions/fromJsonc/) |
| `fromToml` *tomltext* | 解析 TOML | [fromToml](https://www.chezmoi.io/reference/templates/functions/fromToml/) |
| `toPrettyJson` [*indent*] *value* | 序列化 JSON，*indent* 預設兩個空白 | [toPrettyJson](https://www.chezmoi.io/reference/templates/functions/toPrettyJson/) |
| `toToml` *value* | 序列化 TOML | [toToml](https://www.chezmoi.io/reference/templates/functions/toToml/) |
| `setValueAtPath` *path* *value* *dict* | 「modifies *dict* to set the value at *path* to *value* and returns *dict*」；*path* 可以是 `.` 分隔字串或 key 的 list；「will create new key/value pairs in *dict* if needed」 | [setValueAtPath](https://www.chezmoi.io/reference/templates/functions/setValueAtPath/) |
| `deleteValueAtPath` *path* *dict* | 刪除；path 不存在則原樣返回 | [deleteValueAtPath](https://www.chezmoi.io/reference/templates/functions/deleteValueAtPath/) |
| `pruneEmptyDicts` *dict* | 由下而上移除空的巢狀 dict | [pruneEmptyDicts](https://www.chezmoi.io/reference/templates/functions/pruneEmptyDicts/) |
| `jq` *query* *input* | 內建 jq（`github.com/itchyny/gojq`），回傳結果 list。**不需要安裝 jq 二進位** | [jq](https://www.chezmoi.io/reference/templates/functions/jq/) |
| `includeTemplate` *filename* [*data*] | 見 §2.2 | [includeTemplate](https://www.chezmoi.io/reference/templates/functions/includeTemplate/) |
| `abortEmpty` | 立即停止模板執行並回傳空字串（⚠️ 見 §5.2） | [abortEmpty](https://www.chezmoi.io/reference/templates/functions/abortEmpty/) |

**`toJson` 的來歷：** `toJson` **不在** chezmoi 自己的函式清單裡（`assets/chezmoi.io/docs/reference/
templates/functions/` 底下沒有 `toJson.md`），它來自 sprig。chezmoi 的做法是：先載入
`sprigin.TxtFuncMap()`，然後**刪掉並覆寫**其中的 `fromJson`、`fromYaml`、`quote`、`splitList`、
`squote`、`toPrettyJson`、`toString`、`toStrings`、`toYaml`（`internal/cmd/config.go`，
註解逐字：「Override sprig template functions. Delete them from the template function map first to
avoid a duplicate function panic.」）。`toJson` 不在刪除名單裡，所以是 sprig 版本。
`quote` 則是 chezmoi 自己的版本（sprig 的被刪掉）。

**sprig / sprout 的 merge 家族——實測全部可用：**

```
$ chezmoi execute-template '{{ mustMerge (dict "a" 1) (dict "b" 2) | toJson }}'
{"a":1,"b":2}
$ chezmoi execute-template '{{ merge (dict "a" 1) (dict "b" 2) | toJson }}'
{"a":1,"b":2}
$ chezmoi execute-template '{{ dig "a" "b" "def" (dict "a" (dict "b" "yes")) }}'
yes
$ chezmoi execute-template '{{ deepCopy (dict "a" 1) | toJson }}'
{"a":1}
```

（文件只說「All standard `text/template` and text template functions from `sprig` are included」，
**沒有逐一列出** sprig 函式，所以上面是實測結論。實作上 chezmoi 現在用的是 sprig 的 fork
`github.com/go-sprout/sprout v1.1.1` 的 `sprigin` 相容層——見 `go.mod` 與 `internal/cmd/config.go:36`。）

**`merge` 的方向要小心：** sprig 的 `merge dst src...` 是「以 dst 為準，src 只補 dst 沒有的 key」。
要「強制覆蓋」時方向必須反過來——`merge (dict "model" "opus") $current` 才是「managed 蓋掉 current」。
本文的範例一律用 `setValueAtPath`，語意最直白，不會踩到方向問題。

**結論：純模板 `modify_` 可以完全不靠外部二進位做完 merge。** 已實測，見 §4。

### 3.2 外部二進位方案的成本

`jq`（JSON）、`dasel` / `yq` / `toml-cli` / `taplo`（TOML）都可以在 shell-mode `modify_` 裡用。成本：

- **本機實測：`jq`、`dasel`、`yq`、`toml-cli` 目前全部沒有安裝。** 要用就得加進
  `.chezmoiscripts/run_onchange_before_10-install-packages.sh.tmpl`（apt）或
  `run_onchange_before_30-install-mise.sh.tmpl`（brew），而這兩支腳本是 `before_`，
  排在檔案套用之前——順序上可行，但等於為了兩個 key 多背一個系統相依。
- chezmoi 內建的 `jq` 模板函式（gojq）已經涵蓋 JSON 的絕大多數需求，**JSON 這半邊完全沒有理由裝 jq**。
- TOML 這半邊，我**無法從一級來源確認**任何一個外部工具在寫入時會保留註解與原始排序
  （dasel / yq 的 TOML 後端行為未在其官方文件中確認，此處不做推測）。
  因此 §4.2 改用 awk：POSIX 工具、本機必定存在、行為完全可控。

### 3.3 兩個檔案的建議

| | `~/.claude/settings.json` | `~/.codex/config.toml` |
|---|---|---|
| 建議 | 純模板 modify-template | shell-mode `modify_` + awk |
| 理由 | JSON 無註解；`fromJson`→`toPrettyJson` 只改排版與 key 順序（字典序），語意零損失 | `fromToml`→`toToml` 會吃掉註解、重排、拆 table，且**會位移不帶 offset 的 date/time** |
| 相依 | 無 | 無（awk 是 POSIX） |
| 備選 | — | 若確認該檔沒有註解也沒有 local date，可改用純模板版（§4.3 附上） |

**TOML 這半邊的誠實說明：** chezmoi 沒有任何保留註解的 TOML 編輯能力。
`fromToml | toToml` 的損失是實測確認的：

```
輸入:                                往返後:
# my codex config                    (註解消失)
model = "gpt-5"                      approval_policy = "on-request"
approval_policy = "on-request"       model = "gpt-5"
                                     model_reasoning_effort = "high"
[tui]
notifications = true                 [mcp_servers]
                                       [mcp_servers.foo]
[mcp_servers.foo]                        command = "npx"
command = "npx"
                                     [tui]
                                       notifications = true
```

以及最嚴重的：

```
$ printf 'ld = 2024-01-01\n' | TZ=Asia/Taipei chezmoi execute-template --with-stdin --file rt.tmpl
ld = 2023-12-31
$ printf 'ld = 2024-01-01\n' | TZ=UTC          chezmoi execute-template --with-stdin --file rt.tmpl
ld = 2024-01-01
```

（`rt.tmpl` = `{{- /* chezmoi:modify-template */ -}}{{ fromToml .chezmoi.stdin | toToml }}`。
`lt = 07:32:00` → `23:32:00`、`ldt = 2024-01-01T07:32:00` → `2023-12-31T23:32:00` 同樣被位移。
帶 offset 的 `d = 2024-01-01T00:00:00Z` 不受影響。）

JSON 那半邊也有一個小損失（實測）：超出 int64 的大整數會退化成 float64，
`12345678901234567890` → `12345678901234567000`；`1e3` 會被正規化成 `1000`。
`~/.claude/settings.json` 裡的時間戳（毫秒級）遠在 int64 範圍內，不受影響。

---

## 4. 可直接使用的範例（針對本 repo）

### 4.1 `~/.claude/settings.json` — 純模板

**來源檔：`dot_claude/modify_settings.json`**（注意：**沒有** `.tmpl` 後綴；`modify_` 在檔案上、`dot_` 在目錄上）

```text
{{- /* chezmoi:modify-template */ -}}
{{- /*
    只管理下面明確列出的 key，其餘一律保留 —— 包含 Claude Code 自己寫進來的
    feedbackSurveyState、tipsHistory 等狀態，以及日後新增的任何 key。
    這個檔案不可以有 .tmpl 後綴，見 docs/research/chezmoi-templates-partial-config.md。
*/ -}}
{{- $cur := dict -}}
{{- if .chezmoi.stdin -}}
{{-   $cur = fromJson .chezmoi.stdin -}}
{{- end -}}

{{- /* --- 受管理的 key（純量） --- */ -}}
{{- $cur = $cur | setValueAtPath "model" "opusplan" -}}
{{- $cur = $cur | setValueAtPath "includeCoAuthoredBy" false -}}
{{- $cur = $cur | setValueAtPath "env.EDITOR" "nvim" -}}

{{- /* --- 受管理的 key（陣列：聯集，不覆蓋既有項目） --- */ -}}
{{- $wantAllow := list "Bash(git status:*)" "Bash(git diff:*)" "Bash(chezmoi diff:*)" -}}
{{- $curAllow := dig "permissions" "allow" (list) $cur -}}
{{- $cur = $cur | setValueAtPath "permissions.allow" (concat $curAllow $wantAllow | uniq | sortAlpha) -}}

{{- /* --- 依機器分岔（沿用 repo 既有的 .isWSL 慣例） --- */ -}}
{{- if .isWSL -}}
{{-   $cur = $cur | setValueAtPath "env.BROWSER" "wslview" -}}
{{- end -}}

{{ $cur | toPrettyJson }}
```

要點：

- `{{- if .chezmoi.stdin -}}` 這一層判空是必要的：檔案不存在時 stdin 是空字串，`fromJson ""` 會炸。
- `dig` + `concat` + `uniq` 是「陣列聯集」的作法——直接 `setValueAtPath "permissions.allow" $wantAllow`
  會把使用者手動加的授權整個蓋掉。
- `sortAlpha` 讓輸出穩定，避免 `chezmoi diff` 每次都有假動靜。
- `.isWSL` 是本 repo `.chezmoi.toml.tmpl` 已經產生的變數。

**實測結果**（target 原本是
`{"feedbackSurveyState":{"lastShownTime":1756000000},"model":"opusplan","permissions":{"allow":["Bash(ls:*)"]}}`，
以簡化版模板只設 `model` 與 `env.FOO`）：

```json
{
  "env": { "FOO": "bar" },
  "feedbackSurveyState": { "lastShownTime": 1756000000 },
  "model": "opus",
  "permissions": { "allow": [ "Bash(ls:*)" ] }
}
```

`feedbackSurveyState` 與 `permissions.allow` 原封不動；再手動塞一個 `"toolAdded": true` 後
`chezmoi apply`，該 key 也保留下來，`chezmoi status` 為空。

### 4.2 `~/.codex/config.toml` — shell-mode `modify_` + awk（建議）

**來源檔：`dot_codex/modify_config.toml`**（同樣**沒有** `.tmpl`；**不需要**執行位元）

```sh
#!/bin/sh
# chezmoi modify_ script for ~/.codex/config.toml
#
# 只改寫下面 MANAGED 列出的 top-level key，其餘位元組原封不動 ——
# 註解、key 順序、空行、[table] 區塊、Codex 自己寫進來的東西全部保留。
#
# 之所以不用 `fromToml | setValueAtPath | toToml` 純模板寫法：那會吃掉全部註解、
# 把 key 重排成字典序、把 [mcp_servers.foo] 拆成兩層，而且會把不帶時區 offset 的
# TOML date/time 依本機時區位移（實測 2024-01-01 -> 2023-12-31）。
# 詳見 docs/research/chezmoi-templates-partial-config.md
set -eu

MANAGED='model = "gpt-5-codex"
model_reasoning_effort = "high"
approval_policy = "on-request"'

awk -v managed="$MANAGED" '
function flush(   i, k, appended) {
    for (i = 1; i <= n; i++) {
        k = order[i]
        if (!(k in done)) { buf[++nbuf] = want[k]; done[k] = 1; appended = 1 }
    }
    for (i = 1; i <= nbuf; i++) print buf[i]
    nbuf = 0
    if (appended && !ateof) print ""
}
BEGIN {
    n = split(managed, lines, "\n")
    for (i = 1; i <= n; i++) {
        line = lines[i]; k = line; sub(/[ \t]*=.*$/, "", k)
        want[k] = line; order[i] = k
    }
    inroot = 1        # 還在第一個 [table] 之前，也就是 root table
}
{
    if (inroot && $0 ~ /^[ \t]*\[/) { flush(); inroot = 0 }
    if (inroot) {
        k = $0; sub(/^[ \t]*/, "", k); sub(/[ \t]*=.*$/, "", k)
        if (k in want) {
            if (!(k in done)) { print want[k]; done[k] = 1 }
            next      # 受管的 key：換成我們的版本，重複出現的丟掉
        }
    }
    print
}
END { ateof = 1; if (inroot) flush() }
'
```

**實測**（chezmoi v2.72.0，整合測試）：

輸入（target 原檔）：
```toml
# my codex config -- keep this comment
model = "gpt-5"
approval_policy   =   "never"

[tui]
notifications = true

[mcp_servers.foo]
command = "npx"
```

`chezmoi cat ~/.codex/config.toml` 輸出：
```toml
# my codex config -- keep this comment
model = "gpt-5-codex"
approval_policy = "on-request"

model_reasoning_effort = "high"

[tui]
notifications = true

[mcp_servers.foo]
command = "npx"
```

註解保留、`[tui]` 與 `[mcp_servers.foo]` 原樣、缺的 key 補在 root table 末尾。
`chezmoi apply` 後 `chezmoi status` 為空；把輸出再餵一次得到相同結果（**冪等**，實測）。
target 不存在（stdin 空）時，輸出就是三行 MANAGED，也一樣冪等。

**限制（要誠實記著）：**
- 只處理 **root table 的 top-level key**（第一個 `[...]` 之前那一段）。要管 `[tui]` 裡的 key
  就得擴充腳本去追蹤目前所在的 table。
- 假設受管的 key 各自寫在一行、`key = value` 形式。多行陣列值（`arr = [` 換行）不會被正確替換。
  `~/.codex/config.toml` 的這幾個 key 都是單行字串，沒問題。
- 不解析 TOML，所以不會驗證語法；反過來說也不會改壞它沒碰到的東西。

**如果要在腳本裡用 chezmoi 的資料**（例如依 `.isWSL` 給不同的 `model`），把檔名改成
`dot_codex/modify_config.toml.tmpl` 並用 `{{ }}`——shell-mode 的 `modify_` **可以**有 `.tmpl`
（限制只對 modify-template 模式），但 awk 裡的 `{` `}` 不會跟 Go 模板衝突（衝突的是 `{{`）。

### 4.3 `~/.codex/config.toml` — 純模板版（備選，接受重排與註解流失）

若確認該檔沒有需要保留的註解、也沒有不帶 offset 的 date/time：

**來源檔：`dot_codex/modify_config.toml`**

```text
{{- /* chezmoi:modify-template */ -}}
{{- $cur := dict -}}
{{- if .chezmoi.stdin -}}
{{-   $cur = fromToml .chezmoi.stdin -}}
{{- end -}}
{{- $cur = $cur | setValueAtPath "model" "gpt-5-codex" -}}
{{- $cur = $cur | setValueAtPath "model_reasoning_effort" "high" -}}
{{- $cur = $cur | setValueAtPath "approval_policy" "on-request" -}}
{{ $cur | toToml }}
```

**實測可用**，但會把整個檔案重排、註解消失（見 §3.3 的對照）。

### 4.4 測試指令

```sh
# 1) 純模板 modify-template：拿真實的 target 當 stdin 餵進去（不會寫任何東西）
chezmoi execute-template --with-stdin --file \
  "$(chezmoi source-path)/dot_claude/modify_settings.json" < ~/.claude/settings.json

# 2) shell-mode modify_ 腳本：直接跑，不經過 chezmoi
sh "$(chezmoi source-path)/dot_codex/modify_config.toml" < ~/.codex/config.toml

# 3) 看 chezmoi 算出來的最終 target 內容（會讀目前的 target，但不寫入）
chezmoi cat ~/.claude/settings.json
chezmoi cat ~/.codex/config.toml

# 4) 看會改什麼
chezmoi diff ~/.claude/settings.json ~/.codex/config.toml

# 5) 冪等性檢查：apply 之後 status 應該是空的
chezmoi apply ~/.claude/settings.json ~/.codex/config.toml
chezmoi status

# 6) 演練：確認 target 不存在時的行為
mv ~/.codex/config.toml ~/.codex/config.toml.bak
chezmoi cat ~/.codex/config.toml
mv ~/.codex/config.toml.bak ~/.codex/config.toml
```

**`--with-stdin` 的一個實測陷阱：** `execute-template --file` **不會**幫你剝掉
`chezmoi:modify-template` 標記行（那個剝除只發生在 `modify_` 的算繪路徑上）。
所以標記要寫成 **Go 模板註解**的形式：

```text
{{- /* chezmoi:modify-template */ -}}
```

這樣 `chezmoi apply` 會整行剝掉、`execute-template` 也因為它是模板註解而輸出空字串，兩邊一致。
如果寫成裸的 `# chezmoi:modify-template`，`chezmoi cat` 正確（被剝掉），
但 `execute-template --file` 會把 `# chezmoi:modify-template` 原樣印在輸出最前面（實測），
測試結果會誤導人。

---

## 5. Gotchas

### 5.1 `modify_` 每次 apply 都會跑

`modify_` 是用來計算 target state 的，所以 `chezmoi apply` / `diff` / `status` / `cat` 每次都會執行它
（`newModifyTargetStateEntryFunc` 裡的 `contentsFunc` 每次呼叫都重新讀 target 並重跑腳本／模板）。

- 它**不是** `run_once_` / `run_onchange_`——那些屬性是給 `run_` 腳本的，`modify_` 沒有這種語意。
- 所以腳本**必須冪等**：跑兩次結果要一樣。§4.1 用 `uniq | sortAlpha`、§4.2 用 `done[]` 去重，
  都是為了這件事。
- 也**必須快**：每次 `chezmoi diff` 都會付這個成本。純模板方案基本上零成本；
  呼叫外部 `curl` / 密碼管理器之類的東西就會很痛。

### 5.2 空輸出會**刪掉** target 檔

這是最容易踩、後果最嚴重的一個。兩件事要分清楚：

1. **來源檔（算繪後）為空** → chezmoi 保留 target 原內容：
   `if isEmpty(modifierContents) { return currentContents, nil }`（`sourcestate.go`）。這是安全的。
2. **模板／腳本的輸出為空** → 走的是一般檔案規則：
   「If the target contents are empty then the file will be removed, unless it has an `empty_` prefix.」
   （[target-types → Files](https://www.chezmoi.io/reference/target-types/#files)）

**實測：** 把 `dot_claude/modify_settings.json` 內容改成只有一行
`{{- /* chezmoi:modify-template */ -}}`（標記行被剝掉後模板為空 → 輸出空字串），
`chezmoi cat` 印出空的，`chezmoi apply` 則試圖**移除** `~/.claude/settings.json`
（在有 TTY 的環境會跳 `.claude/settings.json has changed since chezmoi last wrote it` 的
overwrite/skip 提示——因為移除操作不帶 `overwrite: true`，不像正常的 modify 那樣被豁免）。

**推論：** 這也意味著在 modify-template 裡呼叫 `abortEmpty`（「causes template execution to
immediately stop and return the empty string」，
[abortEmpty](https://www.chezmoi.io/reference/templates/functions/abortEmpty/)）會導致**刪檔**，
而不是「跳過這個檔案」。想要「條件成立才管這個檔」，正確做法是在 `.chezmoiignore` 裡用模板排除它，
或在模板裡原樣輸出 `.chezmoi.stdin`。（`abortEmpty` 與 `modify_` 的互動未在官方文件明寫，
此處為**由兩份文件推得的結論**，未實測 `abortEmpty` 本身。）

### 5.3 `.tmpl` 與 modify-template 不能並存

見 §2.1。錯誤訊息（實測）：

```
chezmoi: .codex/config.toml: template: dot_codex/modify_config.toml.tmpl:3:15:
executing "dot_codex/modify_config.toml.tmpl" at <.chezmoi.stdin>: map has no entry for key "stdin"
```

同樣的錯誤也會出現在「在一般 `.tmpl` 檔裡誤用 `.chezmoi.stdin`」的時候。

### 5.4 target 檔語法壞掉時，整個 apply 會失敗

純模板方案會在 `fromJson` / `fromToml` 解析失敗時中止（實測）：

```
chezmoi: .claude/settings.json: template: dot_claude/modify_settings.json:2:35:
executing "dot_claude/modify_settings.json" at <fromJson .chezmoi.stdin>:
error calling fromJson: invalid character 'o' in literal null (expecting 'u')
```

這其實是好事——它不會默默用一個全新檔案蓋掉一個壞掉但可能還有救的檔案。但要知道
**`chezmoi apply` 會因此整個失敗**，不只是這一個檔案。想更寬容的話，可以在模板裡先做
「看起來不像 JSON 就當空的」的防衛，代價是真的會覆蓋掉壞檔。

### 5.5 `chezmoi add` **不能**回收 `modify_` 管理的檔案——而且會把腳本毀掉

**實測（v2.72.0，這是本次調查最危險的發現）：**

```
來源狀態: dot_claude/modify_settings.json   （modify 模板）
$ chezmoi add ~/.claude/settings.json
（無任何輸出、無警告、exit 0）
來源狀態: dot_claude/settings.json          （target 的完整內容，modify 模板消失了）
```

`chezmoi add` 把 `modify_settings.json` **換成**了一個普通的 `settings.json`，內容是 target 的完整
副本——部分管理的設定就這樣被靜默地換成完全管理，而且 modify 腳本沒了。

**原因（推論）：** `add` 的語意是「把 target 現況寫進來源狀態」，它沒有辦法把「完整內容」
反推成「一段 modify 邏輯」。官方文件沒有針對這個情境的警告
（我在 [add](https://www.chezmoi.io/reference/commands/add/) 與 target-types 都沒找到），
所以這是**實測結論 + 推論**，不是文件明載的行為。

**因應：**
- 為這兩個檔案建立 `modify_` 之後，**永遠不要**對它們跑 `chezmoi add`。
- 本 repo 的 `README.md` 「日常使用」段落目前寫著 `chezmoi add ~/.p10k.zsh`——那是安全的
  （`dot_p10k.zsh` 是完全管理）。若之後要在 README 補一行提醒，就是這一條。
- 要改受管的 key，直接編輯來源的 `modify_` 檔（`chezmoi edit ~/.claude/settings.json` 會開啟
  來源檔，也就是 modify 腳本本身）。

### 5.6 `chezmoi apply` 不會為 `modify_` target 跳「檔案被改過」的提示

見 §2.1。這是刻意設計（`overwrite: true` → `defaultPreApplyFunc` 的 `promptNone`），
對本題是好事。但反過來說：**你不會被提醒工具改了什麼**。想看差異就自己跑 `chezmoi diff`。
`--interactive` 旗標會強制每個檔案都問（`case c.Interactive: mode = promptYesNoAll`
排在 `Overwrite()` 判斷之前），`--force` 則相反。

### 5.7 `.chezmoiignore` 的互動

- 若 `.chezmoiignore` 裡（或子目錄的 `.chezmoiignore` 裡）匹配到 `.claude/settings.json`，
  這個 target 就完全不受管，`modify_` 不會跑。pattern 是「match against the target path,
  not the source path」（[chezmoiignore](https://www.chezmoi.io/reference/special-files/chezmoiignore/)），
  所以要寫 `.claude/settings.json`，不是 `dot_claude/modify_settings.json`。
- 「All excludes take priority over all includes」——`!` 開頭的排除永遠贏。
- 若要「某些機器不管這兩個檔」，`.chezmoiignore` 是正確的工具（不是 §5.2 的 `abortEmpty`）：

  ```
  {{- if ne .chezmoi.os "linux" }}
  .codex/config.toml
  {{- end }}
  ```
- 本 repo 的 `docs/` 那一行已經涵蓋 `docs/research/`（實測確認，見檔頭）。

### 5.8 秘密不要放進去

- `modify_` 的內容會**原封不動存進 git**。API key、token 一律不要直接寫在模板裡。
- chezmoi 提供的正解：
  - `encrypted_` 屬性（age / gpg），
    [source-state-attributes](https://www.chezmoi.io/reference/source-state-attributes/)：
    「Encrypt the file in the source state」；`.age` / `.asc` 後綴會被自動剝掉。
  - 密碼管理器模板函式（1Password / Bitwarden / pass / keyring / Vault / …），
    [secret-functions](https://www.chezmoi.io/reference/templates/secret-functions/)。
    但記住 §5.1：`modify_` 每次 apply 都跑，把密碼管理器呼叫塞進去等於每次 `chezmoi diff`
    都要解鎖一次。
  - `decrypt` / `encrypt` 模板函式。
- chezmoi 自己也有這個意識：寫暫存腳本時先 `f.Chmod(0o700)`，註解逐字
  「Make the script private before writing it in case it contains any secrets.」
  （`internal/chezmoi/realsystem.go`）。
- 這兩個檔本身可能含敏感內容，可以考慮加 `private_`（清除 group/world 權限）：
  `dot_claude/private_modify_settings.json`。**⚠️ 前綴順序未經實測驗證**——
  文件只說「The order of prefixes is important」但沒給完整順序表，
  上線前請先用 `chezmoi managed` / `chezmoi diff` 確認 target 名稱是 `.claude/settings.json` 而不是別的。

### 5.9 其他

- **檔案結尾的換行：** `toPrettyJson` 不會自己加結尾換行，模板最後一行的 `{{ ... }}` 後面
  那個換行才是。實測 diff 顯示會多一個 `+`（空行）——若原檔沒有結尾換行，第一次 apply 會加上去。
  這是一次性的，之後就穩定了。
- **key 順序：** `toPrettyJson` / `toToml` 輸出的 map key 是字典序（Go 的 map 序列化行為）。
  第一次 apply 會把整個檔案重排一次，之後就穩定，diff 也乾淨。
- **`chezmoi cat` 需要 target 存在才有意義**：它會實際讀取目前的 target 內容當 stdin。
- **`.chezmoiscripts/` 的順序**：本 repo 的 `run_onchange_before_*` 腳本排在檔案套用**之前**
  （`before_` = "Run script before updating the destination"，
  [source-state-attributes](https://www.chezmoi.io/reference/source-state-attributes/)），
  所以如果哪天真的要裝 `jq` / `dasel` 給 modify 腳本用，加在那裡順序是對的。
- **ASCII 順序**：「chezmoi deterministically performs actions in ASCII order of their target name」
  （[target-types](https://www.chezmoi.io/reference/target-types/)）——`.claude` 早於 `.codex`，
  兩者互不相干，無所謂。

---

## 附錄：無法從一級來源確認的項目

以下是我**沒有**在 chezmoi 官方文件或原始碼中找到明確依據的，文中已個別標註，這裡集中列出：

1. **`modify_` 腳本的 exit code 契約**——reference 沒有專章。文中的說法（非零 exit → 該 target 算繪失敗
   → apply 報錯）是從 `newModifyTargetStateEntryFunc` 回傳 `chezmoilog.LogCmdOutput(...)` 的 error
   推得，未實測非零 exit。
2. **shell-mode `modify_` 可以有 `.tmpl` 後綴**——由 `.tmpl` 的一般規則與
   `readContentsAndExecuteTemplate` 在 modify-template 檢查之前執行這兩點推得，未實測。
3. **`chezmoi add` 覆蓋 `modify_` 來源檔**——行為是實測確認的，但官方文件沒有任何相關說明或警告，
   所以「為什麼」是推論。也因此這個行為可能在未來版本改變。
4. **`abortEmpty` 在 modify-template 裡會導致刪檔**——由 `abortEmpty` 文件（回傳空字串）
   加上 target-types 的「empty contents → file removed」推得，未直接實測 `abortEmpty`。
5. **`private_` 與 `modify_` 的前綴順序**——「The order of prefixes is important」但文件沒給順序表，
   未實測。
6. **`dasel` / `yq` / `toml-cli` 是否保留 TOML 註解**——未在其官方文件中確認，文中不做斷言。
7. **`.chezmoi.stdin` 未列在 templates/variables reference 頁**——這是文件的缺漏，
   不是變數不存在；實作依據見 `sourcestate.go`。

## 附錄：引用來源

**官方文件（www.chezmoi.io）**

- [reference/target-types/](https://www.chezmoi.io/reference/target-types/) — Files / Create file / Modify file / Remove entry / Directories / Symbolic links / Scripts
- [reference/source-state-attributes/](https://www.chezmoi.io/reference/source-state-attributes/) — 前綴與後綴總表
- [reference/templates/variables/](https://www.chezmoi.io/reference/templates/variables/) — `.chezmoi.*`
- [reference/templates/functions/](https://www.chezmoi.io/reference/templates/functions/) — 函式索引（含 fromJson / fromToml / toToml / toPrettyJson / setValueAtPath / deleteValueAtPath / pruneEmptyDicts / jq / includeTemplate / abortEmpty 各自的頁面）
- [reference/templates/init-functions/](https://www.chezmoi.io/reference/templates/init-functions/) — promptStringOnce / promptBoolOnce / …
- [reference/special-files/chezmoiignore/](https://www.chezmoi.io/reference/special-files/chezmoiignore/)
- [reference/special-files/chezmoi-format-tmpl/](https://www.chezmoi.io/reference/special-files/chezmoi-format-tmpl/)
- [reference/special-directories/chezmoitemplates/](https://www.chezmoi.io/reference/special-directories/chezmoitemplates/)
- [reference/commands/execute-template/](https://www.chezmoi.io/reference/commands/execute-template/)
- [reference/commands/cat/](https://www.chezmoi.io/reference/commands/cat/)、[diff/](https://www.chezmoi.io/reference/commands/diff/)
- [user-guide/manage-different-types-of-file/](https://www.chezmoi.io/user-guide/manage-different-types-of-file/)
- [user-guide/manage-machine-to-machine-differences/](https://www.chezmoi.io/user-guide/manage-machine-to-machine-differences/)
- [user-guide/templating/](https://www.chezmoi.io/user-guide/templating/) — Testing templates
- [links/related-software/](https://www.chezmoi.io/links/related-software/#vorpalblade/chezmoi_modify_manager)

**原始碼（github.com/twpayne/chezmoi）**

- `internal/chezmoi/sourcestate.go` — `modifyTemplateRx`、`newModifyTargetStateEntryFunc`
- `internal/chezmoi/realsystem.go` — `prepareScriptCmd`
- `internal/chezmoi/entrystate.go` — `(*EntryState).Overwrite`
- `internal/cmd/config.go` — sprig 覆寫清單、`defaultPreApplyFunc`、`templateFuncs: sprigin.TxtFuncMap()`
- `internal/cmd/executetemplatecmd.go` — `--with-stdin` 的實作
- `go.mod` — `github.com/go-sprout/sprout v1.1.1`
- `assets/chezmoi.io/docs/` — 上列所有文件頁的原始 Markdown

**Go / sprig**

- [text/template — Actions](https://pkg.go.dev/text/template#hdr-Actions)（`{{ template "name" . }}`）
- [sprig — Dictionaries](http://masterminds.github.io/sprig/dicts.html)（`merge` / `mustMerge` / `dig` / `deepCopy` / `set`）
