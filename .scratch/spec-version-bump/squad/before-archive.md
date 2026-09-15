# Squad — before archive（spec-version-bump）

- `cut`: before-archive
- `tier`: 2
- `source_state`: `05ca70a`（四個透鏡都讀這一個 commit）
- `lenses`: evidence-vs-git ／ mapping-honesty ／ verdict-state ／ ledger-completeness
- `inputs`: 任務契約、SPEC v2、`05ca70a`、各自的 lens brief。四個都沒有拿到協調者的對話。三個透鏡另外重跑了量測：一個以同形入口重跑整輪 gate，兩個重建 base 的 RED。
- `counts`: class 1/2/3 = 11 / 11 / 3
- `verdict`: 擋住封存（第二輪：evidence-vs-git 透鏡在 `bda2fe1` 之後複驗，
  自行解除它的兩條 class 1，並新增一條 class 2。其他三個透鏡沒有複驗。）

## 裁決

擋住封存，兩個互相獨立的原因。

1. **Gate 的 headline 是 BLOCKED。** 契約 `.chezmoitemplates/evidence-first-contract.md:42`
   寫「A failing gate blocks done」，`dot_agents/workflows/evidence-first.md:370` 的
   Anti-Gaming 第 6 條把它寫成「絕對，貫穿每一個 phase」。mutation 層 38/44 失敗。
   verdict-state 透鏡自行到 base ref 重跑，確認六個存活 mutant 逐一相同、存活清單
   `diff` 為空，所以「與本次變更無關」對 mutation 的分數成立；但它同時指出，這個失敗
   讓 `supply-chain`、`changed-lines`、`manifest-audit` 三層變成 NOT REACHED，而那三層
   量的就是本次變更。因此「無關」不能延伸到封鎖的後果。
2. **證據報告與 SPEC 有事實錯誤。** 兩個透鏡各自獨立抓到同一條：RED 重建表把 S11 記成
   綠，實測在 base 是紅的 5 條。連同它共 11 條 class 1，見下。

第 2 條已經解掉：11 條 class 1 全部修完（`248c501` 與本輪改寫的 evidence report），
其中一條是真正的程式缺陷——未閉合圍欄裡的核准紀錄會被放行。改完在 `248c501` 重跑了
一次完整的 gate。

第 1 條解不開就不能封存，而它需要使用者決定：換一台跑得到 `pwsh.exe` 的主機重跑，或由
使用者逐字核准把它記成一次宣告過的降級。

另有兩項 class 2 要人類定價，一併放在同一次決定裡，不另開核准輪：`.gitignore` 進了
變更集但不在授權的 12 個檔案內；`check_agent_doc_invariants.py` 補的 `require` 比 v2
核准文字寫的多一條（核准寫「一條」，同句的理由「成對釘法」要兩條，實作跟了理由）。

## Class 1 —— 擋住封存，封存前必須修掉

