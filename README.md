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
| modules built | 6233 | **489** |
| built-in symbols | 3204 | 1880 |
| debug info | DWARF5 + BTF | none |

## Layout

```
kernel/     the kernel package: PKGBUILD, base config, debloat pipeline
desktop/    package list, dotfiles and installer for the Openbox session
hardware/   MacBookAir6,2 drivers, module options and quirks
docs/       BUILD.md, HARDWARE.md, DEBLOAT.md
```

## Quick start

On the target machine, running CachyOS:

```sh
git clone https://github.com/Omargamal7/Cachyos-core
cd Cachyos-core

# 1. Build and install the kernel (takes a while on a 2013 dual-core)
cd kernel && makepkg -si && cd ..

# 2. The desktop
sudo desktop/install.sh --user="$USER"

# 3. The drivers that are not in the kernel tree
sudo hardware/mba62/install.sh
```

Then reboot into the new kernel and run `startx`.

Both installers take `--dry-run`, which prints every command they would run
and changes nothing. Use it first.

## What you should know before building

**Upstream's 6.18 BORE patch is broken, and this repo carries a fix.**
Linux 6.18.36 reworked `check_preempt_wakeup_fair()`, and neither copy of
CachyOS's BORE patch has caught up: `sched/` no longer applies, and
`sched-dev/` applies but fails to compile. `kernel/patches/` contains a
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

## Credits

The kernel is CachyOS's — this repo only re-configures it. Upstream is
[CachyOS/linux-cachyos](https://github.com/CachyOS/linux-cachyos) and
[CachyOS/kernel-patches](https://github.com/CachyOS/kernel-patches); BORE is
[firelzrd/bore-scheduler](https://github.com/firelzrd/bore-scheduler).
