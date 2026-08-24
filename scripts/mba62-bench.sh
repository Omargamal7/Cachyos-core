#!/usr/bin/env bash
# Measure what this machine actually does, so tuning decisions rest on numbers
# from your laptop rather than on numbers from someone's blog post.
#
#   scripts/mba62-bench.sh facts                    what the hardware is
#   scripts/mba62-bench.sh sample [options]         record a session
#   scripts/mba62-bench.sh diff BEFORE AFTER        compare two recordings
#
#   --label NAME      name for this recording (default: the current settings)
#   --duration SECS   how long to sample for (default: 300)
#   --out DIR         where to write reports (default: ./bench)
#
# The intended shape of a measurement:
#
#   1. scripts/mba62-bench.sh sample --label before --duration 300
#      ...and for those five minutes, use the machine the way you normally do.
#      Open the tabs you normally open. The point is your workload, not a
#      synthetic one.
#   2. Change one thing.
#   3. scripts/mba62-bench.sh sample --label after --duration 300
#      ...doing the same thing again.
#   4. scripts/mba62-bench.sh diff bench/before-*.txt bench/after-*.txt
#
# Nothing here writes outside --out, and nothing needs root -- though running
# it under sudo lets it read every process's memory instead of only yours.
set -euo pipefail

mode="${1:-}"; shift || true
label="" duration=300 outdir="./bench"

positional=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --label)    label="$2"; shift 2 ;;
        --duration) duration="$2"; shift 2 ;;
        --out)      outdir="$2"; shift 2 ;;
        -h|--help)  sed -n '2,28p' "${BASH_SOURCE[0]}" | sed 's/^# \?//'; exit 0 ;;
        --*)        echo "unknown option: $1" >&2; exit 2 ;;
        *)          positional+=("$1"); shift ;;
    esac
done

have() { command -v "$1" >/dev/null 2>&1; }

# Overridable so the sampling path can be exercised on a machine without PSI
# (a container, or a kernel built without CONFIG_PSI). Not a tuning knob.
psi_dir="${MBA62_PSI_DIR:-/proc/pressure}"
# Read a sysfs/proc file, or print a marker. Never abort the run: a missing
# file is itself a finding, and a report that stops halfway is worthless.
rd() { [[ -r $1 ]] && cat "$1" 2>/dev/null || echo "(not available: $1)"; }

