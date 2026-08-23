# Building the kernel

## What gets built

`linux-cachyos-bore-mba62` and `linux-cachyos-bore-mba62-headers`, from
CachyOS's `cachyos-6.18.42-1` source tarball plus the BORE scheduler.

6.18 is a longterm release, which is why it is the base here: the machine
gets years of stable fixes without another config migration.

## Prerequisites

An Arch or CachyOS system with `base-devel`, and the CachyOS signing keys so
`makepkg` can verify the tarball:

```sh
gpg --recv-keys E18447AC260021D31F3FF6C4C8A2A4774B8B63C4 \
                E8B9AA39F054E30E8290D492C3C4820857F654FE
```

You do **not** need `rust`, `rust-bindgen` or `rust-src`: `CONFIG_RUST` is
off (no in-tree Rust driver applies to 2013 Haswell hardware).

## Building

```sh
cd kernel
makepkg -si
```

Build options are environment variables, read at the top of the PKGBUILD:

| variable | default | notes |
|---|---|---|
| `_HZ_ticks` | `1000` | 300 saves a little power |
| `_preempt` | `full` | `full` / `lazy` / `voluntary` / `none` |
| `_processor_opt` | `generic_v3` | see below |
| `_cc_harder` | `yes` | `-O3` instead of `-O2` |
| `_hugepage` | `always` | `always` / `madvise` |
| `_makenconfig` | `no` | drop into `nconfig` before compiling |

```sh
_HZ_ticks=300 _preempt=lazy makepkg -si
```

### Why `generic_v3` and not `native`

Haswell-ULT implements x86-64-v3 (AVX2, BMI2, FMA), so `generic_v3` gives the
same instruction set `native` would — but it is safe to build on a *different*
machine. `native` bakes in the builder's CPU, which produces a kernel that
will not boot on the laptop if you build it anywhere else. Only use `native`
when compiling on the MacBook itself.

## The BORE patch problem

**This is the part most likely to bite you.** Upstream CachyOS's 6.18 BORE
patch does not work against current 6.18 point releases, and this repo carries
a local fix.

Linux 6.18.36 reworked `check_preempt_wakeup_fair()` in `kernel/sched/fair.c`,
replacing the local `bool do_preempt_short` with
`enum preempt_wakeup_action preempt_action`. `cachyos/kernel-patches` has two
copies of the BORE patch for 6.18 and both still target the older shape:

| patch | against `cachyos-6.18.42-1` |
|---|---|
| `6.18/sched/0001-bore-cachy.patch` | **fails to apply** — one hunk rejected |
| `6.18/sched-dev/0001-bore-cachy.patch` | applies cleanly, then **fails to compile** |

The `sched-dev` failure is the nastier of the two, because the patch looks
fine until the build reaches `kernel/sched/fair.o`:

```
kernel/sched/fair.c: In function 'check_preempt_wakeup_fair':
kernel/sched/fair.c:9010:17: error: 'do_preempt_short' undeclared
```

So the PKGBUILD takes `sched-dev` and applies
`0002-bore-fix-preempt-wakeup-action.patch` on top. That patch moves
BORE's slice-protection bypass next to the in-tree `PREEMPT_SHORT` check —
which the BORE block's own comment calls its companion — and gives it the
same treatment that path now uses:

```c
preempt_action = PREEMPT_WAKEUP_SHORT;
goto pick;
```

which is what `do_preempt_short = true` used to produce: at `pick:` the flag
selects `pick_next_entity()`'s non-protecting variant, and at `preempt:` it
triggers `cancel_protect_slice()`.

### Retiring the fixup

The BORE patch is fetched from `master` of `cachyos/kernel-patches`, which
is a moving target, and its `b2sum` is pinned here. So when CachyOS
refreshes it you get a checksum failure from `makepkg` before anything is
built — which is the point: it forces a look rather than silently applying a
patch on top of a patch. At that point:

1. Check whether `sched/0001-bore-cachy.patch` applies again — if it does,
   switch `_patchsource` back to `sched/` in the PKGBUILD.
2. Delete `0002-bore-fix-preempt-wakeup-action.patch` from `source=()`
   and from `prepare()`.
3. Update the patch's `b2sum`.

## Bumping to a newer 6.18.x

CachyOS tags each point release as `cachyos-6.18.<minor>-<rel>`:

```sh
git ls-remote --tags https://github.com/CachyOS/linux \
  | grep -o 'cachyos-6\.18\.[0-9]*-[0-9]*' | sort -V | tail -3
```

Then in `kernel/PKGBUILD` set `_minor`, and update the tarball `b2sum`
(`makepkg -g` prints the new sums). Refresh the base config at the same time:

```sh
scripts/update-base-config.sh
```

That pulls CachyOS's current `linux-cachyos-lts/config` into `kernel/config`.
The debloat fragments are layered over whatever that file contains, so a
refreshed base does not silently re-enable anything — but do re-read the
`verify-config.sh` output afterwards.

## Verifying a config without building

`gen-config.sh` works standalone against any unpacked, BORE-patched tree:

```sh
kernel/gen-config.sh /path/to/linux-source /tmp/out.config
VERBOSE=1 kernel/verify-config.sh /tmp/out.config kernel/*.conf
```

It exits non-zero if any symbol in `critical-symbols.txt` is missing, so it
is usable as a CI check.
