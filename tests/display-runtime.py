#!/usr/bin/env python3
"""Display Keep/Revert through the REAL Settings adapter, native modal keys and the REAL recovery helper.

    python3 tests/display-runtime.py            # about two minutes
    BESKAR_KEEP_RUNTIME=1 python3 tests/display-runtime.py   # keep the temporary tree

Isolation (nothing here can reach a real display, config or the live shell):
  * a nested niri only provides a Wayland socket for pleamar; its own socket is never exported to the shell;
  * `niri` on PATH, and the helper's niri binary, are the FAKE niri of tests/display-preview.py, which edits a
    JSON file; every call (argv, socket, HOME) is journalled and checked at the end;
  * HOME is a throwaway tree whose .config/beskar/shell-dir names a copy of the shell, exactly how the adapter
    finds the helper; there, display-preview.py is a wrapper that sets the private XDG_RUNTIME_DIR / fake niri
    and EXECs the real helper (same pid, so its parent stays pleamar and parent_watch is real);
  * the helper's journal and watchdogs live in a private XDG_RUNTIME_DIR; the real /run/user is checked untouched;
  * every other owner scene is a stub and the other commands Settings could run are harmless stubs on PATH.
Only display-related behaviour is checked.  Scenarios are independent and reported together.
"""
import atexit
import importlib.util
import json
import os
import re
import shutil
import signal
import socket
import subprocess
import sys
import tempfile
import time
import traceback
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
SOURCE = REPO / "shell"
BINARY = str(REPO / "bin/exp/pleamar")

# the fake niri and its outputs come from the helper's own tests: one definition of "niri"
_spec = importlib.util.spec_from_file_location("display_preview_tests", REPO / "tests/display-preview.py")
DP = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(DP)

# the fake gets one extra knob: `delay` (seconds) slows only the APPLY call, to open a race window
FAKE_NIRI = DP.FAKE_NIRI.replace(
    'log(argv)\n',
    'log(argv)\nif argv[:2] == ["msg", "output"] and read("delay"):\n'
    '    import time\n    time.sleep(float(read("delay")))\n', 1)
assert "delay" in FAKE_NIRI

OUTPUTS = {name: DP.OUTPUTS[name] for name in ("HDMI-A-1", "eDP-1")}   # Settings lists them sorted: HDMI first

processes = []
root = None
failures = []
passed = 0


def cleanup():
    for proc in reversed(processes):
        if proc.poll() is None:
            proc.terminate()
            try:
                proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait(timeout=5)
    for pid in watchdog_pids():
        try:
            os.kill(pid, signal.SIGKILL)
        except OSError:
            pass


atexit.register(cleanup)


def check(cond, why):
    global passed
    if not cond:
        raise AssertionError(why)
    passed += 1


# ── the isolated world ───────────────────────────────────────────────

root = Path(tempfile.mkdtemp(prefix="bdr-"))
base = root / "repo"                  # what shell-dir names
scene_dir = base / "shell"            # the copied, latest shell
rt = root / "rt"                      # the helper's private XDG_RUNTIME_DIR
home = root / "home"
nstate = root / "niri-state"
fakebin = root / "fakebin"
for d in (rt, home / ".config/beskar", nstate, fakebin, root / "data"):
    d.mkdir(parents=True)
rt.chmod(0o700)
shutil.copytree(SOURCE, scene_dir, ignore=shutil.ignore_patterns("__pycache__", "*.pyc"))
shutil.copytree(REPO / "assets/icons", base / "assets/icons")
(home / ".config/beskar/shell-dir").write_text(str(base) + "\n")

# owners other than Settings are stubs (no sessions, no notifications, no audio, no panels)
for name in ("topbar", "dialogs", "notifications", "system", "activities"):
    (scene_dir / (name + ".luau")).write_text("-- isolated stub\n")
