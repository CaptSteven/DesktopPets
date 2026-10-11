#!/bin/sh
#
# Reports the pet's real CPU cost as a percentage of one core.
#
# `ps -o %cpu` is a decaying average that lies about short-lived processes, so this samples the
# process's *cumulative* CPU time twice and divides by the wall-clock gap. That is the number worth
# comparing before and after a change.
#
# Note the pet spends its time in two very different modes, and they cost different amounts:
#   - walking: the window is moved every tick, and the sprite changes at 10fps
#   - idle/asleep: nothing moves, and the sprite changes at 3-6fps
# Measure both, or you will "optimise" the wrong one.
#
# Usage:
#   Scripts/measure-cpu.sh [seconds] [label]
#
# Examples:
#   Scripts/measure-cpu.sh 60 wal        # while it is walking about
#   Scripts/measure-cpu.sh 60 idle       # while it is dozing

set -eu

cd "$(dirname "$0")/.."

SECONDS_TO_RUN=${1:-60}
LABEL=${2:-run}

PID=$(pgrep -x DesktopPets | head -1 || true)
if [ -z "$PID" ]; then
    echo "measure-cpu.sh: DesktopPets is not running." >&2
    echo "  Start it first: swift run DesktopPets   (or open dist/DesktopPets.app)" >&2
    exit 1
fi

# `ps -o time=` gives [[dd-]hh:]mm:ss.cc of CPU time consumed so far.
cpu_seconds() {
    ps -o time= -p "$1" 2>/dev/null | tr -d ' ' | awk '
        {
            line = $0
            days = 0
            if (index(line, "-") > 0) {
                split(line, d, "-")
                days = d[1] + 0
                line = d[2]
            }
            n = split(line, t, ":")
            if (n == 3)      s = t[1] * 3600 + t[2] * 60 + t[3]
            else if (n == 2) s = t[1] * 60 + t[2]
            else             s = t[1]
            print days * 86400 + s
        }'
}

START_CPU=$(cpu_seconds "$PID")
START_WALL=$(date +%s)

printf 'measuring "%s" for %ss (pid %s) ' "$LABEL" "$SECONDS_TO_RUN" "$PID"
i=0
while [ "$i" -lt "$SECONDS_TO_RUN" ]; do
    sleep 5
    i=$((i + 5))
    printf '.'
done
printf '\n'

END_CPU=$(cpu_seconds "$PID")
END_WALL=$(date +%s)

ELAPSED=$((END_WALL - START_WALL))
if [ "$ELAPSED" -le 0 ]; then
    echo "measure-cpu.sh: no elapsed time to measure over" >&2
    exit 1
fi

awk -v label="$LABEL" -v cpu="$END_CPU" -v start="$START_CPU" -v secs="$ELAPSED" 'BEGIN {
    used = cpu - start
    printf "  %-6s cpu time %.2fs over %ds  ->  %.2f%% of one core\n", label, used, secs, (used / secs) * 100
}'
