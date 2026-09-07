# SPEC — ArchLinux（omarchy）支援

- `spec_version`: v2
- `status`: approved
- `tier`: 3
- `scope`: archlinux-support
- `base_ref`: `4ddc1b5`（`origin/main`，PR #16 合併點）
- `contract`: `~/.claude/CLAUDE.md` 的 evidence-first 契約，未被本 repo 覆寫
- `research`: `docs/research/archlinux-omarchy-support.md`（commit `edc0922`）

Tier 3 的理由：這次變更會在 omarchy 上以 `sudo pacman` 安裝套件、改變登入
shell、覆寫 omarchy 寫入的 `~/.config/git/config`，並且決定是否搬動使用者現有的
`~/.config/nvim`。任一步寫錯就是使用者環境或資料的損失。與 `windows-support`
（同樣搬動 nvim 設定）的分級一致。

---

## 0. 目標

讓同一份 source 在 **ArchLinux（以 omarchy v4.x 為目標）** 上 `chezmoi init --apply`
出一套等價的環境。現有三個平台的行為不得改變。

| 面向 | Linux（Debian 系，現況） | macOS（現況） | Windows（現況） | **Arch / omarchy（本次新增）** |
|---|---|---|---|---|
| 系統套件 | apt | — | winget | **pacman（`core`/`extra`）** |
| 工具鏈 | Homebrew | Homebrew | winget | **pacman，不裝 Homebrew** |
| Shell | zsh + Oh My Zsh + p10k | 同左 | pwsh 7 | **zsh + Oh My Zsh + p10k，並載入 omarchy 的 `env-bootstrap`** |
| 版本管理 | mise（brew） | mise（brew） | mise（winget） | **mise（pacman）** |
| neovim | mise 釘 `versions.toml` + LazyVim starter | 同左 | 同左 | **pacman `neovim`；不 clone starter，沿用 omarchy 出廠的 `omarchy-nvim`** |
| 預設 shell | `chsh` 到 zsh | — | — | **`chsh` 到 zsh（同 Linux）** |

---

## 1. 已實測確立的事實

環境：Windows 11 主機、chezmoi v2.72.0、WSL distro `omarchy`（Arch rolling
`VERSION_ID=20260830`，omarchy `dev (f0020448)`，git tag `v4.0.0`）。
細節與指令輸出見研究文件 §2、§4。