- [HIGH] `.scratch/spec-version-bump/evidence.md:82` — RED 重建表把「S11、CRLF guard」合成一列記為 `passed（兩條都是 GREEN-guard）`，S11 在 base 是紅的 — 以 `SPEC_ARCHIVE_UNDER_TEST=$(git show 9a2e879:…/spec-archive.py)` 跑當前測試檔得 `FAIL: 45 of 86`，其中 5 行是 `FAIL: S11 two Approval sections cannot be evaluated — expected rc 2 …, got rc 0`；同一次執行裡 CRLF 那條是 `ok:` — class 1 — 拆成兩列，S11 改 `failed（5 斷言）`，CRLF guard 維持 GREEN-guard — status: fixed（本輪改寫 evidence report）
- [HIGH] `.scratch/spec-version-bump/evidence.md:13` — 標頭 `ordering: tests-first` 對 S11 不成立：S11 涵蓋的實作由 `4e1a8b5` 引入，S11 的測試由 10 個 commit 之後的 `f4308d8` 引入，是先實作後測試 — `git log --oneline -S"more than one Approval section"` → `4e1a8b5`；`git log --oneline -S"two Approval sections cannot be evaluated"` → `f4308d8`；`git log --oneline 4e1a8b5..f4308d8 | wc -l` → 10 — class 1 — 改成 `mixed`，並在括號裡點名 S11 這一條的方向 — status: fixed（本輪改寫 evidence report）
- [HIGH] `dot_agents/skills/spec-archive/scripts/spec-archive.py:131` — `_without_noise` 的圍欄剝除需要成對圍欄，未閉合圍欄裡的完整紀錄會被算成核准，違反 SPEC §2「圍欄程式碼區塊內的文字不是紀錄」 — 直接呼叫 `approved_versions(approval_section(_without_noise(t), "x"))`：閉合圍欄得 `[]`，同一筆紀錄改成未閉合圍欄得 `['v1']`；S4 的兩個圍欄誘餌都是閉合的（`tests/spec_archive_test.py:152-165`），沒有斷言走到這條路徑 — class 1 — 讓未閉合圍欄吃到檔尾，並補一個誘餌 — status: fixed（`248c501`）
- [HIGH] `specs/spec-version-bump/SPEC.md:279` — 同一份 SPEC 一邊授權改 `AGENTS.md`（`:275`，v2 新增），一邊寫「**不改**：`AGENTS.md`」（`:279`，v1 留下），而該檔實際被改 — `git diff 9a2e879..HEAD --stat -- AGENTS.md` → `1 file changed, 2 insertions(+), 2 deletions(-)` — class 1 — 刪掉 `:279` 的舊句，授權以 `:275` 為準 — status: fixed（`248c501`）
- [HIGH] `specs/spec-version-bump/SPEC.md:244` — `.gitignore` 進了變更集，但不在 SPEC「授權修改的檔案（12 個）」裡，SPEC 全文也沒提到這個檔 — `git diff 9a2e879..4110034 --name-only` 共 16 條含 `.gitignore`（`2bd80e6` 加 `CLAUDE.local.md` 一行）；`grep -n gitignore specs/spec-version-bump/SPEC.md` 只命中 `:341`，講的是 `.chezmoiignore` — class 2（**本輪改判**：evidence-vs-git 透鏡提報為 class 1，但它不是 SPEC 寫下的某條規則被違反，而是一個 SPEC 沒有涵蓋的變更，依 skill 的定義屬 class 2）— 記進 SPEC Revisions 與 evidence 的 H10，**不自行補進授權清單**；併入本輪本來就要做的那一次人類決定，不另開一輪核准
- [HIGH] `.scratch/spec-version-bump/evidence.md:122` — 「加上正整數限制後 39 個斷言轉紅」重現不出來 — 在 `check_approval` 的 R2 守衛前插入 `die` 得 `FAIL: 3 of 86`；兩個透鏡各試四種插入點，得到 3／4／7／8，沒有一種接近 39 — class 1 — 換成實測值 3，並寫出 mutant 的逐字內容 — status: fixed（本輪改寫 evidence report）
- [HIGH] `.scratch/spec-version-bump/evidence.md:170` — H3 寫「該腳本的失效方向是 `unconfirmed` 仍 exit 0 的誠實降級」，與實測相反 — 把 `tools/gate-intent.sh:67-153` 的 awk 抽出單獨跑：`LC_ALL=C` 下 `approves v1版` 使 awk 印 `v1`、Python 得 `[]`；經 `gate-intent.sh:157-162` 這會變成 `recorded=yes` → `intent=confirmed`，是 fail-open — class 1 — 改寫 H3 的失效方向，並把「0 不一致」限定在那 27 個輸入上 — status: fixed（本輪改寫 evidence report）
- [HIGH] `.scratch/spec-version-bump/evidence.md:15` — 標頭 `source_state` 寫「執行前後各驗一次，兩次相同」，同一份報告 `:104` 把 `source-state-after` 記成 NOT REACHED — `tools/gate.sh:86-97` 的 `run_layer` 在失敗層直接 `exit 1`，mutation 之後的 after 驗證與 `:211` 的 `diff` 都沒跑 — class 1 — 標頭改成「before 於本輪、after NOT REACHED」 — status: fixed（本輪改寫 evidence report）
- [HIGH] `.scratch/spec-version-bump/evidence.md:49` — 這一列把 `AGENTS.md` 與 `.chezmoitemplates/evidence-first-contract.md` 對到「`check_agent_doc_invariants.py` 的 94 條」並標 pass，該腳本讀不到這兩個檔 — `grep -c AGENTS tests/check_agent_doc_invariants.py` → 0；合約檔本次唯一的變更是第 1 行 `| v0.8 |` → `| v0.9 |` 的 Go template 註解標記，沒有任何 invariant 讀它，報告自己的 H7 也這麼說 — class 1 — 兩個檔各拆一列，標 unverified — status: fixed（本輪改寫 evidence report）
- [HIGH] `specs/spec-version-bump/SPEC.md:215` — 13 條 Must NOT 只有 12 條在報告的 Stated claim 表裡有列，「Must NOT 把 `approval: not obtained` 視為核准」沒有 — 逐條比對 `evidence.md:54-72` 的 17 列；`grep -c "not obtained"` 在 `tests/spec_archive_test.py` 與 `spec-archive.py` 都是 0 — class 1 — 補一列，狀態只能是 unverified — status: fixed（本輪改寫 evidence report）
- [MED] `.scratch/spec-version-bump/evidence.md:60` — 「§2 的十條解析規則 … pass」over-claim：§2 章節邊界那一條（層級 3 的 `### Approval` 裝不下分節式紀錄，SPEC `:112-114`，v2 才寫進去）沒有任何斷言 — `grep -n "heading=" tests/spec_archive_test.py` 只有 `:623` 一處，值是 `## 8. Approval record` — class 1 — 這一列降為 partial，點名沒覆蓋到的那一條 — status: fixed（本輪改寫 evidence report）
- [MED] `specs/spec-version-bump/SPEC.md:292` — 兩處計數與引用錯：after-spec 紀錄實測 `class 1/2/3 = {'1': 6, '2': 31, '3': 5}`，SPEC 寫 6/26/5；`:309-310` 把 13/10/5 記在 `d86b3dd`，該數字只在 `9205bd3` 之後成立 — class 1 — 兩處改成實測值與正確的 commit — status: fixed（`248c501`）

