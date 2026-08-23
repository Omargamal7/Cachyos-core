#!/usr/bin/env bash
# Check a generated .config against the project's expectations.
#
#   verify-config.sh <.config> <fragment>...
#
# Two classes of check:
#   * critical-symbols.txt -- boot/usability contract. A miss is fatal.
#   * the fragments themselves -- every value we asked for should have
#     survived `make olddefconfig`. A miss is a warning, because kconfig is
#     allowed to override us (a `select` from a driver we kept beats an
#     `is not set`), but it should never happen silently.
set -euo pipefail

config="${1:?usage: verify-config.sh <.config> <fragment>...}"
shift
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

[[ -r $config ]] || { echo "verify-config: cannot read $config" >&2; exit 2; }

# value_of SYMBOL -> y | m | n
value_of() {
    local v
    v=$(sed -n -e "s/^CONFIG_$1=//p" -e "s/^# CONFIG_$1 is not set\$/n/p" "$config" | head -1)
    printf '%s' "${v:-n}"
}

fail=0 warn=0
kept=()

echo "== critical symbols =="
while read -r sym want; do
    [[ -z ${sym:-} || $sym == \#* ]] && continue
    got=$(value_of "$sym")
    case "$want" in
        'y|m') [[ $got == y || $got == m ]] || { printf '  FAIL %-24s want y or m, got %s\n' "$sym" "$got"; fail=$((fail+1)); } ;;
        *)     [[ $got == "$want" ]]        || { printf '  FAIL %-24s want %s, got %s\n' "$sym" "$want" "$got"; fail=$((fail+1)); } ;;
    esac
done < "$here/critical-symbols.txt"
[[ $fail -eq 0 ]] && echo "  all $(grep -cvE '^\s*(#|$)' "$here/critical-symbols.txt") critical symbols satisfied"

# Two very different signals get lumped together if we just diff requests
# against the result:
#   * we asked for a driver and did not get it   -- usually a real mistake
#   * we asked to drop something and kconfig kept it -- almost always a
#     `select` from a driver we deliberately kept, i.e. working as intended
# Only the first is worth reading line by line.
echo "== asked for, did not get =="
missing=0
for frag in "$@"; do
    [[ -r $frag ]] || continue
    while IFS= read -r line; do
        case "$line" in
            CONFIG_*=*)
                sym=${line%%=*}; sym=${sym#CONFIG_}; want=${line#*=}
                # string/int values are compared verbatim
                got=$(sed -n "s/^CONFIG_$sym=//p" "$config" | head -1)
                [[ -z $got ]] && got=n
                ;;
            '# CONFIG_'*' is not set')
                sym=${line#\# CONFIG_}; sym=${sym% is not set}; want=n
                got=$(value_of "$sym")
                ;;
            *) continue ;;
        esac
        if [[ $got != "$want" ]]; then
            if [[ $want == n ]]; then
                warn=$((warn+1))          # kept by a select; summarised below
                kept+=("$(printf '  %-28s kept as %s   (%s)' "$sym" "$got" "$(basename "$frag")")")
            else
                printf '  %-28s asked %-8s got %s   (%s)\n' "$sym" "$want" "$got" "$(basename "$frag")"
                missing=$((missing+1))
            fi
        fi
    done < "$frag"
done
[[ $missing -eq 0 ]] && echo "  none"
echo "== asked to drop, kept by a select =="
if [[ ${VERBOSE:-0} != 0 && $warn -gt 0 ]]; then
    printf '%s\n' "${kept[@]}"
else
    echo "  $warn symbol(s); set VERBOSE=1 to list them"
fi

echo "== size =="
printf '  built-in (=y): %s\n' "$(grep -c '=y$' "$config")"
printf '  modules  (=m): %s\n' "$(grep -c '=m$' "$config")"

if [[ $fail -gt 0 ]]; then
    echo "verify-config: $fail critical symbol(s) missing" >&2
    exit 1
fi
if [[ $missing -gt 0 ]]; then
    echo "verify-config: OK, but $missing requested symbol(s) did not survive olddefconfig"
else
    echo "verify-config: OK"
fi