| # | 事實 | 來源 |
|---|---|---|
| F1 | omarchy 的 `/etc/os-release` 有 `ID=arch`，**沒有** `ID_LIKE` | 研究 §2.1 |
| F2 | Windows 主機上 `.chezmoi.osRelease` 是空 map `{}`；`hasKey .chezmoi "osRelease"` 為 true | 本機 `execute-template` |
| F3 | omarchy 內**沒有** chezmoi、zsh、brew、git-lfs；**有** pacman、yay、sudo、git、curl、mise、nvim 0.12.5、chsh（util-linux）、systemd（PID 1）、`XDG_RUNTIME_DIR=/run/user/1000` | 研究 §2.1 |
| F4 | brew 清單的七個工具在 Arch `extra` 都有同名套件：`mise fzf git-lfs ripgrep fd lazygit tree-sitter-cli`；`neovim`、`zsh`、`chezmoi`、`base-devel` 亦在官方 repo。不需要 AUR | 研究 §4.1（`pacman -Si` 逐一實測） |
| F5 | omarchy 用套件 `omarchy-nvim` 把 LazyVim 放進 `/etc/skel/.config/nvim/`，`useradd -m` 抄進 `$HOME`。`~/.config/nvim` 是一般目錄，不是 symlink，且含 omarchy 專屬外掛（`lua/plugins/omarchy-theme-hotreload.lua`、`theme.lua`、`all-themes.lua`） | 研究 §2.2；本機 `find /etc/skel` |
| F6 | `/etc/skel/.config/nvim/lua/plugins/` **沒有** `completion.lua`。本 repo 管理的 `.config/nvim/lua/plugins/completion.lua` 疊在上面不會撞名 | 本機 `find /etc/skel` |
| F7 | omarchy 安裝時寫入 `~/.config/git/config`（alias `co/br/ci/st`、`init.defaultbranch=master`、`pull.rebase=true` 等），不在 `/etc/skel`。本 repo 以「全檔接管」管理同一個路徑 | 本機 `git config --global --list`；`private_dot_config/git/config` 註解 |
| F8 | `omarchy reinstall configs` 執行 `cp -af /etc/skel/. ~/`，會覆寫 `~/.config/nvim/**` 中與 skel 同名的檔案；不會碰 `completion.lua`（F6）與 `~/.config/git/config`（F7） | 研究 §5 |
| F9 | omarchy 的 shell 整合分兩層：`default/bash/env-bootstrap`（POSIX sh 語法：`.`、`case`、`${PATH:+…}`，設 `OMARCHY_PATH` 與 PATH）與 `default/bash/rc`（bash 專用：`source`、`bind -f`） | 本機 `cat` |
| F10 | 這台 WSL 是 dev 模式：`/etc/omarchy.conf` 指定 `OMARCHY_PATH=/home/omarchy/.local/share/omarchy`；`/usr/share/omarchy` 與 `/etc/profile.d/omarchy.sh` 不存在。正式安裝的預設值是 `/usr/share/omarchy`，`omarchy-*` 在 `/usr/bin` | 本機 `ls`；`env-bootstrap` 註解 |
| F11 | 本 repo 在 Linux 上管理的 `~/.config` 檔案只有 `git/config`、`nvim/lua/plugins/completion.lua`、`uv/uv.toml`；其餘落在 `~/.zshrc`、`~/.zprofile`、`~/.p10k.zsh`、`~/.oh-my-zsh/`、`~/.claude/`、`~/.codex/`、`~/.agents/` | 本機 `chezmoi managed`（linux fixture） |
| F12 | `chezmoi managed` 會列出渲染成空的腳本 | `tests/golden/managed-*.txt` 第 36–47 行 |
| F13 | WSL omarchy 的 kernel 字串含 `microsoft`，本 repo 的 `.isWSL` 會為 true，`05-wsl-user-runtime-dir` 會渲染；linger 檢查後大機率 no-op | 本機 `uname -r`；腳本邏輯 |

---

## 2. 設計

### 2.1 `platform.toml` 新增兩個欄位（唯一的發行版判斷點）

```toml
distro     = "arch" | ""             # linux 且 .chezmoi.osRelease 有 id 時取 id，否則 ""
pkgManager = "apt" | "pacman" | ""   # linux: distro == "arch" → pacman，其餘 → apt；darwin/windows → ""
brewPrefix = ""                      # pkgManager == "pacman" 時改為空字串（其餘不變）
```

- 讀取順序：`$os`/`$arch`（含現有 override）→ `$distro`（`distroOverride`
  測試接縫，只有這個檔案認得；無 override 時 `hasKey .chezmoi "osRelease"` 且
  `hasKey .chezmoi.osRelease "id"` 才讀，否則 `""`）→ `$pkgManager` →
  `$brewPrefix`。
- **`brewPrefix` 非空** 是「這個平台用 brew」的唯一訊號。所有 brew 相關守衛從
  `$p.isPosix` 改為 `ne $p.brewPrefix ""`。這在 linux/darwin 上渲染結果不變。
- 在 Windows 主機上以 `osOverride=linux` 渲染時 `.chezmoi.osRelease` 是 `{}`
  （F2），`distro` 為 `""`，`pkgManager` 為 `apt`，與現況等價。
- 接縫只證明 `platform.toml` 自身的邏輯。「真正的 Arch 機器上 chezmoi 會算出
  `arch`」由 L9 在 omarchy 內用真實 chezmoi 驗證（M4）。

### 2.2 腳本

