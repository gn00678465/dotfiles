#!/bin/sh
# End-to-end check inside a throwaway Linux environment (test layer L9, the
# POSIX half of tests/sandbox/_probe.ps1).
#
# The sandbox is the only place a real install is allowed to run: the host is
# off limits. Everything here runs against a machine that is thrown away
# afterwards -- a debian:12 container (tests/sandbox/docker.sh) or a fresh WSL
# distro (tests/sandbox/wsl.sh). Only the WSL one has systemd, so the checks
# that need logind report SKIP in the container rather than a PASS they did
# not earn.
#
# Two modes, mirroring the Windows probe.
#
# Local (no --branch): the source tree is /src/dotfiles, put there by the
# launcher from `git archive HEAD`, and output goes to /out. chezmoi is
# installed the way init.sh installs it and then pointed at that tree with
# `chezmoi init --apply --source`.
#
# Remote (--branch <name>): nothing is mounted. The probe runs init.sh from
# GitHub with --branch, exactly the line a first-time user runs, and every
# expected value is read from `chezmoi source-path` afterwards.
#
# Unlike the Windows probe this one does not stop after the first install: the
# things this repo got wrong were all on the *second* run -- `chezmoi update`
# dying on a missing /run/user/<uid>, a removed neovim never coming back -- so
# the probe goes on to a second apply, `chezmoi git`, and a remove-and-reinstall
# round.
#
# Output survives only through /out (or $HOME/chezmoi-probe when /out is not
# mounted) and the results table echoed to the console at the end.
set -u

branch=""
while [ $# -gt 0 ]; do
    case "$1" in
        --branch) [ $# -ge 2 ] || { echo "probe: --branch needs a value" >&2; exit 2; }
                  branch=$2; shift 2 ;;
        --branch=*) branch=${1#*=}; shift ;;
        *) echo "probe: unknown argument: $1" >&2; exit 2 ;;
    esac
done
remote=0
[ -n "$branch" ] && remote=1

# /out only counts when the launcher mounted it: a directory this script made
# itself dies with the sandbox.
out_dir=/out
if [ ! -d "$out_dir" ] || [ ! -w "$out_dir" ]; then
    out_dir="$HOME/chezmoi-probe"
fi
mkdir -p "$out_dir"
transcript="$out_dir/transcript.txt"
results="$out_dir/results.tsv"
treesitter_log="$out_dir/treesitter.log"

# Transcript: re-exec once with everything piped through tee. POSIX sh has no
# process substitution, and the exit status has to come back through a file
# because a pipeline's status is tee's.
if [ -z "${PROBE_TRANSCRIPT:-}" ]; then
    rc_file="$out_dir/.rc"
    rm -f "$rc_file"
    { PROBE_TRANSCRIPT=1 sh "$0" ${branch:+--branch "$branch"}; echo $? > "$rc_file"; } 2>&1 | tee "$transcript"
    rc=$(cat "$rc_file" 2>/dev/null || echo 1)
    rm -f "$rc_file"
    exit "$rc"
fi

# check() captures a test function's stdout as the result detail, so anything
# a long step wants the operator to see while it runs has to bypass that
# capture. fd 3 is the console, saved here before any capture starts.
exec 3>&1

: > "$results"
echo "probe: mode=$([ $remote = 1 ] && echo "remote branch $branch" || echo local) out_dir=$out_dir"
echo "probe: $(uname -srm); $(cat /etc/debian_version 2>/dev/null || echo 'not debian'); glibc $(ldd --version 2>/dev/null | head -1 | sed 's/.* //')"

# Which package path the dotfiles take on this machine, decided the way
# platform.toml decides it: ID= in /etc/os-release. Everything below that
# differs between Debian (apt + Homebrew + mise-pinned neovim) and Arch (pacman
# only, omarchy's own LazyVim) keys off this one flag.
distro=$(. /etc/os-release 2>/dev/null && printf '%s' "${ID:-}")
arch=0; [ "$distro" = arch ] && arch=1
echo "probe: distro=${distro:-unknown}; path=$([ $arch = 1 ] && echo 'pacman (Arch)' || echo 'apt + Homebrew')"

