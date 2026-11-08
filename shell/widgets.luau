-- Desktop widgets: logic. The cards live in CARDS (this file is the only writer of ~/.config/beskar/widgets.json);
-- `model.ws` is what the scene draws. Feeds (weather, system, calendar) run only while a card needs them.
--
--   card = { id, out = "HDMI-A-1", kind, sz (0 small · 1 medium · 2 large), x, y }
--   kinds: 1 clock · 2 date · 3 weather · 4 battery · 5 system · 6 media · 7 month calendar

local clockfmt = require("clockfmt")
local locate = require("location")

local UNIT, GAP = 160, 16
local GRID = 16
local TOP_SAFE, SIDE_SAFE = 40, 12     -- the frame's ring and top bar

local KINDS = {
    { id = 1, name = "Clock",    icon = "󰥔", sizes = { 0, 1, 2 }, def = 1 },
    { id = 2, name = "Date",     icon = "󰃭", sizes = { 0, 1 },    def = 0 },
    { id = 3, name = "Weather",  icon = "󰖙", sizes = { 0, 1, 2 }, def = 0 },
    { id = 4, name = "Battery",  icon = "󰁹", sizes = { 0, 1 },    def = 0 },
    { id = 5, name = "System",   icon = "󰍹", sizes = { 0, 1, 2 }, def = 1 },
    { id = 6, name = "Music",    icon = "󰎆", sizes = { 1 },       def = 1 },
    { id = 7, name = "Calendar", icon = "󰸗", sizes = { 2 },       def = 2 },
    { id = 8, name = "Day",      icon = "󰔟", sizes = { 0, 1 },    def = 0 },
    { id = 9, name = "Controls", icon = "󰕾", sizes = { 1 },       def = 1 },
}
local function kind_of(id)
    return KINDS[id]
end

local function say(scene, cmd)
    pcall(sys.call, "say", scene, cmd)
end
local function sh(script, cb, ...)
    run("sh", { "-c", script, "x", ... }, cb, cb == nil and { output = false } or nil)
end

-- ── which copy of the scene is on which monitor (pleamar logs it at start; see topbar.luau) ──
local OUTPUTS = {}          -- index (1-based) → name
local SIZES = {}            -- name → { w, h } logical
local CARDS = {}
local NEXT_ID = 1
local HISTORY = {}
local loaded = false

local function width_of(sz) return sz == 0 and UNIT or (UNIT * 2 + GAP) end
local function height_of(sz) return sz == 2 and (UNIT * 2 + GAP) or UNIT end

local function index_of(out)
    for i, n in ipairs(OUTPUTS) do
        if n == out then return i - 1 end
    end
    return -1
end

