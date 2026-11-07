#!/usr/bin/env bash
# macOS Shell Launcher for Wayland Compositors (Pleamar Engine)
set -e
export PLEAMAR_NO_LENS=1
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN="$DIR/bin/pleamar"
# One pid file per Wayland display, so a second shell (say, one in a nested pleamar-wm) never touches the first.
PID_FILE="/tmp/pleamar_macos_shell.${WAYLAND_DISPLAY:-wayland-0}.pids"
CONFIG_FILE="$HOME/.config/pleamar_shell.json"

if [ ! -f "$BIN" ]; then
    echo "Pleamar binary not found at $BIN. Building..."
    (cd "$DIR/cloned_repos/pleamar" && cargo build --release)
    mkdir -p "$DIR/bin"
    ln -sf "$DIR/cloned_repos/pleamar/target/release/pleamar" "$BIN"
fi

kill_all() {
    echo "Stopping the Pleamar shell components on ${WAYLAND_DISPLAY:-this display}..."
    # Only the pleamar processes that belong to THIS Wayland display (their own WAYLAND_DISPLAY says so),
    # so a shell running in a nested compositor does not kill the one on the real desktop, nor the reverse.
    for pid in $(pgrep -x pleamar 2>/dev/null); do
        theirs=$(tr '\0' '\n' < "/proc/$pid/environ" 2>/dev/null | sed -n 's/^WAYLAND_DISPLAY=//p' | head -1)
        if [ "${theirs:-wayland-0}" = "${WAYLAND_DISPLAY:-wayland-0}" ]; then
            kill -9 "$pid" 2>/dev/null || true
        fi
    done
    rm -f "$PID_FILE"
}

check_status() {
    echo "macOS / iNiR Shell Status:"
    for comp in topbar border spotlight control_center notifications dashboard wallpapers osd settings lock session capture appswitcher clipboard; do
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
        
        ACCENT=$(grep -o '"accent": *[0-9]*' "$CONFIG_FILE" | awk '{print $2}' || true)
        [ -z "$ACCENT" ] && ACCENT="0"
        AUTO=$(grep -o '"accent_auto": *[a-z]*' "$CONFIG_FILE" | awk '{print $2}' || true)
        [ -z "$AUTO" ] && AUTO="false"
        STYLE=$(grep -o '"panel_style": *[0-9]*' "$CONFIG_FILE" | awk '{print $2}' || true)
        [ -z "$STYLE" ] && STYLE="0"
        [ -z "$DM" ] && DM="true"
        [ -z "$SKIN" ] && SKIN="0"

        for comp in topbar border spotlight control_center notifications dashboard wallpapers osd settings session capture appswitcher clipboard; do
            "$BIN" --say "$comp" "fact dark_mode $DM" >/dev/null 2>&1 || true
            "$BIN" --say "$comp" "fact skin $SKIN" >/dev/null 2>&1 || true
        done
        for comp in topbar control_center notifications dashboard settings wallpapers spotlight osd clipboard session capture appswitcher lock; do
            "$BIN" --say "$comp" "fact accent $ACCENT" >/dev/null 2>&1 || true
            "$BIN" --say "$comp" "fact accent_auto $AUTO" >/dev/null 2>&1 || true
            "$BIN" --say "$comp" "fact panel_style $STYLE" >/dev/null 2>&1 || true
        done
    fi
}

