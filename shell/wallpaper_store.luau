-- Wallpaper backend helpers (pure: no surface, no timer, no watcher, no service). Two users:
--
--   wallpaper.luau   the RENDERER. It validates every `text wp_new` itself before it touches the picture it shows, so a
--                    bad path from anywhere (the picker, `--say`, a stale file) can never blank the desktop.
--   dockpanels.luau  the PICKER. `require("wallpaper_store")` and use `check` / `commit` / `restore` / `status` below
--                    instead of writing ~/.config/beskar/wallpaper by hand. The picker still owns the favourites
--                    (the `fav_*` functions only compute lists: it keeps the file) and the intent of the click.
--
-- Files (all in ~/.config/beskar, one path per line, written atomically by `commit` / `restore`):
--   wallpaper            what is shown now (unchanged contract: start.sh, lock.luau and settings.luau read it)
--   wallpaper.previous   what was shown before the last change (for "restore previous")
--
-- Why a command validates and not the renderer: pleamar paints `image x = from some_text` and never says whether the
-- file loaded (no loaded / failed signal exists in 0.8.0-exp.16), and a failed one draws nothing, so promoting it to the
-- visible picture would leave a bare dark box. The only safe contract is: prove the file is a readable, supported,
-- fully decodable picture BEFORE its path reaches `wp_b_path` / `wp_a_path`. `sh` is already allowed in both scenes.
--
-- Every helper takes the `run` function (the sandbox's global `run`; tests pass a fake) and a callback that gets ONE
-- result table:  { ok = true,  path, size = "1920x1080" | "?", source }   or   { ok = false, code, message }
-- codes: bad_path missing not_file unreadable too_large unsupported corrupt too_big no_previous write_failed none
-- unknown. `message` is short English for a toast; branch on `code`.

local M = {}

M.MAX_PATH = 4096
M.MAX_FAVOURITES = 48
M.MAX_BYTES = 134217728 -- 128 MiB file
M.MAX_SIDE = 16384 -- pixels on a side
M.MAX_PIXELS = 100000000 -- 100 MP (decoding it needs about 600 MB: the script limits ImageMagick's memory too)
M.FX = { circle = 0, fade = 1, wipe = 2 } -- the wp_fx enum Settings owns
M.EXTENSIONS = { jpg = "jpeg", jpeg = "jpeg", png = "png", webp = "webp" }

-- ── paths ────────────────────────────────────────────────────────────

-- What a `text` or a file line gives, without the whitespace at either end (a path starts with "/" and ends with an
-- extension, so neither end can legitimately be blank).
function M.clean_path(raw)
    if type(raw) ~= "string" then
        return ""
    end
    return (raw:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- true, or false + code + message. Syntax only (no disk): absolute, bounded, no control characters (a path is ONE line
-- of the current-wallpaper file and one field of the helper's output), no `..` component, a supported extension.
function M.valid_path(path)
    if type(path) ~= "string" or path == "" then
        return false, "bad_path", "No picture chosen"
    end
    if #path > M.MAX_PATH then
        return false, "bad_path", "Path is too long"
    end
    if path:sub(1, 1) ~= "/" then
        return false, "bad_path", "Path must be absolute"
    end
    if path:find("%c") then
        return false, "bad_path", "Path has control characters"
    end
    if path:find("/%.%./", 1) or path:find("/%.%.$") then
        return false, "bad_path", "Path must not contain .."
    end
    local ext = path:match("%.([%w]+)$")
    if not ext or not M.EXTENSIONS[ext:lower()] then
        return false, "unsupported", "Only JPEG, PNG and WebP pictures"
    end
    return true
end

function M.pretty(path)
    local name = tostring(path or ""):match("([^/]+)$") or tostring(path or "")
    name = name:gsub("%.[%w]+$", ""):gsub("[_%-]+", " ")
    if #name > 40 then
        name = name:sub(1, 38) .. "…"
    end
    return name
end

-- ── transition ───────────────────────────────────────────────────────

-- wp_fx as the renderer understands it: 0 circle, 1 fade, 2 wipe. Anything else is the circle.
function M.clamp_fx(n)
    n = tonumber(n)
    if n == 0 or n == 1 or n == 2 then
        return n
    end
    return 0
end

-- Reads `"wallpaper_fx": N` out of prefs.json text (the whole file or the line). nil when absent or out of range, so a
-- missing preference never overrides what Settings already said.
function M.parse_fx(text)
    local n = tostring(text or ""):match('"wallpaper_fx"%s*:%s*(%-?%d+)')
    n = tonumber(n)
    if n == 0 or n == 1 or n == 2 then
        return n
    end
    return nil
end

-- ── the validation / persistence script (POSIX sh, run as `sh -c SCRIPT wallpaper-store MODE ARGS…`) ─────────────
-- Paths only ever travel as positional arguments (never interpolated into the script text) and the script never
-- `eval`s anything. It always exits 0 and answers on stdout:
--   check PATH       ok<TAB>PATH<TAB>WxH        | err<TAB>code<TAB>message          full validation (decodes it)
--   commit PATH      the same, and on success: wallpaper.previous <- old wallpaper, wallpaper <- PATH (atomic)
--   restore          the same for the previous picture; on success the two files swap (restoring twice toggles)
--   status P1 P2 …   one line per path: ok<TAB>PATH | <code><TAB>PATH      cheap (no decode): for favourites
--   boot             ok<TAB>PATH<TAB>WxH<TAB>current|previous|bundled | err<TAB>none<TAB>…  first usable picture
--   prefs            the first 64 KiB of ~/.config/beskar/prefs.json (the renderer reads wallpaper_fx from it)
-- Validation = regular readable file, ≤128 MiB, content sniffed (JPEG / PNG / WebP) and agreeing with the extension
-- (a decoder that picks the format by extension must not be handed a mismatch), exactly one frame (no animation:
-- it would repaint for ever), ≤16384 px a side and ≤100 MP, and (with ImageMagick) a real decode inside 20 s that does not report a cut-off file.
-- Without `magick` the checks stop at the content sniff and the size reads "?".
M.SCRIPT = [=[
CFG="${HOME:-/nonexistent}/.config/beskar"
MAXB=134217728
MAXSIDE=16384
MAXPX=100000000
mode=$1
[ $# -gt 0 ] && shift
ecode=""
emsg=""
dims="?"

tmo() { if command -v timeout >/dev/null 2>&1; then timeout "$@"; else shift; "$@"; fi; }

bad() { ecode=$1; emsg=$2; return 1; }

# $1 path, $2 full|light. 0 = fine (dims set), 1 = not (ecode / emsg set).
inspect() {
  f=$1
  dims="?"
  case $f in /*) ;; *) bad bad_path "Path must be absolute"; return 1;; esac
  case $f in *[[:cntrl:]]*) bad bad_path "Path has control characters"; return 1;; esac
  [ -e "$f" ] || { bad missing "The picture is not there any more"; return 1; }
  [ -f "$f" ] || { bad not_file "That is not a picture file"; return 1; }
  [ -r "$f" ] || { bad unreadable "The picture cannot be read"; return 1; }
  size=$(wc -c < "$f" 2>/dev/null | tr -d ' ')
  case $size in ''|*[!0-9]*) bad unreadable "The picture cannot be read"; return 1;; esac
  [ "$size" -gt 0 ] || { bad corrupt "The picture is empty"; return 1; }
  [ "$size" -le "$MAXB" ] || { bad too_large "The picture is bigger than 128 MB"; return 1; }
  hex=$(head -c 12 -- "$f" 2>/dev/null | od -An -tx1 | tr -d ' \n')
  coder=""
  case $hex in
    ffd8ff*) coder=jpeg;;
    89504e470d0a1a0a*) coder=png;;
    52494646????????57454250) coder=webp;;
  esac
  [ -n "$coder" ] || { bad unsupported "Only JPEG, PNG and WebP pictures"; return 1; }
  low=$(printf '%s' "$f" | tr 'A-Z' 'a-z')
  want=""
  case $low in *.jpg|*.jpeg) want=jpeg;; *.png) want=png;; *.webp) want=webp;; esac
  [ "$want" = "$coder" ] || { bad unsupported "Only JPEG, PNG and WebP pictures"; return 1; }
  [ "$2" = full ] || return 0
  command -v magick >/dev/null 2>&1 || return 0
  out=$(tmo 10 magick identify -ping -format '%w %h\n' "$coder:-" < "$f" 2>/dev/null) || { bad corrupt "The picture is damaged"; return 1; }
  frames=$(printf '%s\n' "$out" | grep -c .)
  [ "$frames" -eq 1 ] || { if [ "$frames" -gt 1 ]; then bad unsupported "Animated pictures are not supported"; else bad corrupt "The picture is damaged"; fi; return 1; }
  set -- $out
  case "$1$2" in ''|*[!0-9]*) bad corrupt "The picture is damaged"; return 1;; esac
  { [ "$1" -ge 1 ] && [ "$2" -ge 1 ]; } || { bad corrupt "The picture is damaged"; return 1; }
  if [ "$1" -gt "$MAXSIDE" ] || [ "$2" -gt "$MAXSIDE" ] || [ $(( $1 * $2 )) -gt "$MAXPX" ]; then
    bad too_big "The picture is too large (limit 100 megapixels)"; return 1
  fi
  dims="$1x$2"
  err=$(tmo 20 magick -limit memory 1GiB -limit map 1GiB -limit disk 2GiB "$coder:-" null: < "$f" 2>&1 >/dev/null) || { bad corrupt "The picture is damaged"; return 1; }
  # a cut-off JPEG only warns (exit 0) and would paint half a picture: harmless warnings (colour profiles) still pass
  case $err in *[Pp]remature*|*[Tt]runcated*|*[Cc]orrupt*|*[Ii]nsufficient*|*nexpected*) bad corrupt "The picture is damaged"; return 1;; esac
  return 0
}

fail() { printf 'err\t%s\t%s\n' "$ecode" "$emsg"; exit 0; }

# first line of a file, without CR or trailing blanks ("" if absent)
line_of() { [ -f "$1" ] && head -n 1 -- "$1" 2>/dev/null | tr -d '\r' | sed 's/[[:space:]]*$//'; }

# $1 file, $2 text: a temporary file in the same folder, then rename. A symlinked file (dotfiles) keeps its link.
atomic_write() {
  tgt=$1
  if [ -L "$tgt" ]; then r=$(readlink -f -- "$tgt" 2>/dev/null); [ -n "$r" ] && tgt=$r; fi
  d=$(dirname -- "$tgt")
  mkdir -p -- "$d" 2>/dev/null || return 1
  t=$(mktemp "$d/.wallpaper.XXXXXX" 2>/dev/null) || return 1
  if printf '%s\n' "$2" > "$t" 2>/dev/null && mv -f -- "$t" "$tgt" 2>/dev/null; then return 0; fi
  rm -f -- "$t" 2>/dev/null
  return 1
}

case $mode in
  check)
    [ $# -ge 1 ] || { bad bad_path "No picture chosen"; fail; }
    inspect "$1" full || fail
    printf 'ok\t%s\t%s\n' "$1" "$dims"
    ;;
  commit)
    [ $# -ge 1 ] || { bad bad_path "No picture chosen"; fail; }
    inspect "$1" full || fail
    cur=$(line_of "$CFG/wallpaper")
    if [ "$cur" != "$1" ]; then
      if [ -n "$cur" ]; then atomic_write "$CFG/wallpaper.previous" "$cur" || { bad write_failed "Could not save the choice"; fail; }; fi
      atomic_write "$CFG/wallpaper" "$1" || { bad write_failed "Could not save the choice"; fail; }
    fi
    printf 'ok\t%s\t%s\n' "$1" "$dims"
    ;;
  restore)
    prev=$(line_of "$CFG/wallpaper.previous")
    [ -n "$prev" ] || { bad no_previous "There is no previous wallpaper"; fail; }
    inspect "$prev" full || fail
    cur=$(line_of "$CFG/wallpaper")
    atomic_write "$CFG/wallpaper" "$prev" || { bad write_failed "Could not save the choice"; fail; }
    if [ -n "$cur" ] && [ "$cur" != "$prev" ]; then atomic_write "$CFG/wallpaper.previous" "$cur"; fi
    printf 'ok\t%s\t%s\n' "$prev" "$dims"
    ;;
  status)
    cnt=0
    for p in "$@"; do
      cnt=$((cnt + 1))
      [ "$cnt" -le 64 ] || break
      if inspect "$p" light; then printf 'ok\t%s\n' "$p"; else printf '%s\t%s\n' "$ecode" "$p"; fi
    done
    ;;
  boot)
    for src in current previous bundled; do
      case $src in
        current) cand=$(line_of "$CFG/wallpaper");;
        previous) cand=$(line_of "$CFG/wallpaper.previous");;
        bundled) cand=$(ls -1 "${HOME:-/nonexistent}"/.local/share/beskar/wallpapers/*.jpg 2>/dev/null | head -n 1);;
      esac
      [ -n "$cand" ] || continue
      if inspect "$cand" full; then printf 'ok\t%s\t%s\t%s\n' "$cand" "$dims" "$src"; exit 0; fi
    done
    bad none "No usable wallpaper"; fail
    ;;
  prefs)
    head -c 65536 "$CFG/prefs.json" 2>/dev/null
    ;;
  *)
    bad unknown "Unknown request"; fail
    ;;
esac
exit 0
]=]

-- ── running it ───────────────────────────────────────────────────────

local function split_tabs(line)
    local out, from = {}, 1
    while true do
        local at = line:find("\t", from, true)
        if not at then
            out[#out + 1] = line:sub(from)
            return out
        end
        out[#out + 1] = line:sub(from, at - 1)
        from = at + 1
    end
end

-- The answer of check / commit / restore / boot → the result table.
function M.parse_result(out)
    local line = tostring(out or ""):match("^([^\n]*)") or ""
    local f = split_tabs(line)
    if f[1] == "ok" and f[2] and f[2] ~= "" then
        return { ok = true, path = f[2], size = f[3] ~= "" and f[3] or "?", source = f[4] }
    elseif f[1] == "err" then
        return { ok = false, code = (f[2] and f[2] ~= "") and f[2] or "unknown", message = f[3] or "" }
    end
    return { ok = false, code = "unknown", message = "The wallpaper check did not answer" }
end

-- The answer of `status` → { [path] = "ok" | code }.
function M.parse_status(out)
    local map = {}
    for line in tostring(out or ""):gmatch("[^\n]+") do
        local f = split_tabs(line)
        if f[1] and f[2] and f[2] ~= "" then
            map[f[2]] = f[1]
        end
    end
    return map
end

-- The arguments for `run("sh", args, cb)`: for a caller that wants to spawn it itself.
function M.argv(mode, ...)
    return { "-c", M.SCRIPT, "wallpaper-store", mode, ... }
end

local function call(runner, mode, cb, ...)
    runner = runner or run
    local args = M.argv(mode, ...)
    runner("sh", args, function(out)
        if cb then
            cb(M.parse_result(out))
        end
    end)
end

local function rejected(cb, code, message)
    if cb then
        cb({ ok = false, code = code, message = message })
    end
end

-- Full validation, nothing written. cb({ ok, path, size } | { ok = false, code, message }).
function M.check(runner, path, cb)
    path = M.clean_path(path)
    local ok, code, message = M.valid_path(path)
    if not ok then
        return rejected(cb, code, message)
    end
    call(runner, "check", cb, path)
end

-- Validate, then remember it (previous <- current, current <- path, atomic). The picker says `text wp_new PATH` to the
-- wallpaper scene only when ok. On any failure NOTHING was changed.
function M.commit(runner, path, cb)
    path = M.clean_path(path)
    local ok, code, message = M.valid_path(path)
    if not ok then
        return rejected(cb, code, message)
    end
    call(runner, "commit", cb, path)
end

-- Go back to the previous wallpaper (the two files swap). On ok, `result.path` is what to show: say it as `wp_new`.
function M.restore(runner, cb)
    call(runner, "restore", cb)
end

-- The first usable picture: current, else previous, else the first one Beskar ships. Writes nothing.
function M.boot(runner, cb)
    call(runner, "boot", cb)
end

-- Cheap check (no decode) of a list of paths, for favourites that may have gone away. At most 48 are asked.
-- cb({ [path] = "ok" | "missing" | "unreadable" | "not_file" | "unsupported" | "corrupt" | … }). A path that was not
-- valid syntactically is answered "bad_path" without running anything.
function M.status(runner, paths, cb)
    runner = runner or run
    local asked, map = {}, {}
    for _, p in ipairs(paths or {}) do
        if #asked >= M.MAX_FAVOURITES then
            break
        end
        if M.valid_path(p) then
            asked[#asked + 1] = p
        else
            map[tostring(p)] = "bad_path"
        end
    end
    if #asked == 0 then
        if cb then
            cb(map)
        end
        return
    end
    runner("sh", M.argv("status", table.unpack(asked)), function(out)
        local got = M.parse_status(out)
        for _, p in ipairs(asked) do
            map[p] = got[p] or "unknown"
        end
        if cb then
            cb(map)
        end
    end)
end

-- The wallpaper_fx saved by Settings, or nil. cb(n | nil)
function M.read_fx(runner, cb)
    runner = runner or run
    runner("sh", M.argv("prefs"), function(out)
        if cb then
            cb(M.parse_fx(out))
        end
    end)
end

-- ── favourites (pure list algebra: the PICKER keeps the file and decides when to save) ───────────────────────────
-- A list is an array of absolute paths, most recent first, at most 48, no duplicates. Suggested file in the picker
-- scene's own files folder: "wallpaper-favourites.json", saved with sys.call("files.write", name, M.fav_encode(list)).

function M.fav_normalize(list)
    local out, seen = {}, {}
    if type(list) ~= "table" then
        return out
    end
    for _, item in ipairs(list) do
        local p = type(item) == "table" and item.path or item
        p = M.clean_path(p)
        if not seen[p] and M.valid_path(p) then
            seen[p] = true
            out[#out + 1] = p
            if #out >= M.MAX_FAVOURITES then
                break
            end
        end
    end
    return out
end

function M.fav_has(list, path)
    for _, p in ipairs(list or {}) do
        if p == path then
            return true
        end
    end
    return false
end

-- → new list, "added" | "exists" | "full" | "invalid"   (never silently evicts: a full list says so)
function M.fav_add(list, path)
    path = M.clean_path(path)
    list = M.fav_normalize(list)
    if not M.valid_path(path) then
        return list, "invalid"
    end
    if M.fav_has(list, path) then
        return list, "exists"
    end
    if #list >= M.MAX_FAVOURITES then
        return list, "full"
    end
    table.insert(list, 1, path)
    return list, "added"
end

-- → new list, "removed" | "missing"   (works for a path that no longer exists on disk: the point of removing)
function M.fav_remove(list, path)
    local out, found = {}, false
    for _, p in ipairs(M.fav_normalize(list)) do
        if p == path then
            found = true
        else
            out[#out + 1] = p
        end
    end
    return out, found and "removed" or "missing"
end

-- → new list, "added" | "removed" | "full" | "invalid"
function M.fav_toggle(list, path)
    path = M.clean_path(path)
    if M.fav_has(list, path) then
        local out = M.fav_remove(list, path)
        return out, "removed"
    end
    return M.fav_add(list, path)
end

-- What to write with files.write (a table is saved as JSON) / what files.read(.., "json") gives back (any garbage →
-- an empty list, so a hand-edited or broken file never throws in the picker).
function M.fav_encode(list)
    return { version = 1, favourites = M.fav_normalize(list) }
end

function M.fav_decode(data)
    if type(data) ~= "table" then
        return {}
    end
    if type(data.favourites) == "table" then
        return M.fav_normalize(data.favourites)
    end
    return M.fav_normalize(data)
end

-- Favourites joined to a `status` map → rows { path, name, available, state } in list order. A favourite that is gone
-- stays in the list (shown "unavailable", removable) rather than vanishing.
function M.fav_rows(list, statuses)
    local rows = {}
    for _, p in ipairs(M.fav_normalize(list)) do
        local state = (statuses and statuses[p]) or "unknown"
        rows[#rows + 1] = { path = p, name = M.pretty(p), available = state == "ok", state = state }
    end
    return rows
end

return M
