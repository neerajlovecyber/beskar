"""Exercise shell/display-preview.py against a FAKE niri in a temporary runtime directory.

Nothing here touches a real compositor, HOME or the real XDG_RUNTIME_DIR:
niri is a script that edits a JSON file, NIRI_SOCKET is a socket bound in the
temporary directory, and every watchdog is killed in tearDown.

Run: python3 tests/display-preview.py
"""
import json
import os
import shutil
import signal
import socket
import stat
import subprocess
import sys
import tempfile
import threading
import time
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCRIPT = os.path.join(ROOT, "shell", "display-preview.py")

FAKE_NIRI = r'''#!%(python)s
import json, os, sys
S = %(state)r
def read(name, default=None):
    try:
        return open(os.path.join(S, name)).read()
    except OSError:
        return default
def log(argv):
    with open(os.path.join(S, "calls.log"), "a") as f:
        f.write(json.dumps({"argv": argv, "socket": os.environ.get("NIRI_SOCKET"),
                            "home": os.environ.get("HOME")}) + "\n")
argv = sys.argv[1:]
log(argv)
if read("fail_all") is not None:
    sys.stderr.write("fake niri: down\n"); sys.exit(1)
outs = json.load(open(os.path.join(S, "outputs.json")))
if argv[:3] == ["msg", "-j", "outputs"]:
    print(json.dumps(outs)); sys.exit(0)
if argv[:2] == ["msg", "output"] and len(argv) == 5:
    left = int(read("fail_apply", "0") or 0)
    name, what, value = argv[2], argv[3], argv[4]
    o = outs.get(name)
    if o is None:
        sys.stderr.write("no such output\n"); sys.exit(1)
    def save():
        json.dump(outs, open(os.path.join(S, "outputs.json"), "w"))
    if what == "scale":
        new = round(float(value) * 120) / 120
        if left > 0:
            open(os.path.join(S, "fail_apply"), "w").write(str(left - 1))
            if read("partial") is not None:
                o["logical"]["scale"] = new; save()
            sys.stderr.write("fake niri: refused\n"); sys.exit(1)
        o["logical"]["scale"] = new; save(); sys.exit(0)
    if what == "mode":
        size, _, rate = value.partition("@")
        w, h = (int(x) for x in size.split("x"))
        cands = [(i, m) for i, m in enumerate(o["modes"]) if m["width"] == w and m["height"] == h]
        if rate:
            cands = [(i, m) for i, m in cands if abs(m["refresh_rate"] - round(float(rate) * 1000)) <= 2]
        if not cands:
            sys.stderr.write("no such mode\n"); sys.exit(1)
        if left > 0:
            open(os.path.join(S, "fail_apply"), "w").write(str(left - 1))
            if read("partial") is not None:
                o["current_mode"] = cands[0][0]; save()
            sys.stderr.write("fake niri: refused\n"); sys.exit(1)
        o["current_mode"] = max(cands, key=lambda c: c[1]["refresh_rate"])[0] if not rate else cands[0][0]
        save(); sys.exit(0)
sys.stderr.write("fake niri: unsupported %%r\n" %% (argv,)); sys.exit(2)
'''


def output(name, modes, current, scale=1.0, custom=False, off=False):
    return {"name": name, "modes": [{"width": w, "height": h, "refresh_rate": r, "is_preferred": False}
                                    for w, h, r in modes],
            "current_mode": None if off else current, "is_custom_mode": custom,
            "logical": None if off else {"x": 0, "y": 0, "width": 1920, "height": 1080, "scale": scale,
                                         "transform": "Normal"}}


OUTPUTS = {
    "HDMI-A-1": output("HDMI-A-1", [(1920, 1080, 119982), (1920, 1080, 119879), (1920, 1080, 60000),
                                    (1280, 720, 59943)], 0),
    "eDP-1": output("eDP-1", [(1920, 1080, 60164), (1280, 720, 60164)], 0, scale=1.25),
    "DP-9": output("DP-9", [(1920, 1080, 60000)], 0, off=True),
    "DP-8": output("DP-8", [(1920, 1080, 60000)], 0, custom=True),
}


