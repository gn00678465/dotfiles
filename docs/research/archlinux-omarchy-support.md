# Arch Linux（omarchy）支援研究

> 比照 `docs/research/windows-native-support.md` 的體例。
>
> **這份筆記有實測環境。** 標「**實測**」的每一條都是在下面這台機器上跑出來的：
>
> - WSL2 distro 名 `omarchy`，Arch Linux（`ID=arch`，rolling，`BUILD_ID=20260830.0.582275`），
>   核心 `6.18.40.1-microsoft-standard-WSL2`
> - omarchy 版本檔 `~/.local/share/omarchy/version` = `4.0.0.alpha`；
>   git checkout 在 commit `f0020448`（2026-08-14），比對 tag 排序，
>   落在 `v4.0.2`（最新穩定 tag）之後——這是 dev/main 分支的快照，不是任何一個
>   已發佈 tag 的逐位元組內容。
> - 這是使用者自述「會重建」的驗證環境，**不是**目標機器；目標是之後在裸機或另一台
>   WSL 上重灌的 omarchy v4.x。
>
> Windows 主機透過 `wsl.exe -d omarchy -- bash <script>` 存取，唯讀探測，
> 未執行 `chezmoi apply`、未修改這個 distro 的任何檔案。
> 沒有實測的地方會明講「未證實」或「查不到」。
> **這個 repo 沒有 Arch 裸機、沒有 Hyprland 桌面環境的實機**：這個 WSL 映像本身
> 沒有安裝 Hyprland（`pacman -Q hyprland` → `error: package 'hyprland' was not
> found`），所以「omarchy 在真正的 Wayland/Hyprland 桌面上」這條完全沒有實測。

---

## 0. 先講結論（Answer first）

| # | 主題 | 結論 |
|---|---|---|
| 1 | 這個 repo 唯一會在 Arch 上壞掉的腳本 | `run_onchange_before_10-install-packages.sh.tmpl`——寫死 `dpkg-query`／`apt-get`，Arch 上兩者都不存在。其餘 POSIX 腳本靠 `$p.isPosix`／`$p.brewPrefix` 走 Homebrew，Homebrew 官方支援 Arch，理論上不用改就能跑，但**不建議**照跑，見 #3。 |
| 2 | omarchy 的套件管理 | 純 pacman（`extra`/`core`/`multilib`）加一個自建 repo `[omarchy]`（`SigLevel = Optional TrustAll`）。**AUR 沒有用到**——`yay` 有裝但這次探測沒看到任何一個套件是從 AUR 來的。 |
| 3 | brew 該不該留在 Arch 上 | 不建議。這個 repo 的 brew 套件清單（mise、fzf、git-lfs、ripgrep、fd、lazygit、tree-sitter-cli）**全部**在 Arch 官方 `extra`/`core` repo 有對應套件（見 §4 表），omarchy 自己的 base package list 也已經預裝了其中大半。裝兩套工具鏈（pacman 版 + brew 版）互相打架，不如直接用 pacman。 |
| 4 | neovim / LazyVim | omarchy 用 pacman 套件 `omarchy-nvim`（2026.8.13-1，「Pre-built LazyVim configuration with cached plugins」）把 LazyVim 起始檔複製進 `/etc/skel/.config/nvim/`，新使用者建立時由 `useradd -m` 抄一份進 `~/.config/nvim`——**不是** symlink，也**不是**這個 repo 的 git-clone-into-target 模式。這個 repo 現有的 `50-neovim` 腳本一旦在 Arch 上跑，會把 omarchy 提供的 LazyVim 設定當「使用者自己的舊設定」整包搬進 `.bak`，再重新 clone 官方 starter——直接跟 omarchy 的預設值打架。 |
| 5 | omarchy 的 dotfiles 所有權模型 | 官方文件明講：`~/.config` 下的東西是「你的檔案，你的改動」；`~/.local/share/omarchy`（原文誤植為 `/usr/share/omarchy`，實測路徑是 `~/.local/share/omarchy`）是 omarchy 自己的，改了會在下次更新被覆蓋。`omarchy-reinstall-configs`／選單的 *Update > Config* 會用 `cp -af /etc/skel/. ~/` 把整個 `$HOME` 重置回套件出廠值。這代表 chezmoi 與 omarchy **都**想管理 `~/.config` 下的同一批檔案（nvim、git、starship 等），需要明確切分。 |
| 6 | 預設 shell | omarchy 不裝 zsh、不改 shell，`$SHELL` 是 `/bin/bash`，`~/.bashrc` 開頭 source `$OMARCHY_PATH/default/bash/env-bootstrap` 與 `$OMARCHY_PATH/default/bash/rc`。這個 repo 的 `default-shell` 腳本（`chsh` 到 zsh）在 Arch 上不會壞（`chsh` 屬於 `util-linux`，已預裝），但會把使用者從 omarchy 精心維護的 bash 環境切到這個 repo 的 zsh 環境，等於丟掉 omarchy 的 bash 整合。 |
| 7 | systemd / WSL runtime dir | omarchy 的 WSL 映像內建 `systemd=true`（`/etc/wsl.conf`），`systemctl --user is-system-running` 回 `running`，`XDG_RUNTIME_DIR=/run/user/1000` 已存在。`05-wsl-user-runtime-dir` 腳本邏輯（`.isWSL` 偵測 + `loginctl enable-linger`）不需要改，`.isWSL` 判斷式只看核心字串含不含 `microsoft`，跟發行版無關（見 §1.1）。 |
| 8 | chezmoi 的發行版偵測 | 官方模板變數是 `.chezmoi.osRelease`（讀 `/etc/os-release`），Arch 上 `.chezmoi.osRelease.id` = `"arch"`，且**沒有** `ID_LIKE` 這一行（實測 `cat /etc/os-release`，§2.1）。這個 repo 現有的 `platform.toml` 只用 `.chezmoi.os`（`linux`/`darwin`/`windows`），完全不看 `osRelease`，所以 Debian 和 Arch 目前在 `$p` 裡是同一個值——這正是要新增的判斷維度。 |
| 9 | 套件清單缺口 | 沒有。這個 repo 目前用到的每一個外部工具，在 Arch 官方 repo 都查得到對應套件（§4），不需要 AUR，也不需要另外編譯。 |
| 10 | 建議設計方向 | 在 `platform.toml` 加 `$p.pkgManager`（`apt`/`pacman`/`""`），由 `.chezmoi.osRelease.id` 決定；`10-install-packages` 依 `pkgManager` 分支；**新增** `30-install-pacman-packages` 取代 Arch 上的 `20-install-homebrew`＋`30-install-brew-packages`（brew 腳本改成只在 `pkgManager == "apt"` 時跑）；`50-neovim` 在 Arch 上整支跳過或改成偵測 `omarchy-nvim` 是否已安裝。詳見 §5。 |

---

## 1. 現有 repo 對平台的假設（Part A）

### 1.1 `.chezmoitemplates/platform.toml`——唯一的 OS 判斷來源

`.chezmoitemplates/platform.toml:6` 的呼叫端合約：`{{- $p := includeTemplate
"platform.toml" . | fromToml -}}`，之後只讀 `$p.os`／`$p.arch`／`$p.isWindows`／
`$p.isPosix`／`$p.brewPrefix`（`platform.toml:6`）。

- `os`／`arch` 直接來自 `.chezmoi.os`／`.chezmoi.arch`（`platform.toml:17-18`），
  可被測試專用的 `osOverride`／`archOverride` 蓋掉（`platform.toml:21-22`，只有
  這個檔案認得這兩個 key，正式 config 沒有）。
