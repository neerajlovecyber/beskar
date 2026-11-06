-- Wallpaper picker logic. Like Marea's: the folders are scanned, small copies are made once and cached,
-- and the picture is painted by a daemon that outlives the shell (here `awww`, with a transition).
--
--   Mine      ~/Pictures/wallpapers, ~/Pictures/Wallpapers, ~/Wallpapers, and the pictures directly in ~/Pictures
--   Built-in  the ones Beskar ships (copied to ~/.local/share/beskar/wallpapers by start.sh), /usr/share/wallpapers,
--             /usr/share/backgrounds
--
-- The choice is remembered in ~/.config/beskar/wallpaper, which start.sh puts back at login.

local COLS, ROWS = 4, 3
local PAGE = COLS * ROWS

local all = {}              -- { path, name, builtin }, in the order shown by "All"
local view = {}             -- what the current tab shows
local row = 0               -- first row on screen
local current = nil         -- path on now
local HOME = ""
local CACHE = ""
local thumb_of = {}         -- path -> thumbnail path
local state = {}            -- path -> "making" | "ready"

-- ── names and paths ──────────────────────────────────────────────
local function pretty(path)
    local name = path:match("([^/]+)$") or path
    name = name:gsub("%.[%w]+$", ""):gsub("[_%-]+", " ")
    if #name > 40 then
        name = name:sub(1, 38) .. "…"
    end
    return name
end

local function hash(str)
    local h = 5381
    for i = 1, #str do
        h = (h * 33 + str:byte(i)) % 4294967296
    end
    return string.format("%08x", h)
end

-- ── painting ─────────────────────────────────────────────────────
local paint

local function make_thumb(path)
    if state[path] then
        return
    end
    state[path] = "making"
    local thumb = thumb_of[path]
    local script = 'mkdir -p "$1" && { [ -f "$2" ] || magick -define jpeg:size=704x396 "$3" -thumbnail 352x198^ -gravity center -extent 352x198 -quality 80 "$2"; }'
    run("sh", { "-c", script, "x", CACHE, thumb, path }, function(_, code)
        if code == 0 then
            state[path] = "ready"
            paint()
        else
            state[path] = nil
        end
    end)
end

