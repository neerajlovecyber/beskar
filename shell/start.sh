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
    # the supervisors first (they would start every scene again), then the scenes themselves
    for pid in $(pgrep -f "shell/supervise.sh" 2>/dev/null); do
        theirs=$(tr '\0' '\n' < "/proc/$pid/environ" 2>/dev/null | sed -n 's/^WAYLAND_DISPLAY=//p' | head -1)
        [ "${theirs:-wayland-0}" = "${WAYLAND_DISPLAY:-wayland-0}" ] && kill "$pid" 2>/dev/null || true
    done
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
    for comp in topbar border spotlight control_center notifications dashboard wallpapers settings lock session capture appswitcher clipboard music overview; do
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
        H12=$(grep -o '"hour12": *[a-z]*' "$CONFIG_FILE" | awk '{print $2}' || true)
        [ -z "$H12" ] && H12="true"
        [ -z "$DM" ] && DM="true"
        [ -z "$SKIN" ] && SKIN="0"

        for comp in topbar border spotlight control_center notifications dashboard wallpapers settings session capture appswitcher clipboard music overview widgets widget_bar polkit welcome; do
            "$BIN" --say "$comp" "fact dark_mode $DM" >/dev/null 2>&1 || true
            "$BIN" --say "$comp" "fact skin $SKIN" >/dev/null 2>&1 || true
        done
        for comp in topbar control_center notifications dashboard settings wallpapers spotlight clipboard music session capture appswitcher lock overview widgets widget_bar polkit welcome; do
            "$BIN" --say "$comp" "fact accent $ACCENT" >/dev/null 2>&1 || true
            "$BIN" --say "$comp" "fact accent_auto $AUTO" >/dev/null 2>&1 || true
            "$BIN" --say "$comp" "fact hour12 $H12" >/dev/null 2>&1 || true
        done
    fi
}

