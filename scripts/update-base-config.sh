#!/usr/bin/env bash
# Refresh kernel/config from CachyOS's current linux-cachyos-lts config.
#
#   scripts/update-base-config.sh [--check]
#
# The debloat fragments are layered over whatever this file contains, so a
# refresh cannot silently re-enable anything -- but it can move symbols
# around, so re-run gen-config.sh afterwards and read the verify output.
#
# --check exits 1 if the upstream config differs, without writing anything.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
dest="$here/kernel/config"
url="https://raw.githubusercontent.com/CachyOS/linux-cachyos/master/linux-cachyos-lts/config"

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

echo ":: fetching $url"
curl -fsSL "$url" -o "$tmp"

grep -q '^CONFIG_' "$tmp" || { echo "that does not look like a kernel config" >&2; exit 1; }

if cmp -s "$tmp" "$dest"; then
    echo ":: already up to date ($(grep -c '=m$' "$dest") modules)"
    exit 0
fi

if [[ ${1:-} == --check ]]; then
    echo ":: upstream config differs:"
    diff -u "$dest" "$tmp" | head -40
    exit 1
fi

echo ":: $(grep -c '=m$' "$dest") -> $(grep -c '=m$' "$tmp") modules in the base config"
cp "$tmp" "$dest"
echo ":: updated $dest"
echo
echo "Now regenerate and check the result:"
echo "  kernel/gen-config.sh /path/to/unpacked/kernel /tmp/out.config"
