# SPEC — Arch 家族支援：正式版 omarchy 與純 Arch

- `spec_version`: v1
- `status`: draft
- `tier`: 3
- `scope`: arch-family-support
- `base_ref`: `4e6f13c`（`origin/main`，PR #18 合併點）
- `contract`: `~/.claude/CLAUDE.md` 的 evidence-first 契約，未被本 repo 覆寫
- `supersedes`: `specs/archive/archlinux-support/SPEC.md`（v2，shipped）的 F1 與 D1
- `research`: 本 SPEC §1（2026-09-08 在 omarchy 4.0.2 VM 與 Arch WSL 映像實測）

Tier 3 的理由：與 `archlinux-support` 相同。變更會在真實機器上以 root 或 `sudo`
執行 pacman、改變登入 shell，並且在純 Arch 上搬動使用者現有的 `~/.config/nvim`。
任一步寫錯就是使用者環境或資料的損失。

---

## 0. 目標

`archlinux-support` 只在 WSL 版 omarchy（dev 模式，`ID=arch`）上驗證過。本次讓
同一份 source 在下列兩種環境也能 `chezmoi init --apply` 出可用的環境，且現有四個
平台（Debian 系、macOS、Windows、WSL omarchy）的行為不變：

| 環境 | 現況 | 目標 |
|---|---|---|
| **正式安裝的 omarchy**（ISO 安裝，4.0.2） | `/etc/os-release` 是 `ID=omarchy`，被當成 Debian：apt 分支、Homebrew 安裝腳本全部渲染，`10-install-packages` 在 `dpkg-query` 之後停止 | 走 pacman 路徑，與 WSL omarchy 相同 |
| **純 Arch**（官方 WSL 映像，無 omarchy） | 套件路徑正確，但 `50-neovim` 渲染成空，`~/.config/nvim` 只剩本 repo 疊上去的 `completion.lua`，nvim 以空設定啟動 | clone LazyVim starter，neovim 仍由 pacman 提供 |

---

## 1. 已實測確立的事實

環境 A：omarchy 4.0.2 VM（ISO 安裝，kernel `7.1.9-arch1-2`，使用者 `madao`，
`wheel`，`sudo` 需要密碼），經 ssh 進入。
環境 B：`wsl --install archlinux --name arch` 的官方 Arch WSL 映像，只有 root，
systemd 已啟用。

| # | 事實 | 來源 |
|---|---|---|
| F1 | 環境 A 的 `/etc/os-release` 是 `ID=omarchy`、`ID_LIKE=arch`、`VERSION_ID="4.0.2"`。檔案來自 `/usr/share/omarchy/etc-overrides/os-release`；`/usr/lib/os-release` 仍是 `ID=arch`。chezmoi 讀到 `.chezmoi.osRelease.id = "omarchy"`、`.idLike = "arch"` | 環境 A `cat`、`diff`、`chezmoi data` |
| F2 | 環境 A 上真實 chezmoi 渲染 `platform.toml` 得到 `distro = "omarchy"`、`pkgManager = "apt"`、`brewPrefix = "/home/linuxbrew/.linuxbrew"`。`10-install-packages` 渲染成 apt 分支，`20-install-homebrew` 非空 | 環境 A `chezmoi execute-template` |
| F3 | 舊 SPEC 的 F1（omarchy `ID=arch`，沒有 `ID_LIKE`）只對 WSL 版 omarchy dev 映像成立。兩種 omarchy 都存在，都要支援 | 舊 SPEC F1；本 F1 |
| F4 | 環境 A 是正式模式：沒有 `/etc/omarchy.conf`，`/usr/share/omarchy/default/bash/env-bootstrap` 與 `/etc/profile.d/omarchy.sh` 存在。現有 `.zshrc`/`.zprofile` 的 omarchy 區塊以 `/usr/share/omarchy` 為預設值，已涵蓋 | 環境 A `ls` |
| F5 | 環境 A 出廠已裝 `omarchy-nvim`、`neovim`、`mise-bin`（`pacman -Q mise` 經 provides 命中）、`fzf`、`ripgrep`、`fd`、`lazygit`、`tree-sitter-cli`、`base-devel`；沒有 `zsh`、`git-lfs`。`~/.config/nvim` 含 `omarchy-theme-hotreload.lua`、`theme.lua` symlink 與 `lazy-lock.json`。`~/.config/git/config` 是 omarchy 寫的 alias 檔 | 環境 A `pacman -Q`、`ls`、`cat` |
| F6 | 環境 B 全新映像沒有 pacman 同步資料庫（`/var/lib/pacman/sync` 為空），沒有 `git`、`sudo`、`zsh`。映像的歡迎訊息要求第一次啟動後執行 `pacman -Syu` | 環境 B `ls`、`command -v`、wsl 安裝輸出 |
| F7 | 環境 B 未更新時，`init --apply` 在 `10-install-packages` 停止：`error: target not found: zsh`，腳本印出更新系統的提示後 exit 1。這是 `pacman-install.sh` 的設計（不做 `-Sy`） | 環境 B `install.log` |
| F8 | 環境 B 執行 `pacman -Syu` 後，以 root 重跑 `chezmoi apply` rc=0：11 個套件裝好、externals 落地、互動 zsh 載入 OMZ 與 p10k、`mise fzf nvim tree-sitter git-lfs rg fd lazygit` 全部解析、git-lfs filter 寫入 `~/.gitconfig`、linger 開啟且 `/run/user/0` 存在、第二次 apply 不互動、`chezmoi git` 正常。`default-shell` 無 tty 時印出 `chsh -s /bin/zsh` 提示 | 環境 B 實測 |
| F9 | 環境 B 套用後 `~/.config/nvim` 只有 `lua/plugins/completion.lua`。沒有 lazy.nvim，此檔不會被載入，`nvim --headless` 啟動且不報錯 | 環境 B `find`、`nvim --headless` |
| F10 | 沒有 `git` 時 `chezmoi init gn00678465` 用內建 git clone 成功。`init.sh` 不會卡在這一步 | 環境 B 以移除 git 的 PATH 實測 |
| F11 | 以 root 執行時所有腳本走 `id -u = 0` 分支，不需要 sudo。一般使用者在環境 B 需要先安裝 `sudo`，否則腳本停在 `sudo not available` | 腳本邏輯；環境 B `command -v sudo` |
| F12 | `tests/sandbox/omarchy.sh` 要求 `ID=arch` 與免密碼 sudo，`_probe.sh` 以 `ID` 判斷 Arch 分支並斷言 `omarchy-version` 與 `omarchy-theme-hotreload.lua`。環境 A（`ID=omarchy`）與環境 B（root、無 omarchy）都無法通過 L9 | 原始碼 |

