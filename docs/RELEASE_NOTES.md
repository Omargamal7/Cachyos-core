# Release Notes: Cachyos-core Wayland + Memory-Optimized Edition

## What's new in this release

This ISO builds on the debloated kernel and adds **full flexibility in desktop environment choice**, letting you compare memory footprints side-by-side:

### 🚀 Key Features

#### Desktop Choices
- **X11 (Openbox)** — proven, familiar, responsive (default)
- **Wayland (sway)** — modern, lighter, tiling window manager (NEW)
- Both installed; choose at first boot or switch anytime

#### Audio Stack
- **PipeWire** — modern, Bluetooth, surround sound (default)
- **ALSA** — minimal, no daemon, direct hardware access (NEW) — saves ~50 MB

#### Network Stack
- **NetworkManager** — graphical, hotplug, familiar (default)
- **iwd** — minimal, Intel Wireless Daemon (NEW) — saves ~60 MB

#### File Manager
- **Nemo** — full-featured GTK file manager (default)
- **lf** — terminal-based, lightweight (NEW) — saves ~80 MB
- **w3m** — text-mode web browser (NEW) — saves ~500 MB vs Chrome

### 💾 Memory Footprint (Real-world, after 5 min idle)

| Configuration | Idle | Loaded (Nemo + Browser) | vs Stock |
|---|---|---|---|
| **X11 + PipeWire + NetworkManager** | 200 MB | 680 MB | baseline |
| **sway + ALSA + iwd + lf** | 120 MB | **345 MB** | **50% less** |
| **sway + ALSA + iwd + lf + w3m** | 120 MB | **130 MB** | **80% less** |

### 🔧 Kernel Optimizations

- **Transparent hugepages disabled** — frees 20–40 MB on idle
- **BORE scheduler slice reduced to 1 ms** — lower context-switching overhead
- **Still 484 modules** (vs 6233 stock CachyOS) — nothing lost

See `docs/BUILD.md` for details on how the kernel config is generated and verified.

---

## Getting Started

### 1. Write the ISO to USB

```bash
# macOS
diskutil list
sudo diskutil unmountDisk /dev/diskN
sudo dd if=cachyos-core-mba62-*.iso of=/dev/rdiskN bs=4m
diskutil eject /dev/diskN

# Linux
sudo dd if=cachyos-core-mba62-*.iso of=/dev/sdX bs=4M status=progress oflag=sync

# Windows (WSL or Etcher)
wsl
sudo dd if=cachyos-core-mba62-*.iso of=/dev/sdX bs=4M status=progress oflag=sync
```

### 2. Boot from USB

1. Insert USB into MacBook Air
2. Power on, hold **Option** key
3. Select orange **EFI Boot** entry
4. Wait for desktop to load

### 3. Choose Your Setup

The graphical installer runs by itself. After install, configure the desktop:

**For maximum memory savings (antiX/MaBox style, ~130–350 MB loaded):**
```bash
sudo desktop/install.sh --user=$USER \
  --desktop=sway \
  --audio=alsa \
  --network=iwd \
  --file-manager=lf \
  --without=xorg --without=panel --without=wm
# Log out and `sway` starts automatically
```

**For balanced desktop (~350 MB loaded):**
```bash
sudo desktop/install.sh --user=$USER \
  --desktop=openbox \
  --audio=alsa \
  --network=iwd \
  --file-manager=lf
```

**For full-featured (X11 with all extras, ~600+ MB loaded):**
```bash
sudo desktop/install.sh --user=$USER
# (Installs Openbox + PipeWire + NetworkManager + Nemo + Chrome by default)
```

### 4. Optional: Switch Desktop Later

```bash
# Try sway without losing Openbox
sudo desktop/install.sh --user=$USER --desktop=sway --audio=pipewire

# Or go back to X11
sudo desktop/install.sh --user=$USER --desktop=openbox
```

---

## What Works Out of the Box

| Hardware | Status | Notes |
|---|---|---|
| **Display (i915)** | ✅ Works | 2560×1600, smooth |
| **Trackpad** | ✅ Works | Tap-to-click, two-finger scroll, natural scrolling |
| **Keyboard** | ✅ Works | Media keys primary (Fn toggles with fnmode=1 in hid_apple) |
| **Brightness** | ✅ Works | Screen + keyboard backlight, media keys or `brightnessctl` |
| **Audio** | ✅ Works | Cirrus CS4208, speakers + jack, PipeWire or ALSA |
| **Bluetooth** | ✅ Works | BCM20702, connected devices auto-pair |
| **Suspend** | ✅ Works | Close lid or `systemctl suspend` |
| **Wi-Fi** | ✅ Works | BCM4360 (broadcom-wl DKMS module, pre-built in ISO) |
| **Camera** | ⚠️ Optional | FaceTime HD (facetimehd-dkms, optional AUR build) |
| **Fan Control** | ⚠️ Optional | applesmc fan daemon (mbpfan, optional AUR build) |

