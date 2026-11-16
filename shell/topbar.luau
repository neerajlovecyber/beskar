-- Top bar logic: opens the other panels, tells the scene which niri workspace is focused and
-- what the weather is. It only reports facts; every command goes through `run`/`spawn`
-- (declared in topbar.plm's `permissions`), so nothing here blocks the logic thread.


-- (the bar style and the other preferences are Settings' facts, read by name: `fact["Settings.bar_style"]`)

-- ── panels ───────────────────────────────────────────────────────
local hooks = require("topbar_hooks")               -- every handler registered below is recorded for the panels that run in this plugin (they cannot emit to us)
local base_on = on
local function on(name, fn) hooks.handlers[name] = fn; return base_on(name, fn) end

local ALIAS = { settings = "Settings", panels = "Panels" }       -- scenes of `desktop` an event can be sent to by name
local function send_toggle(panel)
    if ALIAS[panel] then emit(ALIAS[panel] .. ".toggle") else pcall(sys.call, "say", panel, "emit toggle") end
end
local function toggle(panel)
    return function()
        send_toggle(panel)
    end
end


-- ── panels that grow out of an island ───────────────────────────
-- The glass is drawn by this scene (one shape per island, driven by the facts `rp_*` right, `cp_*` centre); the
-- panel scenes draw only content and report to us (shell/panel.luau → panel_open / panel_height / panel_close).
-- Two panels can share an island (the Control Center and the notifications use the right one): the one that
-- opened last owns it, and a panel closing only turns the glass off if it still owns it.
local panel_data = require("panels_data")
local PANELS, BY_ID = panel_data.panels, panel_data.by_id
local owner = {}        -- island → id of the panel that owns its glass
local heights = {}      -- id → last height it reported
local widths = {}       -- id → last width it reported (panels whose width follows their content)

local PRIORITIES = {
    [26] = 100, -- timer panel
    [25] = 100, -- personal editor
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
        emit("Notifications.hide_banner")
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
                emit("Notifications.hide_banner")
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
        fact[p.island .. "_w"] = widths[p.id] or p.w
        if heights[p.id] then
            fact[p.island .. "_h"] = heights[p.id]
        end
        fact[p.island .. "_on"] = true
        if p.island == "bp" then
            fact.bp_keep = (p.name == "widget_bar")
        end
    end
end)

-- The owner, frame and action catalogue use the same static IDs and opening routes.
local MERGED, DOCK = panel_data.merged, panel_data.dock
-- Every panel is ONE surface that follows the monitor named in `Panels.panel_mon`: the `Panels` scene owns it (panels.plm),
-- so we tell IT the monitor's index (`open_screen`) and its output NAME. Settings' sheet has its own `open_screen`.
-- Ours (OUTPUTS) is filled in below.
local OUTPUT_NAMES
local function overlay_screen(s, name)
    local n = OUTPUT_NAMES and OUTPUT_NAMES()[s + 1] or ""
    emit("Panels.set_screen", { s = s, name = n })
    if name == "settings" then
        emit("Settings.set_screen", s)               -- Settings' sheet has its own `open_screen`
    elseif name and not (MERGED[name] or DOCK[name]) then
        pcall(sys.call, "say", name, "fact open_screen " .. s)         -- the capture picker (its own process)
    end
end

-- a click on nothing while a panel is open: close every panel (the widget bar stays: you work on the desktop with it)
on("outside_click", function()
    emit("Panels.outside_close")      -- (the widget bar and the password dialog stay)
end)

on("panel_height", function(v)
    local id, h = tonumber(v and v.id) or 0, math.floor(tonumber(v and v.h) or 0)       -- {id, h} from the Panels scene
    local p = BY_ID[id]
    if p then
        heights[id] = h
        if owner[p.island] == id then
            fact[p.island .. "_h"] = h
        end
    end
end)

on("panel_width", function(v)
    local id, w = tonumber(v and v.id) or 0, math.floor(tonumber(v and v.w) or 0)       -- {id, w} from the Panels scene
    local p = BY_ID[id]
    if p then
        widths[id] = w
        if owner[p.island] == id then
            fact[p.island .. "_w"] = w
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
local OUTPUTS = {}                       -- monitor names by screen index (0 -> OUTPUTS[1], 1 -> OUTPUTS[2])
OUTPUT_NAMES = function() return OUTPUTS end
local push_mon                           -- forward declaration for sync_outputs listeners

local function sync_outputs()
    local map = {}
    for s = 0, 7 do
        local sname = text["screen." .. s .. ".name"]
        if sname and sname ~= "" then
            map[s + 1] = sname
        end
    end
    if #map > 0 then
        local changed = (#map ~= #OUTPUTS)
        if not changed then
            for i, n in ipairs(map) do
                if OUTPUTS[i] ~= n then
                    changed = true
                    break
                end
            end
        end
        if changed then
            OUTPUTS = map
            return true
        end
    end
    return false
end

sync_outputs()

for s = 0, 7 do
    on("text:screen." .. s .. ".name", function()
        if sync_outputs() and push_mon then
            push_mon()
        end
    end)
end
on("fact:screens.count", function()
    if sync_outputs() and push_mon then
        push_mon()
    end
end)

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
                emit("Panels.close")
                return
            end
            fact[p.island .. "_screen"] = s
            overlay_screen(s, name)
            if name == "control_center" then
                fact.cc_page = page or 0                -- the frame owns the Control Center now
            end
            emit("Panels.show", p.id)
        end)
    end
end
on("open_control_center", open_island_panel("control_center"))
on("open_cc_wifi", open_island_panel("control_center", 1))
on("open_cc_bt", open_island_panel("control_center", 2))
on("open_personal", open_island_panel("personal"))
local open_timer = open_island_panel("timer")
on("open_timer", open_timer)
local function show_personal_on(s)
    s = tonumber(s)
    if not s or s ~= math.floor(s) or not OUTPUTS[s + 1] then return end
    fact.cp_screen = s
    overlay_screen(s, "personal")
    emit("Panels.show", PANELS.personal.id)
end
on("open_personal_on", show_personal_on)
on("open_personal_output", function(ordinal)
    ordinal = tonumber(ordinal)
    if not ordinal or ordinal ~= math.floor(ordinal) then return end
    local names = {}
    for _, name in ipairs(OUTPUTS) do names[#names + 1] = name end
    table.sort(names)
    for i, name in ipairs(OUTPUTS) do
        if name == names[ordinal + 1] then show_personal_on(i - 1); return end
    end
end)
on("open_timer_output", function(ordinal)
    ordinal = tonumber(ordinal)
    if not ordinal or ordinal ~= math.floor(ordinal) then return end
    local names = {}
    for _, name in ipairs(OUTPUTS) do names[#names + 1] = name end
    table.sort(names)
    for i, name in ipairs(OUTPUTS) do
        if name == names[ordinal + 1] then
            fact.cp_screen = i - 1
            overlay_screen(i - 1, "timer")
            emit("Panels.show", PANELS.timer.id)
            return
        end
    end
end)
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
    local t = clockfmt(fact["Settings.hour12"], fact["Settings.pref_seconds"])
    if text.clock_text ~= t then
        text.clock_text = t
    end
end
paint_clock()
every(1000, paint_clock)
on("fact:Settings.hour12", paint_clock)
on("fact:Settings.pref_seconds", paint_clock)

-- ── the little bars (music) and the recording dot move only while they show ──
-- (a plm `wave` paints the whole scene at the monitor's rate for ever; this phase ticks at 10 fps, and only
-- while something plays or records and is visible: cuts render frames in half)
local ph_timer = nil
local function waves_visible()
    return fact["Settings.reduce_motion"] ~= true
        and ((fact["System.is_playing"] == true and fact["System.media_on"] == true) or fact.rec_on == true)
        and (tonumber(fact.act_kind) or 0) == 0
end
local function wave_tick()
    ph_timer = nil
    local should_tick = waves_visible()
    if should_tick then
        fact.m_ph = (tonumber(fact.m_ph) or 0) + 0.125 * 57.2958
        ph_timer = after(125, wave_tick)
    end
end
local function wave_kick()
    if not waves_visible() then
        if ph_timer then cancel(ph_timer); ph_timer = nil end
        return
    end
    if not ph_timer then
        local should_tick = waves_visible()
        if should_tick then
            ph_timer = after(125, wave_tick)
        end
    end
end
on("fact:Settings.reduce_motion", wave_kick)
on("fact:rec_on", wave_kick)
on("fact:act_kind", function(k)
    if (tonumber(k) or 0) == 0 then
        wave_kick()
    end
end)

-- ── music in the clock pill: the cover and a few bars while a player has something ──
local function media_changed()
    if fact["System.media_on"] == true and fact["System.is_playing"] == true then
        wave_kick()
    elseif ph_timer and not fact.rec_on then
        cancel(ph_timer)
        ph_timer = nil
    end
end
on("fact:System.media_on", media_changed)        -- the System scene watches the media service once
on("fact:System.is_playing", media_changed)

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

-- ── live activity: charging, and the privacy dots: polled sensors, in shell/frame_sensors.luau ──
require("frame_sensors")({ owner = owner, PRIORITIES = PRIORITIES, card_open = card_open })

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

-- Timer state belongs to Activities. Keep legacy event routes for scripts.
on("timer_start", function(seconds) emit("Activities.start", seconds) end)
on("timer_cancel", function() emit("Activities.cancel") end)
on("timer_finished", function()
    -- Notifications retains timer history and already suppresses a duplicate Timer banner.
    run("notify-send", { "-a", "Timer", "-i", "alarm", "-u", "critical", "-h", "string:sound-name:none", "Timer done", "Time’s up!" }, nil, { output = false })
    if not (owner.cp and (PRIORITIES[owner.cp] or 0) > 50) then
        card_open(11, 5000, { glyph = "󰔛", title = "Timer done", sub = "Click to open timer", value = "Time’s up", tone = 2 })
    end
end)

on("card_click", function()
    if owner.cp == 11 then
        cancel_activity(11)
        open_timer()
    elseif owner.cp == 13 then
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

-- Note: last_toast_screen is kept up to date event-driven in push_mon() from niri workspaces.

-- Panels that are their own window (Spotlight, clipboard, wallpapers, Settings, the session dialog, the app
-- switcher) open on ONE monitor: the one with the focus. They are `screens: each` scenes that show their content
-- only where `open_screen` says (common/here.plm). Everything that wants one asks us (`open_panel N`): a niri key
-- through start.sh, a button in another panel. The toggle is the panel's own.
-- EVERYTHING that opens over the desktop is a panel of the `Panels` owner (its `cur` is the panel id), drawn by one of the panel scenes
local OVERLAY, FOCUS_PANELS = panel_data.dock, panel_data.focus
local function open_panel(n)
    local name = FOCUS_PANELS[tonumber(n) or 0]
    if not name then
        return
    end
    local function open_it(s)
        local p = PANELS[name]
        if p then
            fact[p.island .. "_screen"] = s          -- its glass is drawn by the frame, on that monitor
        end
        if OVERLAY[name] then
            overlay_screen(s)
            emit("Panels.toggle", OVERLAY[name])
            return
        end
        local function go()
            overlay_screen(s, name)
            send_toggle(name)
        end
        if name == "settings" and (fact["Panels.open"] == true or fact["Panels.open"] == 1) then
            -- Settings opened FROM a panel (Spotlight, the Control Center…): close the panel first and let its closing
            -- animation finish, or the old panel lingers over the new window, dimming it
            emit("Panels.close")
            after(260, go)
        else
            go()
        end
    end
    monitor_of_click(function(s)
        if name == "capture" then
            -- the picker is its own scene, started on demand (it ends itself when idle): make sure it is up first
            run("sh", { "-c", '"$(cat "$HOME/.config/beskar/shell-dir")/shell/start.sh" capture-ensure' }, function() open_it(s) end)
        else
            open_it(s)
        end
    end)
end
on("open_panel", open_panel)

-- Shortcuts and Spotlight use the frame's existing focused-monitor route.
on("open_session", function(screen)
    screen = tonumber(screen)
    if screen and screen >= 0 then fact.last_screen = screen end       -- asked from a panel: that panel's monitor
    hooks.call("prepare_menu")
    open_panel(panel_data.slots.session)
end)

-- ── the power menu (the gem button) ──────────────────────────────
local function say(scene, words)
    pcall(sys.call, "say", scene, words)
end
-- The monitor the power menu is on (`open_screen`), for the windows its items open.
-- the session / polkit / welcome dialogs live in ONE scene, `dialogs`; `cur` says which
local function show_dock_on_menu_monitor(id)        -- (the session dialog grows out of the dock: panel 11)
    local s = tonumber(fact.open_screen) or 0
    local p = BY_ID[id]
    if p then fact[p.island .. "_screen"] = s end          -- the frame draws the glass on the SAME monitor as the dialog
    overlay_screen(s)
    emit("Panels.show", id)
end
local function show_on_menu_monitor(name)
    overlay_screen(tonumber(fact.open_screen) or 0, name)
    emit(ALIAS[name] .. ".show")           -- only Settings is opened this way
end
local PM = {
    [1] = function() emit("Settings.set_tab", 6); show_on_menu_monitor("settings") end,         -- About This PC
    [2] = function() emit("Settings.set_tab", 0); show_on_menu_monitor("settings") end,         -- System Settings
    [8] = function() say("widgets", "emit edit_toggle") end,                                     -- Edit Widgets…
    [9] = function()
        hooks.call("prepare_menu")
        show_dock_on_menu_monitor(11)
    end,                                                                                 -- Session menu

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
every(30000, read_tray_hide)

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

-- ── dock: the apps you pinned, plus the ones running (shell/frame_dock.luau) ──
local dock = require("frame_dock")({ on = on, wins = function() return WINS end })
build_dock = dock.build_dock
local entry_for, name_of, pretty_app, lower = dock.entry_for, dock.name_of, dock.pretty_app, dock.lower
local frame_options = require("frame_options")

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
                        rank = k,
                    }
                end
            end
        end
    end
    model.cur_apps = list
end

push_mon = function()
        sync_outputs()
        local shown, busy = {}, {}
        local focused_output = nil
        for _, w in ipairs(WS) do
            if w.is_active and w.output then
                shown[w.output] = w.idx or 1
                busy[w.output] = w.id
            end
            if w.is_focused and w.output then
                focused_output = w.output
            end
        end
        if focused_output then
            for i, n in ipairs(OUTPUTS) do
                if n == focused_output and (i - 1) ~= last_toast_screen then
                    last_toast_screen = i - 1
                    emit("Panels.set_toast_mon", n)
                    emit("Notifications.set_toast_screen", i - 1)
                end
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
            recs[i] = { active = shown[name] or 1, busy = count[busy[name] or -1] or 0, nws = per_out[name] or 1,
                modules = require("frame_options").output_visible(fact["Settings.module_output_policy"], text["Settings.frame_output_name"], name, OUTPUTS, focused_output),
                dock = require("frame_options").output_visible(fact["Settings.dock_output_policy"], text["Settings.frame_output_name"], name, OUTPUTS, focused_output) }
        end
        model.mon = recs
        build_ws()
        build_cur()
    end

for _, name in ipairs({ "module_output_policy", "dock_output_policy" }) do on("fact:Settings." .. name, push_mon) end
on("text:Settings.frame_output_name", push_mon)
local edge = require("frame_options").edge_controller({
    delay = function() return fact["Settings.dock_show_delay"] end,
    after = after,
    reveal = function() emit("reveal") end,
})
on("reveal_edge", edge.enter)
on("leave_edge", edge.leave)

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

-- ── niri: the workspace each monitor shows ─────────────────────
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
    sync_outputs()
    refresh_workspaces()
    refresh_running()
end

run("niri", { "msg", "-j", "outputs" }, function(out, code)
    local ok, o = pcall(json.decode, out or "")
    if code == 0 and ok and type(o) == "table" then
        if not sync_outputs() or #OUTPUTS == 0 then
            local names = {}
            for name in pairs(o) do
                names[#names + 1] = name
            end
            table.sort(names)
            OUTPUTS = names
        end
    end
    refresh_niri()
end)

-- Screen learning fallback: sync_outputs() gets monitor names directly from pleamar
-- (text["screen.0.name"], text["screen.1.name"]), but if delayed, learn from log.
local function learn_screens(tries)
    -- one process for the whole desktop (desktop.plm): the log lines say which scene each surface is
    -- (`surface 5 on HDMI-A-1 · … · Topbar copy 1`); with one process per scene the topbar's own log has `surface N on NAME`
    local script = "if grep -q 'surface [0-9]* on .* Topbar' \"${BESKAR_DESKTOP_LOG:-/tmp/pleamar_desktop.log}\" 2>/dev/null; then "
        .. "grep 'surface [0-9]* on .* Topbar' \"${BESKAR_DESKTOP_LOG:-/tmp/pleamar_desktop.log}\" | head -8; "
        .. "else grep 'surface [0-9]* on' /tmp/pleamar_topbar.log 2>/dev/null | head -8; fi"
    run("sh", { "-c", script }, function(out)
        local map = {}
        local n = 0
        for line in (out or ""):gmatch("[^\n]+") do
            local name = line:match("surface %d+ on (%S+)")
            if name then
                local copy = line:match("Topbar copy (%d+)")
                local idx = copy and tonumber(copy) or (line:find("Topbar", 1, true) and 0 or nil)
                if idx == nil then
                    idx = tonumber(line:match("surface (%d+) on")) or n
                end
                map[idx + 1] = name
                n = n + 1
            end
        end
        if #map >= 2 or (#map > 0 and tries == 0) then
            OUTPUTS = map
            push_mon()
        elseif tries > 0 then
            after(2000, function() learn_screens(tries - 1) end)
        end
    end)
end
after(2000, function() learn_screens(4) end)

-- niri prints one JSON object per event. Debounce rapid window/workspace bursts
-- so moving or resizing windows doesn't flood process calls.
local refresh_timer = nil
local function schedule_refresh_niri()
    if not refresh_timer then
        refresh_timer = after(60, function()
            refresh_timer = nil
            refresh_niri()
        end)
    end
end

local streaming = false
local function follow_niri()
    if streaming then
        return
    end
    streaming = true
    spawn("niri", { "msg", "-j", "event-stream" }, function(line)
        if line:find("Workspace", 1, true) or line:find("WindowOpenedOrChanged", 1, true) or line:find("WindowClosed", 1, true) then
            schedule_refresh_niri()
        end
    end, function()
        streaming = false      -- niri went away; the timer below retries
    end)
end

follow_niri()
every(5000, follow_niri)

-- ── weather ──────────────────────────────────────────────────────
on("weather_reload", function() emit("Weather.reload_location") end)

-- ── updates: updates.luau checks pacman and tells us the count (`upd_n`); the arrow opens its panel ──
on("open_updates", open_island_panel("updates"))

-- the Updates panel's logic (its content is drawn in this scene's own surface: common/updates_panel.plm)
local panel_module = require("panelclient")({ updates = 16, control_center = 1, dashboard = 3, music = 9, weather = 15, personal = 25, timer = 26, spotlight = 4, wallpapers = 5, clipboard = 6, widget_bar = 10, session = 11, polkit = 12, welcome = 24, switcher = 21, overview = 22 })
panel_module("updates", require("updates_panel"))
-- the Control Center's logic (its content is drawn in this scene's own surface: common/cc_panel.plm)
panel_module("control_center", require("cc"))
-- weather, music, today, the timer and the Personal editor
require("info_panels")(panel_module)
-- Spotlight, the wallpaper strip, the clipboard and the widget bar
require("dock_panels")(panel_module)
-- the session dialog, polkit, welcome, the app switcher and the overview
require("dialog_panels")(panel_module)
require("window_panels")(panel_module)

-- one panel at a time
require("exclusive")("topbar")
