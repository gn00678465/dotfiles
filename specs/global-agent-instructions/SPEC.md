# SPEC — 精簡全域代理指示並修正驗證交接 (Tier 2)

- `spec_version`: v2
- `status`: approved
- `tier`: 2
- `scope`: global-agent-instructions
- `base_ref`: `e0d3e0e721dd6a01120a9b516f9c9fcfa57ab751`
- `branch`: `fix/global-agent-instructions`
- 實作者：Herdr Sonnet 窗格 `w1:p3`。
- 驗證者：Codex 與 Herdr Fable 窗格 `w1:p1`；先各自記錄結果，再交換比對。

## Intent

使用者要求分析並修正本專案會部署到全域的 instructions，由 Sonnet 實作，Codex 與 Fable 驗證實作者的驗證結果。使用者不需要閱讀原始碼；預期行為由本 SPEC 記錄，實際證據由最後的 evidence 報告記錄。

修正已觀察到的文字矛盾、重複確認與證據交接缺口，然後原地精簡常駐指示。保留兩個全域入口共用單一模板的架構，以及 evidence-first 的高保證約束。Tier 2 加上使用者指定的雙方獨立驗證。

## Scenarios

這次的產品包含自然語言指示。下列「指示要求」驗證的是文件契約與具體情境的一致性，不聲稱文字測試能證明模型實際遵守指示。可執行介面另以真實命令驗證。每個情境須對應具名檢查，報告區分機械檢查與人工語意審閱。

### S1 — 全域入口一致且縮短

- 輸入：使用既有平台測試接縫，分別以 linux、darwin、windows 算繪 Codex 與 Claude 的全域指示入口。
- 預期：同平台兩份內容相同，契約只出現一次；來源仍是既有共用模板。每份常駐內容不超過 600 個空白分隔詞（本機基準為 793）；不以省略必要約束換取字數。
- 檢查：具名模板算繪檢查、基準與候選的詞數比較，以及 S2 的語意檢查。

### S2 — 契約核心保留

- 輸入：一般文件修正，以及涉及 money、auth、data loss、concurrency、public API 或使用者明確要求高保證的任務。
- 預期：一般任務不自動啟動完整契約；原有高保證觸發條件仍有效。保留規格核准綁定版本、核准紀錄、tests-first 提交、RED、tier、防止削弱測試、失敗不得宣稱完成，以及未取得證據時揭露降級。
- 預期：`specs/<scope>/SPEC.md`、既有狀態值、spec-archive 交接與報告欄位仍相容。精簡理由與例子，不先搬動契約來源檔案。
- 檢查：`tests/check_agent_doc_invariants.py` 的既有約束與新增負向控制；兩位驗證者依本情境核對縮寫前後語意。

### S3 — 已核准工作不重問，未授權工作仍確認

- 輸入 A：有效的已提交 approved SPEC，tier、scope、intent 與 setup plan 都明確包含本次 gate 檔案及工具。
- 預期 A：verification-gate 沿用 SPEC 與既有授權，不重新詢問 intent、tier 或同一 setup 工作。
- 輸入 B：gate 單獨使用且沒有可確認的 intent，或需要超出既有授權的新依賴、需求變更。
- 預期 B：只詢問缺少的必要資訊或授權；不把一般回答、啟動流程或逾時當成指定 SPEC 版本的核准。
- 檢查：具名文件契約檢查及 A/B 情境語意審閱。核對基準版 `verification-gate/SKILL.md` 的 scaffold（第 53 行）、Inputs（第 65、73–74 行）、intent 問題（第 151 行）、寫入路徑（第 470 行）與工具安裝（第 646 行）等位置：沿用有效授權，不保留與此例外衝突的無條件確認句。不得以動態代理測試已通過的措辭描述此結果。

### S4 — 證據產生端完整交付封存所需資料

- 輸入：已核准並提交的 SPEC，以及按全域證據範本填入、引用該 SPEC 的 final evidence。暫存測試使用 v1/v2 固定資料；真實交付使用核准 SPEC 的實際版本。
- 預期：gate 指示明確要求從已提交 SPEC 導出 intent 與版本；報告帶有封存程式接受的整段反引號標記，例如 `spec_version: v1`，且等於所引用 SPEC 的版本。工作流程在 CLOSE 前提交 `.scratch/<scope>/evidence.md`，不讓兩個候選位置同時留有受追蹤證據。
- 預期：在暫存 Git 專案中，依實際範本填好的有效 evidence 可由既有封存程式成功處理。缺少版本、版本不符、未提交或重複候選的既有拒絕仍有效。
- 檢查：擴充 `tests/spec_archive_test.py`，使用實際 evidence 範本與既有封存程式跑正向與負向情境；禁止只測一段與範本無關的手寫字串。

