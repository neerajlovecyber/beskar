#!/usr/bin/env python3
"""Keep / Revert for a display change, with a recovery path independent of Settings.

    display-preview.py begin OUTPUT scale|mode REQUESTED OLD|-
    display-preview.py keep TOKEN
    display-preview.py revert TOKEN
    display-preview.py status

Every command prints ONE line of JSON on stdout: {"ok": true|false, ...}.
Exit status: 0 ok, 1 refused / failed, 2 usage.  Arguments are positional and
are validated against fixed grammars; nothing is ever passed to a shell.

`begin` captures the output's CURRENT scale / transform / mode from
`niri msg -j outputs` (the actual state, not what a UI believes), starts a
detached watchdog and waits until it is armed, and only then applies the change.
The watchdog restores the old value when nobody confirms within 15 s, when the
watched parent process dies, or when it is asked to stop.  `keep` confirms.
Everything is serialised by one flock; the journal (txn.json, the only state)
lives in $XDG_RUNTIME_DIR/beskar/display-preview/ (mode 700, files 600).
See docs/CUSTOMIZATION_PLAN.md (C6).  Never touches HOME or any config file.
"""
import fcntl
import hmac
import json
import math
import os
import re
import secrets
import shutil
import signal
import stat
import subprocess
import sys
import time

JOURNAL_VERSION = 1
MAX_TIMEOUT = 15.0            # the confirmation window is never longer than this
NIRI_CALL_TIMEOUT = 5.0
APPLY_GUARD = 12.0            # watchdog's deadline while `begin` is applying
ARMING_STALE = 8.0            # an "arming" journal older than this was abandoned
READY_WAIT = 2.5              # how long begin waits for each watchdog launch
RESTORE_ATTEMPTS = 4
WATCHDOG_ROUNDS = 3           # extra restore rounds after a failed one
LOCK_WAIT = 45.0
TICK = 0.1
ACTIVE = ("arming", "applying", "pending")
SCALE_TOLERANCE = 0.02        # niri rounds a scale to 1/120
TEST_ENV_PREFIX = "BESKAR_DISPLAY_PREVIEW_"

OUTPUT_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._:+-]{0,63}$")
TOKEN_RE = re.compile(r"^[0-9a-f]{32}$")
ID_RE = re.compile(r"^[0-9a-f]{16}$")
SCALE_RE = re.compile(r"^[0-9]{1,2}(?:\.[0-9]{1,4})?$")
MODE_RE = re.compile(r"^([0-9]{3,5})x([0-9]{3,5})(?:@([0-9]{1,3}(?:\.[0-9]{1,3})?))?$")


class Fail(Exception):
    def __init__(self, code, message="", **extra):
        super().__init__(message or code)
        self.code, self.message, self.extra = code, message or code, extra


def now():
    return time.monotonic()


def env_float(name, default, low, high):
    try:
        value = float(os.environ.get(TEST_ENV_PREFIX + name, ""))
    except ValueError:
        return default
    return min(high, max(low, value)) if math.isfinite(value) else default


def confirm_timeout():
    return env_float("TIMEOUT", MAX_TIMEOUT, 0.2, MAX_TIMEOUT)


def retry_gap():
    return env_float("RETRY_GAP", 0.5, 0.0, 2.0)


# ── state directory, lock, journal ──────────────────────────────────

def runtime_dir():
    rt = os.environ.get("XDG_RUNTIME_DIR", "")
    if not rt or not os.path.isabs(rt) or "\0" in rt:
        raise Fail("no-runtime-dir", "XDG_RUNTIME_DIR is not set")
    try:
        st = os.stat(rt)
    except OSError:
        raise Fail("no-runtime-dir", "XDG_RUNTIME_DIR is not usable")
    if not stat.S_ISDIR(st.st_mode) or st.st_uid != os.getuid() or st.st_mode & 0o022:
        raise Fail("no-runtime-dir", "XDG_RUNTIME_DIR is not a private directory of this user")
    return rt


def private_dir(path, tighten):
    try:
        os.mkdir(path, 0o700)
    except FileExistsError:
        pass
    except OSError as e:
        raise Fail("state-dir", "cannot create %s: %s" % (path, e.strerror))
    st = os.lstat(path)
    if not stat.S_ISDIR(st.st_mode) or st.st_uid != os.getuid():
        raise Fail("state-dir", "%s is not a directory of this user" % path)
    if tighten and st.st_mode & 0o077:
        os.chmod(path, 0o700)


