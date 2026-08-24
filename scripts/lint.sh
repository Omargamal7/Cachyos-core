#!/usr/bin/env bash
# Fast checks: syntax, schemas, and the installer's actual behaviour.
#
#   bash scripts/lint.sh          # everything that does not need root
#   sudo bash scripts/lint.sh     # ...plus the real installer runs
#
# Everything here finishes in seconds and needs no Arch container, which is the
# point: the kernel and ISO builds take an hour, so they cannot be the thing
# standing between a bad change and the default branch.
#
# The checks are not generic linting. Each one exists because something it
# would have caught actually reached this repository:
#
#   * dotfiles installed to $HOME/<repo path>/desktop/skel/... because a quoted
#     prefix in ${var#...} was written with backslashes
#   * an installer that lost its exec bit
#   * package groups renamed, silently voiding documented --without= flags
#   * a kernel fragment value with a trailing comment, which kconfig rejects as
#     an invalid int and quietly drops
#   * XML that is not well-formed, which fails at login rather than at build
set -uo pipefail   # deliberately not -e: run every check, then report

cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1
fails=0
ok()   { printf '  ok    %s\n' "$*"; }
bad()  { printf '  FAIL  %s\n' "$*"; fails=$((fails + 1)); }
skip() { printf '  skip  %s\n' "$*"; }
have() { command -v "$1" >/dev/null 2>&1; }
section() { printf '\n== %s ==\n' "$*"; }

# Files with a shell shebang. Selected by shebang, not extension: this repo has
# a Python script called prune-drivers.sh on purpose.
# Found with find rather than `git ls-files`: this has to work in a checkout
# the caller does not own (git refuses those), in a worktree, and in a tarball.
mapfile -t shell_files < <(find . -type f -not -path './.git/*' | sed 's|^\./||' | sort |
    while read -r f; do
        head -1 "$f" 2>/dev/null | grep -qE '^#!.*(bash|/sh|dash|ksh)' && echo "$f"
    done)
# Sourced fragments have no shebang and must be named explicitly.
sourced_files=(desktop/skel/.bash_profile desktop/skel/.config/openbox/autostart
               desktop/skel/.config/labwc/autostart desktop/skel/.config/openbox/environment)

section "shell syntax"
for f in "${shell_files[@]}" "${sourced_files[@]}"; do
    [[ -e $f ]] || continue
    bash -n "$f" 2>/dev/null && ok "$f" || bad "$f does not parse"
done

section "shellcheck"
if have shellcheck; then
    if shellcheck -S warning "${shell_files[@]}"; then ok "no findings at warning level"
    else bad "shellcheck findings above"; fi
    for f in "${sourced_files[@]}"; do
        [[ -e $f ]] || continue
        # No shebang, so the dialect has to be given explicitly.
        shellcheck -S warning -s bash "$f" && ok "$f" || bad "$f"
    done
else
    skip "shellcheck not installed"
fi

section "executable bits"
# An installer that is not executable fails at `sudo desktop/install.sh`.
for f in desktop/install.sh hardware/mba62/install.sh iso/build.sh \
         kernel/gen-config.sh kernel/verify-config.sh scripts/mba62-bench.sh; do
    [[ -e $f ]] || continue
    [[ -x $f ]] && ok "$f is executable" || bad "$f is not executable"
done

section "XML is well-formed"
# xmllint also rejects "--" inside a comment, which is what makes this worth
# running against hand-written config.
while read -r f; do
    xmllint --noout "$f" 2>/dev/null && ok "$f" || bad "$f is not well-formed XML"
done < <(find . -type f -name '*.xml' -not -path './.git/*' | sed 's|^\./||' | sort)

section "JSON and YAML parse"
python3 - <<'PY'
import json, re, sys, pathlib
rc = 0
for f in pathlib.Path(".").glob("desktop/skel/.config/**/*.jsonc"):
    try:
        json.loads(re.sub(r'^\s*//.*$', '', f.read_text(), flags=re.M)); print(f"  ok    {f}")
    except Exception as e:
        print(f"  FAIL  {f}: {e}"); rc = 1
try:
    import yaml
    for f in pathlib.Path("iso/airootfs/etc/calamares").rglob("*.conf"):
        try:
            yaml.safe_load(f.read_text()); print(f"  ok    {f}")
        except Exception as e:
            print(f"  FAIL  {f}: {e}"); rc = 1
except ImportError:
    print("  skip  pyyaml not installed")
sys.exit(rc)
PY
[[ $? -eq 0 ]] || fails=$((fails + 1))