## Class 2 —— 記錄並修，不需要升版

- [MED] `.scratch/spec-version-bump/evidence.md:124` — 「兩支解析器 … 0 不一致」的控制強度被高估 — mapping-honesty 另造 10 個對抗輸入，其中 2 個不一致（未閉合圍欄；紀錄本文中一行裸 `#`） — class 2 — 把宣稱限定在那 27 個輸入上
- [LOW] `.scratch/spec-version-bump/evidence.md:78` — 這一列與 `:80` 指定用 `f3f6b2d` 與 `5bea393` 重跑，兩個 commit 從 HEAD 不可達也不在 origin 上 — `git merge-base --is-ancestor f3f6b2d HEAD` 為假，`5bea393` 同；只從本機 `backup/pre-marker-rebase` 可達；數字本身正確 — class 2 — 改引在分支上的 `2b6226a`／`2a93375`，備份 SHA 留在 H9
- [LOW] `.scratch/spec-version-bump/evidence.md:40` — 這一列與 `:60`、`:81` 用 `::S3b` 當測試名，測試檔裡沒有這個字串 — `grep -c S3b tests/spec_archive_test.py` → 0；斷言名是 `S3 the same ### v1.2 record does archive a v1.2 spec`（`:562`），只有 fixture scope 叫 `s3b`（`:561`） — class 2 — 改寫成 grep 得到的名字
- [LOW] `.scratch/spec-version-bump/evidence.md:135` — `gate-manifest-audit.sh` 在 Changed unit 表標 NOT REACHED，NOT REACHED 清單裡卻沒有它 — `tools/gate.sh:218-219` 在所有 `run_layer` 之後，mutation 失敗即不可達 — class 2 — 補進清單
- [LOW] `.scratch/spec-version-bump/evidence.md:37` — Changed unit 表少一列 `tests/spec_archive_test.py`：報告自己的 `changed_unit_command` 輸出 16 個檔案，表只對到 15 個 — `git diff 9a2e879..4110034 --name-only | wc -l` → 16；範本寫「Rows are derived from the diff, not chosen」 — class 2 — 補一列
- [LOW] `.scratch/spec-version-bump/evidence.md:115` — 「8 個手工 mutant」的括號只列得出 7 個描述 — class 2 — 把兩種圍欄拆開寫，讓數字與描述對得上
- [LOW] `.gate/spec-version-bump/source-state-before.txt:1` — 工作樹根目錄殘留一份中斷執行的產出，內容是 `5bea393`（改寫歷史前的 head），容易被下一位讀者誤當成 Gate 表的憑據 — 該檔為 `commit=5bea3937fe8ad71d946efb5b67230d2dbcadff13`，`layers-ran` 只有五層，mtime 10:31 早於 `4110034` 的 11:51 — class 2 — 封存前刪掉，`.gate/` 被 git 忽略，刪它不動來源狀態
- [LOW] `.scratch/spec-version-bump/evidence.md:8` — `change_set` 記到 `4110034`，HEAD 是 `05ca70a`，差別只有報告自己 192 行 — `git diff 9a2e879..HEAD --name-only | wc -l` → 17，比報告的指令多一個檔 — class 2 — 維持 `4110034`（gate 那一次的樹），在 `changed_unit_command` 旁註明報告自己不在該範圍內

