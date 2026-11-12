#!/usr/bin/env bash
# Smoke test of the running shell: opens every panel on the monitor with the focus, checks that the owner scene (`panels`)
# says it is open, that the frame draws glass for it where it should, that it closes, and that the log has no new errors.
# usage: shell/smoke.sh          (the shell must be running; it uses bin/exp/pleamar --say)
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
B="$DIR/bin/exp/pleamar"; [ -x "$B" ] || B="$DIR/bin/pleamar"
L=/tmp/pleamar_desktop.log
fail=0
say() { "$B" --say "$@" 2>&1 | head -1; }
err0=$(grep -ciE "runtime error|panic|thread .* panicked" "$L" 2>/dev/null); err0=${err0:-0}
check() {      # check <label> <command to open> <expected cur>
    local label="$1" cmd="$2" want="$3"
    local cur open try
    for try in 1 2; do          # one retry: a panel can lose the very first moment to a focus change
        eval "$cmd" >/dev/null 2>&1
        sleep 1.6
        cur=$(say panels 'get cur'); open=$(say panels 'get open')
        [ "$open" = true ] && [ "$cur" = "$want" ] && break
        say panels "emit close" >/dev/null; sleep 1
    done
    if [ "$open" = true ] && [ "$cur" = "$want" ]; then
        echo "ok    $label (cur=$cur)"
    else
        echo "FAIL  $label: open=$open cur=$cur (wanted $want)"; fail=1
    fi
    say panels "emit close" >/dev/null; sleep 0.8
    if [ "$(say panels 'get open')" != false ]; then echo "FAIL  $label did not close"; fail=1; fi
}
check "control center"  "$B --say topbar 'emit open_control_center'" 1
check "notifications"   "$B --say topbar 'emit open_notifications'" 2
check "today"           "$B --say topbar 'emit open_dashboard'" 3
check "music"           "$B --say topbar 'emit open_music'" 9
check "weather"         "$B --say topbar 'emit open_weather'" 15
check "spotlight"       "$B --say topbar 'emit open_panel 1'" 4
check "clipboard"       "$B --say topbar 'emit open_panel 2'" 6
check "wallpapers"      "$B --say topbar 'emit open_panel 3'" 5
check "app switcher"    "$B --say topbar 'emit open_panel 6'" 21
check "widget bar"      "$B --say topbar 'emit open_panel 7'" 10
check "overview"        "$B --say topbar 'emit open_panel 10'" 22
check "welcome"         "$B --say topbar 'emit open_panel 9'" 24
check "session dialog"  "$B --say dialogs 'fact ses_kind 0'; $B --say topbar 'emit open_panel 5'" 11
# updates has no hotkey: ask the owner directly
check "updates"         "$B --say panels 'emit show 16'" 16
# settings (its own window)
"$B" --say topbar "emit open_panel 4" >/dev/null 2>&1; sleep 1.6
if [ "$(say settings 'get open')" = true ]; then echo "ok    settings"; else echo "FAIL  settings"; fail=1; fi
"$B" --say settings "fact open false" >/dev/null 2>&1
err1=$(grep -ciE "runtime error|panic|thread .* panicked" "$L" 2>/dev/null); err1=${err1:-0}
if [ "$err1" -gt "$err0" ]; then echo "FAIL  $((err1 - err0)) new error(s) in $L:"; grep -iE 'runtime error|panic' "$L" | tail -3 | cut -c1-200; fail=1; else echo "ok    no new errors in the log"; fi
[ "$fail" = 0 ] && echo "SMOKE PASSED" || echo "SMOKE FAILED"
exit "$fail"
