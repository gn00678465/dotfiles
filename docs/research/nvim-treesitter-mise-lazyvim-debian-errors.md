# mise + LazyVim starter 在 Debian/Ubuntu 上的 nvim-treesitter 錯誤研究

> **這份筆記沒有實測環境。** 我沒有 Debian/Ubuntu 機器可以真的跑一次 `mise use --global neovim@latest`
> 加 LazyVim starter 去重現錯誤。以下每一條結論都直接來自官方 repo 的 README、`:help` 文件、原始碼
> 或官方 issue/PR 原文（連結見各段落與文末「引用來源」），**沒有一條是我自己跑出來的**。凡是只在
> issue 討論串出現、沒有官方確認的說法，都會標「**未證實**」；查不到的就寫「查不到」。
>
> 比照 `docs/research/chezmoi-templates-partial-config.md` 的慣例撰寫。

---

## 0. 先講結論（Answer first）

| # | 主題 | 結論 |
|---|---|---|
| 1 | `master` vs `main` 分支 | `master` 已凍結（frozen，只為回溯相容保留），`main` 是「不相容的全新重寫」。**LazyVim 現在用 `main`**（2025-09-17 遷移）。 |
| 2 | 各分支最低 Neovim 版本 | `master`：Neovim 0.10 或 0.11（**明確不支援 0.12**）。`main`：Neovim **0.12.0 以上**。LazyVim 自身宣稱最低 0.11.2，但用一段程式碼在偵測到 Neovim < 0.12 時把 `nvim-treesitter` **釘死在舊 commit** 來補洞——這個補洞是 2026-04-02 才加的，起因是一個真實的破版事故（issue #7092）。 |
| 3 | ABI 版本綁定 | 真實存在，且是 Neovim 自己的機制：`vim.treesitter.language_version` / `minimum_language_version` 定義目前 Neovim 內建 tree-sitter runtime 能吃的 parser ABI 範圍；parser 編譯時用 `tree-sitter generate --abi <該版本>`。錯配時 Neovim 原始碼會丟出**逐字**訊息 `ABI version mismatch for %s: supported between %d and %d, found %d`。 |
| 4 | "invalid node type" 錯誤 | **真實存在，是最常見的一種**，但根本原因通常不是 ABI，而是「query 檔案（highlights.scm 等）版本」跟「實際裝的 parser」對不上，或 runtimepath 上有重複的 `parser` 目錄。官方 troubleshooting 文件逐字給了這個診斷與修法。 |
| 5 | C compiler 需求 | 兩個分支都需要（`main` README 逐字：「a C compiler in your path」；`master`：「a C compiler in your path and libstdc++」）。這個 repo 的 `build-essential` **已經足夠**（含 gcc/g++/make/libc-dev）。 |
| 6 | `tree-sitter` CLI 需求 | **只有 `main` 分支是硬性需求**（README 明寫 `tree-sitter-cli 0.26.1 以上，不能用 npm 版`，原始碼也證實每次編譯 parser 都呼叫 `tree-sitter build`，不再像 `master` 那樣直接呼叫 cc）。`build-essential` **不含** `tree-sitter` CLI。但 LazyVim 對 `main` 分支有內建的「找不到就用 mason.nvim 自動裝」的補救機制。 |
| 7 | mise 裝的 neovim 是什麼 | **不是原始碼編譯，是 neovim 官方在 GitHub Releases 發布的預編譯 Linux 二進位**（mise 的 neovim registry 設定：`vfox:mise-plugins/vfox-neovim` 為主、`aqua:neovim/neovim` 為輔，兩者原始碼都證實是抓 `nvim-linux-x86_64.tar.gz` 這類 release asset）。 |
| 8 | glibc 相容性 | **這是本次調查裡最確定、後果最直接的一條。** Neovim 官方 release workflow 明寫在 `ubuntu-22.04` runner 上建置 Linux 版（並註明「Build on the oldest supported images, so we have broader compatibility」），Ubuntu 22.04 的 glibc 是 **2.35**。Debian 11 bullseye 的 glibc 是 **2.31**（太舊，跑不動）；Debian 12 bookworm 是 **2.36**、Debian 13 trixie 是 **2.41**（都可以）。 |
| 9 | `neovim@latest` 有沒有危險 | 目前不會抓到 nightly（GitHub 的「Latest release」標記目前指向 `v0.12.5`，`nightly` 這個 tag 本身被 GitHub API 標成 `prerelease: true`，mise 官方文件說 `latest` 優先採信後端的權威 latest 標記）。**但它是浮動 pin**：腳本把字面上的 `"latest"` 寫進 `~/.config/mise/config.toml`，之後每次重跑都會抓當下最新版。真正的風險不是「抓到 nightly」，而是「(a) 抓到的版本比 nvim-treesitter `main` 分支當時要求的更新／更舊，版本要求本身在過去一年內至少變動兩次；(b) 抓到的官方預編譯檔所需的 glibc 底線可能隨 Neovim CI 的 runner 版本上升而上升」。 |
| 10 | 舊 parser 殘留 | 真實存在，官方文件有專門的診斷指令與清除方式：`:echo nvim_get_runtime_file('parser', v:true)` 找重複目錄、`:TSUpdate` / `:TSUpdate all` 更新、`:TSUninstall all` 清空重裝。預設安裝路徑在兩分支都落在 `stdpath('data')`，即 Linux 上的 `~/.local/share/nvim/...`。 |

**對這份 repo 兩個具體問題的結論：**

