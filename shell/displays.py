#!/usr/bin/env python3
"""Display settings the user KEPT in Settings → Displays, so they survive a restart.

    displays.py save OUTPUT scale|mode VALUE     record one kept setting (atomic write of ~/.config/beskar/displays.json)
    displays.py restore                          apply every recorded setting to the outputs niri has now (start.sh, at login)

Values are validated against fixed grammars and passed to `niri msg output` as separate arguments (never through a shell).
An output that is not connected is skipped; a value niri refuses is reported on stderr and the rest still apply.
"""
import json, os, re, subprocess, sys, tempfile

PATH = os.path.expanduser("~/.config/beskar/displays.json")
NAME = re.compile(r"^[A-Za-z0-9_.:+-]{1,64}$")
VALUE = {"scale": re.compile(r"^\d(\.\d{1,3})?$"), "mode": re.compile(r"^\d{3,5}x\d{3,5}(@\d{1,3}(\.\d{1,3})?)?$")}

def load():
    try:
        with open(PATH) as f:
            d = json.load(f)
        return d if isinstance(d, dict) else {}
    except Exception:
        return {}

def save(name, kind, value):
    if not NAME.match(name) or kind not in VALUE or not VALUE[kind].match(value):
        print("refused", file=sys.stderr); return 1
    d = load()
    entry = d.get(name) if isinstance(d.get(name), dict) else {}
    entry[kind] = value
    d[name] = entry
    os.makedirs(os.path.dirname(PATH), exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(PATH), prefix=".displays.")
    with os.fdopen(fd, "w") as f:
        json.dump(d, f, indent=1, sort_keys=True)
    os.replace(tmp, PATH)
    return 0

def restore():
    try:
        outs = json.loads(subprocess.run(["niri", "msg", "-j", "outputs"], capture_output=True, text=True, timeout=5).stdout or "{}")
    except Exception:
        return 0
    for name, entry in load().items():
        if name not in outs or not isinstance(entry, dict) or not NAME.match(name):
            continue
        for kind in ("mode", "scale"):          # mode first: a scale is checked against the mode's size
            value = entry.get(kind)
            if isinstance(value, str) and VALUE[kind].match(value):
                r = subprocess.run(["niri", "msg", "output", name, kind, value], capture_output=True, text=True, timeout=5)
                if r.returncode != 0:
                    print(f"displays: {name} {kind} {value}: {r.stderr.strip()}", file=sys.stderr)
    return 0

if __name__ == "__main__":
    a = sys.argv[1:]
    if a[:1] == ["save"] and len(a) == 4:
        sys.exit(save(a[1], a[2], a[3]))
    if a == ["restore"]:
        sys.exit(restore())
    print(__doc__, file=sys.stderr); sys.exit(2)