def state_dir(create):
    rt = runtime_dir()
    base = os.path.join(rt, "beskar")
    leaf = os.path.join(base, "display-preview")
    if create:
        private_dir(base, False)
        private_dir(leaf, True)
    elif not os.path.isdir(leaf):
        return None
    return leaf


class Lock:
    """Exclusive flock on <state>/lock; every journal transition happens under it."""

    def __init__(self, directory):
        self.path = os.path.join(directory, "lock")
        self.fd = None

    def __enter__(self):
        self.fd = os.open(self.path, os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW | os.O_CLOEXEC, 0o600)
        os.fchmod(self.fd, 0o600)
        end = now() + LOCK_WAIT
        while True:
            try:
                fcntl.flock(self.fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
                return self
            except BlockingIOError:
                if now() > end:
                    os.close(self.fd)
                    raise Fail("lock-timeout", "another display-preview command is busy")
                time.sleep(0.02)

    def __exit__(self, *exc):
        try:
            os.close(self.fd)   # closing releases the flock
        except OSError:
            pass


def journal_path(directory):
    return os.path.join(directory, "txn.json")


def read_journal(directory):
    try:
        fd = os.open(journal_path(directory), os.O_RDONLY | os.O_NOFOLLOW | os.O_CLOEXEC)
    except FileNotFoundError:
        return None
    except OSError:
        raise Fail("corrupt-journal", "journal cannot be opened")
    try:
        st = os.fstat(fd)
        if not stat.S_ISREG(st.st_mode) or st.st_uid != os.getuid() or st.st_size > 65536:
            raise Fail("corrupt-journal", "journal has the wrong type or owner")
        with os.fdopen(fd, "r", encoding="utf-8") as f:
            fd = None
            data = json.load(f)
    except Fail:
        raise
    except (ValueError, OSError):
        raise Fail("corrupt-journal", "journal is not valid JSON")
    finally:
        if fd is not None:
            os.close(fd)
    required = ("v", "id", "token", "state", "output", "type", "old", "niri", "acks")
    if not isinstance(data, dict) or data.get("v") != JOURNAL_VERSION or any(k not in data for k in required):
        raise Fail("corrupt-journal", "journal has an unknown layout")
    return data


def write_journal(directory, j):
    j["updated"] = now()
    tmp = os.path.join(directory, "txn.%d.tmp" % os.getpid())
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW | os.O_CLOEXEC, 0o600)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump(j, f, sort_keys=True)
            f.flush()
            os.fsync(f.fileno())
        os.replace(tmp, journal_path(directory))
    except BaseException:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


def set_aside_corrupt(directory):
    try:
        os.replace(journal_path(directory), os.path.join(directory, "txn.corrupt"))
    except OSError:
        pass


# ── processes ───────────────────────────────────────────────────────

def proc_info(pid):
    """(state letter, start time in ticks) of a live process, else None."""
    try:
        with open("/proc/%d/stat" % pid, "r", encoding="utf-8", errors="replace") as f:
            rest = f.read().rsplit(")", 1)[1].split()
        return rest[0], rest[19]
    except (OSError, IndexError, ValueError):
        return None


def proc_alive(pid, start):
    info = proc_info(pid)
    return bool(info) and info[0] not in ("Z", "X") and (start is None or info[1] == start)


def proc_comm(pid):
    try:
        with open("/proc/%d/comm" % pid, "r", encoding="utf-8", errors="replace") as f:
            return f.read().strip()
    except OSError:
        return ""


def parent_to_watch():
    """The process whose death means Settings is gone.

    BESKAR_DISPLAY_PARENT_PID=<pid> says it explicitly (0 / none = do not watch).
    Without it the direct parent is watched only when it is pleamar itself: a
    short-lived wrapper or a terminal must not make every change revert at once.
    """
    explicit = os.environ.get("BESKAR_DISPLAY_PARENT_PID", "").strip().lower()
    if explicit in ("0", "none"):
        return None
    if explicit:
        if not explicit.isdigit() or int(explicit) <= 1:
            raise Fail("bad-parent", "BESKAR_DISPLAY_PARENT_PID is not a pid")
        pid = int(explicit)
    else:
        pid = os.getppid()
        if pid <= 1 or not proc_comm(pid).startswith("pleamar"):
            return None
    info = proc_info(pid)
    if not info or info[0] in ("Z", "X"):
        return None
    return {"pid": pid, "start": info[1]}