class Fixture(unittest.TestCase):
    TIMEOUT = "15"

    def setUp(self):
        self.root = tempfile.mkdtemp(prefix="bdp-", dir="/tmp")
        self.rt = os.path.join(self.root, "rt")
        self.home = os.path.join(self.root, "home")
        self.nstate = os.path.join(self.root, "niri-state")
        for d in (self.rt, self.home, self.nstate):
            os.mkdir(d)
        os.chmod(self.rt, 0o700)
        self.sock_path = os.path.join(self.rt, "niri.sock")
        self.sock = socket.socket(socket.AF_UNIX)
        self.sock.bind(self.sock_path)
        self.fake = os.path.join(self.root, "niri")
        with open(self.fake, "w") as f:
            f.write(FAKE_NIRI % {"python": sys.executable, "state": self.nstate})
        os.chmod(self.fake, 0o755)
        self.write_outputs(OUTPUTS)
        self.children = []

    def tearDown(self):
        j = self.journal(required=False)
        for pid in [j and j.get("watchdog_pid")] + [c.pid for c in self.children]:
            if pid:
                try:
                    os.kill(pid, signal.SIGKILL)
                except OSError:
                    pass
        for c in self.children:
            c.wait()
        self.sock.close()
        shutil.rmtree(self.root, ignore_errors=True)

    # -- helpers
    def write_outputs(self, data):
        with open(os.path.join(self.nstate, "outputs.json"), "w") as f:
            json.dump(data, f)

    def outputs(self):
        with open(os.path.join(self.nstate, "outputs.json")) as f:
            return json.load(f)

    def flag(self, name, value="1"):
        with open(os.path.join(self.nstate, name), "w") as f:
            f.write(value)

    def unflag(self, name):
        os.unlink(os.path.join(self.nstate, name))

    def calls(self):
        try:
            with open(os.path.join(self.nstate, "calls.log")) as f:
                return [json.loads(line) for line in f]
        except OSError:
            return []

    def applies(self):
        return [c["argv"] for c in self.calls() if c["argv"][:2] == ["msg", "output"]]

    def env(self, **extra):
        env = {"PATH": os.environ.get("PATH", "/usr/bin:/bin"), "XDG_RUNTIME_DIR": self.rt,
               "NIRI_SOCKET": self.sock_path, "HOME": self.home,
               "BESKAR_DISPLAY_PREVIEW_NIRI": self.fake, "BESKAR_DISPLAY_PREVIEW_LAUNCH": "direct",
               "BESKAR_DISPLAY_PREVIEW_TIMEOUT": self.TIMEOUT, "BESKAR_DISPLAY_PREVIEW_RETRY_GAP": "0.02",
               "BESKAR_DISPLAY_PARENT_PID": "0"}
        env.update(extra)
        return {k: v for k, v in env.items() if v is not None}

    def run_cli(self, *args, env=None):
        r = subprocess.run([sys.executable, SCRIPT] + list(args), env=env or self.env(),
                           stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=60)
        self.assertEqual(r.stderr, "")
        lines = r.stdout.splitlines()
        self.assertEqual(len(lines), 1, r.stdout)
        data = json.loads(lines[0])
        self.assertEqual(data["ok"], r.returncode == 0, (r.returncode, data))
        return r.returncode, data

    def ok(self, *args, **kw):
        rc, data = self.run_cli(*args, **kw)
        self.assertEqual(rc, 0, data)
        return data

    def fails(self, code, *args, **kw):
        rc, data = self.run_cli(*args, **kw)
        self.assertNotEqual(rc, 0, data)
        self.assertEqual(data["error"], code, data)
        return data

    def journal(self, required=True):
        path = os.path.join(self.rt, "beskar", "display-preview", "txn.json")
        try:
            with open(path) as f:
                return json.load(f)
        except OSError:
            if required:
                raise
            return None

    def wait_state(self, want, seconds=8.0):
        end = time.monotonic() + seconds
        while time.monotonic() < end:
            j = self.journal(required=False)
            if j and j["state"] == want:
                return j
            time.sleep(0.05)
        self.fail("state never became %s: %s" % (want, self.journal(required=False)))

    def begin_scale(self, value="1.5", old="1", output="HDMI-A-1", **kw):
        return self.ok("begin", output, "scale", value, old, **kw)

    def scale(self, name="HDMI-A-1"):
        return self.outputs()[name]["logical"]["scale"]

    def mode(self, name="HDMI-A-1"):
        o = self.outputs()[name]
        return o["modes"][o["current_mode"]]["refresh_rate"]


