-- (the body of the notifications scene: notifications.luau runs it as module("notifications", require("notif")))
-- Notification centre logic, after Marea's: this logic is the receiver of the desktop's notifications.
return function(panel, opened, shown, closed)
-- Every handler is also kept in H: the keyboard code at the end calls them directly (this plugin cannot emit to itself).
local base_on = on
local H = {}
local function on(name, fn) H[name] = fn; return base_on(name, fn) end
local refocus = function() end        -- set by the keyboard code at the end: keeps the focus on the same row after a repaint
--
--   · what arrives is KEPT until somebody deals with it (`notifications.keep`): a centre is not a bar of
--     bubbles, so a notification that asks to expire after 5 s does not vanish before you open it
--   · what is dealt with — dismissed here, cleared, or closed by its own application — goes to a history,
--     newest first, and to disk (`history.json`), so a restart does not wash it away
--   · the top bar's bell is told how many are waiting

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

-- ── quiet policy: per-app rules (saved here) and the effective quiet state ───────────────────
-- Pure rules live in quiet_policy.luau. Manual Do Not Disturb stays `fact.dnd` and is never written by a policy: the
-- effective state is `fact.quiet`, derived from manual DND, Activities' explicit modes and Settings' quiet hours.
local Quiet = require("quiet_policy")
local rules, rules_locked = nil, false
local rule_map = {}
do
    local ok, saved = pcall(sys.ask, "files.read", "quiet.json", "json")
    local problem
    if ok then rules, problem = Quiet.rules_new(saved) end
    if not rules then
        rules, rules_locked = Quiet.rules_new(nil), true     -- unreadable: keep the file, accept no changes
        text.rules_status = problem or "Could not read the saved quiet rules. The file has been kept."
    end
    rule_map = Quiet.rule_map(rules)
end

local rules_dirty, rules_timer = false, nil
local function save_rules()
    rules_timer = nil
    if not rules_dirty or rules_locked then return end
    if pcall(sys.call, "files.write", "quiet.json", Quiet.snapshot(rules)) then
        rules_dirty = false
        text.rules_status = ""
    else
        text.rules_status = "Could not save quiet rules. Retrying…"
        rules_timer = after(2000, save_rules)
    end
end
local function queue_save()
    rules_dirty = true
    if rules_timer then cancel(rules_timer) end
    rules_timer = after(400, save_rules)
end

local held = 0               -- banners kept back by quiet state or an app rule since the centre was last opened

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

