#!/usr/bin/env bash
# Install the debloated Openbox desktop: Openbox + xfce4-panel + Terminator
# + Nemo + Chrome, and nothing else.
#
#   sudo desktop/install.sh [options]
#
#   --user=NAME        account to install the dotfiles for (default: $SUDO_USER)
#   --browser=chrome   google-chrome from the AUR (default)
#   --browser=chromium chromium from [extra], no AUR helper needed
#   --browser=none     skip the browser
#   --without=GROUP    skip a group from packages.txt (repeatable)
#   --dry-run          print what would happen and change nothing
#
# Re-running is safe: packages already present are skipped, and existing
# dotfiles are backed up rather than overwritten.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
target_user="${SUDO_USER:-}"
browser=chrome
skip_groups=()
dry_run=0

for arg in "$@"; do
    case "$arg" in
        --user=*)    target_user="${arg#*=}" ;;
        --browser=*) browser="${arg#*=}" ;;
        --without=*) skip_groups+=("${arg#*=}") ;;
        --dry-run)   dry_run=1 ;;
        -h|--help)   sed -n '2,16p' "${BASH_SOURCE[0]}" | sed 's/^# \?//'; exit 0 ;;
        *)           echo "unknown option: $arg" >&2; exit 2 ;;
    esac
done

case "$browser" in chrome|chromium|none) ;; *)
    echo "--browser must be chrome, chromium or none" >&2; exit 2 ;;
esac

run() {
    if [[ $dry_run == 1 ]]; then printf '  would run: %s\n' "$*"; else "$@"; fi
}

[[ $dry_run == 1 || $EUID -eq 0 ]] || { echo "run me with sudo" >&2; exit 1; }
[[ -n $target_user ]] || { echo "cannot tell which user to configure; pass --user=NAME" >&2; exit 1; }
home_dir="$(getent passwd "$target_user" | cut -d: -f6)"
[[ -n $home_dir ]] || { echo "no such user: $target_user" >&2; exit 1; }

command -v pacman >/dev/null || { echo "this script targets Arch/CachyOS (pacman not found)" >&2; exit 1; }

# ---------------------------------------------------------------- packages --
echo ":: reading package list"
declare -a wanted=()
group=""
while IFS= read -r line; do
    line="${line%%#*}"; line="${line#"${line%%[![:space:]]*}"}"; line="${line%"${line##*[![:space:]]}"}"
    [[ -z $line ]] && continue
    if [[ $line =~ ^\[(.+)\]$ ]]; then group="${BASH_REMATCH[1]}"; continue; fi
    for s in ${skip_groups[@]+"${skip_groups[@]}"}; do
        [[ $group == "$s" ]] && continue 2
    done
    wanted+=("$line")
done < "$here/packages.txt"

echo ":: ${#wanted[@]} packages requested"
run pacman -S --needed --noconfirm "${wanted[@]}"

# ------------------------------------------------------------------ browser --
case "$browser" in
    chromium)
        run pacman -S --needed --noconfirm chromium
        browser_cmd=chromium
        ;;
    chrome)
        browser_cmd=google-chrome-stable
        if pacman -Si google-chrome >/dev/null 2>&1; then
            # CachyOS users often have an AUR-backed repo enabled already.
            run pacman -S --needed --noconfirm google-chrome
        elif helper=$(command -v paru || command -v yay); then
            run sudo -u "$target_user" "$helper" -S --needed --noconfirm google-chrome
        else
            echo "!! google-chrome is an AUR package and no AUR helper (paru/yay)"
            echo "!! was found, nor is it in a configured repository."
            echo "!! Install one of them and re-run, or use --browser=chromium."
            browser_cmd=""
        fi
        ;;
    none) browser_cmd="" ;;
esac

# ----------------------------------------------------------------- dotfiles --
echo ":: installing dotfiles for $target_user ($home_dir)"
stamp="$(date +%Y%m%d%H%M%S)"

install_file() {
    local src="$1" rel="$2" dest="$home_dir/$2"
    if [[ -e $dest ]]; then
        if cmp -s "$src" "$dest"; then
            echo "  unchanged: $rel"; return
        fi
        echo "  backing up existing $rel -> $rel.bak-$stamp"
        run cp -a "$dest" "$dest.bak-$stamp"
    else
        echo "  installing: $rel"
    fi
    run install -D -o "$target_user" -g "$target_user" -m "${3:-644}" "$src" "$dest"
}

while IFS= read -r -d '' src; do
    rel="${src#"$here/skel/"}"
    mode=644
    [[ $rel == .xinitrc ]] && mode=755
    [[ $rel == .bash_profile ]] && mode=644
    [[ $rel == .config/openbox/autostart ]] && mode=755
    # keybindings.xml is merged into rc.xml below, not installed as-is
    [[ $rel == .config/openbox/keybindings.xml ]] && continue
    # never clobber a panel layout the user has already tuned
    if [[ $rel == .config/xfce4/xfconf/* && -e "$home_dir/$rel" ]]; then
        echo "  keeping existing $rel"; continue
    fi
    install_file "$src" "$rel" "$mode"
done < <(find "$here/skel" -type f -print0)

# --------------------------------------------------------------- openbox rc --
# Start from the distro's rc.xml so the schema always matches the installed
# Openbox, then merge in only our bindings.
rc="$home_dir/.config/openbox/rc.xml"
if [[ ! -e $rc ]]; then
    if [[ -r /etc/xdg/openbox/rc.xml ]]; then
        echo ":: seeding rc.xml from /etc/xdg/openbox/rc.xml"
        run install -D -o "$target_user" -g "$target_user" -m 644 /etc/xdg/openbox/rc.xml "$rc"
    else
        echo "!! /etc/xdg/openbox/rc.xml not found -- is openbox installed?" >&2
    fi
fi
if [[ -e $rc || $dry_run == 1 ]]; then
    echo ":: merging key bindings into rc.xml"
    run "$here/merge-keybindings.py" "$rc" "$here/skel/.config/openbox/keybindings.xml"
    run chown "$target_user:$target_user" "$rc"
fi

# Point the menu and bindings at whichever browser actually got installed.
if [[ -n ${browser_cmd:-} && $browser_cmd != google-chrome-stable ]]; then
    echo ":: rewriting browser command to $browser_cmd"
    run sed -i "s/google-chrome-stable/$browser_cmd/g" \
        "$home_dir/.config/openbox/menu.xml" "$rc"
fi

# ----------------------------------------------------------------- services --
echo ":: enabling services"
run systemctl enable NetworkManager.service
# PipeWire needs nothing enabled here: its packages ship the user units
# already wanted by default.target, and it is socket-activated on first use.

cat <<'DONE'

Done. Log out and log back in on the console -- .bash_profile starts X on
tty1 by itself, so there is nothing to type. (`startx` still works if you
prefer to launch it by hand.)

If you want a display manager instead, `pacman -S ly && systemctl enable ly`
is the smallest sensible option; nothing here depends on one.

Next: hardware/mba62/install.sh sets up the Wi-Fi, camera and fan drivers.
DONE