add_result() { # status name detail
    _line=$(printf '%s\t%s\t%s' "$1" "$2" "$(printf '%s' "$3" | tr '\n' '|' | tr -s '|' | sed 's/|/ | /g')")
    echo "$_line"
    printf '%s\n' "$_line" >> "$results"
}

# check NAME FUNC: FUNC prints its detail (or the failure reason) and returns
# non-zero on failure. Nothing here has a tty, so anything that would prompt
# is a FAIL, which is the point.
check() {
    _name=$1; shift
    if _detail=$("$@" 2>&1); then add_result PASS "$_name" "$_detail"
    else add_result FAIL "$_name" "$_detail"; fi
}
skip() { add_result SKIP "$1" "$2"; }

# Long steps stream their output as it happens -- a silent console is
# indistinguishable from a hang -- and keep a copy so a failure's detail can
# carry the tail, which is the only thing that survives remote mode.
run_streamed() { # logfile command...
    _log=$1; shift
    { "$@"; echo $? > "$_log.rc"; } 2>&1 | tee "$_log" >&3
    _rc=$(cat "$_log.rc"); rm -f "$_log.rc"
    return "$_rc"
}
output_tail() { # logfile [lines]
    [ -s "$1" ] || { echo '(no output)'; return; }
    grep -v '^[[:space:]]*$' "$1" | tail -n "${2:-30}"
}

# The probe starts before anything is installed, so nothing the install adds
# to a login shell's PATH is visible here. Rebuild it from the same three
# places the dotfiles use (.zprofile: ~/.local/bin, brew shellenv, mise shims)
# and report what was found, so a "not found" later is readable.
path_report=""
update_probe_path() {
    _found=""
    for _d in "$HOME/.local/bin" /home/linuxbrew/.linuxbrew/bin /home/linuxbrew/.linuxbrew/sbin "$HOME/.local/share/mise/shims"; do
        if [ -d "$_d" ]; then
            _found="$_found $_d"
            case ":$PATH:" in *":$_d:"*) ;; *) PATH="$_d:$PATH" ;; esac
        fi
    done
    export PATH
    path_report="added:${_found:- none}"
}

# ---------------------------------------------------------------- prerequisites
c_curl() { command -v curl || { echo 'curl missing (README lists it as the one thing init.sh cannot install)'; return 1; }; }
check 'curl is available (README prerequisite)' c_curl

repo=/src/dotfiles
c_source_tree() { [ -d "$repo/.chezmoiscripts" ] || { echo "missing $repo"; return 1; }; echo "$repo"; }
[ $remote = 1 ] || check 'source tree is present' c_source_tree

# ---------------------------------------------------------------- install
echo
if [ $remote = 1 ]; then
    echo "probe: running init.sh --branch $branch from GitHub -- this is the whole install"
    echo 'probe: this usually takes 10-25 minutes (apt, Homebrew, brew formulas, externals, LazyVim clone)'
    c_init_sh() {
        run_streamed "$out_dir/install.log" sh -c \
            "sh -c \"\$(curl -fsLS https://raw.githubusercontent.com/gn00678465/dotfiles/$branch/init.sh)\" -- --branch $branch" \
            || { echo "init.sh -> failed"; output_tail "$out_dir/install.log"; return 1; }
        echo applied
    }
    check "init.sh --branch $branch completes" c_init_sh
else
    echo 'probe: installing chezmoi the way init.sh does'
    c_install_chezmoi() {
        # init.sh's install line without its `chezmoi init` tail: the init call
        # below is the one under test, and it differs per mode.
        run_streamed "$out_dir/chezmoi-install.log" sh -c \
            'sh -c "$(curl -fsLS https://get.chezmoi.io)" -- -b "$HOME/.local/bin"' \
            || { echo 'get.chezmoi.io failed'; output_tail "$out_dir/chezmoi-install.log"; return 1; }
        "$HOME/.local/bin/chezmoi" --version
    }
    check 'init.sh installs chezmoi into ~/.local/bin' c_install_chezmoi
    update_probe_path

    echo
    echo 'probe: running chezmoi init --apply --source /src/dotfiles -- this is the whole install'
    echo 'probe: this usually takes 10-25 minutes (apt, Homebrew, brew formulas, externals, LazyVim clone)'
    c_init_apply() {
        run_streamed "$out_dir/install.log" chezmoi init --apply --source "$repo" \
            || { echo 'chezmoi init --apply -> failed'; output_tail "$out_dir/install.log"; return 1; }
        echo applied
    }
    check 'chezmoi init --apply completes' c_init_apply
