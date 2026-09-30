#!/bin/sh
# Drive the zsh startup files rendered from this checkout in a throwaway HOME.
#
#   zsh-probe.sh up                      create a run, print its directory
#   zsh-probe.sh doctor <run>            is this run worth driving?
#   zsh-probe.sh drive <run> <label> <mode> [cmd]
#   zsh-probe.sh local <run> absent|quiet|noisy|failing
#   zsh-probe.sh check <run>             the standard scenario set, PASS/FAIL
#   zsh-probe.sh down <run>              delete the HOME, keep the evidence
#
# The real HOME is never read by the shells under test. The throwaway HOME lives
# under /tmp, not in the checkout, because mise looks for .config/mise/ in every
# ancestor of the working directory and would pick up the real ~/.config/mise.
# Oh My Zsh and the gitstatusd binary are copied in because the rendered .zshrc
# sources them, and a missing gitstatusd makes powerlevel10k download one.
set -eu

REPO=$(CDPATH= cd -- "$(dirname -- "$0")/../../../.." && pwd)
GATE="$REPO/.gate/verify-dotfiles"
MINPATH=/usr/local/bin:/usr/bin:/bin

die() { printf 'zsh-probe: %s\n' "$*" >&2; exit 2; }

run_dir() {
    [ $# -ge 1 ] || die "missing <run>"
    [ -f "$1/home-path" ] || die "$1 is not a live run. Run 'up' for a new one."
    RUN=$(CDPATH= cd -- "$1" && pwd); H=$(cat "$RUN/home-path"); EV="$RUN/evidence"
    [ -d "$H" ] || die "$H is gone. Run 'up' for a new run."
}

render_into() { # target-name dest
    chezmoi -S "$REPO" cat "$HOME/$1" > "$2" || die "chezmoi cat ~/$1 failed"
}

cmd_up() {
    command -v chezmoi >/dev/null || die "chezmoi not on PATH"
    [ -d "$HOME/.oh-my-zsh" ] || die "no ~/.oh-my-zsh to copy; apply the externals first"
    mkdir -p "$GATE"
    RUN=$(mktemp -d "$GATE/$(date +%Y%m%d-%H%M%S)-XXXX")
    H=$(mktemp -d "${TMPDIR:-/tmp}/verify-dotfiles-home.XXXXXX")
    printf '%s\n' "$H" > "$RUN/home-path"; mkdir -p "$H/.cache" "$RUN/evidence"
    for f in .zshrc .zprofile .p10k.zsh; do render_into "$f" "$H/$f"; done
    cp -a "$HOME/.oh-my-zsh" "$H/.oh-my-zsh"
    [ ! -d "$HOME/.cache/gitstatus" ] || cp -a "$HOME/.cache/gitstatus" "$H/.cache/gitstatus"
    git -C "$REPO" rev-parse HEAD > "$RUN/evidence/source-rev"
    git -C "$REPO" diff --stat -- dot_zshrc.tmpl dot_zprofile.tmpl dot_p10k.zsh >> "$RUN/evidence/source-rev"
    printf '%s\n' "$RUN"
}

cmd_doctor() {
    run_dir "$@"; ok=0
    for f in .zshrc .zprofile .p10k.zsh; do
        render_into "$f" "$RUN/.fresh"
        if cmp -s "$RUN/.fresh" "$H/$f"; then printf 'ok    %s matches the current source\n' "$f"
        else printf 'STALE %s differs from the current source; run down + up\n' "$f"; ok=1; fi
    done
    rm -f "$RUN/.fresh"
    [ -r "$H/.oh-my-zsh/oh-my-zsh.sh" ] && echo "ok    oh-my-zsh copy present" || { echo "FAIL  oh-my-zsh copy missing"; ok=1; }
    [ "$H" != "$HOME" ] && echo "ok    HOME under test is $H" || { echo "FAIL  HOME under test is the real HOME"; ok=1; }
    printf 'info  %s\n' "$(zsh --version)"
    return $ok
}

# The environment a display manager or ssh gives a fresh session. `inherit`
# adds what a Hyprland/uwsm session exports, which terminal emulators pass on.
zenv() { # mode-path cmd...
    _p=$MINPATH
    [ "$1" != inherit ] || _p="$MINPATH:$H/.local/share/mise/shims:$H/.local/bin"
    shift
    (cd "$H" && env -i HOME="$H" USER="${USER:-$(id -un)}" LOGNAME="${USER:-$(id -un)}" \
        SHELL="$(command -v zsh)" TERM=xterm-256color LANG="${LANG:-C.UTF-8}" \
        PATH="$_p" "$@")
}

# Modes: login (zsh -l -c, no terminal), interactive (zsh -i -c),
# login-interactive (zsh -l -i -c), inherit (zsh -i -c from a session PATH),
# pty (a terminal session that reaches the prompt and exits).
cmd_drive() {
    run_dir "$1"; label=$2; mode=$3; cmd=${4:-'print -r -- "RC=$?"'}
    out="$EV/$label"
    case $mode in
        login)             flags=-lc ;;
        interactive)       flags=-ic ;;
        login-interactive) flags=-lic ;;
        inherit)           flags=-ic ;;
        pty)               flags= ;;
        *) die "unknown mode: $mode" ;;
    esac
    printf 'mode=%s\ncmd=%s\nzshrc.local=%s\n' "$mode" "$cmd" \
        "$(cat "$H/.zshrc.local" 2>/dev/null || echo '<absent>')" > "$out.cmd"
    if [ "$mode" = pty ]; then
        # p10k writes its instant-prompt cache only after the first prompt is
        # drawn; input sent earlier ends the session before that happens.
        cache="$H/.cache/p10k-instant-prompt-${USER:-$(id -un)}.zsh"
        { i=0; while [ ! -e "$cache" ] && [ $i -lt 50 ]; do sleep 0.2; i=$((i + 1)); done
          sleep 1; printf '%s\nexit\n' "$cmd"; } |
            zenv pty script -qfec 'zsh -i' /dev/null > "$out.out" 2> "$out.err" && rc=0 || rc=$?
    elif [ "$mode" = login ]; then
        zenv "$mode" zsh "$flags" "$cmd" > "$out.out" 2> "$out.err" && rc=0 || rc=$?
    else
        # An interactive shell always has a terminal. Without one, p10k's
        # gitstatus fails `setopt monitor` and writes errors no user sees.
        zenv "$mode" ZP_CMD="$cmd" ZP_ERR="$out.err" \
            script -qfec "zsh $flags \"\$ZP_CMD\" 2>\"\$ZP_ERR\"" /dev/null < /dev/null \
            > "$out.raw" && rc=0 || rc=$?
        tr -d '\r' < "$out.raw" > "$out.out"; rm -f "$out.raw"
    fi
    printf '%s\n' "$rc" > "$out.rc"
    printf '%s  rc=%s  %s\n' "$label" "$rc" "$out.out"
}

