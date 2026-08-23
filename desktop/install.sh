#!/usr/bin/env bash
# Install the debloated desktop: choice of X11 (Openbox) or Wayland (sway).
#
#   sudo desktop/install.sh [options]
#
#   --user=NAME           account to install the dotfiles for (default: $SUDO_USER)
#   --desktop=openbox     window manager: openbox (X11, default) or sway (Wayland)
#   --browser=BROWSER     chrome (default) | chromium | firefox | w3m | falkon | none
#   --audio=AUDIO         pipewire (default) or alsa
#   --network=NETWORK     networkmanager (default) or iwd
#   --file-manager=MGR    nemo (default) | lf | ranger | none
#   --without=GROUP       skip a group from packages.txt (repeatable)
#   --dry-run             print what would happen and change nothing
#
# Examples:
#   # Lightweight Wayland + ALSA + iwd + lf (~250 MB loaded)
#   sudo desktop/install.sh --user=$USER --desktop=sway --audio=alsa --network=iwd --file-manager=lf --without=xorg
#
#   # Standard X11 + PipeWire + NetworkManager (~350+ MB loaded)
#   sudo desktop/install.sh --user=$USER --desktop=openbox
#
# Re-running is safe: packages already present are skipped, and existing
# dotfiles are backed up rather than overwritten.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
target_user="${SUDO_USER:-}"
desktop=openbox
browser=chrome
audio=pipewire
network=networkmanager
file_manager=nemo
skip_groups=()
dry_run=0

for arg in "$@"; do
    case "$arg" in
        --user=*)       target_user="${arg#*=}" ;;
        --desktop=*)    desktop="${arg#*=}" ;;
        --browser=*)    browser="${arg#*=}" ;;
        --audio=*)      audio="${arg#*=}" ;;
        --network=*)    network="${arg#*=}" ;;
        --file-manager=*) file_manager="${arg#*=}" ;;
        --without=*)    skip_groups+=("${arg#*=}") ;;
        --dry-run)      dry_run=1 ;;
        -h|--help)      sed -n '2,28p' "${BASH_SOURCE[0]}" | sed 's/^# \?//'; exit 0 ;;
        *)              echo "unknown option: $arg" >&2; exit 2 ;;
    esac
done

case "$desktop" in openbox|sway) ;; *)
    echo "--desktop must be openbox or sway" >&2; exit 2 ;;
esac

case "$browser" in chrome|chromium|firefox|w3m|falkon|none) ;; *)
    echo "--browser must be chrome, chromium, firefox, w3m, falkon or none" >&2; exit 2 ;;
esac

case "$audio" in pipewire|alsa) ;; *)
    echo "--audio must be pipewire or alsa" >&2; exit 2 ;;
esac

case "$network" in networkmanager|iwd) ;; *)
    echo "--network must be networkmanager or iwd" >&2; exit 2 ;;
esac

case "$file_manager" in nemo|lf|ranger|none) ;; *)
    echo "--file-manager must be nemo, lf, ranger or none" >&2; exit 2 ;;
esac

run() {
    if [[ $dry_run == 1 ]]; then printf '  would run: %s\n' "$*"; else "$@"; fi
}

[[ $dry_run == 1 || $EUID -eq 0 ]] || { echo "run me with sudo" >&2; exit 1; }
[[ -n $target_user ]] || { echo "cannot tell which user to configure; pass --user=NAME" >&2; exit 1; }
home_dir="$(getent passwd "$target_user" | cut -d: -f6)"
[[ -n $home_dir ]] || { echo "no such user: $target_user" >&2; exit 1; }

command -v pacman >/dev/null || { echo "this script targets Arch/CachyOS (pacman not found)" >&2; exit 1; }

echo ":: Installing $desktop desktop with $audio audio and $network networking"

# ================================================================ packages --
echo ":: reading package list"
declare -a wanted=()
group=""
while IFS= read -r line; do
    line="${line%%#*}"; line="${line#\"${line%%[![:space:]]*}\"}"; line="${line%\"${line##*[![:space:]]}\"}"
    [[ -z $line ]] && continue
    if [[ $line =~ ^\[(.+)\]$ ]]; then group="${BASH_REMATCH[1]}"; continue; fi
    
    # Skip groups based on desktop choice
    if [[ $desktop == sway ]]; then
        [[ $group == xorg || $group == wm || $group == panel ]] && continue
        [[ $group == wayland || $group == waybar || $group == wayland-brightness ]] && skip_groups=()
        [[ $group == screenshots-x11 ]] && continue
        # screenshots-wayland gets included
    else
        [[ $group == wayland || $group == waybar || $group == wayland-brightness ]] && continue
        [[ $group == screenshots-wayland ]] && continue
    fi
    
    # Skip groups based on audio choice
    if [[ $audio == alsa ]]; then
        [[ $group == audio-default ]] && continue
    else
        [[ $group == audio-lightweight ]] && continue
    fi
    
    # Skip groups based on network choice
    if [[ $network == iwd ]]; then
        [[ $group == network-default ]] && continue
    else
        [[ $group == network-lightweight ]] && continue
    fi
    
    # Skip groups based on file manager choice
    if [[ $file_manager == lf ]]; then
        [[ $group == files ]] && continue
    elif [[ $file_manager == ranger ]]; then
        [[ $group == files ]] && continue
    elif [[ $file_manager == none ]]; then
        [[ $group == files || $group == files-lightweight ]] && continue
    else  # nemo (default)
        [[ $group == files-lightweight ]] && continue
    fi
    
    # Skip explicitly requested groups
    for s in ${skip_groups[@]+"${skip_groups[@]}"}; do
        [[ $group == "$s" ]] && continue 2
    done
    wanted+=("$line")