fi
update_probe_path

if [ $arch = 1 ]; then
    # Must NOT #4 / M3: the brew scripts render empty on Arch, so nothing may
    # have created the linuxbrew prefix.
    c_no_brew() {
        [ ! -e /home/linuxbrew ] || { echo '/home/linuxbrew exists'; return 1; }
        case "$path_report" in *linuxbrew*) echo "$path_report"; return 1 ;; esac
        echo "$path_report"
    }
    check 'no Homebrew on Arch (Must NOT #4)' c_no_brew
else
    c_path() { echo "$path_report"; case "$path_report" in *linuxbrew*) ;; *) echo 'brew prefix not found'; return 1 ;; esac; }
    check 'PATH rebuilt from ~/.local/bin, brew prefix, mise shims' c_path
fi

if [ $remote = 1 ]; then
    c_source_path() {
        _p=$(chezmoi source-path 2>/dev/null | head -1)
        [ -n "$_p" ] || { echo 'chezmoi source-path returned nothing'; return 1; }
        [ -d "$_p/.chezmoiscripts" ] || { echo "missing $_p"; return 1; }
        repo=$_p; echo "$_p"
    }
    check 'source tree is present' c_source_path
    repo=$(chezmoi source-path 2>/dev/null | head -1)
fi

# ---------------------------------------------------------------- packages
# Same question the Windows probe asks: is the package installed, using the
# same command the install script uses to decide. Both lists must stay
# identical to the scripts'; L11 asserts that, because a package added there
# and missed here would be silently unverified.
apt_packages='zsh git curl build-essential procps file'
brew_formulas='mise fzf git-lfs ripgrep fd lazygit tree-sitter-cli'
pacman_packages='zsh git curl base-devel'
pacman_tools='mise fzf git-lfs ripgrep fd lazygit tree-sitter-cli neovim'

if [ $arch = 1 ]; then
    c_pacman() { pacman -Q "$1" 2>/dev/null || { echo 'not installed'; return 1; }; }
    for _p in $pacman_packages $pacman_tools; do check "pacman package installed: $_p" c_pacman "$_p"; done
else
    c_apt() { dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q '^install ok installed$' || { echo 'not installed'; return 1; }; echo installed; }
    for _p in $apt_packages; do check "apt package installed: $_p" c_apt "$_p"; done
    # stderr dropped on the detail line: brew's `locale` warnings on a fresh
    # rootfs are noise here, the version is the fact.
    c_brew() { brew list --formula "$1" >/dev/null 2>&1 || { echo 'not installed'; return 1; }; brew list --versions "$1" 2>/dev/null; }
    for _f in $brew_formulas; do check "brew formula installed: $_f" c_brew "$_f"; done
fi

# ---------------------------------------------------------------- files
c_zsh_files() {
    for _n in .zshrc .zprofile .p10k.zsh .oh-my-zsh/oh-my-zsh.sh .oh-my-zsh/custom/themes/powerlevel10k/powerlevel10k.zsh-theme; do
        [ -e "$HOME/$_n" ] || { echo "missing $_n"; return 1; }
    done; echo ok
}
check 'zsh files and externals landed' c_zsh_files

# The Linux analogue of the "tool on PATH" question, asked the one way it can
# be answered: start the shell the user gets and see what it resolves.
c_login_shell() {
    _out=$(zsh -ilc 'command -v mise fzf nvim tree-sitter' 2>/dev/null) || { echo "zsh -il failed: $_out"; return 1; }
    printf '%s' "$_out" | tr '\n' ' '
}
check 'interactive login zsh resolves mise, fzf, nvim, tree-sitter' c_login_shell

