-- The dock, split out of topbar.luau: the pinned apps (~/.config/beskar/dock, written whole and atomically), the apps running in
-- niri, their thumbnails on hover, and the pin events (dock_pin, dock_move_pin, request_dock_pins…). `env` hands over what the
-- frame owns: `on` (its recording wrapper: every handler is also kept in topbar_hooks) and `wins()` (the windows niri last
-- reported; the frame replaces that list, so it is read through a function). It returns what the workspaces section needs.
return function(env)
    local on = env.on
    local build_dock

    -- ── dock: the apps you pinned, plus the ones running ─────────────
    -- Pinned apps are the lines of ~/.config/beskar/dock (desktop ids: org.gnome.Nautilus, kitty, …); edit it by
    -- hand or right-click an icon → "Keep in Dock". With no file the dock shows two: a file manager and a terminal.
    local pinned = nil          -- list of desktop ids, nil = the defaults
    local entries = {}          -- desktop entries (apps service)
    local by_key = {}           -- lower-case id / wmclass / last part of the id → entry
    local items = {}            -- what the dock shows now, in model order
    local thumbnails_by_id = {}
    local thumbnails_list = {}
    local hovered_dock_idx = -1

    sys.watch("thumbnails", function(info)
        thumbnails_list = (info and info.list) or {}
        thumbnails_by_id = {}
        for _, t in ipairs(thumbnails_list) do
            if t.id and t.id ~= "" then
                thumbnails_by_id[t.id] = t
            end
        end
        if hovered_dock_idx >= 0 and build_dock then
            build_dock()
        end
    end)

    local function lower(s)
        return string.lower(s or "")
    end

    local function index_entries(list)
        entries = list or {}
        by_key = {}
        for _, e in ipairs(entries) do
            local id = lower(e.id):gsub("%.desktop$", "")
            by_key[id] = e
            if e.wmclass and e.wmclass ~= "" then
                by_key[lower(e.wmclass)] = e
            end
            local last = id:match("([^%.]+)$")
            if last and not by_key[last] then
                by_key[last] = e
            end
        end
    end

    local function entry_for(app_id)
        local k = lower(app_id)
        return by_key[k] or by_key[k:match("([^%.]+)$") or k]
    end

    local FILE_MANAGERS = { "org.gnome.nautilus", "nautilus", "thunar", "org.kde.dolphin", "dolphin", "nemo", "pcmanfm", "pcmanfm-qt" }
    local TERMINALS = { "kitty", "com.mitchellh.ghostty", "ghostty", "alacritty", "foot", "org.wezfurlong.wezterm", "wezterm", "org.gnome.terminal", "konsole", "xterm" }

    local function default_of(preferred, category)
        for _, id in ipairs(preferred) do
            if by_key[id] then
                return by_key[id]
            end
        end
        for _, e in ipairs(entries) do
            if (e.categories or ""):find(category, 1, true) then
                return e
            end
        end
    end

    local function default_pins()
        local out = {}
        local files = default_of(FILE_MANAGERS, "FileManager")
        local term = default_of(TERMINALS, "TerminalEmulator")
        if files then out[#out + 1] = files.id end
        if term then out[#out + 1] = term.id end
        return out
    end

    -- The pin file is written whole and atomically (temp file + mv), one write at a time: a move that follows another
    -- while the first is still running waits for it, and `read_pins` ignores any answer that raced a local edit
    -- (`pins_gen` changes with every edit and every finished write).
    local frame_options = require("frame_options")
    local pins_ready = false
    local pins_gen = 0
    local pin_save_timer = nil          -- a move's debounced write is waiting
    local pin_save_busy = false         -- a write is running
    local pin_save_again = false        -- the list changed while it ran

    local function flush_pins()
        pin_save_timer = nil
        if pin_save_busy then
            pin_save_again = true
            return
        end
        pin_save_busy = true
        require("pins_store").write(run, {list=pinned or default_pins()}, function(ok)
            pin_save_busy = false
            pins_gen = pins_gen + 1
            if pin_save_again then
                pin_save_again = false
                flush_pins()
            end
        end)
    end

    local function save_pins(list)
        pinned = list
        pins_gen = pins_gen + 1
        if pin_save_timer then
            cancel(pin_save_timer)
        end
        flush_pins()
    end

    -- "com.t3tools.T3Code" → "T3Code", "google-chrome" → "Google chrome": a readable name for an app with no desktop entry
    local function pretty_app(id)
        local last = (id or ""):match("([^%.]+)$") or id or ""
        last = last:gsub("[_%-]+", " ")
        return (last:sub(1, 1):upper() .. last:sub(2))
    end

    local function name_of(e)
        return (e.local_name and e.local_name ~= "") and e.local_name or e.name or e.id
    end

    build_dock = function()
        local pins = pinned or default_pins()
        local groups, order = {}, {}
        for _, w in ipairs(env.wins()) do
            local e = entry_for(w.app_id)
            local key = e and lower(e.id) or ("app:" .. lower(w.app_id))
            local g = groups[key]
            if not g then
                g = { entry = e, app_id = w.app_id or "", wins = {}, pid = w.pid }
                groups[key] = g
                order[#order + 1] = key
            end
            g.wins[#g.wins + 1] = w.id
        end
        local list, used = {}, {}
        for pin_pos, id in ipairs(pins) do
            local e = by_key[lower(id)]
            local aid, cmd = id:match("^app:([^|]+)|(.*)$")
            if aid then
                -- an app with no (visible) desktop entry, pinned from its running window: we keep how to start it
                local key = "app:" .. lower(aid)
                if not used[key] and #list < 12 then
                    used[key] = true
                    list[#list + 1] = { name = pretty_app(aid), icon = lower(aid), pinned = true, cmd = cmd, pinstr = id, pin_pos = pin_pos,
                                        wins = groups[key] and groups[key].wins or {} }
                end
            elseif e and not used[lower(e.id)] and #list < 12 then
                local key = lower(e.id)
                used[key] = true
                list[#list + 1] = { entry = e, name = name_of(e), icon = e.icon or "", pinned = true, pinstr = id, pin_pos = pin_pos,
                                    wins = groups[key] and groups[key].wins or {} }
            end
        end
        for _, key in ipairs(order) do
            if not used[key] and #list < 12 then
                local g = groups[key]
                local e = g.entry
                list[#list + 1] = { entry = e, name = e and name_of(e) or pretty_app(g.app_id), icon = e and e.icon or lower(g.app_id),
                                    pinned = false, wins = g.wins, app_id = g.app_id, pid = g.pid }
            end
        end
        items = list
        local move_flags = frame_options.move_flags(list)       -- Move Left / Right in the item's menu, among the visible pins
        local rows = {}
        for i, it in ipairs(list) do
            local win_title = ""
            local win_thumb = ""
            local has_thumb = false
            if #it.wins > 0 then
                for _, w in ipairs(env.wins()) do
                    if w.id == it.wins[1] then
                        win_title = w.title or ""
                        break
                    end
                end
                local sid = tostring(it.wins[1])
                local t = thumbnails_by_id[sid]
                if not t then
                    local w_app = lower(it.app_id or (it.entry and it.entry.id) or "")
                    for _, cand in ipairs(thumbnails_list) do
                        if cand.title == win_title or lower(cand.app or "") == w_app then
                            t = cand
                            break
                        end
                    end
                end
                if t and t.picture and t.picture ~= "" then
                    win_thumb = t.picture
                    has_thumb = true
                end
            end
            rows[i] = {
                icon = it.icon,
                name = it.name,
                running = #it.wins > 0,
                pinned = it.pinned,
                sep = (not it.pinned) and i > 1 and list[i - 1].pinned,
                canpin = it.entry ~= nil or it.cmd ~= nil or it.pid ~= nil,
                mvl = move_flags[i].left,
                mvr = move_flags[i].right,
                preview_thumb = win_thumb,
                preview_title = (win_title ~= "") and win_title or it.name,
                preview_has = has_thumb,
            }
        end
        model.dock_items = rows
    end

    on("dock_hover", function(idx)
        local i = tonumber(idx) or -1
        hovered_dock_idx = i
        local it = items[i + 1]
        if it and #it.wins > 0 then
            local sid = tostring(it.wins[1])
            pcall(sys.call, "thumbnails.want", { sid })
            if build_dock then build_dock() end
        end
    end)

    on("dock_unhover", function()
        hovered_dock_idx = -1
        pcall(sys.call, "thumbnails.want")
    end)

    local function launch(entry)
        local exec = (entry.exec or ""):gsub("%%[%a%%]", ""):gsub("%s+$", "")
        if exec ~= "" then
            pcall(sys.call, "apps.launch", exec)
        end
    end

    on("dock_click", function(i)
        local it = items[(i or 0) + 1]
        if not it then
            return
        end
        if #it.wins > 0 then
            run("niri", { "msg", "action", "focus-window", "--id", tostring(it.wins[1]) }, nil, { output = false })
        elseif it.entry then
            launch(it.entry)
        elseif it.cmd and it.cmd ~= "" then
            run("sh", { "-c", "setsid -f " .. it.cmd .. " >/dev/null 2>&1" }, nil, { output = false })
        end
    end)

    on("dock_pin", function(i)
        local it = items[(i or 0) + 1]
        if not it then
            return
        end
        if not it.entry then
            if it.cmd then            -- unpin an app we pinned by its window
                local out = {}
                for _, id in ipairs(pinned or default_pins()) do
                    if id ~= it.pinstr then out[#out + 1] = id end
                end
                save_pins(out)
                build_dock()
            elseif it.pid then        -- pin: learn the command line from /proc
                local aid = it.app_id
                run("sh", { "-c", 'P=/proc/' .. tostring(it.pid) .. '; ID="$1"; for d in "$HOME/.local/share/applications" /usr/local/share/applications /usr/share/applications; do f="$d/$ID.desktop"; if [ -f "$f" ]; then C=$(sed -n "s/^Exec=//p" "$f" | head -1 | sed "s/ *%[a-zA-Z]//g"); [ -n "$C" ] && { echo "$C"; exit 0; }; fi; done; A=$(tr "\\0" "\\n" < $P/environ 2>/dev/null | sed -n "s/^APPIMAGE=//p" | head -1); if [ -n "$A" ]; then echo "$A"; else tr "\\0" " " < $P/cmdline; fi', "x", aid }, function(out)
                    local cmd = (out or ""):gsub("%s+$", ""):gsub("[\n|]", " ")
                    if cmd == "" then return end
                    local list = {}
                    for _, id in ipairs(pinned or default_pins()) do list[#list + 1] = id end
                    list[#list + 1] = "app:" .. aid .. "|" .. cmd
                    save_pins(list)
                    build_dock()
                end)
            end
            return
        end
        local current = {}
        for _, id in ipairs(pinned or default_pins()) do
            current[#current + 1] = id
        end
        local out, found = {}, false
        for _, id in ipairs(current) do
            if lower(id) == lower(it.entry.id) then
                found = true               -- unpin: leave it out
            else
                out[#out + 1] = id
            end
        end
        if not found then
            out[#out + 1] = it.entry.id    -- pin
        end
        save_pins(out)
        build_dock()
    end)

    -- Reorder the pinned apps one step. `dock_move_pin(id, direction)`: id is the dock's item index (0-based, like
    -- `dock_click`) or a pin string already in the list; direction < 0 left, > 0 right. Only two existing entries swap places
    -- (see frame_options.plan_move): nothing in the event is ever written to the file or run. The order is saved shortly after
    -- the LAST move of a burst; the running-only apps are not part of it.
    local PIN_SAVE_MS = 600

    -- The answer to `request_dock_pins`, and the one that follows every move: the pinned apps the dock shows, in dock order
    -- (frame_options.snapshot: index = the id `dock_move_pin` takes, a command-free pin label, a bounded name, can it move).
    -- Settings declares `set_dock_pins`; until it does the emit is a harmless miss.
    local function send_dock_pins()
        pcall(emit, "Settings.set_dock_pins", frame_options.snapshot(items))
    end
    on("request_dock_pins", send_dock_pins)

    on("dock_move_pin", function(p)
        local id, dir = frame_options.parse_move(p)
        if id == nil then
            return
        end
        local pins = pinned or default_pins()
        local out = frame_options.plan_move(items, pins, id, dir)
        if not out then
            return
        end
        pinned = out
        pins_gen = pins_gen + 1
        build_dock()
        if pin_save_timer then
            cancel(pin_save_timer)
        end
        pin_save_timer = after(PIN_SAVE_MS, flush_pins)
        send_dock_pins()
    end)

    on("dock_quit", function(i)
        local it = items[(i or 0) + 1]
        if not it then
            return
        end
        for _, wid in ipairs(it.wins) do
            run("niri", { "msg", "action", "close-window", "--id", tostring(wid) }, nil, { output = false })
        end
    end)

    sys.watch("apps", function(list)
        index_entries(list)
        build_dock()
    end)

    -- ~/.config/beskar/dock, read now and every few seconds so a hand edit shows up
    local function read_pins()
        if pin_save_timer or pin_save_busy then
            return                  -- our own edit is not on disk yet: the file is older than what the dock shows
        end
        local gen = pins_gen
        run("sh", { "-c", 'if [ -f "$HOME/.config/beskar/dock" ]; then cat "$HOME/.config/beskar/dock"; else echo "__none__"; fi' }, function(out, code)
            if code ~= 0 or not out or gen ~= pins_gen or pin_save_timer or pin_save_busy then
                return
            end
            pins_ready = true
            local list, none = {}, false
            for line in out:gmatch("[^\n]+") do
                if line == "__none__" then
                    none = true
                elseif line:match("%S") then
                    list[#list + 1] = line:gsub("^%s+", ""):gsub("%s+$", "")
                end
            end
            local new = (not none) and list or nil
            local same = (new == nil and pinned == nil)
            if new and pinned and #new == #pinned then
                same = true
                for k = 1, #new do
                    if new[k] ~= pinned[k] then same = false end
                end
            end
            if not same then
                pinned = new
                build_dock()
            end
        end)
    end
    read_pins()
    every(15000, read_pins)

    return { build_dock = build_dock, entry_for = entry_for, name_of = name_of, pretty_app = pretty_app, lower = lower }
end