- `isWindows`／`isPosix`（`platform.toml:33-34`）是布林值，`brewPrefix`
  （`platform.toml:25-29`）依 `os`／`arch` 算出 linuxbrew 或 macOS 的兩種路徑，
  Windows 上是空字串。
- **這裡完全沒有讀 `.chezmoi.osRelease`**：Linux 底下不管是 Debian 還是 Arch，
  `$p.os` 都是 `"linux"`，`$p` 裡的其他欄位也完全一樣。要分辨 Arch，必須在這個
  檔案裡新增一個維度（見 §5）。

`.chezmoi.toml.tmpl:2-8` 另外算出 `isWSL`（讀 `.chezmoi.kernel.osrelease`，
`contains "microsoft"`），寫進 `[data]` 供各腳本用 `.isWSL` 存取——這一段跟發行版
無關，Arch WSL（`uname -a` 含 `microsoft-standard-WSL2`，見 §2.1）一樣會判成
`true`。

`init.sh`／`init.ps1` 只負責取得 chezmoi 本身並跑 `chezmoi init --apply`，兩支都
沒有發行版分支，理論上在 Arch 上原樣可用（`init.sh` 用 `curl` 抓
`get.chezmoi.io` 的安裝腳本，跟發行版無關）。

### 1.2 `.chezmoiscripts/*.tmpl`——每一支腳本的平台守門

| 腳本 | 守門條件 | Arch 上會怎樣 |
|---|---|---|
| `run_onchange_before_05-wsl-user-runtime-dir.sh.tmpl:2` | `and (eq $p.os "linux") .isWSL` | 邏輯本身只依賴 systemd／loginctl，跟發行版無關（`platform.toml` 沒有分支）；在 omarchy WSL 上 `/run/systemd/system` 存在、`loginctl` 可用，這支腳本原樣可跑，且大機率立刻 `exit 0`（因為 lingering 大概率已開，見 §2.1）。 |
| `run_onchange_before_10-install-packages.sh.tmpl:2,11,21,26,29,31` | `eq $p.os "linux"` | **會壞**。第 11 行 `dpkg-query -W -f='${Status}' "$pkg"`——Arch 沒有 `dpkg-query`；第 21/29/31 行 `apt-get`——Arch 沒有 `apt-get`。整支腳本在 Arch 上要嘛因為找不到指令直接非零結束，要嘛（如果殼把找不到指令當成「未安裝」處理）落到第 21 行 `apt-get: command not found`，兩種情況都會讓 `run_onchange_before_10-install-packages` 失敗，整個 apply 在裝任何檔案之前中止。 |
| `run_once_before_20-install-homebrew.sh.tmpl:2` | `$p.isPosix` | 邏輯本身跟發行版無關，只要 `10-install-packages` 先把 `build-essential`／`procps`／`file` 之類的建置需求裝好，理論上能在 Arch 上跑（Homebrew 官方支援 Arch，見 §4）。**但**這條路徑跟 omarchy 自己的套件管理重複（見 §0 #3）。 |
| `run_onchange_before_30-install-brew-packages.sh.tmpl:2` | `$p.isPosix` | 同上，理論上可跑，但重複。 |
| `run_onchange_before_30-install-winget-packages.ps1.tmpl` | `$p.isWindows` | 跟 Arch 無關（渲染成空）。 |
| `run_onchange_before_35-install-ps-modules.ps1.tmpl` | `$p.isWindows` | 跟 Arch 無關。 |
| `run_after_default-shell.sh.tmpl:2` | `eq $p.os "linux"` | 邏輯讀 `getent passwd`／`/etc/shells`／`chsh`，這些在 Arch 上都存在（`chsh` 屬於 `util-linux`，實測 `pacman -Qo /usr/bin/chsh` → `util-linux 2.42.2-1`）。前提是 zsh 已經裝好且寫進 `/etc/shells`——目前只有 `10-install-packages`（apt 專用）會裝 zsh，Arch 上沒有對應步驟，所以這支腳本現狀會在「找不到 zsh」時直接 `exit 0`（第 4-6 行的空字串守門），不會報錯，但也不會做任何事。 |
| `run_before_50-neovim.sh.tmpl:3` | `$p.isPosix` | 邏輯可執行（靠 `$p.brewPrefix/bin/mise`），但語意上跟 omarchy 自帶的 `omarchy-nvim` 衝突（見 §0 #4、§3）。 |
| `run_onchange_after_40-git-lfs.sh.tmpl:2` | `$p.isPosix` | 靠 brew 裝的 `git-lfs`；若 Arch 改用 pacman 裝 `git-lfs`，這支腳本目前的 `eval "$(brewPrefix/bin/brew shellenv)"` 前置動作會失敗（找不到 brew）。 |

### 1.3 其他檔案

- `.chezmoiignore` 只用 `$p.isWindows` 分兩支（Windows 專屬 vs POSIX 專屬檔案），
  沒有 Debian／Arch 之分，Arch 落在 POSIX 那一支，不需要改。
- `.chezmoitemplates/versions.toml` 定義 neovim 版本 pin（`0.12.5`）、LazyVim
  starter URL、marker 檔名、PSFzf 版本，跟發行版無關。omarchy 自己也把
  neovim 釘在 `0.12.5-1`（`pacman -Si neovim`，見 §2.1）——巧合但值得記一筆：
  如果之後改用 pacman 的 neovim 而不是 mise 的，版本剛好對得上，但這是
  rolling release，pacman 的 neovim 版本會隨官方 repo 更新，不會固定在
  `0.12.5`。
- `dot_zshrc.tmpl`／`dot_zprofile.tmpl` 沒有 grep 到 `apt`/`dpkg`/`debian`/
  `ubuntu`/`linuxbrew` 字樣（全域 grep 結果只命中 `AGENTS.md`、測試工具、
  `.chezmoiscripts` 裡列出的那幾支），對 Arch 沒有已知的壞點，但兩者都假設
  zsh 是互動 shell，跟 omarchy 預設的 bash 環境不會自動整合（見 §0 #6）。

### 1.4 測試對 Arch 的涵蓋度

`tests/cases/L1-platform.sh` 目前只斷言 `linux`/`darwin-arm64`/`darwin-amd64`/
`windows` 四種 `osOverride` 值算出的 `$p` 欄位，**沒有**、也**不能**驗證 Arch：
`osOverride` 只換掉 `.chezmoi.os`，Arch 與 Debian在 `.chezmoi.os` 上是同一個值
`"linux"`。要新增 Arch 的渲染矩陣，需要一個新的測試接縫（例如
`osReleaseIdOverride`，比照 `osOverride`／`archOverride` 的寫法），因為
`.chezmoi.osRelease` 不是 chezmoi config 檔案裡可以直接覆寫的欄位——它是
chezmoi 執行當下真的去讀執行機器的 `/etc/os-release` 算出來的（見 §4.3）。

`tests/cases/L2-script-render-matrix.sh` 的 `_expect()` 函式（`L2:15-27`）用
`$ALL_OSES`（`linux`/`linux-arm64`/`darwin-arm64`/`darwin-amd64`/`windows`/
`windows-arm64`）逐一渲染每支腳本，同樣只到 `.chezmoi.os` 層級，無法區分
Arch。新增 `10-install-packages` 的 pacman 分支後，這張表要跟著改，且需要一個
能把某個 fixture 渲染成「Arch」的辦法。