---

## 2. 設計

### 2.1 `platform.toml`：Arch 家族判斷

`$distro` 維持 `.chezmoi.osRelease.id` 的原值（omarchy 上是 `omarchy`）。新增
`$distroLike`，來源 `.chezmoi.osRelease.idLike`（純 Arch 沒有此 key，需 `hasKey`
守住），測試接縫 `distroLikeOverride`。

`pkgManager` 在 Linux 上的判斷改為：`$distro` 等於 `arch`，或 `$distroLike` 以空白
分割後含有 `arch` → `pacman`；否則 `apt`。`brewPrefix` 的判斷不變（跟著
`pkgManager`）。輸出欄位不新增；呼叫端繼續只看 `$p.pkgManager` 與
`$p.brewPrefix`。

新增 fixture `tests/fixtures/os-omarchy.toml`：`distroOverride = "omarchy"`、
`distroLikeOverride = "arch"`。`os-arch.toml` 不變。

### 2.2 `50-neovim` 在 pacman 平台執行

平台守衛從 `ne $p.brewPrefix ""` 改為 `$p.isPosix`，內部分兩段：

- mise 段：只在 `ne $p.brewPrefix ""` 渲染（不變）。pacman 平台的 neovim 由
  `30-install-pacman-packages` 安裝，`versions.toml` 的釘版本仍不適用於 Arch。
- starter 段：兩者共用。pacman 平台在進入 starter 段前先做執行期判斷：
  `pacman -Q omarchy-nvim` 成功即 `exit 0`，不備份、不 clone、不寫 marker。
  這取代舊 SPEC 的 D1=A，等於 D1 選項 C。WSL omarchy 與正式 omarchy 都有
  `omarchy-nvim`，行為與現況相同。

`.zshrc`、`.zprofile`、`default-shell`、`40-git-lfs`、pacman 兩支腳本不變。

### 2.3 純 Arch 的前置條件（只改文件）

不改 `pacman-install.sh`。README 的 Arch 段落加上：全新系統先 `pacman -Syu`
並重新啟動；官方 WSL 映像預設只有 root，以 root 執行可直接安裝，改用一般使用者
時要先裝 `sudo` 並設定 `wheel`。

### 2.4 L9：三種 Arch 家族環境

