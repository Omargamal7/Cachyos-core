#!/usr/bin/env bash
# shellcheck disable=SC2034
#
# archiso profile for the MacBookAir6,2 live/install image.
#
# The installer is Calamares in offline mode: its unpackfs module copies this
# live filesystem straight onto the disk, so whatever boots from the USB stick
# is exactly what ends up installed. There is no package selection step and no
# network required.

iso_name="cachyos-core-mba62"
iso_label="MBA62_$(date --date="@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%Y%m)"
iso_publisher="Omar Gamal <https://github.com/Omargamal7/Cachyos-core>"
iso_application="CachyOS-core Openbox live/install for MacBookAir6,2"
iso_version="$(date --date="@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%Y.%m.%d)"
install_dir="arch"
buildmodes=('iso')

# MacBookAir6,2 is 64-bit EFI only -- it has no BIOS/CSM path, so a
# bios.syslinux bootmode would only add weight. uefi.grub is kept over
# systemd-boot because Apple's firmware is happier chainloading it and it is
# what CachyOS ships.
bootmodes=('uefi.grub')

arch="x86_64"
pacman_conf="pacman.conf"
airootfs_image_type="squashfs"
airootfs_image_tool_options=('-comp' 'zstd' '-Xcompression-level' '19' '-b' '1M')

file_permissions=(
  ["/etc/shadow"]="0:0:400"
  ["/etc/gshadow"]="0:0:400"
  ["/root"]="0:0:750"
  ["/etc/sudoers.d"]="0:0:750"
  ["/etc/sudoers.d/g_wheel"]="0:0:440"
  ["/usr/local/bin/install-to-disk"]="0:0:755"
  ["/usr/local/bin/live-session-setup"]="0:0:755"
)