`tests/cases/L6-file-golden.sh` 用 `tests/fixtures/l6/<case>/os-<os>.toml`
真的跑 `chezmoi apply --exclude=scripts,externals`，驗證 codex／claude 設定檔
逐位元組相同；這一層只測 `modify_`／設定檔渲染，不牽涉套件安裝腳本，Arch 不會
在這裡引入新差異（前提是 `$p.pkgManager` 之類的新欄位不影響這兩份設定檔的
渲染邏輯）。

`tests/sandbox/README.md` 說明 L9：Windows 用 Windows Sandbox，Linux 用
`docker.sh`（`debian:12` 容器）或 `wsl.sh`（全新 `chezmoi-probe` WSL distro）。
兩者都是 Debian 系（docker.sh 明講 `debian:12`；`wsl.sh` 用什麼 distro 沒有在
README 裡明講基底映像，但探針邏輯是共用的 `_probe.sh`，跟 `docker.sh` 問同一組
問題）。**目前沒有任何一層自動化會真的在 Arch 上跑一次 `chezmoi apply`**——
這次的探測是唯讀的手動 `wsl.exe -d omarchy` 呼叫，不是任何一層自動化測試。

### 1.5 evidence-first 工作流程摘要

`C:/Users/gn006/.agents/workflows/evidence-first.md` 定義的 SPEC 必要欄位：
**Tier**（1 輕微／2 一般／3 高風險，Tier 3 要附失敗模型）、**Scenarios**（每條對應
至少一個自動化測試）、**Must NOT**（負向約束與不變式）、**Setup plan**（工具、git
隔離機制、`spec-archive` 會動到的檔案路徑、每個新依賴的一句話理由）、**Approval**
（逐字引用核准內容、日期、版本）、**Revisions**（只增不刪的修訂記錄）。SPEC 固定
放在 `specs/<scope>/SPEC.md`，evidence 報告放在 `.scratch/<scope>/evidence.md`。
這份研究筆記本身不是 SPEC，不觸發這個流程；但如果之後真的動手改
`.chezmoiscripts/`，該改動屬於「觸及安裝腳本、影響所有使用者」的變更，值得走一次
完整的 evidence-first 流程並宣告 Tier（建議 Tier 2：非高風險類別，但影響面廣，
需要可驗證的測試矩陣）。

---

## 2. omarchy WSL 實測（Part B）

### 2.1 基本資訊

```
$ cat /etc/os-release
NAME="Arch Linux"
ID=arch
BUILD_ID=rolling
VERSION_ID=20260830.0.582275
```

（沒有 `ID_LIKE` 這一行——Arch 是 base distro，`.chezmoi.osRelease.idLike` 在這台
機器上會是空值/不存在。）

> **更正（2026-09-08，SPEC arch-family-support F1）**：上面只對 WSL 版 omarchy dev
> 映像成立。ISO 正式安裝的 omarchy 4.0.2 把 `/etc/os-release` 換成
> `/usr/share/omarchy/etc-overrides/os-release`，內容是 `ID=omarchy`、`ID_LIKE=arch`、
> `VERSION_ID="4.0.2"`；`/usr/lib/os-release` 仍是 `ID=arch`。chezmoi 讀到
> `.chezmoi.osRelease.id = "omarchy"`、`.idLike = "arch"`。只比對 `id` 會把它當成
> Debian 走 apt + Homebrew（實測，第一支腳本就停）。`platform.toml` 因此改成
> 「`id` 是 `arch`，或 `idLike` 逐字含 `arch`」。

```
$ uname -a
Linux MADAO 6.18.40.1-microsoft-standard-WSL2 #1 SMP PREEMPT_DYNAMIC ... x86_64 GNU/Linux
$ id
uid=1000(omarchy) gid=1000(omarchy) groups=1000(omarchy),998(wheel)
$ echo $SHELL
/bin/bash
$ getent passwd omarchy
omarchy:x:1000:1000::/home/omarchy:/bin/bash
```

工具存在性（`which`／`command -v`，各自獨立指令跑出來的，見方法論附註）：

| 工具 | 存在 | 路徑 |
|---|---|---|
| pacman | 有 | `/usr/sbin/pacman` |
| yay | 有 | `/usr/sbin/yay` |
| paru | **沒有** | — |
| sudo | 有 | `/usr/sbin/sudo` |
| git | 有 | `/usr/sbin/git` |
| zsh | **沒有** | — |
| curl | 有 | `/usr/sbin/curl` |
| brew | **沒有** | — |
| mise | 有 | `/usr/sbin/mise` |
| nvim | 有 | `/usr/sbin/nvim` |
| fish | **沒有** | — |
| bash | 有 | `/usr/sbin/bash` |
| chsh | 有 | `/usr/sbin/chsh`（實體檔在 `/usr/bin/chsh`，屬於套件 `util-linux 2.42.2-1`） |
| loginctl | 有（`systemd 261.2-1`） | |
| systemctl | 有 | |

```
$ pacman -Q | wc -l
290
$ pacman -Qe | wc -l
52
```

`pacman -Qe`（明確安裝的套件）完整清單見附錄 A。這是 WSL 映像的清單，**不是**
`omarchy-base.packages`（見 §2.3）——兩者差很多：WSL 映像沒有 Hyprland、沒有
桌面環境相關套件（`pacman -Q hyprland` → 找不到），是精簡過的 CLI-only 變體。

```
$ pacman -Qg | 去重
nerd-fonts
tree-sitter-grammars
```

（`pacman -Qg` 只列出這台機器上實際裝到的兩個群組成員的來源群組名，不是完整的
群組清單。）

```
$ echo $XDG_RUNTIME_DIR; ls -ld /run/user/*
/run/user/1000
drwx------ 6 omarchy omarchy 180 ... /run/user/1000
$ systemctl --user is-system-running
running
$ cat /etc/wsl.conf
[boot]
systemd=true
[user]
default=omarchy
```

`XDG_RUNTIME_DIR` 已存在、`systemctl --user` 是 `running`——這台機器上
`05-wsl-user-runtime-dir` 腳本會在檢查 `loginctl show-user omarchy
--property=Linger` 之後直接 `exit 0`（lingering 大機率已經開，因為目錄已存在），
不代表這支腳本邏輯不需要跑，只代表它在這台機器上是 no-op。

### 2.2 nvim / LazyVim

```
$ ls ~/.config/nvim
init.lua  lazy-lock.json  lazyvim.json  lua/  plugin/  README.md  ...
$ readlink -f ~/.config/nvim
/home/omarchy/.config/nvim        ← 不是 symlink，是真的目錄
$ nvim --version | head -3
NVIM v0.12.5
$ pacman -Qo ~/.config/nvim/init.lua
error: No package owns /home/omarchy/.config/nvim/init.lua   ← $HOME 底下的檔案不歸 pacman 管
$ pacman -Ql omarchy-nvim | head
omarchy-nvim /etc/skel/.config/nvim/
omarchy-nvim /etc/skel/.config/nvim/init.lua
...
$ pacman -Si omarchy-nvim
Name            : omarchy-nvim
Version         : 2026.8.13-1
Description     : Pre-built LazyVim configuration with cached plugins
Depends On      : neovim>=0.9.0  git
Conflicts With  : omarchy-lazyvim
```