if [ $arch = 1 ]; then
    # M6: making zsh the login shell must not lose omarchy's own environment.
    # .zshrc/.zprofile source omarchy's env-bootstrap, which sets OMARCHY_PATH
    # and puts omarchy-* on PATH (in dev-link mode; production has them in
    # /usr/bin anyway).
    c_omarchy_env() {
        _out=$(zsh -ilc 'command -v git-lfs omarchy-version && printf "OMARCHY_PATH=%s\n" "$OMARCHY_PATH"' 2>/dev/null) \
            || { echo "zsh -il failed: $_out"; return 1; }
        case "$_out" in *OMARCHY_PATH=/*) ;; *) echo "OMARCHY_PATH unset: $_out"; return 1 ;; esac
        printf '%s' "$_out" | tr '\n' ' '
    }
    check 'login zsh resolves git-lfs and omarchy-version and exports OMARCHY_PATH' c_omarchy_env
fi

c_windows_files() {
    for _n in AppData .config/powershell; do
        [ ! -e "$HOME/$_n" ] || { echo "$_n should not exist on Linux"; return 1; }
    done; echo ok
}
check 'Windows-only files did NOT land' c_windows_files

if [ $arch = 1 ]; then
    # D1 / M2: 50-neovim renders empty on Arch, so omarchy's LazyVim config
    # must still be exactly where useradd put it -- no .bak, no starter marker,
    # omarchy's own plugins intact -- with our override layered on top.
    c_nvim_omarchy() {
        _cfg="$HOME/.config/nvim"
        [ -z "$(ls -d "$HOME"/.config/nvim.bak* "$HOME"/.local/share/nvim.bak* 2>/dev/null)" ] \
            || { echo 'a .bak of the nvim config exists: 50-neovim moved it'; return 1; }
        [ -f "$_cfg/init.lua" ] || { echo 'no init.lua'; return 1; }
        [ -f "$_cfg/lua/plugins/omarchy-theme-hotreload.lua" ] || { echo 'omarchy plugin missing: the config was replaced'; return 1; }
        [ ! -e "$_cfg/.chezmoi-lazyvim-starter" ] || { echo 'starter marker present: 50-neovim ran'; return 1; }
        [ -f "$_cfg/lua/plugins/completion.lua" ] || { echo 'our override is missing'; return 1; }
        echo "$_cfg"
    }
    check 'omarchy nvim config was left in place, with our override on top (M2)' c_nvim_omarchy
else
    c_nvim_config() {
        _cfg="$HOME/.config/nvim"
        [ -f "$_cfg/init.lua" ] || { echo 'no init.lua'; return 1; }
        [ -f "$_cfg/.chezmoi-lazyvim-starter" ] || { echo 'no marker'; return 1; }
        [ ! -e "$_cfg/.git" ] || { echo '.git was not removed'; return 1; }
        [ -f "$_cfg/lua/plugins/completion.lua" ] || { echo 'our override is missing'; return 1; }
        echo "$_cfg"
    }
    check 'nvim config is the LazyVim starter with our marker' c_nvim_config
fi

# Every symlink_ under dot_claude/skills, read from the source tree rather
# than a name written here: the Windows probe carried a skill name that had
# been renamed, and its check was "expected to fail" there so nobody noticed.
c_skills() {
    _n=0
    for _s in "$repo"/dot_claude/skills/symlink_*; do
        _name=${_s##*/symlink_}; _name=${_name%.tmpl}
        [ -L "$HOME/.claude/skills/$_name" ] || { echo "missing symlink $_name"; return 1; }
        [ -e "$HOME/.claude/skills/$_name" ] || { echo "dangling symlink $_name -> $(readlink "$HOME/.claude/skills/$_name")"; return 1; }
        _n=$((_n + 1))
    done
    [ "$_n" -gt 0 ] || { echo 'no symlink_ sources found'; return 1; }
    echo "$_n symlinks resolve"
}
check 'claude skills symlinks' c_skills