- [LOW] `tests/check_agent_doc_invariants.py` — SPEC v2「本版新授權什麼」第 3 項寫「補一條 `require`」，實作補了兩條 — `git diff 9a2e879..HEAD -- tests/check_agent_doc_invariants.py` 新增 4 個呼叫、移除 0 個（2 `forbid` ＋ 2 `require`），90 → 94；SPEC 同一句的理由是「維持成對釘法」，成對就是兩條 — class 2 — 記進 evidence 的 H12，不改 SPEC 的核准文字；與 `.gitignore` 併入同一次人類決定

- [LOW] `.scratch/spec-version-bump/evidence.md:96` — Gate 表宣稱「`248c501` 的一次完整執行」，但那次執行的 `.gate/` 產出隨暫存 worktree 一併被移除，磁碟上無法佐證 — evidence-vs-git 透鏡在第二輪回報；我核對後確認 `.gate/` 目錄確實不存在，但該次執行的完整 stdout 仍在（記錄 `head: 248c501…`、`gate-mutants: 38/44`、六個存活 mutant 逐字相同），mtime 12:33 落在 `248c501`（12:28:45）與 `5eefcb0`（12:35:51）之間 — class 2 — 改寫 H15，寫明產出已不存在、只能重跑，並記下該透鏡除 mutation 外的獨立重現 — status: fixed（本輪改寫 evidence report）

## Class 3 —— 不在本次範圍，記進 Honest notes

- [MED] `dot_agents/skills/spec-archive/scripts/spec-archive.py:60` — 讀 front matter 版號的 `SPEC_VERSION_RE` 用 `\b` 結尾，`v1.2junk` → `v1`、`v1-rc1` → `v1`、`v1.` → `v1` — 實測四個輸入；base ref 的同一個常數逐字相同，本次未觸及 — class 3 — 記進 Honest notes
- [LOW] `tools/gate.sh:218` — manifest 稽核不經 `run_layer`，所以它自己不在 `layers-ran` 裡，也就無法稽核自己 — class 3 — 記進 Honest notes
- [LOW] `.scratch/spec-version-bump/evidence.md:100` — Gate 表的最終數字最後是靠 `~/.claude/jobs/638ca7ab/tmp/gaterun/.gate/` 的原始產出佐證，該目錄不在版控內 — evidence-vs-git 透鏡以同形入口重跑得到相同結果，含六個存活 mutant 的名稱，但同形不是同一次 — class 3 — 記進 Honest notes

## 透鏡之間的分歧與裁定

- **「39 個斷言轉紅」的真值**：mapping-honesty 得 3／4／3／7，evidence-vs-git 得
  4／3／7／8。兩者的插入點命名不同，數字對不起來。我自己以「R2 守衛前插 `die`」這個
  最自然的放法重跑，得 3 of 86，並把它寫進上面那條。三方都同意的只有一件事：不是 39。
- **變更集的檔案數**：mapping-honesty 說 16，我在 HEAD 量到 17。兩者都對——報告自己
  宣告的指令是 `git diff 9a2e879..4110034`（16 個），第 17 個是報告自己。上面拆成兩條記。
- **`.gitignore` 的處置**：evidence-vs-git 建議「補進授權清單或記進 Honest notes」，二擇
  一。我裁定記進 Honest notes：補進授權清單要升版與再核准，而這一行與本次的行為無關，
  值不回票價。

## 四個透鏡各自讓步的範圍

- **evidence-vs-git**：只比對報告宣稱與 git／可重跑的量測。SPEC 設計是否正確、R1／R2 的
  政策是否合理、squad 紀錄的內容與計數都不在範圍。本機同樣沒有 pwsh，L4／L7／L8 的
  PowerShell 部分跑不了。
- **mapping-honesty**：只查對照表與它宣稱的斷言對不對得上。沒有查 mutation 的 38/44 與
  六個存活 mutant 的等價性判定、supply-chain／pacman-ids／changed-lines 三層本身、
  `tests/run.sh` 的 739 條、`gate-properties.py` 的 329 個案例、L2–L11 的內容正確性。
- **verdict-state**：只回答「這個狀態能不能封存」。沒有查報告的逐條對照，也沒有查 SPEC
  的內容。
- **ledger-completeness**：只查 13 條 Must NOT、授權清單、時序與前兩個 cut 的 class-3
  發現有沒有落進 Honest notes。沒有重跑任何 gate 層。