結論：`omarchy-nvim` 套件把 LazyVim starter 灌進 `/etc/skel/.config/nvim/`，
`useradd -m` 建立使用者時複製一份到 `$HOME`；之後這份檔案就是**一般檔案**，
不再受 pacman 管。`omarchy-reinstall-configs`（見下）用 `cp -af /etc/skel/. ~/`
重置，會覆蓋使用者對 `~/.config/nvim` 的任何修改。`mise ls` 沒有輸出（`mise`
本身是 pacman 套件，`2026.8.10-1`），代表這台機器完全沒有用 mise 管理任何 runtime
（包含 neovim）——neovim 是 pacman 套件裝的，不是 mise 裝的。

### 2.3 omarchy 倉庫 checkout 與套件清單

```
$ ls ~/.local/share/omarchy
AGENTS.md  CLAUDE.md  agents/  applications/  bin/  config/  default/  docs/
etc/  install/  manual/  migrations/  README.md  shell/  test/  themes/  version
$ cat ~/.local/share/omarchy/version
4.0.0.alpha
$ git -C ~/.local/share/omarchy log -1 --oneline
f0020448 More manual tweaks
$ git -C ~/.local/share/omarchy tag --sort=-creatordate | head -5
v4.0.2
v4.0.1
v4.0.0
v4.0.0-beta3
v3.8.4
```