def parent_dead(j):
    p = j.get("parent")
    return bool(p) and not proc_alive(p["pid"], p["start"])


# ── niri ────────────────────────────────────────────────────────────

class NiriError(Exception):
    pass


def niri_env(j):
    env = {"PATH": os.environ.get("PATH", "/usr/bin:/bin"), "LANG": "C",
           "NIRI_SOCKET": j["niri"]["socket"]}
    if os.environ.get("XDG_RUNTIME_DIR"):
        env["XDG_RUNTIME_DIR"] = os.environ["XDG_RUNTIME_DIR"]
    return env


def niri_run(j, args):
    try:
        r = subprocess.run([j["niri"]["bin"]] + args, env=niri_env(j), stdin=subprocess.DEVNULL,
                           stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=NIRI_CALL_TIMEOUT,
                           close_fds=True, cwd="/")
    except subprocess.TimeoutExpired:
        raise NiriError("niri did not answer in %ds" % NIRI_CALL_TIMEOUT)
    except OSError as e:
        raise NiriError("cannot run niri: %s" % e.strerror)
    if r.returncode != 0:
        raise NiriError("niri failed: %s" % r.stderr.decode("utf-8", "replace").strip()[:160])
    return r.stdout


def niri_outputs(j):
    out = niri_run(j, ["msg", "-j", "outputs"])
    if len(out) > 4_000_000:
        raise NiriError("niri output list is too large")
    try:
        data = json.loads(out.decode("utf-8", "replace"))
    except ValueError:
        raise NiriError("niri output list is not JSON")
    if not isinstance(data, dict):
        raise NiriError("niri output list has an unknown shape")
    return data


def describe(o):
    """Scale / transform / current mode of one output, or Fail(unsupported)."""
    logical = o.get("logical")
    if not isinstance(logical, dict):
        raise Fail("unsupported", "the output is off")
    try:
        scale = float(logical["scale"])
        modes, index = o["modes"], o["current_mode"]
        if not isinstance(modes, list) or not isinstance(index, int) or isinstance(index, bool) \
                or not 0 <= index < len(modes):
            raise KeyError("current_mode")
        m = modes[index]
        mode = {"width": int(m["width"]), "height": int(m["height"]), "refresh_rate": int(m["refresh_rate"])}
    except (KeyError, TypeError, ValueError):
        raise Fail("unsupported", "niri did not report this output's mode")
    return {"scale": scale, "transform": str(logical.get("transform", "Normal")), "mode": mode,
            "custom": bool(o.get("is_custom_mode"))}


def fmt_scale(value):
    return ("%.6f" % value).rstrip("0").rstrip(".")


def fmt_mode(m):
    return "%dx%d@%.3f" % (m["width"], m["height"], m["refresh_rate"] / 1000.0)


def mode_matches(cur, m):
    return cur["width"] == m["width"] and cur["height"] == m["height"] \
        and abs(cur["refresh_rate"] - m["refresh_rate"]) <= 2


def restore_args(j):
    if j["type"] == "scale":
        return ["msg", "output", j["output"], "scale", fmt_scale(j["old"]["scale"])]
    return ["msg", "output", j["output"], "mode", fmt_mode(j["old"]["mode"])]


def is_old(j, cur):
    if j["type"] == "scale":
        return abs(cur["scale"] - j["old"]["scale"]) < 0.005
    return mode_matches(cur["mode"], j["old"]["mode"])


def parse_requested(typ, text):
    """Canonical request for the journal; Fail(bad-value) when it is malformed."""
    if typ == "scale":
        if not SCALE_RE.match(text):
            raise Fail("bad-value", "scale must look like 1.25")
        value = float(text)
        if not 0.25 <= value <= 8.0:
            raise Fail("bad-value", "scale must be between 0.25 and 8")
        return {"scale": value}
    m = MODE_RE.match(text)
    if not m:
        raise Fail("bad-value", "mode must look like 1920x1080 or 1920x1080@60.000")
    rate = int(round(float(m.group(3)) * 1000)) if m.group(3) else None
    return {"width": int(m.group(1)), "height": int(m.group(2)), "refresh_rate": rate}