done < "$here/packages.txt"

echo ":: ${#wanted[@]} packages requested"
run pacman -S --needed --noconfirm "${wanted[@]}"

# ================================================================ browser --
case "$browser" in
    chromium)
        run pacman -S --needed --noconfirm chromium
        browser_cmd=chromium
        ;;
    firefox)
        run pacman -S --needed --noconfirm firefox
        browser_cmd=firefox
        ;;
    w3m)
        # w3m is already in [browser-lightweight]
        browser_cmd=w3m
        ;;
    falkon)
        run pacman -S --needed --noconfirm falkon
        browser_cmd=falkon
        ;;
    chrome)
        browser_cmd=google-chrome-stable
        if pacman -Si google-chrome >/dev/null 2>&1; then
            run pacman -S --needed --noconfirm google-chrome
        elif helper=$(command -v paru || command -v yay); then
            run sudo -u "$target_user" "$helper" -S --needed --noconfirm google-chrome
        else
            echo "!! google-chrome is an AUR package and no AUR helper (paru/yay)"
            echo "!! was found. Install one and re-run, or use --browser=chromium."
            browser_cmd=""
        fi
        ;;
    none) browser_cmd="" ;;
esac

# ================================================================ dotfiles --
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
    rel="${src#\"$here/skel/\"}"
    
    # Skip X11-only dotfiles if using Wayland
    if [[ $desktop == sway ]]; then
        [[ $rel == .xinitrc ]] && continue
        [[ $rel == .bash_profile ]] && continue
        [[ $rel == .config/openbox* ]] && continue
        [[ $rel == .config/xfce4* ]] && continue
    fi
    
    mode=644
    [[ $rel == .xinitrc ]] && mode=755
    [[ $rel == .bash_profile ]] && mode=644
    [[ $rel == .config/openbox/autostart ]] && mode=755
    [[ $rel == .config/sway/config ]] && mode=755
    # keybindings.xml is merged into rc.xml below, not installed as-is
    [[ $rel == .config/openbox/keybindings.xml ]] && continue
    # never clobber panel layouts the user has tuned
    if [[ $rel == .config/xfce4/xfconf/* && -e "$home_dir/$rel" ]]; then
        echo "  keeping existing $rel"; continue
    fi
    install_file "$src" "$rel" "$mode"
done < <(find "$here/skel" -type f -print0)

# ======================================================= Openbox rc (X11 only) --
if [[ $desktop == openbox ]]; then
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
        run python3 "$here/merge-keybindings.py" "$rc" "$here/skel/.config/openbox/keybindings.xml"
        run chown "$target_user:$target_user" "$rc"
    fi
    
    # Point the menu and bindings at whichever browser actually got installed.
    if [[ -n ${browser_cmd:-} && $browser_cmd != google-chrome-stable ]]; then
        echo ":: rewriting browser command to $browser_cmd"
        run sed -i "s/google-chrome-stable/$browser_cmd/g" \
            "$home_dir/.config/openbox/menu.xml" "$rc"
    fi
fi

# ========================================================== Sway config (Wayland) --
if [[ $desktop == sway ]]; then
    sway_config="$home_dir/.config/sway/config"
    if [[ ! -e $sway_config ]]; then
        echo ":: generating sway config"
        mkdir -p "$(dirname \"$sway_config\")"
        run cat > "$sway_config" <<'SWAY'
# Sway configuration for MacBook Air 6,2 with minimal footprint
set $mod Mod4

# Terminal (Command+Return)
bindsym $mod+Return exec terminator

# File manager (Command+E)
bindsym $mod+e exec terminator -e lf

# Browser (Command+B)
bindsym $mod+b exec BROWSER_CMD

# Lock (Command+L)
bindsym $mod+l exec swaylock -c 1d2021

# Brightness (media keys)
bindsym XF86MonBrightnessUp exec brightnessctl set +5%
bindsym XF86MonBrightnessDown exec brightnessctl set 5%-
bindsym XF86KbdBrightnessUp exec brightnessctl -d smc::kbd_backlight set +10%
bindsym XF86KbdBrightnessDown exec brightnessctl -d smc::kbd_backlight set 10%-

# Audio (media keys)
bindsym XF86AudioRaiseVolume exec amixer set Master 5%+
bindsym XF86AudioLowerVolume exec amixer set Master 5%-
bindsym XF86AudioMute exec amixer set Master toggle

# Close window (Command+Q)
bindsym $mod+q kill

# Focus (arrow keys)
bindsym $mod+Left focus left
bindsym $mod+Right focus right
bindsym $mod+Up focus up
bindsym $mod+Down focus down

# Move window (Command+Shift+Arrows)
bindsym $mod+Shift+Left move left
bindsym $mod+Shift+Right move right
bindsym $mod+Shift+Up move up
bindsym $mod+Shift+Down move down

# Fullscreen (Command+F)
bindsym $mod+f fullscreen toggle

# Floating (Command+Space)
bindsym $mod+space floating toggle

# Workspace switching
bindsym $mod+1 workspace 1
bindsym $mod+2 workspace 2
bindsym $mod+3 workspace 3
bindsym $mod+4 workspace 4

# Move to workspace
bindsym $mod+Shift+1 move container to workspace 1
bindsym $mod+Shift+2 move container to workspace 2
bindsym $mod+Shift+3 move container to workspace 3
bindsym $mod+Shift+4 move container to workspace 4

# Reload config (Command+Shift+C)
bindsym $mod+Shift+c reload

# Exit Sway (Command+Shift+E)
bindsym $mod+Shift+e exec swaymsg exit

# Suspend (close lid handled by systemd, or bind manually)
# bindsym $mod+Escape exec systemctl suspend

# Output configuration (auto-detect, 2560x1600)
output * scale 1

# Gaps and appearance
gaps inner 5
gaps outer 2
border_radius 4

# Status bar
bar {
    status_command while true; do echo \"$(date +%H:%M:%S)\"; sleep 1; done
    position top
    colors {
        background #1d2021
        statusline #d5c4a1
        inactive_workspace #1d2021 #1d2021 #928374
        active_workspace #1d2021 #458588 #1d2021
    }
}

# Input configuration (keyboard & trackpad)
input "*" {
    xkb_layout us
    repeat_delay 250
    repeat_rate 50
}

input "type:touchpad" {
    tap enabled
    natural_scroll enabled
    accel_profile adaptive
}

# Autostart
exec dbus-launch
SWAY
        run chown "$target_user:$target_user" "$sway_config"
    fi
    
    # Replace placeholder with actual browser command
    if [[ -n ${browser_cmd:-} ]]; then
        echo ":: setting sway browser to $browser_cmd"
        run sed -i "s|BROWSER_CMD|$browser_cmd|g" "$sway_config"
    fi
fi

# ================================================================ services --
echo ":: enabling services"

if [[ $network == networkmanager ]]; then
    if [[ -e /usr/lib/systemd/system/NetworkManager.service ]]; then
        run systemctl enable NetworkManager.service \
            || echo "!! could not enable NetworkManager -- run 'systemctl enable NetworkManager' yourself"
    else
        echo "   NetworkManager is not installed -- skipping"
    fi
else
    if [[ -e /usr/lib/systemd/system/iwd.service ]]; then
        run systemctl enable iwd.service \
            || echo "!! could not enable iwd -- run 'systemctl enable iwd' yourself"
    fi
fi

if [[ $audio == pipewire ]]; then
    # PipeWire is socket-activated; nothing to enable here
    echo "   PipeWire will autostart on first use (socket-activated)"
else
    echo "   ALSA configured; use 'alsamixer' or 'amixer' for volume control"
fi

if [[ $desktop == sway ]]; then
    echo "   sway configured; start X by running 'sway' from tty"
else
    echo "   Openbox configured; start X by running 'startx' or it autostart on login"
fi

cat <<DONE

Done. To start the desktop:

Done. Log out and log back in on the console -- .bash_profile starts X on
tty1 by itself, so there is nothing to type. (startx still works if you
prefer to launch it by hand.)

Memory footprint (rough estimates):
  - Idle: $desktop with $audio and $network
    Openbox + PipeWire + NetworkManager: ~200 MB
    sway + ALSA + iwd: ~120 MB
  - Loaded (with file manager + browser open):
    Openbox + Nemo + Chrome: ~600 MB
    sway + lf + w3m: ~200 MB
    sway + lf + Falkon: ~350 MB

Next: hardware/mba62/install.sh sets up the Wi-Fi, camera and fan drivers.
DONE
