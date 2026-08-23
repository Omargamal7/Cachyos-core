# Installing on the MacBook Air

The short version: download the ISO, write it to a USB stick, hold Option at
power-on, click through the installer.

## 1. Get the ISO

Download the newest `cachyos-core-mba62-*.iso` from the
[releases page](https://github.com/Omargamal7/Cachyos-core/releases/tag/iso-latest),
along with `SHA256SUMS`.

Check it before you write it:

```sh
sha256sum -c SHA256SUMS
```

If no ISO is there yet, build one: Actions → **ISO** → Run workflow. It needs
the **Kernel packages** workflow to have run at least once first, since it
takes the kernel from that release rather than recompiling it.

## 2. Write it to a USB stick

This erases the stick. Get the device name right.

**From Linux:**

```sh
lsblk                       # find your stick -- /dev/sdb, /dev/sdc, ...
sudo dd if=cachyos-core-mba62-*.iso of=/dev/sdX bs=4M status=progress oflag=sync
```

**From macOS:**

```sh
diskutil list               # find your stick -- /dev/disk2, /dev/disk3, ...
diskutil unmountDisk /dev/diskN
sudo dd if=cachyos-core-mba62-*.iso of=/dev/rdiskN bs=4m
diskutil eject /dev/diskN
```

Note the `r` in `/dev/rdiskN` — the raw device is many times faster on macOS.
macOS will offer to initialise the disk when it finishes; **click Ignore**.

**From Windows:** use [Rufus](https://rufus.ie) in DD mode, or
[balenaEtcher](https://etcher.balena.io).

## 3. Boot it

1. Shut the MacBook Air down fully.
2. Plug in the stick.
3. Power on and **hold Option (⌥)** until the boot picker appears.
4. Pick the orange **EFI Boot** entry.

The GRUB menu offers a normal entry and a "safe graphics" one. Take the normal
one; the safe entry is there in case the panel stays black.

It boots straight to an Openbox desktop and starts the installer.

> **If the boot picker does not show the stick**, it is almost always the
> write rather than the Mac: `dd` to `/dev/diskN` instead of `/dev/rdiskN`,
> a partition instead of the whole disk (`/dev/sdb1` rather than `/dev/sdb`),
> or an incomplete flush. Re-write it and try again.

## 4. Install

The installer is Calamares. It asks for location, keyboard, where to install,
and a user account, then copies the running system to disk.

That last part is worth knowing: this is an **offline install**. It copies the
exact filesystem you booted, so the installed system is what you have been
looking at — same kernel, same desktop, same drivers. No network needed, and
nothing can be downloaded that differs from what you tested.

On the partitioning screen:

* **Erase disk** if the Mac is becoming a Linux-only machine.
* **Manual partitioning** if macOS is staying. Leave the existing EFI System
  Partition alone and let the installer use it — do not format it, or you will
  break the macOS boot entry.

The bootloader is GRUB, installed both to its own directory and to
`\EFI\BOOT\BOOTX64.EFI`. Apple's firmware often only lists the fallback path
in the Startup Manager, which is why both are written.

## 5. First boot

There is no login screen by design. You get a text login on the console; log
in and X starts by itself.

What you should find working, with nothing to configure:

| | |
|---|---|
| Wi-Fi | `broadcom-wl` is built into the image, so the BCM4360 works from first boot |
| Trackpad | tap-to-click, two-finger scroll, natural scrolling |
| Keyboard | media keys primary; Fn+F1..F12 for plain function keys |
| Brightness | screen and keyboard, on the usual keys |
| Audio | Cirrus CS4208, speakers and headphone jack |
| Bluetooth | BCM20702 |
| Suspend | closing the lid |

Right-click the desktop for the Openbox menu. `Super` is the Command key:
`Super+Return` for a terminal, `Super+E` for files, `Super+B` for Chrome.

### The two that may or may not be there

The camera driver and the fan daemon are built from the AUR while the ISO is
assembled, and the build is allowed to fail rather than take the whole image
down with it — `facetimehd-firmware` in particular has to pull the firmware
out of an Apple driver package at build time, which needs a working network
on the build machine.

Check what you actually got:

```sh
modinfo facetimehd >/dev/null 2>&1 && echo "camera driver present"
systemctl status mbpfan
```

If either is missing, install it once you are online:

```sh
sudo hardware/mba62/install.sh --skip-wifi
```

## 6. Keeping the kernel current

The kernel is not in any public pacman repository, so `pacman -Syu` will not
update it. When a new build is published:

```sh
sudo mba62-update
```

That pulls the newest packages from this project's releases and installs them
with `pacman -U`. Everything else updates normally through pacman.

## If something goes wrong

**Black screen after GRUB** — reboot and pick "safe graphics". If that works,
the panel needs a kernel parameter; open an issue with the output of
`dmesg | grep -i i915`.

**No Wi-Fi** — check the card is what this image expects:

```sh
lspci -nn | grep -i net      # expect 14e4:43a0
lsmod | grep wl
```

A different Broadcom part wants the in-tree `brcmfmac` driver instead. See
[HARDWARE.md](HARDWARE.md).

**The Mac boots straight to macOS** — hold Option at power-on rather than
letting it boot; if the Linux entry is not listed at all, re-run the
installer's bootloader step or reinstall GRUB from a live session.