def apply_args(j, want):
    if j["type"] == "scale":
        return ["msg", "output", j["output"], "scale", fmt_scale(want["scale"])]
    spec = "%dx%d" % (want["width"], want["height"])
    if want["refresh_rate"] is not None:
        spec += "@%.3f" % (want["refresh_rate"] / 1000.0)
    return ["msg", "output", j["output"], "mode", spec]


def applied(j, want, cur):
    if j["type"] == "scale":
        return abs(cur["scale"] - want["scale"]) <= SCALE_TOLERANCE
    m = cur["mode"]
    if (m["width"], m["height"]) != (want["width"], want["height"]):
        return False
    return want["refresh_rate"] is None or abs(m["refresh_rate"] - want["refresh_rate"]) <= 5


# ── restoring and reconciling (the caller holds the lock) ───────────

def finish(directory, j, state, reason, **fields):
    j["state"], j["reason"] = state, reason
    j.update(fields)
    if state == "reverted":
        j["acks"]["reverted"] = True
    write_journal(directory, j)
    return j


def restore(directory, j, reason):
    """Put the old value back, verify it, and journal the outcome. Idempotent."""
    last = "unknown"
    for attempt in range(RESTORE_ATTEMPTS):
        try:
            outs = niri_outputs(j)
            o = outs.get(j["output"])
            if not isinstance(o, dict) or not isinstance(o.get("logical"), dict):
                j["acks"]["restored"] = False
                return finish(directory, j, "reverted", reason, note="output-gone")
            if is_old(j, describe(o)):
                j["acks"]["restored"] = True
                return finish(directory, j, "reverted", reason, error=None)
            niri_run(j, restore_args(j))
            time.sleep(0.05)
            if is_old(j, describe(niri_outputs(j)[j["output"]])):
                j["acks"]["restored"] = True
                return finish(directory, j, "reverted", reason, error=None)
            last = "the old value did not stick"
        except NiriError as e:
            last = str(e)
        except (KeyError, Fail):
            last = "output state could not be read"
        if attempt + 1 < RESTORE_ATTEMPTS:
            time.sleep(retry_gap())
    j["acks"]["restored"] = False
    return finish(directory, j, "restore-failed", reason, error=last)


def overdue_reason(j):
    if j["state"] == "arming":
        return "arming-timeout" if now() - j["created"] > ARMING_STALE else None
    if j["state"] in ("applying", "pending"):
        if j.get("deadline") is not None and now() > j["deadline"]:
            return "timeout"
        if parent_dead(j):
            return "parent-exit"
    return None


def reconcile(directory, j):
    """Act on an active transaction whose time ran out or whose parent died."""
    if j["state"] not in ACTIVE:
        return j
    reason = overdue_reason(j)
    if reason is None:
        return j
    if j["state"] == "arming":      # nothing was applied
        return finish(directory, j, "aborted", reason)
    return restore(directory, j, reason)


def public(j):
    left = None
    if j["state"] == "pending" and j.get("deadline") is not None:
        left = max(0, int((j["deadline"] - now()) * 1000))
    old = fmt_scale(j["old"]["scale"]) if j["type"] == "scale" else fmt_mode(j["old"]["mode"])
    pid = j.get("watchdog_pid")
    return {"state": j["state"], "reason": j.get("reason"), "output": j["output"], "type": j["type"],
            "requested": j["requested"], "old": old, "remaining_ms": left,
            "timeout_ms": int(j["timeout"] * 1000), "acks": j["acks"], "note": j.get("note"),
            "detail": j.get("error"), "watchdog_alive": bool(pid) and proc_alive(pid, j.get("watchdog_start")),
            "parent_watch": bool(j.get("parent"))}


# ── watchdog launch ─────────────────────────────────────────────────

def watchdog_argv(j):
    return [sys.executable, "-I", os.path.abspath(__file__), "_watchdog", j["id"]]


def clean_env():
    env = {"PATH": os.environ.get("PATH", "/usr/bin:/bin"), "LANG": "C"}
    for key, value in os.environ.items():
        if key == "XDG_RUNTIME_DIR" or key.startswith(TEST_ENV_PREFIX):
            env[key] = value
    return env


