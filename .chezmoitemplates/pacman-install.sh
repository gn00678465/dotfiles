# Shared by 10-install-packages (Arch branch) and 30-install-pacman-packages.
# Usage: pacman_install_missing <pkg>...  -- installs only the packages that
# `pacman -Q` does not know, with the same root/sudo handling as the apt path.
#
# -S --needed --noconfirm and nothing else. No -Sy: refreshing the database
# without upgrading is the partial-upgrade state Arch does not support. No
# -Syu: a full system upgrade is the user's (or omarchy-update's) decision, not
# an apply side effect. The price is that a stale database makes -S fail with
# 404s, so that case gets an explicit hint instead of a silent retry.
pacman_install_missing() {
    missing=""
    for _pkg in "$@"; do
        if ! pacman -Q "$_pkg" >/dev/null 2>&1; then
            missing="$missing $_pkg"
        fi
    done
    if [ -z "$missing" ]; then
        return 0
    fi

    echo "chezmoi: installing missing packages:$missing"
    if [ "$(id -u)" -eq 0 ]; then
        pacman -S --needed --noconfirm $missing && return 0
    elif command -v sudo >/dev/null 2>&1; then
        # Prime the sudo credential cache first: fails fast and loudly with no
        # tty, instead of hanging or half-installing.
        if ! sudo -v; then
            echo "chezmoi: sudo authentication failed. Run: sudo pacman -S --needed$missing" >&2
            return 1
        fi
        sudo pacman -S --needed --noconfirm $missing && return 0
    else
        echo "chezmoi: sudo not available. Run as root: pacman -S --needed$missing" >&2
        return 1
    fi
    # The two causes look the same to -S: a database that is out of date, and one
    # that was never synced (a fresh image, where the keyring is empty too). Name
    # both, and keep the exact commands in the README so this stays one screen.
    echo "chezmoi: pacman could not install:$missing" >&2
    echo "chezmoi: the package database is out of date or was never synced, and -S alone never syncs it." >&2
    echo "chezmoi: update the system first, then re-run chezmoi apply:" >&2
    echo "chezmoi:   omarchy: Update > Omarchy" >&2
    echo "chezmoi:   plain Arch: a full system upgrade, as root" >&2
    echo "chezmoi:   fresh image: initialise and populate the pacman keyring first (pacman-key)" >&2
    echo "chezmoi: exact commands: README, section 'Arch 家族'." >&2
    return 1
}
