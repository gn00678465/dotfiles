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
