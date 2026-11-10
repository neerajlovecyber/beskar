-- Top bar logic: opens the other panels, tells the scene which niri workspace is focused and
-- what the weather is. It only reports facts; every command goes through `run`/`spawn`
-- (declared in topbar.plm's `permissions`), so nothing here blocks the logic thread.

local locate = require("location")      -- where you are (see location.luau)
local WEATHER_EVERY_MS = 15 * 60 * 1000

-- Load saved bar style from prefs.json
local function load_bar_style()
    run("sh", { "-c", 'cat "$HOME/.config/beskar/prefs.json" 2>/dev/null' }, function(out)
        local ok, p = pcall(json.decode, out or "")
        if ok and type(p) == "table" and p.bar_style ~= nil then
            fact.bar_style = tonumber(p.bar_style) or 0
        end
    end)
end
load_bar_style()

-- ── panels ───────────────────────────────────────────────────────
local function toggle(panel)
    return function()
        pcall(sys.call, "say", panel, "emit toggle")
    end
end


-- ── panels that grow out of an island ───────────────────────────
-- The glass is drawn by this scene (one shape per island, driven by the facts `rp_*` right, `cp_*` centre); the
-- panel scenes draw only content and report to us (shell/panel.luau → panel_open / panel_height / panel_close).
-- Two panels can share an island (the Control Center and the notifications use the right one): the one that
-- opened last owns it, and a panel closing only turns the glass off if it still owns it.
local PANELS = {
    control_center = { id = 1, island = "rp", w = 372 },
    notifications = { id = 2, island = "rp", w = 386 },
    dashboard = { id = 3, island = "cp", w = 360 },
    music = { id = 9, island = "cp", w = 380 },
    weather = { id = 15, island = "cp", w = 420 },
    updates = { id = 16, island = "rp", w = 372 },
    banner = { id = 7, island = "cp", w = 380, kind = 1 },     -- a notification, shown inside the centre pill
    spotlight = { id = 4, island = "bp", w = 640 },      -- bottom: grow out of the dock
    wallpapers = { id = 5, island = "bp", w = 980 },
    clipboard = { id = 6, island = "bp", w = 560 },
    widget_bar = { id = 10, island = "bp", w = 800 },
}
local BY_ID = {}
for name, p in pairs(PANELS) do
    p.name = name
    BY_ID[p.id] = p
end
local owner = {}        -- island → id of the panel that owns its glass
local heights = {}      -- id → last height it reported

local PRIORITIES = {
    [3] = 100,  -- dashboard panel
    [9] = 100,  -- music panel
    [15] = 100, -- weather panel
    [7] = 70,   -- banner
    [8] = 60,   -- volume / brightness
    [11] = 50,  -- timer done
    [12] = 40,  -- charging
    [13] = 30,  -- screenshot
    [14] = 20,  -- privacy (camera/mic)
}

local charging_timer = nil
local shot_timer = nil
local timer_done_timer = nil
local priv_timer = nil
local last_shot_file = ""

local osd_release      -- forward declaration

local card_timers = {}      -- id -> timer of the activity card that is up (11 timer done, 12 charging, 13 screenshot, 14 privacy)

local function cancel_activity(id)
    if id == 8 and osd_release then
        osd_release()
    elseif card_timers[id] ~= nil or (id >= 11 and id <= 14) then
        if card_timers[id] then cancel(card_timers[id]); card_timers[id] = nil end
        if owner.cp == id then fact.cp_on = false end
    elseif id == 7 then
        pcall(sys.call, "say", "notifications", "fact banner_on false")
    end
    if owner.cp == id then
        owner.cp = nil
    end
    fact.act_kind = 0
end

local last_toast_screen = nil      -- the monitor with the focus (kept up to date below)

-- A live activity is a CARD in the centre pill, the same one the volume / brightness / microphone feedback uses
-- (osd_kind 3): glyph (or the screenshot thumbnail) in a tile, a title, a sub line and a value on the right.
-- c = { glyph, title, sub, value, tone (0 ink, 1 ok, 2 warn, 3 danger), thumb = true }
local function card_open(id, ms, c)
    if owner.cp and owner.cp ~= id then
        cancel_activity(owner.cp)
    end
    owner.cp = id
    text.card_glyph = c.glyph or ""
    text.card_title = c.title or ""
    text.card_sub = c.sub or ""
    text.card_value = c.value or ""
    fact.card_tone = c.tone or 0
    fact.card_thumb = c.thumb == true
    fact.osd_kind = 3
    fact.cp_screen = last_toast_screen or 0
    fact.cp_kind = 2
    fact.cp_w = 380
    fact.cp_h = 58
    fact.cp_on = true
    if card_timers[id] then cancel(card_timers[id]) end
    card_timers[id] = after(ms, function()
        card_timers[id] = nil
        if owner.cp == id then
            owner.cp = nil
            fact.cp_on = false
        end
    end)
end

on("panel_open", function(id)
    local p = BY_ID[tonumber(id) or 0]
    if p then
        if p.kind == 1 then
            -- a banner never takes the island from a panel that is open there or something higher priority
            if owner[p.island] and (PRIORITIES[owner[p.island]] or 0) >= 70 then
                pcall(sys.call, "say", "notifications", "fact banner_on false")
                return
            end
            if owner[p.island] and owner[p.island] ~= p.id then
                cancel_activity(owner[p.island])
            end
            fact[p.island .. "_screen"] = last_toast_screen or 0
        else
            if owner[p.island] and owner[p.island] ~= p.id then
                cancel_activity(owner[p.island])
            end
        end
        if p.island == "cp" then
            fact.cp_kind = p.kind or 0
        end
        owner[p.island] = p.id
        fact[p.island .. "_w"] = p.w
        if heights[p.id] then
            fact[p.island .. "_h"] = heights[p.id]
        end
        fact[p.island .. "_on"] = true
        if p.island == "bp" then
            fact.bp_keep = (p.name == "widget_bar")
        end
    end
end)

-- Weather, music, today and updates live in ONE scene, `panels` (panels.plm): one shared open / open_screen / cur
-- (the panel id) / panel_h. `panel_say(name, words)` talks to whichever scene a panel is in.
local MERGED = { dashboard = true, music = true, weather = true, updates = true }
local function panel_say(name, words)
    pcall(sys.call, "say", MERGED[name] and "panels" or name, words)
end

-- a click on nothing while a panel is open: close every panel (the widget bar stays: you work on the desktop with it)
on("outside_click", function()
    for name, p in pairs(PANELS) do
        if name ~= "banner" and name ~= "widget_bar" then
            panel_say(name, "fact open false")
        end
    end
end)

on("panel_height", function(v)
    v = tonumber(v) or 0
    local id, h = math.floor(v / 10000), v % 10000
    local p = BY_ID[id]
    if p then
        heights[id] = h
        if owner[p.island] == id then
            fact[p.island .. "_h"] = h
        end
    end
end)

on("panel_close", function(id)
    local p = BY_ID[tonumber(id) or 0]
    if p and owner[p.island] == p.id then
        owner[p.island] = nil
        fact[p.island .. "_on"] = false
        fact.act_kind = 0
    end
end)

-- Which monitor a click was on: `last_screen` is set by the button's own rule just before it emits. Anything
-- else (a niri key bound to start.sh) has none, and then the monitor with the focus is used.
local OUTPUTS = {}                       -- monitor names by screen index (filled further down)

local function monitor_of_click(cb)
    local s = tonumber(fact.last_screen)
    if s and s >= 0 then
        fact.last_screen = -1
        cb(s)
        return
    end
    run("niri", { "msg", "-j", "focused-output" }, function(out)
        local ok, o = pcall(json.decode, out or "")
        local name = ok and type(o) == "table" and o.name
        for i, n in ipairs(OUTPUTS) do
            if n == name then
                cb(i - 1)
                return
            end
        end
        cb(0)
    end)
end

-- Open (or close, if it is already open on that monitor) a panel on the monitor of the click. `page` is for the
-- Control Center only: a number opens it on that page (a second click on the same button closes nothing, it
-- just switches page), nil toggles it.
local function open_island_panel(name, page)
    return function()
        monitor_of_click(function(s)
            local p = PANELS[name]
            local open_here = fact[p.island .. "_on"] == true and owner[p.island] == p.id
                and tonumber(fact[p.island .. "_screen"]) == s
            if open_here and page == nil then
                panel_say(name, "fact open false")
                return
            end
            fact[p.island .. "_screen"] = s
            panel_say(name, "fact open_screen " .. s)
            if MERGED[name] then panel_say(name, "fact cur " .. p.id) end
            if name == "control_center" then
                pcall(sys.call, "say", name, "fact page " .. (page or 0))
            end
            panel_say(name, "fact open true")
        end)
    end
end
on("open_control_center", open_island_panel("control_center"))
on("open_cc_wifi", open_island_panel("control_center", 1))
on("open_cc_bt", open_island_panel("control_center", 2))
on("open_dashboard", open_island_panel("dashboard"))
on("open_notifications", open_island_panel("notifications"))
on("open_music", open_island_panel("music"))
on("open_weather", open_island_panel("weather"))
on("rec_stop", function()
    pcall(sys.call, "say", "capture", "emit toggle_record")
end)

-- ── the clock: the time only (no date), 12 hour with AM / PM unless Settings says 24 ──
local clockfmt = require("clockfmt")
local function paint_clock()
    local t = clockfmt(fact.hour12, fact.pref_seconds)
    if text.clock_text ~= t then
        text.clock_text = t
    end
end
paint_clock()
every(1000, paint_clock)
on("fact:hour12", paint_clock)
on("fact:pref_seconds", paint_clock)

-- ── music in the clock pill: the cover and a few bars while a player has something ──
pcall(sys.watch, "media", function(m)
    m = m or {}
    local has = (m.player or "") ~= "" and (m.title or "") ~= ""
    fact.m_on = has
    fact.m_playing = m.playing == true
    fact.m_has_art = (m.art or "") ~= ""
    text.m_art = m.art or ""
end)

-- ── volume / brightness feedback, inside the centre pill ─────────────────────────────────────
-- (replaces the floating bezel). It borrows the centre island for a moment: not from the dashboard, but from a
-- notification banner, which makes way. The level comes from the audio / brightness services, so it shows whatever
-- changed them (a key, the Control Center slider, another program).
local OSD_ID = 8
local OSD_MS = 1500
local osd_timer = nil

osd_release = function()
    if osd_timer then
        cancel(osd_timer)
        osd_timer = nil
    end
    if owner.cp == OSD_ID then
        owner.cp = nil
        fact.cp_on = false
    end
end

local function osd_show(kind, level, muted)
    if owner.cp and (PRIORITIES[owner.cp] or 0) > 60 then
        return                                       -- panel (100) or banner (70) has the island
    end
    if owner.cp and owner.cp ~= OSD_ID then
        cancel_activity(owner.cp)
    end
    fact.osd_kind = kind
    fact.osd_level = math.min(1, math.max(0, level or 0))
    fact.osd_muted = muted == true
    owner.cp = OSD_ID
    fact.cp_screen = last_toast_screen or 0
    fact.cp_kind = 2
    fact.cp_w = 380
    fact.cp_h = 58                                   -- a card, like a banner
    fact.cp_on = true
    if osd_timer then
        cancel(osd_timer)
    end
    osd_timer = after(OSD_MS, function()
        osd_timer = nil
        osd_release()
    end)
end

local last_vol, last_mute, last_br, last_imute = nil, nil, nil, nil
pcall(sys.watch, "audio", function(a)
    if a and a.volume ~= nil then
        local mute = a.muted == true
        if last_vol ~= nil and (math.abs(a.volume - last_vol) > 0.005 or mute ~= last_mute) then
            osd_show(0, a.volume, mute)
        end
        last_vol, last_mute = a.volume, mute
    end
    if a and a.input_muted ~= nil then
        local im = a.input_muted == true
        if last_imute ~= nil and im ~= last_imute then
            osd_show(2, 1, im)                       -- the microphone was muted / unmuted
        end
        last_imute = im
    end
end)
pcall(sys.watch, "brightness", function(b)
    if b and b.level ~= nil then
        if last_br ~= nil and math.abs(b.level - last_br) > 0.005 then
            osd_show(1, b.level, false)
        end
        last_br = b.level
    end
end)

on("osd_vol_up", function()
    pcall(sys.call, "audio.step", 0.05)
end)
on("osd_vol_down", function()
    pcall(sys.call, "audio.step", -0.05)
end)
on("osd_vol_mute", function()
    pcall(sys.call, "audio.mute")
end)
on("osd_br_up", function()
    pcall(sys.call, "brightness.level", math.min(1, (last_br or 0.5) + 0.05))
end)
on("osd_br_down", function()
    pcall(sys.call, "brightness.level", math.max(0.05, (last_br or 0.5) - 0.05))
end)
on("osd_popup", function()
    osd_show(0, last_vol or 0.5, last_mute)
end)

-- ── live activity: charging ──────────────────────────────────────
-- The battery service only says "charging". A laptop on its charger with a charge limit (96 %, say) is plugged in and NOT
-- charging, so the power supply is read here: `bat_ac` (the charger is connected) and `bat_status`.
local function show_charging_activity(ac, status, pct)
    if owner.cp and (PRIORITIES[owner.cp] or 0) > 40 then
        return
    end
    local title, sub, tone
    if not ac then
        title, sub, tone = "On battery", "Charger disconnected", 0
    elseif status == "Charging" then
        title, sub, tone = "Charging", "Power connected", 1
    elseif status == "Full" then
        title, sub, tone = "Fully charged", "Power connected", 1
    else
        title, sub, tone = "Plugged in", "Power connected  ·  not charging (charge limit)", 1
    end
    card_open(12, 3000, { glyph = ac and "󰚥" or "󰁹", title = title, sub = sub, value = pct .. "%", tone = tone })
end

local last_ac = nil
local function poll_power()
    run("sh", { "-c", 'ac=0; for f in /sys/class/power_supply/A*/online /sys/class/power_supply/AC*/online; do [ -r "$f" ] && [ "$(cat "$f")" = 1 ] && ac=1; done; echo "$ac $(cat /sys/class/power_supply/BAT*/status 2>/dev/null | head -1) $(cat /sys/class/power_supply/BAT*/capacity 2>/dev/null | head -1)"' }, function(out)
        local ac, status, pct = (out or ""):match("^(%d) (.-) (%d+)%s*$")
        if not ac then return end
        local plugged = ac == "1"
        fact.bat_ac = plugged
        text.bat_status = status
        if last_ac ~= nil and plugged ~= last_ac then
            show_charging_activity(plugged, status, tonumber(pct) or 0)
        end
        last_ac = plugged
    end)
end
poll_power()
every(3000, poll_power)

-- ── live activity: screenshot taken ──────────────────────────────
local function show_screenshot_activity(file)
    if owner.cp and (PRIORITIES[owner.cp] or 0) > 30 then
        return
    end
    last_shot_file = file
    text.shot_path = file
    card_open(13, 3500, { title = "Screenshot saved", sub = "Click to open  ·  copied to the clipboard", thumb = true })
end

on("text:shot_path", function(file)
    if file and file ~= "" then
        show_screenshot_activity(tostring(file))
    end
end)

on("screenshot_taken", function(file)
    local f = (file and tostring(file) ~= "" and tostring(file) ~= "nil") and tostring(file) or text.shot_path
    if f and f ~= "" then
        show_screenshot_activity(f)
    end
end)

on("open_screenshot", function()
    if last_shot_file and last_shot_file ~= "" then
        run("xdg-open", { last_shot_file }, nil, { output = false })
        if owner.cp == 13 then
            cancel_activity(13)
        end
    end
end)

-- ── live activity: timer countdown and done alert ────────────────
local timer_remaining = 0
local timer_timer = nil

local function fmt_timer(s)
    if s >= 3600 then
        return string.format("%d:%02d:%02d", s // 3600, (s % 3600) // 60, s % 60)
    else
        return string.format("%d:%02d", s // 60, s % 60)
    end
end

local function timer_tick()
    if timer_remaining <= 0 then
        timer_remaining = 0
        fact.timer_on = false
        timer_timer = nil
        -- Alert with sound-free notification
        run("notify-send", { "-a", "Timer", "-i", "alarm", "-u", "critical", "-h", "string:sound-name:none", "Timer done", "Time's up!" }, nil, { output = false })
        -- Timer done: a card for 5 s (priority 50)
        if not (owner.cp and (PRIORITIES[owner.cp] or 0) > 50) then
            card_open(11, 5000, { glyph = "󰔛", title = "Timer done", sub = "Click to dismiss", value = "Time's up", tone = 2 })
        end
        return
    end
    text.timer_text = fmt_timer(timer_remaining)
    timer_remaining = timer_remaining - 1
    timer_timer = after(1000, timer_tick)
end

on("timer_start", function(sec)
    sec = tonumber(sec) or 0
    if sec <= 0 then return end
    if timer_timer then cancel(timer_timer); timer_timer = nil end
    if timer_done_timer then cancel(timer_done_timer); timer_done_timer = nil end
    if owner.cp == 11 then cancel_activity(11) end
    timer_remaining = sec
    fact.timer_on = true
    timer_tick()
end)

on("timer_cancel", function()
    if timer_timer then cancel(timer_timer); timer_timer = nil end
    fact.timer_on = false
    timer_remaining = 0
end)

on("card_click", function()
    if owner.cp == 13 then
        if last_shot_file and last_shot_file ~= "" then
            run("xdg-open", { last_shot_file }, nil, { output = false })
        end
        cancel_activity(13)
    elseif owner.cp then
        cancel_activity(owner.cp)
    end
end)

on("dismiss_timer_done", function()
    if owner.cp == 11 then
        cancel_activity(11)
    end
end)

-- Keep the notification banner on the monitor with the focus: ask niri now and then, tell it when it changes.
every(2000, function()
    run("niri", { "msg", "-j", "focused-output" }, function(out)
        local ok, o = pcall(json.decode, out or "")
        local name = ok and type(o) == "table" and o.name
        for i, n in ipairs(OUTPUTS) do
            if n == name and (i - 1) ~= last_toast_screen then
                last_toast_screen = i - 1
                pcall(sys.call, "say", "notifications", "fact toast_screen " .. (i - 1))
            end
        end
    end)
end)

-- Panels that are their own window (Spotlight, clipboard, wallpapers, Settings, the session dialog, the app
-- switcher) open on ONE monitor: the one with the focus. They are `screens: each` scenes that show their content
-- only where `open_screen` says (common/here.plm). Everything that wants one asks us (`open_panel N`): a niri key
-- through start.sh, a button in another panel. The toggle is the panel's own.
local FOCUS_PANELS = { [1] = "spotlight", [2] = "clipboard", [3] = "wallpapers", [4] = "settings", [5] = "session", [6] = "appswitcher", [7] = "widget_bar", [8] = "polkit", [9] = "welcome", [10] = "overview", [11] = "capture" }
on("open_panel", function(n)
    local name = FOCUS_PANELS[tonumber(n) or 0]
    if not name then
        return
    end
    monitor_of_click(function(s)
        local p = PANELS[name]
        if p then
            fact[p.island .. "_screen"] = s          -- its glass is drawn by the frame, on that monitor
        end
        pcall(sys.call, "say", name, "fact open_screen " .. s)
        pcall(sys.call, "say", name, "emit toggle")
    end)
end)

-- ── the power menu (the gem button) ──────────────────────────────
local function say(scene, words)
    pcall(sys.call, "say", scene, words)
end
-- The monitor the power menu is on (`open_screen`), for the windows its items open.
local function show_on_menu_monitor(name)
    say(name, "fact open_screen " .. (tonumber(fact.open_screen) or 0))
    say(name, "fact open true")
end
local PM = {
    [1] = function() say("settings", "fact tab 6"); show_on_menu_monitor("settings") end,         -- About This PC
    [2] = function() say("settings", "fact tab 0"); show_on_menu_monitor("settings") end,         -- System Settings
    [8] = function() say("widgets", "emit edit_toggle") end,                                     -- Edit Widgets…
    [3] = function() say("lock", "fact locked true") end,                                           -- Lock Screen
    [4] = function() run("systemctl", { "suspend" }, nil, { output = false }) end,                 -- Sleep
    [5] = function() say("session", "fact kind 2"); show_on_menu_monitor("session") end,          -- Log Out…
    [6] = function() say("session", "fact kind 1"); show_on_menu_monitor("session") end,          -- Restart…
    [7] = function() say("session", "fact kind 0"); show_on_menu_monitor("session") end,          -- Shut Down…
}
on("pm_item", function(n)
    local f = PM[tonumber(n) or 0]
    if f then
        f()
    end
end)


-- ── tray ─────────────────────────────────────────────────────────
-- The service's list goes to the scene's `icons` model (it draws the picture). Reading the model
-- back gives each record with EVERYTHING it carried, `key` included, which is what
-- tray.activate / tray.secondary / tray.context need.
-- Every app that has a tray icon shows, except the two that only repeat what the bar already draws itself:
-- nm-applet (network) and blueman (Bluetooth). To hide more, put the item's id (one per line) in
-- ~/.config/beskar/tray-hide; to show these two again, put `-nm-applet` / `-blueman` there.
-- Ids seen on this machine: chrome_status_icon_1, Cachy-Update, nm-applet, blueman, … (`describe` lists them).
local DEFAULT_HIDE = { ["nm-applet"] = true, ["blueman"] = true }
local hidden = DEFAULT_HIDE
local last_tray = {}

local function show_tray()
    local shown = {}
    for _, it in ipairs(last_tray) do
        if not hidden[it.id or ""] and it.status ~= "Passive" then
            shown[#shown + 1] = it
        end
    end
    model.icons = shown
end

sys.watch("tray", function(list)
    last_tray = list or {}
    show_tray()
end)

local function read_tray_hide()
    run("sh", { "-c", 'cat "$HOME/.config/beskar/tray-hide" 2>/dev/null' }, function(out)
        local set = {}
        for k, v in pairs(DEFAULT_HIDE) do
            set[k] = v
        end
        for line in (out or ""):gmatch("[^\n]+") do
            local id = line:gsub("^%s+", ""):gsub("%s+$", "")
            if id:sub(1, 1) == "-" then
                set[id:sub(2)] = nil          -- show one of the defaults again
            elseif id ~= "" and id:sub(1, 1) ~= "#" then
                set[id] = true
            end
        end
        hidden = set
        show_tray()
    end)
end
read_tray_hide()
every(10000, read_tray_hide)

local function tray_action(call)
    return function(i)
        local it = model.icons and model.icons[(i or 0) + 1]
        if it and it.key then
            pcall(sys.call, call, it.key)
        end
    end
end

on("tray_activate", tray_action("tray.activate"))       -- left click
on("tray_secondary", tray_action("tray.secondary"))     -- middle click
on("tray_context", tray_action("tray.context"))         -- right click: the app's own menu

-- Last answers from niri, combined into `model.mon` (workspace shown + how many windows it holds).
local WS, WINS = {}, {}
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

local function save_pins(list)
    pinned = list
    local script = 'mkdir -p "$HOME/.config/beskar" && : > "$HOME/.config/beskar/dock" && for a in "$@"; do printf "%s\\n" "$a" >> "$HOME/.config/beskar/dock"; done'
    local args = { "-c", script, "x" }
    for _, id in ipairs(list) do
        args[#args + 1] = id
    end
    run("sh", args, nil, { output = false })
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
    for _, w in ipairs(WINS) do
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
    for _, id in ipairs(pins) do
        local e = by_key[lower(id)]
        local aid, cmd = id:match("^app:([^|]+)|(.*)$")
        if aid then
            -- an app with no (visible) desktop entry, pinned from its running window: we keep how to start it
            local key = "app:" .. lower(aid)
            if not used[key] and #list < 12 then
                used[key] = true
                list[#list + 1] = { name = pretty_app(aid), icon = lower(aid), pinned = true, cmd = cmd, pinstr = id,
                                    wins = groups[key] and groups[key].wins or {} }
            end
        elseif e and not used[lower(e.id)] and #list < 12 then
            local key = lower(e.id)
            used[key] = true
            list[#list + 1] = { entry = e, name = name_of(e), icon = e.icon or "", pinned = true,
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
    local rows = {}
    for i, it in ipairs(list) do
        local win_title = ""
        local win_thumb = ""
        local has_thumb = false
        if #it.wins > 0 then
            for _, w in ipairs(WINS) do
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
    run("sh", { "-c", 'if [ -f "$HOME/.config/beskar/dock" ]; then cat "$HOME/.config/beskar/dock"; else echo "__none__"; fi' }, function(out)
        if not out then
            return
        end
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
every(5000, read_pins)

-- ── workspaces: one capsule per workspace of each monitor ──
-- `model ws_list`: one record per workspace, `out` the monitor (0 = first of `niri msg outputs`, sorted by name).
-- `wins` is how many windows it has.
local function build_ws()
    local by_ws = {}
    for _, w in ipairs(WINS) do
        if w.workspace_id then
            local l = by_ws[w.workspace_id]
            if not l then
                l = {}
                by_ws[w.workspace_id] = l
            end
            l[#l + 1] = w
        end
    end
    local out_index = {}
    for i, name in ipairs(OUTPUTS) do
        out_index[name] = i - 1
    end
    local sorted = {}
    for _, ws in ipairs(WS) do
        sorted[#sorted + 1] = ws
    end
    table.sort(sorted, function(a, b)
        if a.output ~= b.output then
            return (a.output or "") < (b.output or "")
        end
        return (a.idx or 0) < (b.idx or 0)
    end)
    local list = {}
    for _, ws in ipairs(sorted) do
        local o = out_index[ws.output]
        if o and #list < 12 then
            local wins = by_ws[ws.id] or {}
            local rec = { out = o, idx = ws.idx or 1, active = ws.is_active == true, wins = #wins }
            list[#list + 1] = rec
        end
    end
    model.ws_list = list
end

on("ws_go", function(v)
    v = tonumber(v) or 0
    local out, idx = math.floor(v / 100), v % 100
    local name = OUTPUTS[out + 1]
    if name then
        run("niri", { "msg", "action", "focus-monitor", name }, function()
            run("niri", { "msg", "action", "focus-workspace", tostring(idx) }, nil, { output = false })
        end, { output = false })
    end
end)

on("ws_focus", function(wid)
    if wid and wid > 0 then
        run("niri", { "msg", "action", "focus-window", "--id", tostring(wid) }, nil, { output = false })
    end
end)

-- ── the apps open in the workspace each monitor shows, left to right as niri lays them out ──
-- `model cur_apps`: `out` the monitor, `focused` the one with the focus there (it also shows its name).
local function build_cur()
    local active_ws = {}                 -- output name → workspace record
    for _, ws in ipairs(WS) do
        if ws.is_active and ws.output then
            active_ws[ws.output] = ws
        end
    end
    local list = {}
    for o, name in ipairs(OUTPUTS) do
        local ws = active_ws[name]
        if ws then
            local wins = {}
            for _, w in ipairs(WINS) do
                if w.workspace_id == ws.id then
                    wins[#wins + 1] = w
                end
            end
            table.sort(wins, function(a, b)
                local pa = a.layout and a.layout.pos_in_scrolling_layout
                local pb = b.layout and b.layout.pos_in_scrolling_layout
                if pa and pb then
                    if pa[1] ~= pb[1] then return pa[1] < pb[1] end
                    return pa[2] < pb[2]
                end
                if pa then return true end
                if pb then return false end
                return (a.id or 0) < (b.id or 0)
            end)
            local focus = ws.active_window_id
            for k, w in ipairs(wins) do
                if k <= 8 and #list < 20 then
                    local e = entry_for(w.app_id)
                    list[#list + 1] = {
                        out = o - 1,
                        icon = e and e.icon or lower(w.app_id),
                        name = e and name_of(e) or pretty_app(w.app_id),
                        wid = w.id,
                        focused = w.id == focus,
                    }
                end
            end
        end
    end
    model.cur_apps = list
end

local function push_mon()
    local shown, busy = {}, {}
    for _, w in ipairs(WS) do
        if w.is_active and w.output then
            shown[w.output] = w.idx or 1
            busy[w.output] = w.id
        end
    end
    local count = {}
    for _, win in ipairs(WINS) do
        if win.workspace_id then
            count[win.workspace_id] = (count[win.workspace_id] or 0) + 1
        end
    end
    local per_out = {}
    for _, w in ipairs(WS) do
        per_out[w.output or ""] = (per_out[w.output or ""] or 0) + 1
    end
    local recs = {}
    for i, name in ipairs(OUTPUTS) do
        recs[i] = { active = shown[name] or 1, busy = count[busy[name] or -1] or 0, nws = per_out[name] or 1 }
    end
    model.mon = recs
    build_ws()
    build_cur()
end

local function refresh_running()
    run("niri", { "msg", "-j", "windows" }, function(out, code)
        if code ~= 0 or not out then
            return
        end
        local ok, list = pcall(json.decode, out)
        if not ok or type(list) ~= "table" then
            return
        end
        WINS = list
        push_mon()
        build_dock()
    end)
end

-- ── niri: the workspace each monitor shows ───────────────────────
-- `model mon` has one record per monitor, in the order of `niri msg outputs`.
local function refresh_workspaces()
    run("niri", { "msg", "-j", "workspaces" }, function(out, code)
        if code ~= 0 or not out then
            return
        end
        local ok, list = pcall(json.decode, out)
        if not ok or type(list) ~= "table" then
            return
        end
        WS = list
        push_mon()
    end)
end

local function refresh_niri()
    refresh_workspaces()
    refresh_running()
end

run("niri", { "msg", "-j", "outputs" }, function(out, code)
    local ok, o = pcall(json.decode, out or "")
    if code == 0 and ok and type(o) == "table" then
        for name in pairs(o) do
            OUTPUTS[#OUTPUTS + 1] = name
        end
        table.sort(OUTPUTS)
    end
    refresh_niri()
end)

-- Which copy of the scene is on which monitor is up to the compositor and changes between runs (screen 0 was
-- HDMI one day and eDP the next), so sorting the names is only a guess. pleamar logs the truth at startup
-- ("surface 0 on eDP-1 …"); read it from the log start.sh keeps, and use it for every per-monitor model.
local learned = false
local function learn_screens(tries)
    run("sh", { "-c", "grep 'surface [0-9]* on' /tmp/pleamar_topbar.log 2>/dev/null | head -8" }, function(out)
        local map = {}
        for idx, name in (out or ""):gmatch("surface (%d+) on (%S+)") do
            map[tonumber(idx) + 1] = name
        end
        if #map > 0 then
            OUTPUTS = map
            learned = true
            push_mon()
        elseif tries > 0 then
            after(3000, function() learn_screens(tries - 1) end)
        end
    end)
end
after(2500, function() learn_screens(6) end)

-- niri prints one JSON object per event. Workspaces and windows are all that can change what we
-- show; ask niri again instead of reading the event.
local streaming = false
local function follow_niri()
    if streaming then
        return
    end
    streaming = true
    spawn("niri", { "msg", "-j", "event-stream" }, function(line)
        if line:find("Workspace", 1, true) or line:find("WindowOpenedOrChanged", 1, true) or line:find("WindowClosed", 1, true) then
            refresh_niri()
        end
    end, function()
        streaming = false      -- niri went away; the timer below retries
    end)
end

follow_niri()
every(5000, follow_niri)

-- ── weather ──────────────────────────────────────────────────────
local function icon_for(code)
    if code == 0 then
        return "󰖙"
    elseif code <= 3 then
        return "󰅟"
    elseif code == 45 or code == 48 then
        return "󰖑"
    elseif (code >= 51 and code <= 67) or (code >= 80 and code <= 82) then
        return "󰖗"
    elseif (code >= 71 and code <= 77) or code == 85 or code == 86 then
        return "󰖘"
    elseif code >= 95 then
        return "󰙾"
    end
    return "󰅟"
end

local function refresh_weather()
    locate(function(place)
        if not place then
            return          -- no place yet: keep the last reading
        end
        local url = string.format(
            "https://api.open-meteo.com/v1/forecast?latitude=%s&longitude=%s&current=temperature_2m,weather_code",
            place.lat, place.lon
        )
        run("curl", { "-fsS", "--max-time", "5", url }, function(out, code)
            if code ~= 0 or not out then
                return
            end
            local ok, data = pcall(json.decode, out)
            local cur = ok and type(data) == "table" and data.current
            if type(cur) ~= "table" or cur.temperature_2m == nil then
                return
            end
            text.weather_temp = string.format("%d°", math.floor(cur.temperature_2m + 0.5))
            text.weather_icon = icon_for(cur.weather_code or 0)
        end)
    end)
end

refresh_weather()
every(WEATHER_EVERY_MS, refresh_weather)
on("weather_reload", refresh_weather)

-- ── privacy: camera and microphone in use ───────────────────────
-- The camera is "in use" while some process has a /dev/video* node open (fuser); the microphone while some program
-- is recording from a source (PipeWire / PulseAudio source-outputs). Nothing is recorded or logged here.
local PRIVACY = [[
cam=0
for d in /dev/video*; do [ -e "$d" ] && fuser "$d" >/dev/null 2>&1 && cam=1; done
mic=$(pactl list short source-outputs 2>/dev/null | wc -l)
[ "$mic" -gt 0 ] && mic=1
echo "$cam $mic"
]]

local last_cam, last_mic = nil, nil

local function show_privacy_activity(is_cam)
    if owner.cp and (PRIORITIES[owner.cp] or 0) > 20 then
        return
    end
    card_open(14, 3000, { glyph = is_cam and "󰄀" or "󰍬", title = is_cam and "Camera in use" or "Microphone in use", sub = "An app is using it right now", tone = is_cam and 1 or 2 })
end

local function poll_privacy()
    run("sh", { "-c", PRIVACY }, function(out)
        local cam, mic = (out or ""):match("(%d) (%d)")
        if cam then
            local is_cam = cam == "1"
            local is_mic = mic == "1"
            fact.priv_cam = is_cam
            fact.priv_mic = is_mic
            if last_cam ~= nil and (not last_cam) and is_cam then
                show_privacy_activity(true)
            elseif last_mic ~= nil and (not last_mic) and is_mic then
                show_privacy_activity(false)
            end
            last_cam = is_cam
            last_mic = is_mic
        end
    end)
end
poll_privacy()
every(4000, poll_privacy)

-- ── updates: updates.luau checks pacman and tells us the count (`upd_n`); the arrow opens its panel ──
on("open_updates", open_island_panel("updates"))

-- one panel at a time
require("exclusive")("topbar")
