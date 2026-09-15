# Independent Verification — spec-version-bump

Tier 2，沒有派 `verifier` agent（那是 Tier 3 的動作）。這份聚合存在的理由只有一個：
把「gate 失敗就不能封存」從散文變成機械拒絕。`spec-archive.py:254-270` 的
`check_verdict` 會讀這一欄，`blocked` 讓 CLOSE 以 exit 1 拒絕。沒有這個檔，
`spec-archive` 不會去讀 evidence report 的 `headline`，一份 BLOCKED 的報告照樣封存得掉。

- `final_source_state`: `248c50141a819b5613925fb4b3de4771820b27ca`
- `final_verdict`: blocked
- `rounds_run`: 0（cap n-a）—— Tier 2 不派 verifier agent
- `verifier`: not performed —— 取而代之的是 `evidence-squad` 的三個 cut，
  每個 cut 3–4 個唯讀透鏡、四個輸入、沒有拿到協調者的對話
- `inputs_given`: n-a（見上）
- `canary`: not run

## 為什麼是 blocked

`tools/gate.sh --scope spec-version-bump` 在 `248c501` 的 headline 是
**BLOCKED at Mutation**（38/44）。契約
`.chezmoitemplates/evidence-first-contract.md:42` 寫「A failing gate blocks done」，
`dot_agents/workflows/evidence-first.md:370` 的 Anti-Gaming 第 6 條把它寫成
「絕對，貫穿每一個 phase」。

六個存活的 mutant 全部只由 L7 的 Windows 分支證偽，而本機沒有 `pwsh.exe`。
base ref `9a2e879` 跑同一個指令得同樣的 38/44、同樣六個名稱，存活清單 `diff` 為空，
所以**這個分數與本次變更無關**。但失敗的後果與本次變更有關：`supply-chain`、
`changed-lines`、`manifest audit` 三層因此 NOT REACHED，而那三層量的就是這次的變更。

## 解除的兩條路（都需要使用者）

1. 在跑得到 `pwsh.exe` 的主機上重跑入口。詳見 evidence report 的
   Structural blind spot：16 條 skip 裡 12 條只要裝 Linux `pwsh` 就會執行，但那
   對 mutation 沒有幫助；L7 的 C 段門檻改掉可多殺 2 個（40/44，仍然失敗）；
   剩下 4 個需要 Windows 語意。
2. 使用者逐字核准「接受這個本機造成、base ref 逐條相同的 mutation 失敗，記成一次
   宣告過的降級」。核准後這一欄改成 `passed`，並把原話逐字記在下面。

## 核准紀錄（降級路線用）

<!-- 逐字引用；沒有核准就保持空白 -->

- 尚未核准。