# Settings is panel 30 of the Panels owner (the frame draws its window): a Panels stub that keeps `open` / `cur` like the real owner
(scene_dir / "panels.luau").write_text(
    'on("close", function() fact.open = false end)\n'
    'on("close_id", function(id) if tonumber(fact.cur) == tonumber(id) then fact.open = false end end)\n')
(scene_dir / "panels.plm").write_text('scene Panels { text panel_mon = "winit"; fact open = false; fact cur = 0; event close ->; event close_id ->; }')
# the Keys scene's texts, as stubs (the real one needs the frame)
(scene_dir / "keys.luau").write_text("-- isolated stub\n")
(scene_dir / "keys.plm").write_text(
    'scene Keys { text side_q = ""; text bind_q = ""; text look_name = ""; text look_document = ""; text quiet_from = ""; text quiet_to = ""; '
    'text shortcut_key = ""; text custom_accent_edit = ""; text frame_output_edit = ""; event set_text ->; }')
(scene_dir / "topbar.plm").write_text(
    "scene Topbar { event close_menu; event open_panel ->; event request_dock_pins ->; event dock_move_pin ->; "
    "surface { size: full, full; level: bottom; anchor: top_left } "
    "box { from: 0, 0; size: screen.width, screen.height; color: #282b39 } }")
(scene_dir / "dialogs.plm").write_text("scene Dialogs { event set_kind ->; }")
(scene_dir / "notifications.plm").write_text(
    "scene Notifications { fact dnd = false; fact quiet = false; text quiet_status = \"\"; text rules_status = \"\"; model quiet_apps max 32 { app: text; mode: number; rule: bool } event cycle_app_rule ->; event set_dnd ->; event set_banner_ms ->; event clear_past ->; }")
(scene_dir / "activities.plm").write_text('scene Activities { fact quiet_focus = false; fact quiet_presentation = false; fact quiet_game = false; event quiet_toggle ->; }')
(scene_dir / "system.plm").write_text(
    'scene System { permissions { services: "audio", "brightness" } '
    "service audio as sound { volume: number; muted: bool } service brightness as display { level: number } }")
(scene_dir / "desktop.plm").write_text("".join(
    f'import scene "{n}.plm" as {a}\n' for n, a in
    [("panels", "Panels"), ("topbar", "Topbar"), ("dialogs", "Dialogs"), ("notifications", "Notifications"),
     ("system", "System"), ("activities", "Activities"), ("keys", "Keys"), ("settings", "Settings")]) + "scene Desktop { }\n")
(root / "nested.kdl").write_text('output "winit" { scale 1.0; }\nprefer-no-csd\nhotkey-overlay { skip-at-startup; }\n')

# harmless stand-ins for everything else Settings can run
fake_niri = fakebin / "niri"
fake_niri.write_text(FAKE_NIRI % {"python": sys.executable, "state": str(nstate)})
fake_niri.chmod(0o755)
for name in ("gsettings", "powerprofilesctl", "matugen", "magick", "systemctl", "loginctl", "kitty", "pacman",
             "yay", "paru", "checkupdates", "wlsunset", "hypridle"):
    p = fakebin / name
    p.write_text("#!/bin/sh\nexit 0\n")
    p.chmod(0o755)

# the private niri socket the helper is told about (a socket file, nothing listens)
sock_path = str(rt / "niri.sock")
niri_sock = socket.socket(socket.AF_UNIX)
niri_sock.bind(sock_path)

