-- The window panels: app switcher and window overview (windows.plm → common/*_panels.plm).
local Hooks = require("topbar_hooks")        -- the frame cannot emit to itself: its own events are called directly
-- Loaded by topbar.luau with its panel client; the panels' content is drawn in the frame's own surface.
return function(module)

local function close_panel() emit("Panels.close") end

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



module("switcher", function(panel, opened, shown, closed)
    local watch = shared_watch
    -- App switcher logic: windows from `niri msg -j windows` (most recently used first),
    -- previews from pleamar `thumbnails` service, icons from `apps` service.
    -- Opened by Super+Tab (start.sh appswitcher -> topbar picks monitor with focus).
    -- Tab / arrows move selection, Enter or click focuses window, Esc closes.

    local window_list = {}
    local by_key = {}
    local thumbnails_list = {}
    local thumbnails_by_id = {}

    -- the glass (drawn by the frame, out of the dock) is as wide as the strip of cards: 152 each, at least 260
    panel.height(172)
    panel.width(260)
    local function resize_switcher(n)
        panel.width(math.max(260, n * 152 + 32))
    end

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
            resize_switcher(#wins)
            request_visible_thumbnails()

            -- the first press goes to the previous window (current one is first)
            local first = (#wins > 1) and 1 or 0
            fact.sw_sel = first
            show_title(first)
        end)
    end

    opened(refresh_windows)
    closed(function() pcall(sys.call, "thumbnails.want") end)      -- stop asking when closed

    -- (a change made by this very logic does not come back through `on("fact:sw_sel")`: show the title here too)
    local function select_app(i)
        fact.sw_sel = i
        show_title(i)
    end

    on("next_app", function()
        local count = #window_list
        if count > 0 then
            select_app(((tonumber(fact.sw_sel) or 0) + 1) % count)
        end
    end)

    on("prev_app", function()
        local count = #window_list
        if count > 0 then
            select_app(((tonumber(fact.sw_sel) or 0) - 1 + count) % count)
        end
    end)

    on("sw_edge", function(d)
        local count = #window_list
        if count > 0 then
            select_app((tonumber(d) or 0) < 0 and 0 or count - 1)
        end
    end)

    on("sw_switch_to", function(idx)
        close_panel()
        pcall(sys.call, "thumbnails.want")
        local i = tonumber(idx) or fact.sw_sel or 0
        local target = window_list[i + 1]
        if target and target.id then
            run("niri", { "msg", "action", "focus-window", "--id", tostring(target.id) }, nil, { output = false })
        end
    end)
end)


module("overview", function(panel, opened, shown, closed)
    local watch = shared_watch
    -- macOS Window Overview (Mission Control HUD) logic
    -- Lists all windows of ALL workspaces as large previews using pleamar `thumbnails` service.
    -- Opened via start.sh overview -> topbar opens panel 10 on the monitor with focus.
    -- Click or Return focuses the selected window, Esc closes, arrow keys navigate the grid.


    local window_list = {}
    local by_key = {}
    local thumbnails_list = {}
    local thumbnails_by_id = {}

    -- the glass is as wide / tall as the grid (4 columns of 290, rows of 181): same sums as `ov_w` / `ov_h` in windows.plm
    local function resize_overview(n)
        panel.width(math.max(560, 56 + math.min(4, math.max(1, n)) * 290))
        panel.height(math.min(800, 80 + math.max(1, math.ceil(n / 4)) * 181))
    end
    resize_overview(0)

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
            resize_overview(#wins)
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

    -- Down / Up go one row; a short last row is reached by its last window (so Down never "does nothing" on a gap)
    on("down_win", function()
        local count = #window_list
        if count > 0 then
            local sel = tonumber(fact.ov_sel) or 0
            if math.floor(sel / COLS) < math.floor((count - 1) / COLS) then
                fact.ov_sel = math.min(sel + COLS, count - 1)
            end
        end
    end)

    on("up_win", function()
        local count = #window_list
        if count > 0 then
            local target = (tonumber(fact.ov_sel) or 0) - COLS
            if target >= 0 then
                fact.ov_sel = target
            end
        end
    end)

    on("ov_edge", function(d)
        local count = #window_list
        if count > 0 then
            fact.ov_sel = (tonumber(d) or 0) < 0 and 0 or count - 1
        end
    end)

    on("ov_switch_to", function(idx)
        close_panel()
        pcall(sys.call, "thumbnails.live")
        local i = tonumber(idx) or fact.ov_sel or 0
        local target = window_list[i + 1]
        if target and target.id then
            run("niri", { "msg", "action", "focus-window", "--id", tostring(target.id) }, nil, { output = false })
        end
    end)
end)
end