| 腳本 | 守衛（改後） | Arch 上的行為 | 其他平台 |
|---|---|---|---|
| `05-wsl-user-runtime-dir.sh` | 不變 | 不變（F13） | 不變 |
| `10-install-packages.sh` | `eq $p.os "linux"`（不變），內部依 `$p.pkgManager` 分支 | pacman 分支：缺少的 `zsh git curl base-devel` 以 `pacman -S --needed --noconfirm` 安裝，root/sudo 流程與 apt 分支相同；不做 `-Sy`/`-Syu`，資料庫過期時明確報錯並提示使用者先更新系統 | apt 分支文字**逐位元組不變** |
| `20-install-homebrew.sh` | `ne $p.brewPrefix ""` | 渲染成空 | 不變 |
| `30-install-brew-packages.sh` | `ne $p.brewPrefix ""` | 渲染成空 | 不變 |
| **新增** `30-install-pacman-packages.sh` | `eq $p.pkgManager "pacman"` | `#!/bin/sh`；`pacman -S --needed --noconfirm mise fzf git-lfs ripgrep fd lazygit tree-sitter-cli neovim`（缺的才裝） | 渲染成空 |
| `40-git-lfs.sh` | `$p.isPosix`（不變），`brew shellenv` 那一行改由 `ne $p.brewPrefix ""` 守衛 | 直接用 PATH 上的 `git-lfs` | 渲染結果不變 |
| `50-neovim.sh` | `ne $p.brewPrefix ""` | 渲染成空：不裝 mise neovim、不備份、不 clone starter（決策 D1） | 不變 |
| `default-shell.sh` | 不變 | `chsh` 到 pacman 裝的 zsh（決策 D3） | 不變 |
| Windows `.ps1` 全部 | 不變 | 渲染成空 | 不變 |

`.chezmoiignore`、`.chezmoiexternal.toml.tmpl`、`init.sh` 不變。chezmoi 本體仍由
`get.chezmoi.io` 安裝到 `~/.local/bin`。

### 2.3 zsh 檔案

- `dot_zshrc.tmpl`、`dot_zprofile.tmpl`：`brew shellenv` 區塊的守衛改為
  `ne $p.brewPrefix ""`（linux/darwin 渲染不變）。
- 新增只在 `eq $p.pkgManager "pacman"` 時輸出的區塊，位置在 PATH 設定之後、
  Oh My Zsh 之前：

```sh
# omarchy: OMARCHY_PATH 與 PATH 由它自己的 env-bootstrap 決定（POSIX sh 語法，F9）。
[ -r /etc/omarchy.conf ] && . /etc/omarchy.conf
: "${OMARCHY_PATH:=/usr/share/omarchy}"
[ -r "$OMARCHY_PATH/default/bash/env-bootstrap" ] && . "$OMARCHY_PATH/default/bash/env-bootstrap"
```

  不載入 `default/bash/rc`（bash 專用，F9）。`.zprofile` 同樣載入
  `env-bootstrap`，讓非互動登入 shell 也找得到 `omarchy-*` 與 mise shims。

### 2.4 `~/.config/git/config`

沿用「全檔接管」（F7）。omarchy 寫入的 alias 與 `defaultbranch=master` 會被本
repo 的內容取代。這是本 repo 在所有平台的既定行為（決策 D4）。

### 2.5 測試接縫與 fixture

- `tests/fixtures/os-arch.toml`：`osOverride = "linux"`、`archOverride = "amd64"`、
  `distroOverride = "arch"`、`isWSL = false`。
- `tests/lib.sh`：`ALL_OSES` 與 `POSIX_OSES` 加入 `arch`。
- 生產用 `.chezmoi.toml.tmpl` 不得出現 `distroOverride`（同 L1 對 `osOverride` 的釘法）。

---

## 3. 情境（每一條對應至少一個以它命名的自動化測試）