# ---------------------------------------------------------------- the facts --
# Everything here is read from the machine. Where docs/HARDWARE.md says to
# confirm rather than assume -- the Wi-Fi card in particular -- this is what
# does the confirming.
facts() {
    echo "== identity =="
    printf '  date          %s\n' "$(date -Is)"
    printf '  model         %s\n' "$(rd /sys/class/dmi/id/product_name)"
    printf '  kernel        %s\n' "$(uname -r)"
    printf '  cmdline       %s\n' "$(rd /proc/cmdline)"

    echo "== cpu =="
    awk -F: '/^model name/ {print "  model        " $2; exit}' /proc/cpuinfo
    awk -F: '/^cpu family/ {f=$2} /^model\t/ {m=$2} /^stepping/ {s=$2}
             END {printf "  family/model/stepping %s/%s/%s\n", f+0, m+0, s+0}' /proc/cpuinfo
    printf '  threads       %s\n' "$(nproc)"

    echo "== memory =="
    awk '/^MemTotal|^SwapTotal/ {printf "  %-13s %s %s\n", $1, $2, $3}' /proc/meminfo

    echo "== storage =="
    if have lsblk; then
        lsblk -d -o NAME,MODEL,SIZE,ROTA 2>/dev/null | sed 's/^/  /'
    fi
    for q in /sys/block/*/queue/scheduler; do
        [[ -r $q ]] || continue
        d=${q#/sys/block/}; d=${d%%/*}
        # loop devices are squashfs mounts, not storage decisions
        [[ $d == loop* || $d == ram* ]] && continue
        printf '  scheduler %-8s %s\n' "$d" "$(cat "$q")"
    done

    echo "== network =="
    if have lspci; then
        lspci -nn 2>/dev/null | grep -iE 'network|wireless' | sed 's/^/  /' || echo "  (none found)"
    else
        echo "  (lspci not installed -- pacman -S pciutils)"
    fi

    echo "== settings in effect =="
    printf '  swappiness            %s\n' "$(rd /proc/sys/vm/swappiness)"
    printf '  page-cluster          %s\n' "$(rd /proc/sys/vm/page-cluster)"
    printf '  watermark_boost       %s\n' "$(rd /proc/sys/vm/watermark_boost_factor)"
    printf '  watermark_scale       %s\n' "$(rd /proc/sys/vm/watermark_scale_factor)"
    printf '  transparent_hugepage  %s\n' "$(rd /sys/kernel/mm/transparent_hugepage/enabled)"
    printf '  zswap enabled         %s\n' "$(rd /sys/module/zswap/parameters/enabled)"
    printf '  cpu governor          %s\n' "$(rd /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor)"
    printf '  pstate status         %s\n' "$(rd /sys/devices/system/cpu/intel_pstate/status)"

    echo "== swap =="
    if have swapon; then
        local sw; sw=$(swapon --show 2>/dev/null || true)
        [[ -n $sw ]] && echo "$sw" | sed 's/^/  /' || echo "  (no swap active)"
    fi
    [[ -e /sys/block/zram0 ]] || echo "  no zram device"
    if [[ -e /sys/block/zram0 ]]; then
        printf '  zram algorithm  %s\n' "$(rd /sys/block/zram0/comp_algorithm)"
        printf '  zram disksize   %s\n' "$(rd /sys/block/zram0/disksize)"
    fi

    echo "== cpu vulnerabilities =="
    # Says plainly whether mitigations=off actually took effect.
    for v in /sys/devices/system/cpu/vulnerabilities/*; do
        [[ -r $v ]] || continue
        printf '  %-22s %s\n' "$(basename "$v")" "$(cat "$v")"
    done
}

# ------------------------------------------------------------------- memory --
# PSS, not RSS. RSS counts every shared page in full against every process
# holding it, so summing RSS across Chrome's process tree over-counts its
# memory badly -- which is where most "Chrome uses N MB" figures come from.
top_pss() {
    local n="${1:-12}"
    for f in /proc/[0-9]*/smaps_rollup; do
        [[ -r $f ]] || continue
        local pid=${f#/proc/}; pid=${pid%%/*}
        local comm pss
        comm=$(tr -d '\0' < "/proc/$pid/comm" 2>/dev/null) || continue
        pss=$(awk '/^Pss:/ {s+=$2} END {print s+0}' "$f" 2>/dev/null) || continue
        [[ -n $pss && $pss -gt 0 ]] && printf '%8d %s\n' "$pss" "$comm"
    done | sort -rn | head -"$n" | awk '{printf "  %8.1f MB  %s\n", $1/1024, $2}'
}

# PSI total counters are cumulative microseconds of stall. Deltas across the
# window are the honest number; the avg fields are a convenience.
psi_total() {  # psi_total <file> <some|full>
    [[ -r $1 ]] || { echo 0; return; }
    awk -v k="$2" '$1 == k { for (i = 2; i <= NF; i++) if ($i ~ /^total=/) { sub("total=", "", $i); print $i } }' "$1"
}

mem_available() { awk '/^MemAvailable/ {print $2}' /proc/meminfo; }
swap_used() { awk '/^SwapTotal/ {t=$2} /^SwapFree/ {f=$2} END {print t-f}' /proc/meminfo; }

sample() {
    local report="$outdir/${label}-$(date +%Y%m%d%H%M%S).txt"
    mkdir -p "$outdir"

    if [[ ! -r "$psi_dir/memory" ]]; then
        echo "!! /proc/pressure is not readable -- this kernel was built without" >&2
        echo "!! CONFIG_PSI, or it needs psi=1 on the command line. Stall time is" >&2
        echo "!! the metric this script exists to collect; without it you would be" >&2
        echo "!! back to guessing from 'free'." >&2
        exit 1
    fi

    {
        facts
        echo
        echo "== sampling for ${duration}s =="
        echo "   Use the machine normally while this runs."
    } | tee "$report"

    local t0_cpu t0_io t0_mem t0_memfull
    t0_cpu=$(psi_total "$psi_dir/cpu" some)
    t0_io=$(psi_total "$psi_dir/io" some)
    t0_mem=$(psi_total "$psi_dir/memory" some)
    t0_memfull=$(psi_total "$psi_dir/memory" full)

    local min_avail max_swap n=0 sum_avail=0
    min_avail=$(mem_available); max_swap=$(swap_used)

    local end=$((SECONDS + duration))
    while (( SECONDS < end )); do
        local a s
        a=$(mem_available); s=$(swap_used)
        (( a < min_avail )) && min_avail=$a
        (( s > max_swap )) && max_swap=$s
        sum_avail=$((sum_avail + a)); n=$((n + 1))
        sleep 2
    done

    {
        echo
        echo "== results =="
        printf '  window                %ss\n' "$duration"
        echo
        echo "  -- stall time (PSI, seconds spent waiting) --"
        printf '  cpu   some            %.2f s\n' "$(( $(psi_total "$psi_dir/cpu" some) - t0_cpu ))e-6"
        printf '  io    some            %.2f s\n' "$(( $(psi_total "$psi_dir/io" some) - t0_io ))e-6"
        printf '  mem   some            %.2f s\n' "$(( $(psi_total "$psi_dir/memory" some) - t0_mem ))e-6"
        printf '  mem   full            %.2f s\n' "$(( $(psi_total "$psi_dir/memory" full) - t0_memfull ))e-6"
        echo "     'some' = at least one task stalled; 'full' = everything stalled."
        echo "     Memory 'full' time is the number that corresponds to the machine"
        echo "     feeling frozen. Lower is better; compare like for like."
        echo
        echo "  -- memory --"
        printf '  MemAvailable min      %.0f MB\n' "$(echo "$min_avail/1024" | bc -l 2>/dev/null || echo "$((min_avail/1024))")"
        printf '  MemAvailable mean     %.0f MB\n' "$(echo "$sum_avail/$n/1024" | bc -l 2>/dev/null || echo "$((sum_avail/n/1024))")"
        printf '  swap used peak        %.0f MB\n' "$(echo "$max_swap/1024" | bc -l 2>/dev/null || echo "$((max_swap/1024))")"
        echo
        if [[ -r /sys/block/zram0/mm_stat ]]; then
            echo "  -- zram effectiveness --"
            awk '{printf "  stored (uncompressed) %.0f MB\n  used   (actual RAM)   %.0f MB\n  ratio                 %.2fx\n",
                  $1/1048576, $3/1048576, ($3 > 0 ? $1/$3 : 0)}' /sys/block/zram0/mm_stat
            echo "     Ratio is how much memory zram is buying you. Below ~2x on this"
            echo "     workload, a cheaper algorithm (lzo-rle) may cost less CPU for"
            echo "     nearly the same benefit -- worth re-running both ways."
            echo
        fi
        echo "  -- largest processes by PSS --"
        top_pss 12
        if [[ $EUID -ne 0 ]]; then
            echo "     (run under sudo to include processes that are not yours)"
        fi
        echo
        echo "  -- boot --"
        if have systemd-analyze; then systemd-analyze 2>/dev/null | sed 's/^/  /' || true; fi
    } | tee -a "$report"

    echo
    echo "Report: $report"
}

