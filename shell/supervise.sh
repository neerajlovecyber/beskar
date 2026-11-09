#!/usr/bin/env bash
# Keeps one shell scene alive: runs pleamar on the scene and starts it again whenever it exits or crashes.
# usage: supervise.sh <scene.plm> <logfile>   (start.sh starts one of these per scene and stops them on stop/restart)
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCENE="$1"; LOG="$2"
export PLEAMAR_NO_LENS=1
: > "$LOG"
fast=0
while :; do
    t0=$(date +%s)
    "$DIR/bin/pleamar" --no-hud --scene "$SCENE" </dev/null >>"$LOG" 2>&1
    code=$?
    now=$(date +%s)
    echo "supervise · $(basename "$SCENE") exited with code $code, starting it again" >>"$LOG"
    # a scene that dies at once, again and again, is retried slowly instead of in a tight loop
    if [ $((now - t0)) -lt 20 ]; then fast=$((fast + 1)); else fast=0; fi
    if [ "$fast" -ge 5 ]; then sleep 30; else sleep 1; fi
done
