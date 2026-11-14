-- The dock's single atomic writer; runner is injected for the sandbox and tests.
local M = {}
local SCRIPT = [=[
set -eu
umask 077
d="$HOME/.config/beskar"
mkdir -p "$d"
p="$d/dock"
expect="$2"
e=$(mktemp "$p.expect.XXXXXX")
trap 'rm -f "$e" "${t:-}"' EXIT HUP INT TERM
if [ "$expect" = missing ]; then [ ! -e "$p" ] && [ ! -L "$p" ] || exit 3
elif [ "$expect" = body ]; then printf '%s' "$3" > "$e"; cmp -s "$p" "$e" || exit 3; fi
if [ -e "$p" ]; then [ -f "$p" ] && [ -r "$p" ] || exit 4; cp -p -- "$p" "$p.bak"; fi
if [ "$1" = default ]; then rm -f -- "$p"; exit; fi
shift 3
t=$(mktemp "$p.tmp.XXXXXX")
: > "$t"
for id in "$@"; do printf '%s\n' "$id" >> "$t"; done
mv -f -- "$t" "$p"
]=]
function M.read(runner, cb)
    runner("sh", { "-c", 'p="$HOME/.config/beskar/dock"; if [ ! -e "$p" ] && [ ! -L "$p" ]; then exit 3; fi; [ -f "$p" ] && [ -r "$p" ] || exit 4; [ "$(wc -c < "$p")" -le 65536 ] || exit 4; cat "$p" && printf "\\n\\036"', "pins-read" }, function(out, code)
        if code == 3 then cb(true, nil); return end
        if code ~= 0 or type(out) ~= "string" or out:sub(-2) ~= "\n\30" then cb(false, nil, "unreadable"); return end
        cb(true, out:sub(1,-3))
    end)
end
function M.write(runner, data, cb, expected)
    local mode = expected == nil and "any" or (expected.missing and "missing" or "body")
    local args = { "-c", SCRIPT, "pins-store", data.default and "default" or "list", mode, expected and expected.body or "" }
    for _, id in ipairs(data.list or {}) do args[#args+1] = id end
    runner("sh", args, function(out, code) cb(code == 0, code == 3 and "stale" or (code == 4 and "unreadable" or "io"), out) end)
end
return M