- `_probe.sh`：`arch=1` 的判斷改為 `ID=arch` 或 `ID_LIKE` 含 `arch`。新增
  `omarchy=1`，以 `pacman -Q omarchy-nvim` 判斷。`omarchy-version`/`OMARCHY_PATH`
  與「omarchy nvim 設定未搬動」兩條只在 `omarchy=1` 執行，否則 SKIP；純 Arch 改跑
  既有的「nvim 設定是 LazyVim starter 且有 marker」。M4 接縫檢查改為期望
  `pkgManager=pacman`、`brewPrefix` 空，`distro` 為 `arch` 或 `omarchy`。
- `tests/sandbox/omarchy.sh`：接受 `ID_LIKE=arch`；預設使用者是 root 時跳過
  `sudo -n` 檢查。加 `--syu` 旗標，在探針之前以 root 執行一次
  `pacman -Syu --noconfirm`，只給全新的拋棄式 distro 用；不加旗標且同步資料庫
  為空時停下並提示。
- 新增 `tests/sandbox/ssh.sh <user@host>`：與 `omarchy.sh` 相同的管線模式
  （`git archive | ssh tar`，探針，`ssh tar | tar`），對正式 omarchy VM 跑探針。
  前提：該使用者有免密碼 sudo（探針沒有 tty）。它只跑
  `chezmoi init --apply`，不改其他系統狀態。

### 2.5 文件

- `docs/research/archlinux-omarchy-support.md` §2.1 補上 F1 與 F3 的更正。
- `AGENTS.md`：`50-neovim` 兩條合併，改寫為「pacman 平台執行期偵測
  `omarchy-nvim`」；平台選擇段落加上 `ID_LIKE`。
- `README.md`：表格的「Arch（omarchy）」欄改為「Arch 家族」，neovim 列分兩種；
  加 §2.3 的前置條件。

---

## 3. 情境（每一條對應至少一個以它命名的自動化測試）

| # | 層 | 情境 | 期望 |
|---|---|---|---|
| S1 | L1 | `os-omarchy` fixture | `linux\|amd64\|false\|true\|\|omarchy\|pacman` |
| S2 | L1 | `os-arch`、`os-linux`、darwin、windows fixture | 輸出逐位元組不變 |
| S3 | L1 | `distroLikeOverride` 只有 partial 認得 | 生產 `.chezmoi.toml.tmpl` 原始碼與渲染結果都沒有這個 key |
| S4 | L2 | `os-omarchy` 的腳本渲染矩陣 | 與 `os-arch` 相同：10 走 pacman、30-pacman 非空、20/30-brew 空、無 `linuxbrew` |
| S5 | L2 | `50-neovim` 在 `os-arch`/`os-omarchy` | 非空；含 `pacman -Q omarchy-nvim`；不含 `mise`、`brew`、`linuxbrew` |
| S6 | L2 | `50-neovim` 在 `os-linux`/darwin | 逐位元組不變 |
| S7 | L6/L11 | Arch 家族的 `.zshrc`/`.zprofile` golden | `os-omarchy` 與 `os-arch` 輸出相同 |
| S8 | L7 | `50-neovim` 的 Arch 分支在重導向環境執行：假 `pacman` 回報 `omarchy-nvim` 已裝 | 不備份、不 clone、marker 不存在 |
| S9 | L7 | 同上，假 `pacman` 回報未裝 | 既有 `~/.config/nvim` 搬到 `.bak`，starter clone，marker 存在；第二次執行不再搬動 |
| S10 | L9 | 環境 B（`omarchy.sh --distro arch --syu`，root） | 探針 0 FAIL；`~/.config/nvim/.chezmoi-lazyvim-starter` 存在；`nvim --headless +Lazy! sync` 通過 |
| S11 | L9 | 環境 A（`ssh.sh madao@<vm>`） | 探針 0 FAIL；`omarchy-theme-hotreload.lua` 仍在；marker 不存在；`pkgManager=pacman` |
| S12 | gate | pacman 套件名可解析 | `tools/gate-pacman-ids.sh` 對 `os-omarchy` 也執行 |

---

## 4. Must NOT（違反任一條即視為失敗）

1. **不得**在 Windows 主機的真實使用者環境執行 `chezmoi apply`。真實 apply 只准在
   環境 A（使用者已重建並授權）與環境 B（拋棄式 WSL distro）。
2. **不得**改變 Debian 系、macOS、Windows 的任何渲染輸出（S2、S6）。
3. **不得**在任何有 `omarchy-nvim` 的機器上搬動、備份或刪除 `~/.config/nvim`、
   `~/.local/share/nvim`、`~/.local/state/nvim`、`~/.cache/nvim`（S8、S11）。
