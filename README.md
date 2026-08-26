# dotfiles

用 chezmoi 管理 zsh 環境（Oh My Zsh + zsh-autosuggestions + zsh-syntax-highlighting + fzf-tab + Powerlevel10k + mise）。

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