# --------------------------------------------------------------------- diff --
# Pulls the same handful of lines out of two reports and puts them side by
# side. Deliberately dumb: the reports are plain text and meant to be read.
diff_reports() {
    local a="$1" b="$2"
    [[ -r $a && -r $b ]] || { echo "usage: $0 diff BEFORE.txt AFTER.txt" >&2; exit 2; }
    printf '%-24s %18s %18s\n' "metric" "$(basename "$a")" "$(basename "$b")"
    printf '%-24s %18s %18s\n' "------" "------" "------"
    local keys=("cpu   some" "io    some" "mem   some" "mem   full"
                "MemAvailable min" "MemAvailable mean" "swap used peak"
                "ratio" "swappiness" "transparent_hugepage")
    for k in "${keys[@]}"; do
        local va vb
        va=$(grep -m1 -F "  $k" "$a" 2>/dev/null | sed "s/.*$k *//" || true)
        vb=$(grep -m1 -F "  $k" "$b" 2>/dev/null | sed "s/.*$k *//" || true)
        [[ -z $va && -z $vb ]] && continue
        printf '%-24s %18s %18s\n' "$k" "${va:-–}" "${vb:-–}"
    done
    echo
    echo "A difference is only meaningful if both runs did the same thing for the"
    echo "same length of time. Two runs of the same configuration first is the"
    echo "cheapest way to find out how much this workload varies on its own."
}

case "$mode" in
    facts)  facts ;;
    sample)
        [[ -n $label ]] || label="run"
        sample ;;
    diff)   diff_reports "${positional[0]:-}" "${positional[1]:-}" ;;
    *)      sed -n '2,28p' "${BASH_SOURCE[0]}" | sed 's/^# \?//'; exit 2 ;;
esac
