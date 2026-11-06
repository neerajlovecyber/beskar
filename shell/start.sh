#!/usr/bin/env bash
# macOS Shell Launcher for Wayland
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN="$DIR/bin/pleamar"

if [ ! -f "$BIN" ]; then
    echo "Pleamar binary not found at $BIN. Building..."
    (cd "$DIR/cloned_repos/pleamar" && cargo build --release)
    mkdir -p "$DIR/bin"
    ln -sf "$DIR/cloned_repos/pleamar/target/release/pleamar" "$BIN"
fi

kill_existing() {
    pkill -f "pleamar.*shell/(topbar|dock|spotlight|control_center)" 2>/dev/null || true
}

case "$1" in
    stop)
        echo "Stopping macOS Shell components..."
        kill_existing
        ;;
    spotlight)
        "$BIN" --say MacSpotlight "emit toggle"
        ;;
    control-center)
        "$BIN" --say MacControlCenter "emit toggle"
        ;;
    *)
        echo "Starting macOS Shell components with Pleamar..."
        kill_existing
        sleep 0.2

        "$BIN" --scene "$DIR/shell/topbar.plm" &
        "$BIN" --scene "$DIR/shell/dock.plm" &
        "$BIN" --scene "$DIR/shell/spotlight.plm" &
        "$BIN" --scene "$DIR/shell/control_center.plm" &

        echo "macOS Shell running!"
        echo " - Spotlight shortcut trigger: $0 spotlight"
        echo " - Control Center shortcut trigger: $0 control-center"
        ;;
esac