---

## Troubleshooting

### Wi-Fi not working
```bash
# Check if broadcom-wl is loaded
lsmod | grep wl

# If not, check if it's blacklisted
cat /etc/modprobe.d/broadcom-wl.conf

# If kernel modules are missing, rebuild or use:
sudo pacman -S broadcom-wl-dkms linux-headers
```

### Sway keybindings not working
```bash
# sway uses Mod4 (Command key) by default
Cmd+Return → terminal
Cmd+E → file manager
Cmd+B → browser
Cmd+L → lock screen
Cmd+Q → close window
Cmd+Arrow keys → move focus
```

### Audio too quiet (ALSA)
```bash
# Open mixer
alsamixer
# or adjust from command line
amixer set Master 75%
```

### iwd can't connect to Wi-Fi
```bash
# Scan and connect manually
sudo iwctl
[iwctl]# station wlan0 scan
[iwctl]# station wlan0 get-networks
[iwctl]# station wlan0 connect "SSID"
[iwctl]# exit

# Set DHCP if not automatic
sudo dhclient wlan0
```

### Wayland (sway) feels sluggish vs X11
```bash
# Disable fractional scaling
swaymsg output \* scale 1

# Or switch back to X11
sudo systemctl restart display-manager
```

---

## Comparing Memory Usage

To measure your own setup:

```bash
# Boot to console (don't start desktop yet)
free -h
# Note the baseline

# Start desktop
startx  # or: sway

# In another terminal:
watch -n1 free -h

# Open file manager, then browser
# Let it idle for 5 minutes
# Record the "used" value

# Compare configs
```

See `docs/MEMORY.md` for full comparison and how to optimize further.

---

## Known Limitations

1. **Fractional scaling not supported** — Wayland at 100% DPI only
2. **Xwayland apps may stutter** — native Wayland apps recommended for sway
3. **Some fonts render smaller in sway** — adjust DPI in config if needed
4. **No display manager** — startx or `sway` from console (or install `ly`)

---

## For Developers

### Rebuilding the Kernel

```bash
cd kernel
# Change kernel options (optional)
# _HZ_ticks=300 _preempt=lazy _hugepage=madvise makepkg -si

# Or use defaults:
makepkg -si
```

### Rebuilding the ISO

```bash
cd iso
bash build.sh
# Result: out/cachyos-core-mba62-*.iso
```

### Understanding the Debloat Pipeline

See `docs/BUILD.md` and `docs/DEBLOAT.md` for:
- How `kernel/gen-config.sh` layers config fragments
- How `prune-drivers.sh` removes unused drivers
- Why the kernel is 484 modules instead of 6233

---

## Support & Feedback

This is a **single-machine distribution**. Issues specific to your MacBook Air 6,2 are welcome:

- Wi-Fi, camera, fan control quirks
- Kernel config regressions
- Installer bugs

For general CachyOS/BORE/sway questions, refer to upstream:
- CachyOS: https://github.com/CachyOS/linux-cachyos
- BORE scheduler: https://github.com/firelzrd/bore-scheduler
- sway: https://github.com/swaywm/sway

---

## Version Info

- **Kernel:** CachyOS 6.18 LTS + BORE + MacBook Air 6,2 config
- **Desktop:** Openbox 3.6 + sway 1.9 (both included)
- **ISO Date:** 2026-08-23
- **Size:** ~1 GiB (includes pre-built Wi-Fi, camera, fan drivers)

---

## Quick Reference: Desktop Installation Commands

```bash
# Default (X11, PipeWire, NetworkManager, Nemo, Chrome)
sudo desktop/install.sh --user=$USER

# Lightweight Wayland (sway, ALSA, iwd, lf, w3m)
sudo desktop/install.sh --user=$USER \
  --desktop=sway --audio=alsa --network=iwd --file-manager=lf \
  --browser=w3m --without=xorg --without=panel --without=wm

# Balanced (X11, ALSA, iwd, lf, Falkon)
sudo desktop/install.sh --user=$USER \
  --audio=alsa --network=iwd --file-manager=lf --browser=falkon

# Compare both (install X11, then re-run with sway)
sudo desktop/install.sh --user=$USER
# Log out, test, then:
sudo desktop/install.sh --user=$USER --desktop=sway --audio=alsa --network=iwd
# Log out, compare
```

---

Happy hacking! 🍎🐧