start_shell() {
    kill_all
    sleep 0.3

    echo "Starting macOS / iNiR Shell components (Pleamar daemon mode)..."

    # Ensure wallpaper daemon is running and wallpaper is displayed
    if ! awww query >/dev/null 2>&1; then
        setsid awww-daemon </dev/null >/tmp/awww.log 2>&1 &
        sleep 0.4
    fi
    # Wallpapers that ship with Beskar go where the picker looks for them (never overwriting)
    mkdir -p "$HOME/.local/share/beskar/wallpapers"
    cp -n "$DIR"/assets/wallpapers/*.jpg "$HOME/.local/share/beskar/wallpapers/" 2>/dev/null || true
    # The wallpaper chosen in the picker (Super+W) is put back; none chosen yet leaves what awww shows
    WALLPAPER=$(cat "$HOME/.config/beskar/wallpaper" 2>/dev/null || true)
    if [ -n "$WALLPAPER" ] && [ -f "$WALLPAPER" ]; then
        awww img "$WALLPAPER" --transition-type none >/dev/null 2>&1 || true
    fi

    setsid "$BIN" --no-hud --scene "$DIR/shell/topbar.plm" </dev/null >/tmp/pleamar_topbar.log 2>&1 &
    PID_BAR=$!
    # Border neutralized - window borders handled natively by compositor
    PID_BORDER=""
    setsid "$BIN" --no-hud --scene "$DIR/shell/spotlight.plm" </dev/null >/tmp/pleamar_spotlight.log 2>&1 &
    PID_SPOTLIGHT=$!
    setsid "$BIN" --no-hud --scene "$DIR/shell/control_center.plm" </dev/null >/tmp/pleamar_cc.log 2>&1 &
    PID_CC=$!
    setsid "$BIN" --no-hud --scene "$DIR/shell/notifications.plm" </dev/null >/tmp/pleamar_notifications.log 2>&1 &
    PID_WIDGETS=$!
    setsid "$BIN" --no-hud --scene "$DIR/shell/dashboard.plm" </dev/null >/tmp/pleamar_dashboard.log 2>&1 &
    PID_DASH=$!
    setsid "$BIN" --no-hud --scene "$DIR/shell/wallpapers.plm" </dev/null >/tmp/pleamar_wallpapers.log 2>&1 &
    PID_WALL=$!
    setsid "$BIN" --no-hud --scene "$DIR/shell/osd.plm" </dev/null >/tmp/pleamar_osd.log 2>&1 &
    PID_OSD=$!
    setsid "$BIN" --no-hud --scene "$DIR/shell/settings.plm" </dev/null >/tmp/pleamar_settings.log 2>&1 &
    PID_SETTINGS=$!
    setsid "$BIN" --no-hud --scene "$DIR/shell/lock.plm" </dev/null >/tmp/pleamar_lock.log 2>&1 &
    PID_LOCK=$!
    setsid "$BIN" --no-hud --scene "$DIR/shell/session.plm" </dev/null >/tmp/pleamar_session.log 2>&1 &
    PID_SESSION=$!
    setsid "$BIN" --no-hud --scene "$DIR/shell/capture.plm" </dev/null >/tmp/pleamar_capture.log 2>&1 &
    PID_CAPTURE=$!
    setsid "$BIN" --no-hud --scene "$DIR/shell/appswitcher.plm" </dev/null >/tmp/pleamar_switcher.log 2>&1 &
    PID_SWITCHER=$!
    setsid "$BIN" --no-hud --scene "$DIR/shell/clipboard.plm" </dev/null >/tmp/pleamar_clipboard.log 2>&1 &
    PID_CLIP=$!

    echo "$PID_BAR $PID_BORDER $PID_SPOTLIGHT $PID_CC $PID_WIDGETS $PID_DASH $PID_WALL $PID_OSD $PID_SETTINGS $PID_LOCK $PID_SESSION $PID_CAPTURE $PID_SWITCHER $PID_CLIP" > "$PID_FILE"
    sleep 0.6

    apply_saved_theme

    echo "macOS / iNiR Shell is active!"
    echo "  - Frame (ring + 3 top islands + bottom dock): PID $PID_BAR"
    echo "  - Screen Border: PID $PID_BORDER"
    echo "  - Spotlight Search: PID $PID_SPOTLIGHT"
    echo "  - Control Center: PID $PID_CC"
    echo "  - Apple Menu: PID"
    echo "  - Widgets & Notifications: PID $PID_WIDGETS"
    echo "  - Bezel OSD (HUD): PID $PID_OSD"
    echo "  - System Settings: PID $PID_SETTINGS"
    echo "  - Wayland Lock Screen: PID $PID_LOCK"
    echo "  - Session Shutdown Dialog: PID $PID_SESSION"
    echo "  - Screen Capture & Record HUD: PID $PID_CAPTURE"
    echo "  - App Switcher (Cmd+Tab): PID $PID_SWITCHER"
    echo "  - Clipboard Manager (Super+V): PID $PID_CLIP"
    echo ""
    echo "Commands & Hotkey Triggers:"
    echo "  - $0 appswitcher     (Toggle Cmd+Tab Application Switcher)"
    echo "  - $0 clipboard       (Toggle Clipboard History Manager)"
    echo "  - $0 settings        (Toggle System Settings)"
    echo "  - $0 lock            (Lock Screen with ext-session-lock)"
    echo "  - $0 session [0|1|2] (0=Shutdown, 1=Restart, 2=Logout modal)"
    echo "  - $0 capture         (Toggle Screen Capture & Record HUD)"
    echo "  - $0 spotlight       (Toggle Spotlight search)"
    echo "  - $0 control-center  (Toggle Control Center)"
    echo "  - $0 power-menu      (Open the power menu; the gem button in the bar does the same)"
    echo "  - $0 notifications   (Toggle Notification Center)"
    echo "  - $0 dashboard       (Toggle the dashboard under the clock)"
    echo "  - $0 wallpapers      (Toggle the wallpaper picker, Super+W)"
    echo "  - $0 vol-up          (Increase Volume + Bezel OSD)"
    echo "  - $0 vol-down        (Decrease Volume + Bezel OSD)"
    echo "  - $0 mute            (Toggle Mute + Bezel OSD)"
    echo "  - $0 bright-up       (Increase Brightness + Bezel OSD)"
    echo "  - $0 bright-down     (Decrease Brightness + Bezel OSD)"
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
    appswitcher)
        "$BIN" --say appswitcher "emit toggle"
        ;;
    clipboard)
        "$BIN" --say clipboard "emit toggle"
        ;;
    settings)
        "$BIN" --say settings "emit toggle"
        ;;
    lock)
        "$BIN" --say lock "fact locked true"
        ;;
    session)
        K_VAL="${2:-0}"
        "$BIN" --say session "fact kind $K_VAL"
        "$BIN" --say session "fact open true"
        ;;
    capture)
        "$BIN" --say capture "emit toggle"
        ;;
    spotlight)
        "$BIN" --say spotlight "emit toggle"
        ;;
    control-center)
        "$BIN" --say control_center "emit toggle"
        ;;
    power-menu)
        # the first copy of the frame (the monitor the compositor lists first)
        "$BIN" --say topbar "fact open_screen 0"
        "$BIN" --say topbar "fact open true"
        ;;
    notifications|widgets)
        "$BIN" --say notifications "emit toggle"
        ;;
    dashboard)
        "$BIN" --say dashboard "emit toggle"
        ;;
    wallpapers)
        "$BIN" --say wallpapers "emit toggle"
        ;;
    vol-up)
        "$BIN" --say osd "emit volume_up"
        ;;
    vol-down)
        "$BIN" --say osd "emit volume_down"
        ;;
    mute)
        "$BIN" --say osd "emit volume_mute"
        ;;
    bright-up)
        "$BIN" --say osd "emit brightness_up"
        ;;
    bright-down)
        "$BIN" --say osd "emit brightness_down"
        ;;
    osd)
        "$BIN" --say osd "emit popup"
        ;;
    dark-mode)
        VAL="true"
        [ "$2" = "off" ] && VAL="false"
        for comp in topbar spotlight control_center notifications dashboard wallpapers osd settings session capture; do
            "$BIN" --say "$comp" "fact dark_mode $VAL"
        done
        mkdir -p "$(dirname "$CONFIG_FILE")"
        echo "{\"dark_mode\": $VAL, \"skin\": 0}" > "$CONFIG_FILE"
        echo "Dark mode set to $VAL."
        ;;
    skin)
        SKIN_VAL="${2:-0}"
        for comp in topbar spotlight control_center notifications dashboard wallpapers osd settings session capture; do
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
