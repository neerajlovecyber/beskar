#!/usr/bin/env bash
# Locks the screen when you are away: idle.sh <minutes> (0 = never on idle). It always locks before the computer sleeps
# (lid closed, Sleep), and turns the screens off a minute after locking. Run by start.sh and by Settings → General.
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MIN="${1:-0}"
CONF="$HOME/.config/beskar/hypridle.conf"
mkdir -p "$HOME/.config/beskar"
if ! [ "$MIN" -gt 0 ] 2>/dev/null; then
    # never: no idle lock and no lock before sleep
    pkill -x hypridle 2>/dev/null
    rm -f "$CONF"
    exit 0
fi
{
    echo "general {"
    echo "    lock_cmd = $DIR/shell/start.sh lock"
    echo "    before_sleep_cmd = $DIR/shell/start.sh lock"
    echo "    after_sleep_cmd = niri msg action power-on-monitors"
    echo "}"
    if [ "$MIN" -gt 0 ] 2>/dev/null; then
        echo "listener {"
        echo "    timeout = $((MIN * 60))"
        echo "    on-timeout = $DIR/shell/start.sh lock"
        echo "}"
        echo "listener {"
        echo "    timeout = $((MIN * 60 + 60))"
        echo "    on-timeout = niri msg action power-off-monitors"
        echo "    on-resume = niri msg action power-on-monitors"
        echo "}"
    fi
} > "$CONF"
command -v hypridle >/dev/null 2>&1 || exit 0
pkill -x hypridle 2>/dev/null
setsid hypridle -c "$CONF" </dev/null >/tmp/hypridle.log 2>&1 &
