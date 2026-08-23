#!/usr/bin/env bash
# Install the MacBookAir6,2 driver stack and its configuration.
#
#   sudo hardware/mba62/install.sh [options]
#
#   --skip-wifi      do not install broadcom-wl-dkms
#   --skip-camera    do not install facetimehd
#   --skip-fan       do not install mbpfan
#   --dry-run        print what would happen and change nothing
#
# Three pieces of this machine are not supported by anything in the kernel
# tree and have to come from DKMS:
#
#   Wi-Fi    Broadcom BCM4360 -> broadcom-wl-dkms
#   Camera   FaceTime HD      -> facetimehd-dkms + firmware from macOS
#   Fan      applesmc is in-tree, but nothing drives the fan -> mbpfan
#
# Everything else -- graphics, audio, trackpad, keyboard, Bluetooth,
# sensors, Thunderbolt -- is handled by the kernel this repo builds.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
do_wifi=1 do_camera=1 do_fan=1 dry_run=0

for arg in "$@"; do
    case "$arg" in
        --skip-wifi)   do_wifi=0 ;;
        --skip-camera) do_camera=0 ;;
        --skip-fan)    do_fan=0 ;;
        --dry-run)     dry_run=1 ;;
        -h|--help)     sed -n '2,22p' "${BASH_SOURCE[0]}" | sed 's/^# \?//'; exit 0 ;;
        *)             echo "unknown option: $arg" >&2; exit 2 ;;
    esac
done

run() { if [[ $dry_run == 1 ]]; then printf '  would run: %s\n' "$*"; else "$@"; fi; }
have() { command -v "$1" >/dev/null 2>&1; }

[[ $dry_run == 1 || $EUID -eq 0 ]] || { echo "run me with sudo" >&2; exit 1; }
have pacman || { echo "this script targets Arch/CachyOS (pacman not found)" >&2; exit 1; }

aur_helper="$(command -v paru || command -v yay || true)"
aur_install() {
    if [[ -n $aur_helper ]]; then
        run sudo -u "${SUDO_USER:-nobody}" "$aur_helper" -S --needed --noconfirm "$@"
    else
        echo "!! $* needs an AUR helper (paru or yay); install one and re-run" >&2
        return 1
    fi
}

# ------------------------------------------------------------ sanity check --
echo ":: checking this is actually a MacBookAir6,2"
model="$(cat /sys/class/dmi/id/product_name 2>/dev/null || true)"
if [[ $model != "MacBookAir6,2" ]]; then
    echo "!! DMI reports '${model:-unknown}', not MacBookAir6,2."
    echo "!! The module options and quirks here are specific to that model."
    if [[ $dry_run == 0 ]]; then
        read -rp "   Continue anyway? [y/N] " reply
        [[ ${reply,,} == y ]] || exit 1
    fi
fi

run pacman -S --needed --noconfirm dkms linux-firmware

# -------------------------------------------------------------------- Wi-Fi --
if [[ $do_wifi == 1 ]]; then
    echo ":: Wi-Fi (Broadcom BCM4360)"
    wifi_id="$(lspci -nn 2>/dev/null | grep -iE 'network|wireless' || true)"
    echo "   device: ${wifi_id:-not detected}"
    if [[ -n $wifi_id && $wifi_id != *14e4:43a0* ]]; then
        echo "!! This is not the 14e4:43a0 BCM4360 these configs assume."
        echo "!! If it is a 43602/4350/4356 the in-tree brcmfmac driver is the"
        echo "!! right one -- skip this step and remove 20-mba62-wifi.conf."
    fi
    run pacman -S --needed --noconfirm broadcom-wl-dkms
fi

# ------------------------------------------------------------------- camera --
if [[ $do_camera == 1 ]]; then
    echo ":: FaceTime HD camera"
    # The driver is useless without firmware, which Apple does not
    # redistribute -- facetimehd-firmware extracts it from an Apple driver
    # package at build time and needs network access.
    aur_install facetimehd-dkms facetimehd-firmware || \
        echo "!! camera skipped; see docs/HARDWARE.md for the manual route"
fi

# ---------------------------------------------------------------------- fan --
if [[ $do_fan == 1 ]]; then
    echo ":: fan control (mbpfan)"
    if aur_install mbpfan-git; then
        run install -Dm644 "$here/mbpfan.conf" /etc/mbpfan.conf
        run systemctl enable mbpfan.service
    fi
fi

# ------------------------------------------------------------- config files --
echo ":: installing module options and quirks"
for f in "$here"/modprobe.d/*.conf; do
    run install -Dm644 "$f" "/etc/modprobe.d/$(basename "$f")"
done
for f in "$here"/X11/xorg.conf.d/*.conf; do
    run install -Dm644 "$f" "/etc/X11/xorg.conf.d/$(basename "$f")"
done
for f in "$here"/udev/rules.d/*.rules; do
    run install -Dm644 "$f" "/etc/udev/rules.d/$(basename "$f")"
done

echo ":: rebuilding the initramfs so the new module options take effect"
if have mkinitcpio; then
    run mkinitcpio -P
elif have dracut; then
    run dracut --force --regenerate-all
fi

cat <<'DONE'

Done. Reboot, then check:

  lsmod | grep -E '^(wl|bcm5974|applesmc|facetimehd)'   drivers loaded
  nmcli device                                          Wi-Fi sees the card
  sensors                                               SMC temperatures
  wpctl status                                          audio sink present
  ls /sys/class/leds/smc::kbd_backlight                 keyboard backlight

If Wi-Fi is missing, `dmesg | grep -i wl` usually says why -- most often
the DKMS module failed to build against a kernel whose headers are not
installed. `pacman -S linux-cachyos-bore-mba62-headers` fixes that.
DONE
