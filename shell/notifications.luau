-- Notification centre logic, after Marea's: this logic is the receiver of the desktop's notifications.
--
--   · what arrives is KEPT until somebody deals with it (`notifications.keep`): a centre is not a bar of
--     bubbles, so a notification that asks to expire after 5 s does not vanish before you open it
--   · what is dealt with — dismissed here, cleared, or closed by its own application — goes to a history,
--     newest first, and to disk (`history.json`), so a restart does not wash it away
--   · the top bar's bell is told how many are waiting

local panel = require("panel")("notifications")   -- the frame draws the glass: tell it the height
local MAX_LIVE = 6          -- cards in the centre
local MAX_PAST = 5          -- rows of history shown
local KEEP_PAST = 100       -- rows of history kept on disk

-- ── how long ago ─────────────────────────────────────────────────
local function age_of(t)
    if not t or t <= 0 then
        return "now"
    end
    local s = os.time() - t
    if s < 60 then return "now" end
    if s < 3600 then return string.format("%d min", s // 60) end
    if s < 86400 then return string.format("%d h", s // 3600) end
    return os.date("%d/%m", t)
end

-- ── history, on disk ─────────────────────────────────────────────
local history = {}
do
    local ok, loaded = pcall(sys.ask, "files.read", "history.json", "json")
    if ok and type(loaded) == "table" and type(loaded.items) == "table" then
        history = loaded.items
    end
end

local saving = false
local function save_history()
    if saving then
        return
    end
    saving = true
    after(1000, function()
        saving = false
        pcall(sys.call, "files.write", "history.json", { items = history })
    end)
end

-- A body may hold line breaks and blank lines ("www.instagram.com\n\nYou have unseen notifications"): the card
-- has room for two lines, so it is flattened to one run of text.
local function flat(s)
    return ((s or ""):gsub("%s*[\r\n]+%s*", " "):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", ""))
end

local live = {}             -- id -> record, as the service gave it
local order = {}            -- ids, newest first
local expanded = {}         -- app -> true while its stack is open
local group_apps = {}       -- key -> app, as of the last paint (the buttons send a key)
local group_ids = {}        -- key -> the ids of that app's notifications

local ROW_CARD, ROW_STACK, ROW_HEAD = 100, 112, 32
local MAX_ROWS = 14

local function row_of(n, kind, key, h, age)
    return {
        kind = kind, key = key, id = n.id, app = n.app or "", title = n.title or "", body = flat(n.body),
        icon = n.icon or "", age = age or age_of(n.time), h = h,
    }
end

local function paint()
    -- waiting, for the banner (the newest first)
    local top = {}
    for _, id in ipairs(order) do
        local n = live[id]
        if n and #top < MAX_LIVE then
            top[#top + 1] = {
                id = n.id, app = n.app or "", title = n.title or "", body = flat(n.body),
                icon = n.icon or "", age = age_of(n.time),
            }
        end
    end
    model.notices = top

    -- waiting, for the centre: grouped by app, in the order of each app's newest notification
    local groups, by_app = {}, {}
    for _, id in ipairs(order) do
        local n = live[id]
        if n then
            local app = n.app or ""
            local g = by_app[app]
            if not g then
                g = { app = app, items = {} }
                by_app[app] = g
                groups[#groups + 1] = g
            end
            g.items[#g.items + 1] = n
        end
    end
    group_apps, group_ids = {}, {}
    local rows, live_h = {}, 0
    local function add(r)
        if #rows < MAX_ROWS then
            rows[#rows + 1] = r
            live_h = live_h + r.h
        end
    end
    for key, g in ipairs(groups) do
        group_apps[key] = g.app
        group_ids[key] = {}
        for i, n in ipairs(g.items) do
            group_ids[key][i] = n.id
        end
        local k = key - 1                                  -- keys count from 0 in the scene
        if #g.items == 1 or fact.group_apps ~= true then
            -- a plain list: every notification is its own card
            for _, n in ipairs(g.items) do
                add(row_of(n, 0, k, ROW_CARD))
            end
        elseif false then
            add(row_of(g.items[1], 0, k, ROW_CARD))
        elseif expanded[g.app] then
            add({ kind = 2, key = k, id = 0, app = g.app ~= "" and g.app or "Notifications", title = "", body = "", icon = "", age = "", h = ROW_HEAD })
            for _, n in ipairs(g.items) do
                add(row_of(n, 0, k, ROW_CARD))
            end
        else
            local n = g.items[1]
            add(row_of(n, 1, k, ROW_STACK, age_of(n.time) .. "  +" .. (#g.items - 1)))
        end
    end
    model.rows = rows
    fact.live_h = live_h

    -- earlier: as many as fit under the waiting ones
    local room = math.floor((800 - 70 - live_h - 60) / 58)
    local count = math.max(0, math.min(MAX_PAST, room, #history))
    local past = {}
    for k = 1, count do
        local h = history[k]
        past[k] = { title = h.title or "", body = flat(h.body), icon = h.icon or "", age = age_of(h.time) }
    end
    model.past = past

    -- how tall the card is: header, the waiting rows (or the empty message), the Earlier rows
    local height
    if #rows < 1 and #past < 1 then
        height = 190
    else
        height = 70 + (#rows > 0 and live_h or (#past > 0 and 0 or 100)) + (#past > 0 and (44 + #past * 58) or 0) + 8
    end
    panel.height(height)

    -- the bell
    pcall(sys.call, "say", "topbar", "fact notif_count " .. tostring(#order))
    pcall(sys.call, "say", "lock", "fact notif_count " .. tostring(#order))        -- the lock screen shows how many, never what
end

local function remember(n)
    table.insert(history, 1, {
        app = n.app, title = n.title, body = n.body, icon = n.icon, time = n.time or os.time(),
    })
    while #history > KEEP_PAST do
        table.remove(history)
    end
    save_history()
end

-- ── the banner: a new notification is shown inside the centre pill for a few seconds ──────────
-- The frame draws the glass (it reports to topbar.luau with panel_open 7); the card is drawn by the `banner` surface
-- of this scene. Hover keeps it up; a click opens the centre; Do Not Disturb or an open centre keep it away.
local BANNER_MS = 5500
local BANNER_ID = 7
local banner_timer = nil
local banner_visible = false

local function to_topbar(words)
    pcall(sys.call, "say", "topbar", words)
end

local function banner_hide()
    if banner_timer then
        cancel(banner_timer)
        banner_timer = nil
    end
    if banner_visible then
        banner_visible = false
        fact.banner_on = false
        to_topbar("emit panel_close " .. BANNER_ID)
    end
end

local function arm_banner()
    if banner_timer then
        cancel(banner_timer)
    end
    banner_timer = after(tonumber(fact.banner_ms) or BANNER_MS, function()
        banner_timer = nil
        if fact.banner_hover == true then
            arm_banner()               -- the pointer is on it: wait a little longer
        else
            banner_hide()
        end
    end)
end

local function banner_show()
    if fact.dnd == true or fact.open == true or fact.banners == false then
        return
    end
    if not banner_visible then
        banner_visible = true
        fact.banner_on = true
        to_topbar("emit panel_open " .. BANNER_ID)
        to_topbar("emit panel_height " .. (BANNER_ID * 10000 + 58))
    end
    arm_banner()
end

-- the frame may refuse (a panel owns the centre island) and turns `banner_on` off itself
on("fact:banner_on", function(v)
    if not (v == true or v == 1) then
        banner_visible = false
        if banner_timer then
            cancel(banner_timer)
            banner_timer = nil
        end
    end
end)

-- opening the centre hides the banner; a click on the banner opens the centre
on("fact:open", function(v)
    if v == true or v == 1 then
        banner_hide()
    end
end)
on("card_click", function()
    if fact.open == true then
        return
    end
    banner_hide()
    to_topbar("emit open_notifications")
end)

local first_list = true

sys.watch("notifications", function(list)
    local present = {}
    local fresh = {}
    for _, n in ipairs(list or {}) do         -- newest first
        present[n.id] = true
        if not live[n.id] then
            fresh[#fresh + 1] = n
        end
        live[n.id] = n
    end
    -- gone: dismissed here, or closed by the application that sent it
    for id, n in pairs(live) do
        if not present[id] then
            remember(n)
            live[id] = nil
        end
    end
    local ids = {}
    for _, n in ipairs(list or {}) do
        ids[#ids + 1] = n.id
    end
    order = ids
    paint()
    if first_list then
        first_list = false               -- what was already waiting when we started is not news
    elseif #fresh > 0 then
        local show_b = false
        for _, n in ipairs(fresh) do
            if n.app ~= "Timer" then
                show_b = true
                break
            end
        end
        if show_b then
            banner_show()
        end
    end
end)

-- Keep what arrives until somebody decides (see the top of the file).
local ok, err = pcall(sys.call, "notifications.keep", true)
if not ok then
    log("notifications.keep ·", err)
end

-- ── buttons ──────────────────────────────────────────────────────
on("dismiss_notice", function(id)
    if id then
        pcall(sys.call, "notifications.dismiss", id)
    end
end)

on("fact:group_apps", paint)
on("group_toggle", function(key)
    local app = group_apps[(tonumber(key) or -1) + 1]
    if app ~= nil then
        expanded[app] = not expanded[app] or nil
        paint()
    end
end)

on("dismiss_group", function(key)
    for _, id in ipairs(group_ids[(tonumber(key) or -1) + 1] or {}) do
        pcall(sys.call, "notifications.dismiss", id)
    end
end)

on("clear_notices", function()
    pcall(sys.call, "notifications.clear")
end)

on("clear_past", function()
    history = {}
    save_history()
    paint()
end)

-- Ages move on; and the bell has to hear again if the top bar was restarted.
every(30000, paint)

-- one panel at a time
require("exclusive")("notifications")
