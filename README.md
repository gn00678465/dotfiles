# dotfiles

用 chezmoi 管理開發環境：Linux（Debian 系與 Arch）、macOS、native Windows。

| | Linux（Debian 系）/ macOS | Arch 家族（omarchy、純 Arch） | Windows |
|---|---|---|---|
| Shell | zsh + Oh My Zsh | zsh + Oh My Zsh；omarchy 上另載入其 `env-bootstrap` | PowerShell 7 |
| Prompt | Powerlevel10k | Powerlevel10k | oh-my-posh（powerlevel10k_rainbow） |
| 補全／建議 | zsh-autosuggestions + zsh-syntax-highlighting | 同左 | PSReadLine（內建） |
| 模糊搜尋 | fzf + fzf-tab | fzf + fzf-tab | fzf + PSFzf |
| 套件 | apt（前置）+ Homebrew | pacman（不裝 Homebrew） | winget |
| 版本管理 | mise | mise（pacman） | mise |
| neovim | mise 釘版本 + LazyVim starter | pacman 的 neovim；omarchy 沿用出廠的 LazyVim 設定，純 Arch clone LazyVim starter | mise 釘版本 + LazyVim starter |

---

## Linux / macOS

### 1. 確認 curl

安裝腳本本身要用 curl 下載，而沒有任何腳本會裝它，所以 curl 必須先存在：

```bash
command -v curl || { sudo apt-get update && sudo apt-get install -y curl; }
```

### 2. 執行安裝腳本

```bash
sh -c "$(curl -fsLS https://raw.githubusercontent.com/gn00678465/dotfiles/main/init.sh)"
```

| 時機 | 問什麼 |
|---|---|
| `run_onchange_before_05-wsl-user-runtime-dir` 開 systemd linger（僅 WSL） | `sudo` 密碼 |
| `run_onchange_before_10-install-packages` 裝套件 | `sudo` 密碼 |
| `run_once_before_20-install-homebrew` 裝 Homebrew | `sudo` 密碼（快取通常還在） |
| `run_after_default-shell` 改登入 shell | **你自己的**密碼（`chsh` 是 setuid，不是 sudo） |

### 安裝指定 branch（測試用）

URL 和 `--branch` 要用同一個 branch 名，這樣跑的是該 branch 自己的 `init.sh`：

```bash
sh -c "$(curl -fsLS https://raw.githubusercontent.com/gn00678465/dotfiles/<branch>/init.sh)" -- --branch <branch>
```

不帶 `--branch` 就是遠端預設 branch（main）。裝完後 `chezmoi update` 會一直追那個 branch，
branch 合併刪除後要回 main：`chezmoi cd && git checkout main`。

已經裝過的機器重跑 `init.sh` 不會重新 clone，`--branch` 會被忽略；要換 branch 用下面的方式。

### Arch 家族：omarchy 與純 Arch

同一行 `init.sh`。發行版由 `/etc/os-release` 決定：`ID=arch`，或 `ID_LIKE` 含
`arch`（正式安裝的 omarchy 是 `ID=omarchy`、`ID_LIKE=arch`），都走 pacman，不裝
Homebrew：

| 時機 | 做什麼 | 問什麼 |
|---|---|---|
| `run_onchange_before_10-install-packages` | `pacman -S --needed` 裝 `zsh git curl base-devel` | `sudo` 密碼 |
| `run_onchange_before_30-install-pacman-packages` | 裝 `mise fzf git-lfs ripgrep fd lazygit tree-sitter-cli neovim`（omarchy 出廠大多已裝） | `sudo` 密碼（快取通常還在） |
| `run_after_default-shell` | 改登入 shell 為 zsh | **你自己的**密碼 |

只用 `pacman -S --needed --noconfirm`，不做 `-Sy` 或 `-Syu`。`-Sy` 之後接 `-S` 會進入
Arch 不支援的部分升級狀態，`-Syu` 則是把整台機器的升級變成套用 dotfiles 的副作用。
代價是資料庫過期或從未同步時 `-S` 會失敗，腳本停下來並印出該執行什麼。

**全新的 Arch 要先更新系統。** 官方 WSL 映像（`wsl --install archlinux`）沒有 pacman
同步資料庫，不先更新就會停在第一支腳本。以 root 執行：

```sh
pacman -Syu
```

若映像連金鑰環都是空的（`-Syu` 報簽章或 keyring 錯誤），先初始化再更新：

```sh
pacman-key --init
pacman-key --populate archlinux
pacman -Syu
```

omarchy 用它自己的 *Update > Omarchy*，不需要手動下 pacman。

更新完重跑同一行 `init.sh` 或 `chezmoi apply` 即可。套件腳本是 `run_onchange_`：
失敗不會被記成完成，下次 apply 會自動重試；成功之後除非清單改變才會再跑，而且
`pacman -Q` 會跳過已安裝的套件。

