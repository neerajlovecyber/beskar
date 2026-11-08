-- macOS Window Overview (Mission Control HUD) logic
-- Lists all windows of ALL workspaces as large previews using pleamar `thumbnails` service.
-- Opened via start.sh overview -> topbar opens panel 10 on the monitor with focus.
-- Click or Return focuses the selected window, Esc closes, arrow keys navigate the grid.

require("exclusive")("overview")

local window_list = {}
local by_key = {}
local thumbnails_list = {}
local thumbnails_by_id = {}

local function lower(s)
    return string.lower(s or "")
end

sys.watch("apps", function(list)
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
        model.wins = window_list
        request_live_thumbnails()
    end
end

sys.watch("thumbnails", function(info)
    thumbnails_list = (info and info.list) or {}
    thumbnails_by_id = {}
    for _, t in ipairs(thumbnails_list) do
        if t.id and t.id ~= "" then
            thumbnails_by_id[t.id] = t
        end
    end
    if fact.open == true or fact.open == 1 then
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
        model.wins = wins
        text.win_count_text = string.format("%d %s", #wins, #wins == 1 and "window" or "windows")

        fact.sel = 0
        request_live_thumbnails()
    end)
end

on("fact:open", function(v)
    if v == true or v == 1 then
        refresh_windows()
    else
        pcall(sys.call, "thumbnails.live") -- stop asking when closed
    end
end)

local COLS = 4

on("next_win", function()
    local count = #window_list
    if count > 0 then
        fact.sel = (fact.sel + 1) % count
    end
end)

on("prev_win", function()
    local count = #window_list
    if count > 0 then
        fact.sel = (fact.sel - 1 + count) % count
    end
end)

on("down_win", function()
    local count = #window_list
    if count > 0 then
        local target = fact.sel + COLS
        if target < count then
            fact.sel = target
        end
    end
end)

on("up_win", function()
    local count = #window_list
    if count > 0 then
        local target = fact.sel - COLS
        if target >= 0 then
            fact.sel = target
        end
    end
end)

on("switch_to", function(idx)
    fact.open = false
    pcall(sys.call, "thumbnails.live")
    local i = tonumber(idx) or fact.sel or 0
    local target = window_list[i + 1]
    if target and target.id then
        run("niri", { "msg", "action", "focus-window", "--id", tostring(target.id) }, nil, { output = false })
    end
end)