# the wrapper the adapter really runs: private runtime + fake niri, then EXEC (same pid, same parent)
(root / "wrapper.json").write_text(json.dumps({"timeout": 15}))
shutil.move(scene_dir / "display-preview.py", scene_dir / "display-preview-real.py")
(scene_dir / "display-preview.py").write_text(f'''#!{sys.executable}
import json, os, sys
cfg = json.load(open({str(root / "wrapper.json")!r}))
with open({str(root / "wrapper.log")!r}, "a") as f:
    comm = open("/proc/%d/comm" % os.getppid()).read().strip()
    f.write(json.dumps({{"pid": os.getpid(), "ppid": os.getppid(), "comm": comm, "argv": sys.argv[1:2]}}) + "\\n")
os.environ.update(XDG_RUNTIME_DIR={str(rt)!r}, NIRI_SOCKET={sock_path!r}, BESKAR_DISPLAY_PREVIEW_NIRI={str(fake_niri)!r},
                  BESKAR_DISPLAY_PREVIEW_LAUNCH="direct", BESKAR_DISPLAY_PREVIEW_RETRY_GAP="0.05",
                  BESKAR_DISPLAY_PREVIEW_TIMEOUT=str(cfg["timeout"]))
os.environ.pop("BESKAR_DISPLAY_PARENT_PID", None)       # the default: watch pleamar, as in production
os.execv(sys.executable, [sys.executable, {str(scene_dir / "display-preview-real.py")!r}] + sys.argv[1:])
''')
(scene_dir / "display-preview.py").chmod(0o755)

real_rt = Path(os.environ.get("XDG_RUNTIME_DIR", "/run/user/%d" % os.getuid()))
real_state = real_rt / "beskar" / "display-preview"
real_before = sorted(p.name for p in real_state.iterdir()) if real_state.is_dir() else None
real_mtime = (real_state / "txn.json").stat().st_mtime if (real_state / "txn.json").exists() else None

env = os.environ.copy()
env.pop("NIRI_SOCKET", None)                       # the shell never learns any niri socket
env.pop("BESKAR_DISPLAY_PARENT_PID", None)
nested_log = root / "nested.log"
niri_proc = subprocess.Popen(["niri", "-c", str(root / "nested.kdl")], env=env, stdout=nested_log.open("w"),
                             stderr=subprocess.STDOUT, start_new_session=True)
processes.append(niri_proc)
for _ in range(200):
    m = re.search(r"listening on Wayland socket: (\S+)", nested_log.read_text())
    if m:
        break
    if niri_proc.poll() is not None:
        raise RuntimeError(nested_log.read_text())
    time.sleep(0.1)
else:
    raise RuntimeError("no nested socket")
env.update(WAYLAND_DISPLAY=m[1], PLEAMAR_SOCKETS=str(root / "sockets"), XDG_DATA_HOME=str(root / "data"),
           HOME=str(home), PATH=str(fakebin) + ":" + env["PATH"], PLEAMAR_SWAPCHAIN="1", PLEAMAR_NO_LENS="1")
scene = None


def start():
    global scene
    scene = subprocess.Popen([BINARY, "--no-hud", "--scene", str(scene_dir / "desktop.plm")], env=env,
                             stdout=(root / "desktop.log").open("a"), stderr=subprocess.STDOUT,
                             start_new_session=True)
    processes.append(scene)
    wait_get("preferences_loaded", "true", 30)
    return scene


# ── drivers ──────────────────────────────────────────────────────────

def say(command):
    r = subprocess.run([BINARY, "--say", "settings", command], env=env, text=True, capture_output=True, timeout=20)
    if r.returncode:
        raise subprocess.CalledProcessError(r.returncode, command, r.stdout, r.stderr)
    return r.stdout.strip()


def panels(command):
    r = subprocess.run([BINARY, "--say", "panels", command], env=env, text=True, capture_output=True, timeout=20)
    if r.returncode:
        raise subprocess.CalledProcessError(r.returncode, command, r.stdout, r.stderr)
    return r.stdout.strip()


def open_window():
    """What the frame does for Settings (panel 30): the Panels owner says it is open."""
    panels("fact cur 30")
    panels("fact open true")


def close_window():
    panels("fact open false")


def get(name):
    try:
        return say("get " + name)
    except subprocess.CalledProcessError:
        return None


