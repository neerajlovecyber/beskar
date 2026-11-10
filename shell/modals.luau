-- Modals (app switcher, window overview, capture picker): ONE scene (modals.plm), one logic; the shared core is
-- modalcore.luau. Each part is its own function (own locals). The apps / thumbnails services are watched ONCE here and
-- handed to every part that asks (`watch(name, fn)`), so two parts never fight over the one watcher.
local module = require("modalcore")({ switcher = 1, overview = 2, capture = 3 }, "mod_sync")

local watchers, last = {}, {}
local function shared_watch(kind, fn)
    if not watchers[kind] then
        watchers[kind] = {}
        sys.watch(kind, function(v)
            last[kind] = { v }
            for _, f in ipairs(watchers[kind]) do f(v) end
        end)
    end
    table.insert(watchers[kind], fn)
    if last[kind] then fn(last[kind][1]) end
end

module("switcher", function(opened, closed, shown)
    local watch = shared_watch
    -- App switcher logic: windows from `niri msg -j windows` (most recently used first),
    -- previews from pleamar `thumbnails` service, icons from `apps` service.
    -- Opened by Super+Tab (start.sh appswitcher -> topbar picks monitor with focus).
    -- Tab / arrows move selection, Enter or click focuses window, Esc closes.

    local window_list = {}
    local by_key = {}
    local thumbnails_list = {}
    local thumbnails_by_id = {}

    local function lower(s)
        return string.lower(s or "")
    end

    watch("apps", function(list)
        by_key = {}
        for _, e in ipairs(list or {}) do
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
    end)

    local function icon_for(app_id)
        local k = lower(app_id)
        local e = by_key[k] or by_key[k:match("([^%.]+)$") or k]
        return (e and e.icon) or k
    end

    local function show_title(idx)
        local w = window_list[(tonumber(idx) or tonumber(fact.sw_sel) or 0) + 1]
        text.sel_title = w and w.title or ""
    end
    on("fact:sw_sel", function(v) show_title(v) end)

    local function focus_secs(w)
        local t = w.focus_timestamp
        if type(t) == "table" then
            return (t.secs or 0) + (t.nanos or 0) / 1e9
        end
        return 0
    end

    local function match_thumbnail(w, used_ids)
        -- 1. Try matching by string ID first (in niri, toplevel identifier is the window ID)
        local sid = tostring(w.id)
        if thumbnails_by_id[sid] and not used_ids[sid] then
            used_ids[sid] = true
            return thumbnails_by_id[sid]
        end
        -- 2. Match by title and app
        local w_title = w.title or ""
        local w_app = lower(w.app_id or "")
        for _, t in ipairs(thumbnails_list) do
            if not used_ids[t.id] then
                if lower(t.app or "") == w_app and (t.title or "") == w_title then
                    used_ids[t.id] = true
                    return t
                end
            end
        end
        -- 3. Match by app only
        for _, t in ipairs(thumbnails_list) do
            if not used_ids[t.id] then
                if lower(t.app or "") == w_app then
                    used_ids[t.id] = true
                    return t
                end
            end
        end
        return nil
    end

    local function request_visible_thumbnails()
        local want_ids = {}
        for _, w in ipairs(window_list) do
            if w.thumb_id and w.thumb_id ~= "" then
                table.insert(want_ids, w.thumb_id)
            end
        end
        if #want_ids > 0 then
            pcall(sys.call, "thumbnails.want", want_ids)
        end
    end

    local function update_window_thumbs()
        if #window_list == 0 then return end
        local used_ids = {}
        local changed = false
        for _, w in ipairs(window_list) do
            local t = match_thumbnail(w, used_ids)
            local pic = (t and t.picture) or ""
            local thumb_id = (t and t.id) or tostring(w.id)
            local has = (pic ~= "")
            if w.thumb ~= pic or w.has_thumb ~= has or w.thumb_id ~= thumb_id then
                w.thumb = pic
                w.has_thumb = has
                w.thumb_id = thumb_id
                changed = true
            end
        end
        if changed then
            model.sw_wins = window_list
            request_visible_thumbnails()
        end
    end

    watch("thumbnails", function(info)
        thumbnails_list = (info and info.list) or {}
        thumbnails_by_id = {}
        for _, t in ipairs(thumbnails_list) do
            if t.id and t.id ~= "" then
                thumbnails_by_id[t.id] = t
            end
        end
        if shown() then
            update_window_thumbs()
        end
    end)

    local function refresh_windows()
        run("niri", { "msg", "-j", "windows" }, function(out)
            local ok, all = pcall(json.decode, out or "")
            if not ok or type(all) ~= "table" then
                return
            end
            local wins = {}
            for _, w in ipairs(all) do
                local app = w.app_id or ""
                if app ~= "" and app ~= "pleamar" then
                    wins[#wins + 1] = {
                        id = w.id,
                        title = w.title or "",
                        app_id = app,
                        icon = icon_for(app),
                        t = focus_secs(w),
                        thumb = "",
                        has_thumb = false,
                        thumb_id = tostring(w.id),
                    }
                end
            end
            table.sort(wins, function(a, b) return a.t > b.t end) -- most recent first
            while #wins > 7 do
                table.remove(wins)
            end

            local used_ids = {}
            for _, w in ipairs(wins) do
                local t = match_thumbnail(w, used_ids)
                if t then
                    w.thumb_id = t.id
                    w.thumb = t.picture or ""
                    w.has_thumb = (w.thumb ~= "")
                end
            end

            window_list = wins
            model.sw_wins = wins
            request_visible_thumbnails()

            -- the first press goes to the previous window (current one is first)
            local first = (#wins > 1) and 1 or 0
            fact.sw_sel = first
            show_title(first)
        end)
    end

    opened(refresh_windows)
    closed(function() pcall(sys.call, "thumbnails.want") end)      -- stop asking when closed

    on("next_app", function()
        local count = #window_list
        if count > 0 then
            fact.sw_sel = (fact.sw_sel + 1) % count
        end
    end)

    on("prev_app", function()
        local count = #window_list
        if count > 0 then
            fact.sw_sel = (fact.sw_sel - 1 + count) % count
        end
    end)

    on("sw_switch_to", function(idx)
        fact.open = false
        pcall(sys.call, "thumbnails.want")
        local i = tonumber(idx) or fact.sw_sel or 0
        local target = window_list[i + 1]
        if target and target.id then
            run("niri", { "msg", "action", "focus-window", "--id", tostring(target.id) }, nil, { output = false })
        end
    end)
end)

module("overview", function(opened, closed, shown)
    local watch = shared_watch
    -- macOS Window Overview (Mission Control HUD) logic
    -- Lists all windows of ALL workspaces as large previews using pleamar `thumbnails` service.
    -- Opened via start.sh overview -> topbar opens panel 10 on the monitor with focus.
    -- Click or Return focuses the selected window, Esc closes, arrow keys navigate the grid.


    local window_list = {}
    local by_key = {}
    local thumbnails_list = {}
    local thumbnails_by_id = {}

    local function lower(s)
        return string.lower(s or "")
    end

    watch("apps", function(list)
        by_key = {}
        for _, e in ipairs(list or {}) do
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
    end)

    local function icon_for(app_id)
        local k = lower(app_id)
        local e = by_key[k] or by_key[k:match("([^%.]+)$") or k]
        return (e and e.icon) or k
    end

    local function focus_secs(w)
        local t = w.focus_timestamp
        if type(t) == "table" then
            return (t.secs or 0) + (t.nanos or 0) / 1e9
        end
        return 0
    end

    local function match_thumbnail(w, used_ids)
        local sid = tostring(w.id)
        if thumbnails_by_id[sid] and not used_ids[sid] then
            used_ids[sid] = true
            return thumbnails_by_id[sid]
        end
        local w_title = w.title or ""
        local w_app = lower(w.app_id or "")
        for _, t in ipairs(thumbnails_list) do
            if not used_ids[t.id] then
                if lower(t.app or "") == w_app and (t.title or "") == w_title then
                    used_ids[t.id] = true
                    return t
                end
            end
        end
        for _, t in ipairs(thumbnails_list) do
            if not used_ids[t.id] then
                if lower(t.app or "") == w_app then
                    used_ids[t.id] = true
                    return t
                end
            end
        end
        return nil
    end

    local function request_live_thumbnails()
        local live_ids = {}
        for _, w in ipairs(window_list) do
            if w.thumb_id and w.thumb_id ~= "" then
                table.insert(live_ids, w.thumb_id)
            end
        end
        if #live_ids > 0 then
            pcall(sys.call, "thumbnails.live", live_ids)
        end
    end

    local function update_window_thumbs()
        if #window_list == 0 then return end
        local used_ids = {}
        local changed = false
        for _, w in ipairs(window_list) do
            local t = match_thumbnail(w, used_ids)
            local pic = (t and t.picture) or ""
            local thumb_id = (t and t.id) or tostring(w.id)
            local has = (pic ~= "")
            if w.thumb ~= pic or w.has_thumb ~= has or w.thumb_id ~= thumb_id then
                w.thumb = pic
                w.has_thumb = has
                w.thumb_id = thumb_id
                changed = true
            end
        end
        if changed then
            model.ov_wins = window_list
            request_live_thumbnails()
        end
    end

    watch("thumbnails", function(info)
        thumbnails_list = (info and info.list) or {}
        thumbnails_by_id = {}
        for _, t in ipairs(thumbnails_list) do
            if t.id and t.id ~= "" then
                thumbnails_by_id[t.id] = t
            end
        end
        if shown() then
            update_window_thumbs()
        end
    end)

    local function refresh_windows()
        run("niri", { "msg", "-j", "windows" }, function(out)
            local ok, all = pcall(json.decode, out or "")
            if not ok or type(all) ~= "table" then
                return
            end
            local wins = {}
            for _, w in ipairs(all) do
                local app = w.app_id or ""
                if app ~= "" and app ~= "pleamar" then
                    local ws_num = tonumber(w.workspace_id) or 0
                    wins[#wins + 1] = {
                        id = w.id,
                        title = w.title or "",
                        app_id = app,
                        ws = ws_num,
                        ws_label = ws_num > 0 and ("WS " .. tostring(ws_num)) or "",
                        icon = icon_for(app),
                        t = focus_secs(w),
                        thumb = "",
                        has_thumb = false,
                        thumb_id = tostring(w.id),
                    }
                end
            end
            -- Sort: all workspaces, most recent first
            table.sort(wins, function(a, b) return a.t > b.t end)
            while #wins > 16 do
                table.remove(wins)
            end

            local used_ids = {}
            for _, w in ipairs(wins) do
                local t = match_thumbnail(w, used_ids)
                if t then
                    w.thumb_id = t.id
                    w.thumb = t.picture or ""
                    w.has_thumb = (w.thumb ~= "")
                end
            end

            window_list = wins
            model.ov_wins = wins
            text.win_count_text = string.format("%d %s", #wins, #wins == 1 and "window" or "windows")

            fact.ov_sel = 0
            request_live_thumbnails()
        end)
    end

    opened(refresh_windows)
    closed(function() pcall(sys.call, "thumbnails.live") end)      -- stop asking when closed

    local COLS = 4

    on("next_win", function()
        local count = #window_list
        if count > 0 then
            fact.ov_sel = (fact.ov_sel + 1) % count
        end
    end)

    on("prev_win", function()
        local count = #window_list
        if count > 0 then
            fact.ov_sel = (fact.ov_sel - 1 + count) % count
        end
    end)

    on("down_win", function()
        local count = #window_list
        if count > 0 then
            local target = fact.ov_sel + COLS
            if target < count then
                fact.ov_sel = target
            end
        end
    end)

    on("up_win", function()
        local count = #window_list
        if count > 0 then
            local target = fact.ov_sel - COLS
            if target >= 0 then
                fact.ov_sel = target
            end
        end
    end)

    on("ov_switch_to", function(idx)
        fact.open = false
        pcall(sys.call, "thumbnails.live")
        local i = tonumber(idx) or fact.ov_sel or 0
        local target = window_list[i + 1]
        if target and target.id then
            run("niri", { "msg", "action", "focus-window", "--id", tostring(target.id) }, nil, { output = false })
        end
    end)
end)

module("capture", function(opened, closed, shown)
    local watch = shared_watch
    -- Screen capture and recording. The sandbox has no `os.execute`: everything goes through `run` / `spawn`.
    --   still    grim (whole screen of the focused monitor, or a region from slurp) → file + clipboard
    --   window   niri's own screenshot of the focused window (it saves and copies it itself)
    --   record   wf-recorder on the focused monitor; the top bar shows a red dot and the time while it runs
    --            (topbar.plm `rec_on`, `rec_time`), and a click there stops it

    local rec_running = false
    local rec_file = nil
    local timer_id = nil
    local secs = 0

    local function to_topbar(words)
        pcall(sys.call, "say", "topbar", words)
    end

    local function notify(title, body, icon)
        run("notify-send", { "-a", "Screen Capture", "-i", icon or "camera-photo", title, body }, nil, { output = false })
    end

    local function stamp()
        return os.date("%Y-%m-%d_%H-%M-%S")
    end

    -- the monitor with the focus, as grim / wf-recorder name it ("" if niri does not say)
    local function focused_output(cb)
        run("niri", { "msg", "-j", "focused-output" }, function(out)
            local ok, o = pcall(json.decode, out or "")
            cb((ok and type(o) == "table" and o.name) or "")
        end)
    end

    -- a directory under $HOME made on demand; the callback gets the full path
    local function dir_of(sub, cb)
        run("sh", { "-c", 'd="$HOME/$1"; mkdir -p "$d" && printf %s "$d"', "x", sub }, function(out, code)
            if code == 0 and out and out ~= "" then
                cb(out)
            else
                notify("Capture failed", "Could not create " .. sub, "dialog-error")
            end
        end)
    end

    local function finish_still(file, title)
        run("sh", { "-c", 'wl-copy --type image/png < "$1"', "x", file }, nil, { output = false })
        to_topbar("text shot_path " .. file)
    end

    -- the monitor with the focus: name and where it sits in the global layout
    local function focused_info(cb)
        run("niri", { "msg", "-j", "focused-output" }, function(out)
            local ok, o = pcall(json.decode, out or "")
            if ok and type(o) == "table" then
                local l = o.logical or {}
                cb(o.name or "", l.x or 0, l.y or 0, l.width or 0)
            else
                cb("", 0, 0, 0)
            end
        end)
    end

    local frozen = nil      -- the picture shown behind the picker
    local frozen_out = nil  -- its monitor, and where that monitor sits (for recording a region)
    local frozen_x, frozen_y, frozen_w = 0, 0, 0

    local function drop_frozen()
        if frozen then
            run("rm", { "-f", frozen }, nil, { output = false })
            frozen = nil
        end
    end

    local function still_name(cb)
        dir_of("Pictures/Screenshots", function(dir)
            cb(string.format("%s/Screen_Shot_%s.png", dir, stamp()))
        end)
    end

    local do_screen_fn, do_window_fn, do_region_fn

    local function stop_recording()
        if timer_id then
            cancel(timer_id)
            timer_id = nil
        end
        rec_running = false
        fact.recording = false
        to_topbar("fact rec_on false")
        run("pkill", { "-INT", "-x", "wf-recorder" }, nil, { output = false })
    end

    local function clock(sec)
        return string.format("%d:%02d", sec // 60, sec % 60)
    end

    local function tick()
        if not rec_running then
            return
        end
        secs = secs + 1
        fact.record_secs = secs
        to_topbar("text rec_time " .. clock(secs))
        timer_id = after(1000, tick)
    end


    local function start_recording(geom)
        dir_of("Videos/Captures", function(dir)
            local file = string.format("%s/Screen_Recording_%s.mp4", dir, stamp())
            local args = {}
            if geom then
                args = { "-g", geom, "-f", file }
            elseif frozen_out and frozen_out ~= "" then
                args = { "-o", frozen_out, "-f", file }
            else
                args = { "-f", file }
            end
            rec_file = file
            rec_running = true
            secs = 0
            fact.recording = true
            fact.record_secs = 0
            to_topbar("text rec_time 0:00")
            to_topbar("fact rec_on true")
            spawn("wf-recorder", args, function() end, function(_, code)
                local was = rec_running
                if timer_id then
                    cancel(timer_id)
                    timer_id = nil
                end
                rec_running = false
                fact.recording = false
                to_topbar("fact rec_on false")
                if was then
                    notify("Recording failed", "wf-recorder stopped unexpectedly", "dialog-error")
                else
                    notify("Recording saved", "Videos/Captures", "video-x-generic")
                end
            end)
            timer_id = after(1000, tick)
        end)
    end

    -- open the picker: the screen is frozen first, so what you select is what you saw
    on("cap_toggle", function()
        if shown() then
            fact.open = false
            return
        end
        if rec_running then
            stop_recording()
            return
        end
        focused_info(function(name, lx, ly, lw)
            local file = string.format("/tmp/beskar-cap-%d.png", os.time())
            local args = name ~= "" and { "-o", name, file } or { file }
            run("grim", args, function(_, code)
                if code ~= 0 then
                    notify("Screenshot failed", "grim could not capture the screen", "dialog-error")
                    return
                end
                drop_frozen()
                frozen, frozen_out, frozen_x, frozen_y, frozen_w = file, name, lx, ly, lw
                text.shot_path = file
                fact.has_sel = false
                fact.sel_w = 0
                fact.sel_h = 0
                after(120, function() fact.cur = 3; fact.open = true end)
            end)
        end)
    end)

    do_screen_fn = function()
        fact.open = false
        local k = fact.kind or 0
        after(350, function()
            if k == 1 then
                start_recording(nil)
            elseif frozen then
                still_name(function(dest)
                    run("cp", { frozen, dest }, function(_, code)
                        if code == 0 then finish_still(dest, "Screenshot taken") end
                    end)
                end)
            end
        end)
    end
    on("do_screen", do_screen_fn)

    -- A screenshot of the whole monitor WITH the shell (grim sees every layer; niri's own screenshot-window draws the
    -- window alone, without the bar, ring and dock). No picker: Ctrl+Print / Alt+Print and the picker's Window mode.
    local function shot_now()
        focused_info(function(name)
            still_name(function(dest)
                local args = name ~= "" and { "-o", name, dest } or { dest }
                run("grim", args, function(_, code)
                    if code == 0 then
                        finish_still(dest, "Screenshot taken")
                    else
                        notify("Screenshot failed", "grim could not capture the screen", "dialog-error")
                    end
                end)
            end)
        end)
    end
    on("shot_now", shot_now)

    do_window_fn = function()
        fact.open = false
        local k = fact.kind or 0
        after(350, function()
            if k == 1 then
                start_recording(nil)
            else
                shot_now()
            end
        end)
    end
    on("do_window", do_window_fn)

    local region_busy = false
    do_region_fn = function()
        local x, y = math.floor(fact.sel_x or 0), math.floor(fact.sel_y or 0)
        local w, h = math.floor(fact.sel_w or 0), math.floor(fact.sel_h or 0)
        -- the monitor's logical width, known from niri (a key press cannot read `screen.width` in the scene: it is 0 there)
        local sw = frozen_w > 0 and frozen_w or math.floor(fact.scr_w or 0)
        if sw <= 0 then sw = 1920 end
        if region_busy then return end            -- one press can arrive from every copy of the surface
        region_busy = true
        after(1500, function() region_busy = false end)
        local k = fact.kind or 0
        fact.open = false
        if w < 4 or h < 4 then return end
        if k == 1 then
            local geom = string.format("%d,%d %dx%d", x + frozen_x, y + frozen_y, w, h)
            after(350, function() start_recording(geom) end)
            return
        end
        if not frozen then return end
        still_name(function(dest)
            local script = 'f="$1"; out="$2"; iw=$(magick identify -format %w "$f"); '
                .. 'magick "$f" -crop "$(($5*iw/$7))x$(($6*iw/$7))+$(($3*iw/$7))+$(($4*iw/$7))" +repage "$out"'
            run("sh", { "-c", script, "x", frozen, dest, tostring(x), tostring(y), tostring(w), tostring(h), tostring(sw) },
                function(_, code)
                    if code == 0 then
                        finish_still(dest, "Screenshot taken")
                    else
                        notify("Screenshot failed", "could not crop the picture", "dialog-error")
                    end
                end)
        end)
    end
    on("do_region", do_region_fn)

    -- Enter: take what the picker is set up for (a selected region, the focused window, or the whole screen)
    on("confirm", function()
        local mode = fact.mode or 0
        if mode == 1 then
            do_window_fn()
        elseif mode == 2 then
            do_screen_fn()
        elseif fact.has_sel == true then
            do_region_fn()
        end
    end)

    on("toggle_record", function()
        if rec_running then
            stop_recording()
        end
    end)
end)

-- opening one closes the other panels (Spotlight, Control Center …)
require("exclusive")("modals")
