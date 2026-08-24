# Performance on a 4 GB MacBookAir6,2

## The rule this document follows

**No number appears here unless it came from a run you can point at.** The
tables below have empty cells. `scripts/mba62-bench.sh` fills them in from your
machine. A figure that has not been measured is written as "unmeasured", not as
a plausible-looking estimate.

That is not pedantry. Every plausible-looking estimate in this repository's
history has been wrong, and the ones that were wrong were also the ones that
looked most confident.

## What actually constrains this machine

4 GB of soldered LPDDR3, a two-core Haswell-ULT, and Chrome. Memory pressure is
the binding constraint; the CPU is idle most of the time and the GPU is idle
almost always. So the work here is about what happens when memory runs out,
and only then about anything else.

## What changed

### Swap exists now

As installed, this system had no swap of any kind. Calamares creates no swap
partition in this profile, and although the base config sets
`CONFIG_ZSWAP_DEFAULT_ON=y`, zswap is a compressed cache *in front of* a swap
device -- with no swap device, it has nothing to do. That leaves the kernel one
way to reclaim memory under pressure: evict page cache, and keep evicting until
there is none left and the OOM killer runs. That is the "everything freezes,
then Chrome dies" failure mode.

- `hardware/mba62/systemd/zram-generator.conf` -- 2 GB of zstd-compressed swap
  in RAM (`zram-size = ram / 2`).
