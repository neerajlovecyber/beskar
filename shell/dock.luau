-- Dock panels (Spotlight, clipboard, wallpapers, widget bar, session dialog, polkit password dialog): ONE scene (dock.plm), one logic; the shared core is
-- panelcore.luau. Each part is its own function (own locals); `opened` / `closed` replace the old `on("fact:open")`.
local module = require("panelcore")({ spotlight = 4, wallpapers = 5, clipboard = 6, widget_bar = 10, session = 11, polkit = 12 })

module("spotlight", function(panel, opened, shown, closed)
    -- Spotlight logic. What you type decides what is listed (best first):
    --   · a sum            `12*(3+4)`, `sqrt(2)`, `2^10`        → the result; Enter copies it
    --   · a web prefix     `g cats`, `yt lofi`, `gh pleamar`, `w niri`, `ddg x`   → search there (xdg-open)
    --   · `>` commands     `> lock`, `> shut down`, `> record`  → run it
    --   · applications     by name
    --   · nothing found    → "Search the web for …"
    -- Every row is an entry { name, sub, kind, icon, run }; `model.hits` shows them, `launch(i)` runs the i-th.

    local apps = {}
    local entries = {}

    local MAX_ROWS = 24       -- results kept (the list shows 7 and scrolls)
    local SEEN_ROWS = 7

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
        { "Log Out…", "logout", function() fact.kind = 2; say("topbar", "emit open_panel 5") end },
        { "Restart…", "reboot", function() fact.kind = 1; say("topbar", "emit open_panel 5") end },
        { "Shut Down…", "poweroff", function() fact.kind = 0; say("topbar", "emit open_panel 5") end },
        { "Take Screenshot", "screenshot", function() say("modals", "fact mode 2"); say("modals", "fact kind 0"); say("topbar", "emit open_panel 11") end },
        { "Select Area Screenshot", "area", function() say("modals", "fact mode 0"); say("modals", "fact kind 0"); say("topbar", "emit open_panel 11") end },
        { "Record Screen", "record", function() say("modals", "fact mode 0"); say("modals", "fact kind 1"); say("topbar", "emit open_panel 11") end },
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
        fact.sp_sel = 0
        panel.height(94 + math.min(math.max(#rows, 1), SEEN_ROWS) * 44)
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
    closed(function()
        text.query = ""
        filter()
    end)
end)

module("clipboard", function(panel, opened, shown, closed)
    -- Clipboard history logic (cliphist + wl-copy). Everything goes through `run` (the sandbox has no io / os), and the
    -- frame draws the glass: this tells it how tall the list is.
    --
    --   history  `cliphist list`: up to 100 entries, stored by cliphist across restarts (start.sh keeps the watcher
    --            `wl-paste --watch cliphist -max-items 100 store` running)
    --   pins     text you pinned: stored by us (files.write) and never removed: not by Clear All, not by the 100 limit
    --   shown    pinned entries first, then the recent ones, filtered by the search; 8 rows at a time (wheel / arrows)


    local MAX_SHOWN = 8
    local MAX_HISTORY = 100

    local history = {}      -- { raw = the line cliphist printed, preview = text }
    local pins = {}         -- { text = full text }
    local view = {}         -- what the list can show now: { kind = "pin"|"hist", idx = n, preview = text }
    local off = 0           -- first row on screen (0-based)
    local CACHE = nil       -- ~/.cache/beskar/clipboard, where image thumbnails live
    local thumb_state = {}  -- cliphist id -> "making" | "ready"

    -- ── pins, on disk ────────────────────────────────────────────────
    do
        local ok, loaded = pcall(sys.ask, "files.read", "pins.json", "json")
        if ok and type(loaded) == "table" and type(loaded.items) == "table" then
            pins = loaded.items
        end
    end

    local saving = false
    local function save_pins()
        if saving then
            return
        end
        saving = true
        after(500, function()
            saving = false
            pcall(sys.call, "files.write", "pins.json", { items = pins })
        end)
    end

    -- ── what is shown ────────────────────────────────────────────────
    local function flat(s)
        return ((s or ""):gsub("[\r\n\t]+", " "):gsub("%s+", " "))
    end

    -- cliphist lists an image as "[[ binary data 40 KiB png 468x111 ]]": turn that into a readable label, and keep
    -- the id so a thumbnail can be made.
    local function image_label(preview)
        local size, fmt, w, h = preview:match("^%[%[ binary data (%S+ %S+) (%a+) (%d+)x(%d+) %]%]")
        if size then
            return string.format("Image · %s × %s · %s", w, h, size), fmt
        end
    end

    local function thumb_path(id)
        return CACHE and (CACHE .. "/" .. id .. ".png") or ""
    end

    local repaint

    local function make_thumb(id)
        if not CACHE or thumb_state[id] then
            return
        end
        thumb_state[id] = "making"
        local script = 'mkdir -p "$1" && { [ -f "$2" ] || cliphist decode "$3" | magick - -thumbnail 112x68 "$2"; }'
        run("sh", { "-c", script, "x", CACHE, thumb_path(id), tostring(id) }, function(_, code)
            if code == 0 then
                thumb_state[id] = "ready"
                repaint()
            else
                thumb_state[id] = nil
            end
        end)
    end

    local function rebuild(keep_off)
        local q = (text.clip_q or ""):lower()
        view = {}
        local pinned_text = {}
        for i, p in ipairs(pins) do
            pinned_text[p.text] = true
            local pv = flat(p.text)
            if q == "" or pv:lower():find(q, 1, true) then
                view[#view + 1] = { kind = "pin", idx = i, preview = pv }
            end
        end
        for i, h in ipairs(history) do
            if not pinned_text[h.preview] and (q == "" or h.preview:lower():find(q, 1, true)) then
                view[#view + 1] = { kind = "hist", idx = i, preview = flat(h.preview), image = h.image, id = h.id }
            end
        end
        if not keep_off then
            off = 0
        end
        off = math.max(0, math.min(off, math.max(0, #view - MAX_SHOWN)))
        local rows = {}
        for k = off + 1, math.min(#view, off + MAX_SHOWN) do
            local v = view[k]
            local is_img = v.image == true
            if is_img then
                make_thumb(v.id)
            end
            rows[#rows + 1] = {
                src = k - 1,
                preview = v.preview,
                pinned = v.kind == "pin",
                pinnable = v.kind == "pin" or not is_img,
                is_img = is_img,
                ready = is_img and thumb_state[v.id] == "ready",
                thumb = is_img and thumb_path(v.id) or "",
            }
        end
        model.clips = rows
        local n = #view
        text.clip_count = (q ~= "" and (n .. " found")) or (#history .. " saved" .. (#pins > 0 and (" · " .. #pins .. " pinned") or ""))
        text.clip_empty = (q ~= "") and "Nothing matches" or "Nothing copied yet"
        if #rows > 0 and (fact.clip_sel >= #rows or fact.clip_sel < 0) then
            fact.clip_sel = 0
        end
        panel.height(58 + (#rows == 0 and 130 or #rows * 46) + 84)   -- an empty list still has room for its message
    end

    repaint = function()
        rebuild(true)
    end

    local function refresh_history()
        run("sh", { "-c", "cliphist list 2>/dev/null | head -n " .. MAX_HISTORY }, function(out)
            local items = {}
            for line in (out or ""):gmatch("[^\n]+") do
                local id_s, preview = line:match("^(%d+)%s+(.*)$")
                if id_s and preview then
                    local label = image_label(preview)
                    items[#items + 1] = { raw = line, id = tonumber(id_s), preview = label or preview, image = label ~= nil }
                end
            end
            history = items
            rebuild(true)
        end)
    end

    opened(function()
        text.clip_q = ""
        refresh_history()
        rebuild(false)
    end)

    on("text:clip_q", function()
        rebuild(false)
    end)

    -- ── buttons ──────────────────────────────────────────────────────
    local function entry_at(src)
        return view[off + (tonumber(src) or 0) + 1]
    end

    on("copy_clip", function(i)
        local v = entry_at(i)
        fact.open = false
        if not v then
            return
        end
        if v.kind == "pin" then
            -- a pinned entry is the text itself
            run("sh", { "-c", 'printf "%s" "$1" | wl-copy', "x", pins[v.idx].text }, nil, { output = false })
        else
            -- a history entry goes back through cliphist (it knows the id) into the clipboard
            run("sh", { "-c", 'printf "%s" "$1" | cliphist decode | wl-copy', "x", history[v.idx].raw }, nil, { output = false })
        end
        run("notify-send", { "-a", "Clipboard", "-i", "edit-paste", "Copied", "Ready to paste" }, nil, { output = false })
    end)

    on("pin_clip", function(i)
        local v = entry_at(i)
        if not v then
            return
        end
        if v.kind == "pin" then
            table.remove(pins, v.idx)
            save_pins()
            rebuild(true)
        else
            -- the full text, decoded, is what is kept (the list only has a one-line preview)
            run("sh", { "-c", 'printf "%s" "$1" | cliphist decode', "x", history[v.idx].raw }, function(out)
                if out and out ~= "" then
                    table.insert(pins, 1, { text = out })
                    save_pins()
                    rebuild(true)
                end
            end)
        end
    end)

    on("clip_scroll", function(wheel)
        local step = (tonumber(wheel) or 0) > 0 and -1 or 1
        off = math.max(0, math.min(math.max(0, #view - MAX_SHOWN), off + step))
        rebuild(true)
    end)

    -- Keep the cursor in view when the arrows run past the ends of the 8 shown rows.
    on("fact:clip_sel", function()
        -- (the rows are the window; moving past it is handled by the wheel)
    end)

    on("clear_all", function()
        -- the history goes; pinned entries stay
        run("cliphist", { "wipe" }, nil, { output = false })
        history = {}
        rebuild(false)
        run("notify-send", { "-a", "Clipboard", "Clipboard cleared", "Pinned entries were kept" }, nil, { output = false })
    end)

    run("sh", { "-c", 'printf %s "$HOME"' }, function(out)
        if out and out ~= "" then
            CACHE = out .. "/.cache/beskar/clipboard"
            rebuild(true)
        end
    end)
    refresh_history()
end)

module("wallpapers", function(panel, opened, shown, closed)
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
    opened(scan)

    scan()
end)

module("widget_bar", function(panel, opened, shown, closed)
    -- The widget bar's logic: it only forwards its buttons to the widgets scene (which owns every decision) and keeps
    -- edit mode and the bar in step (closing the bar by Esc ends edit mode).
    panel.height(132)

    local function widgets(words)
        pcall(sys.call, "say", "widgets", words)
    end

    on("wb_add", function(code) widgets("emit w_add " .. math.floor(tonumber(code) or 0)) end)
    on("wb_preset", function(n) widgets("emit w_preset " .. math.floor(tonumber(n) or 0)) end)
    on("wb_undo", function() widgets("emit w_undo") end)
    on("wb_tidy", function() widgets("emit w_tidy") end)
    on("wb_grid", function() widgets("emit w_grid") end)
    on("wb_done", function() widgets("emit edit_done") end)

    opened(function() widgets("emit w_bar_open") end)
    closed(function() widgets("emit edit_done") end)
    panel.keep()                 -- a click outside does not close it: you work on the desktop with it


    local DATA = require("widgets_data")
    local kinds, presets = {}, {}
    for _, k in ipairs(DATA.KINDS) do kinds[#kinds + 1] = { id = k.id, name = k.name, icon = k.icon } end
    for i, p in ipairs(DATA.PRESETS) do presets[#presets + 1] = { id = i, name = p.name } end
    model.kinds = kinds
    model.presets = presets
end)

module("session", function(panel, opened, shown, closed)
    -- Session dialog logic: shut down, restart, log out (with a 60 s countdown). Enter presses the highlighted button
    -- (the action by default); the dialog grows out of the dock like Spotlight.
    panel.height(250)
    local timer_id = nil

    local function clear_timer()
        if timer_id then
            cancel(timer_id)
            timer_id = nil
        end
    end

    on("confirm_action", function()
        clear_timer()
        fact.open = false
        local k = fact.kind or 0
        if k == 0 then
            log("Session: Powering off system...")
            run("systemctl", { "poweroff" }, function(_, code)
                if code ~= 0 then log("Session: poweroff failed with code", code) end
            end)
        elseif k == 1 then
            log("Session: Restarting system...")
            run("systemctl", { "reboot" }, function(_, code)
                if code ~= 0 then log("Session: reboot failed with code", code) end
            end)
        else
            log("Session: Logging out...")
            run("niri", { "msg", "action", "quit", "--skip-confirmation" })
        end
    end)

    -- Countdown loop: runs while this dialog is the one shown
    opened(function()
        fact.ses_sel = 1          -- Enter presses the action by default
        fact.countdown = 60
        clear_timer()
        local function tick()
            if not shown() then return end
            if fact.countdown > 1 then
                fact.countdown = fact.countdown - 1
                timer_id = after(1000, tick)
            else
                emit("confirm_action")
            end
        end
        timer_id = after(1000, tick)
    end)
    closed(clear_timer)

    on("ses_enter", function()
        if not shown() then return end
        if (tonumber(fact.ses_sel) or 1) == 1 then
            emit("confirm_action")
        else
            fact.open = false
        end
    end)
    on("dismiss", function() if shown() then fact.open = false end end)
end)

module("polkit", function(panel, opened, shown, closed)
    -- The authentication agent. Watching the `polkit` service makes this process the session's agent (one per session).
    -- Requests come one at a time: `pending` (a program waits; polkit's message and whose password it takes), then
    -- `asking` (an answer is awaited; the prompt, secret or not), `error = "wrong"` after a bad one (three tries at most).
    panel.height(310)
    panel.keep()                 -- a click outside does not close it: it has to be answered or cancelled
    local pending = false

    local function open_on_focused_monitor()
        -- the frame knows which monitor has the focus (FOCUS_PANELS in topbar.luau toggles us there)
        pcall(sys.call, "say", "topbar", "emit open_panel 8")
    end

    sys.watch("polkit", function(p)
        p = p or {}
        local was_wrong = fact.pk_wrong == true
        text.pk_message = p.message or ""
        local prompt = p.prompt or ""
        prompt = prompt:gsub(":%s*$", "")
        text.pk_prompt = (prompt ~= "" and prompt) or ("Password for " .. (p.user or "administrator"))
        text.pk_info = p.info or ""
        fact.pk_secret = p.secret ~= false
        fact.pk_asking = p.asking == true
        fact.pk_wrong = p.error == "wrong"

        if p.pending == true then
            if not pending then
                pending = true
                text.password = ""
                if not shown() then open_on_focused_monitor() end
            end
        elseif pending then
            pending = false
            text.password = ""
            if shown() then fact.open = false end
        end

        if fact.pk_wrong and not was_wrong then
            text.password = ""
            emit("pk_shake")
        end
    end)

    on("pk_answer", function()
        if not shown() or fact.pk_asking ~= true then return end
        local pwd = text.password or ""
        text.password = ""
        pcall(sys.call, "polkit.answer", pwd)
    end)

    on("pk_cancel", function()
        if not shown() then return end
        text.password = ""
        pcall(sys.call, "polkit.cancel")
        fact.open = false
        pending = false
    end)

    -- closed by anything else (another panel took over): the program must be told it was dismissed
    closed(function()
        if pending then
            pending = false
            text.password = ""
            pcall(sys.call, "polkit.cancel")
        end
    end)
end)

-- opening one closes the others (Control Center, notifications, Settings …)
require("exclusive")("dock")
