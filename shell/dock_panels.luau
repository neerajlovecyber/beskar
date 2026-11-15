-- The dock panels: Spotlight, clipboard, wallpaper strip, widget bar (common/dock_panels.plm).
local text = require("keys_text")     -- the text fields are the Keys scene's (keys_text.luau)
local Hooks = require("topbar_hooks")        -- the frame cannot emit to itself: its own events are called directly
-- Loaded by topbar.luau with its panel client; the panels' content is drawn in the frame's own surface.
return function(module)

local function close_panel() emit("Panels.close") end

-- the capture picker is its own scene, started on demand (start.sh capture-ensure), then told what to do
local function capture_start(mode, kind)
    run("sh", { "-c", '"$(cat "$HOME/.config/beskar/shell-dir")/shell/start.sh" capture-ensure' }, function()
        pcall(sys.call, "say", "capture", "fact mode " .. mode)
        pcall(sys.call, "say", "capture", "fact kind " .. kind)
        Hooks.emit("Topbar.open_panel", 11)
    end)
end


module("spotlight", function(panel, opened, shown, closed)
    -- Spotlight logic. What you type decides what is listed (best first):
    --   · a sum            `12*(3+4)`, `sqrt(2)`, `2^10`        → the result; Enter copies it
    --   · a web prefix     `g cats`, `yt lofi`, `gh pleamar`, `w niri`, `ddg x`   → search there (xdg-open)
    --   · `>` commands     `> lock`, `> shut down`, `> record`  → run it
    --   · `/` files         `/ report`, `/ project/readme` → files and folders under your search roots
    --   · applications     by name
    --   · nothing found    → "Search the web for …"
    -- Every row is an entry { name, sub, kind, icon, run }; `model.hits` shows them, `launch(i)` runs the i-th.

    local actions = require("actions")
    local search = require("spotlight_search")
    local slots = require("panels_data").slots
    local apps, windows, entries = {}, {}, {}
    local ok, saved = pcall(sys.ask, "files.read", "spotlight-history.json", "json")
    local history = search.history(ok and saved or nil)
    local window_epoch, window_pending = 0, false
    local file_rows, file_search = {}, nil

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

    local parse_timer_spec = require("timer_state").parse

    local function unavailable(message)
        run("notify-send", { "Spotlight", message }, nil, { output = false })
    end

    local function dispatch(action)
        if action.event then
            Hooks.emit(action.event, action.value)
        elseif action.route == "lock" then say("lock", "fact locked true")
        elseif action.route == "sleep" then run("systemctl", { "suspend" }, nil, { output = false })
        elseif action.route == "session" then
            Hooks.emit("Topbar.set_kind", action.value)
            Hooks.emit("Topbar.open_panel", slots.session)
        elseif action.route == "capture" then capture_start(action.mode, action.kind)
        elseif action.route == "widgets" then say("widgets", "emit edit_toggle") end
    end

    local function execute(entry)
        if entry.run then entry.run()
        elseif entry.path then
            run("xdg-open", { entry.path }, function(_, code)
                if code == 2 then unavailable("That file or folder no longer exists")
                elseif code ~= 0 then unavailable("Could not open that file or folder") end
            end)
        elseif entry.app then
            -- The app database can change between displaying a row and pressing Enter.
            local app
            for _, candidate in ipairs(apps) do
                if search.app_key(candidate) == entry.app_key then app = candidate; break end
            end
            if not app then unavailable("That application is no longer installed"); return end
            local launched, result = pcall(sys.call, "apps.launch", app.exec)
            if not launched or result == false then unavailable("Could not launch " .. app.name); return end
            search.record(history, entry.app_key)
            local written, err = pcall(sys.call, "files.write", "spotlight-history.json", history)
            if not written then log("Spotlight: could not save app history", err) end
        elseif entry.window_id then
            run("niri", { "msg", "action", "focus-window", "--id", tostring(entry.window_id) }, function(_, code)
                if code ~= 0 then unavailable("That window is no longer available") end
            end)
        elseif entry.tab ~= nil then
            if entry.setting_id then emit("Settings.reveal_setting", entry.setting_id)
            else emit("Settings.set_tab", entry.tab) end
            Hooks.emit("Topbar.open_panel", slots.settings)
        elseif entry.action then dispatch(entry.action) end
    end

    -- ── the list ─────────────────────────────────────────────────────
    local function paint(selected_key)
        local rows, selected = {}, 0
        for i, e in ipairs(entries) do
            if i > MAX_ROWS then break end
            local has_icon = (e.kind == 0 or e.kind == 4) and (e.icon or "") ~= ""
            local actionable = e.run ~= nil or e.app ~= nil or e.window_id ~= nil or e.tab ~= nil or e.action ~= nil or e.path ~= nil
            rows[i] = { name = e.name, sub = e.sub or "", kind = e.kind, site = e.site or 0,
                glyph = e.glyph or (e.kind ~= 0 and e.icon) or "󰀻", icon = has_icon and e.icon or "",
                has_icon = has_icon, actionable = actionable }
            if e.key and e.key == selected_key then selected = i - 1 end
        end
        model.hits = rows
        if not selected_key or selected ~= tonumber(fact.sp_sel) then fact.sc_t = math.max(0, selected - 6) * 44 end
        fact.sp_sel = selected
        panel.height(94 + math.min(math.max(#rows, 1), SEEN_ROWS) * 44)
    end

    local function build()
        local raw = text.query or ""
        local q = raw:gsub("^%s+", ""):gsub("%s+$", "")
        local low = q:lower()
        entries = {}

        -- Explicit modes never fall back to a web search.
        local mode = low:sub(1, 1)
        if mode == "/" then entries = file_rows; return end
        if mode == ">" or mode == "@" or mode == "?" then
            entries = search.results(q, { apps = apps, windows = windows, settings = actions.settings_results, commands = actions.commands }, history, MAX_ROWS)
            if #entries == 0 then
                local label = mode == "@" and "windows" or (mode == "?" and "settings" or "commands")
                entries[1] = { name = "No matching " .. label, sub = "Try another search", kind = 3, glyph = "󰍉" }
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
                        emit("Activities.start", sec)
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

        -- Apps, windows, Settings and commands share matching and stable ranking.
        local results = search.results(q, { apps = apps, windows = windows, settings = actions.settings_results, commands = actions.commands }, history, MAX_ROWS - #entries)
        for _, entry in ipairs(results) do entries[#entries + 1] = entry end

        -- nothing at all: the web
        if #entries == 0 and low ~= "" then
            entries[1] = web_entry("g", q)
        end
    end

    local function filter(keep_selection)
        local selected = keep_selection and entries[(tonumber(fact.sp_sel) or 0) + 1]
        build()
        paint(selected and selected.key)
    end

    file_search = require("spotlight_files").new(function(rows)
        file_rows = rows
        filter(true)
    end)

    local function refresh_windows()
        if not shown() or window_pending then return end
        local epoch = window_epoch
        window_pending = true
        run("niri", { "msg", "-j", "windows" }, function(out, code)
            if epoch ~= window_epoch or not shown() then return end
            window_pending = false
            local decoded, list = pcall(json.decode, out or "")
            windows = code == 0 and decoded and type(list) == "table" and list or {}
            filter(true)
        end)
    end

    -- Keep only app IDs/counts in history, never search queries or window titles.
    if not sys.watch("apps", function(list) apps = list or {}; filter(true) end) then
        apps = {}
        filter()
    end
    on("text:Keys.query", function()
        file_search.update(text.query or "", shown())
        filter()
    end)
    opened(function()
        window_epoch = window_epoch + 1
        window_pending = false
        file_search.update(text.query or "", true)
        filter()
        refresh_windows()
    end)
    every(2000, refresh_windows)

    on("launch", function(i)
        local entry = entries[(tonumber(i) or -1) + 1]
        if not entry or not (entry.run or entry.app or entry.window_id or entry.tab ~= nil or entry.action or entry.path) then return end
        close_panel()
        after(150, function() execute(entry) end)
    end)

    closed(function()
        window_epoch = window_epoch + 1
        window_pending = false
        windows = {}
        file_search.update("", false)
        file_rows = {}
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
    local clip_missing = nil -- cliphist is not installed: the panel says so instead of "Nothing copied yet"
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
        fact.clip_off = off
        fact.clip_total = n
        text.clip_count = (q ~= "" and (n .. " found")) or (#history .. " saved" .. (#pins > 0 and (" · " .. #pins .. " pinned") or ""))
        text.clip_empty = clip_missing and "Clipboard history needs cliphist (install the cliphist package)"
            or ((q ~= "") and "Nothing matches" or "Nothing copied yet")
        if #rows > 0 and (fact.clip_sel >= #rows or fact.clip_sel < 0) then
            fact.clip_sel = 0
        end
        panel.height(58 + (#rows == 0 and 130 or #rows * 46) + 84)   -- an empty list still has room for its message
    end

    repaint = function()
        rebuild(true)
    end

    local function refresh_history()
        if clip_missing == nil then
            run("sh", { "-c", "command -v cliphist >/dev/null" }, function(_, code) clip_missing = code ~= 0; rebuild(true) end)
        end
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

    on("text:Keys.clip_q", function()
        rebuild(false)
    end)

    -- ── buttons ──────────────────────────────────────────────────────
    local function entry_at(src)
        return view[off + (tonumber(src) or 0) + 1]
    end

    on("copy_clip", function(i)
        local v = entry_at(i)
        close_panel()
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

    -- Keys. `clip_sel` is the cursor's row INSIDE the 8 shown; the window (`off`) scrolls so the cursor never leaves it.
    local function goto_entry(abs)
        local n = #view
        if n == 0 then return end
        abs = math.max(0, math.min(n - 1, abs))
        if abs < off then off = abs elseif abs >= off + MAX_SHOWN then off = abs - MAX_SHOWN + 1 end
        off = math.max(0, math.min(math.max(0, n - MAX_SHOWN), off))
        rebuild(true)
        fact.clip_sel = abs - off
    end
    on("clip_move", function(d)
        d = tonumber(d) or 0
        goto_entry((off + (tonumber(fact.clip_sel) or 0)) + d)
    end)

    -- Delete takes the entry under the cursor out of the history (a pinned one: off the pins). The search field
    -- owns Delete while something is typed in it.
    on("clip_delete", function(i)
        if (text.clip_q or "") ~= "" then return end
        local v = entry_at(i)
        if not v then return end
        local keep = off + (tonumber(i) or 0)
        if v.kind == "pin" then
            table.remove(pins, v.idx)
            save_pins()
            rebuild(true)
        else
            local raw = history[v.idx].raw
            table.remove(history, v.idx)
            run("sh", { "-c", 'printf "%s\\n" "$1" | cliphist delete', "x", raw }, nil, { output = false })
            rebuild(true)
        end
        goto_entry(keep)
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
    panel.height(316)               -- thumbnails plus transition/favourite controls

    local WS = require("wallpaper_store")
    local favourites, favourite_status, favourites_writable = {}, {}, true
    local applying = false
    local ok_fav, raw_fav = pcall(sys.ask, "files.read", "wallpaper-favourites.json")
    if not ok_fav then favourites_writable = false
    elseif raw_fav then
        local ok, saved = pcall(json.decode, raw_fav)
        if ok and type(saved) == "table" and (saved.version == nil or saved.version == 1) then favourites = WS.fav_decode(saved)
        else favourites_writable = false end
    end
    if not favourites_writable then text.wall_status = "Favourites file cannot be read; it has been preserved" end

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
            if w.available ~= false then make_thumb(w.path) end
            rows[#rows + 1] = {
                name = w.name,
                thumb = thumb_of[w.path],
                ready = state[w.path] == "ready",
                current = w.path == current,
                builtin = w.builtin,
                sel = (first + #rows) == cur + 1,
                favourite = WS.fav_has(favourites, w.path),
                available = w.available ~= false,
            }
        end
        fact.wall_favourite = view[cur + 1] and WS.fav_has(favourites, view[cur + 1].path) or false
        fact.wall_favourites_writable = favourites_writable
        model.walls = rows
        fact.wall_total = #view
        fact.wall_row = row
        fact.wall_rows = math.max(1, #view - PAGE + 1)
        text.wall_hint = string.format("%d pictures", #view)
    end

    local function rebuild(tab)
        view = {}
        if tab == 3 then
            for _, w in ipairs(WS.fav_rows(favourites, favourite_status)) do view[#view + 1] = w end
        else
            for _, w in ipairs(all) do
                if tab == 0 or (tab == 1 and not w.builtin) or (tab == 2 and w.builtin) then view[#view + 1] = w end
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
        emit("Settings.set_pal_src", path)
    end

    on("accent_now", function()
        if current then
            accent_from(current)
        end
    end)

    -- ── buttons ──────────────────────────────────────────────────────
    local function set_tab(n)
        local tab = tonumber(n)
        if not tab or tab < 0 or tab > 3 or tab ~= math.floor(tab) then return end
        fact.wall_tab = tab
        if tab == 3 then WS.status(nil, favourites, function(status) favourite_status = status; if fact.wall_tab == 3 then rebuild(3) end end) end
        rebuild(tab)
    end
    on("wall_tab_set", set_tab)
    -- Up / Down on the keyboard: the previous / next filter tab (stops at the ends)
    on("wall_tab_step", function(d)
        set_tab(math.max(0, math.min(3, (tonumber(fact.wall_tab) or 0) + (tonumber(d) or 0))))
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

    local function committed(result)
        applying, fact.wall_busy = false, false
        if not result.ok then text.wall_status = result.message or "Could not change wallpaper"; return end
        current = result.path
        text.wall_status = "Wallpaper applied"
        paint()
        local sent = pcall(sys.call, "say", "wallpaper", "text wp_new " .. current)
        if not sent then text.wall_status = "Choice saved; wallpaper process is unavailable" end
        if fact["Settings.accent_auto"] == true then accent_from(current) end
    end
    local function apply(w)
        if not w or applying then return end
        if #w.path > 3500 then text.wall_status = "Picture path is too long"; return end
        applying, fact.wall_busy = true, true
        text.wall_status = "Checking picture…"
        WS.commit(nil, w.path, committed)
    end
    on("wall_restore", function()
        if applying then return end
        applying, fact.wall_busy = true, true
        text.wall_status = "Checking previous picture…"
        WS.restore(nil, committed)
    end)
    on("wall_favourite_toggle", function(index)
        if not favourites_writable then text.wall_status = "Favourites file is protected; repair it before editing"; return end
        local n = tonumber(index)
        if not n or n < 0 then n = cur else n = row + n end
        local picture = view[n + 1]
        if not picture then return end
        cur = n
        local next_list, status = WS.fav_toggle(favourites, picture.path)
        if status == "full" then text.wall_status = "Favourites is full (48 pictures)"; return end
        if status == "invalid" then text.wall_status = "This picture cannot be saved as a favourite"; return end
        local ok = pcall(sys.call, "files.write", "wallpaper-favourites.json", WS.fav_encode(next_list))
        if not ok then text.wall_status = "Could not save favourites"; return end
        favourites = next_list
        text.wall_status = status == "added" and "Added to favourites" or "Removed from favourites"
        if fact.wall_tab == 3 then rebuild(3) else paint() end
    end)

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
    opened(function()
        WS.status(nil, favourites, function(status)
            favourite_status = status
            if fact.wall_tab == 3 then rebuild(3) end
        end)
        scan()
    end)

    scan()
end)


module("widget_bar", function(panel, opened, shown, closed)
    -- The widget bar's logic: it only forwards its buttons to the widgets scene (which owns every decision) and keeps
    -- edit mode and the bar in step (closing the bar by Esc ends edit mode). Its second page, Desktops (C4a), lists the
    -- layouts Widgets keeps: widget_bar_layouts.luau reads Widgets' snapshot (`text wb_layouts`, pushed by `say`) and asks
    -- Widgets to save / load / rename / duplicate / update / delete; nothing here writes the layouts file.
    local PAGE_H = { [0] = 176, [1] = 272, [2] = 336 }     -- Card includes a bounded stack chooser; surface = max page + dock
    -- Page 2 (Card options) is a local overlay on the layouts controller, which only knows pages 0 and 1: `layout_page`
    -- is the page it reports and `fact.wb_page` shows 2 while the Card page is up.
    panel.height(PAGE_H[0])

    local function widgets(words)
        return pcall(sys.call, "say", "widgets", words)
    end

    on("wb_add", function(code) widgets("emit w_add " .. math.floor(tonumber(code) or 0)) end)
    on("wb_preset", function(n) widgets("emit w_preset " .. math.floor(tonumber(n) or 0)) end)
    on("wb_undo", function() widgets("emit w_undo") end)
    on("wb_tidy", function() widgets("emit w_tidy") end)
    on("wb_grid", function() widgets("emit w_grid") end)
    on("wb_done", function() widgets("emit edit_done") end)

    local DATA = require("widgets_data")
    local kinds, presets = {}, {}
    for _, k in ipairs(DATA.KINDS) do kinds[#kinds + 1] = { id = k.id, name = k.name, icon = k.icon } end
    for i, p in ipairs(DATA.PRESETS) do presets[#presets + 1] = { id = i, name = p.name } end
    model.kinds = kinds
    model.presets = presets

    -- ── saved desktops ──
    local shown_rows = ""
    local ctl, opt
    local layout_page, card_page = 0, false
    local function apply_page()
        local page = card_page and 2 or layout_page
        fact.wb_page = page
        panel.height(PAGE_H[page] or PAGE_H[0])
    end
    ctl = require("widget_bar_layouts").controller({
        json = json,
        say = widgets,
        after = after,
        clear_name = function() text.wb_name = "" end,
        page_changed = function(page) layout_page = page; apply_page() end,
        publish = function(v)
            -- the rows are the only list: write them when they change, the scalars every time (they are cheap)
            local sig = {}
            for _, r in ipairs(v.rows) do sig[#sig + 1] = r.id .. "|" .. r.name .. "|" .. r.meta .. "|" .. r.tag .. "|" .. tostring(r.sel) end
            local joined = table.concat(sig, "\n")
            if joined ~= shown_rows then
                shown_rows = joined
                local rows = {}
                for i, r in ipairs(v.rows) do rows[i] = { id = r.id, name = r.name, meta = r.meta, tag = r.tag, sel = r.sel } end
                model.wb_rows = rows
            end
            layout_page = v.page
            fact.wb_page = card_page and 2 or v.page
            fact.wb_selected = v.sel_id
            fact.wb_total = v.total
            fact.wb_top = v.top
            fact.wb_arm = v.arm
            fact.wb_exists = v.exists
            fact.wb_ready = v.ready
            fact.wb_status_ok = v.status_ok
            fact.wb_can_save = v.can_save
            fact.wb_can_load = v.can_load
            fact.wb_can_rename = v.can_rename
            fact.wb_can_dup = v.can_duplicate
            fact.wb_can_update = v.can_update
            fact.wb_can_delete = v.can_delete
            text.wb_hint = v.hint
            text.wb_status = v.status
            text.wb_range = v.range
        end,
    })
    on("text:wb_layouts", function(body) ctl.snapshot(body) end)
    on("text:Keys.wb_name", function(name) ctl.set_name(name) end)
    -- ── card options (C4b) ──
    local shown_opts = ""
    opt = require("widget_bar_options").controller({
        json = json,
        say = widgets,
        kind_name = function(id)
            for _, k in ipairs(DATA.KINDS) do if k.id == id then return k.name end end
            return "Widget " .. id
        end,
        page_changed = function(active) card_page = active; apply_page() end,
        publish = function(v)
            local sig = {}
            for _, r in ipairs(v.rows) do sig[#sig + 1] = r.id .. "|" .. r.label .. "|" .. r.value .. "|" .. r.n .. "|" .. r.l1 .. "|" .. r.l2 .. "|" .. r.l3 .. "|" .. tostring(r.sel) end
            local joined = table.concat(sig, "\n")
            if joined ~= shown_opts then
                shown_opts = joined
                local rows = {}
                for i, r in ipairs(v.rows) do rows[i] = { id = r.id, label = r.label, value = r.value, n = r.n, l1 = r.l1, l2 = r.l2, l3 = r.l3, sel = r.sel } end
                model.wb_opts = rows
            end
            fact.wb_opt_has = v.has_card
            fact.wb_opt_row = v.row
            fact.wb_opt_count = v.count
            fact.wb_opt_ok = v.status_ok
            fact.wb_opt_can_reset = v.can_reset
            text.wb_opt_title = v.title
            text.wb_opt_sub = v.sub
            text.wb_opt_empty = v.empty
            text.wb_opt_hint = v.hint
            text.wb_opt_status = v.status
            fact.wb_stack_join = v.stack_can_join
            fact.wb_stacked = v.stacked
            fact.wb_stack_unstack = v.stack_can_unstack
            text.wb_stack_label = v.stack_label
            text.wb_stack_position = v.stack_position
        end,
    })
    on("text:wb_card_options", function(body) opt.snapshot(body) end)
    on("wb_opt", function(code) opt.choose(code) end)
    on("wb_opt_pick", function(id) opt.pick(id) end)
    on("wb_opt_move", function(d) opt.move(d) end)
    on("wb_opt_change", function(d) opt.change(d) end)
    on("wb_opt_cycle", function() opt.cycle() end)
    on("wb_opt_reset", function() opt.reset() end)
    on("wb_stack_target", function(d) opt.stack_target(d) end)
    on("wb_stack_join", function() opt.stack_join() end)
    on("wb_stack_prev", function() opt.stack_page(-1) end)
    on("wb_stack_next", function() opt.stack_page(1) end)
    on("wb_stack_unstack", function() opt.stack_unstack() end)

    local function switch_page(n)
        n = math.floor(tonumber(n) or 0)
        fact.wb_cur = -1
        if n == 2 then opt.enter(); return end
        opt.leave()                       -- back to Widgets / Desktops: the layouts controller never left its own page
        ctl.tab(n)
        apply_page()
    end
    on("wb_tab", switch_page)
    -- Alt+Left / Alt+Right: the previous / next page
    on("wb_tab_step", function(d)
        local page = math.max(0, math.min(2, (tonumber(fact.wb_page) or 0) + (tonumber(d) or 0)))
        if page ~= tonumber(fact.wb_page) then switch_page(page) end
    end)

    -- Widgets page, keyboard: one cursor over the kinds (6 per row) and then the presets (one row), laid out as drawn.
    local COLS = 6
    local function cursor_move(dir)
        local nk, np = #kinds, #presets
        local total = nk + np
        if total == 0 then return end
        local c = tonumber(fact.wb_cur) or -1
        if c < 0 or c >= total then fact.wb_cur = 0; return end
        local is_kind = c < nk
        if dir == 1 then c = math.max(0, c - 1)
        elseif dir == 2 then c = math.min(total - 1, c + 1)
        elseif dir == 5 then c = 0
        elseif dir == 6 then c = total - 1
        elseif dir == 4 then            -- down: the next row of kinds, else the preset under the column
            if is_kind then
                if c + COLS < nk then c = c + COLS
                elseif np > 0 then
                    local x = 24 + (c % COLS) * 126
                    c = nk + math.max(0, math.min(np - 1, math.floor((x - 92) / 106 + 0.5)))
                end
            end
        elseif dir == 3 then            -- up: the kind above (the preset: the kind above its x, on the last row)
            if is_kind then
                if c - COLS >= 0 then c = c - COLS end
            else
                local x = 92 + (c - nk) * 106
                local col = math.max(0, math.min(COLS - 1, math.floor((x - 24) / 126 + 0.5)))
                local last_row = math.floor((nk - 1) / COLS)
                c = math.min(nk - 1, last_row * COLS + col)
            end
        end
        fact.wb_cur = c
    end
    on("wb_nav", function(dir) cursor_move(math.floor(tonumber(dir) or 0)) end)
    on("wb_activate", function()
        local c = tonumber(fact.wb_cur) or -1
        if c < 0 then return end
        if c < #kinds then
            -- the same code as the chip's press: monitor * 100 + kind
            widgets("emit w_add " .. math.floor((tonumber(fact.open_screen) or 0) * 100 + kinds[c + 1].id))
        elseif presets[c - #kinds + 1] then
            widgets("emit w_preset " .. presets[c - #kinds + 1].id)
        end
    end)
    on("wb_pick", function(id) ctl.pick(id) end)
    on("wb_move", function(d) ctl.move(d) end)
    on("wb_scroll", function(wheel) ctl.scroll(wheel) end)
    on("wb_save", function() ctl.save() end)
    on("wb_load", function() ctl.load() end)
    on("wb_rename", function() ctl.rename() end)
    on("wb_dup", function() ctl.duplicate() end)
    on("wb_update", function() ctl.update() end)
    on("wb_delete", function() ctl.delete() end)
    on("wb_submit", function() ctl.submit() end)
    -- Esc cancels a pending confirmation first; otherwise it closes the bar like every dock panel
    on("wb_escape", function()
        if opt.active() or not ctl.escape() then close_panel() end
    end)

    opened(function()
        fact.wb_cur = -1
        ctl.opened()
        opt.opened()
        apply_page()
        widgets("emit w_bar_open")
    end)
    closed(function()
        ctl.closed()
        opt.closed()
        apply_page()
        widgets("emit edit_done")
    end)
    panel.keep()                 -- a click outside does not close it: you work on the desktop with it
end)
end
