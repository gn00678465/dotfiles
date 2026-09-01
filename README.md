# dotfiles

用 chezmoi 管理 zsh 環境（Oh My Zsh + zsh-autosuggestions + zsh-syntax-highlighting + fzf-tab + Powerlevel10k + mise）。

---

## Windows 原生安裝

在 Windows 10/11 x64 的 PowerShell 中先安裝 chezmoi，再套用本 repository：

```powershell
winget install --id twpayne.chezmoi --exact --source winget
chezmoi init --apply https://github.com/gn00678465/dotfiles.git
```

測試指定 branch 時，branch 名稱必須同時出現在 init 參數與 repository：

```powershell
chezmoi init --apply --branch <branch> https://github.com/gn00678465/dotfiles.git
```

套用時 WinGet 會安裝 PowerShell 7、Oh My Posh、mise、Git／Git LFS 與 C++ Build
Tools。Git 與 Build Tools 會出現 **UAC** 提示；取消或安裝失敗會中止套用。完成後請開啟新的
`pwsh` session。Oh My Posh 使用 `powerlevel10k_rainbow` theme pointer；首次 cache miss
需要網路下載 theme。若 icon 顯示異常，在 Windows Terminal 選擇 Nerd Font；這不是 bootstrap
自動安裝的相依性。

---

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

## 日常使用

```bash
chezmoi diff                 # 看會改什麼
chezmoi apply                # 套用
chezmoi add ~/.p10k.zsh      # 跑完 p10k configure 後把結果收回 repo
chezmoi update               # git pull + apply（追目前 checkout 的 branch）
chezmoi cd                   # 進 source dir；git checkout <branch> 後 exit 再 chezmoi apply
chezmoi apply --refresh-externals   # 強制重抓 external
```