`~/.local/share/omarchy/install/omarchy-base.packages`（節錄，全文見 §3）
含 `mise`、`fzf`、`ripgrep`(未直接列出但 `fd`/`bat`/`eza`/`zoxide`/`starship`/
`lazygit`/`tree-sitter-cli`/`neovim`/`omarchy-nvim` 都在清單裡）——**這個 repo
想用 brew 裝的每一個工具，omarchy 出廠就已經幫你裝好了**。清單裡沒有 `zsh`、
沒有 `git-lfs`、沒有 `chezmoi`（這三個不是 omarchy 出廠預裝，但都在 Arch 官方
`extra` repo，見 §4）。

`~/.local/share/omarchy/install/` 目錄結構：`config/`、`hardware/`、
`helpers/`、`login/`、`post-install/`、`provisioning/`、`user/`，加上
`omarchy-base.packages`、`omarchy-other.packages` 兩份套件清單檔。

`~/.local/share/omarchy/bin/` 裡跟套件管理相關的命名慣例（`ls | grep pkg`）：
`omarchy-pkg-add`、`omarchy-pkg-install`、`omarchy-pkg-remove`、
`omarchy-pkg-present`、`omarchy-pkg-missing`、`omarchy-pkg-drop`、
`omarchy-pkg-aur-add`、`omarchy-pkg-aur-install`、`omarchy-pkg-aur-accessible`、
`omarchy-reinstall-pkgs`、`omarchy-update-aur-pkgs`、`omarchy-update-orphan-pkgs`、
`omarchy-update-system-pkgs`——`omarchy-pkg-*` 系列包 pacman，`*-aur-*` 系列包
`yay`。沒有找到 `omarchy-version` 這個指令（`which omarchy-version` 找不到）；
版本資訊改用讀 `~/.local/share/omarchy/version` 這份純文字檔取得。

### 2.4 shell 環境

```
$ cat ~/.bashrc
[[ -r /home/omarchy/.local/share/omarchy/default/bash/env-bootstrap ]] && source ...
[[ $- != *i* ]] && return
source "$OMARCHY_PATH/default/bash/rc"
# Add your own exports, aliases, and functions here.
$ cat ~/.bash_profile
[[ -f ~/.bashrc ]] && . ~/.bashrc
$ ls ~/.zshrc
ls: cannot access '/home/omarchy/.zshrc': No such file or directory
```

omarchy 的 bash 整合分兩層：非互動 shell 也會跑的 `env-bootstrap`
（設 `OMARCHY_PATH`、`PATH`），互動 shell 才跑的 `default/bash/rc`（別名、函式）。
使用者的自訂區塊明講「自己的東西寫在這裡，不要動上面那兩行」——這跟這個 repo
`dot_zshrc.tmpl` 的分區風格（chezmoi 管的區塊 vs 使用者自訂區塊）概念一致，只是
omarchy 選 bash，這個 repo 選 zsh。

### 2.5 pacman repo 設定

```
$ grep -v '^#' /etc/pacman.conf
[core]
Include = /etc/pacman.d/mirrorlist
[extra]
Include = /etc/pacman.d/mirrorlist
[multilib]
Include = /etc/pacman.d/mirrorlist
[omarchy]
SigLevel = Optional TrustAll
Server = https://pkgs.omarchy.org/stable/$arch
```

四個 repo：官方三個（`core`／`extra`／`multilib`）加 omarchy 自己的
`pkgs.omarchy.org`（`omarchy-nvim`、`omarchy-keyring` 這些 `omarchy-*` 套件
就是從這裡來的）。`SigLevel = Optional TrustAll` 代表這個第三方 repo **不驗證
簽章**——理論資安考量，但這是 omarchy 官方自建的 repo，不是使用者自行加的，
記錄事實即可，不在這份研究的判斷範圍內。

### 2.6 pacman hooks

`/etc/pacman.d/hooks` 不存在（`ls` 報錯），實際 hook 放在
`/usr/share/libalpm/hooks/`：glibc、systemd（`sysusers`、`tmpfiles`、
`binfmt`、`hwdb`、`daemon-reload`）、fontconfig、`update-ca-trust`、
`depmod` 等標準 Arch hook，跟 omarchy 或這個 repo 無關，記錄供參考。

### 2.7 這個 WSL 映像跟裸機的已知差異

- 沒有 Hyprland（`pacman -Q hyprland` 找不到），沒有 zsh（`pacman -Q zsh`
  找不到）——`omarchy-base.packages`（ISO 用的清單，§3）裡兩者都在，
  代表這個 WSL 映像**不是**直接拿 ISO 清單裝出來的，是另外裁減過的 WSL 專用
  變體。這代表「WSL 上的 omarchy」跟「裸機上的 omarchy」在套件層級不完全一樣，
  這份研究的 §2 各項結論僅代表 WSL 變體，裸機（真正跑 Hyprland）的行為
  **未證實**。
- `pacman -Qe`（52 個明確安裝的套件，附錄 A）比 `omarchy-base.packages`
  （超過 150 行，§3）少非常多，且清單內容不完全交集（例如 `dust`、
  `lazydocker`、`github-cli`、`rust`、`clang`、`llvm` 這些在 WSL 映像的
  `pacman -Qe` 裡，但不在 `omarchy-base.packages`——WSL 映像顯然疊加了額外的
  開發工具鏈）。

---

## 3. `omarchy-base.packages` 全文（Part B/C，來自 WSL checkout 與 GitHub 對照）

```
# Omarchy core package list pacstrapped by the ISO.
# The ISO builder also reads this file when constructing the offline mirror.

aether, alsa-utils, asdcontrol, avahi, bash-completion, bat, bluez,
bluez-tools, bluez-utils, bolt, brightnessctl, btop, chromium, clang,
cliamp, cups, cups-browsed, cups-filters, cups-pdf, ddcutil, docker,
docker-buildx, docker-compose, dosfstools, dotnet-runtime, dua-cli,
evince, exfatprogs, expac, eza, fakeroot, fastfetch, fcitx5, fcitx5-gtk,
fcitx5-qt, fd, ffmpegthumbnailer, fontconfig, foot, fzf, git,
gnome-keyring, gnome-themes-extra, grim, gpu-screen-recorder, gum,
gvfs-mtp, gvfs-nfs, gvfs-smb, herdr, hyprland, hyprland-guiutils,
hyprland-preview-share-picker, hyprpicker, hyprsunset, imagemagick, imv,
inetutils, inotify-tools, inxi, networkmanager, jq, kdenlive,
kernel-modules-hook, lazydocker, lazygit, less, libsecret, libvips,
libyaml, libreoffice-fresh, llvm, localsend, lua51, luarocks, man-db,
mariadb-libs, mise, moonlight-qt, mpv, mpv-mpris, nautilus,
nautilus-python, gnome-disk-utility, noto-fonts, noto-fonts-cjk,
noto-fonts-emoji, nss-mdns, nvim, obs-studio, obsidian, omacalc, omacut,
omawrite, omarchy-nvim, pacman-contrib, pamixer, pinta, plocate,
plymouth, postgresql-libs, power-profiles-daemon, python-gobject,
python-poetry-core, ttfx, qemu-user-static-binfmt, qrencode,
quickshell-git, ripgrep, ruby, tensaku, sddm, slurp, socat, starship,
sushi, system-config-printer, tesseract, tesseract-data-eng, tldr,
tree-sitter-cli, tmux, tobi-try, ttf-ia-writer,
ttf-jetbrains-mono-nerd-basic, tzupdate, udiskie, ufw, ufw-docker,
unzip, usage, uwsm, whois, wireless-regdb, wireplumber, wl-clipboard,
wtype, woff2-font-awesome, xdg-desktop-portal-gtk,
xdg-desktop-portal-hyprland, xdg-terminal-exec, xournalpp,
yaru-icon-theme, yay, yt-dlp, zbar, zoxide
```

這是 ISO 安裝器用的完整清單（`install/omarchy-base.packages` 開頭註解：
「Omarchy core package list pacstrapped by the ISO. The ISO builder also
reads this file when constructing the offline mirror.」），涵蓋桌面環境
（Hyprland 全家桶）、辦公／多媒體（LibreOffice、OBS、Chromium）、開發工具
（clang、llvm、docker、mise）。這個 repo 關心的子集合都在裡面：`mise`、
`fzf`、`fd`、`ripgrep`（間接由 `pacman -Qe` 證實有裝，`omarchy-base.packages`
清單裡雖沒直接看到 `ripgrep` 字樣但 `pacman -Si ripgrep` 存在於 `extra`）、
`lazygit`、`tree-sitter-cli`、`nvim`／`omarchy-nvim`、`eza`、`zoxide`、
`starship`、`bat`。

---

## 4. 套件對照與可用性（Part C）

### 4.1 brew → pacman 對照表

全部用 WSL omarchy 上的 `pacman -Si <pkg>` 實測（`MSYS_NO_PATHCONV=1
MSYS2_ARG_CONV_EXCL="*" wsl.exe -d omarchy -- bash <script>` 執行，避開
Git Bash 對 wsl.exe 參數的路徑改寫問題，見方法論附註）：

| 這個 repo 的 brew 套件（`30-install-brew-packages.sh.tmpl`） | pacman 套件名 | 來源 repo | 版本（實測時點） | omarchy 出廠已裝？ |
|---|---|---|---|---|
| `mise` | `mise` | extra | 2026.8.10-1 | 是（`omarchy-base.packages`，且 WSL `pacman -Qe` 有） |
| `fzf` | `fzf` | extra | 0.74.3-1 | 是 |
| `git-lfs` | `git-lfs` | extra | 3.7.1-2 | **否**（不在 `omarchy-base.packages`，WSL `pacman -Qe` 也沒有） |
| `ripgrep` | `ripgrep` | extra | 15.2.0-1 | 是（WSL `pacman -Qe` 有） |
| `fd` | `fd` | extra | 10.4.2-2 | 是 |
| `lazygit` | `lazygit` | extra | 0.64.1-1 | 是 |
| `tree-sitter-cli` | `tree-sitter-cli` | extra | 0.26.9-1 | 是 |

`10-install-packages.sh.tmpl` 的 apt 清單（`zsh`、`git`、`curl`、
`build-essential`、`procps`、`file`）對照：

| apt 套件 | pacman 對應 | 來源 repo | 備註 |
|---|---|---|---|
| `zsh` | `zsh` | extra，5.9.2-1（實測） | omarchy 出廠不裝 |
| `git` | `git` | core，2.55.0-1（`pacman -Qe` 實測版本） | omarchy 出廠已裝 |
| `curl` | `curl` | core，8.21.0-1（實測） | omarchy 出廠已裝（basestrap 依賴） |
| `build-essential` | `base-devel`（套件群組） | core，1-2（實測） | omarchy 出廠已裝 |
| `procps` | `procps-ng` | core，4.0.7-1（實測） | Arch 用 `procps-ng` 不是 `procps` |
| `file` | `file` | 未單獨查證（Arch 官方套件名同為 `file`，屬 `core`，`base` 群組依賴鏈通常已含），**未證實** | — |

其他相關套件：

| 用途 | pacman 套件 | 來源 repo | 版本（實測） |
|---|---|---|---|
| chezmoi 本體 | `chezmoi` | extra | 2.72.0-1（與這個 repo `AGENTS.md` 提到的實測版本相同） |
| neovim | `neovim` | extra | 0.12.5-1（與這個 repo `versions.toml` 的 pin `0.12.5` 相同，但 Arch 是 rolling release，之後會隨官方 repo 往前推） |
| chsh 來源 | `util-linux` | core（`base` 群組依賴） | 2.42.2-1（實測，`pacman -Qo /usr/bin/chsh`） |
| loginctl 來源 | `systemd` | core（`base` 群組依賴） | 261.2-1（實測） |
| openssh | `openssh` | core | 10.5p1-1（實測，供對照） |

**結論：這個 repo 目前用到的每一個外部工具，在 Arch 官方 `core`/`extra` repo
都有對應套件，不需要 AUR。**

### 4.2 Homebrew on Linux 官方立場

`docs.brew.sh/Homebrew-on-Linux` 明列 Arch Linux 的安裝指令：
`sudo pacman -S base-devel procps-ng curl file git`，與 Debian/Ubuntu、
Fedora、CentOS Stream/RHEL 並列——**Homebrew 官方文件把 Arch Linux 列為受支援
的安裝路徑之一**，不是只能靠 AUR。這代表如果要保留 brew 路線，`10-install-packages`
在 Arch 分支要裝 `base-devel procps-ng curl file git`（`procps-ng` 而非
`procps`）而不是照搬 apt 清單。但如 §0 #3，這條路線會跟 omarchy 已經用 pacman
裝好的同一批工具重複，不建議採用。

### 4.3 chezmoi 的發行版偵測能力

chezmoi 官方模板變數 `.chezmoi.osRelease`：「The information from
`/etc/os-release`, Linux only」，欄位對應 `/etc/os-release` 的 key（小寫化），
所以 Arch 上 `.chezmoi.osRelease.id` = `"arch"`，`.chezmoi.osRelease.idLike`
在這台機器上不存在（因為 `/etc/os-release` 沒有 `ID_LIKE` 這一行，實測，見
§2.1）。這跟 Debian 的 `id=debian`／`idLike` 通常也沒有（Debian 本身也不寫
`ID_LIKE`，只有衍生版如 Ubuntu 才會寫 `ID_LIKE=debian`）形成對比，用
`.chezmoi.osRelease.id` 直接比對字串（`"arch"`／`"debian"`）比用 `idLike`
可靠。**重要**：`.chezmoi.osRelease` 沒有像 `sourceDir` 那樣的 config 覆寫入口
——它是 chezmoi 執行時真的去讀執行機器的 `/etc/os-release`，所以要在非 Linux
主機（這個 repo 唯一的渲染環境是 Windows 主機 + WSL Debian）上測試「假裝自己是
Arch」的渲染結果，不能靠 chezmoi 原生機制，必須靠 `platform.toml` 自己加一層
override（比照 `osOverride`／`archOverride` 的既有模式，見 §6）。

### 4.4 mise 與 neovim 版本管理

`mise` 在 Arch `extra` repo 有官方套件（實測 `2026.8.10-1`），omarchy 也用它
（`~/.local/share/omarchy/install/user/mise.sh` 裝的是 AI CLI 工具，如
`codex`、`claude`、`gh`，不是 neovim；`mise ls` 在這台機器上沒有輸出，代表沒有
任何語言 runtime 或 neovim 是透過 mise 裝的）。neovim 在這台機器上是
`pacman -S neovim` 裝的（`0.12.5-1`），不是 mise。這代表 Arch 上有兩條可選路徑：
(a) 沿用這個 repo 現有的「mise 裝 neovim，pin 版本」模式（跟 POSIX/Windows 一致，
但需要先用 pacman 裝出 mise 本體），(b) 直接用 pacman 的 `neovim`（跟 omarchy
自己的選擇一致，但版本釘不住——rolling release 沒有版本 pin 機制，`versions.toml`
裡的 `neovim = "0.12.5"` 這個 pin 概念在純 pacman 路�	徑下失去意義）。

---

## 5. omarchy 的 dotfiles 所有權模型與更新／遷移機制

`omarchy.org/manual/dotfiles/` 原文（WebFetch 摘要，文字經確認與變數探測結果
一致，但這份筆記轉述時把原文誤植的 `/usr/share/omarchy` 修正為實測到的
`~/.local/share/omarchy`，兩者哪個才是文件正確用字**未證實**，只確定實際路徑
是 `~/.local/share/omarchy`）：

> 「Those are considered your files for your changes. The files that live in
> `~/.local/share/omarchy` belong to Omarchy itself.」
>
> 「If you need to change anything in `~/.local/share/omarchy`, you should be
> overwriting the value in `~/.config` instead.」
>
> 使用者可編輯的範例：`~/.config/hypr/`、`~/.config/omarchy/`、
> `~/.config/foot/`、`~/.bashrc`、`~/.XCompose`。
>
> 重置方式：選單 *Update > Config* 或指令 `omarchy reinstall configs`。

實測到的重置腳本 `~/.local/share/omarchy/bin/omarchy-reinstall-configs`
（全文見 §2，摘要）：

```sh
cp -af /etc/skel/. ~/
omarchy-refresh-limine
omarchy-refresh-plymouth
if omarchy-cmd-present omarchy-nvim-refresh; then
  omarchy-nvim-refresh
elif omarchy-cmd-present omarchy-nvim-setup; then
  omarchy-nvim-setup --force
fi
```

`cp -af /etc/skel/. ~/` 一次覆蓋 `.bashrc`、`.config/**`、
`~/.local/share/applications`、nautilus 擴充、品牌素材、hypr 開關、遷移標記——
**這是全面覆蓋，不是合併**，任何被 chezmoi 管理但也落在 `/etc/skel` 涵蓋範圍內
的檔案，只要使用者跑一次 `omarchy reinstall configs`，就會被 omarchy 的出廠值
蓋掉，不會等 chezmoi 下次 apply 才發現（chezmoi 的變更偵測是雜湊比對，被覆蓋後
下次 `chezmoi apply` 會偵測到「跟 chezmoi state 不符」而改回來，但兩邊都不知道
對方的存在，等於互相打架）。

Update 機制（WebSearch 摘要，`learn.omacom.io` 的 Updates 頁）：「Omarchy 和
套件透過選單 *Update > Omarchy* 保持最新——拉最新的 omarchy 程式碼與設定、跑
待執行的 migrations、更新所有系統套件。」migrations 目錄（`~/.local/share/
omarchy/migrations`）裡是以 Unix timestamp 命名的 shell script（實測列出
`1786...sh` 這種檔名，§2），代表 omarchy 有自己的一次性遷移機制，會在更新時
針對使用者環境做增量調整——這條機制對 chezmoi 管理的檔案是否有感知、會不會
主動改動 chezmoi 管的檔案，**未證實**（沒有逐一讀過每一支 migration script）。

---

## 6. 設計選項與建議（Part D）

### 選項一：Arch 上完全比照 POSIX（brew 路線），只修 `10-install-packages`

在 `10-install-packages` 加 `pacman -S --needed --noconfirm base-devel
procps-ng curl file git zsh`（見 §4.2 的官方 Homebrew Arch 需求），其餘腳本
（`20-install-homebrew`、`30-install-brew-packages`、`50-neovim`）完全不動，
靠 `$p.isPosix` 自動涵蓋 Arch。

- 優點：改動最小，只動一支腳本；跟現有 POSIX 邏輯（brew 全平台一致）保持
  一致，`brewPrefix` 機制不用動。
  - 缺點：跟 omarchy 已經用 pacman 裝好的同一批工具（mise、fzf、
    ripgrep、fd、lazygit、tree-sitter-cli，見 §4.1）重複安裝，浪費磁碟
    （linuxbrew 是完整第二套工具鏈）也製造「兩個版本的同一個工具，PATH
    優先順序決定用哪個」的混淆。`50-neovim` 腳本會把 omarchy 出廠的
    `omarchy-nvim` LazyVim 設定當「使用者舊設定」搬進 `.bak`，跟官方
    LazyVim starter 重新 clone 一份——功能上兩者殊途同歸（都是 LazyVim），
    但版本、外掛鎖定檔（`lazy-lock.json`）會不一樣，且使用者會在
    `~/.config/nvim.bak` 找到一份自己從沒動過的「舊設定」，造成困惑。

### 選項二：Arch 走純 pacman 路線（建議）

新增 `$p.pkgManager`（`platform.toml` 依 `.chezmoi.osRelease.id` 算：
`apt` 對應 debian 系、`pacman` 對應 arch 系、其餘平台空字串）。

- `10-install-packages` 依 `$p.pkgManager` 分支：`apt` 分支維持現狀；
  `pacman` 分支裝 `base-devel procps-ng curl file git zsh`。
- `20-install-homebrew`、`30-install-brew-packages` 的守門條件從
  `$p.isPosix` 改成 `eq $p.pkgManager "apt"`（也就是只有 Debian 系才裝
  brew；macOS 沒有 `pkgManager` 分類但仍需要 brew，需要另外處理——見下方
  「守門條件的精確寫法」）。
- **新增** `run_onchange_before_30-install-pacman-packages.sh.tmpl`，守門
  `eq $p.pkgManager "pacman"`，用 `pacman -S --needed --noconfirm` 裝
  §4.1 表裡那七個工具裡 omarchy 出廠沒裝的（目前只有 `git-lfs`；其餘六個
  omarchy 出廠已裝，重複 `pacman -S --needed` 是 no-op，不裝也不會壞，
  但寫出來讓這支腳本本身冪等、不依賴「使用者一定是用 omarchy 而不是純
  Arch」這個假設更安全）。
- `40-git-lfs` 的 `eval "$($p.brewPrefix/bin/brew shellenv)"` 前置動作要
  改成依 `$p.pkgManager` 分支：`apt` 系維持走 brew 的 `git-lfs`，
  `pacman` 系直接呼叫系統的 `git-lfs`（不需要 `brew shellenv`）。
- `50-neovim`：**建議整支在 `pacman` 系上跳過**（守門加一條
  `ne $p.pkgManager "pacman"`），改為信任 omarchy 出廠的 `omarchy-nvim`。
  這是本研究裡影響面最大、也最需要使用者拍板的一個決定，理由：
  - omarchy 自己有 `omarchy-nvim-refresh`／`omarchy-reinstall-configs`
    這套維護機制，跟這個 repo 的 marker 檔（`.chezmoi-lazyvim-starter`）
    邏輯是兩條互不相知的軌道，同時存在只會增加「到底誰改的」的除錯難度。
  - 如果使用者想要「這個 repo管理的那份 LazyVim 設定＋覆寫」而不是 omarchy
    出廠版，才需要讓 `50-neovim` 在 Arch 上也跑——這是一個產品決定，不是
    技術限制，留給 §7 開放問題。
- `default-shell`：邏輯不用改（`chsh` 在 Arch 上原生可用），但只有在
  `zsh` 真的被裝出來之後才有意義，所以隱含依賴 `10-install-packages` 的
  `pacman` 分支已經跑過。

守門條件的精確寫法（因為 macOS 不屬於 `apt` 也不屬於 `pacman`，但仍需要
brew）：`platform.toml` 讓 `brewPrefix` 非空這件事本身已經是「這個平台該用
brew」的訊號（Windows 上是空字串），可以把 `20-install-homebrew`／
`30-install-brew-packages`／`50-neovim`（若選擇繼續讓 Arch 走 mise+brew）的
守門條件從 `$p.isPosix` 改成 `ne $p.brewPrefix ""`，比新增
`eq $p.pkgManager "apt"` 更貼近現有「`brewPrefix` 決定要不要用 brew」的
既有慣例（`platform.toml:23` 的註解本來就是這個意圖），且不需要 macOS
也塞一個 `pkgManager` 值。`$p.pkgManager` 則只在 `10-install-packages`／
新的 `30-install-pacman-packages` 用得到（macOS 上 `pkgManager` 可以留
空字串，因為 macOS 不需要系統套件管理員分支，全部靠 brew）。

- 優點：不重複安裝，尊重 omarchy 已經做好的選擇，跟 omarchy 自己的更新／
  維護機制（`omarchy-update-system-pkgs`）而不是這個 repo 自己的
  `run_onchange` 雜湊機制對齊，减少兩套機制打架的面積。
- 缺點：改動面較大（`platform.toml`、四支既有腳本、一支新腳本），且
  `neovim` 版本 pin 的概念在純 pacman 路徑下失去意義（§4.4），
  `versions.toml` 的 `neovim` 欄位對 Arch 分支不適用，需要在腳本或註解裡
  明講「這個 pin 只對 mise 路徑有效」。

### 建議

選項二。理由濃縮：這個 repo 目前的 brew 路線是「Debian 系統缺工具，用 brew
補齊」的產物；Arch／omarchy 的起點跟 Debian 完全不同——工具已經在，缺的只是
「這個 repo 管理的那組使用者設定檔」。硬套 brew 路線等於無視這個差異，換來
維護兩套包管理系統的長期成本。`50-neovim` 是否要跳過，因為牽涉到「這個 repo
的 LazyVim 覆寫 vs omarchy 出廠 LazyVim」哪個優先，屬於需要使用者決定的產品
問題，列入 §7。

---

## 7. 測試策略

### 現有測試層可以涵蓋的部分

- **L1／L2 的渲染矩陣**：新增 `osReleaseIdOverride`（比照 `platform.toml`
  現有的 `osOverride`／`archOverride` 寫法，只有這個檔案認得，正式環境沒有
  這個 key）；`platform.toml` 讀取順序改成：先算 `$os`／`$arch`，再依
  `hasKey . "osReleaseIdOverride"` 決定 `$osReleaseId`（預設退回
  `.chezmoi.osRelease.id`，非 Linux 平台這個欄位本來就不存在，要用
  `hasKey .chezmoi "osRelease"` 先擋，否則在 Windows/macOS fixture 上算繪
  會因為 `missingkey=error` 直接報錯，見 `platform.toml:11` 的既有註解）。
  有了這個接縫，L1 可以新增一組 `osOverride=linux, osReleaseIdOverride=arch`
  的斷言，驗證 `$p.pkgManager` 算出 `"pacman"`；L2 的 `_expect()` 表可以
  幫新的 `30-install-pacman-packages.sh.tmpl` 登記「只在 Arch 渲染矩陣的那
  一格非空」。
- **L6 檔案 golden**：如果 Arch 分支不影響 `modify_` 檔案或設定檔渲染邏輯
  （選項二的改動集中在安裝腳本，不動 `.codex`/`.claude` 設定樣板），這一層
  不需要新增 Arch 專屬 fixture，現有的 linux/windows 兩組已經涵蓋設定檔
  渲染邏輯本身跟發行版無關這件事。
- **L3（managed set／LF attributes）**：新增的 `30-install-pacman-packages
  .sh.tmpl` 需要走一次這一層，確認它被列進 managed 腳本清單、`.gitattributes`
  的 LF 規則涵蓋到它（比照其他 `.sh.tmpl`）。
- **L4（語法）**：新腳本要能通過既有的 shell 語法檢查層，不需要新機制。

### 需要新機制或無法在現有工具下驗證的部分

- **`.chezmoi.osRelease` 本身無法在 Windows/WSL Debian 主機上偽裝成 Arch**
  ——它是 chezmoi 讀執行機器真實 `/etc/os-release` 的結果，不是 config 可覆寫
  的欄位（§4.3）。上面提的 `osReleaseIdOverride` 接縫解決的是「讓
  `platform.toml` 自己的邏輯可測試」，不是「讓 chezmoi 原生行為可測試」——
  這條區別要在測試檔案的註解裡講清楚，比照現有 `platform.toml:10-15` 對
  `osOverride`／`archOverride` 的說明方式，避免未來的人誤以為這個接縫證明了
  chezmoi 在真正的 Arch 機器上也會算出同樣的值（那件事只有真的在 Arch 上跑
  chezmoi 才能證明，也就是下面這條）。
- **`pacman -S` 實際裝不裝得起來、omarchy WSL 上跑一次完整 `chezmoi apply`
  會不會成功**：目前 L9 的 Linux 探針（`docker.sh` 用 `debian:12`、`wsl.sh`
  用哪個 distro 未在 README 明講但邏輯共用 Debian 系的 `_probe.sh`）完全沒有
  觸及 Arch。要驗證 Arch 分支，需要新增一支對等的探針——最直接的作法是比照
  `wsl.sh` 的模式，但目標是使用者現有的 `omarchy` WSL distro（或它的一份
  複本，避免探測污染使用者要重建的環境）而不是 `chezmoi-probe` 這種
  用完即丟的全新 distro；也可以參考 `docker.sh` 的模式，改用官方 Arch
  Docker image（`archlinux:latest`）跑一次 `pacstrap`-less 的最小驗證，
  但 Docker 版的 Arch image 沒有 omarchy 的套件與 skel，驗證不到
  `omarchy-nvim` 那條路徑，只能驗證「純 Arch＋這個 repo 的 pacman 分支
  能不能跑完」，omarchy 特有的整合（dotfiles 所有權衝突、`omarchy-nvim`）
  仍然只有對著真正的 omarchy 環境才能驗證。
- **omarchy migrations 是否會跟 chezmoi 管理的檔案衝突**：這份研究沒有逐一
  讀過 `~/.local/share/omarchy/migrations/` 底下每一支腳本內容，這條風險
  停留在「已知存在，未評估」的狀態，需要之後针對「這個 repo 打算讓 chezmoi
  管理哪些檔案」的具體清單，逐一比對是否落在任何一支 migration 的改動範圍內。
- **裸機（真正的 Hyprland 桌面）行為**：這次探測的 WSL 映像沒有裝 Hyprland
  （§2.7），omarchy 的桌面環境整合（主題、桌布、`omarchy-theme-*` 系列
  指令）完全沒有實測，這個 repo 目前也沒有管理任何桌面環境相關的設定檔，
  這條差異暫時不影響設計，但如果之後要管理桌面相關設定，需要在真正的裸機或
  帶 Hyprland 的 WSLg 環境上重新驗證。

---

## 8. 開放問題（需要使用者決定）

1. **`50-neovim` 在 Arch 上要不要跑？** 選 A：完全跳過，信任
   `omarchy-nvim` 出廠設定，使用者若想要這個 repo 管理的 LazyVim 覆寫
   （`private_dot_config/nvim/` 底下的檔案），需要另外設計一套「疊加在
   omarchy 設定之上」的機制。選 B：跟 POSIX 一樣跑，接受它會把
   `omarchy-nvim` 的出廠設定搬進 `.bak`，之後靠這個 repo 自己的 LazyVim
   starter＋覆寫。選 C：偵測 `omarchy-nvim` 套件是否存在
   （`pacman -Qi omarchy-nvim`），存在就跳過，不存在（例如使用者之後移除了
   這個套件）才跑原本邏輯。
2. **`git-lfs` 在 Arch 上要不要裝、透過哪個管道？** 目前只有這一個工具是
   omarchy 出廠沒裝、也不在 `pacman -Qe` 清單裡的（§4.1）。建議走
   `pacman -S git-lfs`（`extra` repo 有），但要跟使用者確認 git-lfs 是否
   仍是必要依賴（`AGENTS.md` 的 `40-git-lfs` 腳本說明其存在理由跟平台
   無關，這裡不重新評估必要性，只確認裝法）。
3. **`~/.config` 下的檔案清單要不要跟 omarchy 的 `/etc/skel` 涵蓋範圍
   逐一比對？** 例如 `~/.config/git`、`~/.config/starship.toml` 這幾個
   在 omarchy `/etc/skel` 也有對應項目（§2.2 的 `ls ~/.config`
   看到 `git`、`starship.toml` 都在），如果這個 repo 之後想管理這些檔案，
   需要先確認 omarchy 出廠版本長什麼樣、`omarchy reinstall configs`
   會不會把 chezmoi 的版本蓋掉（會，§5），使用者要接受這個已知的互相覆蓋
   風險，還是要求 chezmoi 的內容明確標注「這是 chezmoi 管的，omarchy
   reinstall configs 會蓋掉，重蓋後要記得重新 `chezmoi apply`」。
4. **是否要在裸機（真正的 Hyprland 桌面）上另外驗證一次？** 這次的
   探測完全侷限在 WSL 變體（§2.7），使用者提到最終要跑裸機或另一台 WSL
   常駐使用，裸機環境的套件差異（多出 Hyprland 全家桶）跟這次的結論
   是否還成立，需要在真正拿到裸機或帶 Hyprland 的環境後重新確認至少
   §2、§3 的關鍵幾條。
5. **`mise` 路徑 vs `pacman` 路徑的 neovim 版本管理，選哪一條？** 見
   §4.4——如果選 pacman 直接裝 `neovim`，`versions.toml` 的 `neovim` pin
   在 Arch 分支要嘛不適用、要嘛需要額外邏輯把 pacman 版本鎖定在特定值
   （Arch 官方沒有簡單的套件版本鎖定機制，通常靠停用該套件的自動更新或
   手動 downgrade，超出這個 repo 現有的安裝腳本模型）。

---

## 附錄 A：WSL omarchy `pacman -Qe`（明確安裝套件）完整清單

實測指令：`pacman -Qe`（2026-09-07，`omarchy` WSL distro）。

```
base 3-3
base-devel 1-2
bash-completion 2.18.0-1
bat 0.26.1-2
btop 1.4.7-1
clang 22.1.8-1
dua-cli 2.42.1-1
dust 1.2.5-1
expac 10-13
eza 0.23.5-2
fastfetch 2.67.1-1
fd 10.4.2-2
fzf 0.74.3-1
git 2.55.0-1
github-cli 2.98.0-1
gum 2.0.0-1
imagemagick 7.1.2.30-1
inetutils 2.8-1
jq 1.8.2-1
lazydocker 0.25.2-1
lazygit 0.64.1-1
less 1:704-1
libqalculate 5.12.0-1
llvm 22.1.8-2
luarocks 3.13.0-5
man-db 2.13.1-2
mise 2026.8.10-1
neovim 0.12.5-1
noto-fonts 1:2026.08.01-1
noto-fonts-emoji 1:2.051-1
omarchy-keyring 20251027-1
omarchy-nvim 2026.8.13-1
plocate 1.1.24-2
ripgrep 15.2.0-1
ruby 3.4.10-1
rust 1:1.98.0-1
socat 1.8.1.3-1
starship 1.26.0-1
sudo 1.9.17.p2-6
tldr 3.4.4-1
tmux 3.7_c-1
tree-sitter-cli 0.26.9-1
ttf-jetbrains-mono-nerd 3.5.1-2
unzip 6.0-23
usage 5.1.0-1
whois 5.6.6-1
wl-clipboard 1:2.3.0-1
xdg-user-dirs 0.20-1
xdg-utils 1.2.1-2
xmlstarlet 1.6.1-6
yay 13.0.1-1
zoxide 0.10.0-1
```

52 個明確安裝的套件（另有 238 個依賴套件，`pacman -Q | wc -l` = 290，
未逐一列出）。

---

## 方法論附註：`wsl.exe` 呼叫的變數展開問題

透過這個 repo 使用的 Bash 工具（Git Bash / MSYS）呼叫 `wsl.exe -d omarchy --
bash -c '...'` 時，只要 `-c` 傳入的字串裡含有 shell 變數展開（哪怕整段用單引號
包住，例如 `for c in ...; do echo "$c"; done` 或單純 `c=x; echo "$c"`），
展開結果會變成空字串——實測重現多次，原因未深究（推測是 Git Bash／MSYS 對
`wsl.exe` 這個 Win32 執行檔的參數傳遞路徑跟一般 POSIX 子行程不同，導致某種
提前展開或跳脫遺失，**未證實**）。純字面字串（沒有變數展開）的 `-c` 呼叫
（例如 `which pacman yay ...`、`pacman -Qe`）不受影響。解法：把要執行的邏輯
寫成獨立的 `.sh` 檔案存到本機暫存目錄，執行前加上
`MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL="*"` 這兩個環境變數（避免 MSYS 把
`/mnt/c/...` 這類看似 POSIX 路徑的參數改寫成 Windows 路徑），再用
`wsl.exe -d omarchy -- bash "/mnt/c/.../probeN.sh"` 執行，本篇 §2、§3、§4
的多指令探測都是用這個方法拿到的。這條方法論本身不影響任何一條實測結論的
真實性，只是記錄下來讓下一個要用同樣方式探測 WSL 環境的人不用重踩一次。
