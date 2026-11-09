-- Spotlight logic. What you type decides what is listed (best first):
--   · a sum            `12*(3+4)`, `sqrt(2)`, `2^10`        → the result; Enter copies it
--   · a web prefix     `g cats`, `yt lofi`, `gh pleamar`, `w niri`, `ddg x`   → search there (xdg-open)
--   · `>` commands     `> lock`, `> shut down`, `> record`  → run it
--   · applications     by name
--   · nothing found    → "Search the web for …"
-- Every row is an entry { name, sub, kind, icon, run }; `model.hits` shows them, `launch(i)` runs the i-th.

local apps = {}
local entries = {}
local panel = require("panel")("spotlight")     -- the frame draws the glass: tell it how tall to be

local MAX_ROWS = 7

-- ── a small calculator (no loadstring in the sandbox) ───────────────────────────
local FUNCS = { sqrt = math.sqrt, abs = math.abs, round = function(x) return math.floor(x + 0.5) end,
    floor = math.floor, ceil = math.ceil, sin = math.sin, cos = math.cos, tan = math.tan,
    log = math.log, ln = math.log, exp = math.exp }
local CONSTS = { pi = math.pi, e = math.exp(1) }

local function calc(src)
    local pos = 1
    local function peek()
        pos = src:find("%S", pos) or (#src + 1)
        return src:sub(pos, pos)
    end
    local expr
    local function atom()
        local c = peek()
        if c == "(" then
            pos = pos + 1
            local v = expr()
            if peek() ~= ")" then error("(") end
            pos = pos + 1
            return v
        elseif c == "-" then
            pos = pos + 1
            return -atom()
        elseif c == "+" then
            pos = pos + 1
            return atom()
        elseif c:match("[%d%.]") then
            local s, e = src:find("^%d*%.?%d+", pos)
            if not s then s, e = src:find("^%d+", pos) end
            if not s then error("n") end
            pos = e + 1
            return tonumber(src:sub(s, e))
        elseif c:match("%a") then
            local s, e = src:find("^%a+", pos)
            local name = src:sub(s, e):lower()
            pos = e + 1
            if CONSTS[name] then return CONSTS[name] end
            local f = FUNCS[name]
            if not f or peek() ~= "(" then error("f") end
            pos = pos + 1
            local v = expr()
            if peek() ~= ")" then error("(") end
            pos = pos + 1
            return f(v)
        end
        error("x")
    end
    local function power()
        local b = atom()
        if peek() == "^" then
            pos = pos + 1
            return b ^ power()
        end
        return b
    end
    local function term()
        local v = power()
        while true do
            local c = peek()
            if c == "*" or c == "x" then pos = pos + 1; v = v * power()
            elseif c == "/" then pos = pos + 1; v = v / power()
            elseif c == "%" then pos = pos + 1; v = v % power()
            else return v end
        end
    end
    expr = function()
        local v = term()
        while true do
            local c = peek()
            if c == "+" then pos = pos + 1; v = v + term()
            elseif c == "-" then pos = pos + 1; v = v - term()
            else return v end
        end
    end
    local v = expr()
    if peek() ~= "" then error("tail") end
    return v
end

local function fmt_number(v)
    if v ~= v or v == math.huge or v == -math.huge then return nil end
    if math.abs(v) >= 1e15 or (v ~= 0 and math.abs(v) < 1e-9) then
        return string.format("%.10g", v)
    end
    local s = string.format("%.10f", v):gsub("0+$", ""):gsub("%.$", "")
    return s
end

local function try_calc(q)
    if #q < 2 or not q:find("%d") then return nil end
    if not (q:find("[%+%-%*/%^%%x]") or q:find("%a+%(")) then return nil end   -- a plain number is not a sum
    if not q:match("^[%d%.%s%+%-%*/%^%%%(%)%a]+$") then return nil end
    local ok, v = pcall(calc, q)
    if not ok or type(v) ~= "number" then return nil end
    return fmt_number(v)
end

-- ── web ──────────────────────────────────────────────────────────
local SITES = {
    g = { "Google", "https://www.google.com/search?q=%s", 1 },
    ddg = { "DuckDuckGo", "https://duckduckgo.com/?q=%s", 5 },
    yt = { "YouTube", "https://www.youtube.com/results?search_query=%s", 2 },
    gh = { "GitHub", "https://github.com/search?q=%s", 3 },
    w = { "Wikipedia", "https://en.wikipedia.org/w/index.php?search=%s", 4 },
    maps = { "Maps", "https://www.google.com/maps/search/%s", 6 },
}
-- longer names for the same sites
SITES.google = SITES.g
SITES.youtube = SITES.yt
SITES.github = SITES.gh
SITES.wiki = SITES.w
SITES.wikipedia = SITES.w
SITES.duckduckgo = SITES.ddg

local HOMES = {
    g = "https://www.google.com", ddg = "https://duckduckgo.com", yt = "https://www.youtube.com",
    gh = "https://github.com", w = "https://en.wikipedia.org", maps = "https://www.google.com/maps",
}

local function urlencode(s)
    return (s:gsub("[^%w%-%._~]", function(c) return string.format("%%%02X", c:byte()) end))
end

local function open_url(url)
    run("xdg-open", { url }, nil, { output = false })
end

local function web_entry(site_key, term)
    local site = SITES[site_key]
    return {
        name = "Search " .. site[1] .. " for “" .. term .. "”", sub = site[1], kind = 2, icon = "󰖟", site = site[3],
        run = function() open_url(string.format(site[2], urlencode(term))) end,
    }
end

-- ── commands ─────────────────────────────────────────────────────
local function say(scene, words)
    pcall(sys.call, "say", scene, words)
end

local function parse_timer_spec(s)
    local raw = s:lower():gsub("%s+", "")
    if raw == "" then return nil end
    if raw:match("^%d+$") then
        local m = tonumber(raw)
        if m and m > 0 then
            return m * 60, string.format("%d min", m)
        end
    end
    local h, m = raw:match("^(%d+)h(%d+)m?$")
    if h and m then
        local nh, nm = tonumber(h), tonumber(m)
        if nh and nm then
            return nh * 3600 + nm * 60, string.format("%dh %dm", nh, nm)
        end
    end
    local only_h = raw:match("^(%d+)h$")
    if only_h then
        local nh = tonumber(only_h)
        if nh and nh > 0 then return nh * 3600, string.format("%d hour", nh) end
    end
    local only_m = raw:match("^(%d+)m$")
    if only_m then
        local nm = tonumber(only_m)
        if nm and nm > 0 then return nm * 60, string.format("%d min", nm) end
    end
    local only_s = raw:match("^(%d+)s$")
    if only_s then
        local ns = tonumber(only_s)
        if ns and ns > 0 then return ns, string.format("%d sec", ns) end
    end
    local hours = tonumber(raw:match("(%d+)h")) or 0
    local mins = tonumber(raw:match("(%d+)m")) or 0
    local secs = tonumber(raw:match("(%d+)s")) or 0
    if hours > 0 or mins > 0 or secs > 0 then
        local total = hours * 3600 + mins * 60 + secs
        local parts = {}
        if hours > 0 then parts[#parts + 1] = hours .. "h" end
        if mins > 0 then parts[#parts + 1] = mins .. "m" end
        if secs > 0 then parts[#parts + 1] = secs .. "s" end
        return total, table.concat(parts, " ")
    end
    return nil
end

local COMMANDS = {
    { "Timer 5 min", "timer 5", function() say("topbar", "emit timer_start 300") end },
    { "Timer 10 min", "timer 10", function() say("topbar", "emit timer_start 600") end },
    { "Timer 25 min", "timer 25", function() say("topbar", "emit timer_start 1500") end },
    { "Lock Screen", "lock", function() say("lock", "fact locked true") end },
    { "Sleep", "suspend", function() run("systemctl", { "suspend" }, nil, { output = false }) end },
    { "Log Out…", "logout", function() say("session", "fact kind 2"); say("topbar", "emit open_panel 5") end },
    { "Restart…", "reboot", function() say("session", "fact kind 1"); say("topbar", "emit open_panel 5") end },
    { "Shut Down…", "poweroff", function() say("session", "fact kind 0"); say("topbar", "emit open_panel 5") end },
    { "Take Screenshot", "screenshot", function() say("capture", "fact mode 2"); say("capture", "fact kind 0"); say("topbar", "emit open_panel 11") end },
    { "Select Area Screenshot", "area", function() say("capture", "fact mode 0"); say("capture", "fact kind 0"); say("topbar", "emit open_panel 11") end },
    { "Record Screen", "record", function() say("capture", "fact mode 0"); say("capture", "fact kind 1"); say("topbar", "emit open_panel 11") end },
    { "Clipboard History", "clipboard", function() say("topbar", "emit open_panel 2") end },
    { "Wallpapers", "wallpapers", function() say("topbar", "emit open_panel 3") end },
    { "Edit Widgets", "widgets", function() say("widgets", "emit edit_toggle") end },
    { "Settings", "settings", function() say("topbar", "emit open_panel 4") end },
    { "Notifications", "notifications", function() say("topbar", "emit open_notifications") end },
    { "Control Center", "control", function() say("topbar", "emit open_control_center") end },
    { "Music", "music", function() say("topbar", "emit open_music") end },
    { "Window Overview", "overview", function() say("topbar", "emit open_panel 10") end },
}

-- ── the list ─────────────────────────────────────────────────────
local function paint()
    local rows = {}
    for i, e in ipairs(entries) do
        if i > MAX_ROWS then break end
        rows[i] = { name = e.name, sub = e.sub or "", kind = e.kind, site = e.site or 0, glyph = e.kind ~= 0 and e.icon or "", icon = e.kind == 0 and e.icon or "" }
    end
    model.hits = rows
    fact.sel = 0
    panel.height(94 + math.max(#rows, 1) * 44)
end

local function build()
    local raw = text.query or ""
    local q = raw:gsub("^%s+", ""):gsub("%s+$", "")
    local low = q:lower()
    entries = {}

    -- `>` commands
    if q:sub(1, 1) == ">" then
        local want = low:sub(2):gsub("^%s+", "")
        for _, c in ipairs(COMMANDS) do
            if want == "" or c[1]:lower():find(want, 1, true) or c[2]:find(want, 1, true) then
                entries[#entries + 1] = { name = c[1], sub = "Command", kind = 3, icon = "󰆍", run = c[3] }
            end
        end
        return
    end

    -- a timer countdown: `timer 7`, `timer 1h30`, `timer 25m`
    local tspec = low:match("^timer%s*(.*)$")
    if tspec and tspec ~= "" then
        local sec, desc = parse_timer_spec(tspec)
        if sec and sec > 0 then
            entries[#entries + 1] = {
                name = "Timer " .. desc,
                sub = "Start countdown · Enter to start",
                kind = 3,
                icon = "󰔛",
                run = function()
                    say("topbar", "emit timer_start " .. sec)
                end,
            }
        end
    end

    -- a sum
    local result = try_calc(q)
    if result then
        entries[#entries + 1] = {
            name = "= " .. result, sub = q .. "  ·  Enter copies", kind = 1, icon = "󰃬",
            run = function()
                run("wl-copy", { result }, nil, { output = false })
            end,
        }
    end

    -- a web prefix: `yt lofi` searches there; the prefix alone (`yt`) offers to open the site
    local key = low:match("^(%a+)%s+.+$")
    if key and SITES[key] then
        entries[#entries + 1] = web_entry(key, q:match("^%a+%s+(.+)$"))
    end
    local bare = low:match("^(%a+)$")
    if bare and SITES[bare] then
        local site = SITES[bare]
        local home = HOMES[bare] or HOMES[(bare == "google" and "g") or (bare == "youtube" and "yt") or (bare == "github" and "gh") or (bare == "wiki" and "w") or (bare == "wikipedia" and "w") or (bare == "duckduckgo" and "ddg") or "g"]
        entries[#entries + 1] = {
            name = "Search " .. site[1], sub = "type what to look for, e.g. “" .. bare .. " cats”", kind = 2, icon = "󰖟", site = site[3],
            run = function() open_url(home) end,
        }
    end

    -- applications
    local n_apps = 0
    for _, a in ipairs(apps) do
        if #entries < MAX_ROWS and (low == "" or a.name:lower():find(low, 1, true)) then
            entries[#entries + 1] = {
                name = a.name, kind = 0, icon = a.icon,
                run = function()
                    log("Spotlight: launching", a.name, "→", a.exec)
                    sys.call("apps.launch", a.exec)
                end,
            }
            n_apps = n_apps + 1
        end
    end

    -- commands, if the text names one ("lock", "record"), without the `>`
    if low ~= "" and #low >= 3 then
        for _, c in ipairs(COMMANDS) do
            if #entries < MAX_ROWS and (c[1]:lower():find(low, 1, true) or c[2]:find(low, 1, true)) then
                entries[#entries + 1] = { name = c[1], sub = "Command", kind = 3, icon = "󰆍", run = c[3] }
            end
        end
    end

    -- nothing at all: the web
    if #entries == 0 and low ~= "" then
        entries[1] = web_entry("g", q)
    end
end

local function filter()
    build()
    paint()
end

-- Watch the system apps database (.desktop files on Linux)
if not sys.watch("apps", function(list) apps = list or {}; filter() end) then
    entries = { { name = "Loading applications...", kind = 0, icon = "", run = function() end } }
    paint()
end

on("text:query", filter)

on("launch", function(i)
    local e = entries[(tonumber(i) or 0) + 1]
    fact.open = false
    if e and e.run then
        after(150, e.run)
    end
end)

-- Reset query when closed
on("fact:open", function(open)
    if not open then
        text.query = ""
        filter()
    end
end)

-- one panel at a time
require("exclusive")("spotlight")