### S5 — CLOSE 時機一致

- 輸入：final evidence 已提交且驗證完成、任務分支尚未合併。
- 預期：流程圖、Phase 6 與 spec-archive 指示一致要求合併前 CLOSE，作為任務分支的最後一次提交。不得保留正常流程「after merge: CLOSE」的舊說明。
- 檢查：具名跨文件一致性檢查；`tests/spec_archive_test.py` 的既有成功與拒絕情境。

### S6 — 提交指示遵守單次執行與邏輯原子性

- 輸入 A：使用者已要求提交 staged 變更，commit 指令成功。
- 預期 A：回報完成，不在執行後再詢問是否協助執行同一命令。
- 輸入 B：一項功能與該功能必需的依賴變更具有不同 commit type；兩群無法各自建置或獨立還原。
- 預期 B：不僅因 type 不同或分數高就強制拆散。可獨立建置與還原的不同邏輯變更才建議拆分。保留只提交已暫存範圍及既有分支保護，不自動 reset 使用者的 staging。
- 檢查：具名文件契約檢查與 A/B 情境語意審閱；本次不改 commit 分析腳本及訊息規範版本。

### S7 — 工程與寫作規則具體且有適用範圍

- 輸入 A：不需要跨程序恢復的簡單修正。
- 預期 A：不因全域規則要求而新加持久化狀態；需要持久化恢復、並行寫入及必要副作用的安全約束仍保留。
- 輸入 B：根因經多輪才找到，最後差異含探索殘留。
- 預期 B：移除探索殘留，保留根因修正、既有模式及非顯而易見理由的註解；合併重複解釋。
- 輸入 C：需要繁體中文回覆，但 zhtw-mcp 不可用。
- 預期 C：使用臺灣繁體中文、短句與明確動詞；不為這個工具新增阻擋、安裝或假稱已查核。工具可用且用語不確定時才查詢。程式碼、識別字與必要技術名詞保留。
- 檢查：具名文件契約檢查及 A/B/C 語意審閱。指示來源沿用既有英文撰寫方式，報告與 SPEC 使用繁體中文。

### S8 — 校準測試與重構指示

- 輸入：單一行為的 RED/GREEN 迴圈，受影響測試已通過，最後 gate 尚未執行。
- 預期：允許先跑受影響測試；測試套件足夠快時仍可全跑。最後 gate 執行全部適用檢查，不因局部通過宣稱整體完成。其他行為的回歸可能延後到 gate 才被發現，需照實揭露。
- 預期：刪除「函式需要一段解釋就拆開」的主觀準則；依職責、實際重複與已宣告約束判斷，不新增抽象以滿足文字規則。
- 檢查：具名文件契約檢查及語意審閱；本次 gate 的實際完整執行紀錄。

### S9 — 本次證據屬於本次 scope 與來源狀態

- 輸入：本 SPEC 的 scope、base ref 與 Sonnet 交付的候選 commit。
- 預期：驗證入口將本次產物寫入 `.gate/global-agent-instructions/`，intent 指向本 SPEC；不重用或覆寫 `.gate/windows-support/`，不誤用歷史 awk 移植基準。
- 預期：驗證前後來源狀態一致。層失敗時入口非零結束；未執行、不適用或缺少工具的層不呈現為通過。
- 檢查：單一入口的成功與失敗控制、manifest／實際層比對及來源狀態檢查。

## Must NOT

- 不直接修改真實家目錄、不執行 chezmoi apply、不修改或推送 main。
- 不為縮短文件而刪除高保證觸發、規格核准、RED、反造假、隔離或失敗拒絕要求。
- 不弱化既有測試、不刪除負向控制、不調整封存程式以接受錯誤報告；範本遵守既有封存格式。
- 不調整平台選擇、安裝工具清單、modify-template 演算法、verifier 協定或 commit 分析腳本。
- 不把自然語言字串檢查當成代理模型行為已被證明；本次不宣稱減少提問次數、延遲或 token 的實測效果。
- 不加入新套件、測試框架或外部服務；不擴充與上述情境無關的文件稽核。
- 不把既有驗證結果套用到未驗證的新來源狀態；實作者改動後重驗受影響項目。

## Setup plan

