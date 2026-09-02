# L9：Windows Sandbox 的 end-to-end 執行

這是唯一允許真的跑 `winget install` 的地方。主機不行
（見 `.scratch/windows-support/spec.md` 的 Must NOT #1）。

## 怎麼跑

```sh
tests/sandbox/prepare.sh           # 把 HEAD 的來源樹與 _probe.ps1 放進 src/
# 然後在 Windows 上按兩下 chezmoi-sandbox\sandbox.wsb
```

沙箱開機後 `sandbox.wsb` 的 `LogonCommand` 會執行 `C:\src\_probe.ps1`。
跑完之後：

| 檔案 | 內容 |
|---|---|
| `out/results.tsv` | 每一條檢查的 PASS/FAIL 與細節，最後一行是總計 |
| `out/transcript.txt` | 整段執行的 transcript |
| `out/treesitter.log` | Neovim 那段的輸出（M12 用） |

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