def launch_watchdog(j, how):
    """Start the watchdog detached. `how` is "systemd" or "direct"; True if it was launched."""
    argv = watchdog_argv(j)
    if how == "systemd":
        # Its own cgroup, so stopping the shell's unit (or crashing Settings) cannot take it along.
        cmd = ["systemd-run", "--user", "--quiet", "--collect", "--unit=beskar-display-preview-" + j["id"][:8],
               "--description=Beskar display preview watchdog"]
        for key, value in clean_env().items():
            if key in ("XDG_RUNTIME_DIR",) or key.startswith(TEST_ENV_PREFIX):
                cmd.append("--setenv=%s=%s" % (key, value))
        try:
            return subprocess.run(cmd + ["--"] + argv, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                                  stderr=subprocess.DEVNULL, timeout=5, close_fds=True).returncode == 0
        except (OSError, subprocess.SubprocessError):
            return False
    try:
        subprocess.Popen(argv, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                         env=clean_env(), cwd="/", close_fds=True, start_new_session=True)
        return True
    except OSError:
        return False


def arm_watchdog(directory, j):
    """Launch until the watchdog acknowledges in the journal; True when it is armed."""
    mode = os.environ.get(TEST_ENV_PREFIX + "LAUNCH", "auto")
    if mode == "none":
        return False
    methods = []
    rt = os.environ.get("XDG_RUNTIME_DIR", "")
    if mode == "auto" and shutil.which("systemd-run") and os.path.exists(os.path.join(rt, "systemd", "private")):
        methods.append("systemd")
    methods.append("direct")
    for how in methods:
        if not launch_watchdog(j, how):
            continue
        end = now() + READY_WAIT
        while now() < end:
            try:
                cur = read_journal(directory)
            except Fail:
                cur = None
            if cur and cur["id"] == j["id"] and cur["acks"].get("watchdog"):
                return True
            time.sleep(0.02)
    return False


# ── commands ────────────────────────────────────────────────────────

def niri_context():
    sock = os.environ.get("NIRI_SOCKET", "")
    if not sock or not os.path.isabs(sock) or "\0" in sock:
        raise Fail("no-niri", "NIRI_SOCKET is not set: not running under niri")
    try:
        st = os.stat(sock)
    except OSError:
        raise Fail("no-niri", "the niri socket does not exist")
    if not stat.S_ISSOCK(st.st_mode) or st.st_uid != os.getuid():
        raise Fail("no-niri", "NIRI_SOCKET is not a socket of this user")
    binary = os.environ.get(TEST_ENV_PREFIX + "NIRI") or shutil.which("niri")
    if not binary or not os.path.isabs(binary) or not os.access(binary, os.X_OK):
        raise Fail("no-niri", "niri is not installed")
    return {"bin": binary, "socket": sock}