WSL 映像預設只有 root。以 root 執行 `init.sh` 可以直接安裝，腳本不需要 sudo。要改用
一般使用者時，先以 root 建好使用者與 sudo，再以該使用者執行 `init.sh`：

```sh
pacman -S --needed sudo
useradd -m -G wheel <name>
passwd <name>
echo '%wheel ALL=(ALL:ALL) ALL' > /etc/sudoers.d/10-wheel
printf '[user]\ndefault=%s\n' <name> >> /etc/wsl.conf
# 在 Windows 執行 wsl --shutdown，重開後就是 <name>
```

純 Arch 沒有 `omarchy-nvim`，`50-neovim` 會把既有的 `~/.config/nvim` 等目錄搬到
`.bak`，再 clone LazyVim starter，與 Debian 相同。

在 omarchy 上要知道的三件事：

- neovim 是 pacman 套件，`~/.config/nvim` 沿用 omarchy 出廠的 `omarchy-nvim`
  設定，這個 repo 只把 `lua/plugins/completion.lua` 疊上去；不會備份或搬動它。
- `~/.zshrc` 與 `~/.zprofile` 會載入 omarchy 的 `env-bootstrap`，所以 `OMARCHY_PATH`
  與 `omarchy-*` 指令在 zsh 裡照常可用；omarchy 的 bash 專用 `rc` 不載入。
- `~/.config/git/config` 由這個 repo 全檔接管，omarchy 安裝時寫入的 alias 與
  `init.defaultbranch=master` 會被取代。`omarchy reinstall configs` 不會碰這個檔案。

**終端機（選配）。** omarchy 4 預設 foot，官方同時支援 Alacritty、Ghostty 與 Kitty：
四種都有出廠設定（`~/.config/<name>`），主題切換也涵蓋它們。想要 GPU 加速與內建的
字型與連字處理，Ghostty 是合理選擇；foot 較輕，而且是預設值。換裝用 omarchy 自己的
機制，以一般使用者執行：

```sh
sudo pacman -S ghostty
omarchy-default-terminal ghostty
```

`ghostty` 在官方 `extra` 倉庫，不是 AUR。也可以走選單：*Install > Package* 安裝，
*Setup > Default > Terminal* 切換；選單只列出已安裝的終端機。切換改的是
`xdg-terminal-exec` 的預設項目，omarchy 的視窗規則與主題會跟著套用。

這個 repo 不安裝終端機，也不管它的設定。換或不換都不影響 `chezmoi apply` 的結果，
你的終端機設定也不會被這個 repo 覆蓋。

---

## Windows

前置條件只有一個：**winget**（Windows 11 內建的「應用程式安裝程式」就有）。
其餘的 PowerShell 7、Git、chezmoi 都由 `init.ps1` 自己裝起來。

```powershell
irm https://raw.githubusercontent.com/gn00678465/dotfiles/main/init.ps1 | iex
```

指定 branch（測試用）：

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/gn00678465/dotfiles/<branch>/init.ps1))) -Branch <branch>
```

**先開「開發人員模式」**（設定 > 系統 > 開發人員專用）。chezmoi 會在
`~/.claude/skills` 底下建 symlink，Windows 上一般帳號沒有這個權限，apply 會失敗。
`init.ps1` 會先探測並提醒，但它不會自己去改這個設定。

裝完之後**開一個新的 PowerShell 7 視窗**：profile 是在這次 apply 才寫進去的。

Windows 上的檔案落點與 POSIX 不同，這是各工具自己的規定，不是這個 repo 選的：

| | 路徑 |
|---|---|
| PowerShell 設定（chezmoi 管的本體） | `~\.config\powershell\profile.ps1` |
| pwsh 真正載入的 profile | `$PROFILE.CurrentUserAllHosts`，只有一行 loader |
| Neovim 設定 | `%LOCALAPPDATA%\nvim` |
| Neovim 資料／狀態 | `%LOCALAPPDATA%\nvim-data` |
| uv | `%APPDATA%\uv\uv.toml` |
| mise（全域） | `~\.config\mise\config.toml`（與 POSIX 相同） |

細節與各條的依據見 `docs/research/windows-native-support.md`。

---

## 日常使用

```bash
chezmoi diff                 # 看會改什麼
chezmoi apply                # 套用
chezmoi add ~/.p10k.zsh      # 跑完 p10k configure 後把結果收回 repo
chezmoi update               # git pull + apply（追目前 checkout 的 branch）
chezmoi cd                   # 進 source dir；git checkout <branch> 後 exit 再 chezmoi apply
chezmoi apply --refresh-externals   # 強制重抓 external
```

---

## Agent 工作流程

這個 repo 也裝 agent 的全域指令與 evidence-first 合約（`~/.claude/CLAUDE.md`、
`~/.codex/AGENTS.md`、`~/.agents/`）。合約何時觸發、六個 Phase 各做什麼、哪些步驟由腳本
擋住，見 [docs/evidence-first.md](docs/evidence-first.md)。