| # | 層 | 情境 | 輸入 | 預期 |
|---|---|---|---|---|
| S1 | L1 | arch 平台事實 | `os-arch` fixture 渲染七欄 | `linux\|amd64\|false\|true\|\|arch\|pacman`（brewPrefix 空） |
| S2 | L1 | 既有平台不變 | linux/darwin×2/windows fixture 渲染七欄 | 前五欄與現況相同；linux 的 `distro` 為 `""`、`pkgManager` 為 `apt`；darwin/windows 兩欄皆 `""` |
| S3 | L1 | 接縫退回 | `native` fixture 無 `distroOverride` | `distro` 等於 `.chezmoi.osRelease.id`（不存在時 `""`） |
| S4 | L1 | 生產 config 無接縫 | `.chezmoi.toml.tmpl` 原始碼與渲染結果 | 不含 `distroOverride` |
| S5 | L2 | arch 渲染矩陣 | 全部腳本以 `arch` 渲染 | 非空：`10`、`30-pacman`、`40-git-lfs.sh`、`default-shell`；空：`05`（isWSL false）、`20`、`30-brew`、`50-neovim.sh`、全部 `.ps1` |
| S6 | L2 | pacman 腳本只在 arch 非空 | `30-install-pacman-packages.sh.tmpl` 以六個既有 fixture 渲染 | 全部為空 |
| S7 | L2 | 10 的分支內容 | `10-install-packages` 以 `arch` 與 `linux` 渲染 | arch 含 `pacman -S --needed --noconfirm` 且套件為 `zsh git curl base-devel`、不含 `apt-get`；linux 含 `apt-get`、不含 `pacman` |
| S8 | L2 | 工具清單一致 | `30-pacman` 與 `30-brew` 的安裝行 | pacman 清單 = brew 清單 ∪ {`neovim`}；兩邊都含 `tree-sitter-cli`、不含 ` tree-sitter ` |
| S9 | L2 | arch 上沒有 brew | `.chezmoiscripts/*`、`.zshrc`、`.zprofile` 以 `arch` 渲染 | 不含 `linuxbrew`、不含 `brew shellenv` |
| S10 | L2 | 40-git-lfs 跨發行版 | `40-git-lfs.sh` 以 `arch`、`linux` 渲染 | arch 不含 `brew shellenv` 且含 `git lfs install --skip-repo`；linux 含 `brew shellenv` |
| S11 | L3 | arch managed 集合 | `cm arch managed` | 等於 `managed-posix.txt` 的內容（F12：新腳本在所有平台都列出，golden 一併更新） |
| S12 | L3 | 新腳本 LF 規則 | `git check-attr eol` | 新腳本為 `lf` |
| S13 | L4 | 新腳本語法 | arch 渲染的 `10`、`30-pacman`、`40`、`default-shell`、`.zshrc`、`.zprofile` | `sh -n` / `zsh -n` 通過（無 WSL interop 時 SKIP） |
| S14 | L6/L11 | zsh 檔案 arch golden | `.zshrc`、`.zprofile` 以 `arch` 渲染 | 與 `tests/golden/render/arch/` 逐位元組相同；含 `env-bootstrap` 區塊、不含 `default/bash/rc` |
| S15 | L10 | 既有平台回歸（檔案） | base ref `4ddc1b5` 與 HEAD 各以六個既有 fixture `apply --exclude=scripts,externals` | 六棵 destination 樹逐位元組相同 |
| S16 | L10 | 既有平台回歸（腳本） | base ref 與 HEAD 各以六個既有 fixture 渲染每支腳本、`.chezmoiignore`、`.chezmoiexternal.toml.tmpl`、`.chezmoi.toml.tmpl` | 逐位元組相同；managed 清單的差異只有 `+.chezmoiscripts/30-install-pacman-packages.sh` |
| S17 | gate | pacman 套件名可解析 | 在 WSL `omarchy` 內對 `10` 與 `30-pacman` 清單逐一 `pacman -Si` | 全部成功（對應 winget ID 解析層） |
| S18 | L11 | 探針清單同步 | `_probe.sh` 的 pacman 清單 vs 腳本渲染的清單 | 相同（同 apt 清單的既有斷言） |
| S19 | L9 | omarchy 端到端 | `tests/sandbox/omarchy.sh` 在 WSL `omarchy` 內跑 `_probe.sh`（local 模式） | 見下表 |

S19 在 omarchy 內必須逐條成立：