def cmd_begin(output, typ, requested, old):
    if not OUTPUT_RE.match(output):
        raise Fail("bad-output", "not an output name")
    if typ not in ("scale", "mode"):
        raise Fail("bad-type", "type must be scale or mode")
    want = parse_requested(typ, requested)
    if old != "-":
        parse_requested(typ, old)
    niri = niri_context()
    directory = state_dir(True)
    timeout = confirm_timeout()
    parent = parent_to_watch()

    with Lock(directory):
        try:
            prior = read_journal(directory)
        except Fail:
            set_aside_corrupt(directory)
            prior = None
        if prior and prior["state"] in ACTIVE:
            prior = reconcile(directory, prior)
            if prior["state"] in ACTIVE:
                raise Fail("busy", "a display change is already waiting for confirmation", state=prior["state"])
        if prior and prior["state"] == "restore-failed":
            # Never capture a half-restored display as the new "old" state.
            prior = restore(directory, prior, prior.get("reason") or "retry")
            if prior["state"] == "restore-failed":
                raise Fail("busy", "the previous display change could not be restored", state="restore-failed")
        ctx = {"niri": niri}
        try:
            outputs = niri_outputs(ctx)
        except NiriError as e:
            raise Fail("niri-query-failed", str(e))
        o = outputs.get(output)
        if not isinstance(o, dict):
            raise Fail("unknown-output", "niri has no output with that name")
        cur = describe(o)
        if typ == "mode":
            if cur["custom"]:
                raise Fail("unsupported", "the current mode is a custom mode and cannot be restored safely")
            modes = [m for m in o["modes"] if isinstance(m, dict)]
            known = [m for m in modes if m.get("width") == want["width"] and m.get("height") == want["height"]
                     and (want["refresh_rate"] is None or abs(int(m.get("refresh_rate", -1)) - want["refresh_rate"]) <= 2)]
            if not known:
                raise Fail("unsupported", "the output does not offer that mode")
            if want["refresh_rate"] is not None and mode_matches(cur["mode"], want):
                raise Fail("no-change", "the output already uses that mode")
        elif abs(cur["scale"] - want["scale"]) < 0.005:
            raise Fail("no-change", "the output already uses that scale")
        if old != "-":
            claimed = parse_requested(typ, old)
            if typ == "scale":
                stale = abs(claimed["scale"] - cur["scale"]) >= 0.005
            else:
                stale = (claimed["width"], claimed["height"]) != (cur["mode"]["width"], cur["mode"]["height"]) or (
                    claimed["refresh_rate"] is not None and abs(claimed["refresh_rate"] - cur["mode"]["refresh_rate"]) > 2)
            if stale:
                raise Fail("stale-old", "the output is not in the state the caller expected",
                           actual=fmt_scale(cur["scale"]) if typ == "scale" else fmt_mode(cur["mode"]))

        j = {"v": JOURNAL_VERSION, "id": secrets.token_hex(8), "token": secrets.token_hex(16), "state": "arming",
             "reason": None, "output": output, "type": typ,
             "requested": requested, "old": {"scale": cur["scale"], "transform": cur["transform"], "mode": cur["mode"]},
             "niri": niri, "parent": parent, "timeout": timeout, "created": now(), "deadline": None,
             "acks": {"watchdog": False, "applied": False, "kept": False, "reverted": False, "restored": False},
             "watchdog_pid": None, "watchdog_start": None, "error": None, "note": None,
             "wall_created": time.time()}
        write_journal(directory, j)
        txn_id = j["id"]

    # The watchdog takes the lock to acknowledge, so it is armed outside ours.
    armed = arm_watchdog(directory, j)

    with Lock(directory):
        try:
            j = read_journal(directory)
        except Fail:
            j = None
        if not j or j["id"] != txn_id or j["state"] != "arming":
            raise Fail("watchdog-failed", "the transaction was taken over while arming")
        if not armed or not j["acks"].get("watchdog"):
            finish(directory, j, "aborted", "watchdog-failed")
            raise Fail("watchdog-failed", "the recovery watchdog could not be started; nothing was changed")
        j["state"], j["deadline"] = "applying", now() + APPLY_GUARD
        write_journal(directory, j)
        try:
            niri_run(j, apply_args(j, want))
            time.sleep(0.05)
            after = describe(niri_outputs(j)[j["output"]])
            if not applied(j, want, after):
                raise NiriError("niri accepted the command but the output did not change")
        except (NiriError, Fail, KeyError) as e:
            message = str(e) if isinstance(e, NiriError) else "the output could not be read after the change"
            j = restore(directory, j, "apply-failed")
            raise Fail("apply-failed", message, state=j["state"], restored=j["acks"]["restored"])
        j["state"], j["deadline"] = "pending", now() + timeout
        j["acks"]["applied"] = True
        write_journal(directory, j)
        return {"token": j["token"], **public(j)}


def load_for_token(directory, token):
    if directory is None:
        raise Fail("no-transaction", "no display change is waiting")
    try:
        j = read_journal(directory)
    except Fail:
        raise Fail("no-transaction", "no display change is waiting")
    if j is None:
        raise Fail("no-transaction", "no display change is waiting")
    if not hmac.compare_digest(j["token"], token):
        raise Fail("stale-token", "that confirmation belongs to another display change")
    return j


def cmd_keep(token):
    directory = state_dir(False)
    if directory is None:
        raise Fail("no-transaction", "no display change is waiting")
    with Lock(directory):
        j = reconcile(directory, load_for_token(directory, token))
        if j["state"] == "kept":
            return {"already": True, **public(j)}
        if j["state"] == "pending":
            j["acks"]["kept"] = True
            finish(directory, j, "kept", "user")
            return public(j)
        raise Fail("reverted" if j["state"] == "reverted" else "not-pending",
                   "the display change was already put back" if j["state"] == "reverted"
                   else "the display change is not waiting for confirmation", **public(j))


