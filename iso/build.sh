#!/usr/bin/env bash
# Build the MacBookAir6,2 live/install ISO.
#
#   sudo iso/build.sh [options]
#
#   --kernel-dir=DIR   directory holding prebuilt linux-cachyos-bore-mba62
#                      packages. Without it the kernel is built from
#                      kernel/ here, which takes an hour or two.
#   --skip-aur         do not build the AUR packages (Chrome, mbpfan,
#                      facetimehd). The ISO still works; those are absent.
#   --out=DIR          where to put the ISO (default: out/)
#
# Must run on Arch or CachyOS, as root, with archiso installed.
#
# What it does, in order:
#   1. builds (or collects) the packages that are not in any repo
#   2. drops them into a local pacman repo the profile points at
#   3. copies the desktop dotfiles into the image's /etc/skel
#   4. runs mkarchiso
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(dirname "$here")"
localrepo="/tmp/mba62-localrepo"
outdir="$root/out"
kernel_dir=""
skip_aur=0

for arg in "$@"; do
    case "$arg" in
        --kernel-dir=*) kernel_dir="${arg#*=}" ;;
        --skip-aur)     skip_aur=1 ;;
        --out=*)        outdir="${arg#*=}" ;;
        -h|--help)      sed -n '2,18p' "${BASH_SOURCE[0]}" | sed 's/^# \?//'; exit 0 ;;
        *) echo "unknown option: $arg" >&2; exit 2 ;;
    esac
done

[[ $EUID -eq 0 ]] || { echo "run me as root" >&2; exit 1; }

missing=()
for tool in mkarchiso repo-add mksquashfs xorriso bsdtar; do
    command -v "$tool" >/dev/null || missing+=("$tool")
done
# git is only needed for the AUR builds, so it is a hard requirement unless
# those are being skipped. Without this check a missing git shows up much
# later as "could not clone", which points at the network rather than the
# actual cause.
if [[ $skip_aur == 0 ]]; then
    command -v git >/dev/null || missing+=(git)
