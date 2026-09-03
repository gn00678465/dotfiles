# dotfiles

用 chezmoi 管理開發環境，Linux / macOS / native Windows 三個平台。

| | Linux / macOS | Windows |
|---|---|---|
| Shell | zsh + Oh My Zsh | PowerShell 7 |
| Prompt | Powerlevel10k | oh-my-posh（powerlevel10k_rainbow） |
| 補全／建議 | zsh-autosuggestions + zsh-syntax-highlighting | PSReadLine（內建） |
| 模糊搜尋 | fzf + fzf-tab | fzf + PSFzf |
| 套件 | apt（前置）+ Homebrew | winget |
| 版本管理 | mise | mise |

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