| 檢查 | 預期 |
|---|---|
| 真實 chezmoi 的 `.chezmoi.osRelease.id` 與 partial 輸出 | `arch` / `pkgManager=pacman` / `brewPrefix=""`（M4） |
| `pacman -Q` 逐一 | `zsh git curl base-devel mise fzf git-lfs ripgrep fd lazygit tree-sitter-cli neovim` 全部已安裝 |
| `/home/linuxbrew` | 不存在 |
| `~/.config/nvim.bak*`、`~/.local/share/nvim.bak*` | **不存在**（M2） |
| `~/.config/nvim/lua/plugins/omarchy-theme-hotreload.lua` | 仍在（omarchy 設定未被搬走） |
| `~/.config/nvim/lua/plugins/completion.lua` | 存在，內容等於 `chezmoi cat` |
| `~/.config/nvim/.chezmoi-lazyvim-starter` | 不存在（50-neovim 沒跑） |
| `nvim --headless "+lua print(1)" +q` | exit 0 |
| `~/.zshrc`、`~/.oh-my-zsh`、`~/.p10k.zsh` | 已落地 |
| `zsh -lic 'command -v mise fzf nvim tree-sitter git-lfs omarchy-version; echo $OMARCHY_PATH'` | 全部解析；`OMARCHY_PATH` 非空（M6） |
| `grep zsh /etc/shells`；`getent passwd omarchy` 第七欄 | zsh 在 `/etc/shells`；`chsh` 完成或腳本印出手動指令（無 tty 時） |
| `~/.config/git/config` | 等於 `chezmoi cat`（D4） |
| `git lfs env` | 顯示 filter 已設定 |
| 第二次 `chezmoi apply` | exit 0，無提示，無新的 `.bak` |
| `chezmoi git -- status` | exit 0（runtime dir 修正仍有效） |

---

## 4. Must NOT（違反任一條即視為失敗）

1. **不得**改變 linux/linux-arm64/darwin-arm64/darwin-amd64/windows/windows-arm64
   六個 fixture 的任何渲染結果（S15、S16）。managed 清單只准多出一支新腳本。
2. **不得**對 Windows 主機、或 WSL distro `dev`/`agent`/`ca`/`docker-desktop`
   執行 `chezmoi apply`。真實 apply 只准在 WSL `omarchy`（使用者授權，將重建）
   或用完即丟的環境。
3. **不得**在 omarchy 上搬動、備份或刪除 `~/.config/nvim`、`~/.local/share/nvim`、
   `~/.local/state/nvim`、`~/.cache/nvim`。
4. **不得**在 Arch 上安裝 Homebrew，或在任何 Arch 渲染結果中出現 `linuxbrew`。
5. **不得**執行 `pacman -Sy`、`-Syu`、`-R*`、`--overwrite`。安裝只用
   `-S --needed --noconfirm`。
6. **不得**用 `.chezmoiignore` 做平台隔離；跨平台隔離只有「渲染成空」。
7. **不得**引入未釘版本或無 checksum 的外部下載。
8. **不得**在 omarchy 內做 `chezmoi init --apply` 以外的系統變更（不手動
   `pacman -R`、不刪 omarchy 檔案），探針只能讀取與比對。
9. **不得**為了讓測試變綠去改測試；**不得**在 evidence 裡寫沒有跑過的檢查。
10. **不得**在 `main` 上提交。

---

## 5. Tier 3 失效模型

| # | 失效模式 | 實際傷害 | 對應檢查 |
|---|---|---|---|
| M1 | 守衛改寫時順手改壞既有平台 | 現有機器壞掉 | S15、S16（L10） |
| M2 | `50-neovim` 在 Arch 上仍執行，把 `omarchy-nvim` 設定搬進 `.bak` 並 clone starter | omarchy 主題整合消失，使用者找到一份「舊設定」 | S5（渲染成空）、S19 |
| M3 | brew 腳本在 Arch 上執行 | 安裝第二套工具鏈，PATH 順序決定用哪個 | S5、S9、S19 |
| M4 | `distroOverride` 接縫與真實 `.chezmoi.osRelease` 行為不一致 | 整個 arch 渲染矩陣是假綠 | S3、S19 第一列 |
| M5 | pacman 套件名錯字 | `pacman -S` 中止，apply 半途停止 | S17 |
| M6 | zsh 成為登入 shell 後失去 `OMARCHY_PATH`/`omarchy-*` | omarchy 指令在新終端機找不到 | S14、S19 |
| M7 | `.zshrc` 載入 bash 專用檔 | zsh 啟動報錯 | S13、S14、S19 |
| M8 | 本 repo 覆寫 omarchy 的 `~/.config/git/config` | omarchy 的 alias 與 `defaultbranch=master` 消失 | 已接受（D4），S19 記錄 |
| M9 | `pacman -S` 因資料庫過期失敗 | apply 中止 | 腳本印出明確指令；S19 於新建映像上不重現，列為已知限制 |
| M10 | 新腳本忘了平台守衛 | 在 Debian/macOS 上執行 pacman | S6、L2 的 `_expect` 表 |

