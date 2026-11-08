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

local function show_title(idx)
    local w = window_list[(tonumber(idx) or tonumber(fact.sel) or 0) + 1]
    text.sel_title = w and w.title or ""
end
on("fact:sel", function(v) show_title(v) end)

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
        model.wins = window_list
        request_visible_thumbnails()
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
        model.wins = wins
        request_visible_thumbnails()

        -- the first press goes to the previous window (current one is first)
        local first = (#wins > 1) and 1 or 0
        fact.sel = first
        show_title(first)
    end)
end

on("fact:open", function(v)
    if v == true or v == 1 then
        refresh_windows()
    else
        pcall(sys.call, "thumbnails.want") -- stop asking when closed
    end
end)

on("next_app", function()
    local count = #window_list
    if count > 0 then
        fact.sel = (fact.sel + 1) % count
    end
end)

on("prev_app", function()
    local count = #window_list
    if count > 0 then
        fact.sel = (fact.sel - 1 + count) % count
    end
end)

on("switch_to", function(idx)
    fact.open = false
    pcall(sys.call, "thumbnails.want")
    local i = tonumber(idx) or fact.sel or 0
    local target = window_list[i + 1]
    if target and target.id then
        run("niri", { "msg", "action", "focus-window", "--id", tostring(target.id) }, nil, { output = false })
    end
end)