class Normal(Fixture):
    def test_begin_applies_after_capturing_and_arming(self):
        r = self.begin_scale()
        self.assertEqual(r["state"], "pending")
        self.assertRegex(r["token"], r"^[0-9a-f]{32}$")
        self.assertEqual(r["old"], "1")
        self.assertEqual(r["timeout_ms"], 15000)
        self.assertTrue(r["acks"]["watchdog"] and r["acks"]["applied"])
        self.assertAlmostEqual(self.scale(), 1.5)
        calls = self.calls()
        self.assertEqual(calls[0]["argv"], ["msg", "-j", "outputs"])           # queried before capture
        self.assertEqual(self.applies(), [["msg", "output", "HDMI-A-1", "scale", "1.5"]])
        self.assertTrue(all(c["socket"] == self.sock_path for c in calls))      # the captured socket
        self.assertTrue(all(c["home"] is None for c in calls))                  # no HOME for niri
        self.assertEqual(os.listdir(self.home), [])
        j = self.journal()
        self.assertEqual(j["old"]["transform"], "Normal")
        self.assertEqual(j["old"]["scale"], 1.0)
        self.assertEqual(j["old"]["mode"]["refresh_rate"], 119982)
        self.assertEqual(j["niri"]["socket"], self.sock_path)

    def test_private_state(self):
        self.begin_scale()
        base = os.path.join(self.rt, "beskar", "display-preview")
        self.assertEqual(stat.S_IMODE(os.stat(base).st_mode), 0o700)
        for name in os.listdir(base):
            self.assertEqual(stat.S_IMODE(os.stat(os.path.join(base, name)).st_mode), 0o600, name)
        self.assertEqual(sorted(os.listdir(base)), ["lock", "txn.json"])

    def test_status_hides_the_token(self):
        t = self.begin_scale()["token"]
        s = self.ok("status")
        self.assertEqual(s["state"], "pending")
        self.assertTrue(s["watchdog_alive"])
        self.assertLessEqual(s["remaining_ms"], 15000)
        self.assertNotIn(t, json.dumps(s))
        self.assertEqual(self.ok("status")["acks"]["applied"], True)

    def test_status_idle(self):
        self.assertEqual(self.ok("status"), {"ok": True, "state": "idle"})

    def test_keep_confirms_and_the_watchdog_leaves_the_change_alone(self):
        t = self.begin_scale()["token"]
        k = self.ok("keep", t)
        self.assertEqual(k["state"], "kept")
        self.assertTrue(k["acks"]["kept"])
        time.sleep(0.5)                       # a watchdog that mis-restored would have done so by now
        self.assertAlmostEqual(self.scale(), 1.5)
        self.assertEqual(len(self.applies()), 1)
        again = self.ok("keep", t)
        self.assertTrue(again["already"])
        self.fails("already-kept", "revert", t)

    def test_revert_restores_scale(self):
        t = self.begin_scale()["token"]
        r = self.ok("revert", t)
        self.assertEqual((r["state"], r["reason"]), ("reverted", "user"))
        self.assertTrue(r["acks"]["restored"])
        self.assertAlmostEqual(self.scale(), 1.0)
        self.assertEqual(self.applies()[-1], ["msg", "output", "HDMI-A-1", "scale", "1"])
        self.assertTrue(self.ok("revert", t)["already"])
        self.fails("reverted", "keep", t)

    def test_revert_restores_mode_with_explicit_refresh(self):
        t = self.ok("begin", "HDMI-A-1", "mode", "1280x720", "1920x1080@119.982")["token"]
        self.assertEqual(self.mode(), 59943)
        self.ok("revert", t)
        self.assertEqual(self.mode(), 119982)
        self.assertEqual(self.applies()[-1], ["msg", "output", "HDMI-A-1", "mode", "1920x1080@119.982"])

    def test_mode_with_close_refresh_siblings_restores_the_exact_one(self):
        self.write_outputs({**OUTPUTS, "HDMI-A-1": {**OUTPUTS["HDMI-A-1"], "current_mode": 1}})
        t = self.ok("begin", "HDMI-A-1", "mode", "1920x1080@60.000", "-")["token"]
        self.assertEqual(self.mode(), 60000)
        self.ok("revert", t)
        self.assertEqual(self.mode(), 119879)

    def test_only_the_changed_property_is_restored(self):
        t = self.ok("begin", "eDP-1", "mode", "1280x720", "-")["token"]
        self.ok("revert", t)
        self.assertEqual(self.scale("eDP-1"), 1.25)
        self.assertTrue(all(a[3] == "mode" for a in self.applies()))

    def test_scale_rounded_by_niri_is_accepted(self):
        r = self.begin_scale("1.33", "1")
        self.assertEqual(r["state"], "pending")