c_statusline() {
    _b="$HOME/.claude/cc-statusline/cc-statusline"
    [ -x "$_b" ] || { echo "missing or not executable: $_b"; return 1; }
    grep -q 'cc-statusline' "$HOME/.claude/settings.json" 2>/dev/null || { echo 'settings.json does not point at it'; return 1; }
    wc -c < "$_b" | tr -d ' '
}
check 'cc-statusline downloaded and wired into settings.json' c_statusline

c_codex() {
    _p="$HOME/.codex/config.toml"
    [ -f "$_p" ] || { echo "missing $_p"; return 1; }
    grep -q '^status_line_use_colors = true$' "$_p" || { echo 'status_line_use_colors missing'; return 1; }
    grep -q '^status_line = \[' "$_p" || { echo 'status_line missing'; return 1; }
    echo ok
}
check 'codex config.toml has the managed [tui] keys' c_codex

if [ $arch = 1 ]; then
    # M4: distroOverride in the test fixtures is only a stand-in. Here the real
    # chezmoi reads /etc/os-release, and the partial has to reach the same
    # answer the os-arch fixture gives L1/L2.
    c_seam() {
        _out=$(printf '%s' '{{ .chezmoi.osRelease.id }}|{{- $p := includeTemplate "platform.toml" . | fromToml -}}{{ $p.distro }}|{{ $p.pkgManager }}|{{ $p.brewPrefix }}' \
            | chezmoi execute-template 2>&1) || { echo "execute-template failed: $_out"; return 1; }
        [ "$_out" = 'arch|arch|pacman|' ] || { echo "expected arch|arch|pacman|, got: $_out"; return 1; }
        echo "$_out"
    }
    check 'real chezmoi osRelease.id reaches the partial: distro=arch pkgManager=pacman brewPrefix empty (M4)' c_seam

    # D4: the file omarchy wrote at install time is replaced by the managed one.
    c_git_config() {
        _want=$(chezmoi cat "$HOME/.config/git/config" 2>&1) || { echo "chezmoi cat failed: $_want"; return 1; }
        [ "$_want" = "$(cat "$HOME/.config/git/config")" ] || { echo 'differs from chezmoi cat'; return 1; }
        echo 'managed content in place (omarchy defaults replaced, D4)'
    }
    check '~/.config/git/config is the managed file (D4)' c_git_config

    # 40-git-lfs without the brew shellenv line: git-lfs comes from pacman.
    c_lfs() {
        _e=$(git lfs env 2>&1) || { echo "git lfs env failed: $_e"; return 1; }
        printf '%s' "$_e" | grep -q 'filter.lfs' || { echo "no filter.lfs in: $_e"; return 1; }
        echo 'filter.lfs configured'
    }
    check 'git lfs filter is configured (40-git-lfs, pacman git-lfs)' c_lfs

    # D3: zsh from pacman is a valid login shell; chsh needs a tty, so without
    # one the script must print the manual command instead of failing.
    c_shell() {
        _z=$(command -v zsh) || { echo 'zsh not on PATH'; return 1; }
        grep -qx "$_z" /etc/shells || { echo "$_z not in /etc/shells"; return 1; }
        _s=$(getent passwd "$(id -un)" | cut -d: -f7)
        case "$_s" in
            */zsh) echo "login shell: $_s" ;;
            *) grep -q 'chsh -s' "$out_dir/install.log" || { echo "shell is $_s and no chsh hint was printed"; return 1; }
               echo "login shell: $_s; chsh hint printed (no tty)" ;;
        esac
    }
    check 'zsh is a valid login shell; chsh done or the manual hint was printed (D3)' c_shell
fi

