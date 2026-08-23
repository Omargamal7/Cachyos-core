#!/usr/bin/env bash
# Produce the debloated .config for an unpacked (and BORE-patched) kernel tree.
#
#   gen-config.sh <kernel-source-dir> [output-config]
#
# Layers, in order, each winning over the last:
#   kernel/config                    CachyOS 6.18 LTS base
#   kernel/fragments/10-strip.conf   subsystem deny-list
#   (generated) 15-prune.conf        per-driver pruning, from prune-rules.conf
#   kernel/fragments/20-mba62.conf   MacBookAir6,2 hardware allowlist
#   kernel/fragments/30-tuning.conf  size / scheduler / DKMS settings
#
# then `make olddefconfig` resolves dependencies and verify-config.sh checks
# that nothing we asked for was silently dropped.
set -euo pipefail

src="${1:?usage: gen-config.sh <kernel-source-dir> [output-config]}"
out="${2:-}"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

[[ -f $src/Makefile && -d $src/kernel ]] || {
    echo "gen-config: $src does not look like a kernel tree" >&2; exit 2; }

# Fragments live in kernel/fragments/ in the repo, but makepkg flattens
# every local source into $srcdir, so accept either layout.
_find() {
    if   [[ -f $here/fragments/$1 ]]; then printf '%s' "$here/fragments/$1"
    elif [[ -f $here/$1 ]];           then printf '%s' "$here/$1"
    else echo "gen-config: cannot find $1" >&2; exit 2
    fi
}

prune="$src/15-prune.conf"
"$here/prune-drivers.sh" "$here/config" "$prune" \
    "$(_find 20-mba62.conf)" "$(_find 30-tuning.conf)"

fragments=(
    "$(_find 10-strip.conf)"
    "$prune"
    "$(_find 20-mba62.conf)"
    "$(_find 30-tuning.conf)"
)

echo ":: merging base config + ${#fragments[@]} fragments"
# -m: merge only, we run olddefconfig ourselves so kconfig resolves against
# the patched tree (BORE adds SCHED_BORE and MIN_BASE_SLICE_NS).
"$src/scripts/kconfig/merge_config.sh" -m -O "$src" \
    "$here/config" "${fragments[@]}" > "$src/.merge.log"
grep -E '^(Value of|Previous value)' "$src/.merge.log" | head -20 || true
rm -f "$src/.merge.log"

echo ":: make olddefconfig"
make -C "$src" olddefconfig >/dev/null

echo ":: verifying"
"$here/verify-config.sh" "$src/.config" "${fragments[@]}"

if [[ -n $out ]]; then
    cp "$src/.config" "$out"
    echo ":: wrote $out"
fi