def until(fn, seconds, why):
    end = time.monotonic() + seconds
    while time.monotonic() < end:
        v = fn()
        if v:
            return v
        time.sleep(0.05)
    raise AssertionError("timed out: " + why + "\n" + (root / "desktop.log").read_text()[-1500:])


def wait_get(name, value, seconds=10):
    until(lambda: get(name) == str(value), seconds, f"{name} == {value} (is {get(name)!r})")


def key(*args):
    """The frame's rules (common/settings_panel.plm) turn the keys of the Keep / Revert prompt into these events; the key path itself
    (Keys scene -> k_* event -> rule) is covered by shell/smoke.sh in the rig."""
    names = [a for a in args if a not in ("-M", "-m", "shift")]
    if names[:2] == ["-k", "Return"]:
        say("emit display_activate")
    elif names[:2] == ["-k", "Escape"]:
        say("emit display_revert")
    elif names[:2] == ["-k", "Tab"] or names[:2] == ["-k", "Left"] or names[:2] == ["-k", "Right"]:
        say("emit display_sel_flip")
    time.sleep(0.2)


def outputs():
    return json.loads((nstate / "outputs.json").read_text())


def scale(name="HDMI-A-1"):
    return outputs()[name]["logical"]["scale"]


def mode(name="HDMI-A-1"):
    o = outputs()[name]
    m = o["modes"][o["current_mode"]]
    return (m["width"], m["height"], m["refresh_rate"])


def niri_calls():
    try:
        return [json.loads(line) for line in (nstate / "calls.log").read_text().splitlines()]
    except OSError:
        return []


def journal():
    try:
        return json.loads((rt / "beskar/display-preview/txn.json").read_text())
    except (OSError, ValueError):
        return None


def watchdog_pids():
    j = journal()
    return [j["watchdog_pid"]] if j and j.get("watchdog_pid") else []


def alive(pid):
    try:
        os.kill(pid, 0)
        return Path("/proc/%d/stat" % pid).read_text().split(")")[-1].split()[0] not in ("Z", "X")
    except (OSError, IndexError):
        return False


def set_wrapper(timeout=15, delay=None):
    (root / "wrapper.json").write_text(json.dumps({"timeout": timeout}))
    if delay is None:
        (nstate / "delay").unlink(missing_ok=True)
    else:
        (nstate / "delay").write_text(str(delay))


def helper(*args):
    """The real helper, through the same wrapper, from the test (a bystander: not watching any parent)."""
    r = subprocess.run([sys.executable, str(scene_dir / "display-preview.py"), *args], env={"PATH": os.environ["PATH"]},
                       capture_output=True, text=True, timeout=60, stdin=subprocess.DEVNULL)
    return json.loads(r.stdout.splitlines()[-1])


def reset(timeout=15, delay=None):
    """Same starting point for every scenario: idle helper, original outputs, Settings fresh and on Displays."""
    global scene
    for pid in watchdog_pids():
        try:
            os.kill(pid, signal.SIGKILL)
        except OSError:
            pass
    shutil.rmtree(rt / "beskar", ignore_errors=True)
    for name in ("fail_apply", "partial", "fail_all"):
        (nstate / name).unlink(missing_ok=True)
    (nstate / "outputs.json").write_text(json.dumps(OUTPUTS))
    set_wrapper(timeout, delay)
    dirty = scene is None or scene.poll() is not None or get("display_pending") != "false" or get("display_busy") != "false"
    if dirty:
        if scene is not None and scene.poll() is None:
            scene.kill()
            scene.wait(timeout=5)
        start()
    close_window()
    wait_get("open", "false")
    show_displays()


def show_displays(pick=0):
    """Open Settings on Displays; Settings reads the (fake) outputs itself."""
    before = len(niri_calls())
    open_window()
    wait_get("open", "true")
    say("emit set_tab 0")
    say("emit set_tab 1")
    until(lambda: any(c["argv"] == ["msg", "-j", "outputs"] for c in niri_calls()[before:]), 10, "Settings listed outputs")
    time.sleep(0.4)
    if pick:
        say(f"emit disp_pick {pick}")
        time.sleep(0.3)