class Safety(Fixture):
    def test_timeout_is_clamped_to_fifteen_seconds(self):
        r = self.begin_scale(env=self.env(BESKAR_DISPLAY_PREVIEW_TIMEOUT="999"))
        self.assertEqual(r["timeout_ms"], 15000)

    def test_watchdog_restores_on_timeout_without_anyone_asking(self):
        self.TIMEOUT = "0.6"
        t = self.begin_scale(env=self.env(BESKAR_DISPLAY_PREVIEW_TIMEOUT="0.6"))["token"]
        j = self.wait_state("reverted")
        self.assertEqual(j["reason"], "timeout")
        self.assertAlmostEqual(self.scale(), 1.0)
        data = self.fails("reverted", "keep", t)                  # too late to keep
        self.assertEqual(data["reason"], "timeout")
        self.assertAlmostEqual(self.scale(), 1.0)

    def test_settings_crash_while_watchdog_survives(self):
        # begin's caller disappears entirely; only the watchdog is left and it is not its child.
        t = self.begin_scale(env=self.env(BESKAR_DISPLAY_PREVIEW_TIMEOUT="0.6"))
        self.assertAlmostEqual(self.scale(), 1.5)
        pid = self.journal()["watchdog_pid"]
        self.assertNotEqual(os.getpgid(pid), os.getpgid(os.getpid()))   # its own session
        self.wait_state("reverted")
        self.assertAlmostEqual(self.scale(), 1.0)

    def test_parent_death_restores_early(self):
        parent = subprocess.Popen(["sleep", "60"])
        self.children.append(parent)
        r = self.begin_scale(env=self.env(BESKAR_DISPLAY_PARENT_PID=str(parent.pid)))
        self.assertTrue(r["parent_watch"])
        time.sleep(0.4)
        self.assertEqual(self.journal()["state"], "pending")            # alive parent: no revert
        parent.kill()
        parent.wait()
        j = self.wait_state("reverted", 5)
        self.assertEqual(j["reason"], "parent-exit")
        self.assertAlmostEqual(self.scale(), 1.0)

    def test_parent_defaults_to_not_watched_for_wrappers(self):
        r = self.begin_scale(env=self.env(BESKAR_DISPLAY_PARENT_PID=None))
        self.assertFalse(r["parent_watch"])

    def test_dead_watchdog_is_covered_by_the_next_command(self):
        t = self.begin_scale(env=self.env(BESKAR_DISPLAY_PREVIEW_TIMEOUT="0.5"))["token"]
        os.kill(self.journal()["watchdog_pid"], signal.SIGKILL)
        time.sleep(0.8)
        s = self.ok("status")                                            # reconciles
        self.assertEqual((s["state"], s["reason"]), ("reverted", "timeout"))
        self.assertAlmostEqual(self.scale(), 1.0)
        self.fails("reverted", "keep", t)

    def test_sigterm_to_the_watchdog_restores(self):
        self.begin_scale()
        os.kill(self.journal()["watchdog_pid"], signal.SIGTERM)
        j = self.wait_state("reverted")
        self.assertEqual(j["reason"], "signal")
        self.assertAlmostEqual(self.scale(), 1.0)

    def test_keep_after_deadline_is_refused_even_if_the_watchdog_is_slow(self):
        t = self.begin_scale(env=self.env(BESKAR_DISPLAY_PREVIEW_TIMEOUT="0.4"))["token"]
        os.kill(self.journal()["watchdog_pid"], signal.SIGKILL)
        time.sleep(0.6)
        self.fails("reverted", "keep", t)
        self.assertAlmostEqual(self.scale(), 1.0)

    def test_apply_failure_leaves_the_display_unchanged(self):
        self.flag("fail_apply", "1")
        d = self.fails("apply-failed", "begin", "HDMI-A-1", "scale", "2", "1")
        self.assertTrue(d["restored"])
        self.assertAlmostEqual(self.scale(), 1.0)
        self.assertEqual(self.journal()["state"], "reverted")
        self.assertEqual(self.ok("status")["reason"], "apply-failed")
        self.begin_scale("1.5")                                          # and a new one is allowed

    def test_partial_apply_failure_is_rolled_back(self):
        self.flag("fail_apply", "1")
        self.flag("partial")
        d = self.fails("apply-failed", "begin", "HDMI-A-1", "mode", "1280x720", "-")
        self.assertTrue(d["restored"])
        self.assertEqual(self.mode(), 119982)

    def test_watchdog_that_cannot_start_means_nothing_is_applied(self):
        d = self.fails("watchdog-failed", "begin", "HDMI-A-1", "scale", "2", "1",
                       env=self.env(BESKAR_DISPLAY_PREVIEW_LAUNCH="none"))
        self.assertEqual(self.applies(), [])
        self.assertAlmostEqual(self.scale(), 1.0)
        self.assertEqual(self.journal()["state"], "aborted")
        self.begin_scale()                                               # not stuck

    def test_failed_restore_is_retryable_with_the_token(self):
        t = self.begin_scale(env=self.env(BESKAR_DISPLAY_PREVIEW_TIMEOUT="0.4"))["token"]
        self.flag("fail_all")
        j = self.wait_state("restore-failed", 10)
        self.assertFalse(j["acks"]["restored"])
        self.fails("busy", "begin", "HDMI-A-1", "scale", "2", "-")      # niri still down: stays refused
        self.unflag("fail_all")
        deadline = time.monotonic() + 15
        while time.monotonic() < deadline and self.journal()["state"] == "restore-failed":
            r = self.run_cli("revert", t)
            if r[0] == 0:
                break
            time.sleep(0.1)
        self.assertEqual(self.journal()["state"], "reverted")
        self.assertAlmostEqual(self.scale(), 1.0)

    def test_begin_after_failed_restore_retries_it_first(self):
        t = self.begin_scale(env=self.env(BESKAR_DISPLAY_PREVIEW_TIMEOUT="0.4"))["token"]
        self.flag("fail_all")
        self.wait_state("restore-failed", 10)
        self.unflag("fail_all")
        self.ok("begin", "HDMI-A-1", "scale", "1.25", "1")               # restores, then captures scale 1
        self.assertEqual(self.journal()["old"]["scale"], 1.0)

    def test_output_that_vanished_is_not_an_error(self):
        t = self.begin_scale(env=self.env(BESKAR_DISPLAY_PREVIEW_TIMEOUT="0.4"))["token"]
        data = self.outputs()
        del data["HDMI-A-1"]
        self.write_outputs(data)
        j = self.wait_state("reverted")
        self.assertEqual(j["note"], "output-gone")