start_shell() {
    kill_all
    sleep 0.3

    echo "Starting macOS / iNiR Shell components (Pleamar daemon mode)..."

    # Clipboard history: something has to store what is copied for the clipboard panel (Super+V) to list: one
    # watcher for text and one for images (up to 100 entries, kept across restarts by cliphist)
    if command -v wl-paste >/dev/null 2>&1 && command -v cliphist >/dev/null 2>&1; then
        if [ "$(pgrep -xc wl-paste 2>/dev/null || echo 0)" -lt 2 ]; then
            pkill -x wl-paste 2>/dev/null || true
            setsid wl-paste --type text --watch cliphist -max-items 100 store </dev/null >/dev/null 2>&1 &
            setsid wl-paste --type image --watch cliphist -max-items 100 store </dev/null >/dev/null 2>&1 &
        fi
    fi

    # Wallpapers that ship with Beskar go where the picker looks for them (never overwriting)
    mkdir -p "$HOME/.local/share/beskar/wallpapers"
    cp -n "$DIR"/assets/wallpapers/*.jpg "$HOME/.local/share/beskar/wallpapers/" 2>/dev/null || true
    # The wallpaper (chosen in the picker, Super+W) is painted by pleamar itself: shell/wallpaper.plm, first, so the
    # desktop is never bare. The old awww daemon is not used any more; stop one left from before.
    pkill -x awww-daemon 2>/dev/null || true
    setsid "$DIR/shell/supervise.sh" "$DIR/shell/wallpaper.plm" /tmp/pleamar_wallpaper.log </dev/null >/dev/null 2>&1 &

    setsid "$DIR/shell/supervise.sh" "$DIR/shell/topbar.plm" /tmp/pleamar_topbar.log </dev/null >/dev/null 2>&1 &
    PID_BAR=$!
    # Border neutralized - window borders handled natively by compositor
    PID_BORDER=""
    setsid "$DIR/shell/supervise.sh" "$DIR/shell/spotlight.plm" /tmp/pleamar_spotlight.log </dev/null >/dev/null 2>&1 &
    PID_SPOTLIGHT=$!
    setsid "$DIR/shell/supervise.sh" "$DIR/shell/control_center.plm" /tmp/pleamar_cc.log </dev/null >/dev/null 2>&1 &
    PID_CC=$!
    setsid "$DIR/shell/supervise.sh" "$DIR/shell/notifications.plm" /tmp/pleamar_notifications.log </dev/null >/dev/null 2>&1 &
    PID_WIDGETS=$!
    setsid "$DIR/shell/supervise.sh" "$DIR/shell/dashboard.plm" /tmp/pleamar_dashboard.log </dev/null >/dev/null 2>&1 &
    PID_DASH=$!
    setsid "$DIR/shell/supervise.sh" "$DIR/shell/wallpapers.plm" /tmp/pleamar_wallpapers.log </dev/null >/dev/null 2>&1 &
    PID_WALL=$!
    setsid "$DIR/shell/supervise.sh" "$DIR/shell/settings.plm" /tmp/pleamar_settings.log </dev/null >/dev/null 2>&1 &
    PID_SETTINGS=$!
    setsid "$DIR/shell/supervise.sh" "$DIR/shell/lock.plm" /tmp/pleamar_lock.log </dev/null >/dev/null 2>&1 &
    PID_LOCK=$!
    setsid "$DIR/shell/supervise.sh" "$DIR/shell/session.plm" /tmp/pleamar_session.log </dev/null >/dev/null 2>&1 &
    PID_SESSION=$!
    setsid "$DIR/shell/supervise.sh" "$DIR/shell/capture.plm" /tmp/pleamar_capture.log </dev/null >/dev/null 2>&1 &
    PID_CAPTURE=$!
    setsid "$DIR/shell/supervise.sh" "$DIR/shell/appswitcher.plm" /tmp/pleamar_switcher.log </dev/null >/dev/null 2>&1 &
    PID_SWITCHER=$!
    setsid "$DIR/shell/supervise.sh" "$DIR/shell/clipboard.plm" /tmp/pleamar_clipboard.log </dev/null >/dev/null 2>&1 &
    setsid "$DIR/shell/supervise.sh" "$DIR/shell/music.plm" /tmp/pleamar_music.log </dev/null >/dev/null 2>&1 &
    PID_CLIP=$!
    setsid "$DIR/shell/supervise.sh" "$DIR/shell/widgets.plm" /tmp/pleamar_widgets.log </dev/null >/dev/null 2>&1 &
    setsid "$DIR/shell/supervise.sh" "$DIR/shell/widget_bar.plm" /tmp/pleamar_widget_bar.log </dev/null >/dev/null 2>&1 &
    # The session's polkit authentication agent: the password dialog for programs that need administrator rights
    setsid "$DIR/shell/supervise.sh" "$DIR/shell/polkit.plm" /tmp/pleamar_polkit.log </dev/null >/dev/null 2>&1 &
    # First-run welcome (it opens itself once, when ~/.config/beskar/welcome-done does not exist)
    setsid "$DIR/shell/supervise.sh" "$DIR/shell/welcome.plm" /tmp/pleamar_welcome.log </dev/null >/dev/null 2>&1 &
    # Window overview (Mission Control HUD grid)
    setsid "$DIR/shell/supervise.sh" "$DIR/shell/overview.plm" /tmp/pleamar_overview.log </dev/null >/dev/null 2>&1 &

    echo "$PID_BAR $PID_BORDER $PID_SPOTLIGHT $PID_CC $PID_WIDGETS $PID_DASH $PID_WALL $PID_SETTINGS $PID_LOCK $PID_SESSION $PID_CAPTURE $PID_SWITCHER $PID_CLIP" > "$PID_FILE"
    sleep 0.6

    apply_saved_theme

    mkdir -p "$HOME/.config/beskar" && printf '%s\n' "$DIR" > "$HOME/.config/beskar/shell-dir"
    # Night light: the choice made in Settings comes back at login (0 off, 1 always, 2 sunset to sunrise)
    NIGHT=$(grep -o '"night": *[0-9]*' "$HOME/.config/beskar/prefs.json" 2>/dev/null | awk '{print $2}')
    NIGHT_T=$(grep -o '"night_t": *[0-9]*' "$HOME/.config/beskar/prefs.json" 2>/dev/null | awk '{print $2}')
    case "${NIGHT:-0}" in
        1) "$DIR/shell/nightlight.sh" on "$(echo "${NIGHT_T:-1}" | awk '{split("4500 3800 3200", a, " "); print a[$1+1]}')" ;;
        2) "$DIR/shell/nightlight.sh" auto "$(echo "${NIGHT_T:-1}" | awk '{split("4500 3800 3200", a, " "); print a[$1+1]}')" ;;
    esac
    # Lock when away (minutes chosen in Settings, off by default) and before sleep
    LOCK_MIN=$(grep -o '"lock_min": *[0-9]*' "$HOME/.config/beskar/prefs.json" 2>/dev/null | awk '{print $2}')
    "$DIR/shell/idle.sh" "${LOCK_MIN:-0}" >/dev/null 2>&1 || true

    echo "macOS / iNiR Shell is active!"
    echo "  - Frame (ring + 3 top islands + bottom dock): PID $PID_BAR"
    echo "  - Screen Border: PID $PID_BORDER"
    echo "  - Spotlight Search: PID $PID_SPOTLIGHT"
    echo "  - Control Center: PID $PID_CC"
    echo "  - Apple Menu: PID"
    echo "  - Widgets & Notifications: PID $PID_WIDGETS"
    echo "  - System Settings: PID $PID_SETTINGS"
    echo "  - Wayland Lock Screen: PID $PID_LOCK"
    echo "  - Session Shutdown Dialog: PID $PID_SESSION"
    echo "  - Screen Capture & Record HUD: PID $PID_CAPTURE"
    echo "  - App Switcher (Cmd+Tab): PID $PID_SWITCHER"
    echo "  - Clipboard Manager (Super+V): PID $PID_CLIP"
    echo ""
    echo "Commands & Hotkey Triggers:"
    echo "  - $0 appswitcher     (Toggle Cmd+Tab Application Switcher)"
    echo "  - $0 overview        (Toggle Window Overview grid)"
    echo "  - $0 clipboard       (Toggle Clipboard History Manager)"
    echo "  - $0 settings        (Toggle System Settings)"
    echo "  - $0 shortcuts       (Settings on the keyboard shortcuts list)"
    echo "  - $0 lock            (Lock Screen with ext-session-lock)"
    echo "  - $0 session [0|1|2] (0=Shutdown, 1=Restart, 2=Logout modal)"
    echo "  - $0 capture         (Toggle Screen Capture & Record HUD)"
    echo "  - $0 spotlight       (Toggle Spotlight search)"
    echo "  - $0 control-center  (Toggle Control Center)"
    echo "  - $0 power-menu      (Open the power menu; the gem button in the bar does the same)"
    echo "  - $0 notifications   (Toggle Notification Center)"
    echo "  - $0 dashboard       (Toggle the dashboard under the clock)"
    echo "  - $0 wallpapers      (Toggle the wallpaper picker, Super+W)"
    echo "  - $0 vol-up          (Increase Volume (shown in the centre pill))"
    echo "  - $0 vol-down        (Decrease Volume (shown in the centre pill))"
    echo "  - $0 mute            (Toggle Mute (shown in the centre pill))"
    echo "  - $0 bright-up       (Increase Brightness (shown in the centre pill))"
    echo "  - $0 bright-down     (Decrease Brightness (shown in the centre pill))"
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
        "$BIN" --say topbar "emit open_panel 6"
        ;;
    overview)
        "$BIN" --say topbar "emit open_panel 10"
        ;;
    clipboard)
        "$BIN" --say topbar "emit open_panel 2"
        ;;
    settings)
        "$BIN" --say topbar "emit open_panel 4"
        ;;
    welcome)
        "$BIN" --say welcome "emit show_again"
        ;;
    shortcuts)
        "$BIN" --say settings "fact tab 5" >/dev/null 2>&1 || true
        "$BIN" --say topbar "emit open_panel 4"
        ;;
    widgets)
        "$BIN" --say widgets "emit edit_toggle"
        ;;
    lock)
        "$BIN" --say lock "fact locked true"
        ;;
    session)
        K_VAL="${2:-0}"
        "$BIN" --say session "fact kind $K_VAL"
        "$BIN" --say topbar "emit open_panel 5"
        ;;
    capture)
        "$BIN" --say topbar "emit open_panel 11"
        ;;
    spotlight)
        "$BIN" --say topbar "emit open_panel 1"
        ;;
    control-center)
        # through the frame, which knows which monitor has the focus
        "$BIN" --say topbar "emit open_control_center"
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
        "$BIN" --say topbar "emit open_dashboard"
        ;;
    wallpapers)
        "$BIN" --say topbar "emit open_panel 3"
        ;;
    vol-up)
        "$BIN" --say topbar "emit osd_vol_up"
        ;;
    vol-down)
        "$BIN" --say topbar "emit osd_vol_down"
        ;;
    mute)
        "$BIN" --say topbar "emit osd_vol_mute"
        ;;
    bright-up)
        "$BIN" --say topbar "emit osd_br_up"
        ;;
    bright-down)
        "$BIN" --say topbar "emit osd_br_down"
        ;;
    osd)
        "$BIN" --say topbar "emit osd_popup"
        ;;
    dark-mode)
        VAL="true"
        [ "$2" = "off" ] && VAL="false"
        for comp in topbar spotlight control_center notifications dashboard wallpapers settings session capture overview; do
            "$BIN" --say "$comp" "fact dark_mode $VAL"
        done
        mkdir -p "$(dirname "$CONFIG_FILE")"
        echo "{\"dark_mode\": $VAL, \"skin\": 0}" > "$CONFIG_FILE"
        echo "Dark mode set to $VAL."
        ;;
    skin)
        SKIN_VAL="${2:-0}"
        for comp in topbar spotlight control_center notifications dashboard wallpapers settings session capture overview; do
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