def begin_scale(index):
    """Choose a scale button; wait until the protected preview is pending."""
    say(f"emit disp_scale {index}")
    wait_get("display_pending", "true", 15)


def settled(state, seconds=10):
    until(lambda: (journal() or {}).get("state") == state, seconds, f"journal state {state} (is {(journal() or {}).get('state')})")


def status_text():
    return get("display_status") or ""


# ── scenarios ────────────────────────────────────────────────────────

def s_begin_is_protected():
    reset()
    check(scale() == 1.0, "starts at scale 1")
    begin_scale(3)                                   # SCALES[4] = 2
    j = journal()
    check(j["state"] == "pending" and j["type"] == "scale" and j["output"] == "HDMI-A-1" and j["requested"] == "2",
          f"journal describes the change: {j}")
    check(scale() == 2.0, "the fake output really changed")
    check(j["old"]["scale"] == 1.0, "the OLD value was captured from niri")
    check(j["acks"]["watchdog"] and j["acks"]["applied"], "watchdog armed before the apply")
    check(alive(j["watchdog_pid"]), "watchdog process is running")
    check(j["parent"] and j["parent"]["pid"] == scene.pid, f"the helper watches pleamar (parent_watch true): {j.get('parent')} vs {scene.pid}")
    check(helper("status")["parent_watch"] is True, "status reports parent_watch true")
    wrapper = [json.loads(l) for l in (root / "wrapper.log").read_text().splitlines()]
    begins = [w for w in wrapper if w["argv"] == ["begin"]]
    check(begins and begins[-1]["ppid"] == scene.pid and begins[-1]["comm"].startswith("pleamar"),
          f"the adapter's process is a direct child of pleamar: {begins[-1:]}")
    check(get("display_busy") == "false" and get("display_sel") == "0", "default selection is Revert (0)")
    check("Reverts in" in status_text(), "countdown text: " + status_text())
    time.sleep(1.5)
    check("Reverts in 1" in status_text() or "Reverts in 1" in (get("display_status") or ""), "the countdown follows the helper: " + status_text())
    subprocess.run(["grim", str(root / "modal.png")], env=env, check=True)
    say("emit display_revert")
    wait_get("display_pending", "false")


def s_default_enter_reverts():
    reset()
    begin_scale(3)
    key("-k", "Return")
    wait_get("display_pending", "false")
    settled("reverted")
    j = journal()
    check(j["reason"] == "user" and scale() == 1.0, f"Return on the default button reverts: {j['reason']}, scale {scale()}")
    check(status_text() == "Previous display setting restored", status_text())
    until(lambda: not alive(j["watchdog_pid"]), 5, "watchdog exits after the revert")


def s_keys_toggle_and_keep():
    reset(timeout=4)
    begin_scale(3)
    check(get("display_sel") == "0", "starts on Revert")
    key("-k", "Right")
    check(get("display_sel") == "1", "Right selects Keep")
    key("-k", "Left")
    check(get("display_sel") == "0", "Left goes back")
    key("-k", "Tab")
    check(get("display_sel") == "1", "Tab toggles")
    key("-M", "shift", "-k", "Tab", "-m", "shift")
    check(get("display_sel") == "0", "Shift+Tab toggles back")
    key("-k", "Right")
    check(get("display_sel") == "1", "Keep selected")
    key("-k", "Return")
    wait_get("display_pending", "false")
    settled("kept")
    check(scale() == 2.0 and status_text() == "Display setting kept", f"Keep leaves the change: {scale()} {status_text()!r}")
    time.sleep(5)                                    # past the confirmation window: the watchdog must stay out
    check(scale() == 2.0 and journal()["state"] == "kept", "no late revert after Keep")
    # Keep refreshed Settings: the displays tab now shows the kept scale (adapter calls refresh)
    check(get("display_busy") == "false", "not busy")


