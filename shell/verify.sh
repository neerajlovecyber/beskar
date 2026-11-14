#!/usr/bin/env bash
# The gate every change passes before it is committed: compile every process, every focused test, the UI geometry guard, and the
# full panel smoke run INSIDE the test rig (shell/rig.sh: a nested niri; your desktop is never touched).
#   shell/verify.sh            everything
#   shell/verify.sh --no-rig   skip the rig stage (compile + tests + guard only)
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"; cd "$DIR" || exit 1
BIN="$DIR/bin/exp/pleamar"
fail=0
step() { printf '\n== %s\n' "$1"; }
bad() { echo "FAIL  $1"; fail=1; }

step "compile"
for scene in desktop widgets lock capture wallpaper; do
    out=$("$BIN" --check "shell/$scene.plm" 2>&1 | tail -1)
    case "$out" in *": ok "*) echo "ok    $scene";; *) bad "$scene: $out";; esac
done

step "focused tests"
for t in tests/*.lua; do
    out=$(lua "$t" 2>&1); code=$?
    [ $code -eq 0 ] && echo "ok    $(basename "$t" .lua): $(printf '%s' "$out" | tail -1 | cut -c1-70)" || bad "$(basename "$t"): $(printf '%s' "$out" | grep -m1 -E 'lua:|assert|Error' | cut -c1-150)"
done

step "UI geometry guard"
python3 shell/check-ui.py >/dev/null 2>&1 && echo "ok    check-ui" || bad "check-ui: $(python3 shell/check-ui.py 2>&1 | head -3)"

if [ "${1:-}" != "--no-rig" ]; then
    step "smoke in the rig"
    if shell/rig.sh start >/dev/null 2>&1; then
        out=$( . /tmp/beskar-rig/env.sh; shell/smoke.sh 2>&1 ); code=$?
        printf '%s\n' "$out" | grep -E '^(ok|FAIL)|SMOKE'
        [ $code -eq 0 ] || bad "smoke in the rig"
        shell/rig.sh stop >/dev/null
    else
        bad "the rig did not start"
    fi
fi

echo
[ $fail -eq 0 ] && echo "VERIFY PASSED" || echo "VERIFY FAILED"
exit $fail
