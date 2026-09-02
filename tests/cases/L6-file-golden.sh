# L6 — 檔案層的 golden，重點在 Tier 3 的資料保全（SPEC M4/M5）。
#
# 做法：把種子檔塞進一個乾淨的暫存 destination，跑真正的
# `chezmoi apply --exclude=scripts,externals`（不執行腳本、不下載 external），
# 再把 ~/.codex/config.toml 與 ~/.claude/settings.json 跟 golden 逐位元組比對。
#
# codex 的 golden 是從 base ref 的 awk 實作跑出來的 —— 那份實作就是這次移植的契約
# 本身，所以「新實作要產生一模一樣的位元組」正是要證的事。

_l6_apply() { # os case dest
    rm -rf "$3"; mkdir -p "$3"
    cp -a "$REPO/tests/fixtures/l6/$2/home/." "$3/"
    chezmoi --source "$REPO" --config "$FIXTURES/os-$1.toml" --destination "$3" \
            --persistent-state "$3.state" --no-tty apply --exclude=scripts,externals 2>&1 \
        | grep -v 'config file template has changed' || true
}

for _c in $(ls "$REPO/tests/fixtures/l6"); do
    # ---- codex：跨平台同一份實作，輸出必須完全一樣 ----
    _d_lin="$TMP/l6-linux-$_c"
    _out=$(_l6_apply linux "$_c" "$_d_lin")
    if [ -n "$_out" ]; then _fail "$_c linux apply 無錯誤" "$_out"; else _pass "$_c linux apply 無錯誤"; fi
    assert_eq "$_c: ~/.codex/config.toml（linux）" \
        "$(cat "$GOLDEN/l6/$_c/.codex/config.toml")" "$(cat "$_d_lin/.codex/config.toml" 2>&1)"
    assert_eq "$_c: ~/.claude/settings.json（linux）" \
        "$(cat "$GOLDEN/l6/$_c/.claude/settings.json")" "$(cat "$_d_lin/.claude/settings.json" 2>&1)"

    _d_win="$TMP/l6-windows-$_c"
    _out=$(_l6_apply windows "$_c" "$_d_win")
    if [ -n "$_out" ]; then _fail "$_c windows apply 無錯誤" "$_out"; else _pass "$_c windows apply 無錯誤"; fi
    assert_eq "$_c: ~/.codex/config.toml（windows，必須與 linux 同一份輸出）" \
        "$(cat "$GOLDEN/l6/$_c/.codex/config.toml")" "$(cat "$_d_win/.codex/config.toml" 2>&1)"
    assert_eq "$_c: ~/.claude/settings.json（windows）" \
        "$(cat "$GOLDEN/l6/$_c/settings.windows.json")" "$(cat "$_d_win/.claude/settings.json" 2>&1)"
done

# 上面那些 apply 是在 Linux 上跑的，所以就算 modify_ 是一支 sh 腳本也會過。
# Windows 上真正的守門條件是：chezmoi 不可以去 exec 它。chezmoi 對 modify_ 的處理是
# 「先算繪成模板；若算繪結果以 chezmoi:modify-template 開頭，就直接當成新內容，
# 完全不執行」。所以這一條結構性斷言，才是 codex 設定能在 Windows 上運作的理由。
# （真的在 Windows 上跑一次是 L8。）
for _m in dot_codex/modify_private_config.toml dot_claude/modify_settings.json; do
    _first=$(head -1 "$REPO/$_m")
    assert_contains "$_m 是 modify-template（Windows 上不會被 exec）" \
        "$_first" "chezmoi:modify-template"
    assert_not_contains "$_m 不得是 shell 腳本" "$_first" "#!"
done

unset _c _d_lin _d_win _out _m _first