def s_escape_reverts():
    reset()
    begin_scale(3)
    key("-k", "Right")                               # Keep selected, but Escape always means Revert
    key("-k", "Escape")
    wait_get("display_pending", "false")
    settled("reverted")
    check(scale() == 1.0 and journal()["reason"] == "user", "Escape reverts whatever is selected")
    check(get("open") == "true", "Escape in the modal does not also close Settings")


def s_buttons_via_events():
    reset()
    begin_scale(3)
    say("emit display_keep")
    wait_get("display_pending", "false")
    check(scale() == 2.0 and journal()["state"] == "kept", "display_keep (the Keep button) keeps")
    reset()
    begin_scale(3)
    say("emit display_revert")
    wait_get("display_pending", "false")
    check(scale() == 1.0 and journal()["state"] == "reverted", "display_revert (the Revert button) reverts")


def s_timeout_reverts_without_input():
    reset(timeout=3)
    begin_scale(3)
    t0 = time.monotonic()
    wait_get("display_pending", "false", 12)
    waited = time.monotonic() - t0
    j = journal()
    check(j["state"] == "reverted" and j["reason"] == "timeout" and scale() == 1.0, f"timeout restores: {j['state']}/{j['reason']}")
    check(waited < 3 + 2.5, f"Settings notices within one poll of the deadline ({waited:.1f}s)")
    check(status_text() == "Previous display setting restored", status_text())
    # the timer stops with the preview: no helper traffic while idle
    n = sum(1 for l in (root / "wrapper.log").read_text().splitlines())
    time.sleep(3)
    check(sum(1 for l in (root / "wrapper.log").read_text().splitlines()) == n, "no polling after the preview ended")


def s_keep_racing_timeout():
    reset(timeout=2)
    begin_scale(3)
    time.sleep(2.4)                                  # the watchdog (0.1 s tick) has reverted; the 1 s poll may not have run yet
    say("emit display_keep")
    wait_get("display_pending", "false", 8)
    wait_get("display_busy", "false", 8)
    check(scale() == 1.0 and journal()["state"] == "reverted", f"a late Keep never keeps: scale {scale()}")
    check(status_text() == "Previous display setting restored", status_text())


def s_close_reverts_now():
    reset()
    begin_scale(3)
    t0 = time.monotonic()
    close_window()
    wait_get("display_pending", "false", 8)
    check(time.monotonic() - t0 < 4, "closing Settings reverts at once (not after the 15 s)")
    j = journal()
    check(j["state"] == "reverted" and j["reason"] == "user" and scale() == 1.0, f"closed => reverted: {j['state']}/{j['reason']}")
    wait_get("open", "false")
    show_displays()                                  # reopening shows no stale modal
    check(get("display_pending") == "false" and get("display_busy") == "false", "reopened clean")


def s_close_while_beginning():
    reset(delay=1.2)
    say("emit disp_scale 3")
    time.sleep(0.4)                                  # the apply is in flight (fake niri sleeps)
    check(get("display_pending") == "false", "not pending yet")
    close_window()
    wait_get("open", "false")
    until(lambda: (journal() or {}).get("state") in ("reverted", "kept", "pending"), 10, "begin finished")
    wait_get("display_pending", "false", 10)
    settled("reverted")
    check(scale() == 1.0 and journal()["reason"] == "user", f"a preview that starts after Close is reverted: scale {scale()}")


