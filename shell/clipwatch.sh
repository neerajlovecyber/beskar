#!/usr/bin/env bash
# Stores what is copied (text or images) with cliphist for the clipboard panel, and starts again if the watcher dies.
# usage: clipwatch.sh text|image   (start.sh starts one of each; kill_all stops them)
kind="$1"
while :; do
    wl-paste --type "$kind" --watch cliphist -max-items 100 store </dev/null >/dev/null 2>&1
    sleep 1
done