---

## 6. Setup plan

- 安裝工具：無。使用既有的 chezmoi v2.72.0、mise 的 Python 3.13、WSL `omarchy`。
- Git 隔離：分支 `feat/archlinux-support`（已自 `4ddc1b5` 建立，含研究文件
  commit `edc0922`）。提交節奏：SPEC 核准時一次；每個行為 RED（只含測試）與
  GREEN（只含實作）各一次；REFACTOR 另提交；閘門後提交 evidence；CLOSE 由
  `spec-archive` 提交。
- 閘門新增檔案：`tests/cases/L10-regression.sh`、`tests/fixtures/os-arch.toml`、
  `tests/golden/render/arch/`、`tests/sandbox/omarchy.sh`、`tools/gate-pacman-ids.sh`
  （S17）；更新 `tests/cases/L1`、`L2`、`L3`、`L4`、`L11`、`tests/lib.sh`、
  `tests/sandbox/_probe.sh`、`tests/golden/managed-*.txt`、`tools/gate.sh`。
- 新增相依：無。
- 真實環境：S19 會在 WSL `omarchy` 內執行 `chezmoi init --apply`，變更該 distro
  的套件與 `$HOME`。使用者已表明該 distro 供驗證使用並將重建。
- 文件：`README.md` 平台表加 Arch 欄；`AGENTS.md` 的 Platform selection 與
  Install scripts 段落加入 `distro`/`pkgManager`、`30-install-pacman-packages`
  與 omarchy 的 nvim/shell 決策。`docs/research/archlinux-omarchy-support.md`
  已提交。

---

## 7. 已知限制與未證實項目

- 只驗證 WSL 變體的 omarchy（dev 模式，F10）。裸機 Hyprland 桌面與正式安裝
  （`/usr/share/omarchy`）未實測；`.zshrc` 區塊同時涵蓋兩種路徑但只有 dev
  路徑被 S19 證明。
- 純 Arch（無 omarchy）上不 clone LazyVim starter；`completion.lua` 會落在空的
  `~/.config/nvim` 內。本次不支援此情境。
- `versions.toml` 的 `neovim` pin 對 Arch 不適用（rolling release）。
- omarchy 的 migrations 是否改動本 repo 管理的檔案：未逐一讀取，未評估。
- `pacman -S` 在資料庫過期時會失敗（M9）。

---

## 8. 已決定事項（exploration round 1）

| # | 決策 | 結果 | 未採用的替代 |
|---|---|---|---|
| D1 | `50-neovim` 在 Arch 上的行為 | **A**：渲染成空，信任 `omarchy-nvim`；本 repo 的 `completion.lua` 疊加 | B：與 POSIX 相同（備份 omarchy 設定、clone starter、mise 釘版本）；C：執行期偵測 `pacman -Q omarchy-nvim`，存在才跳過 |
| D2 | Tier | **3** | 2（不派 verifier） |
| D3 | omarchy 上的 shell | **zsh 為登入 shell，`.zshrc`/`.zprofile` 載入 omarchy `env-bootstrap`** | 保留 bash |
| D4 | `~/.config/git/config` | **全檔接管，覆寫 omarchy 的版本** | Arch 上忽略此檔 |

§0、§2、§3、§5 的內容以這四項為前提，v1 與 v2 之間沒有其他變更。

---

## Approval

- 2026-09-07 — approves v2 — 「核准 SPEC v2」（AskUserQuestion 結構化提問，問題
  明示 `specs/archlinux-support/SPEC.md`、commit `2b12938`，並列出 Setup plan 授權
  範圍：分支提交節奏、新增測試檔案、在 WSL distro `omarchy` 內執行
  `chezmoi init --apply`）。

## Revisions

- 2026-09-07 — v1 草稿。依研究文件 §6 選項二撰寫；D1–D4 待決。
- 2026-09-07 — exploration round 1：使用者以結構化提問選擇 D1=A、D2=Tier 3、
  D3=zsh + env-bootstrap、D4=全檔接管（四項皆為建議選項）。§8 改為已決定事項，
  版本升為 v2。