fi
if (( ${#missing[@]} )); then
    echo "missing required tool(s): ${missing[*]}" >&2
    echo "on Arch: pacman -S archiso squashfs-tools libisoburn git" >&2
    exit 1
fi

# makepkg refuses to run as root, so everything that builds runs as this user.
build_user="${SUDO_USER:-}"
if [[ -z $build_user || $build_user == root ]]; then
    id -u isobuilder >/dev/null 2>&1 || useradd -m isobuilder
    build_user=isobuilder
    echo "isobuilder ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/isobuilder
fi
as_builder() { sudo -H -u "$build_user" "$@"; }

rm -rf "$localrepo"
mkdir -p "$localrepo"

# ---------------------------------------------------------------- kernel ----
if [[ -n $kernel_dir ]]; then
    echo ":: taking prebuilt kernel packages from $kernel_dir"
    shopt -s nullglob
    pkgs=("$kernel_dir"/linux-cachyos-bore-mba62*.pkg.tar.zst)
    shopt -u nullglob
    (( ${#pkgs[@]} )) || { echo "no linux-cachyos-bore-mba62 packages in $kernel_dir" >&2; exit 1; }
    cp "${pkgs[@]}" "$localrepo/"
else
    echo ":: building the kernel from $root/kernel (this is the slow part)"
    workdir="$(mktemp -d)"
    cp -r "$root/kernel/." "$workdir/"
    chown -R "$build_user" "$workdir"
    # The CachyOS source-signing keys are usually not in the local keyring and
    # the tarball is already pinned by b2sum, which makepkg still verifies.
    ( cd "$workdir" && as_builder makepkg -s --noconfirm --skippgpcheck --nocheck )
    cp "$workdir"/linux-cachyos-bore-mba62*.pkg.tar.zst "$localrepo/"
    rm -rf "$workdir"
fi

# ------------------------------------------------------------------- AUR ----
# Chrome is not in any pacman repository, and neither are the fan daemon or
# the camera driver. google-chrome is just a repack of Google's .deb;
# facetimehd-firmware extracts the camera firmware from an Apple driver
# package, so that one needs a working network connection to build.
#
# Any of these failing is survivable -- the ISO is still complete without
# them -- so a failure is reported and the build carries on.
if [[ $skip_aur == 0 ]]; then
    for pkg in google-chrome mbpfan-git facetimehd-firmware facetimehd-dkms; do
        echo ":: building $pkg from the AUR"
        d="$(mktemp -d)"; chown "$build_user" "$d"
        if as_builder git clone -q --depth 1 "https://aur.archlinux.org/$pkg.git" "$d/$pkg" 2>/dev/null; then
            if ( cd "$d/$pkg" && as_builder makepkg -s --noconfirm --skippgpcheck ); then
                # Skip the -debug split packages makepkg produces; they are
                # only useful with a debugger and would bloat the image.
                for built in "$d/$pkg"/*.pkg.tar.zst; do
                    case "$(basename "$built")" in
                        *-debug-*) continue ;;
                        *) cp "$built" "$localrepo/" ;;
                    esac
                done
            else
                echo "!! $pkg failed to build -- carrying on without it" >&2
            fi
        else
            echo "!! could not clone $pkg from the AUR -- carrying on without it" >&2
        fi
        rm -rf "$d"
    done
fi

echo ":: local repo contents"
ls -1 "$localrepo"/*.pkg.tar.zst | sed 's|.*/|   |'
repo-add -q "$localrepo/mba62.db.tar.gz" "$localrepo"/*.pkg.tar.zst

# Add whatever AUR builds succeeded to the package list, so a failed optional
# build does not fail the whole ISO.
pkglist="$(mktemp)"
cp "$here/packages.x86_64" "$pkglist"
for pkg in google-chrome mbpfan-git facetimehd-firmware facetimehd-dkms; do
    if compgen -G "$localrepo/$pkg-*.pkg.tar.zst" >/dev/null; then
        echo "$pkg" >> "$pkglist"
    fi
done

# --------------------------------------------------- assemble the profile ---
# Everything below writes into a copy, never into iso/ itself: a build should
# not leave generated files in the working tree.
work="$(mktemp -d -p /var/tmp mkarchiso.XXXXXX)"
profile="$(mktemp -d -p /var/tmp profile.XXXXXX)"
trap 'rm -rf "$work" "$profile" "$pkglist"' EXIT

cp -r "$here/." "$profile/"
cp "$pkglist" "$profile/packages.x86_64"

# The desktop configuration is the same one desktop/install.sh lays down; the
# ISO bakes it into /etc/skel so the live user and every account created by
# the installer start with it.
echo ":: copying desktop dotfiles into /etc/skel"
skel="$profile/airootfs/etc/skel"
mkdir -p "$skel"
cp -r "$root/desktop/skel/." "$skel/"
# keybindings.xml is merged into rc.xml at first login, not shipped as-is
rm -f "$skel/.config/openbox/keybindings.xml"

# The hardware configuration belongs on the image too -- it is the same set of
# files hardware/mba62/install.sh would write.
echo ":: copying MacBookAir6,2 hardware configuration"
install -Dm644 "$root"/hardware/mba62/modprobe.d/*.conf -t "$profile/airootfs/etc/modprobe.d/"
install -Dm644 "$root"/hardware/mba62/X11/xorg.conf.d/*.conf -t "$profile/airootfs/etc/X11/xorg.conf.d/"
install -Dm644 "$root"/hardware/mba62/udev/rules.d/*.rules -t "$profile/airootfs/etc/udev/rules.d/"
install -Dm644 "$root/hardware/mba62/mbpfan.conf" "$profile/airootfs/etc/mbpfan.conf"
install -Dm755 "$root/hardware/mba62/bin/mba62-epb" "$profile/airootfs/usr/local/bin/mba62-epb"
install -Dm644 "$root/hardware/mba62/systemd/mba62-epb.service" \
    "$profile/airootfs/etc/systemd/system/mba62-epb.service"
# systemctl cannot enable a unit in a tree that is not booted, so the
# multi-user.target.wants symlink is created the same way archiso's own
# profile does it -- by hand.
mkdir -p "$profile/airootfs/etc/systemd/system/multi-user.target.wants"
ln -sf /etc/systemd/system/mba62-epb.service \
    "$profile/airootfs/etc/systemd/system/multi-user.target.wants/mba62-epb.service"

# --------------------------------------------------------------- mkarchiso --

mkdir -p "$outdir"
echo ":: mkarchiso"
mkarchiso -v -w "$work" -o "$outdir" "$profile"

# ----------------------------------------------------------------- verify ---
# mkarchiso exits 0 even when something we care about quietly did not happen --
# most importantly a DKMS module that failed to build, which would leave the
# laptop with no Wi-Fi and no obvious reason why. Check the assembled tree
# before it is thrown away.
airootfs="$work/x86_64/airootfs"
iso_file="$(ls -1t "$outdir"/*.iso | head -1)"
echo ":: verifying the image"
fail=0

# Contents of the live filesystem.
check() {
    local desc="$1" path="$2"
    if compgen -G "$airootfs$path" >/dev/null; then
        printf '   ok    %s\n' "$desc"
    else
        printf '   MISS  %s (%s)\n' "$desc" "$path"
        fail=$((fail+1))
    fi
}

# Contents of the finished ISO. The boot files are checked here rather than in
# the airootfs because mkarchiso copies them onto the ISO and then empties
# ${airootfs}/boot entirely -- looking for them in the live filesystem finds
# nothing and says the image is broken when it is fine.
iso_listing="$(bsdtar -tf "$iso_file" 2>/dev/null)"
check_iso() {
    local desc="$1" pattern="$2"
    if grep -qE "$pattern" <<<"$iso_listing"; then
        printf '   ok    %s\n' "$desc"
    else
        printf '   MISS  %s (%s)\n' "$desc" "$pattern"
        fail=$((fail+1))
    fi
}

check_iso "kernel image on the ISO"  "^arch/boot/x86_64/vmlinuz-linux-cachyos-bore-mba62$"
check_iso "live initramfs on the ISO" "^arch/boot/x86_64/initramfs-linux-cachyos-bore-mba62\\.img$"
check_iso "squashfs"                 "^arch/x86_64/airootfs\\.sfs$"
check_iso "GRUB config"              "^boot/grub/grub\\.cfg$"
# Apple's firmware generally only lists a loader from the Startup Manager when
# it is at this path, so an ISO without it will not appear in the boot picker.
check_iso "EFI fallback loader"      "^EFI/BOOT/BOOTx64\\.EFI$"

check "kernel modules"            "/usr/lib/modules/*-cachyos-bore-mba62/kernel"
check "BCM4360 Wi-Fi module"      "/usr/lib/modules/*-cachyos-bore-mba62/updates/dkms/wl.ko*"
check "Cirrus audio codec"        "/usr/lib/modules/*-cachyos-bore-mba62/kernel/sound/hda/codecs/cirrus/snd-hda-codec-cs420x.ko*"
check "Calamares binary"          "/usr/bin/calamares"
check "our Calamares settings"    "/etc/calamares/settings.conf"
check "unpackfs override"         "/etc/calamares/modules/unpackfs-mba62.conf"
check "bootloader override"       "/etc/calamares/modules/bootloader-mba62.conf"
check "installer launcher"        "/usr/local/bin/install-to-disk"
check "Openbox"                   "/usr/bin/openbox"
check "xfce4-panel"               "/usr/bin/xfce4-panel"
check "Terminator"                "/usr/bin/terminator"
check "Nemo"                      "/usr/bin/nemo"
check "desktop dotfiles in skel"  "/etc/skel/.config/openbox/autostart"
check "hardware quirks"           "/etc/modprobe.d/10-mba62-input.conf"
check "EPB helper"                "/usr/local/bin/mba62-epb"
check "EPB service enabled"       "/etc/systemd/system/multi-user.target.wants/mba62-epb.service"
# There is deliberately no intel-ucode.img on the ISO. mkinitcpio's microcode
# hook embeds the microcode into the initramfs from the individual firmware
# files, so archiso sets need_external_ucodes=0 and copies no image. Those
# firmware files are what must survive -- archiso empties /boot, and the
# installed system regenerates its initramfs from these.
check "CPU microcode firmware"    "/usr/lib/firmware/intel-ucode"

if compgen -G "$airootfs/usr/lib/modules/"*"/updates/dkms/facetimehd.ko"* >/dev/null; then
    echo "   ok    FaceTime HD camera module"
else
    echo "   note  no camera module (AUR build skipped or failed)"
fi

if compgen -G "$airootfs/opt/google/chrome/chrome" >/dev/null; then
    echo "   ok    Google Chrome"
elif compgen -G "$airootfs/usr/bin/chromium" >/dev/null; then
    echo "   note  Chrome missing, Chromium present instead"
else
    echo "   note  no browser on the image (AUR build skipped or failed)"
fi

if (( fail )); then
    echo ":: $fail expected file(s) missing from the image -- see above" >&2
    exit 1
fi

echo
echo ":: done"
ls -lh "$outdir"/*.iso