paint = function()
    local first = row * COLS + 1
    local rows = {}
    for i = first, math.min(#view, first + PAGE - 1) do
        local w = view[i]
        thumb_of[w.path] = thumb_of[w.path] or (CACHE .. "/" .. hash(w.path) .. ".jpg")
        make_thumb(w.path)
        rows[#rows + 1] = {
            name = w.name,
            thumb = thumb_of[w.path],
            ready = state[w.path] == "ready",
            current = w.path == current,
            builtin = w.builtin,
        }
    end
    model.walls = rows
    fact.wall_total = #view
    fact.wall_row = row
    fact.wall_rows = math.max(1, math.ceil(#view / COLS))
    text.wall_hint = string.format("%d pictures", #view)
end

local function rebuild(tab)
    view = {}
    for _, w in ipairs(all) do
        if tab == 0 or (tab == 1 and not w.builtin) or (tab == 2 and w.builtin) then
            view[#view + 1] = w
        end
    end
    row = 0
    paint()
end

local function show_current_row()
    for i, w in ipairs(view) do
        if w.path == current then
            row = math.min(math.floor((i - 1) / COLS), math.max(0, math.ceil(#view / COLS) - ROWS))
            return
        end
    end
end

-- ── what is on now ───────────────────────────────────────────────
local function read_current(then_)
    run("sh", { "-c", "awww query 2>/dev/null | head -1" }, function(out)
        local p = out and out:match("image: ([^\n]+)")
        if p and p ~= "" then
            current = p
        end
        if then_ then
            then_()
        end
    end)
end

-- ── scanning ─────────────────────────────────────────────────────
local SCAN = [[
H="$HOME"
img() { fd -t f -e jpg -e jpeg -e png -e webp -S +120k "$@" 2>/dev/null; }
for d in "$H/Pictures/wallpapers" "$H/Pictures/Wallpapers" "$H/Wallpapers" "$H/Imágenes/Wallpapers"; do
    [ -d "$d" ] && img --max-depth 3 . "$d" | sed 's/^/1|/'
done
[ -d "$H/Pictures" ] && img --max-depth 1 . "$H/Pictures" | sed 's/^/1|/'
for d in "$H/.local/share/beskar/wallpapers" /usr/share/wallpapers /usr/share/backgrounds; do
    [ -d "$d" ] && img --max-depth 3 . "$d" | sed 's/^/2|/'
done
printf 'HOME|%s\n' "$H"
]]

local scanning = false
local function scan()
    if scanning then
        return
    end
    scanning = true
    run("sh", { "-c", SCAN }, function(out, code)
        scanning = false
        if code ~= 0 or not out then
            return
        end
        local mine, built, seen = {}, {}, {}
        for line in out:gmatch("[^\n]+") do
            local kind, path = line:match("^(%w+)|(.+)$")
            if kind == "HOME" then
                HOME = path
                CACHE = HOME .. "/.cache/beskar/wallpapers"
            elseif path and not seen[path] then
                seen[path] = true
                local entry = { path = path, name = pretty(path), builtin = kind == "2" }
                if kind == "2" then
                    built[#built + 1] = entry
                else
                    mine[#mine + 1] = entry
                end
            end
        end
        local function by_name(a, b) return a.name:lower() < b.name:lower() end
        table.sort(mine, by_name)
        table.sort(built, by_name)
        all = {}
        for _, e in ipairs(mine) do all[#all + 1] = e end
        for _, e in ipairs(built) do all[#all + 1] = e end
        read_current(function()
            rebuild(tonumber(fact.wall_tab) or 0)
            show_current_row()
            paint()
        end)
    end)
end

-- ── the accent that goes with a picture ─────────────────────────
-- Take the most colourful of the picture's main colours and map its hue to the nearest of Beskar's
-- accents (0 blue · 1 purple · 2 pink · 3 red · 4 orange · 5 green · 6 graphite for greys).
local function accent_index(r, g, b)
    r, g, b = r / 255, g / 255, b / 255
    local mx, mn = math.max(r, g, b), math.min(r, g, b)
    local d = mx - mn
    local s = mx == 0 and 0 or d / mx
    if s < 0.18 or d == 0 then
        return 6, s, mx
    end
    local h
    if mx == r then h = ((g - b) / d) % 6 elseif mx == g then h = (b - r) / d + 2 else h = (r - g) / d + 4 end
    h = h * 60
    local idx
    if h < 15 or h >= 345 then idx = 3
    elseif h < 70 then idx = 4
    elseif h < 170 then idx = 5
    elseif h < 255 then idx = 0
    elseif h < 300 then idx = 1
    else idx = 2 end
    return idx, s, mx
end

local function accent_from(path)
    run("magick", { path, "-resize", "120x120", "-colors", "8", "-format", "%c", "histogram:info:-" }, function(out, code)
        if code ~= 0 or not out then
            return
        end
        local best, best_score = 6, -1
        for line in out:gmatch("[^\n]+") do
            local count, hex = line:match("(%d+):.-#(%x%x%x%x%x%x)")
            if count then
                local r, g, b = tonumber(hex:sub(1, 2), 16), tonumber(hex:sub(3, 4), 16), tonumber(hex:sub(5, 6), 16)
                local idx, sat, val = accent_index(r, g, b)
                local lively = (val > 0.28 and val < 0.97) and 1 or 0.25
                local score = tonumber(count) * sat * sat * lively
                if score > best_score then
                    best, best_score = idx, score
                end
            end
        end
        pcall(sys.call, "say", "settings", "emit auto_accent " .. best)
    end)
end

on("accent_now", function()
    if current then
        accent_from(current)
    end
end)

-- ── buttons ──────────────────────────────────────────────────────
on("wall_tab_set", function(n)
    fact.wall_tab = tonumber(n) or 0
    rebuild(fact.wall_tab)
end)

on("wall_scroll", function(wheel)
    local rows = math.max(1, math.ceil(#view / COLS))
    local max_row = math.max(0, rows - ROWS)
    local step = (tonumber(wheel) or 0) > 0 and -1 or 1
    local nxt = math.max(0, math.min(max_row, row + step))
    if nxt ~= row then
        row = nxt
        paint()
    end
end)

on("wall_pick", function(i)
    local w = view[row * COLS + (tonumber(i) or 0) + 1]
    if not w then
        return
    end
    current = w.path
    paint()
    local script = [[
pgrep -x awww-daemon >/dev/null || { setsid awww-daemon </dev/null >/dev/null 2>&1 & sleep 0.4; }
awww img "$1" --transition-type grow --transition-pos 0.85,0.1 --transition-duration 1.4 --transition-fps 60
mkdir -p "$HOME/.config/beskar" && printf '%s\n' "$1" > "$HOME/.config/beskar/wallpaper"
]]
    run("sh", { "-c", script, "x", w.path }, function(_, code)
        if code ~= 0 then
            log("wallpaper · awww failed for", w.path)
        end
    end)
    if fact.accent_auto == true then
        accent_from(w.path)
    end
end)

-- Opening the picker looks again (a new picture in the folder shows up) and lands on the one in use.
on("fact:open", function(v)
    if v == true or v == 1 then
        scan()
    end
end)

scan()
require("exclusive")("wallpapers")
