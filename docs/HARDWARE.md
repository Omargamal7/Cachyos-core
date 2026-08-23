# MacBookAir6,2 hardware

13-inch MacBook Air, Mid 2013 / Early 2014. Everything below was checked
against the Linux 6.18 source rather than recalled from forum posts; where a
claim depends on your particular unit, the check to run is given.

## What the kernel handles on its own

| Part | Device | Driver | Config |
|---|---|---|---|
| CPU | Haswell-ULT (i5-4250U / i5-4260U / i7-4650U) | `intel_pstate`, `intel_idle` | built in |
| GPU | Intel HD Graphics 5000 (GT3) | `i915` | built in |
| Storage | PCIe SSD behind AHCI | `ahci` | built in |
| Audio | Intel Lynx Point-LP HDA + Cirrus CS4208 | `snd_hda_intel`, `snd_hda_codec_cs420x` | module |
| Trackpad | Wellspring8 (05ac:0290/0291/0292) | `bcm5974` | built in |
| Keyboard | Apple internal USB | `hid_apple` | built in |
| Bluetooth | Broadcom BCM20702 | `btusb` | module |
| Sensors, fan, keyboard backlight | Apple SMC | `applesmc` | module |
| Thunderbolt 1 | Cactus Ridge | `thunderbolt` (`CONFIG_USB4`) | module |
| EFI properties | Apple device properties | `APPLE_PROPERTIES` | built in |

Boot-critical drivers are built in rather than modular, so the machine comes
up without depending on an initramfs. A LUKS root still needs one — see
"dm-crypt" below.

### Audio needs no quirk

A lot of old advice says to set `options snd_hda_intel model=mba6`. You do
not need it. The kernel matches this machine by codec SSID in
`sound/hda/codecs/cirrus/cs420x.c`:

```c
SND_PCI_QUIRK(0x106b, 0x7200, "MacBookAir 6,2", CS4208_MBA6),
```

and applies the fixup automatically. The `model=` line is only a fallback if
headphone/speaker switching misbehaves; it is commented out in
`modprobe.d/40-mba62-audio.conf`.

### Keyboard behaviour

`modprobe.d/10-mba62-input.conf` sets `hid_apple fnmode=1`, which makes the
media keys primary and `Fn`+F1..F12 produce F1..F12 — what macOS does. The
kernel's own default is `fnmode=3` (auto). Set `fnmode=2` if you would rather
have plain function keys.

The other two knobs there are `iso_layout` (swaps backtick/tilde with
greater-than/less-than; `-1` auto-detects) and `swap_opt_cmd` (`1` gives PC
Alt/Super placement).

## What needs out-of-tree drivers

### Wi-Fi — Broadcom BCM4360

This is the one part with no in-tree option. The card is `14e4:43a0`, and
`brcmfmac` does not support it — checking `pcie.c` in 6.18, its PCIe device
table covers 43602, 4350, 4356, 4358, 4359, 4364, 4371 and friends, but not
4360. It needs the proprietary `wl` module:

```sh
pacman -S broadcom-wl-dkms
```

Confirm what you actually have before assuming:

```sh
lspci -nn | grep -i net
```

If it reports `14e4:43ba`, `14e4:43a3` or `14e4:4365`, your unit was serviced
with a different card and `brcmfmac` is the right driver — the kernel keeps it
as a module for exactly that case. Remove
`/etc/modprobe.d/20-mba62-wifi.conf` (which blacklists it) and skip
`broadcom-wl-dkms`.

Because `wl` is a FullMAC driver that talks to `cfg80211` directly, this
kernel has **`mac80211` disabled entirely**. That removes a large amount of
code, but it also means no SoftMAC driver will work — if you ever swap in an
Intel or Atheros card, re-enable `CONFIG_MAC80211` in
`kernel/20-mba62.conf`.

### Camera — FaceTime HD

The camera is a Broadcom 1570 PCIe device (`14e4:1570`) driven by
[facetimehd](https://github.com/patjak/facetimehd), which is out of tree and
needs firmware Apple does not redistribute. `facetimehd-firmware` extracts it
from an Apple driver package at build time, so that step needs network access.

```sh
paru -S facetimehd-dkms facetimehd-firmware
```

The driver links against `videobuf2-dma-sg`, which has no Kconfig prompt of
its own — it only ever appears via another capture driver's `select`. With
every TV tuner and SoC ISP stripped out, nothing selected it, so
`kernel/20-mba62.conf` enables `VIDEO_IPU3_CIO2` purely to pull
`videobuf2-dma-sg.ko` into the build. That is why an Intel IPU3 driver is in
the config of a 2013 laptop. If you skip the camera, both can go.

### Fan control — mbpfan

`applesmc` exposes the fan and temperatures but nothing drives them, and the
stock firmware only ramps up once the CPU is already hot. `mbpfan` reads
`applesmc` and adjusts the fan; `hardware/mba62/mbpfan.conf` starts it earlier
and more gradually than the defaults.

## Things worth checking after a fresh install

```sh
lsmod | grep -E '^(wl|bcm5974|applesmc|facetimehd)'  # drivers loaded
sensors                                              # SMC temperatures
wpctl status                                         # audio sink present
nmcli device                                         # Wi-Fi sees the card
ls /sys/class/leds/smc::kbd_backlight                # keyboard backlight
ls /sys/class/backlight/intel_backlight              # panel backlight
cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_driver   # intel_pstate
```

## dm-crypt and LUKS

`CONFIG_DM_CRYPT` is a module, not built in — the kernel caps it at `=m`
because it `depends on (ENCRYPTED_KEYS || ENCRYPTED_KEYS=n)` and
`ENCRYPTED_KEYS` is itself modular. This costs nothing in practice: a LUKS
root needs an initramfs for the passphrase prompt regardless, and
mkinitcpio's `encrypt` / `sd-encrypt` hook pulls the module in.

## The SD card slot

The SDXC slot on this model is USB-attached, so `usb-storage` (built in)
covers it. In case a particular unit differs, the config also keeps the small
Realtek PCIe reader modules (`MMC_REALTEK_PCI`, `MISC_RTSX_PCI`) — three
modules as cheap insurance against a wrong assumption.

## Graphics driver choice

`hardware/mba62/X11/xorg.conf.d/20-intel.conf` uses xorg-server's built-in
`modesetting` driver with `TearFree`, which is what upstream recommends for
Haswell and newer. `xf86-video-intel` (the older SNA/UXA driver) is still
around and occasionally smoother on Ivy Bridge and older, but it is
unmaintained. If you install it, **delete that file** — the two drivers fight
over the device and X will fail to start.