def s_settings_crash_recovery():
    reset(timeout=15)
    begin_scale(3)
    j = journal()
    wd, pid = j["watchdog_pid"], scene.pid
    check(scale() == 2.0 and alive(wd), "preview pending with a live watchdog")
    t0 = time.monotonic()
    scene.kill()
    scene.wait(timeout=5)
    until(lambda: (journal() or {}).get("state") == "reverted", 8, "watchdog reverted after pleamar died")
    j = journal()
    check(j["reason"] == "parent-exit" and scale() == 1.0, f"crash => early revert: {j['reason']}, scale {scale()}")
    check(time.monotonic() - t0 < 6, "far sooner than the 15 s confirmation window")
    until(lambda: not alive(wd), 5, "watchdog exited")
    start()                                          # a fresh Settings
    open_window()
    wait_get("open", "true")
    check(get("display_pending") == "false" and get("display_busy") == "false", "the restarted Settings shows no modal")
    check(scale() == 1.0, "display stays restored")
    # and it can preview again after recovery
    show_displays()
    begin_scale(3)
    say("emit display_revert")
    wait_get("display_pending", "false")


def s_both_die_then_next_use_recovers():
    """Watchdog AND Settings gone: nothing runs until something asks.  Reports what a restart does."""
    reset(timeout=15)
    begin_scale(3)
    wd = journal()["watchdog_pid"]
    os.kill(wd, signal.SIGKILL)
    scene.kill()
    scene.wait(timeout=5)
    until(lambda: not alive(wd), 5, "watchdog killed")
    start()
    time.sleep(2.5)
    stuck = scale() == 2.0
    GAPS.append(("a restarted Settings does not reconcile an orphaned pending preview "
                 "(display stays changed until the 15 s deadline passes and something calls the helper)") if stuck else None)
    r = helper("status")                             # the helper's safety net: whoever asks next finishes the job
    check(r["state"] == "reverted" and r["reason"] in ("parent-exit", "timeout") and scale() == 1.0,
          f"the next helper call restores: {r}")


def s_mode_choices_restore_exactly():
    reset()
    check(mode() == (1920, 1080, 119982), "starts on the 119.982 Hz mode (a 119.879 sibling exists)")
    say("emit disp_res 1")                           # 1280 x 720
    wait_get("display_pending", "true", 15)
    check(mode()[:2] == (1280, 720) and journal()["type"] == "mode", f"mode applied: {mode()}")
    key("-k", "Return")
    wait_get("display_pending", "false")
    check(mode() == (1920, 1080, 119982), f"revert restores the EXACT refresh rate: {mode()}")
    show_displays()
    say("emit disp_hz 1")                            # the 60 Hz sibling at the same size
    wait_get("display_pending", "true", 15)
    check(mode() == (1920, 1080, 60000), f"refresh applied: {mode()}")
    key("-k", "Escape")
    wait_get("display_pending", "false")
    check(mode() == (1920, 1080, 119982), "Escape restores the refresh rate")


def s_selected_output_is_the_one_changed():
    reset()
    show_displays(pick=1)                            # eDP-1 (scale 1.25)
    say("emit disp_scale 0")                         # 1
    wait_get("display_pending", "true", 15)
    j = journal()
    check(j["output"] == "eDP-1" and scale("eDP-1") == 1.0 and scale("HDMI-A-1") == 1.0, f"only eDP-1 changed: {j['output']}")
    check(abs(j["old"]["scale"] - 1.25) < 0.01, "old value is eDP-1's 1.25")
    key("-k", "Return")
    wait_get("display_pending", "false")
    check(abs(scale("eDP-1") - 1.25) < 0.01, "eDP-1 restored")


def s_failures_are_shown_and_do_not_wedge():
    reset()
    (nstate / "fail_apply").write_text("1")
    (nstate / "partial").write_text("1")
    say("emit disp_scale 3")
    until(lambda: "refused" in status_text() or "apply" in status_text().lower() or "fail" in status_text().lower(), 10,
          "failure text: " + status_text())
    wait_get("display_busy", "false")
    check(get("display_pending") == "false" and scale() == 1.0, f"a partial failure is rolled back: {scale()}")
    check("refused" in status_text(), "the message names the refusal: " + status_text())
    say("emit disp_scale 0")                         # already 1.0
    until(lambda: "already uses" in status_text(), 10, "no-change text: " + status_text())
    wait_get("display_busy", "false")
    begin_scale(3)                                   # the adapter is not stuck busy / holding a stale token
    say("emit display_revert")
    wait_get("display_pending", "false")
    check(scale() == 1.0, "works again after errors")


