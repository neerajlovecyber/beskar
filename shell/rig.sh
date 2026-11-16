#!/usr/bin/env bash
# The test rig: runs THIS working tree's desktop process (and widgets) in a nested niri, fully apart from the desktop you use.
#
#   shell/rig.sh start          a nested niri window appears; the shell starts inside it (about 10 s)
#   shell/rig.sh say <scene> …  pleamar --say against the rig's scenes        (shell/rig.sh say topbar "emit open_panel 1")
#   shell/rig.sh key <wtype args>   type into the rig                          (shell/rig.sh key -k Escape)
#   shell/rig.sh shot [file]    screenshot of the rig's screen (default /tmp/beskar-rig/shot.png)
#   shell/rig.sh log            the rig desktop's log
#   shell/rig.sh stop
#
# What keeps it apart: its own session D-Bus (dbus-run-session: the notification server and the tray watcher it claims are not
# yours), its own pleamar sockets (PLEAMAR_SOCKETS), HOME and XDG_DATA_HOME (your preferences, history and widgets are never
# read or written), NIRI_SOCKET pointing at the nested niri, BESKAR_RIG=1 (no second polkit agent: there is one per session),
# and stubs for the commands that would act on the real machine (systemctl, loginctl, gsettings, powerprofilesctl, wlsunset,
# hypridle, pkexec, kitty and other terminals). The lock screen and the capture picker are not started.
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
R="${BESKAR_RIG_DIR:-/tmp/beskar-rig}"
BIN="$DIR/bin/exp/pleamar"

envfile() { echo "$R/env.sh"; }
load() { [ -f "$(envfile)" ] || { echo "rig is not running (shell/rig.sh start)" >&2; exit 1; }; . "$(envfile)"; }

inner() {      # runs under dbus-run-session: niri, then the scenes; waits until stopped
    local wl sock
    env -u NIRI_SOCKET -u WAYLAND_DISPLAY niri -c "$R/nested.kdl" >"$R/niri.log" 2>&1 &
    echo $! >"$R/niri.pid"
    for _ in $(seq 1 100); do
        wl=$(grep -o 'listening on Wayland socket: [^ ]*' "$R/niri.log" 2>/dev/null | awk '{print $NF}' | head -1)
        [ -n "$wl" ] && break; sleep 0.1
    done
    [ -n "$wl" ] || { echo "nested niri did not start" >"$R/error"; exit 1; }
    sock=$(ls -t "${XDG_RUNTIME_DIR}"/niri."$wl".*.sock 2>/dev/null | head -1)
    cat >"$(envfile)" <<EOF
export WAYLAND_DISPLAY='$wl'
export NIRI_SOCKET='$sock'
export PLEAMAR_SOCKETS='$R/sockets'
export XDG_DATA_HOME='$R/data'
export HOME='$R/home'
export PATH='$R/fakebin:$PATH'
export PLEAMAR_SWAPCHAIN=1 PLEAMAR_NO_LENS=1 BESKAR_RIG=1
export BESKAR_DESKTOP_LOG='$R/desktop.log'
export DBUS_SESSION_BUS_ADDRESS='$DBUS_SESSION_BUS_ADDRESS'      # the rig's own bus: notify-send / gdbus here reach the rig, not you
EOF
    . "$(envfile)"
    "$BIN" --no-hud --scene "$DIR/shell/desktop.plm" >"$R/desktop.log" 2>&1 &
    echo $! >>"$R/scenes.pid"
    echo ready >"$R/state"
    wait
}

start() {
    stop >/dev/null 2>&1
    rm -rf "$R"; mkdir -p "$R/sockets" "$R/data" "$R/home/.config/beskar" "$R/fakebin"
    printf '%s\n' "$DIR" >"$R/home/.config/beskar/shell-dir"
    touch "$R/home/.config/beskar/welcome-done"
    cat >"$R/nested.kdl" <<'KDL'
output "winit" {
    scale 1.0
}
prefer-no-csd
hotkey-overlay {
    skip-at-startup
}
layout {
    struts {
        left 6
        right 6
        top 6
        bottom 6
    }
}
KDL
    for c in systemctl loginctl gsettings powerprofilesctl wlsunset hypridle pkexec kitty foot alacritty ghostty wezterm konsole xterm; do
        printf '#!/bin/sh\necho "rig: %s $*" >>"%s/stubbed.log"\nexit 0\n' "$c" "$R" >"$R/fakebin/$c"; chmod +x "$R/fakebin/$c"
    done
    setsid dbus-run-session -- bash "$0" _inner </dev/null >"$R/rig.log" 2>&1 &
    echo $! >"$R/rig.pid"
    for _ in $(seq 1 100); do [ -f "$R/state" ] && break; [ -f "$R/error" ] && { cat "$R/error"; exit 1; }; sleep 0.1; done
    load
    for _ in $(seq 1 120); do
        [ "$("$BIN" --say settings 'get preferences_loaded' 2>/dev/null)" = true ] && break; sleep 0.25
    done
    sleep 1
    echo "rig ready on $WAYLAND_DISPLAY (logs in $R)"
}

stop() {
    [ -f "$R/scenes.pid" ] && xargs -r kill <"$R/scenes.pid" 2>/dev/null
    [ -f "$R/niri.pid" ] && kill "$(cat "$R/niri.pid")" 2>/dev/null
    [ -f "$R/rig.pid" ] && kill -- -"$(cat "$R/rig.pid")" 2>/dev/null
    rm -f "$R/state" "$(envfile)"
    echo "rig stopped"
}

case "${1:-}" in
    _inner) inner ;;
    start) start ;;
    stop) stop ;;
    say) load; shift; "$BIN" --say "$@" ;;
    key) load; shift; wtype "$@" ;;
    shot) load; grim "${2:-$R/shot.png}" && echo "${2:-$R/shot.png}" ;;
    log) tail -n "${2:-40}" "$R/desktop.log" ;;
    *) sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'; exit 1 ;;
esac
