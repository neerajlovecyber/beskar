#!/usr/bin/env bash
# macOS Shell Launcher for Wayland
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN="$DIR/bin/pleamar"

if [ ! -f "$BIN" ]; then
    echo "Pleamar binary not found at $BIN. Building..."
    (cd "$DIR/cloned_repos/pleamar" && cargo build --release)
    mkdir -p "$DIR/bin"
    ln -sf "$DIR/cloned_repos/pleamar/target/release/pleamar" "$BIN"
fi

kill_all() {
    echo "Stopping all Pleamar shell components..."
    pkill -9 -x pleamar 2>/dev/null || true
}

case "$1" in
    stop)
        kill_all
        echo "Pleamar shell stopped."
        ;;
    spotlight)
        "$BIN" --say MacSpotlight "emit toggle"
        ;;
    control-center)
        "$BIN" --say MacControlCenter "emit toggle"
        ;;
    *)
        kill_all
        sleep 0.2

        echo "Starting macOS Shell components with Pleamar..."
        # Launch each scene with --no-hud to disable the debug frame graph
        "$BIN" --no-hud --scene "$DIR/shell/topbar.plm" &
        PID_BAR=$!
        "$BIN" --no-hud --scene "$DIR/shell/dock.plm" &
        PID_DOCK=$!
        "$BIN" --no-hud --scene "$DIR/shell/spotlight.plm" &
        PID_SPOTLIGHT=$!
        "$BIN" --no-hud --scene "$DIR/shell/control_center.plm" &
        PID_CC=$!

        echo "macOS Shell running! (PIDs: $PID_BAR, $PID_DOCK, $PID_SPOTLIGHT, $PID_CC)"
        echo " - Spotlight shortcut trigger: $0 spotlight"
        echo " - Control Center shortcut trigger: $0 control-center"
        echo " - To stop the shell: $0 stop"

        # Wait on background processes and clean up on Ctrl+C or script termination
        trap "echo 'Terminating shell...'; kill_all; exit 0" INT TERM EXIT
        wait
        ;;
esac