class Tokens(Fixture):
    def test_wrong_and_malformed_tokens(self):
        t = self.begin_scale()["token"]
        self.fails("stale-token", "keep", "0" * 32)
        self.fails("stale-token", "revert", "0" * 32)
        self.fails("stale-token", "keep", "nope")
        self.fails("stale-token", "keep", t.upper())
        self.assertEqual(self.ok("status")["state"], "pending")
        self.assertAlmostEqual(self.scale(), 1.5)
        self.ok("keep", t)

    def test_no_transaction(self):
        self.fails("no-transaction", "keep", "0" * 32)
        self.begin_scale()
        shutil.rmtree(os.path.join(self.rt, "beskar"))
        self.fails("no-transaction", "revert", "0" * 32)

    def test_previous_token_is_stale_after_a_new_transaction(self):
        t1 = self.begin_scale()["token"]
        self.ok("keep", t1)
        t2 = self.begin_scale("2", "1.5")["token"]
        self.assertNotEqual(t1, t2)
        self.fails("stale-token", "keep", t1)
        self.fails("stale-token", "revert", t1)
        self.assertEqual(self.ok("status")["state"], "pending")
        self.ok("revert", t2)
        self.assertAlmostEqual(self.scale(), 1.5)

    def test_only_one_active_transaction(self):
        t = self.begin_scale()["token"]
        d = self.fails("busy", "begin", "eDP-1", "scale", "1.5", "1.25")
        self.assertEqual(d["state"], "pending")
        self.assertAlmostEqual(self.scale("eDP-1"), 1.25)
        self.ok("keep", t)
        self.ok("begin", "eDP-1", "scale", "1.5", "1.25")

    def test_concurrent_begin_only_one_wins(self):
        procs = [subprocess.Popen([sys.executable, SCRIPT, "begin", "HDMI-A-1", "scale", v, "1"], env=self.env(),
                                  stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True) for v in ("1.5", "2")]
        results = []
        for p in procs:
            out, err = p.communicate(timeout=30)
            self.assertEqual(err, "")
            results.append(json.loads(out))
        self.assertEqual(sorted(r["ok"] for r in results), [False, True], results)
        loser = [r for r in results if not r["ok"]][0]
        self.assertIn(loser["error"], ("busy", "stale-old"))

    def test_keep_and_revert_race_has_exactly_one_winner(self):
        for _ in range(8):
            self.setUp_again()
            t = self.begin_scale()["token"]
            procs = [subprocess.Popen([sys.executable, SCRIPT, cmd, t], env=self.env(),
                                      stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
                     for cmd in ("keep", "revert")]
            keep, revert = [json.loads(p.communicate(timeout=30)[0]) for p in procs]
            j = self.journal()
            self.assertIn(j["state"], ("kept", "reverted"))
            if j["state"] == "kept":
                self.assertTrue(keep["ok"] and not keep.get("already"))
                self.assertFalse(revert["ok"])
                self.assertEqual(revert["error"], "already-kept")
                self.assertAlmostEqual(self.scale(), 1.5)
            else:
                self.assertTrue(revert["ok"] and not revert.get("already"))
                self.assertFalse(keep["ok"])
                self.assertEqual(keep["error"], "reverted")
                self.assertAlmostEqual(self.scale(), 1.0)

    def setUp_again(self):
        j = self.journal(required=False)
        if j and j.get("watchdog_pid"):
            try:
                os.kill(j["watchdog_pid"], signal.SIGKILL)
            except OSError:
                pass
        shutil.rmtree(os.path.join(self.rt, "beskar"), ignore_errors=True)
        self.write_outputs(OUTPUTS)

    def test_keep_racing_the_timeout(self):
        # Keep fired at about the deadline: it must either win cleanly or lose cleanly, never both.
        for _ in range(5):
            self.setUp_again()
            t = self.begin_scale(env=self.env(BESKAR_DISPLAY_PREVIEW_TIMEOUT="0.3"))["token"]
            time.sleep(0.25)
            rc, data = self.run_cli("keep", t)
            j = self.wait_state("kept" if rc == 0 else "reverted")
            self.assertAlmostEqual(self.scale(), 1.5 if rc == 0 else 1.0)
            time.sleep(0.3)
            self.assertEqual(self.journal()["state"], j["state"])           # nothing flips afterwards


class Validation(Fixture):
    def refused(self, code, *args):
        before = len(self.applies())
        self.fails(code, *args)
        self.assertEqual(len(self.applies()), before)
        self.assertFalse(os.path.exists(os.path.join(self.rt, "beskar", "display-preview", "txn.json")))

    def test_output_names(self):
        for bad in ("HDMI A", "-h", "--all", "a;touch x", "$(id)", "a/b", "`id`", "", "x" * 65, "ü"):
            self.refused("bad-output", "begin", bad, "scale", "1.5", "1")
        self.refused("unknown-output", "begin", "HDMI-A-9", "scale", "1.5", "1")

    def test_values_are_never_interpreted(self):
        for bad in ("1.5;touch /tmp/pwned", "$(touch x)", "1e1", "auto", "-1", "0", "0.1", "9", "1.5 ", "1,5", "NaN"):
            self.refused("bad-value", "begin", "HDMI-A-1", "scale", bad, "1")
        for bad in ("1920", "1920x", "1920x1080@", "1920x1080@60;id", "auto", "1920x1080@6e1", "x1080"):
            self.refused("bad-value", "begin", "HDMI-A-1", "mode", bad, "-")
        self.assertFalse(os.path.exists("/tmp/pwned"))
        self.refused("bad-type", "begin", "HDMI-A-1", "transform", "90", "-")
        self.refused("bad-value", "begin", "HDMI-A-1", "scale", "1.5", "$(id)")

    def test_usage_and_control_characters(self):
        for argv in ([], ["nope"], ["begin"], ["begin", "HDMI-A-1", "scale", "1.5"], ["keep"], ["status", "x"],
                     ["begin", "HDMI-A-1", "scale", "1.5", "1", "extra"], ["begin", "HDMI-A-1\n", "scale", "1.5", "1"]):
            rc, data = self.run_cli(*argv)
            self.assertEqual((rc, data["error"]), (2, "usage"), argv)
        self.assertEqual(self.calls(), [])

    def test_unsupported_modes_and_outputs(self):
        self.refused("unsupported", "begin", "HDMI-A-1", "mode", "1024x768", "-")
        self.refused("unsupported", "begin", "HDMI-A-1", "mode", "1920x1080@75.000", "-")
        self.refused("unsupported", "begin", "DP-9", "scale", "1.5", "-")       # off
        self.refused("unsupported", "begin", "DP-8", "mode", "1920x1080", "-")  # custom mode
        self.refused("no-change", "begin", "HDMI-A-1", "scale", "1.0", "-")
        self.refused("no-change", "begin", "HDMI-A-1", "mode", "1920x1080@119.982", "-")

    def test_stale_expectation_is_refused(self):
        d = self.fails("stale-old", "begin", "HDMI-A-1", "scale", "1.5", "2")
        self.assertEqual(d["actual"], "1")
        self.fails("stale-old", "begin", "HDMI-A-1", "mode", "1280x720", "1920x1080@60.000")
        self.assertEqual(self.applies(), [])

    def test_the_old_value_comes_from_niri_not_from_the_caller(self):
        self.begin_scale("1.5", "-")
        self.assertEqual(self.journal()["old"]["scale"], 1.0)

    def test_no_niri(self):
        self.fails("no-niri", "begin", "HDMI-A-1", "scale", "1.5", "1", env=self.env(NIRI_SOCKET=None))
        self.fails("no-niri", "begin", "HDMI-A-1", "scale", "1.5", "1",
                   env=self.env(NIRI_SOCKET=os.path.join(self.rt, "gone.sock")))
        self.fails("no-niri", "begin", "HDMI-A-1", "scale", "1.5", "1",
                   env=self.env(NIRI_SOCKET=os.path.join(self.root, "niri")))   # a file, not a socket
        self.assertEqual(self.calls(), [])

    def test_niri_down(self):
        self.flag("fail_all")
        self.fails("niri-query-failed", "begin", "HDMI-A-1", "scale", "1.5", "1")
        self.assertEqual(self.applies(), [])

    def test_runtime_dir(self):
        self.fails("no-runtime-dir", "begin", "HDMI-A-1", "scale", "1.5", "1", env=self.env(XDG_RUNTIME_DIR=None))
        self.fails("no-runtime-dir", "begin", "HDMI-A-1", "scale", "1.5", "1", env=self.env(XDG_RUNTIME_DIR="rt"))
        os.chmod(self.rt, 0o777)
        self.fails("no-runtime-dir", "begin", "HDMI-A-1", "scale", "1.5", "1")

    def test_state_directory_symlink_is_refused(self):
        os.mkdir(os.path.join(self.rt, "beskar"))
        os.mkdir(os.path.join(self.root, "elsewhere"))
        os.symlink(os.path.join(self.root, "elsewhere"), os.path.join(self.rt, "beskar", "display-preview"))
        self.fails("state-dir", "begin", "HDMI-A-1", "scale", "1.5", "1")
        self.assertEqual(os.listdir(os.path.join(self.root, "elsewhere")), [])

    def test_loose_state_directory_is_tightened(self):
        d = os.path.join(self.rt, "beskar", "display-preview")
        os.makedirs(d)
        os.chmod(d, 0o755)
        self.begin_scale()
        self.assertEqual(stat.S_IMODE(os.stat(d).st_mode), 0o700)

    def test_corrupt_journal_does_not_block(self):
        d = os.path.join(self.rt, "beskar", "display-preview")
        os.makedirs(d, mode=0o700)
        with open(os.path.join(d, "txn.json"), "w") as f:
            f.write("{not json")
        self.begin_scale()
        self.assertTrue(os.path.exists(os.path.join(d, "txn.corrupt")))


if __name__ == "__main__":
    unittest.main(verbosity=2)