def cmd_revert(token):
    directory = state_dir(False)
    if directory is None:
        raise Fail("no-transaction", "no display change is waiting")
    with Lock(directory):
        j = reconcile(directory, load_for_token(directory, token))
        if j["state"] == "reverted":
            return {"already": True, **public(j)}
        if j["state"] == "kept":
            raise Fail("already-kept", "the display change was already kept", **public(j))
        if j["state"] in ("applying", "pending", "restore-failed"):
            j = restore(directory, j, "user" if j["state"] != "restore-failed" else j.get("reason") or "user")
            if j["state"] != "reverted":
                raise Fail("restore-failed", j.get("error") or "the old value could not be restored", **public(j))
            return public(j)
        raise Fail("not-pending", "the display change is not waiting for confirmation", **public(j))


def cmd_status():
    directory = state_dir(False)
    if directory is None:
        return {"state": "idle"}
    with Lock(directory):
        try:
            j = read_journal(directory)
        except Fail:
            return {"state": "idle", "note": "corrupt-journal"}
        if j is None:
            return {"state": "idle"}
        return public(reconcile(directory, j))   # a safety net when the watchdog is gone


# ── the watchdog (internal command) ─────────────────────────────────

STOP = []


def cmd_watchdog(txn_id):
    for sig in (signal.SIGTERM, signal.SIGHUP, signal.SIGINT):
        signal.signal(sig, lambda *_: STOP.append(1))
    directory = state_dir(False)
    if directory is None:
        return
    with Lock(directory):
        try:
            j = read_journal(directory)
        except Fail:
            return
        if not j or j["id"] != txn_id or j["state"] != "arming":
            return
        if j.get("watchdog_pid") and proc_alive(j["watchdog_pid"], j.get("watchdog_start")):
            return          # a second launch method raced the first
        info = proc_info(os.getpid())
        j["watchdog_pid"], j["watchdog_start"] = os.getpid(), info[1] if info else None
        j["acks"]["watchdog"] = True
        write_journal(directory, j)

    failed_rounds = 0
    while True:
        stopping = bool(STOP)
        time.sleep(0 if stopping else TICK)
        try:
            j = read_journal(directory)
        except Fail:
            return
        if not j or j["id"] != txn_id:
            return
        if j["state"] == "restore-failed":
            if failed_rounds >= WATCHDOG_ROUNDS or stopping:
                return
            failed_rounds += 1
            time.sleep(4 * retry_gap())
            with Lock(directory):
                j = read_journal(directory)
                if j and j["id"] == txn_id and j["state"] == "restore-failed":
                    restore(directory, j, j.get("reason") or "timeout")
            continue
        if j["state"] not in ACTIVE:
            return
        if stopping or overdue_reason(j):
            with Lock(directory):
                j = read_journal(directory)
                if not j or j["id"] != txn_id or j["state"] not in ACTIVE:
                    continue
                if stopping and j["state"] in ("applying", "pending"):
                    restore(directory, j, "signal")
                elif stopping:
                    finish(directory, j, "aborted", "signal")
                else:
                    reconcile(directory, j)
            if stopping:
                return


# ── entry point ─────────────────────────────────────────────────────

USAGE = ("usage: display-preview.py begin OUTPUT scale|mode REQUESTED OLD|-  |  keep TOKEN  |  "
         "revert TOKEN  |  status")


def emit(payload, ok):
    sys.stdout.write(json.dumps({"ok": ok, **payload}, sort_keys=True) + "\n")
    sys.stdout.flush()


def main(argv):
    try:
        for a in argv:
            if len(a) > 200 or "\0" in a or "\n" in a or "\r" in a:
                raise Fail("usage", USAGE)
        cmd, rest = (argv[0], argv[1:]) if argv else ("", [])
        if cmd == "begin" and len(rest) == 4:
            result = cmd_begin(*rest)
        elif cmd in ("keep", "revert") and len(rest) == 1:
            if not TOKEN_RE.match(rest[0]):
                raise Fail("stale-token", "not a confirmation token")
            result = (cmd_keep if cmd == "keep" else cmd_revert)(rest[0])
        elif cmd == "status" and not rest:
            result = cmd_status()
        elif cmd == "_watchdog" and len(rest) == 1 and ID_RE.match(rest[0]):
            cmd_watchdog(rest[0])
            return 0
        else:
            raise Fail("usage", USAGE)
        emit(result, True)
        return 0
    except Fail as e:
        emit({**e.extra, "error": e.code, "message": e.message}, False)
        return 2 if e.code == "usage" else 1
    except Exception as e:  # never a traceback on the caller's stdout
        emit({"error": "internal", "message": type(e).__name__}, False)
        return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
