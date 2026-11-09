-- Wallpaper picker logic. Like Marea's: the folders are scanned, small copies are made once and cached,
-- and the picture is painted by the wallpaper scene (wallpaper.plm), with a transition.
--
--   Mine      ~/Pictures/wallpapers, ~/Pictures/Wallpapers, ~/Wallpapers (never the rest of ~/Pictures, and never
--             files named screenshot / mock)
--   Built-in  the ones Beskar ships (copied to ~/.local/share/beskar/wallpapers by start.sh), /usr/share/wallpapers,
--             /usr/share/backgrounds
--
-- The choice is remembered in ~/.config/beskar/wallpaper, which start.sh puts back at login.

local PAGE = 5                  -- pictures on screen, in one row
local panel = require("panel")("wallpapers")
panel.height(250)               -- the strip's height, for the frame's glass

local all = {}              -- { path, name, builtin }, in the order shown by "All"
local view = {}             -- what the current tab shows
local row = 0               -- the first picture on screen (0-based)
local cur = 0               -- the picture the keyboard cursor is on (0-based, in `view`)
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
    local first = row + 1
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
            sel = (first + #rows) == cur + 1,
        }
    end
    model.walls = rows
    fact.wall_total = #view
    fact.wall_row = row
    fact.wall_rows = math.max(1, #view - PAGE + 1)
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
    cur = 0
    paint()
end

local function show_current_row()
    for i, w in ipairs(view) do
        if w.path == current then
            row = math.max(0, math.min(i - 3, #view - PAGE))      -- the one in use, about the middle
            cur = i - 1
            return
        end
    end
end

-- ── what is on now ───────────────────────────────────────────────
local function read_current(then_)
    run("sh", { "-c", 'cat "$HOME/.config/beskar/wallpaper" 2>/dev/null | head -1' }, function(out)
        local p = (out or ""):gsub("%s+$", "")
        if p ~= "" then
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
img() { fd -t f -e jpg -e jpeg -e png -e webp -S +120k -E "*[Ss]creenshot*" -E "*[Ss]creen_[Ss]hot*" -E "*mock*" "$@" 2>/dev/null; }
for d in "$H/Pictures/wallpapers" "$H/Pictures/Wallpapers" "$H/Wallpapers" "$H/Imágenes/Wallpapers"; do
    [ -d "$d" ] && img --max-depth 3 . "$d" | sed 's/^/1|/'
done
[ -d "$H/.local/share/beskar/wallpapers" ] && img --max-depth 2 . "$H/.local/share/beskar/wallpapers" | sed 's/^/2|/'
for d in /usr/share/wallpapers /usr/share/backgrounds; do
    [ -d "$d" ] && img --max-depth 3 . "$d" | sed 's/^/3|/'
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
        local mine, built, system, seen = {}, {}, {}, {}
        for line in out:gmatch("[^\n]+") do
            local kind, path = line:match("^(%w+)|(.+)$")
            if kind == "HOME" then
                HOME = path
                CACHE = HOME .. "/.cache/beskar/wallpapers"
            elseif path and not seen[path] then
                seen[path] = true
                local entry = { path = path, name = pretty(path), builtin = kind ~= "1" }
                if kind == "2" then
                    built[#built + 1] = entry
                elseif kind == "3" then
                    system[#system + 1] = entry
                else
                    mine[#mine + 1] = entry
                end
            end
        end
        local function by_name(a, b) return a.name:lower() < b.name:lower() end
        table.sort(mine, by_name)
        table.sort(built, by_name)
        table.sort(system, by_name)
        all = {}
        for _, e in ipairs(mine) do all[#all + 1] = e end
        for _, e in ipairs(built) do all[#all + 1] = e end      -- Beskar's own first
        for _, e in ipairs(system) do all[#all + 1] = e end     -- then the system's
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

-- The palette engine lives in settings.luau (matugen on the wallpaper, sent to every scene).
local function accent_from(path)
    pcall(sys.call, "say", "settings", "text pal_src " .. path)
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
    local max_off = math.max(0, #view - PAGE)
    local step = (tonumber(wheel) or 0) > 0 and -1 or 1
    local nxt = math.max(0, math.min(max_off, row + step))
    if nxt ~= row then
        row = nxt
        paint()
    end
end)

local function apply(w)
    if not w then
        return
    end
    current = w.path
    paint()
    -- Remember it (start.sh and the lock screen read this file) and let the wallpaper scene reveal it.
    run("sh", { "-c", 'mkdir -p "$HOME/.config/beskar" && printf "%s\\n" "$1" > "$HOME/.config/beskar/wallpaper"', "x", w.path }, nil, { output = false })
    pcall(sys.call, "say", "wallpaper", "text wp_new " .. w.path)
    if fact.accent_auto == true then
        accent_from(w.path)
    end
end

on("wall_pick", function(i)
    local idx = row + (tonumber(i) or 0)
    cur = idx
    apply(view[idx + 1])
end)

-- Arrows (on screen or on the keyboard). Left / Right move the cursor one picture and scroll to keep it in view;
-- the arrow buttons turn a whole page; Enter applies the picture under the cursor.
local function keep_in_view()
    local max_off = math.max(0, #view - PAGE)
    if cur < row then
        row = cur
    elseif cur >= row + PAGE then
        row = cur - PAGE + 1
    end
    row = math.max(0, math.min(max_off, row))
end

on("wall_move", function(d)
    if #view < 1 then
        return
    end
    cur = math.max(0, math.min(#view - 1, cur + (tonumber(d) or 0)))
    keep_in_view()
    paint()
end)

on("wall_page", function(d)
    if #view < 1 then
        return
    end
    local max_off = math.max(0, #view - PAGE)
    row = math.max(0, math.min(max_off, row + (tonumber(d) or 0) * PAGE))
    cur = math.max(row, math.min(row + PAGE - 1, cur + (tonumber(d) or 0) * PAGE))
    cur = math.max(0, math.min(#view - 1, cur))
    paint()
end)

on("wall_enter", function()
    apply(view[cur + 1])
end)

-- Opening the picker looks again (a new picture in the folder shows up) and lands on the one in use.
on("fact:open", function(v)
    if v == true or v == 1 then
        scan()
    end
end)

scan()
require("exclusive")("wallpapers")
