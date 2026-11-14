"""Exercise the actual Luau provider against fd, using only a temporary filesystem."""
from pathlib import Path
import os
import subprocess
import tempfile
import time


ADAPTER = r'''
package.path = "shell/?.luau;" .. package.path
local scheduled, rows
sys = { ask = function(what) if what == "env" then return arg[1] end end }
function after(_, fn) scheduled = fn; return fn end
function cancel() scheduled = nil end
function run(command, args, reply)
    local function quote(value) return "'" .. value:gsub("'", "'\\''") .. "'" end
    local words = { quote(command) }
    for _, value in ipairs(args) do words[#words + 1] = quote(value) end
    local child = assert(io.popen(table.concat(words, " ") .. " 2>/dev/null", "r"))
    local output = child:read("*a")
    local ok, _, code = child:close()
    reply(output, ok and 0 or (code or -1))
end
local provider = require("spotlight_files").new(function(value) rows = value end)
provider.update("/ " .. arg[2], true)
if scheduled then scheduled() end
for _, row in ipairs(rows or {}) do if row.path then io.write(row.path, "\0") end end
'''


def results(root, query, env=None):
    output = subprocess.check_output(
        ["lua", "-", str(root), query], input=ADAPTER.encode(), env=env, timeout=6
    )
    return [Path(os.fsdecode(value)) for value in output.split(b"\0") if value]


with tempfile.TemporaryDirectory(prefix="beskar file search '") as temporary:
    base = Path(temporary)
    home = base / "home"
    home.mkdir()
    for parent in ("Documents", "Work", "node_modules", "target", "build", ".hidden"):
        folder = home / parent
        folder.mkdir()
        (folder / "report.txt").write_text("fixture")
    (home / "report folder").mkdir()
    (home / ".fdignore").write_text("ignored*\n")
    (home / "ignored-report.txt").write_text("fixture")
    found = results(home, "report")
    assert set(found) == {
        home / "Documents/report.txt", home / "Work/report.txt", home / "report folder"
    }, found

    literal = home / "cost $100 [draft] 'v2'.txt"
    literal.write_text("fixture")
    assert results(home, "[draft]") == [literal]
    assert results(home, "cost $100 [draft] 'v2'") == [literal]
    line_break = home / "line\nwith\rbreak.txt"
    line_break.write_text("fixture")
    assert results(home, "line") == [line_break]
    option = home / "--hidden.txt"
    option.write_text("fixture")
    assert results(home, "--hidden") == [option]
    assert results(home, "Documents/report") == [home / "Documents/report.txt"]

    outside = base / "outside"
    outside.mkdir()
    (outside / "symlink-target-secret.txt").write_text("fixture")
    (home / "linked-folder").symlink_to(outside, target_is_directory=True)
    assert not results(home, "symlink-target-secret")
    deep = home
    for _ in range(9):
        deep = deep / "level"
        deep.mkdir()
    (deep / "beyond-depth-limit.txt").write_text("fixture")
    assert not results(home, "beyond-depth-limit")

    for index in range(40):
        (home / f"overflow-{index:02d}.txt").write_text("fixture")
    assert len(results(home, "overflow")) == 24

    # A stalled backend still terminates and retains only complete NUL-delimited paths.
    fake_bin = base / "fake-bin"
    fake_bin.mkdir()
    fake_fd = fake_bin / "fd"
    fake_fd.write_text('#!/bin/sh\nprintf "%s\\0" "$BESKAR_TEST_FILE_RESULT"\nsleep 4\n')
    fake_fd.chmod(0o755)
    env = dict(os.environ, PATH=str(fake_bin) + ":" + os.environ["PATH"], BESKAR_TEST_FILE_RESULT=str(literal))
    started = time.monotonic()
    assert results(home, "stalled", env) == [literal]
    assert 1.5 < time.monotonic() - started < 4

print("Spotlight file backend: 11 filesystem checks passed")