- `hardware/mba62/sysctl.d/99-mba62-memory.conf` -- the four vm settings that
  make swap-in-RAM behave, from the [Arch Wiki's zram page][zram]. Each is
  commented with what it does, quoting `Documentation/admin-guide/sysctl/vm.rst`.
- `zswap.enabled=0` on the kernel command line, because zswap in front of zram
  compresses every page twice. `mm/Kconfig` names this parameter as the
  documented way to override `ZSWAP_DEFAULT_ON`.

Verify after boot: `zramctl`, `swapon --show`, `cat /proc/pressure/memory`.

[zram]: https://wiki.archlinux.org/title/Zram

### CPU mitigations are off

`mitigations=off` is now on the installed system's command line. This turns off
Spectre, Meltdown, MDS, L1TF and the rest. Haswell pays for those on every
syscall and context switch, and this is a single-user laptop, so the trade was
taken deliberately.

**What it costs you:** these mitigations exist because a process on the machine
-- including JavaScript in a browser tab -- can otherwise read memory it has no
right to. Turning them off is a real reduction in security, not a formality.

**To get them back:** delete the word `mitigations=off` from
`GRUB_CMDLINE_LINUX_DEFAULT` in `/etc/default/grub` and run `grub-mkconfig -o
/boot/grub/grub.cfg`. To test without committing, press `e` at the GRUB menu,
edit the line, and press Ctrl-X to boot once.

Verify which state you are in: `grep . /sys/devices/system/cpu/vulnerabilities/*`,
or the `cpu vulnerabilities` section of `scripts/mba62-bench.sh facts`.

### Smaller things

- `nowatchdog` -- drops the soft-lockup and NMI hard-lockup detectors.
- `desktop/install.sh` now creates dotfile directories owned by the target user.
  `install -D` applies `-o`/`-g` to the file only, so `~/.config/sway` was
  being created root-owned.

## What deliberately did not change

This section is the useful half. Each of these was examined and left alone, for
a reason that is written down so it does not get re-litigated.

| Thing | Current | Why it stays |
|---|---|---|
| Tick rate | `_HZ_ticks=1000` | 1000 Hz is the right call when the priority is interactive latency. It costs power; that is the accepted trade. |
| Preemption | `_preempt=full` | Same reasoning. Lower-latency preemption is what "responsiveness" means. |
| `CONFIG_NO_HZ_FULL` | `y` | Inherited from CachyOS and **free here**: `tick_nohz_full_setup()` is only reached from `housekeeping_setup()` in `kernel/sched/isolation.c`, i.e. from `nohz_full=`/`isolcpus=`. Without those parameters `tick_nohz_full_running` stays false and `context_tracking_key` is never incremented, so the static branches are patched out. |
| I/O scheduler | kernel default | The SSD is single-queue AHCI, whose default is already `mq-deadline`. `cachyos-settings` -- which ships `60-ioschedulers.rules` -- is not installed on this image, and its rule would set `mq-deadline` for this device anyway. A udev rule here would be a no-op that looked like tuning. |
| MGLRU | `CONFIG_LRU_GEN_ENABLED=y` | Already on, and already the right default for a small-memory machine. |
| Transparent hugepages | `always` | Plausibly worth changing on 4 GB, entirely unmeasured. It is a boot parameter, so measure it rather than assume: see below. |
| BORE `MIN_BASE_SLICE_NS` | `2000000` (upstream) | A latency knob. Changing it without measuring latency is guessing. |

## Choosing a Wayland compositor

There are more lightweight Wayland compositors than anyone can keep track of,
and most comparisons of them are vibes. Here is what can actually be checked:
what is in the official Arch repositories, how big it is, and how many
dependencies it drags in. Sizes are from the repositories on 2026-08-24 via
`archlinux.org/packages`.

| Compositor | Repo | Version | Installed | Deps | Model |
|---|---|---|---|---|---|
| **labwc** | extra | 0.20.1 | 0.7 MiB | 16 | stacking, Openbox-shaped config |
| river | extra | 0.4.8 | 1.1 MiB | 8 | tiling, configured by a shell script |
| sway | extra | 1.12 | 5.6 MiB | 15 | tiling, i3-compatible |
| wayfire | extra | 0.11.0 | 8.8 MiB | 21 | stacking, plugin/effects oriented |
| niri | extra | 26.04 | 24.9 MiB | 14 | scrolling tiler |
| hyprland | extra | 0.56.2 | 64.5 MiB | 63 | tiling, effects |
| cage | extra | 0.3.1 | 0.1 MiB | 5 | single-window kiosk, not a desktop |
| *(openbox)* | extra | 3.6.1 | 1.2 MiB | 9 | *the X11 session, for reference* |

dwl, wlmaker, hikari, japokwm, miriway, velox and vivarium are **not** in the
official repositories, so using one means the AUR and a build. That is a real
cost on a machine this size and the reason none of them is wired up here.

**Installed size is not memory use.** It is a bound on how much code there is,
not on how much of it runs. The only number that matters is what the
compositor costs on this machine with your workload, which is what
`scripts/mba62-bench.sh` measures.

### Why labwc is the one wired up

Not because it is smallest, though it is. Because comparing Openbox-on-X11
against a *tiling* compositor changes two things at once -- the display
protocol and the entire window-management model -- and leaves you unable to
say which one you are reacting to. labwc is stacking, reads `rc.xml`,
`menu.xml` and `autostart` under the same names, and takes the same `W-` key
syntax, so `desktop/skel/.config/labwc/rc.xml` is a near line-for-line
translation of the Openbox bindings. Switch between them and the only thing
that changed is X11 vs Wayland.

sway is wired up too, as the tiling option. It is a different way to work, not
just a different protocol -- worth trying on its own merits, but it is not the
experiment that answers "is Wayland lighter here".

### Adding another one

Three edits, by design:

1. A group in `desktop/packages.txt` (`[river]`, say).
2. A skel directory: `desktop/skel/.config/river/`.
3. A row in the `session_skip` table in `desktop/install.sh`, and a branch in
   `desktop/skel/.bash_profile` so the session starts on tty1.

Then measure it against the others rather than arguing about it.

## Measuring, instead of guessing

```sh
scripts/mba62-bench.sh facts                          # what this machine is
scripts/mba62-bench.sh sample --label before          # then use the machine for 5 min
# change one thing, reboot if needed
scripts/mba62-bench.sh sample --label after           # do the same thing again
scripts/mba62-bench.sh diff bench/before-*.txt bench/after-*.txt
```

The metric that matters is **PSI stall time** from `/proc/pressure/memory`, not
`free`. `free` tells you how memory is labelled; PSI tells you how long tasks
actually spent waiting, which is what "it feels slow" is. `full` stall time on
memory is the number that corresponds to the machine locking up.

Process memory is reported as **PSS**, not RSS. RSS charges every shared page in
full to every process mapping it, so summing RSS across Chrome's process tree
over-counts badly -- that is where most "Chrome uses N MB" figures come from.

Before trusting any difference, run the *same* configuration twice. That tells
you how much this workload varies on its own, which is the floor below which a
difference means nothing.

### Things worth measuring first

1. **THP `always` vs `madvise`.** Boot with `transparent_hugepage=madvise`,
   sample, compare. No rebuild needed.
2. **zram `zstd` vs `lzo-rle`.** Change `compression-algorithm` in
   `/etc/systemd/zram-generator.conf`, reboot, sample. The bench script prints
   the compression ratio so you can see what the CPU cost bought.
3. **`mitigations=off` vs on.** One GRUB edit, no rebuild. This is the largest
   single CPU-side difference available on this machine, and now you can price
   it rather than believe a blog post.

## Results

Fill these in from your own runs. Empty means not yet measured.

System changes, one at a time:

| Configuration | mem `full` stall | mem `some` stall | MemAvailable min | swap peak |
|---|---|---|---|---|
| Baseline (before zram) | | | | |
| zram + sysctls | | | | |
| + `mitigations=off` | | | | |
| + `transparent_hugepage=madvise` | | | | |

Sessions, same workload, same duration, on whichever system configuration you
settled on above:

| Session | mem `full` stall | MemAvailable min | compositor PSS | notes |
|---|---|---|---|---|
| Openbox (X11) | | | | |
| labwc (Wayland) | | | | |
| sway (Wayland) | | | | |
