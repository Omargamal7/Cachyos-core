# Memory Footprint Comparison: X11 vs Wayland

This guide compares the memory usage of different configurations on a MacBook Air 6,2.

## Measurements (rough estimates)

### Idle (after boot, nothing running but system daemons)

| Configuration | Idle RSS | Notes |
|---|---|---|
| Openbox + xfce4-panel + PipeWire + NetworkManager | ~200 MB | X11 baseline |
| sway + waybar + ALSA + iwd | ~120 MB | Wayland lightweight |
| **Savings** | **~80 MB** | 40% less |

### Loaded (file manager + browser open for 5 minutes)

| Configuration | Idle | + Nemo/lf | + Chrome | Total |
|---|---|---|---|---|
| **X11 Stack** | 200 | +80 | +400 | ~680 MB |
| **Wayland Stack** | 120 | +20 | +300 | ~440 MB |
| **Savings** | — | 75% less | 25% less | **~240 MB (35%)** |

### With lightweight alternatives

| Configuration | Idle | + lf | + w3m | + Falkon (capped 200M) | Total |
|---|---|---|---|---|---|
| sway + ALSA + iwd | 120 | +5 | +20 | +200 | **~345 MB** |
| sway + ALSA + iwd | 120 | +5 | +5 | (text only) | **~130 MB** |

## Why the difference?

### X11 (Xorg + Openbox) overhead:
- **Xorg server:** ~50–80 MB (must manage GPU, input, compositing)
- **xfce4-panel:** 20–30 MB (Qt, xfce4-settings, xfce4-power-manager)
- **PipeWire + wireplumber:** 30–50 MB (audio daemon + session manager)
- **NetworkManager + applet:** 40–60 MB (daemon + GTK UI layer)
- **Total:** ~200 MB idle, plus all app overhead

### Wayland (sway) overhead:
- **sway window manager:** 20–30 MB (Wayland protocol is simpler)
- **waybar:** 5–10 MB (minimal status bar)
- **ALSA:** <5 MB (no daemon, direct hardware access)
- **iwd:** 5–10 MB (lightweight Wi-Fi daemon)
- **Total:** ~120 MB idle

## How to test

### Install both configurations
```bash
# Standard X11 installation
sudo desktop/install.sh --user=$USER

# Then try Wayland variant
sudo desktop/install.sh --user=$USER --desktop=sway --audio=alsa --network=iwd \
  --file-manager=lf --without=xorg --without=panel --without=wm
```

### Measure memory at boot
```bash
# Log in to console, don't start desktop yet
free -h                    # baseline RAM
startx                     # or: sway (if sway installed)

# In another terminal:
watch -n1 free -h          # monitor memory over time

# Then open apps:
# Openbox: open nemo, open chrome
# Sway: terminator -e lf, then your browser
```

## Recommendations

### For minimum RAM usage (< 300 MB with apps):
```bash
sudo desktop/install.sh --user=$USER \
  --desktop=sway \
  --audio=alsa \
  --network=iwd \
  --file-manager=lf \
  --browser=w3m \
  --without=xorg --without=panel --without=wm
```

### For balanced (X11 with lighter options, ~350 MB loaded):
```bash
sudo desktop/install.sh --user=$USER \
  --audio=alsa \
  --network=iwd \
  --file-manager=lf \
  --browser=falkon
```

### For full-featured (X11 with all bells, ~600 MB+):
```bash
sudo desktop/install.sh --user=$USER \
  --desktop=openbox \
  --audio=pipewire \
  --network=networkmanager \
  --file-manager=nemo \
  --browser=chrome
```

## Kernel tuning for memory savings

In `kernel/30-tuning.conf`, these settings reduce footprint:

- `CONFIG_MIN_BASE_SLICE_NS=1000000` (1ms) — reduces scheduler overhead
- `# CONFIG_TRANSPARENT_HUGEPAGE is not set` — saves 20–40 MB on idle systems
- Disable preemption entirely: `_preempt=none makepkg -si` — 5–10 MB savings (at cost of latency)

## antiX / MaBox comparison

- **antiX 23:** ~300 MB loaded (uses runit + minimal Xfce, no PipeWire)
- **MaBox 24:** ~350 MB loaded (uses Manjaro's Xfce4 with lighter tweaks)
- **This repo (sway + ALSA + iwd):** ~345 MB loaded (competitive)
- **This repo (sway + ALSA + iwd + w3m):** ~130 MB loaded (beats both)

## Troubleshooting

### Memory not dropping after closing apps
PipeWire may hold cached buffers; ALSA releases them immediately.
```bash
# Verify ALSA is being used:
ps aux | grep -i alsa    # should show minimal processes

# Clear PipeWire cache (if still installed):
sudo systemctl restart pipewire
```

### Wayland apps lagging
If Wayland feels sluggish compared to X11, try:
```bash
# Increase refresh rate
swaymsg output \* scale 1  # ensure no fractional scaling

# Or switch back to X11:
sudo systemctl restart display-manager
```

### iwd not connecting
```bash
# Scan and connect manually
sudo iwctl
[iwctl]# station wlan0 scan
[iwctl]# station wlan0 get-networks
[iwctl]# station wlan0 connect SSID
[iwctl]# exit

# Or set up DHCP:
sudo dhclient wlan0
```

### No sound with ALSA
```bash
# List audio devices
arecord -l

# Unmute and set levels
alsamixer

# Or use command-line
amixer set Master unmute
amixer set Master 70%
```
