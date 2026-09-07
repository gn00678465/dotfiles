# L10 — 既有平台回歸。SPEC（archlinux-support）Must NOT #1：六個既有 fixture
# （linux、linux-arm64、darwin-arm64、darwin-amd64、windows、windows-arm64）的
# 渲染結果不得因為 Arch 支援而改變；managed 清單只准多出一支新腳本。
#
# 做法：把 base ref 的來源樹解到暫存目錄，兩邊各以同一個 fixture apply 一次到
# 各自的 destination（--exclude=scripts,externals：不執行任何腳本、不下載任何
# external），整棵樹 diff（S15）。腳本不會被 apply 落地，所以另外逐支渲染比對，
# 連同 .chezmoiignore、.chezmoiexternal.toml.tmpl、.chezmoi.toml.tmpl（S16）。
#
# base ref 從 SPEC 讀。SPEC 在 CLOSE 後會搬到 specs/archive/，兩個位置都找。

_BASE_REF=""
for _spec in "$REPO/specs/archlinux-support/SPEC.md" "$REPO/specs/archive/archlinux-support/SPEC.md"; do
    [ -f "$_spec" ] || continue
    _BASE_REF=$(sed -n 's/^- `base_ref`: `\([0-9a-f]*\)`.*/\1/p' "$_spec" | head -1)
    [ -n "$_BASE_REF" ] && break
done

if [ -z "$_BASE_REF" ]; then
    skip "既有平台回歸" "SPEC 裡讀不到 base ref"
elif ! git -C "$REPO" cat-file -e "$_BASE_REF^{commit}" 2>/dev/null; then
    skip "既有平台回歸" "base ref $_BASE_REF 不在這個 repo 裡"
else
    _base_src="$TMP/l10-base-src"
    mkdir -p "$_base_src"
    git -C "$REPO" archive "$_BASE_REF" | tar -x -C "$_base_src"

    # 與 lib.sh 的 cm() 相同，只是 source 可以指定。每個 (source, os) 組合有自己的
    # destination 與 persistent state。
    _cm_src() { # source tag os subcommand...
        _src=$1; _tag=$2; _os=$3; shift 3
        _cfg="$FIXTURES/os-$_os.toml"
        [ -f "$_cfg" ] || _cfg="$FIXTURES/$_os.toml"
        mkdir -p "$TMP/l10-dest-$_tag-$_os"
        chezmoi --source "$_src" --config "$_cfg" \
            --destination "$TMP/l10-dest-$_tag-$_os" \
            --persistent-state "$TMP/l10-state-$_tag-$_os.boltdb" \
            --no-tty "$@"
    }
    # 測試用的 --config 本來就不是 .chezmoi.toml.tmpl 產生的，chezmoi 每次都會
    # 提醒一次；那是預期中的，濾掉，其他任何輸出都算錯誤。
    _apply_filtered() { # source tag os
        _cm_src "$1" "$2" "$3" apply --exclude=scripts,externals 2>&1 \
            | grep -v 'config file template has changed' || true
    }

    for _os in linux linux-arm64 darwin-arm64 darwin-amd64 windows windows-arm64; do
        # ---- S15：檔案樹 ----
        _base_out=$(_apply_filtered "$_base_src" base "$_os")
        _new_out=$(_apply_filtered "$REPO" new "$_os")
        if [ -n "$_base_out" ]; then _fail "$_os：base ref apply 無錯誤" "$_base_out"; else _pass "$_os：base ref apply 無錯誤"; fi
        if [ -n "$_new_out" ]; then _fail "$_os：目前來源 apply 無錯誤" "$_new_out"; else _pass "$_os：目前來源 apply 無錯誤"; fi
        _diff=$(diff -r "$TMP/l10-dest-base-$_os" "$TMP/l10-dest-new-$_os" 2>&1) || true
        assert_eq "$_os：套用結果與 base ref 逐位元組相同（S15）" "" "$_diff"

        # ---- S16：腳本與其他模板的渲染 ----
        # 基準：base ref 有的每一支腳本，新來源都要渲染出同樣的位元組。
        for _f in "$_base_src"/.chezmoiscripts/*; do
            _s=$(basename "$_f")
            if [ ! -f "$REPO/.chezmoiscripts/$_s" ]; then
                _fail "$_os：腳本 $_s 仍存在" "base ref 有這支腳本，目前來源沒有"
                continue
            fi
            _cm_src "$_base_src" base "$_os" execute-template < "$_f" > "$TMP/l10-r-base" 2>&1 || true
            _cm_src "$REPO" new "$_os" execute-template < "$REPO/.chezmoiscripts/$_s" > "$TMP/l10-r-new" 2>&1 || true
            assert_bytes_eq "$_os：$_s 的渲染與 base ref 逐位元組相同（S16）" "$TMP/l10-r-base" "$TMP/l10-r-new"
        done
        for _t in .chezmoiignore .chezmoiexternal.toml.tmpl .chezmoi.toml.tmpl; do
            # .chezmoi.toml.tmpl 會把 .chezmoi.sourceDir 寫進 sourceDir = ...，兩邊的
            # source 路徑本來就不同，那一行濾掉；其餘位元組仍逐一比對。
            _cm_src "$_base_src" base "$_os" execute-template < "$_base_src/$_t" 2>&1 \
                | grep -v '^sourceDir = ' > "$TMP/l10-r-base" || true
            _cm_src "$REPO" new "$_os" execute-template < "$REPO/$_t" 2>&1 \
                | grep -v '^sourceDir = ' > "$TMP/l10-r-new" || true
            assert_bytes_eq "$_os：$_t 的渲染與 base ref 逐位元組相同（S16）" "$TMP/l10-r-base" "$TMP/l10-r-new"
        done

        # ---- managed 清單：只准多出一支新腳本，不准少任何東西 ----
        _cm_src "$_base_src" base "$_os" managed --exclude=externals | LC_ALL=C sort > "$TMP/l10-mg-base"
        _cm_src "$REPO" new "$_os" managed --exclude=externals | LC_ALL=C sort > "$TMP/l10-mg-new"
        _added=$(comm -13 "$TMP/l10-mg-base" "$TMP/l10-mg-new")
        _removed=$(comm -23 "$TMP/l10-mg-base" "$TMP/l10-mg-new")
        assert_eq "$_os：managed 只多出 30-install-pacman-packages.sh" \
            '.chezmoiscripts/30-install-pacman-packages.sh' "$_added"
        assert_eq "$_os：managed 沒有任何 target 消失" "" "$_removed"
    done
fi

unset _BASE_REF _spec _base_src _os _base_out _new_out _diff _f _s _t _added _removed