4. **不得**在 Arch 家族安裝 Homebrew 或渲染任何含 `linuxbrew` 的腳本（S4）。
5. **不得**在 `.chezmoiscripts/` 執行 `pacman -Sy`、`-Syu`、`-R*`、`--overwrite`。
   `--syu` 只存在於測試啟動器，且只對拋棄式 distro。
6. **不得**在 `.chezmoiscripts/` 或 zsh 檔案以 `ID=omarchy` 做分支。omarchy 的偵測
   只有執行期的 `pacman -Q omarchy-nvim` 與既有的檔案存在檢查。
7. **不得**在環境 A 做 `chezmoi init --apply` 以外的系統變更。
8. **不得**把 `mise` 的 neovim 釘版本帶到 Arch 家族。

---

## 5. Tier 3 失效模型

| # | 失效 | 後果 | 對應檢查 |
|---|---|---|---|
| M1 | `ID_LIKE` 判斷寫錯，正式 omarchy 仍走 apt | 安裝在第一支腳本停止 | S1、S4、S11 |
| M2 | `ID_LIKE` 判斷過寬（例如 `ID_LIKE="ubuntu debian"` 的字串比對誤命中） | Debian 衍生版走 pacman | S2；用 `splitList` 精確比對 |
| M3 | `50-neovim` 在 omarchy 上誤判未裝 `omarchy-nvim` | omarchy 主題整合被搬進 `.bak` | S8、S11 |
| M4 | `50-neovim` 在純 Arch 上重複備份 | 使用者設定被反覆搬動 | S9 |
| M5 | 假 `pacman` 與真實 `pacman -Q` 的 provides 行為不同 | L7 通過但 L9 失敗 | S10、S11 用真實 pacman |
| M6 | 探針的 omarchy 判斷與腳本不一致 | L9 在其中一種環境誤報 | 兩者都用 `pacman -Q omarchy-nvim` |
| M7 | 測試接縫 `distroLikeOverride` 滲入生產 config | 所有平台判斷失準 | S3 |

---

## 6. Setup plan

- 分支：`feat/arch-family-support`，自 `4e6f13c`。
- 提交節奏：SPEC → 測試（RED）→ 實作（GREEN），每個情境一組提交。
- 新增檔案：`tests/fixtures/os-omarchy.toml`、`tests/sandbox/ssh.sh`、
  `tests/golden/render/omarchy/`（若 L11 需要）。
- 真實環境：環境 B 由 `omarchy.sh --distro arch --syu` 以 root 執行
  `pacman -Syu` 與 `chezmoi init --apply`，用後可重建。環境 A 由 `ssh.sh` 執行
  `chezmoi init --apply`，需要使用者先在 VM 上為 `madao` 設定免密碼 sudo。
- 需要的 gate 之外的動作：無。

---

## 7. 已知限制與未證實項目

- 純 Arch 的一般使用者流程（非 root）未實測；只驗證 root 與 omarchy 的
  `wheel` 使用者。
- 全新 Arch 映像的 `pacman -Syu` 是使用者的動作，本 repo 不代做。
- WSL 版 omarchy 已被使用者移除，S11 之後不再對它重跑；其行為由 `os-arch`
  fixture 與環境 B 的 pacman 路徑覆蓋，omarchy 專屬部分由環境 A 覆蓋。
- `tests/sandbox/ssh.sh` 需要免密碼 sudo；有密碼的 VM 只能由使用者在 tty 內
  手動執行 `init.sh`。

---

## 8. 已決定事項（exploration round 1）

| # | 決定 | 選定 | 未選 |
|---|---|---|---|
| D1 | omarchy 偵測方式 | **`ID_LIKE` 含 `arch` 即走 pacman；`distro` 保留原值** | 把 `distro` 正規化為 `arch`（失去資訊） |
| D2 | 純 Arch 的 neovim | **執行期 `pacman -Q omarchy-nvim`，沒有就 clone starter（舊 D1 選項 C）** | 維持渲染成空（純 Arch 沒有可用的 nvim 設定） |
| D3 | 全新 Arch 的資料庫 | **只改文件與測試啟動器；腳本不做 `-Sy`** | 腳本偵測空資料庫後自動 `-Syu` |
| D4 | 環境 A 的探針 | **新增 `ssh.sh`，前提免密碼 sudo** | 不做自動化，使用者手動跑 `init.sh` |

## Approval

（待核准）

## Revisions

- 2026-09-08 — v1 草稿。依環境 A、B 實測撰寫；D1–D4 由使用者以結構化提問選定（exploration round 1），全文待使用者審閱與核准。