- **`neovim@latest` 這個 pin 危不危險？** 危險的地方不在「抓到不穩定版本」，而在「浮動 pin + 官方預編譯二進位對 glibc 有底線，且該底線會隨時間上升」。**建議改成明確釘住的版本**，不是為了避開 nightly，而是為了讓「這台機器裝到的 Neovim」可重現、可稽核，並且在 nvim-treesitter `main` 分支下一次調高最低 Neovim 版本需求時，不會在使用者毫無預警的情況下炸掉（issue #7092 就是活生生的例子）。
- **`build-essential` 夠不夠？** 對「C compiler」這個需求是夠的（兩分支都只需要 cc/gcc/g++）。**但對 `nvim-treesitter` `main` 分支缺一個東西：`tree-sitter` CLI 二進位**——這不是 apt 套件，`build-essential` 不含它。目前的救援機制是 LazyVim 在偵測到 `tree-sitter` 不在 PATH 時，會用內建的 `mason.nvim` 自動下載安裝（見 §4），所以「現狀能動」，但這個安全網要求：(a) 使用者用的是有 `mason.nvim` 的 LazyVim 預設設定、(b) 第一次啟動 Neovim 時有網路。用 brew 裝 `tree-sitter` formula 可以把這個依賴前移到安裝腳本層，更穩。

---

## 1. `nvim-treesitter` 的兩個分支：`master`（凍結）vs `main`（重寫）

`main` 分支 README 開頭就是這句警告（逐字）：

> This is a full, incompatible, rewrite: Treat this as a different plugin you need to set up from scratch following the instructions below. If you can't or don't want to update, specify the `master` branch (which is locked but will remain available for backward compatibility with Nvim 0.11).

