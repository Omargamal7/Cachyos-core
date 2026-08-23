# How the debloat works

The stock CachyOS 6.18 LTS config builds **6233 modules**. This one builds
**489**. Nothing here is hand-edited into a 12,000-line `.config` — the config
is generated on every build and checked afterwards, so it cannot silently rot
when the base config is refreshed.

## The pipeline

`kernel/gen-config.sh` layers four things, each winning over the last, then
runs `make olddefconfig` and verifies the result:

| layer | file | what it does |
|---|---|---|
| 1 | `kernel/config` | CachyOS's `linux-cachyos-lts` config, vendored verbatim |
| 2 | `fragments/10-strip.conf` | turns off whole subsystems by their gate symbol |
| 3 | *generated* `15-prune.conf` | per-driver pruning, from `prune-rules.conf` |
| 4 | `fragments/20-mba62.conf` | the MacBookAir6,2 hardware allowlist |
| 5 | `fragments/30-tuning.conf` | BORE, debug info, DKMS and compression settings |

Then:

| | |
|---|---|
| `make olddefconfig` | resolves dependencies and `select`s |
| `verify-config.sh` | asserts the result is still bootable and usable |

### Why three layers instead of one

**Gate symbols do the bulk of the work.** Turning off `CONFIG_SND_SOC` drops
several hundred embedded-audio modules in one line; `CONFIG_MEDIA_PCI_SUPPORT`,
`CONFIG_INFINIBAND` and `CONFIG_SCSI_LOWLEVEL` behave the same way. That is
what `10-strip.conf` is: about 380 lines, each one closing a door.

**Gates do not help inside a subsystem you need.** `CONFIG_HWMON` has to stay
on for `applesmc` — and it ships 194 sensor-chip drivers for hardware that is
not in this laptop. Same story for 118 HID drivers, 69 RTCs, 66 watchdogs.
Listing every one of those by hand would be unmaintainable and would go stale
on the first base-config refresh.

So `prune-rules.conf` expresses them as rules instead:

```
SENSORS_*        SENSORS_APPLESMC SENSORS_CORETEMP
HID_*            HID_APPLE HID_GENERIC HID_MULTITOUCH ...
RTC_DRV_*        RTC_DRV_CMOS
```

`prune-drivers.sh` reads those, walks every symbol enabled in the base config,
and writes a generated fragment disabling the matches. Anything the hardware
allowlist turns on is exempt automatically, so `20-mba62.conf` stays the single
source of truth for what this machine keeps. That produces about 3800
`is not set` lines, regenerated on every build.

### Why the verify step exists

`make olddefconfig` is allowed to overrule you. A driver you kept can `select`
something you tried to drop; a symbol you asked for can vanish because a
dependency went with the subsystem it lived in. Both happen silently.

`verify-config.sh` splits the two cases, because they mean opposite things:

* **asked for, did not get** — a mistake. `CONFIG_VIDEOBUF2_DMA_SG` quietly
  disappearing would have shipped a kernel the camera driver cannot build
  against.
* **asked to drop, kept by a `select`** — expected. 134 of these, all
  infrastructure pulled back by drivers that are staying.

On top of that, `critical-symbols.txt` lists 56 symbols the machine will not
boot or will not be usable without — the AHCI and NVMe path, `i915`, the USB
stack, `hid_apple` and `bcm5974`, `SCHED_BORE`, the namespaces and seccomp
that systemd and Chrome's sandbox require, and the two settings that keep DKMS
modules loadable. A miss there fails the build.

## What was deliberately removed

Anything below can come back by editing `kernel/fragments/10-strip.conf` (or
`prune-rules.conf`) and rebuilding.

| removed | why | cost if you want it back |
|---|---|---|
| `DEBUG_INFO`, `DEBUG_INFO_BTF` | largest single saving in build time and installed size | no `bpftrace`, no libbpf CO-RE |
| `VIRTUALIZATION` / KVM, Xen, Hyper-V, VirtualBox, VMware | this is a laptop, not a host | no local VMs |
| `MAC80211` | the BCM4360 uses FullMAC `wl`, which needs only `cfg80211` | no SoftMAC card will work |
| every non-Intel GPU | there is one GPU in this machine | — |
| `SND_SOC` | embedded codec framework; HDA is separate | — |
| TV tuners, DVB, analog capture | — | — |
| `XFS`, `NFS`, `CIFS`, `Ceph`, `F2FS`, `NTFS3`, `EROFS`, … | kept: btrfs, ext4, vfat, exfat, hfsplus, overlay, squashfs | mounting those filesystems |
| `RUST` | no in-tree Rust driver applies to Haswell | drops `rust*` build deps |
| `NUMA`, `MAXSMP`, `KEXEC`, `CRASH_DUMP`, `EDAC` | server-scale features on a 2-core laptop | no kdump |
| `INFINIBAND`, `SCSI_LOWLEVEL`, `FUSION`, `FIREWIRE`, MD RAID | — | — |
| `IIO`, `STAGING`, `PARPORT`, `PCCARD`, `ISDN`, `W1`, `SPI` | no such hardware | — |
| `NETFILTER_ADVANCED`, most xtables, IPVS, IP_SET | nftables covers a desktop firewall | complex firewall rules |
| SCTP, DCCP, TIPC, RDS, ATM, CAN, NFC, 802.15.4, HAM radio | — | — |

## Kept on purpose, even though it looks like bloat

* **`SERIO_I8042`, `KEYBOARD_ATKBD`, `MOUSE_PS2`** — this machine's keyboard
  and trackpad are USB, so in theory these are dead weight. They are built in
  anyway: they cost a few tens of kilobytes, and being wrong about it means a
  laptop with no keyboard at boot.
* **`MMC_REALTEK_PCI` and friends** — three modules covering the possibility
  that a given unit's SD reader is PCIe rather than USB.
* **`BRCMFMAC`** — for units serviced with a 43602-based card.
* **`IA32_EMULATION`** — small, and disabling it breaks 32-bit binaries in
  surprising places.
* **`VIDEO_IPU3_CIO2`** — an Intel IPU3 driver on a 2013 laptop, enabled only
  because it is the cheapest x86 selector for `videobuf2-dma-sg`, which
  `facetimehd` links against. See [HARDWARE.md](HARDWARE.md).

## Changing the hardware target

If you are adapting this to a different Mac, the files to edit in order are:

1. `kernel/fragments/20-mba62.conf` — the allowlist. Everything else is
   subtractive; this is where hardware gets named.
2. `kernel/critical-symbols.txt` — what must survive.
3. `hardware/mba62/modprobe.d/` — module options and blacklists.

`10-strip.conf` and `prune-rules.conf` are mostly model-independent for any
Intel Mac laptop.
