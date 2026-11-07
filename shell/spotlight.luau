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
    g = { "Google", "https://www.google.com/search?q=%s" },
    ddg = { "DuckDuckGo", "https://duckduckgo.com/?q=%s" },
    yt = { "YouTube", "https://www.youtube.com/results?search_query=%s" },
    gh = { "GitHub", "https://github.com/search?q=%s" },
    w = { "Wikipedia", "https://en.wikipedia.org/w/index.php?search=%s" },
    maps = { "Maps", "https://www.google.com/maps/search/%s" },
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
        name = "Search " .. site[1] .. " for “" .. term .. "”", sub = site[1], kind = 2, icon = "󰖟",
        run = function() open_url(string.format(site[2], urlencode(term))) end,
    }
end

-- ── commands ─────────────────────────────────────────────────────
local function say(scene, words)
    pcall(sys.call, "say", scene, words)
end

local COMMANDS = {
    { "Lock Screen", "lock", function() say("lock", "fact locked true") end },
    { "Sleep", "suspend", function() run("systemctl", { "suspend" }, nil, { output = false }) end },
    { "Log Out…", "logout", function() say("session", "fact kind 2"); say("topbar", "emit open_panel 5") end },
    { "Restart…", "reboot", function() say("session", "fact kind 1"); say("topbar", "emit open_panel 5") end },
    { "Shut Down…", "poweroff", function() say("session", "fact kind 0"); say("topbar", "emit open_panel 5") end },
    { "Take Screenshot", "screenshot", function() say("capture", "fact target_mode 0"); say("capture", "emit capture") end },
    { "Select Area Screenshot", "area", function() say("capture", "fact target_mode 2"); say("capture", "emit capture") end },
    { "Record Screen", "record", function() say("capture", "emit toggle_record") end },
    { "Clipboard History", "clipboard", function() say("topbar", "emit open_panel 2") end },
    { "Wallpapers", "wallpapers", function() say("topbar", "emit open_panel 3") end },
    { "Settings", "settings", function() say("topbar", "emit open_panel 4") end },
    { "Notifications", "notifications", function() say("topbar", "emit open_notifications") end },
    { "Control Center", "control", function() say("topbar", "emit open_control_center") end },
    { "Music", "music", function() say("topbar", "emit open_music") end },
}

-- ── the list ─────────────────────────────────────────────────────
local function paint()
    local rows = {}
    for i, e in ipairs(entries) do
        if i > MAX_ROWS then break end
        rows[i] = { name = e.name, sub = e.sub or "", kind = e.kind, glyph = e.kind ~= 0 and e.icon or "", icon = e.kind == 0 and e.icon or "" }
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

    -- a web prefix: `g cats`
    local key, term = low:match("^(%a+)%s+(.+)$")
    if key and SITES[key] then
        entries[#entries + 1] = web_entry(key, q:match("^%a+%s+(.+)$"))
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
