# L9：Windows Sandbox 的 end-to-end 執行

這是唯一允許真的跑 `winget install` 的地方。主機不行
（見 `specs/windows-support/SPEC.md` 的 Must NOT #1）。

探針有兩種模式。**本機模式**測的是還沒推上去的分支，需要事先對應資料夾；
**遠端模式**一行指令就跑得完，但只能測已經推上 GitHub 的分支。

## 本機模式（未推送的分支）

```sh
tests/sandbox/prepare.sh           # 把 HEAD 的來源樹與 _probe.ps1 放進 src/
# 然後在 Windows 上按兩下 chezmoi-sandbox\sandbox.wsb
```

沙箱開機後 `sandbox.wsb` 的 `LogonCommand` 會執行 `C:\src\_probe.ps1`。
來源樹是唯讀對應的 `C:\src\dotfiles`，輸出寫到對應出去的 `C:\out`：

| 檔案 | 內容 |
|---|---|
| `out/results.tsv` | 每一條檢查的 PASS/FAIL 與細節，最後一行是總計 |
| `out/transcript.txt` | 整段執行的 transcript |
| `out/treesitter.log` | Neovim 那段的輸出（M12 用） |

## 遠端模式（任何一台有 Sandbox 的機器）

不需要 `prepare.sh`，不需要對應任何資料夾，也不需要這個 repo 在本機。開一個乾淨的
Windows Sandbox，在裡面的 Windows PowerShell 5.1 貼上一行：

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/gn00678465/dotfiles/feat/windows-support/tests/sandbox/_probe.ps1))) -Branch feat/windows-support
```

`-Branch` 一給，探針就不再找 `C:\src`，改成讓 chezmoi 自己 clone
（`chezmoi init --apply --branch <分支> gn00678465`）—— 這也正是真實使用者第一次
安裝時走的路。凡是要讀來源樹取預期值的檢查，改讀 `chezmoi source-path`。

**前提**：那個分支必須已經推上 GitHub。遠端模式測的是 GitHub 上的內容，不是你本機
工作樹的內容；要測沒推上去的東西，用上面的本機模式。

> **關掉就沒了。** 遠端模式沒有對應資料夾，`C:\out` 不存在，輸出改寫到
> `%USERPROFILE%\Desktop\chezmoi-probe\`。Sandbox 一關，那個桌面連同裡面的檔案
> 全部消失，**沒有任何東西留在主機上**。所以探針在結尾會把 `results.tsv` 全文再印
> 一次到主控台：在關掉視窗之前，把那一段捲上去複製出來，或整個 transcript 選起來
> 複製。這是唯一會活下來的副本。

## 這一層在證什麼

前面 L1–L8 都沒有真的安裝任何東西：L1–L7 是渲染與行為，L8 是 Windows 主機上的
唯讀驗證。**「winget 的套件 ID 真的裝得起來」「安裝完的環境真的能用」只有這裡能證。**

特別是兩條在別處證不了的：

- **M12（未證實項）**：nvim-treesitter 在 Windows 上到底能不能用 zig 編出 parser。
  探針會跑一次 `Lazy! sync` + `TSInstall! lua`，看有沒有產出 `lua.so`。
- **symlink 權限**：乾淨的沙箱沒有開發人員模式，所以 `~/.claude/skills` 那兩個
  symlink **預期會失敗**。這條的 FAIL 是預期結果，它證明 `init.ps1` 的警告不是多餘的。

## 為什麼探針裡有 winget 自舉那一段

Sandbox 的基礎映像沒有 App Installer，所以 `winget` 不存在。那段程式碼只服務這個
測試環境，**不會進到 `init.ps1`**：真實的 Windows 11 本來就有 winget。

---

# L9（Linux）：Docker 容器與全新 WSL distro

Linux 的探針是 `_probe.sh`，跟 `_probe.ps1` 問同一組問題，再多走「第二次之後」：
這個 repo 真正出過的錯（`chezmoi update` 撞不存在的 `/run/user/<uid>`、刪掉的 neovim
不會裝回）都不在第一次安裝出現。所以它在第一次 `init --apply` 之後還會做第二次
`apply`（必須不互動、不重新 bootstrap nvim）、`chezmoi git`（`update` 的 code path）、
以及 `mise uninstall neovim` → `apply` → 裝回來。

兩個啟動器，探針共用：

| | `docker.sh` | `wsl.sh` |
|---|---|---|
| 環境 | `debian:12` 容器，用完即丟 | 全新的 `chezmoi-probe` WSL distro，跑完 `--unregister` |
| 能從哪裡跑 | 任何有 docker 的機器 | 只有 Windows 主機上的 WSL（需要 `wsl.exe` 互通） |
| systemd | 沒有 → linger / `chezmoi update` 兩條是 **SKIP** | 有 → 這是唯一能證明 WSL runtime-dir 修正的地方 |
| 輸出 | `.gate/l9-linux/`（`--out` 可改） | `chezmoi-sandbox\out\`，與 Windows Sandbox 同一個資料夾 |

```sh
tests/sandbox/docker.sh                  # 本機模式：HEAD（git archive，只帶已提交的內容）
tests/sandbox/docker.sh --branch <name>  # 遠端模式：跑 GitHub 上那個分支的 init.sh
tests/sandbox/wsl.sh                     # 本機模式：經 prepare.sh 放到 chezmoi-sandbox\src
tests/sandbox/wsl.sh --branch <name>     # 遠端模式
tests/sandbox/wsl.sh --keep              # 跑完保留 distro（wsl.exe -d chezmoi-probe 進去看）
```

`results.tsv` 的格式與 Windows 相同（`PASS|FAIL|SKIP <tab> 名稱 <tab> 細節`，最後一行
`SUMMARY`），探針結尾一樣把全表印到主控台。容器與 distro 都是 root 先做最小的自舉
（`sudo`、`curl`、一個叫 `probe` 的使用者、免密碼 sudo——探針沒有 tty，跟 Windows Sandbox
的使用者是管理員同一個道理），那段不屬於 dotfiles。

`wsl.sh` 會在你的 Windows 上用 `wsl --import` 註冊一個 distro（rootfs 由 docker 的 `debian:12`
匯出，所以也需要 docker），名字 `chezmoi-probe` 是保留給它的：同名的既有 distro 會被直接換掉。
不用 `wsl --install Debian`：從 WSL 內部呼叫它會把呼叫端 distro 的 Windows 互通一起清掉（實測）。

**跑完之後呼叫端 distro 的互通會斷**（`wsl.exe`、`pwsh.exe` 變成 `exec format error`）：
binfmt_misc 是整個 WSL VM 共用的，探針 distro 停掉時它的 `/init` 會把 `WSLInterop` 註銷。
`wsl.sh` 結尾偵測到會印出修法，需要 root：

```sh
sudo sh -c 'echo ":WSLInterop:M::MZ::/init:PF" > /proc/sys/fs/binfmt_misc/register'
```

第一次在全新 WSL distro 的實跑：33 PASS / 0 FAIL / 1 SKIP（`chezmoi update` 在本機模式沒有
remote 可拉）。`XDG_RUNTIME_DIR=/run/user/1000` 確實被 WSL 塞進來、`05-wsl-user-runtime-dir`
把 linger 開起來、目錄存在、`chezmoi git` 能跑——原本壞掉的那條路徑在乾淨的機器上證明修好了。
