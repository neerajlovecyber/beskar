#!/usr/bin/env bash
# macOS Shell Launcher for Wayland Compositors (Pleamar Engine)
set -e
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN="$DIR/bin/pleamar"
PID_FILE="/tmp/pleamar_macos_shell.pids"
CONFIG_FILE="$HOME/.config/pleamar_shell.json"

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

apply_saved_theme() {
    if [ -f "$CONFIG_FILE" ]; then
        DM=$(grep -o '"dark_mode": *[a-z]*' "$CONFIG_FILE" | awk '{print $2}' || true)
        SKIN=$(grep -o '"skin": *[0-9]*' "$CONFIG_FILE" | awk '{print $2}' || true)
        
        [ -z "$DM" ] && DM="true"
        [ -z "$SKIN" ] && SKIN="0"

        for comp in topbar dock spotlight control_center apple_menu; do
            "$BIN" --say "$comp" "fact dark_mode $DM" >/dev/null 2>&1 || true
            "$BIN" --say "$comp" "fact skin $SKIN" >/dev/null 2>&1 || true
        done
    fi
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

    apply_saved_theme

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
    echo "  - $0 dark-mode [on|off]"
    echo "  - $0 skin [0|1|2]    (0=Liquid Glass, 1=Light Acrylic, 2=Classic Solid)"
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
    dark-mode)
        VAL="true"
        [ "$2" = "off" ] && VAL="false"
        for comp in topbar dock spotlight control_center apple_menu; do
            "$BIN" --say "$comp" "fact dark_mode $VAL"
        done
        mkdir -p "$(dirname "$CONFIG_FILE")"
        echo "{\"dark_mode\": $VAL, \"skin\": 0}" > "$CONFIG_FILE"
        echo "Dark mode set to $VAL."
        ;;
    skin)
        SKIN_VAL="${2:-0}"
        for comp in topbar dock spotlight control_center apple_menu; do
            "$BIN" --say "$comp" "fact skin $SKIN_VAL"
        done
        mkdir -p "$(dirname "$CONFIG_FILE")"
        echo "{\"dark_mode\": true, \"skin\": $SKIN_VAL}" > "$CONFIG_FILE"
        echo "Glass skin set to $SKIN_VAL."
        ;;
    *)
        start_shell
        ;;
esac