def s_busy_is_refused_politely():
    reset()
    begin_scale(3)
    calls = len((root / "wrapper.log").read_text().splitlines())
    say("emit disp_scale 2")                         # while a preview waits, a second change is ignored by the adapter
    time.sleep(0.5)
    check(len((root / "wrapper.log").read_text().splitlines()) == calls, "a second change while pending starts nothing")
    check(scale() == 2.0 and get("display_pending") == "true", "the first preview is untouched")
    say("emit display_revert")
    wait_get("display_pending", "false")


def s_modal_blocks_the_sheet():
    reset()
    begin_scale(3)
    key("Hello")                                     # typing must not reach the search / sheet
    check(get("display_pending") == "true", "typing does not dismiss the modal")
    check(get("settings_search") in ("false", None), "search did not take the typing")
    key("-k", "Escape")
    wait_get("display_pending", "false")


SCENARIOS = [s_begin_is_protected, s_default_enter_reverts, s_keys_toggle_and_keep, s_escape_reverts,
             s_buttons_via_events, s_timeout_reverts_without_input, s_keep_racing_timeout, s_close_reverts_now,
             s_close_while_beginning, s_settings_crash_recovery, s_both_die_then_next_use_recovers,
             s_mode_choices_restore_exactly, s_selected_output_is_the_one_changed,
             s_failures_are_shown_and_do_not_wedge, s_busy_is_refused_politely, s_modal_blocks_the_sheet]
GAPS = []


def main():
    only = set(sys.argv[1:])
    start()
    (root / "fixture.json").write_text(json.dumps({"root": str(root), "niri": niri_proc.pid, "scene": scene.pid}))
    for fn in SCENARIOS:
        if only and fn.__name__ not in only and fn.__name__[2:] not in only:
            continue
        t0 = time.monotonic()
        try:
            fn()
            print("ok    %-44s %.1fs" % (fn.__name__, time.monotonic() - t0), flush=True)
        except Exception:
            failures.append(fn.__name__)
            print("FAIL  %-44s %.1fs" % (fn.__name__, time.monotonic() - t0), flush=True)
            traceback.print_exc()
            subprocess.run(["grim", str(root / ("fail-" + fn.__name__ + ".png"))], env=env)
    # whole-run isolation checks
    try:
        calls = niri_calls()
        check(calls, "the fake niri was used")
        bad = [c for c in calls if c["socket"] not in (None, sock_path)]
        check(not bad, f"every niri call used the private socket or none: {bad[:2]}")
        check(all(c["argv"][:2] == ["msg", "output"] or c["argv"] == ["msg", "-j", "outputs"] for c in calls), "only output queries/changes")
        check("runtime error" not in (root / "desktop.log").read_text().lower(), "no Luau runtime error in the log")
        after = sorted(p.name for p in real_state.iterdir()) if real_state.is_dir() else None
        mt = (real_state / "txn.json").stat().st_mtime if (real_state / "txn.json").exists() else None
        check(after == real_before and mt == real_mtime, "the real runtime dir's display-preview state is untouched")
        print("ok    whole-run isolation (%d fake niri calls, none real)" % len(calls))
    except Exception:
        failures.append("isolation")
        print("FAIL  whole-run isolation")
        traceback.print_exc()
    for g in filter(None, GAPS):
        print("GAP   " + g)
    print("%d checks, %d failing scenarios; runtime: %s" % (passed, len(failures), root))
    return 1 if failures else 0


if __name__ == "__main__":
    code = main()
    cleanup()
    if not code and not os.environ.get("BESKAR_KEEP_RUNTIME"):
        shutil.rmtree(root, ignore_errors=True)
    sys.exit(code)
