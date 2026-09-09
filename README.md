# Cachyos-core

A debloated CachyOS **6.18 LTS + BORE** kernel and a minimal Openbox desktop,
built for exactly one machine: a **MacBookAir6,2** (13-inch, Mid 2013 /
Early 2014, Haswell-ULT).

Nothing here tries to be a general-purpose distribution. The kernel config is
an allowlist of the hardware in this laptop, and the desktop is Openbox +
xfce4-panel + Terminator + Nemo + Chrome, with the glue those five need and
nothing more.

| | stock CachyOS 6.18 LTS | this config |
|---|---|---|
| modules built | 6233 | **484** |
| built-in symbols | 3204 | 1875 |
| debug info | DWARF5 + BTF | none |
| Rust | on | off |

This config has been built end to end against `cachyos-6.18.42-1` with the
BORE patch applied: `bzImage` 13 MB, ~500 `.ko` files (~46 MB unstripped),
229 drivers linked into the image. BORE is confirmed present in the result
(`effective_prio_bore`, `update_curr_bore` and the `sched_burst_*` sysctls
are all in `System.map`), and the trackpad, keyboard, i915, AHCI and NVMe
are built in rather than modular, so the machine comes up without depending
on an initramfs.

## Layout

```
kernel/     the kernel package: PKGBUILD, base config, debloat pipeline
iso/        archiso profile + build script for the live/install image
desktop/    package list, dotfiles and installer for the Openbox session
hardware/   MacBookAir6,2 drivers, module options and quirks
docs/       INSTALL.md, BUILD.md, HARDWARE.md, DEBLOAT.md
```

## Installing

**Download the ISO, write it to a USB stick, hold Option at power-on.** The
image boots to the desktop and starts a graphical installer that copies the
running system to disk — same kernel, same desktop, same drivers, no network
needed. [docs/INSTALL.md](docs/INSTALL.md) has the details, including the
`dd` incantations for Linux, macOS and Windows.

**[⬇ cachyos-core-mba62-2026.09.09-x86_64.iso](https://github.com/Omargamal7/Cachyos-core/releases/download/iso-latest/cachyos-core-mba62-2026.09.09-x86_64.iso)**
· 1.06 GiB · [SHA256SUMS](https://github.com/Omargamal7/Cachyos-core/releases/download/iso-latest/SHA256SUMS)
· `58722935013eae474a8d1a9c38ca5a2bb091c46563c6c5c7b16dae2318923a9a`

It carries the debloated kernel, Chrome, and — compiled against that kernel
while the image is assembled — the `wl` Wi-Fi module and the `facetimehd`
camera driver with its firmware. `EFI/BOOT/BOOTx64.EFI` is present, which is
the path Apple's Startup Manager actually looks at.

To rebuild: Actions → **ISO** → Run workflow.

The MacBook Air never compiles anything. The kernel is built in CI and
published as a [package](https://github.com/Omargamal7/Cachyos-core/releases/tag/kernel-latest)
(27 MiB, vs ~130 MiB for stock `linux-cachyos`); `sudo mba62-update` pulls
the latest.

### Or, on a system you already have

If you would rather keep an existing CachyOS install and just add these
pieces:

```sh
git clone https://github.com/Omargamal7/Cachyos-core
cd Cachyos-core
sudo pacman -U ./linux-cachyos-bore-mba62-*.pkg.tar.zst   # from the releases page
sudo desktop/install.sh --user="$USER"
sudo hardware/mba62/install.sh
```

Both installers take `--dry-run`, which prints every command they would run
and changes nothing. Use it first.

## What you should know before building

**Upstream's 6.18 BORE patch is broken, and this repo carries a fix.**
Linux 6.18.36 reworked `check_preempt_wakeup_fair()`, and neither copy of
CachyOS's BORE patch has caught up: `sched/` no longer applies, and
`sched-dev/` applies but fails to compile. `kernel/` contains a
13-line adaptation. [docs/BUILD.md](docs/BUILD.md) explains it and how to
retire it once upstream refreshes.

**The config is generated and verified, not hand-maintained.**
`kernel/gen-config.sh` layers a deny-list, a generated per-driver prune and a
hardware allowlist over CachyOS's config, then asserts that all 56 symbols in
`kernel/critical-symbols.txt` survived `olddefconfig`. If one did not, the
build fails instead of producing a kernel that will not boot.

**Three drivers are not in the kernel and never will be:** the BCM4360
Wi-Fi (`broadcom-wl`), the FaceTime HD camera (`facetimehd`, plus firmware
extracted from macOS) and fan control (`mbpfan`).
[docs/HARDWARE.md](docs/HARDWARE.md) covers each one.

**Some things were deliberately removed** — KVM, Xen, bpftrace's BTF,
mac80211, XFS, NFS, all non-Intel GPUs. If you need one back,
[docs/DEBLOAT.md](docs/DEBLOAT.md) says which fragment to edit.

**Wi-Fi works on the installed system without a network.** `broadcom-wl` is
built against this kernel while the ISO is assembled, which matters on a
laptop with no ethernet port: a first boot that cannot reach the internet to
fetch its own network driver is a dead end.

## Credits

The kernel is CachyOS's — this repo only re-configures it. Upstream is
[CachyOS/linux-cachyos](https://github.com/CachyOS/linux-cachyos) and
[CachyOS/kernel-patches](https://github.com/CachyOS/kernel-patches); BORE is
[firelzrd/bore-scheduler](https://github.com/firelzrd/bore-scheduler).