- Tools to install: none。使用既有 Git、chezmoi、uv 管理的 Python、可用 POSIX/WSL 工具；工具不存在須記錄，不能假稱執行。
- New dependencies: none。
- Git isolation: Sonnet 在 `D:/Projects/dotfiles-dev/dotfiles-global-agent-instructions` 的任務 worktree 單一寫入。Codex 與 Fable 在候選 commit 的各自隔離副本執行破壞性負向控制。原始 main 工作目錄維持不變。
- Sonnet 工作目錄：若 Claude 出現跨工作目錄讀取視窗，取消該次讀取並只將本任務 worktree 加入允許的工作目錄；不設定永久允許所有專案的外部讀取。本項納入使用者核准的設定範圍。
- Checkpoint cadence: 核准紀錄與 SPEC 一起提交；每組行為先提交已觀察失敗的測試，再提交對應實作。純文字語意由明確場景審閱補足，不捏造 RED。已存在行為的新保護測試需以隔離負向控制證明可失敗。
- 實作可修改：`.chezmoitemplates/agent-instructions.md`、`.chezmoitemplates/evidence-first-contract.md`、`dot_agents/workflows/evidence-first.md`、`dot_agents/skills/verification-gate/SKILL.md`、其 `references/entry-point.md` 與 `assets/templates/evidence.md`、`dot_agents/skills/commit/SKILL.md`。`docs/evidence-first.md` 僅同步本次 Phase 4 交接與 gate 入口說明；既有 spec-archive 技能與程式不修改。
- 測試可修改：`tests/check_agent_doc_invariants.py`、`tests/spec_archive_test.py`；必要時新增 `tests/agent_instructions_test.py`，容納模板算繪與具名契約檢查。保留原有檢查能力，文字更名不得掩蓋語意降級。
- Gate 接線：新增 stdlib 入口 `tools/gate-agent-instructions.py`，重用既有檢查；不改寫 `tools/gate.sh` 的歷史 Windows 移植假設。正式命令為 `uv run --no-project python tools/gate-agent-instructions.py --base e0d3e0e721dd6a01120a9b516f9c9fcfa57ab751`。scope 固定為本任務，不新增通用組態框架。
- Gate 接線可直接呼叫既有 `sh tools/gate-intent.sh global-agent-instructions` 與其他相容檢查，不重寫其解析器。執行通道使用已存在的 Git for Windows `sh.exe` 或可用 WSL；每個必要工具都先確認可執行，不能僅因檔名存在就宣稱可用。
- Gate 必須包含：SPEC/基準/來源狀態、跨文件一致性、真實範本與封存相容性、全平台指示算繪、適用既有測試、具體負向控制及層執行紀錄。一般指示的語意審閱由 Codex/Fable 紀錄，不包裝為自動化語意證明。
- Evidence：Sonnet 先交付 gate 結果與各 RED/GREEN commit。兩位驗證者各自記錄後才取得實作者報告並交換結果。最後一次修正後由 verification-gate 的 `evidence` 產生最終報告，提交到 `.scratch/global-agent-instructions/evidence.md`；比對紀錄提交到同目錄的 `verification.md`。
- 驗證回合：先執行兩輪上限；有未解決失敗則不得宣稱完成。來源狀態固定後才封存 SPEC。合併前交付具體結果，不自動推送遠端。
- 本次交付物：核准 SPEC、測試與實作提交、gate 入口、RED 紀錄、final evidence、兩位驗證者的獨立結果與差異處理紀錄。

## Approval

- 2026-09-06 — approves v2 — "我核准 global-agent-instructions 的 SPEC v2，包括 S1S9、Must NOT 與 Setup plan。"
- 核准後由協調者新增 `YYYY-MM-DD — approves <spec_version> — "<使用者原文>"` 紀錄，將 status 設為 approved 並與 SPEC 同次提交。此說明不是核准紀錄；版本修訂重新取得核准。
- 2026-09-06 — 流程啟動授權（非本 SPEC 的版本核准）：使用者原文「OK, claude-sonnet 已經 idel, 可以開始進行」。該訊息發生於本文件建立前，不記為 approved。

## Revisions

- 2026-09-06 — v1 草稿：依 Codex/Fable 的兩輪討論與使用者指定的 Sonnet 實作、雙方驗證流程建立；加入 gate scope 的前置檢查需求。
- 2026-09-06 — v2：依 Fable 前置審閱定案獨立 gate 路徑、600 詞上限、正式核准紀錄格式及確認規則位置；釐清固定測試版本與真實 SPEC 版本，納入必要文件同步與 Sonnet 單一 worktree 的工作目錄設定。