section "kernel config fragments"
# CONFIG_FOO=1000    # comment  is not a comment to kconfig: it makes the value
# invalid, so the symbol silently reverts to its default.
bad_lines=$(grep -nE '^CONFIG_[A-Z0-9_]+=[^ #]+[[:space:]]+#' kernel/*.conf || true)
[[ -z $bad_lines ]] && ok "no trailing comments on value lines" \
    || bad "trailing comment makes these values invalid:"$'\n'"$bad_lines"

section "package list integrity"
python3 - <<'PY'
import re, sys, pathlib
rc = 0
groups, cur, pkgs = {}, None, []
for line in pathlib.Path("desktop/packages.txt").read_text().splitlines():
    line = line.split("#")[0].strip()
    if not line: continue
    if line.startswith("["): cur = line.strip("[]"); groups[cur] = []
    else: groups[cur].append(line); pkgs.append(line)
dupes = {p for p in pkgs if pkgs.count(p) > 1}
print(f"  ok    {len(groups)} groups, {len(pkgs)} packages" if not dupes
      else f"  FAIL  duplicate packages: {sorted(dupes)}")
rc |= bool(dupes)
empty = [g for g, v in groups.items() if not v]
if empty: print(f"  FAIL  empty groups: {empty}"); rc = 1

# Every group named in install.sh's session table must exist, or a rename
# silently turns a --without= flag into a no-op.
sh = pathlib.Path("desktop/install.sh").read_text()
named = set()
for m in re.finditer(r'session_skip=\(([^)]*)\)', sh): named |= set(m.group(1).split())
missing = sorted(named - set(groups))
print("  ok    every group in the session table exists" if not missing
      else f"  FAIL  session table names groups that packages.txt lacks: {missing}")
rc |= bool(missing)

# Binaries the session configs invoke must be installed by some group.
need = {"labwc": "labwc", "sway": "sway", "swaylock": "swaylock", "grim": "grim",
        "slurp": "slurp", "waybar": "waybar", "swaybg": "swaybg", "mako": "mako",
        "terminator": "terminator", "nemo": "nemo", "brightnessctl": "brightnessctl",
        "xwayland": "xorg-xwayland"}
absent = sorted({p for p in need.values() if p not in pkgs})
print("  ok    every referenced binary has a package" if not absent
      else f"  FAIL  referenced but in no group: {absent}")
rc |= bool(absent)
sys.exit(rc)
PY
[[ $? -eq 0 ]] || fails=$((fails + 1))

section "hardware config trees are installed"
# Adding a directory under hardware/mba62 and forgetting to install it is
# silent: the files simply never reach the machine.
for d in hardware/mba62/*/; do
    name=$(basename "$d")
    [[ $name == mba62 ]] && continue
    grep -q "$name" hardware/mba62/install.sh && ok "$name is installed by install.sh" \
        || bad "hardware/mba62/$name exists but install.sh never installs it"
    grep -q "hardware/mba62/$name" iso/build.sh && ok "$name is staged into the ISO" \
        || bad "hardware/mba62/$name is not staged by iso/build.sh"
done

section "memory settings reach both install paths"
grep -q 'zswap.enabled=0' iso/airootfs/etc/calamares/modules/bootloader-mba62.conf \
    && ok "zswap off on the ISO path" || bad "zswap.enabled=0 missing from kernelParams"
[[ -e hardware/mba62/tmpfiles.d/99-mba62-zswap.conf ]] \
    && ok "zswap off on the existing-install path" || bad "no tmpfiles rule for zswap"

section "installer behaviour"
stub=$(mktemp -d)
trap 'rm -rf "$stub"' EXIT
printf '#!/bin/sh\nexit 0\n' > "$stub/pacman"; chmod +x "$stub/pacman"
export PATH="$stub:$PATH"

resolve() {  # resolve <desktop> [extra args...]
    local d="$1"; shift
    bash desktop/install.sh --user=root --dry-run --desktop="$d" "$@" 2>/dev/null \
        | sed -n 's/.*would run: pacman -S --needed --noconfirm //p' | head -1
}
for d in openbox labwc sway; do
    list=$(resolve "$d")
    [[ -n $list ]] && ok "--desktop=$d resolves $(wc -w <<<"$list") packages" \
        || bad "--desktop=$d resolved nothing"
done
grep -qw labwc <<<"$(resolve labwc)" && ok "labwc session installs labwc" || bad "labwc missing from its own session"
grep -qw sway  <<<"$(resolve labwc)" && bad "labwc session also installs sway" || ok "labwc session excludes sway"
grep -qw xorg-server <<<"$(resolve sway)" && bad "sway session installs Xorg" || ok "sway session excludes Xorg"
# The reverted change reset skip_groups while parsing, silently discarding this.
grep -qw ttf-dejavu <<<"$(resolve labwc --without=fonts)" \
    && bad "--without=fonts was ignored" || ok "--without= survives group selection"
bash desktop/install.sh --desktop=nonesuch 2>/dev/null && bad "invalid --desktop accepted" \
    || ok "invalid --desktop rejected"

section "dotfiles land in the right place"
if [[ $EUID -ne 0 ]]; then
    skip "needs root to create a scratch user (run under sudo)"
else
    home="$stub/home"; mkdir -p "$home"
    userdel lintuser 2>/dev/null
    useradd -M -d "$home" lintuser 2>/dev/null
    chown lintuser "$home"
    for d in openbox labwc sway; do
        rm -rf "${home:?}"/{.[!.],}* 2>/dev/null
        if ! bash desktop/install.sh --user=lintuser --desktop="$d" >/dev/null 2>&1; then
            bad "--desktop=$d exited non-zero"; continue
        fi
        # The bug this exists for: a broken prefix strip put every dotfile under
        # $HOME/<absolute path to the repo>/desktop/skel/...
        strays=$(find "$home" -path '*desktop/skel*' -o -path '*home*Cachyos*' 2>/dev/null | head -3)
        [[ -z $strays ]] && ok "$d: no dotfiles at a repo-shaped path" \
            || bad "$d: dotfiles installed under a repo path: $strays"
        [[ -r $home/.bash_profile ]] && ok "$d: .bash_profile present" || bad "$d: no .bash_profile"
        marker=$(cat "$home/.config/mba62-session" 2>/dev/null)
        [[ $marker == "$d" ]] && ok "$d: session marker recorded" \
            || bad "$d: session marker is '${marker:-missing}'"
        owner=$(stat -c '%U' "$home/.config" 2>/dev/null)
        [[ $owner == lintuser ]] && ok "$d: ~/.config owned by the user" \
            || bad "$d: ~/.config owned by $owner"
    done
    userdel lintuser 2>/dev/null
fi

printf '\n'
if [[ $fails -eq 0 ]]; then echo "lint: all checks passed"; exit 0
else echo "lint: $fails check(s) failed"; exit 1; fi
