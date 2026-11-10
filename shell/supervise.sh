#!/usr/bin/env bash
# Keeps the shell's scenes alive with ONE process: runs a pleamar per scene and starts it again whenever it exits or
# crashes (after 1 s; 30 s if it dies 5 times in a row within 20 s each).
# usage: supervise.sh <scene.plm>:<logfile> [<scene.plm>:<logfile> ...]   (start.sh starts ONE of these for all scenes
# and stops it on stop / restart; to restart a scene by hand, just kill its pleamar: it comes back)
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PLEAMAR_NO_LENS=1

declare -a SCENE LOGF FAST T0
declare -A BYPID

launch() {      # launch <index> <delay seconds>: the subshell sleeps, then BECOMES pleamar (same pid)
    local i=$1 d=$2
    T0[$i]=$(( $(date +%s) + d ))
    (
        [ "$d" -gt 0 ] && sleep "$d"
        exec "$DIR/bin/pleamar" --no-hud --scene "${SCENE[$i]}" </dev/null >>"${LOGF[$i]}" 2>&1
    ) &
    BYPID[$!]=$i
}

i=0
for pair in "$@"; do
    SCENE[$i]="${pair%%:*}"; LOGF[$i]="${pair#*:}"; FAST[$i]=0
    : > "${LOGF[$i]}"
    launch "$i" 0
    i=$((i + 1))
done

while :; do
    wait -n -p done_pid
    code=$?
    i="${BYPID[$done_pid]}"
    [ -z "$i" ] && continue
    unset "BYPID[$done_pid]"
    now=$(date +%s)
    echo "supervise · $(basename "${SCENE[$i]}") exited with code $code, starting it again" >>"${LOGF[$i]}"
    # a scene that dies at once, again and again, is retried slowly instead of in a tight loop
    if [ $((now - T0[$i])) -lt 20 ]; then FAST[$i]=$((FAST[$i] + 1)); else FAST[$i]=0; fi
    if [ "${FAST[$i]}" -ge 5 ]; then launch "$i" 30; else launch "$i" 1; fi
done
