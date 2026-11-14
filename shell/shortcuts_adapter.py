#!/usr/bin/env python3
"""Filesystem and niri effects for shell/shortcuts.luau. No KDL logic lives here.

Every command takes plain argv (no shell is ever involved) and answers with an exit code:

  read PATH                      0 text + "\n\x1e" on stdout | 3 missing | 4 unreadable | 5 too large
                                 (the end marker lets the caller tell the exact text from output a runtime trimmed)
  real PATH                      0 canonical path on stdout
  write PATH TEXT --absent       0 | 5 too large | 6 changed on disk | 7 refused | 8 I/O error
  write PATH TEXT --expect OLD   same; compare-and-swap: PATH must hold exactly OLD (or not exist for --absent)
  remove PATH --expect OLD       0 | 6 | 7 | 8   (only to undo a file the caller created)
  validate CONFIG                0 valid | 1 invalid (message on stdout) | 127 niri missing | 124 timed out
  reload                         0 | 1 (message on stdout)

Writes are refused unless the basename is one of OWNED (Beskar-owned includes), whatever the caller asks.
`write` keeps PATH + ".beskar-bak" (the previous text), writes a temp file next to PATH, fsyncs, renames it over PATH
(through a symlink to its target, so dotfile managers keep working) and fsyncs the directory.

niri is `niri` unless BESKAR_NIRI names another executable (tests use a fake; nothing else reads that variable).
"""
import os
import re
import subprocess
import sys
import tempfile

OWNED = {"beskar-shortcuts.kdl", "beskar.kdl"}
MAX_READ = 1024 * 1024
MAX_WRITE = 100000
ANSI = re.compile(r"\x1b\[[0-9;]*[A-Za-z]")


def out(text):
    sys.stdout.buffer.write(text.encode("utf-8"))
    sys.stdout.flush()


def read_text(path):
    """-> (text | None, code): 0 ok, 3 missing, 4 unreadable, 5 too large."""
    try:
        if not os.path.exists(path):
            return None, 3
        if not os.path.isfile(path):
            return None, 4
        if os.path.getsize(path) > MAX_READ:
            return None, 5
        with open(path, "rb") as handle:
            data = handle.read(MAX_READ + 1)
        if len(data) > MAX_READ:
            return None, 5
        if b"\0" in data:
            return None, 4
        return data.decode("utf-8"), 0
    except (OSError, UnicodeDecodeError):
        return None, 4


def allowed(path):
    return os.path.basename(path) in OWNED and os.path.isabs(path)


def target_of(path):
    """Write through a symlink to its target; never replace the link itself."""
    return os.path.realpath(path) if os.path.islink(path) else path


def matches(path, mode, expect):
    current, code = read_text(path)
    if mode == "--absent":
        return code == 3
    return code == 0 and current == expect


def fsync_dir(path):
    try:
        fd = os.open(path, os.O_RDONLY)
        try:
            os.fsync(fd)
        finally:
            os.close(fd)
    except OSError:
        pass


def atomic_write(path, text, mode_bits):
    directory = os.path.dirname(path)
    fd, temp = tempfile.mkstemp(prefix=os.path.basename(path) + ".tmp.", dir=directory)
    try:
        with os.fdopen(fd, "wb") as handle:
            handle.write(text.encode("utf-8"))
            handle.flush()
            os.fsync(handle.fileno())
        os.chmod(temp, mode_bits)
        os.replace(temp, path)
    except BaseException:
        try:
            os.unlink(temp)
        except OSError:
            pass
        raise
    fsync_dir(directory)


def cmd_write(argv):
    if len(argv) < 4:
        return 8
    path, text, mode = argv[1], argv[2], argv[3]
    if mode not in ("--absent", "--expect") or not allowed(path):
        return 7
    if mode == "--expect" and len(argv) < 5:
        return 8
    expect = argv[4] if mode == "--expect" else None
    if len(text.encode("utf-8")) > MAX_WRITE:
        return 5
    path = target_of(path)
    if not allowed(path):
        return 7
    try:
        if not matches(path, mode, expect):
            return 6
        mode_bits = 0o644
        if os.path.exists(path):
            mode_bits = os.stat(path).st_mode & 0o7777
            previous, code = read_text(path)
            if code == 0 and previous != text:
                atomic_write(path + ".beskar-bak", previous, mode_bits)
        else:
            os.makedirs(os.path.dirname(path), exist_ok=True)
        atomic_write(path, text, mode_bits)
        return 0
    except OSError:
        return 8


def cmd_remove(argv):
    if len(argv) < 4 or argv[2] != "--expect":
        return 8
    path, expect = argv[1], argv[3]
    if not allowed(path):
        return 7
    path = target_of(path)
    try:
        if not matches(path, "--expect", expect):
            return 6
        os.unlink(path)
        fsync_dir(os.path.dirname(path))
        return 0
    except OSError:
        return 8


def niri():
    return os.environ.get("BESKAR_NIRI") or "niri"


def run_niri(args, timeout):
    env = dict(os.environ, NO_COLOR="1")
    try:
        done = subprocess.run([niri()] + args, capture_output=True, text=True, timeout=timeout, env=env, check=False)
    except FileNotFoundError:
        return 127, "niri is not installed"
    except subprocess.TimeoutExpired:
        return 124, "niri did not answer in time"
    text = ANSI.sub("", (done.stdout or "") + (done.stderr or ""))
    lines = [line for line in text.splitlines() if " DEBUG " not in line and " INFO " not in line]
    return done.returncode, "\n".join(lines).strip()[-2000:]


def main(argv):
    if not argv:
        return 2
    cmd = argv[0]
    if cmd == "read" and len(argv) == 2:
        text, code = read_text(argv[1])
        if code == 0:
            out(text + "\n\x1e")
        return code
    if cmd == "real" and len(argv) == 2:
        out(os.path.realpath(argv[1]))
        return 0
    if cmd == "write":
        return cmd_write(argv)
    if cmd == "remove":
        return cmd_remove(argv)
    if cmd == "validate" and len(argv) == 2:
        code, message = run_niri(["validate", "-c", argv[1]], 20)
        out(message)
        return 0 if code == 0 else (code if code in (124, 127) else 1)
    if cmd == "reload" and len(argv) == 1:
        code, message = run_niri(["msg", "action", "load-config-file"], 10)
        out(message)
        return 0 if code == 0 else 1
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