（[nvim-treesitter/nvim-treesitter, `main` 分支 README](https://github.com/nvim-treesitter/nvim-treesitter/blob/main/README.md)）

`master` 分支 README 開頭也對稱地寫了（逐字）：

> The `master` branch is frozen and provided for backward compatibility only. All future updates happen on the `main` branch, which will become the default branch in the future.

（[nvim-treesitter/nvim-treesitter, `master` 分支 README](https://github.com/nvim-treesitter/nvim-treesitter/blob/master/README.md)）

### 1.1 各分支的 Requirements 區塊（逐字對照）

**`main` 分支：**

> - Neovim 0.12.0 or later (nightly)
> - `tar` and `curl` in your path
> - [`tree-sitter-cli`](https://github.com/tree-sitter/tree-sitter/blob/master/crates/cli/README.md) (0.26.1 or later, installed via your package manager, **not npm**)
> - a C compiler in your path (see <https://docs.rs/cc/latest/cc/#compile-time-requirements>)

同段另有支援政策：

> The current **support policy** for Neovim is
> * the _latest_ stable release,
> * the _latest_ nightly prerelease.
> Other versions may work but are neither tested nor considered for fixes.

（[main 分支 README#Requirements](https://github.com/nvim-treesitter/nvim-treesitter/blob/main/README.md)）

**`master` 分支：**

> - **Neovim 0.10 or 0.11** (Neovim 0.12 is **not supported**);
> - `tar` and `curl` in your path (or alternatively `git`);
> - a C compiler in your path and libstdc++ installed ([Windows users please read this!](https://github.com/nvim-treesitter/nvim-treesitter/wiki/Windows-support)).
> - `tree-sitter-cli` up to **0.25.x**.

（[master 分支 README#Requirements](https://github.com/nvim-treesitter/nvim-treesitter/blob/master/README.md)）

**現在（本文撰寫時）Neovim 的 stable release tag 是 `v0.12.5`**（[neovim/neovim releases/tag/stable](https://github.com/neovim/neovim/releases/tag/stable)），落在 `main` 分支要求的範圍內，也超出 `master` 分支「不支援 0.12」的紅線。

### 1.2 LazyVim 用哪一個分支

LazyVim 目前的 `nvim-treesitter` plugin spec（`lua/lazyvim/plugins/treesitter.lua`）開頭是：

```lua
{
  "nvim-treesitter/nvim-treesitter",
  branch = "main",
  commit = vim.fn.has("nvim-0.12") == 0 and "7caec274fd19c12b55902a5b795100d21531391f" or nil,
  version = false, -- last release is way too old and doesn't work on Windows
  ...
```

（[LazyVim/lua/lazyvim/plugins/treesitter.lua](https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/plugins/treesitter.lua)）

`branch = "main"` 是 2025-09-17 的遷移，commit message 逐字：

> feat(treesitter)!: migrate to `nvim-treesitter` **main** branch

（[commit 5eac460c](https://github.com/LazyVim/LazyVim/commit/5eac460c)）

同一天稍早也有一個被關閉、未真正合併但描述了原因的 PR，body 逐字：

> Treesitter's master branch has been archived, this switches to the main branch.

（[PR #6253](https://github.com/LazyVim/LazyVim/pull/6253)——**這條的措辭「archived」是 PR 作者自己的說法，官方 README 用的字是「frozen/locked」，不是 GitHub 的 archive 狀態，這裡只引用其動機，不採信「archived」這個字面說法**。）

### 1.3 一個已經真實發生的破版事故：main 分支後來連 0.11 都不支援了

`commit = vim.fn.has("nvim-0.12") == 0 and "<舊 commit>" or nil` 這段補丁是 2026-04-02 才加進去的，commit message 逐字：

> fix(treesitter): `nvim-treesitter` on longer support nvim-0.11, so pin when needed. Fixes #7092

（[commit ef272ff7](https://github.com/LazyVim/LazyVim/commit/ef272ff7)）

它修的 issue 標題就是（逐字）：

> bug: nvim-treesitter requires neovim 0.12.0 or later

回報者當時的 Neovim 版本是 `NVIM v0.11.7`，更新 LazyVim 後直接壞掉。
（[issue #7092](https://github.com/LazyVim/LazyVim/issues/7092)）

**這條的意義：** `nvim-treesitter` `main` 分支的最低 Neovim 版本需求，在大約半年內至少調整過兩次方向（一開始 README 寫 0.12.0，實務上曾經一段時間仍相容 0.11，然後徹底收緊到只認 0.12+）。LazyVim 目前用「偵測版本、版本不夠就釘死舊 commit」的方式補洞，但這個補洞本身也是**在事故發生之後才補上**的，不是先天保證。

---

## 2. ABI 版本綁定：真的存在，機制在 Neovim 這一側

Neovim 官方 `:help` 文件（`vim.treesitter` 章節）逐字：

> *vim.treesitter.language_version*
> The latest parser ABI version that is supported by the bundled treesitter library.
>
> *vim.treesitter.minimum_language_version*
> The earliest parser ABI version that is supported by the bundled treesitter library.

（[neovim/runtime/doc/treesitter.txt](https://github.com/neovim/neovim/blob/master/runtime/doc/treesitter.txt)）

`nvim-treesitter` `main` 分支在編譯 parser 前，會用 `tree-sitter generate --abi <目前 Neovim 支援的最新 ABI>` 把 grammar 生成對應 ABI 的 `parser.c`：

```lua
local r = system({
  'tree-sitter',
  'generate',
  '--abi',
  tostring(vim.treesitter.language_version),
  ...
```

（[nvim-treesitter/lua/nvim-treesitter/install.lua](https://github.com/nvim-treesitter/nvim-treesitter/blob/main/lua/nvim-treesitter/install.lua)）

錯配時，Neovim 自己的原始碼（不是 nvim-treesitter）會丟出這個**逐字**訊息（可直接拿去 grep）：

```c
uint32_t lang_version = ts_language_abi_version(lang);
if (lang_version < TREE_SITTER_MIN_COMPATIBLE_LANGUAGE_VERSION
    || lang_version > TREE_SITTER_LANGUAGE_VERSION) {
  return luaL_error(L,
                    "ABI version mismatch for %s: supported between %d and %d, found %d",
                    path,
                    TREE_SITTER_MIN_COMPATIBLE_LANGUAGE_VERSION,
                    TREE_SITTER_LANGUAGE_VERSION, lang_version);
}
```

（[neovim/src/nvim/lua/treesitter.c](https://github.com/neovim/neovim/blob/master/src/nvim/lua/treesitter.c)）

**這個錯誤的實際觸發情境（依機制推論，未實測）：** 升級 Neovim 本體之後，`[minimum_language_version, language_version]` 這個窗口整個往上移動；如果沒有重新 `:TSUpdate`，舊的、用舊窗口編譯出來的 `.so` parser 的 ABI 版本可能低於新窗口的下限，就會觸發這個錯誤。反過來「先裝了很新的 parser，再降級 Neovim」也可能觸發上限那一側。**官方文件沒有把「升級 Neovim 後忘記 TSUpdate」明講成這個錯誤的觸發場景**，這一段是我從三份原始碼／文件（`treesitter.c`、`install.lua`、`:help treesitter`）拼起來的推論。

### 2.1 `:h nvim-treesitter-commands` 也證實了 `TSUpdate` 的作用

`main` 分支 `doc/nvim-treesitter.txt` 逐字：

> `:TSUpdate [{language}]` — Update parsers to the `revision` specified in the manifest if this is newer than the installed version.

（[nvim-treesitter/doc/nvim-treesitter.txt](https://github.com/nvim-treesitter/nvim-treesitter/blob/main/doc/nvim-treesitter.txt)）

---

## 3. "Invalid node type" / "query error: invalid node type"：更常見，但根因通常不是 ABI

`master` 分支 README 的 Troubleshooting 一節，有一條標題就是這個錯誤字串，內容逐字：

> #### I get `query error: invalid node type at position`
>
> This could be due a query file outside this plugin using outdated nodes, or due to an outdated parser.
>
> - Make sure you have the parsers up to date with `:TSUpdate`
> - Make sure you don't have more than one `parser` runtime directory. You can execute this command `:echo nvim_get_runtime_file('parser', v:true)` to find all runtime directories. If you get more than one path, remove the ones that are outside this plugin (`nvim-treesitter` directory), so the correct version of the parser is used.

（[master 分支 README#Troubleshooting](https://github.com/nvim-treesitter/nvim-treesitter/blob/master/README.md)）

同一節也記錄了另一個相關但不同的錯誤：

> #### I get `Error detected while processing .../plugin/nvim-treesitter.vim` every time I open Neovim
>
> This is probably due to a change in a parser's grammar or its queries. Try updating the parser that you suspect has changed (`:TSUpdate {language}`) or all of them (`:TSUpdate`).

（同上）

### 3.1 真實案例（issue 原文標題，供 grep 對照，這些是使用者實際回報的字串，不是官方逐字保證）

- `Query error at 226:4. Invalid node type "except*"` — [issue #8519](https://github.com/nvim-treesitter/nvim-treesitter/issues/8519)
- `Python highligh broken: invalid node type "except*"` — [issue #8440](https://github.com/nvim-treesitter/nvim-treesitter/issues/8440)
- `[BUG] Invalid node type "tab" in vim query` — [issue #8381](https://github.com/nvim-treesitter/nvim-treesitter/issues/8381)
- 對應修法的 PR：`fix(vim): remove invalid "tab" node type from highlights query` — [PR #8619](https://github.com/nvim-treesitter/nvim-treesitter/pull/8619)

這幾個例子的共通模式：**query 檔（highlights.scm 之類）引用了一個 parser grammar 版本裡不存在（或已改名）的 node type**——通常是 nvim-treesitter 專案自己的 query 檔跟它鎖定的 parser 版本一時對不齊（見 §8619 這種上游修復 PR），或是使用者自己在 `runtimepath` 上疊了另一份 query／parser。**這不是「Neovim 版本」或「ABI」問題**，是「plugin 版本內部的 query 與 parser 是否互相匹配」問題，`:TSUpdate` 通常就能解決，因為它會把 query 與 parser 一起更新到 nvim-treesitter 鎖定的配對版本。

### 3.2 為什麼 Neovim 自己也「參一腳」：內建 query 目錄

Neovim 本體（不是 nvim-treesitter plugin）自帶一份 `runtime/queries/`，目前只涵蓋這些語言：`c`、`diff`、`lua`、`markdown`、`markdown_inline`、`query`、`vim`、`vimdoc`
（[neovim/runtime/queries 目錄列表](https://github.com/neovim/neovim/tree/master/runtime/queries)）——這剛好幾乎就是 LazyVim `ensure_installed` 清單裡與「Neovim 自身需要」重疊的那幾種語言（`vimdoc`/`vim` 用來高亮 `:help` 與 vimscript、`lua` 用來高亮 Neovim 自己的設定檔）。**但 Neovim 本體不隨附任何已編譯的 parser `.so`**（`runtime/parser/` 這個路徑在 neovim/neovim repo 裡不存在，實測 GitHub API 回 404）。也就是說：Neovim 提供「自己的一份 query」，但 parser 永遠得靠 nvim-treesitter（或使用者自己）裝；`runtimepath` 上兩邊的 query／parser 版本沒對齊，就是 §3.1 那類錯誤的溫床。

---

## 4. C compiler 與 `tree-sitter` CLI 是兩個不同的需求，`main` 分支才新增了後者

### 4.1 `master` 分支：直接呼叫 cc，`tree-sitter` CLI 只在「從 grammar 重新產生」時才需要

`master` 分支 `install.lua` 逐字：

```lua
M.compilers = { vim.fn.getenv "CC", "cc", "gcc", "clang", "cl", "zig" }
...
if generate_from_grammar and vim.fn.executable "tree-sitter" ~= 1 then
  api.nvim_err_writeln "tree-sitter CLI not found: `tree-sitter` is not executable!"
```

（[master 分支 lua/nvim-treesitter/install.lua](https://github.com/nvim-treesitter/nvim-treesitter/blob/master/lua/nvim-treesitter/install.lua)）

因為絕大多數 parser repo 都已經附上預先產生好的 `src/parser.c`，`generate_from_grammar` 通常是 `false`，所以在 `master` 分支上，日常的 `:TSInstall`/`:TSUpdate` 通常**只需要一個 C compiler**，不需要 `tree-sitter` CLI。

### 4.2 `main` 分支：每次編譯都經過 `tree-sitter build`

`main` 分支的編譯函式：

```lua
local function do_compile(logger, compile_location)
  logger:info(string.format('Compiling parser'))
  local r = system({
    'tree-sitter',
    'build',
    '-o',
    'parser.so',
  }, { cwd = compile_location })
  ...
```

（[main 分支 lua/nvim-treesitter/install.lua](https://github.com/nvim-treesitter/nvim-treesitter/blob/main/lua/nvim-treesitter/install.lua)）

也就是說 `main` 分支底下，**「編譯一個 parser」這件事本身就是透過 `tree-sitter` CLI 完成**（`tree-sitter build` 內部再去找 C compiler），這正是 README Requirements 把 `tree-sitter-cli 0.26.1+` 跟「C compiler」並列成兩個獨立條件的原因——`build-essential` 只解決後者。

### 4.3 LazyVim 對 `main` 分支的自救機制：找不到就用 mason 裝

`lua/lazyvim/util/treesitter.lua` 的健康檢查與自動安裝邏輯逐字（節錄）：

```lua
function M.check()
  ...
  local ret = {
    ["tree-sitter (CLI)"] = have("tree-sitter"),
    ["C compiler"] = have_cc,
    tar = have("tar"),
    curl = have("curl"),
  }
  ...
end

function M.ensure_treesitter_cli(cb)
  if vim.fn.executable("tree-sitter") == 1 then
    return cb(true)
  end
  -- try installing with mason
  if not pcall(require, "mason") then
    return cb(false, "`mason.nvim` is disabled in your config, so we cannot install it automatically.")
  end
  ...
  local mr = require("mason-registry")
  mr.refresh(function()
    local p = mr.get_package("tree-sitter-cli")
    if not p:is_installed() then
      LazyVim.info("Installing `tree-sitter-cli` with `mason.nvim`...")
      p:install(...)
```

（[LazyVim/lua/lazyvim/util/treesitter.lua](https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/util/treesitter.lua)）

`mason.nvim` 的 `tree-sitter-cli` 套件本身抓的是 tree-sitter 官方 GitHub Release 的預編譯二進位：

```yaml
source:
  id: pkg:github/tree-sitter/tree-sitter@v0.26.13
  asset:
    - target: linux_x64
      file: tree-sitter-linux-x64.gz
      bin: tree-sitter-linux-x64
```

（[mason-org/mason-registry, packages/tree-sitter-cli/package.yaml](https://github.com/mason-org/mason-registry/blob/main/packages/tree-sitter-cli/package.yaml)）

**這條安全網的前提條件（都要成立）：** (1) LazyVim 預設啟用 `mason.nvim`（starter 沒有關掉的話會有）、(2) 第一次啟動 Neovim、`lazy.nvim` 跑 `build = ...` 時**要有網路**能連 GitHub。這個 repo 的安裝腳本本身**不會**啟動 Neovim（只 clone starter、不執行 `nvim`），所以「補洞」這件事實際發生在使用者第一次手動打開 `nvim` 的當下，不是 bootstrap 腳本執行的當下。

### 4.4 Homebrew 也有現成的 `tree-sitter` formula（可雙平台裝）

```json
{"name": "tree-sitter", "versions": {"stable": "0.26.13", "bottle": true}}
```

（[formulae.brew.sh/api/formula/tree-sitter.json](https://formulae.brew.sh/api/formula/tree-sitter.json)）

`bottle: true` 代表這是預先編譯好的二進位安裝（不需要在機器上重新編譯），跟這個 repo 現有 `mise`/`fzf`/`git-lfs` 等 brew 套件的安裝方式一致。

---

## 5. mise 裝的 neovim：預編譯二進位，不是原始碼編譯

mise 的官方 registry 對 `neovim` 這個工具的定義（逐字）：

```toml
backends = ["vfox:mise-plugins/vfox-neovim", "aqua:neovim/neovim"]
bins = ["nvim"]
description = "Vim-fork focused on extensibility and usability"
version_order = "source"
```

（[jdx/mise, registry/neovim.toml](https://github.com/jdx/mise/blob/main/registry/neovim.toml)）

### 5.1 兩個 backend 都是抓 neovim 官方 GitHub Release 的預編譯壓縮檔

`vfox-neovim` 外掛（第一優先 backend）組裝下載檔名的邏輯逐字：

```lua
elseif os_type == "linux" then
    ext = ".tar.gz"
    if arch_type == "arm64" then
        platform = "linux-arm64"
    else
        platform = "linux-x86_64"
    end
...
local asset_name = "nvim-" .. platform .. ext
```

（[mise-plugins/vfox-neovim, hooks/available.lua](https://github.com/mise-plugins/vfox-neovim/blob/main/hooks/available.lua)）

備援的 `aqua:neovim/neovim` backend（aqua-registry 的定義）針對近期版本也是直接抓 GitHub Release asset：

```yaml
- version_constraint: "true"
  asset: nvim-{{.OS}}-{{.Arch}}.{{.Format}}
  format: tar.gz
  replacements:
    amd64: x86_64
    darwin: macos
    windows: win64
  files:
    - name: nvim
      src: "{{.AssetWithoutExt}}/bin/nvim"
```

（[aquaproj/aqua-registry, pkgs/neovim/neovim/registry.yaml](https://github.com/aquaproj/aqua-registry/blob/main/pkgs/neovim/neovim/registry.yaml)）

**結論：mise 兩個 backend 都沒有在本機編譯 Neovim，抓的都是 `neovim/neovim` repo 自己發布的 `nvim-linux-x86_64.tar.gz`。**

### 5.2 這份預編譯檔是在哪個 runner 上建出來的

Neovim 官方 release workflow，`linux` job 的 matrix 與註解逐字：

```yaml
# Build on the oldest supported images, so we have broader compatibility
jobs:
  ...
  linux:
    strategy:
      matrix:
        runner: [ ubuntu-22.04, ubuntu-22.04-arm ]
```

（[neovim/neovim, .github/workflows/release.yml](https://github.com/neovim/neovim/blob/master/.github/workflows/release.yml)）

### 5.3 glibc 版本對照（Debian/Ubuntu 官方套件頁面）

| 發行版 | glibc (libc6) 版本 | 來源 |
|---|---|---|
| Ubuntu 22.04 jammy（neovim 建置用 runner） | **2.35** | [packages.ubuntu.com/jammy/libc6](https://packages.ubuntu.com/jammy/libc6) |
| Debian 11 bullseye | **2.31** | [packages.debian.org/bullseye/libc6](https://packages.debian.org/bullseye/libc6) |
| Debian 12 bookworm | **2.36** | [packages.debian.org/bookworm/libc6](https://packages.debian.org/bookworm/libc6) |
| Debian 13 trixie | **2.41** | [packages.debian.org/trixie/libc6](https://packages.debian.org/trixie/libc6) |

**glibc 是向下相容、不能向上相容的動態函式庫**：一支連結到 glibc 2.35 符號的執行檔，理論上無法在 glibc 2.31 的系統上執行（會在 dynamic linker 階段報類似 `version 'GLIBC_2.3x' not found` 的錯誤）。這件事的機制本身（glibc 的相容性方向）是業界共識、不需要額外一手來源佐證；**這裡有一手來源支撐的部分是「neovim 官方建置用的 runner 版本」與「各 Debian 版本實際的 glibc 版本號」這兩個事實**，兩者相減直接得出「Debian 11 用 mise 裝新版 neovim 會裝到跑不動的二進位」這個結論。**我沒有找到 neovim 官方文件明文寫「最低支援 glibc 版本」**，上面的推論是從建置 runner 反推，查不到更直接的官方聲明。

### 5.4 `neovim@latest` 到底會不會抓到 nightly

GitHub Releases API 目前列出的最新幾筆（逐字節錄關鍵欄位）：

```
nightly   prerelease=True   draft=False
v0.12.5   prerelease=False  draft=False
stable    prerelease=False  draft=False
```

（[api.github.com/repos/neovim/neovim/releases](https://api.github.com/repos/neovim/neovim/releases)）

mise 官方文件對 `latest` 版本解析的說明逐字：

> For `latest`, an authoritative result from the backend still wins—for example, the release marked **Latest** on GitHub or Forgejo.

（[mise.jdx.dev, Dev Tools 章節](https://mise.jdx.dev/dev-tools/)）

`nightly` tag 被 GitHub API 標成 `prerelease: true`，不會是 GitHub 判定的「Latest release」，所以 **`neovim@latest` 目前不會抓到 nightly**——這點可以放心。

**但它仍然是「浮動」的：** `50-neovim.sh.tmpl` 的註解自己承認：「Writes `neovim = "latest"` to `~/.config/mise/config.toml` and installs it. Idempotent: re-running only re-resolves latest.」（見 repo 現有腳本）。意思是這台機器將來任何一次 `mise install`/`mise upgrade`，都會重新解析出「當下」的最新穩定版，而不是「當初 bootstrap 時測過的那個版本」。結合 §5.3 的 glibc 底線與 §1.3 的 nvim-treesitter 需求變動歷史，**風險不是「這次會不會抓到壞版本」，而是「這是一個沒有上限、沒有人工審核的自動升級管道，且升級對象是一個已經證實會突然提高門檻（0.11→0.12）的相依鏈最上游」**。

---

## 6. 舊 parser 殘留與清除方式

### 6.1 預設安裝路徑

`main` 分支 README 逐字：

```lua
require('nvim-treesitter').setup {
  -- Directory to install parsers and queries to (prepended to `runtimepath` to have priority)
  install_dir = vim.fn.stdpath('data') .. '/site'
}
```

（[main 分支 README#Setup](https://github.com/nvim-treesitter/nvim-treesitter/blob/main/README.md)）

`master` 分支則是透過 `M.get_parser_install_dir` 用 `utils.get_package_path()`（同樣落在 `stdpath` 系統下）決定安裝位置
（[master 分支 lua/nvim-treesitter/configs.lua](https://github.com/nvim-treesitter/nvim-treesitter/blob/master/lua/nvim-treesitter/configs.lua)）。

Neovim 官方文件對 `stdpath('data')` 在 Linux 上的預設值逐字：

> DATA DIRECTORY (DEFAULT)
>                   *$XDG_DATA_HOME*              Nvim: stdpath("data")
>     Unix:         ~/.local/share              ~/.local/share/nvim

（[neovim/runtime/doc/starting.txt](https://github.com/neovim/neovim/blob/master/runtime/doc/starting.txt)）

也就是說，`main` 分支的 parser 實際落在 `~/.local/share/nvim/site/parser/*.so`（Linux 上）。

### 6.2 官方推薦的清除／診斷指令

- `:TSUpdate [{language}]` — 把 parser 更新到 nvim-treesitter 目前鎖定的版本（[doc/nvim-treesitter.txt](https://github.com/nvim-treesitter/nvim-treesitter/blob/main/doc/nvim-treesitter.txt)）。
- `:TSUninstall {language|all}` — 「Deletes the parser for one or more {language}, or all parsers with `all`」（同上）。
- 診斷是否有「兩份 parser 打架」：`:echo nvim_get_runtime_file('parser', v:true)`，官方 troubleshooting 逐字建議「若看到超過一個路徑，把 `nvim-treesitter` 目錄以外的都刪掉」（[master 分支 README#Troubleshooting](https://github.com/nvim-treesitter/nvim-treesitter/blob/master/README.md)）。
- **手動整個清空重來**（`rm -rf ~/.local/share/nvim/site/parser` 或整個 `~/.local/share/nvim`）：官方文件沒有把這個當成正式的疑難排解步驟寫出來，這是從「安裝路徑就是這裡」與「LazyVim 官方安裝文件本身在換 starter 時建議 `mv ~/.local/share/nvim{,.bak}`」（見 §7）合理推得的做法，**查不到官方文件把「刪 `~/.local/share/nvim`」明講成 treesitter 疑難排解的第一步**。

---

## 7. LazyVim 官方安裝文件本身怎麼講 Requirements 與乾淨安裝

`LazyVim/LazyVim` README 的 Requirements 區塊逐字：

> - Neovim >= **0.11.2** (needs to be built with **LuaJIT**)
> - Git >= **2.19.0** (for partial clones support)
> - a [Nerd Font](https://www.nerdfonts.com/) **_(optional)_**
> - a **C** compiler for `nvim-treesitter`. See [here](https://github.com/nvim-treesitter/nvim-treesitter#requirements)

（[LazyVim/LazyVim README](https://github.com/LazyVim/LazyVim/blob/main/README.md)）

官方安裝頁（lazyvim.org/installation）建議乾淨安裝時連舊的 runtime 狀態一起搬走：

> Make a backup of your current Neovim files:
> ```
> mv ~/.config/nvim{,.bak}
> mv ~/.local/share/nvim{,.bak}
> mv ~/.local/state/nvim{,.bak}
> mv ~/.cache/nvim{,.bak}
> ```

（[lazyvim.org/installation](https://www.lazyvim.org/installation)）——這一段間接證實：LazyVim 官方認定「舊的 `~/.local/share/nvim`」是需要在乾淨安裝／排除疑難時處理的東西，跟 §6 的「舊 parser 殘留」是同一類問題的官方應對方式。

同一頁的 Fedora Docker 範例明確把 `tree-sitter-cli` 跟 `neovim` 一起裝：

```sh
dnf install -y git lazygit fd-find curl ripgrep tree-sitter-cli neovim
```

而 Alpine 範例只裝 `alpine-sdk`（build tools）沒有明確裝 `tree-sitter-cli`——**這兩個範例對 `tree-sitter-cli` 的處理不一致，查不到官方對這個不一致的說明**，我判斷 Alpine 範例可能較舊或依賴 §4.3 的 mason 自動安裝機制，不確定，如實記錄矛盾。

---

## 8. 對本 repo 的具體建議

### 8.1 `.chezmoiscripts/run_onchange_before_10-install-packages.sh.tmpl`（apt，僅 Linux）

**現況：** `zsh git curl build-essential procps file`

- **C compiler 需求：已滿足，不用改。** `build-essential` 提供 gcc/g++/make/libc6-dev，滿足 §4.1／§4.2 兩個分支對「C compiler」的要求（含 `master` 分支額外要求的 libstdc++，來自 g++）。
- **`tar`：`main` 分支 README 明列為需求，目前清單裡沒有明確加。** Debian/Ubuntu 的最小安裝映像通常內建 `tar`（它是 essential 套件），但我**查不到**官方文件保證所有基底映像都有它，屬於低風險、低成本的補強項，若要追求穩妥可以加，不加也大概率沒事——**不是本次調查能給出肯定答案的項目**。
- **不建議在這裡加 `tree-sitter` CLI。** 它不是 apt 套件（Debian/Ubuntu 官方 repo 沒有這個套件，需要另外抓 GitHub Release 二進位或用 cargo/mason），跟這支腳本「只裝 apt 套件」的定位（AGENTS.md 裡的既有慣例）不符。

### 8.2 `.chezmoiscripts/run_onchange_before_30-install-brew-packages.sh.tmpl`（brew，雙平台）

**現況：** `mise fzf git-lfs ripgrep fd lazygit`

- **建議新增 `tree-sitter` formula**（§4.4 已確認是 bottled、雙平台可用）。理由：`nvim-treesitter` `main` 分支把 `tree-sitter` CLI 從「選用」升級成「每次編譯 parser 都要用」的硬性需求（§4.2 原始碼證實），而目前這個需求完全靠 LazyVim 執行期的 mason 自動安裝機制頂著（§4.3）。加上這一行可以把依賴前移到 bootstrap 階段、變成確定性安裝，不再依賴「使用者第一次開 nvim 時剛好有網路、剛好 mason.nvim 沒被關掉」這兩個執行期條件。
- **風險：幾乎沒有。** 這是一個獨立的 bottled formula，不會跟現有套件衝突，安裝失敗只會讓 `mason.nvim` 的自動安裝機制照舊接手（現狀不會變差）。

### 8.3 `.chezmoiscripts/run_onchange_before_50-neovim.sh.tmpl`

**現況：** `mise use --global neovim@latest`，之後 clone LazyVim starter。

- **`neovim@latest` 建議改成明確釘版本。** 不是因為它會抓到 nightly（§5.4 已排除這個疑慮），而是兩個更實際的理由：
  1. **glibc 底線風險（§5.3）：** mise 裝的是 neovim 官方在 `ubuntu-22.04`（glibc 2.35）建出來的預編譯檔。這個 runner 版本本質上是 neovim 專案自己隨時間調整的政策（他們的原話是「build on the oldest supported images」——但「oldest supported」這個標準本身會隨 GitHub Actions 汰役舊 runner 而水漲船高）。目前只影響 Debian 11 及更舊的系統，Debian 12/13 都還在安全範圍內；但因為 `latest` 是浮動的，這條安全邊界不是這個 repo 能控制或提前知會的。
  2. **上游相依鏈版本要求會突然收緊（§1.3，issue #7092 是真實案例）：** `nvim-treesitter` `main` 分支對 Neovim 版本的最低要求，在半年多內從「相容 0.11」收緊到「只認 0.12+」。LazyVim 已經加了偵測邏輯來自救（太舊會自動釘舊 commit），但**沒有對稱的「太新」保護**——如果 nvim-treesitter 未來要求 0.13+ 而這個 repo 用 `latest` 裝到的是 0.13.x，目前看不到任何自動降級機制。
  - **建議做法：** 把 `mise use --global neovim@latest` 改成 `mise use --global neovim@<具體版本，例如目前的 0.12.5>`，並把「何時手動升級這個 pin」變成一個刻意的、有 changelog 可查的動作（例如升級時順手看一眼 nvim-treesitter 與 LazyVim 的 Requirements 有沒有變動）。
  - **權衡：** 釘版本的代價是需要有人定期手動升級，否則會停在舊版本錯過修補與新功能；`latest` 的好處是永遠追新、零維護成本。如果這個 repo 的哲學就是「其他工具（`mise fzf git-lfs ripgrep fd lazygit`）也都是裝當下最新版，沒有特別釘」，那對 neovim 特別處理需要額外理由——本文提供的理由是：**neovim 是這條鏈裡唯一「預編譯二進位有外部系統相容性底線（glibc）」且「下游相依（nvim-treesitter）版本要求已經證實會無預警收緊」的工具**，跟 `fzf`/`ripgrep`/`fd`/`lazygit` 這種相對獨立、沒有這兩個特性的 CLI 工具不是同一個風險等級。
- **`tree-sitter` CLI 沒有在這支腳本裡處理，見 §8.2 的建議。**
- **這支腳本目前不會啟動 `nvim`，所以 §4.3 的 mason 自動安裝與 lazy.nvim 的 `:TSUpdate` build 都不會在 bootstrap 當下發生**——它們發生在使用者第一次手動打開 `nvim` 的時候。這不是問題（腳本本來就沒有假裝要做完整的 plugin 安裝），只是提醒：如果之後想讓 bootstrap 更「一次到位」，需要額外用 headless nvim（例如 `nvim --headless "+Lazy! sync" +qa`）觸發，那時候 §8.2 的 `tree-sitter` 依賴就會從「執行期救援」變成「bootstrap 期間就需要」，重要性更高。

### 8.4 `private_dot_config/nvim/lua/plugins/completion.lua`

跟 treesitter 無關（只覆寫 `blink.cmp` 的 keymap），不受本次調查影響，不需要改動。

---

## 附錄：查不到、或只有間接證據的項目

1. **Neovim 官方沒有明文寫「最低支援 glibc 版本」。** §5.3 的結論是從「release.yml 的 runner 版本」與「Debian/Ubuntu 官方套件頁的 glibc 版本」兩份一手來源相減推得，不是 neovim 官方自己的聲明。
2. **`abortEmpty`／`:TSUpdate` 之外，官方沒有把「直接刪除 `~/.local/share/nvim`」寫成正式的 treesitter 疑難排解步驟。** §6.2 最後一條是推論。
3. **LazyVim 安裝文件裡 Fedora 範例裝 `tree-sitter-cli`、Alpine 範例不裝的不一致，查不到官方解釋。**（§7）
4. **`neovim@latest` 在 mise 的 `version_order = "source"` 設定下，「latest」與「ls-remote 排序」的完整互動細節**——官方文件只講了「latest 優先信任後端的權威 latest 標記」這一條規則，没有更完整地說明 `version_order = "source"` 在 `neovim@latest` 這個具體案例下是否還有其他分支邏輯；本文的結論只依賴那一條被文件明講的規則。
5. **PR #6253 body 用「archived」形容 `master` 分支，但官方 README 用的字是「frozen/locked」，兩者是否等價（尤其 GitHub 的 repository-level archive 狀態）查不到，本文不採信「archived」這個字面說法，只採信其動機描述。**（§1.2）
6. **這個 repo 目前使用的 Debian/Ubuntu 版本沒有寫死在腳本裡**（`10-install-packages` 只判斷 `.chezmoi.os == "linux"`，不分辨發行版版本），所以「這台機器的 glibc 是否夠新」是一個腳本層面完全沒有檢查、也查不到的執行期變數。

## 引用來源

**nvim-treesitter/nvim-treesitter**

- [main 分支 README](https://github.com/nvim-treesitter/nvim-treesitter/blob/main/README.md) — Requirements、Setup、install_dir
- [master 分支 README](https://github.com/nvim-treesitter/nvim-treesitter/blob/master/README.md) — Requirements、Troubleshooting
- [main 分支 doc/nvim-treesitter.txt](https://github.com/nvim-treesitter/nvim-treesitter/blob/main/doc/nvim-treesitter.txt) — `:TSInstall` / `:TSUpdate` / `:TSUninstall`
- [main 分支 lua/nvim-treesitter/install.lua](https://github.com/nvim-treesitter/nvim-treesitter/blob/main/lua/nvim-treesitter/install.lua) — `--abi` 旗標、`tree-sitter build`
- [master 分支 lua/nvim-treesitter/install.lua](https://github.com/nvim-treesitter/nvim-treesitter/blob/master/lua/nvim-treesitter/install.lua) — `M.compilers`、`generate_from_grammar` 判斷
- [master 分支 lua/nvim-treesitter/configs.lua](https://github.com/nvim-treesitter/nvim-treesitter/blob/master/lua/nvim-treesitter/configs.lua) — `parser_install_dir`
- issues：[#8519](https://github.com/nvim-treesitter/nvim-treesitter/issues/8519)、[#8440](https://github.com/nvim-treesitter/nvim-treesitter/issues/8440)、[#8381](https://github.com/nvim-treesitter/nvim-treesitter/issues/8381)、PR [#8619](https://github.com/nvim-treesitter/nvim-treesitter/pull/8619)

**neovim/neovim**

- [releases/tag/stable](https://github.com/neovim/neovim/releases/tag/stable)（目前 `v0.12.5`）
- [.github/workflows/release.yml](https://github.com/neovim/neovim/blob/master/.github/workflows/release.yml) — Linux release 用 `ubuntu-22.04` runner
- [runtime/doc/treesitter.txt](https://github.com/neovim/neovim/blob/master/runtime/doc/treesitter.txt) — `vim.treesitter.language_version` / `minimum_language_version`
- [runtime/doc/starting.txt](https://github.com/neovim/neovim/blob/master/runtime/doc/starting.txt) — `stdpath("data")` 預設值
- [src/nvim/lua/treesitter.c](https://github.com/neovim/neovim/blob/master/src/nvim/lua/treesitter.c) — `ABI version mismatch` 錯誤字串
- [runtime/queries/](https://github.com/neovim/neovim/tree/master/runtime/queries) — 內建 query 涵蓋的語言
- [api.github.com/repos/neovim/neovim/releases](https://api.github.com/repos/neovim/neovim/releases) — `nightly` 標 `prerelease: true`
- [BUILD.md](https://github.com/neovim/neovim/blob/master/BUILD.md)（僅供對照，未在本文引用其結論）

**LazyVim**

- [LazyVim/LazyVim README](https://github.com/LazyVim/LazyVim/blob/main/README.md) — Requirements
- [lua/lazyvim/plugins/treesitter.lua](https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/plugins/treesitter.lua) — `branch = "main"`、版本偵測 pin
- [lua/lazyvim/util/treesitter.lua](https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/util/treesitter.lua) — 健康檢查、mason 自動安裝 `tree-sitter-cli`
- commit [5eac460c](https://github.com/LazyVim/LazyVim/commit/5eac460c) — 遷移到 `main` 分支
- commit [ef272ff7](https://github.com/LazyVim/LazyVim/commit/ef272ff7) — 加入版本偵測 pin
- issue [#7092](https://github.com/LazyVim/LazyVim/issues/7092) — 破版事故原文
- PR [#6253](https://github.com/LazyVim/LazyVim/pull/6253)（未合併但記錄了動機）
- [lazyvim.org/installation](https://www.lazyvim.org/installation) — 官方安裝步驟、Docker 範例

**mise / aqua / mason**

- [jdx/mise, registry/neovim.toml](https://github.com/jdx/mise/blob/main/registry/neovim.toml) — backend 定義
- [mise.jdx.dev/dev-tools/](https://mise.jdx.dev/dev-tools/) — `latest` 版本解析規則
- [mise-plugins/vfox-neovim, hooks/available.lua](https://github.com/mise-plugins/vfox-neovim/blob/main/hooks/available.lua) — 下載檔名邏輯
- [aquaproj/aqua-registry, pkgs/neovim/neovim/registry.yaml](https://github.com/aquaproj/aqua-registry/blob/main/pkgs/neovim/neovim/registry.yaml) — GitHub Release asset 對照
- [mason-org/mason-registry, packages/tree-sitter-cli/package.yaml](https://github.com/mason-org/mason-registry/blob/main/packages/tree-sitter-cli/package.yaml)

**Debian / Ubuntu / Homebrew**

- [packages.debian.org/bullseye/libc6](https://packages.debian.org/bullseye/libc6)（2.31）
- [packages.debian.org/bookworm/libc6](https://packages.debian.org/bookworm/libc6)（2.36）
- [packages.debian.org/trixie/libc6](https://packages.debian.org/trixie/libc6)（2.41）
- [packages.ubuntu.com/jammy/libc6](https://packages.ubuntu.com/jammy/libc6)（2.35）
- [formulae.brew.sh/api/formula/tree-sitter.json](https://formulae.brew.sh/api/formula/tree-sitter.json)

**這個 repo 現況（供對照，非外部來源）**

- `.chezmoiscripts/run_onchange_before_10-install-packages.sh.tmpl`
- `.chezmoiscripts/run_onchange_before_30-install-brew-packages.sh.tmpl`
- `.chezmoiscripts/run_onchange_before_50-neovim.sh.tmpl`
- `private_dot_config/nvim/lua/plugins/completion.lua`