local ROW_CARD, ROW_STACK, ROW_HEAD = 88, 100, 32
local MAX_ROWS = 16          -- rendered window, not a limit on reachable notifications
local MAX_HEIGHT = 720
local all_rows, scroll, view_h, content_h = {}, 0, 112, 112
local function paint_window()
    local rows = {}
    local top = math.max(0, math.min(scroll, math.max(0, content_h - view_h)))
    for _, r in ipairs(all_rows) do
        if r.y + r.h >= top - 64 and r.y <= top + view_h + 64 and #rows < MAX_ROWS then
            rows[#rows + 1] = r
        end
    end
    model.rows = rows
end
on("list_scrolled", function(offset)
    scroll = math.max(0, tonumber(offset) or 0)
    paint_window()
end)

-- The buttons a notification offers (not its "default" action: a click on the card is that), at most two.
local ROW_ACTIONS = 36
local function buttons_of(n)
    local out = {}
    for _, a in ipairs(type(n.actions) == "table" and n.actions or {}) do
        if type(a) == "table" and a.key ~= "default" and type(a.label) == "string" and a.label ~= "" and #out < 2 then
            out[#out + 1] = a
        end
    end
    return out
end

local function row_of(n, kind, key, h, age)
    local b = kind == 0 and buttons_of(n) or {}
    return {
        kind = kind, key = key, id = n.id, app = n.app or "", title = n.title or "", body = flat(n.body),
        icon = n.icon or "", has_icon = (n.icon or "") ~= "", age = age or age_of(n.time),
        h = h + (#b > 0 and ROW_ACTIONS or 0),
        na = #b, a1 = b[1] and b[1].label or "", a2 = b[2] and b[2].label or "",
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
                icon = n.icon or "", has_icon = (n.icon or "") ~= "", age = age_of(n.time),
            }
        end
    end
    model.notices = top

    -- the banner shows the newest notification whose app may show one (a rule can keep an app out of it)
    rule_map = Quiet.rule_map(rules)
    local toast, counted, recent = {}, 0, {}
    for _, id in ipairs(order) do
        local n = live[id]
        if n then
            local mode = Quiet.rule_mode(rule_map, n.app or "")
            if mode == "normal" and #toast < 1 then
                toast[1] = { id = n.id, app = n.app or "", title = n.title or "", body = flat(n.body), icon = n.icon or "", has_icon = (n.icon or "") ~= "", age = age_of(n.time) }
            end
            if mode ~= "muted" then counted = counted + 1 end
            recent[#recent + 1] = n.app
        end
    end
    model.toast = toast

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
        r.y = live_h
        rows[#rows + 1] = r
        live_h = live_h + r.h
    end
    for key, g in ipairs(groups) do
        group_apps[key] = g.app
        group_ids[key] = {}
        for i, n in ipairs(g.items) do
            group_ids[key][i] = n.id
        end
        local k = key - 1                                  -- keys count from 0 in the scene
        if #g.items == 1 or fact["Settings.group_apps"] ~= true then
            -- a plain list: every notification is its own card
            for _, n in ipairs(g.items) do
                add(row_of(n, 0, k, ROW_CARD))
            end
        elseif false then
            add(row_of(g.items[1], 0, k, ROW_CARD))
        elseif expanded[g.app] then
            add({ kind = 2, key = k, id = 0, app = g.app ~= "" and g.app or "Notifications", title = "", body = "", icon = "", has_icon = false, age = "", h = ROW_HEAD })
            for _, n in ipairs(g.items) do
                add(row_of(n, 0, k, ROW_CARD))
            end
        else
            local n = g.items[1]
            add(row_of(n, 1, k, ROW_STACK, age_of(n.time) .. "  +" .. (#g.items - 1)))
        end
    end
    all_rows = rows
    fact.live_h = live_h

    -- History scrolls after the waiting cards instead of disappearing when they fill the panel.
    local count = math.min(MAX_PAST, #history)
    local past = {}
    for k = 1, count do
        local h = history[k]
        past[k] = { title = h.title or "", body = flat(h.body), icon = h.icon or "", age = age_of(h.time) }
    end
    model.past = past

    content_h = live_h + (#past > 0 and (40 + #past * 58) or 0)
    local height = (#rows == 0 and #past == 0) and 190 or math.min(MAX_HEIGHT, 78 + content_h)
    view_h = height - 78
    fact.nc_height = height
    panel.height(height)
    paint_window()
    refocus()

    -- Senders Settings can offer a rule for: waiting first, then the history.
    for _, h in ipairs(history) do recent[#recent + 1] = h.app end
    model.quiet_apps = Quiet.app_list(rules, recent, Quiet.MAX_APPS)
    fact.rules_n = #rules.apps

    -- the bell: muted apps are held quietly and not counted
    fact.notif_count = counted
    pcall(sys.call, "say", "lock", "fact notif_count " .. tostring(counted))        -- the lock screen shows how many, never what
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


local function banner_hide()
    if banner_timer then
        cancel(banner_timer)
        banner_timer = nil
    end
    if banner_visible then
        banner_visible = false
        fact.banner_on = false
        emit("Topbar.panel_close", BANNER_ID)
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
    if fact.quiet == true or shown() or fact["Settings.banners"] == false then
        return
    end
    if not banner_visible then
        banner_visible = true
        fact.banner_on = true
        emit("Topbar.panel_open", BANNER_ID)
        emit("Topbar.panel_height", { id = BANNER_ID, h = 58 })
    end
    arm_banner()
end

-- ── effective quiet state ─────────────────────────────────────────
local function read_fact(name)
    local ok, v = pcall(function() return fact[name] end)
    if ok then return v end
end

local function paint_quiet_text(eff)
    text.quiet_label = eff.label
    text.quiet_status = eff.quiet and (eff.label .. (held > 0 and ("  ·  " .. held .. " held") or "")) or ""
    text.quiet_short = eff.short
end

local last_eff = Quiet.effective({})
local function refresh_quiet()
    local eff = Quiet.effective({
        manual = fact.dnd == true,
        policies = {
            focus = read_fact("Activities.quiet_focus") == true,
            presentation = read_fact("Activities.quiet_presentation") == true,
            game = read_fact("Activities.quiet_game") == true,
        },
        hours = Quiet.hours_from(read_fact("Settings.quiet_enabled"), read_fact("Settings.quiet_start"), read_fact("Settings.quiet_end")),
        minute = Quiet.minute_of(os.date("*t")),
    })
    local was = fact.quiet == true
    fact.quiet = eff.quiet
    last_eff = eff
    paint_quiet_text(eff)
    if eff.quiet and not was then banner_hide() end
end

local function set_held(n)
    held = n
    fact.held_count = n
    paint_quiet_text(last_eff)
end

-- asked by the other scenes (the owner sets its own facts)
on("set_dnd", function(v) fact.dnd = (v == true or v == 1); refresh_quiet() end)
on("fact:dnd", refresh_quiet)
on("set_banner_hover", function(v) fact.banner_hover = (tonumber(v) == 1) end)       -- the frame draws the cards and tells us
for _, name in ipairs({ "Activities.quiet_focus", "Activities.quiet_presentation", "Activities.quiet_game" }) do
    on("fact:" .. name, refresh_quiet)
end
-- Settings' quiet-hours facts may not exist yet: a missing one means "no window", and the 30 s tick re-reads them.
for _, name in ipairs({ "Settings.quiet_enabled", "Settings.quiet_start", "Settings.quiet_end" }) do
    pcall(on, "fact:" .. name, refresh_quiet)
end

-- ── per-app rules: the owner API Settings (or a card menu) calls ──
local function apply_rule(app, mode, cycle)
    if rules_locked then
        text.rules_status = "Saved quiet rules could not be read, so they cannot be changed. The file has been kept."
        return
    end
    local changed, err
    if cycle then changed, err = Quiet.rule_cycle(rules, app) else changed, err = Quiet.rule_set(rules, app, mode) end
    if err then text.rules_status = err; return end
    text.rules_status = ""
    if changed then queue_save(); paint() end
end
-- { app = "Mail", mode = "muted" | "no_banner" | "normal" | 2 | 1 | 0 }
on("set_app_rule", function(v)
    if type(v) == "table" then apply_rule(v.app, v.mode) else text.rules_status = "set_app_rule needs { app, mode }." end
end)
on("clear_app_rule", function(app) apply_rule(app, "normal") end)
on("cycle_app_rule", function(app) apply_rule(app, nil, true) end)
on("clear_app_rules", function()
    if rules_locked then apply_rule("", "normal"); return end
    if Quiet.rules_clear(rules) then text.rules_status = ""; queue_save(); paint() end
end)

on("set_banner_ms", function(v) fact.banner_ms = tonumber(v) or 5500 end)
on("set_toast_screen", function(i) fact.toast_screen = tonumber(i) or 0 end)
on("hide_banner", function() banner_hide() end)

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
local focus_reset = function() end
opened(function() banner_hide(); if held > 0 then set_held(0) end; focus_reset() end)
closed(function() focus_reset() end)
on("card_click", function()
    if shown() then
        return
    end
    banner_hide()
    emit("Topbar.open_notifications")
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
        refresh_quiet()                  -- a window may have opened or closed since the last tick
        local show_b, kept = false, 0
        for _, n in ipairs(fresh) do
            if n.app ~= "Timer" then
                local t = Quiet.treatment(fact.quiet == true, Quiet.rule_mode(rule_map, n.app or ""))
                if t.banner then show_b = true else kept = kept + 1 end
            end
        end
        if kept > 0 and not shown() then set_held(held + kept) end
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
on("invoke_action", function(v)
    v = tonumber(v) or 0
    local id, index = v // 10, v % 10
    local n = live[id]
    local a = n and buttons_of(n)[index]
    if not a then return end
    pcall(sys.call, "notifications.invoke", id, a.key)
    pcall(sys.call, "notifications.dismiss", id)          -- answered: it leaves the centre like a dismissed one
end)

on("dismiss_notice", function(id)
    if id then
        pcall(sys.call, "notifications.dismiss", id)
    end
end)

on("fact:Settings.group_apps", paint)
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
every(30000, function() refresh_quiet(); paint() end)
refresh_quiet()



-- ── keyboard ─────────────────────────────────────────────────────
-- The frame's rules (common/notice_view.plm) send `nc_key(code)`. The focus walks the STOPS: every row of the list (card, stack,
-- group header; all of them, not only the 16 drawn), then Clear All, then the Clear of Earlier. A card with its own buttons has
-- up to two more positions inside it (`fsub`). The focus is remembered by the row's identity, so a repaint (a new notification,
-- one dismissed, the ages ticking) keeps it on the same card; the frame draws the ring from the nc_* facts.
local fi, fid, fsub = 1, nil, 0
local armed_enter, armed_space = false, false

local function stops()
    local list = {}
    for _, r in ipairs(all_rows) do
        local ident = (r.kind == 0 and ("c" .. r.id)) or (r.kind == 1 and ("s" .. r.key)) or ("h" .. r.key)
        list[#list + 1] = { t = 0, row = r, ident = ident }
    end
    if #order > 0 then list[#list + 1] = { t = 1, ident = "clear" } end
    if #history > 0 then list[#list + 1] = { t = 2, ident = "past" } end
    return list
end

local function max_sub(s)
    return (s and s.t == 0 and s.row.kind == 0) and s.row.na or 0
end

local function publish(bump)
    local list = stops()
    if #list == 0 then
        fact.nc_kind = -1
        fid = nil
        return list
    end
    if fid then
        for i, s in ipairs(list) do
            if s.ident == fid then fi = i; break end
        end
    end
    fi = math.max(1, math.min(fi, #list))
    local s = list[fi]
    fid = s.ident
    fsub = math.max(0, math.min(fsub, max_sub(s)))
    fact.nc_kind = s.t
    fact.nc_sub = fsub
    if s.t == 0 then
        fact.nc_row = s.row.kind
        fact.nc_fy = s.row.y
        fact.nc_fh = s.row.kind == 0 and (s.row.h - 8) or (s.row.kind == 1 and 80 or ROW_HEAD)
    elseif s.t == 2 then
        fact.nc_fy = tonumber(fact.live_h) or 0
        fact.nc_fh = 40
    end
    if bump and s.t ~= 1 then fact.nc_bump = (tonumber(fact.nc_bump) or 0) + 1 end
    return list
end

refocus = function() publish(false) end
focus_reset = function()
    fi, fid, fsub = 1, nil, 0
    armed_enter, armed_space = false, false
    publish(true)
end

local function go(index, sub)
    fi, fid, fsub = index, nil, sub or 0
    publish(true)
end

local function activate()
    local list = stops()
    local s = list[fi]
    if not s then return end
    if s.t == 1 then H.clear_notices(); fi, fid, fsub = 1, nil, 0; return end
    if s.t == 2 then H.clear_past(); return end
    local r = s.row
    if r.kind == 0 then
        local n = live[r.id]
        if fsub > 0 then
            H.invoke_action(r.id * 10 + fsub)
        elseif n then
            for _, a in ipairs(type(n.actions) == "table" and n.actions or {}) do
                if type(a) == "table" and a.key == "default" then
                    pcall(sys.call, "notifications.invoke", r.id, "default")
                    pcall(sys.call, "notifications.dismiss", r.id)
                    break
                end
            end
        end
    else
        -- a stack opens on its first card; a group closes back onto its stack
        if r.kind == 1 then fi, fid, fsub = fi + 1, nil, 0 else fid, fsub = nil, 0 end
        H.group_toggle(r.key)
        publish(true)
    end
end

local function dismiss()
    local s = stops()[fi]
    if not s or s.t ~= 0 then return end
    local r = s.row
    fsub = 0
    if r.kind == 0 then H.dismiss_notice(r.id)
    elseif r.kind == 1 then H.dismiss_group(r.key) end
end

base_on("nc_key", function(code)
    code = tonumber(code)
    if not shown() or not code then return end
    local list = publish(false)
    if #list == 0 then return end
    local s = list[fi]
    if code == 1 then go((fi - 2) % #list + 1)
    elseif code == 2 then go(fi % #list + 1)
    elseif code == 5 then
        if fsub < max_sub(s) then go(fi, fsub + 1) else go(fi % #list + 1) end
    elseif code == 6 then
        if fsub > 0 then go(fi, fsub - 1)
        else
            local pi = (fi - 2) % #list + 1
            go(pi, max_sub(list[pi]))
        end
    elseif code == 4 then
        if fsub < max_sub(s) then go(fi, fsub + 1)
        elseif s.t == 0 and s.row.kind == 1 then activate() end       -- Right on a stack opens it
    elseif code == 3 then
        if fsub > 0 then go(fi, fsub - 1) end
    elseif code == 7 then dismiss()
    elseif code == 10 then armed_enter = true
    elseif code == 11 then armed_space = true
    elseif code == 20 then
        if armed_enter then armed_enter = false; activate() end
    elseif code == 21 then
        if armed_space then armed_space = false; activate() end
    end
end)


end