local function push()
    local recs = {}
    for _, c in ipairs(CARDS) do
        local scr = index_of(c.out)
        if scr >= 0 and #recs < 16 then
            recs[#recs + 1] = { id = c.id, scr = scr, kind = c.kind, sz = c.sz, x = c.x, y = c.y }
        end
    end
    model.ws = recs
end

local have = {}             -- kind → true while some card shows it (feeds follow this)
local start_feeds           -- defined below

-- ── saving (debounced, atomic) ──
local save_timer = nil
local function save_now()
    local list = {}
    for _, c in ipairs(CARDS) do
        list[#list + 1] = { id = c.id, out = c.out, kind = c.kind, sz = c.sz, x = c.x, y = c.y }
    end
    local j = json.encode({ version = 1, snap = fact.snap_on and true or false, next = NEXT_ID, cards = list })
    sh('mkdir -p "$HOME/.config/beskar" && printf "%s\\n" "$1" > "$HOME/.config/beskar/widgets.json.tmp" && mv "$HOME/.config/beskar/widgets.json.tmp" "$HOME/.config/beskar/widgets.json"', nil, j)
end
local function save()
    if save_timer then cancel(save_timer) end
    save_timer = after(400, function() save_timer = nil; save_now() end)
end

local function snapshot()
    local copy = {}
    for _, c in ipairs(CARDS) do
        copy[#copy + 1] = { id = c.id, out = c.out, kind = c.kind, sz = c.sz, x = c.x, y = c.y }
    end
    HISTORY[#HISTORY + 1] = copy
    if #HISTORY > 20 then table.remove(HISTORY, 1) end
    fact.can_undo = #HISTORY > 0
end

local function changed()
    push()
    start_feeds()
    save()
end

-- ── placing ──
local function snap(v)
    if fact.snap_on then
        return math.floor(v / GRID + 0.5) * GRID
    end
    return math.floor(v + 0.5)
end

local function clamp_card(c)
    local sz = SIZES[c.out]
    local w, h = width_of(c.sz), height_of(c.sz)
    local maxx = (sz and sz[1] or 1920) - w - SIDE_SAFE
    local maxy = (sz and sz[2] or 1080) - h - SIDE_SAFE - 60
    c.x = math.max(SIDE_SAFE, math.min(c.x, maxx))
    c.y = math.max(TOP_SAFE, math.min(c.y, maxy))
end

local function overlaps(c, x, y, w, h)
    local cw, ch = width_of(c.sz), height_of(c.sz)
    return x < c.x + cw and x + w > c.x and y < c.y + ch and y + h > c.y
end

local function free_spot(out, sz)
    local w, h = width_of(sz), height_of(sz)
    local screen = SIZES[out] or { 1920, 1080 }
    local y = 48
    while y + h < screen[2] - 80 do
        local x = 48
        while x + w < screen[1] - 20 do
            local hit = false
            for _, c in ipairs(CARDS) do
                if c.out == out and overlaps(c, x - GAP / 2, y - GAP / 2, w + GAP, h + GAP) then
                    hit = true
                    break
                end
            end
            if not hit then return x, y end
            x = x + GRID * 2
        end
        y = y + GRID * 2
    end
    return 48, 48
end

local function add_card(out, kind, sz, x, y)
    local k = kind_of(kind)
    if not k then return end
    local size = sz or k.def
    local cx, cy = x, y
    if not cx then cx, cy = free_spot(out, size) end
    CARDS[#CARDS + 1] = { id = NEXT_ID, out = out, kind = kind, sz = size, x = cx, y = cy }
    NEXT_ID = NEXT_ID + 1
end

local function defaults()
    CARDS = {}
    for _, out in ipairs(OUTPUTS) do
        add_card(out, 1, 1, 48, 72)
        add_card(out, 3, 0, 48, 248)
        add_card(out, 5, 0, 224, 248)
    end
end

-- ── presets: whole desktops in one click (applied to every monitor) ──
local PRESETS = {
    { name = "Glance",    cards = { { 1, 1, 48, 72 }, { 3, 0, 48, 248 }, { 4, 0, 224, 248 } } },
    { name = "Dashboard", cards = { { 1, 1, 48, 72 }, { 2, 0, 400, 72 }, { 3, 0, 576, 72 }, { 5, 2, 48, 248 }, { 7, 2, 400, 248 } } },
    { name = "Focus",     cards = { { 1, 2, 48, 72 }, { 2, 0, 400, 72 } } },
    { name = "Listening", cards = { { 6, 1, 48, 72 }, { 1, 0, 400, 72 }, { 3, 0, 576, 72 } } },
    { name = "Bare",      cards = {} },
}
on("w_preset", function(n)
    local p = PRESETS[tonumber(n) or 0]
    if not p then return end
    snapshot()
    CARDS = {}
    for _, out in ipairs(OUTPUTS) do
        for _, c in ipairs(p.cards) do add_card(out, c[1], c[2], c[3], c[4]) end
    end
    for _, c in ipairs(CARDS) do clamp_card(c) end
    changed()
end)
model.presets = (function()
    local r = {}
    for i, p in ipairs(PRESETS) do r[#r + 1] = { id = i, name = p.name } end
    return r
end)()

-- ── edit mode ──
local function set_editing(on)
    fact.editing = on
    if on then
        HISTORY = {}
        fact.can_undo = false
    else
        save_now()
    end
end

local function find(id)
    for i, c in ipairs(CARDS) do
        if c.id == id then return c, i end
    end
end

on("edit_toggle", function() set_editing(not fact.editing) end)
on("edit_done", function() set_editing(false) end)

on("w_drop", function(id)
    local c = find(id)
    local dx, dy = tonumber(fact.drag_dx) or 0, tonumber(fact.drag_dy) or 0
    if c and (math.abs(dx) > 2 or math.abs(dy) > 2) then
        snapshot()
        c.x, c.y = snap(c.x + dx), snap(c.y + dy)
        clamp_card(c)
        push()
        save()
    end
    fact.drag_id = 0
    fact.drag_dx = 0
    fact.drag_dy = 0
end)

on("w_add", function(code)
    local scr, kind = math.floor(code / 100), code % 100
    local out = OUTPUTS[scr + 1] or OUTPUTS[1]
    if not out or #CARDS >= 16 then return end
    snapshot()
    add_card(out, kind)
    changed()
end)

on("w_remove", function(id)
    local c, i = find(id)
    if not c then return end
    snapshot()
    table.remove(CARDS, i)
    changed()
end)

on("w_resize", function(id)
    local c = find(id)
    if not c then return end
    local k = kind_of(c.kind)
    if #k.sizes < 2 then return end
    snapshot()
    local at = 1
    for i, s in ipairs(k.sizes) do
        if s == c.sz then at = i end
    end
    c.sz = k.sizes[at % #k.sizes + 1]
    clamp_card(c)
    changed()
end)

on("w_undo", function()
    local last = table.remove(HISTORY)
    if not last then return end
    CARDS = last
    fact.can_undo = #HISTORY > 0
    changed()
end)

on("w_reset", function()
    snapshot()
    defaults()
    changed()
end)

on("w_grid", function()
    fact.snap_on = not fact.snap_on
    save()
end)

on("w_open", function(kind)
    if fact.editing then return end
    if kind == 1 or kind == 2 or kind == 3 or kind == 5 or kind == 7 then
        say("topbar", "emit open_dashboard")
    end
end)

-- ── media ──
local playing = false
sys.watch("media", function(m)
    m = m or {}
    local title = m.title or ""
    playing = m.playing == true
    fact.has_player = (m.player or "") ~= "" or title ~= ""
    fact.is_playing = playing
    text.track_title = title ~= "" and title or "Unknown title"
    text.track_artist = m.artist or ""
    text.cover_art = m.art or ""
end)
on("w_vol", function(v) sys.call("audio.volume", v) end)
on("w_bri", function(v) sys.call("brightness.level", math.max(0.05, tonumber(v) or 1)) end)
on("w_play", function() sys.call("media.toggle") end)
on("w_next", function() sys.call("media.next") end)
on("w_prev", function() sys.call("media.previous") end)

-- ── clock, date, calendar ──
local last_day = ""
local function paint_clock()
    local t = clockfmt(fact.hour12)
    local time, ampm = t:match("^(%d+:%d+)%s*(%a*)$")
    text.w_time = time or t
    text.w_ampm = ampm or ""
    local hh, mm, ss = tonumber(os.date("%H")), tonumber(os.date("%M")), tonumber(os.date("%S"))
    local used = hh * 3600 + mm * 60 + ss
    fact.day_pct = math.floor(used * 100 / 86400)
    local left = 86400 - used
    text.day_left = string.format("%dh %dm left", math.floor(left / 3600), math.floor(left % 3600 / 60))
    local day = os.date("%Y-%m-%d")
    if day ~= last_day then
        last_day = day
        text.w_month = os.date("%B"):upper()
        text.w_day = tostring(tonumber(os.date("%d")))
        text.w_dow = os.date("%A")
        text.w_datelong = os.date("%A, %B ") .. tonumber(os.date("%d"))
        -- the month grid, weeks start on Monday
        text.cal_title = os.date("%B %Y")
        local now = os.time()
        local y, m, d = tonumber(os.date("%Y", now)), tonumber(os.date("%m", now)), tonumber(os.date("%d", now))
        local first = os.time({ year = y, month = m, day = 1, hour = 12 })
        local wd = (tonumber(os.date("%w", first)) + 6) % 7      -- Monday = 0
        for k = 0, 41 do
            local t2 = os.time({ year = y, month = m, day = 1 - wd + k, hour = 12 })
            local dm = tonumber(os.date("%m", t2))
            text["cd." .. k] = tostring(tonumber(os.date("%d", t2)))
            local kind = 0
            if dm ~= m then kind = 1 elseif tonumber(os.date("%d", t2)) == d then kind = 2 end
            fact["cm." .. k] = kind
        end
    end
end
paint_clock()
every(15000, paint_clock)
on("fact:hour12", paint_clock)

-- ── weather ──
local function icon_for(code)
    if code == 0 then return "󰖙"
    elseif code <= 3 then return "󰖐"
    elseif code == 45 or code == 48 then return "󰖑"
    elseif (code >= 51 and code <= 67) or (code >= 80 and code <= 82) then return "󰖗"
    elseif (code >= 71 and code <= 77) or code == 85 or code == 86 then return "󰖘"
    elseif code >= 95 then return "󰙾" end
    return "󰖐"
end
local function words_for(code)
    if code == 0 then return "Clear"
    elseif code <= 2 then return "Partly Cloudy"
    elseif code == 3 then return "Overcast"
    elseif code == 45 or code == 48 then return "Fog"
    elseif code >= 51 and code <= 57 then return "Drizzle"
    elseif (code >= 61 and code <= 67) or (code >= 80 and code <= 82) then return "Rain"
    elseif (code >= 71 and code <= 77) or code == 85 or code == 86 then return "Snow"
    elseif code >= 95 then return "Thunderstorm" end
    return "Cloudy"
end
local function refresh_weather()
    locate(function(place)
        if not place then return end
        text.weather_city = place.city
        local url = string.format(
            "https://api.open-meteo.com/v1/forecast?latitude=%s&longitude=%s&current=temperature_2m,weather_code&daily=temperature_2m_max,temperature_2m_min&timezone=auto&forecast_days=1",
            place.lat, place.lon)
        run("curl", { "-fsS", "--max-time", "6", url }, function(out, code)
            if code ~= 0 or not out then return end
            local ok, d = pcall(json.decode, out)
            local cur = ok and type(d) == "table" and d.current
            if type(cur) ~= "table" or cur.temperature_2m == nil then return end
            local wc = cur.weather_code or 0
            text.weather_temp = string.format("%d°", math.floor(cur.temperature_2m + 0.5))
            text.weather_cond = words_for(wc)
            text.weather_icon = icon_for(wc)
            local day = d.daily
            if type(day) == "table" and day.temperature_2m_max and day.temperature_2m_min then
                text.weather_range = string.format("H %d°  L %d°",
                    math.floor(day.temperature_2m_max[1] + 0.5), math.floor(day.temperature_2m_min[1] + 0.5))
            end
        end)
    end)
end

-- ── system ──
local STATS = [[
a=$(awk '/^cpu /{print $2+$3+$4+$5+$6+$7+$8, $5+$6}' /proc/stat); sleep 0.4
b=$(awk '/^cpu /{print $2+$3+$4+$5+$6+$7+$8, $5+$6}' /proc/stat)
echo "$a $b" | awk '{d=$3-$1; i=$4-$2; print (d>0) ? int((d-i)*100/d+0.5) : 0}'
awk '/MemTotal/{t=$2} /MemAvailable/{a=$2} END{print int((t-a)*100/t+0.5)}' /proc/meminfo
df / | awk 'NR==2{gsub("%","",$5); print $5}'
awk '{s=int($1); d=int(s/86400); h=int((s%86400)/3600); m=int((s%3600)/60); if (d>0) printf "%dd %dh %dm\n", d, h, m; else printf "%dh %dm\n", h, m}' /proc/uptime
]]
local stats_busy = false
local function refresh_stats()
    if stats_busy then return end
    stats_busy = true
    run("sh", { "-c", STATS }, function(out, code)
        stats_busy = false
        if code ~= 0 or not out then return end
        local l = {}
        for line in out:gmatch("[^\r\n]+") do l[#l + 1] = line end
        if #l >= 3 then
            fact.cpu_pct = math.min(100, tonumber(l[1]) or 0)
            fact.mem_pct = math.min(100, tonumber(l[2]) or 0)
            fact.disk_pct = math.min(100, tonumber(l[3]) or 0)
        end
        if l[4] then text.up_text = l[4] end
    end)
end

-- Feeds follow the cards: a timer exists only while something on a desktop uses it.
local timers = {}
function start_feeds()
    have = {}
    for _, c in ipairs(CARDS) do
        if index_of(c.out) >= 0 then have[c.kind] = true end
    end
    if have[3] and not timers.weather then
        refresh_weather()
        timers.weather = every(15 * 60000, refresh_weather)
    elseif not have[3] and timers.weather then
        cancel(timers.weather)
        timers.weather = nil
    end
    if have[5] and not timers.stats then
        refresh_stats()
        timers.stats = every(3000, refresh_stats)
    elseif not have[5] and timers.stats then
        cancel(timers.stats)
        timers.stats = nil
    end
end

-- ── start: screens, outputs, then the saved layout ──
local function load_layout()
    sh('cat "$HOME/.config/beskar/widgets.json" 2>/dev/null', function(out)
        local ok, d = pcall(json.decode, out or "")
        CARDS = {}
        if ok and type(d) == "table" and type(d.cards) == "table" then
            for _, c in ipairs(d.cards) do
                if kind_of(tonumber(c.kind) or 0) then
                    CARDS[#CARDS + 1] = { id = tonumber(c.id) or 0, out = c.out, kind = tonumber(c.kind), sz = tonumber(c.sz) or 0,
                        x = tonumber(c.x) or 48, y = tonumber(c.y) or 72 }
                end
            end
            NEXT_ID = tonumber(d.next) or (#CARDS + 1)
            if d.snap == false then fact.snap_on = false end
        else
            defaults()
        end
        loaded = true
        for _, c in ipairs(CARDS) do clamp_card(c) end
        changed()
    end)
end

local function learn(tries)
    sh("grep 'surface [0-9]* on' /tmp/pleamar_widgets.log 2>/dev/null | head -8", function(out)
        local map = {}
        for idx, name in (out or ""):gmatch("surface (%d+) on (%S+)") do
            map[tonumber(idx) + 1] = name
        end
        if #map > 0 then
            OUTPUTS = map
            fact.nscreens = #map
            sh("niri msg -j outputs 2>/dev/null", function(o)
                local ok, d = pcall(json.decode, o or "")
                if ok and type(d) == "table" then
                    for name, info in pairs(d) do
                        local lm = info.logical
                        if lm then SIZES[name] = { lm.width, lm.height } end
                    end
                end
                if loaded then changed() else load_layout() end
            end)
        elseif tries > 0 then
            after(2000, function() learn(tries - 1) end)
        else
            OUTPUTS = { "eDP-1" }
            load_layout()
        end
    end)
end
model.kinds = (function()
    local r = {}
    for _, k in ipairs(KINDS) do r[#r + 1] = { id = k.id, name = k.name, icon = k.icon } end
    return r
end)()
after(1200, function() learn(8) end)
