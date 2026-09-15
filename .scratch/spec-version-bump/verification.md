# Independent Verification — spec-version-bump

Tier 2，沒有派 `verifier` agent（那是 Tier 3 的動作）。取而代之的是 `evidence-squad`
的三個 cut，每個 cut 3–4 個唯讀透鏡、四個輸入、沒有拿到協調者的對話。

- `final_source_state`: `deed0570092d22eed202aa3d201740ed47bf8b5b`
- `final_verdict`: not performed
- `rounds_run`: 0（cap n-a）—— Tier 2 不派 verifier agent；
  接受 gate 降級而放行封存，核准者原話見下方「降級核准」
- `verifier`: not performed
- `inputs_given`: n-a（見上）
- `canary`: not run

`final_verdict` 這一欄問的是「獨立驗證（Phase 5）的結論」。本次沒有跑，所以它是
`not performed`，而不是 `passed`——**沒有任何一輪獨立驗證說過這份工作通過**。
gate 的結論不放在這一欄，放在 evidence report 的 `headline`。

## 這一欄先前是 `blocked`，為什麼改掉

`spec-archive.py` 不讀 evidence report 的 `headline`，所以「A failing gate blocks
done」在 CLOSE 這一端原本沒有任何機械把關。本輪先把這一欄填成 `blocked`，讓
`check_verdict`（`:254-270`）以 exit 1 擋住封存，把那句散文變成機械拒絕。
核准者核准降級後改成這一欄的真值 `not performed`。**改動留在版控裡。**

## 降級核准

核准者於 2026-09-15 逐字核准：

> 接受這個本機造成、改動前後完全相同的失敗，記成一次宣告過的降級

### 這句話涵蓋什麼

`tools/gate.sh --scope spec-version-bump` 在 `248c501` 的 headline 是
**BLOCKED at Mutation**（38/44）。六個存活的 mutant 全部只由 L7 的 Windows 分支
證偽，而本機沒有 `pwsh.exe`。base ref `9a2e879` 跑同一個指令得同樣的 38/44、
同樣六個名稱，存活清單 `diff` 為空——**這個分數與本次變更無關，改動前後完全相同**，
正是核准原話指的那件事。

### 這句話不涵蓋什麼

1. **Windows 上的實際行為仍然沒有任何證據。** 這不是被核准了，是仍然不知道。
   evidence report 的 Structural blind spot 寫明哪些補得回來、哪些補不回來。
2. **四層 NOT REACHED 不是被核准通過。** gate 停在 mutation，後面四層與 manifest
   稽核沒有執行。其中 supply-chain、changed-lines、manifest 稽核量的就是本次變更。
   本輪把前三層在 `deed057` 單獨跑過並記進 evidence report，但**那是單獨執行，
   不是 gate 同一次的數字**，Gate 表維持 NOT REACHED。manifest 稽核無法單獨跑
   （它稽核的是那一次執行的 `layers-ran`）。
3. **`spec-archive.py` 不讀 headline 這個洞仍然存在**（evidence H16），不屬於本 scope。

## Rounds

| Round | Source state | Verdict | Behavioural findings | Description/mapping findings |
|---|---|---|---|---|
| — | — | not performed | — | — |

沒有跑過任何一輪 verifier。三個 squad cut 的紀錄在
`.scratch/spec-version-bump/squad/`：after-spec 42 條、after-implement 28 條、
before-archive 25 條（11 class 1 全部 `status: fixed`）。

## Fixed after the last verified state (therefore unverified)

`248c501` 之後只改了紀錄類檔案（evidence report、squad 紀錄、本檔）。
產品程式碼與測試自 `248c501` 起未動，`git diff 248c501..HEAD --name-only` 只有
`.scratch/` 底下的檔案。
