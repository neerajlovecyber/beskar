#!/usr/bin/env bash
# macOS Shell Launcher for Wayland Compositors (Pleamar Engine)
set -e
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN="$DIR/bin/pleamar"
PID_FILE="/tmp/pleamar_macos_shell.pids"

if [ ! -f "$BIN" ]; then
    echo "Pleamar binary not found at $BIN. Building..."
    (cd "$DIR/cloned_repos/pleamar" && cargo build --release)
    mkdir -p "$DIR/bin"
    ln -sf "$DIR/cloned_repos/pleamar/target/release/pleamar" "$BIN"
fi

kill_all() {
    echo "Stopping all Pleamar shell components..."
    pkill -9 -x pleamar 2>/dev/null || true
    rm -f "$PID_FILE"
}

check_status() {
    echo "macOS Shell Status:"
    for comp in topbar dock spotlight control_center apple_menu; do
        if pgrep -f "pleamar.*$comp\.plm" >/dev/null 2>&1; then
            echo "  ✔ $comp is RUNNING"
        else
            echo "  ✖ $comp is STOPPED"
        fi
    done
}

start_shell() {
    kill_all
    sleep 0.3

    echo "Starting macOS Shell components (Pleamar daemon mode)..."

    setsid "$BIN" --no-hud --scene "$DIR/shell/topbar.plm" </dev/null >/tmp/pleamar_topbar.log 2>&1 &
    PID_BAR=$!
    setsid "$BIN" --no-hud --scene "$DIR/shell/dock.plm" </dev/null >/tmp/pleamar_dock.log 2>&1 &
    PID_DOCK=$!
    setsid "$BIN" --no-hud --scene "$DIR/shell/spotlight.plm" </dev/null >/tmp/pleamar_spotlight.log 2>&1 &
    PID_SPOTLIGHT=$!
    setsid "$BIN" --no-hud --scene "$DIR/shell/control_center.plm" </dev/null >/tmp/pleamar_cc.log 2>&1 &
    PID_CC=$!
    setsid "$BIN" --no-hud --scene "$DIR/shell/apple_menu.plm" </dev/null >/tmp/pleamar_apple.log 2>&1 &
    PID_APPLE=$!

    echo "$PID_BAR $PID_DOCK $PID_SPOTLIGHT $PID_CC $PID_APPLE" > "$PID_FILE"
    sleep 0.6

    echo "macOS Shell is active!"
    echo "  - Top Bar: PID $PID_BAR"
    echo "  - Dock: PID $PID_DOCK"
    echo "  - Spotlight Search: PID $PID_SPOTLIGHT"
    echo "  - Control Center: PID $PID_CC"
    echo "  - Apple Menu: PID $PID_APPLE"
    echo ""
    echo "Commands & Hotkey Triggers:"
    echo "  - $0 spotlight       (Toggle Spotlight search)"
    echo "  - $0 control-center  (Toggle Control Center)"
    echo "  - $0 apple-menu      (Toggle Apple menu)"
    echo "  - $0 status          (Check shell status)"
    echo "  - $0 stop            (Stop shell)"
}

case "$1" in
    stop)
        kill_all
        echo "Pleamar shell stopped."
        ;;
    status)
        check_status
        ;;
    restart)
        start_shell
        ;;
    spotlight)
        "$BIN" --say spotlight "emit toggle"
        ;;
    control-center)
        "$BIN" --say control_center "emit toggle"
        ;;
    apple-menu)
        "$BIN" --say apple_menu "emit toggle"
        ;;
    *)
        start_shell
        ;;
esac
