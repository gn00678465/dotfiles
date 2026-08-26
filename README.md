# dotfiles

用 chezmoi 管理 zsh 環境（Oh My Zsh + zsh-autosuggestions + zsh-syntax-highlighting
+ fzf-tab + Powerlevel10k + mise）。取代原本的一鍵安裝 shell 腳本。

---

### 1. 確認 curl

安裝腳本本身要用 curl 下載，而沒有任何腳本會裝它，所以 curl 必須先存在：

```bash
command -v curl || { sudo apt-get update && sudo apt-get install -y curl; }
```

### 2. 執行 chezmoi 安裝腳本

```bash
sh -c "$(curl -fsLS get.chezmoi.io)" -- -b "$HOME/.local/bin" init --apply gn00678465
```

`-b "$HOME/.local/bin"` 不能省：安裝腳本的 `BINDIR` 預設是 `./bin`，相對於當下工作目錄，
腳本全程不會 `cd` 到 `$HOME`。少了它，事後 `chezmoi` 指令不在 PATH 上。

必須在真實終端機執行，過程中有兩次互動：

| 時機 | 問什麼 |
|---|---|
| `run_onchange_before_install-packages` 裝套件 | `sudo` 密碼 |
| `run_after_default-shell` 改登入 shell | **你自己的**密碼（`chsh` 是 setuid，不是 sudo） |

---

## 日常使用

```bash
chezmoi diff                 # 看會改什麼
chezmoi apply                # 套用
chezmoi add ~/.p10k.zsh      # 跑完 p10k configure 後把結果收回 repo
chezmoi update               # git pull + apply
chezmoi apply --refresh-externals   # 強制重抓 external
```