# ---------------------------------------------------------------- neovim + tree-sitter
pin=$(sed -n 's/^neovim = "\([^"]*\)".*/\1/p' "$repo/.chezmoitemplates/versions.toml" 2>/dev/null)
if [ $arch = 1 ]; then
    # Arch: neovim and tree-sitter-cli are pacman packages; the mise pin in
    # versions.toml does not apply (rolling release, SPEC §7).
    c_nvim_pacman() {
        _v=$(nvim --version 2>&1 | head -1) || { echo "nvim failed: $_v"; return 1; }
        echo "$_v via $(command -v nvim) ($(pacman -Q neovim 2>/dev/null))"
    }
    check 'nvim runs (pacman neovim; the mise pin does not apply on Arch)' c_nvim_pacman
    c_treesitter_pacman() {
        _ts=$(command -v tree-sitter) || { echo 'tree-sitter not on PATH'; return 1; }
        case "$_ts" in /usr/bin/*) ;; *) echo "tree-sitter is $_ts, not pacman's"; return 1 ;; esac
        _v=$(tree-sitter --version 2>&1) || { echo "tree-sitter --version failed: $_v"; return 1; }
        echo "$_v at $_ts"
    }
    check "tree-sitter CLI is pacman's and runs" c_treesitter_pacman
else
    c_nvim_pin() {
        [ -n "$pin" ] || { echo 'could not read the neovim pin from versions.toml'; return 1; }
        _v=$(nvim --version 2>&1 | head -1)
        [ "$_v" = "NVIM v$pin" ] || { echo "expected NVIM v$pin, got: $_v"; return 1; }
        echo "$_v via $(command -v nvim)"
    }
    check 'nvim runs and is the pinned version from versions.toml' c_nvim_pin

    # The Debian 12 regression: brew's `tree-sitter` formula stopped shipping the
    # CLI, LazyVim fell back to mason's prebuilt binary, and that one wants a
    # newer glibc than Debian 12 has. Both halves are asserted: the CLI is brew's,
    # and it actually executes.
    c_treesitter() {
        _ts=$(command -v tree-sitter) || { echo 'tree-sitter not on PATH'; return 1; }
        case "$_ts" in /home/linuxbrew/*) ;; *) echo "tree-sitter is $_ts, not brew's"; return 1 ;; esac
        _v=$(tree-sitter --version 2>&1) || { echo "tree-sitter --version failed: $_v"; return 1; }
        echo "$_v at $_ts"
    }
    check "tree-sitter CLI is brew's and runs on this glibc" c_treesitter
fi

echo
echo 'probe: running nvim Lazy! sync + nvim-treesitter install lua (the Linux M12)'
echo 'probe: this usually takes 3-10 minutes and is capped at 15'
c_parser() {
    timeout 900 nvim --headless '+Lazy! sync' '+qa' > "$treesitter_log" 2>&1
    timeout 900 nvim --headless -c "lua require('nvim-treesitter').install({'lua'}):wait(600000)" -c qa >> "$treesitter_log" 2>&1
    for _p in "$HOME/.local/share/nvim/lazy/nvim-treesitter/parser/lua.so" "$HOME/.local/share/nvim/site/parser/lua.so"; do
        [ -f "$_p" ] && { echo "lua parser built: $_p"; return 0; }
    done
    echo "no lua parser produced -- see treesitter.log"; output_tail "$treesitter_log" 10; return 1
}
check 'nvim-treesitter builds a parser' c_parser

# ---------------------------------------------------------------- second run
# Everything above is the first install. The bugs this probe exists for only
# show up afterwards.
echo
echo 'probe: second chezmoi apply (must be non-interactive and idempotent)'
c_second_apply() {
    run_streamed "$out_dir/apply2.log" chezmoi apply --no-tty \
        || { echo 'second apply -> failed'; output_tail "$out_dir/apply2.log" 15; return 1; }
    echo ok
}
check 'second chezmoi apply completes without a prompt' c_second_apply

c_idempotent() {
    [ -z "$(ls -d "$HOME"/.config/nvim.bak* 2>/dev/null)" ] || { echo 'a re-run backed up ~/.config/nvim again'; return 1; }
    if [ $arch = 1 ]; then
        [ ! -e "$HOME/.config/nvim/.chezmoi-lazyvim-starter" ] || { echo 'starter marker appeared: 50-neovim ran on Arch'; return 1; }
    else
        [ -f "$HOME/.config/nvim/.chezmoi-lazyvim-starter" ] || { echo 'marker gone'; return 1; }
    fi
    echo ok
}
check 'second apply did not re-bootstrap nvim' c_idempotent

# `chezmoi git` is the code path `chezmoi update` takes: chezmoi MkdirAll's
# $XDG_RUNTIME_DIR before spawning git. In the container the variable is
# unset, so this passes trivially; in the fresh WSL distro it is the bug.
c_chezmoi_git() {
    _out=$(chezmoi git -- status --short --branch 2>&1) || { echo "chezmoi git failed: $_out"; return 1; }
    echo "XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-unset}; $(printf '%s' "$_out" | head -1)"
}
check 'chezmoi git works (the chezmoi update code path)' c_chezmoi_git

if [ -d /run/systemd/system ]; then
    c_linger() {
        _l=$(loginctl show-user "$(id -un)" --property=Linger --value 2>&1) || { echo "loginctl: $_l"; return 1; }
        [ "$_l" = yes ] || { echo "Linger=$_l"; return 1; }
        [ -d "/run/user/$(id -u)" ] || { echo "/run/user/$(id -u) missing"; return 1; }
        echo "Linger=yes, /run/user/$(id -u) present"
    }
    check '05-wsl-user-runtime-dir enabled linger and /run/user/<uid> exists' c_linger
    if [ $remote = 1 ]; then
        c_update() {
            run_streamed "$out_dir/update.log" chezmoi update --no-tty \
                || { echo 'chezmoi update -> failed'; output_tail "$out_dir/update.log" 15; return 1; }
            echo ok
        }
        check 'chezmoi update completes' c_update
    else
        skip 'chezmoi update completes' 'local mode: the source tree is not a clone with a remote'
    fi
else
    skip '05-wsl-user-runtime-dir enabled linger and /run/user/<uid> exists' 'no systemd in this sandbox'
    skip 'chezmoi update completes' 'no systemd in this sandbox (and local mode has no remote)'
fi

# A removed neovim must come back on the next apply (50-neovim is run_, not
# run_onchange_).
echo
if [ $arch = 1 ]; then
    # On Arch neovim is a pacman package and the probe never removes packages
    # (SPEC Must NOT #8): the machine is the user's, not a throwaway rootfs.
    skip 'a removed neovim is reinstalled by the next apply' 'Arch: neovim is a pacman package; the probe does not remove packages (Must NOT #8)'
else
    echo 'probe: removing neovim from mise and applying again'
    c_reinstall() {
        mise uninstall "neovim@$pin" >/dev/null 2>&1 || { echo 'mise uninstall failed'; return 1; }
        mise ls neovim 2>/dev/null | grep -q missing || { echo 'uninstall did not take'; return 1; }
        run_streamed "$out_dir/apply3.log" chezmoi apply --no-tty --include=scripts \
            || { echo 'apply -> failed'; output_tail "$out_dir/apply3.log" 15; return 1; }
        mise ls neovim 2>/dev/null | grep -q missing && { echo 'neovim still missing after apply'; return 1; }
        nvim --version | head -1
    }
    check 'a removed neovim is reinstalled by the next apply' c_reinstall
fi

# ---------------------------------------------------------------- report
n_pass=$(grep -c '^PASS' "$results"); n_fail=$(grep -c '^FAIL' "$results"); n_skip=$(grep -c '^SKIP' "$results")
summary="PASS=$n_pass FAIL=$n_fail SKIP=$n_skip"
printf 'SUMMARY\t%s\t\n' "$summary" >> "$results"
echo
echo "probe: $summary"
echo "probe: results in $results, transcript in $transcript"

if [ -s "$treesitter_log" ]; then
    echo; echo '--- treesitter.log (tail 200) ---'; tail -n 200 "$treesitter_log"; echo '--- end treesitter.log ---'
fi
echo; echo '--- results.tsv (full) ---'; cat "$results"; echo '--- end results.tsv ---'
[ "$n_fail" -eq 0 ]