cmd_local() {
    run_dir "$1"
    case $2 in
        absent)  rm -f "$H/.zshrc.local" ;;
        quiet)   printf 'export LOCAL_MARK=1\nalias ll="ls -l"\n' > "$H/.zshrc.local" ;;
        noisy)   printf 'echo hello-from-local\n' > "$H/.zshrc.local" ;;
        failing) printf 'false\n' > "$H/.zshrc.local" ;;
        *) die "unknown .zshrc.local variant: $2" ;;
    esac
}

cmd_check() {
    run_dir "$1"; fails=0; sum="$EV/summary.txt"; : > "$sum"
    verdict() { # name detail cmd...
        _n=$1; _d=$2; shift 2
        if "$@"; then r=PASS; else r=FAIL; fails=$((fails + 1)); fi
        printf '%s  %s  (%s)\n' "$r" "$_n" "$_d" | tee -a "$sum"
    }
    dupes() { tr ':' '\n' < "$EV/$1.out" | grep -v '^RC=' | sort | uniq -d | tr '\n' ' '; }
    has() { grep -aq -- "$2" "$EV/$1.out"; }
    lacks() { ! has "$@"; }
    empty() { [ -z "$1" ]; }
    noerr() { [ ! -s "$EV/$1.err" ]; }

    # Every scenario runs with the instant-prompt cache that a user's first
    # terminal session writes; p10k takes a different path without it.
    cmd_local "$RUN" absent
    cmd_drive "$RUN" p10k-warmup pty 'true' > /dev/null

    pathcmd='print -r -- "RC=$?"; print -r -- "$PATH"'
    for m in interactive login-interactive login inherit; do
        cmd_drive "$RUN" "path-$m" "$m" "$pathcmd" > /dev/null
        d=$(dupes "path-$m")
        verdict "path-$m has no duplicate PATH entries" "dupes: ${d:-none}" empty "$d"
        verdict "path-$m startup writes nothing to stderr" "$EV/path-$m.err" noerr "path-$m"
    done
    verdict "status is 0 after .zshrc with no .zshrc.local" "$(head -1 "$EV/path-interactive.out")" \
        has path-interactive 'RC=0'

    cmd_drive "$RUN" mise-interactive interactive 'whence -w _mise_hook; whence -p mise' > /dev/null
    verdict "interactive shell has the mise hook" "$EV/mise-interactive.out" has mise-interactive '_mise_hook: function'
    cmd_drive "$RUN" mise-login login 'print -r -- "$PATH"; whence -p mise' > /dev/null
    verdict "login shell has the mise shims on PATH" "$EV/mise-login.out" has mise-login '/.local/share/mise/shims'

    cmd_local "$RUN" quiet
    cmd_drive "$RUN" local-quiet interactive 'print -r -- "RC=$? LOCAL_MARK=$LOCAL_MARK"; alias ll' > /dev/null
    local_ok() { has local-quiet 'RC=0 LOCAL_MARK=1' && has local-quiet "ll='ls -l'"; }
    verdict ".zshrc.local is sourced and keeps status 0" "$(head -1 "$EV/local-quiet.out")" local_ok

    cmd_local "$RUN" noisy
    cmd_drive "$RUN" p10k-noisy pty 'true' > /dev/null
    verdict "p10k warns when .zshrc.local prints (detector works)" "$EV/p10k-noisy.out" \
        has p10k-noisy 'Console output during zsh initialization'
    cmd_local "$RUN" absent
    cmd_drive "$RUN" p10k-clean pty 'true' > /dev/null
    verdict "p10k does not warn on a clean startup" "$EV/p10k-clean.out" \
        lacks p10k-clean 'Console output during zsh initialization'

    printf '%s failed\n' "$fails" | tee -a "$sum"
    [ "$fails" -eq 0 ]
}

cmd_down() {
    run_dir "$@"
    case $H in "${TMPDIR:-/tmp}"/verify-dotfiles-home.*) rm -rf "$H" ;; *) die "refusing to delete $H" ;; esac
    rm -f "$RUN/home-path"
    printf 'removed %s; evidence kept in %s\n' "$H" "$EV"
}

[ $# -ge 1 ] || die "usage: zsh-probe.sh up|doctor|drive|local|check|down ..."
sub=$1; shift
case $sub in
    up) cmd_up ;; doctor) cmd_doctor "$@" ;; drive) cmd_drive "$@" ;;
    local) cmd_local "$@" ;; check) cmd_check "$@" ;; down) cmd_down "$@" ;;
    *) die "unknown subcommand: $sub" ;;
esac
