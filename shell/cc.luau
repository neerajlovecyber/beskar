-- (the body of the Control Center scene: controlcenter.luau runs it as module("control_center", require("cc")))
local text = require("keys_text")     -- the text fields are the Keys scene's (keys_text.luau)
local Hooks = require("topbar_hooks")        -- the frame cannot emit to itself: its own events are called directly
return function(panel, opened, shown, closed)
-- Control Center companion logic

-- Every handler is also kept in H: the keyboard navigation at the end of the file calls them directly (this plugin cannot emit
-- an event to itself).
local base_on = on
local H = {}
local function on(name, fn) H[name] = fn; return base_on(name, fn) end
local panel_shown = shown                 -- (a Bluetooth local below is also called `shown`)
local ensure_valid = function() end          -- set by the keyboard code below, called when a list changes under the focus

-- The look is owned by Settings (it tells every scene, saves it to disk and tells GTK apps): here we only ASK it.
on("toggle_dark", function()
    local cur = (fact["Settings.dark_mode"] == true or fact["Settings.dark_mode"] == 1)
    emit("Settings.set_dark_mode", (cur and "0" or "1"))
end)

on("set_dark_mode", function(val)
    emit("Settings.set_dark_mode", (val == true or val == 1) and 1 or 0)
end)

on("choose_skin", function(val)
    emit("Settings.choose_skin", tonumber(val) or 0)
end)

on("volume_set", function(val)
    sys.call("audio.volume", val)
end)

on("brightness_set", function(val)
    sys.call("brightness.level", math.max(0.1, tonumber(val) or 1))
end)






on("pick_output", function(id)
    log("Control Center: Switching default audio sink to ID", id)
    sys.call("audio.default", id)
end)


-- ── the card's height, and telling the frame ───────────────────
-- The frame (topbar.plm) draws the glass, so it has to know how big the card is and whether it is open.
-- Counts of what the pages list are kept by the code below.
local wifi_n, bt_n, outs_n, apps_n = 0, 0, 1, 0
local outs_c, out_ids, app_vols = 0, {}, {}     -- real output count, their ids, each app stream's volume (keyboard)
local last_h = nil
local function push_height()
    local page = tonumber(fact.cc_page) or 0
    local h
    if page == 0 then
        h = 434
    elseif page == 1 then
        h = (fact.asking == true) and 240 or math.max(230, 176 + wifi_n * 40)
    elseif page == 2 then
        h = math.max(200, 78 + bt_n * 52)
    else
        h = math.max(190, 100 + outs_n * 40 + apps_n * 56 + (apps_n > 0 and 12 or 40))
    end
    if h ~= last_h then
        last_h = h
        panel.height(h)
    end
end
on("fact:cc_page", function() push_height(); fact.cc_focus = 0 end)
on("fact:asking", push_height)

-- ── Wi-Fi ────────────────────────────────────────────────────────
-- Rows are built here (active one first, then strongest) so they can say "Joining…". A secured
-- network that was never used asks for its password on a sheet; a known one just joins.
local net_state, shown_nets = {}, {}
local joining, joining_since = nil, 0

local function quality(p)
    if p >= 75 then return "Excellent" elseif p >= 50 then return "Good" elseif p >= 25 then return "Fair" end
    return "Weak"
end

local function paint_wifi()
    local list = {}
    for _, n in ipairs(net_state.networks or {}) do
        list[#list + 1] = n
    end
    table.sort(list, function(a, b)
        if (a.active == true) ~= (b.active == true) then return a.active == true end
        return (a.strength or 0) > (b.strength or 0)
    end)
    shown_nets = {}
    local rows = {}
    local current
    for _, n in ipairs(list) do
        if n.active then current = n end
        if #rows < 6 then
            shown_nets[#rows + 1] = n
            rows[#rows + 1] = {
                name = n.ssid, signal = n.strength or 0, secure = n.secure == true,
                known = n.known == true, active = n.active == true, joining = joining ~= nil and n.ssid == joining,
            }
        end
    end
    model.wifi_rows = rows
    wifi_n = #rows
    push_height()
    ensure_valid()
    if joining and current and current.ssid == joining then joining = nil end

    local wired = net_state.kind == "wired" and net_state.online
    local state, title, status = 1, "Not connected", "Choose a network below"
    if joining then
        state, title, status = 4, joining, "Joining…"
    elseif wired then
        state, title, status = 3, "Wired", net_state.name or "Connected by cable"
    elseif net_state.wifi == false then
        state, title, status = 0, "Wi-Fi is off", "The radio is resting"
    elseif current or (net_state.online and net_state.kind == "wifi") then
        local p = math.floor((current and (current.strength or 0) * 100) or (net_state.strength or 0) + 0.5)
        state = 2
        title = (current and current.ssid) or net_state.name or ""
        status = string.format("%s · %d%%", quality(p), p)
        fact.wifi_signal = p / 100
    elseif net_state.error and net_state.error ~= "none" and net_state.error ~= "" then
        status = "Could not join (" .. tostring(net_state.error) .. ")"
    end
    fact.wifi_state = state
    text.wifi_title = title
    text.wifi_status = status
end

sys.watch("network", function(n)
    net_state = n or {}
    fact.net_online = (n and n.online) == true
    text.net_name = (n and n.name) or ""
    paint_wifi()
end)

-- A network that never answers must not stay "joining" forever.
every(3000, function()
    if joining and os.time() - joining_since > 25 then
        joining = nil
        paint_wifi()
    end
end)

local function join(ssid, password)
    joining, joining_since = ssid, os.time()
    local ok, err = pcall(sys.call, "network.connect", ssid, password)
    if not ok then
        log("wi-fi ·", err)
        joining = nil
    end
    paint_wifi()
end

local ask_index
local function stop_asking()
    fact.asking = false
    text.wifi_pw = ""
    text.ask_error = ""
    ask_index = nil
end

on("pick_network", function(i)
    local n = shown_nets[(i or 0) + 1]
    if not n or n.active or joining then
        return
    end
    if n.secure and not n.known then
        ask_index = (i or 0) + 1
        text.ask_name = n.ssid
        text.wifi_pw = ""
        text.ask_error = ""
        fact.asking = true
    else
        join(n.ssid)
    end
end)

on("wifi_join", function()
    local n = ask_index and shown_nets[ask_index]
    local pw = text.wifi_pw or ""
    if not n then
        return
    end
    if pw == "" then
        text.ask_error = "Type the password first"
        return
    end
    stop_asking()
    join(n.ssid, pw)
end)
on("wifi_cancel", stop_asking)
on("wifi_disconnect", function()
    joining = nil
    pcall(sys.call, "network.disconnect")
    paint_wifi()
end)
on("wifi_power", function() pcall(sys.call, "network.wifi", true) end)
on("toggle_wifi", function()
    pcall(sys.call, "network.wifi", net_state.wifi == false)
end)
on("wifi_rescan", function() pcall(sys.call, "network.scan") end)

-- ── Do Not Disturb: no banners while it is on (they still land in the centre) ──
on("set_page", function(n) fact.cc_page = tonumber(n) or 0 end)

on("toggle_dnd", function()
    local now_on = not (fact["Notifications.dnd"] == true)           -- the notification centre owns it: ask it
    local v = tostring(now_on)
    emit("Notifications.set_dnd", now_on)
end)

-- ── the four round shortcuts ─────────────────────────────────────
local function open_later(n)
    -- the panel is closing; give it a moment so the new window does not fight it for focus
    after(250, function() Hooks.emit("Topbar.open_panel", n) end)
end
on("sc_search", function() open_later(1) end)
on("sc_clip", function() open_later(2) end)
on("sc_shot", function() open_later(11) end)
on("sc_session", function()
    -- the session chooser opens on the monitor this panel is on (niri's focused output may be the other one)
    local screen = tonumber(fact["Panels.open_screen"])
    after(250, function() Hooks.emit("Topbar.open_session", screen) end)
end)

-- ── Settings shortcut ────────────────────────────────────────────
on("open_settings", function()
    Hooks.emit("Topbar.open_panel", 4)          -- through the frame: it lets this panel finish closing first
end)

-- (what is playing and the player controls are the System scene's: system.luau)

-- ── Bluetooth ────────────────────────────────────────────────────
-- Paired devices (connected first) and, while searching, the new ones near. Each row carries one
-- action: Connect / Disconnect / Pair. `busy` marks the one being worked on until its state changes.
local KINDS = {
    ["audio-headphones"] = 1, ["audio-headset"] = 1,
    ["input-mouse"] = 2, ["input-keyboard"] = 3, ["phone"] = 4,
    ["computer"] = 5, ["input-gaming"] = 6, ["audio-card"] = 7, ["audio-speakers"] = 7,
}
local last_connected = nil
local bt_state, shown = {}, {}
local busy_address, busy_word, busy_ticks = nil, "", 0
local failed_address, failed_until = nil, 0     -- the last one that did not answer, shown for a while

local function paint_bt()
    local mine, near = {}, {}
    for _, d in ipairs(bt_state.devices or {}) do
        if d.paired then
            mine[#mine + 1] = d
        elseif bt_state.discovering and (d.name or "") ~= "" then
            near[#near + 1] = d
        end
    end
    table.sort(mine, function(a, b)
        if (a.connected == true) ~= (b.connected == true) then
            return a.connected == true
        end
        return (a.name or "") < (b.name or "")
    end)
    shown = {}
    local rows = {}
    local function add(d)
        if #rows >= 8 then
            return
        end
        local state, status
        if d.address == busy_address then
            state, status = 2, busy_word
        elseif d.address == failed_address and os.time() < failed_until and not d.connected then
            state, status = 0, "Not reachable"
        elseif d.connected then
            state, status = 1, "Connected"
        elseif d.paired then
            state, status = 0, "Paired"
        else
            state, status = 3, "New device"
        end
        shown[#rows + 1] = d
        rows[#rows + 1] = {
            name = (d.name or "") ~= "" and d.name or d.address,
            status = status,
            kind = KINDS[d.icon or ""] or 0,
            state = state,
            battery = d.battery or -1,
        }
    end
    for _, d in ipairs(mine) do add(d) end
    for _, d in ipairs(near) do add(d) end
    model.bt_rows = rows
    bt_n = #rows
    push_height()
    ensure_valid()

    local present = bt_state.present ~= false
    fact.bt_present = present
    fact.bt_on = present and bt_state.powered == true
    fact.bt_scanning = bt_state.discovering == true
    local any_connected = false
    for _, d in ipairs(bt_state.devices or {}) do
        if d.connected then any_connected = true end
    end
    if any_connected ~= last_connected then
        last_connected = any_connected
        fact.bt_connected = any_connected == true
    end
    local first = mine[1]
    text.bt_sub = (first and first.connected) and first.name
        or ((present and bt_state.powered) and "On" or "Off")
end

sys.watch("bluetooth", function(state)
    local was = {}
    for _, d in ipairs(bt_state.devices or {}) do
        was[d.address] = d.connected
    end
    bt_state = state or {}
    if busy_address then
        for _, d in ipairs(bt_state.devices or {}) do
            if d.address == busy_address and was[d.address] ~= nil and was[d.address] ~= d.connected then
                busy_address = nil
            end
        end
    end
    paint_bt()
end)

-- The top bar may have been restarted: tell it again now and then.
every(15000, function()
    if last_connected ~= nil then
        fact.bt_connected = last_connected == true
    end
end)

-- A device that never answers must not stay "working" forever.
every(2000, function()
    if failed_address and os.time() >= failed_until then
        failed_address = nil
        paint_bt()
    end
    if busy_address then
        busy_ticks = busy_ticks + 1
        if busy_ticks > 5 then
            failed_address, failed_until = busy_address, os.time() + 10
            busy_address = nil
            paint_bt()
        end
    end
end)

on("bt_action", function(i)
    local d = shown[(i or 0) + 1]
    if not d or not d.address or busy_address then
        return
    end
    busy_address, busy_ticks = d.address, 0
    busy_word = d.connected and "Disconnecting…" or (d.paired and "Connecting…" or "Pairing…")
    paint_bt()
    local ok, err = pcall(sys.call, d.connected and "bluetooth.disconnect" or "bluetooth.connect", d.address)
    if not ok then
        log("bluetooth ·", err)
        busy_address = nil
        paint_bt()
    end
end)

on("bt_power", function()
    pcall(sys.call, "bluetooth.power", not (bt_state.powered == true))
end)
on("toggle_bt", function()
    pcall(sys.call, "bluetooth.power", not (bt_state.powered == true))
end)
on("bt_scan", function()
    pcall(sys.call, "bluetooth.scan", not (bt_state.discovering == true))
end)

-- Stop listening for new devices when the panel closes.
opened(function()
    push_height()
    fact.cc_focus = 0                       -- keyboard focus starts on the first item of the page
end)
closed(function()
    stop_asking()
    require("topbar_hooks").focus()
    fact.cc_page = 0                        -- reopening starts on the overview with the focus on its first item
    fact.cc_focus = 0
    if bt_state.discovering then
        pcall(sys.call, "bluetooth.scan", false)
    end
end)


-- ── Sound: each app's own volume ─────────────────────────────────
local app_ids = {}
sys.watch("audio", function(a)
    local rows = {}
    app_ids = {}
    for _, app in ipairs((a and a.apps) or {}) do
        if #rows < 4 then
            app_ids[#rows + 1] = app.id
            local label = app.name or app.binary or "App"
            if (app.title or "") ~= "" and app.title ~= label then
                label = label .. " · " .. app.title
            end
            rows[#rows + 1] = { name = label, volume = app.volume or 0, muted = app.muted == true }
        end
    end
    model.app_rows = rows
    apps_n = #rows
    app_vols = {}
    for i, r in ipairs(rows) do app_vols[i] = r.volume end
    local outs = {}
    for _, o in ipairs((a and a.outputs) or {}) do
        outs[#outs + 1] = { id = o.id, name = o.name or "", default = o.default == true }
    end
    model.outs = outs
    outs_c = #outs
    out_ids = {}
    for i, o in ipairs(outs) do out_ids[i] = o.id end
    outs_n = math.max(1, #outs)
    fact.snd_volume = tonumber(a and a.volume) or 0
    fact.snd_muted = (a and a.muted) == true
    push_height()
    ensure_valid()
end)
sys.watch("brightness", function(b)
    fact.disp_level = tonumber(b and b.level) or 1
end)

on("app_volume", function(v)
    v = tonumber(v) or 0
    local idx = math.floor(v)
    local frac = math.min(1, (v - idx) / 0.999)
    local id = app_ids[idx + 1]
    if id then
        pcall(sys.call, "audio.app_volume", id, frac)
    end
end)


-- ── keyboard ─────────────────────────────────────────────────────
-- The frame's rules (common/cc_panel.plm) send `cc_key(code)`; the focus is the fact `cc_focus` (a SLOT of the page, drawn as a
-- ring by the panel). Up / Down / Tab move it, Left / Right adjust a slider, switch the player's track or step inside a row of
-- tiles, Enter / space act on release (and only after their own press was seen here, so the Enter that opened or submitted
-- something never fires the item under it), Escape leaves a sub-page, then closes.
local function truthy(v) return v == true or v == 1 end
local function page_n() return tonumber(fact.cc_page) or 0 end
local function focus_n() return tonumber(fact.cc_focus) or 0 end
local MAX_SLOT = { [0] = 11, 8, 9, 9 }
local ROWS0 = { { 0 }, { 1 }, { 2 }, { 3, 4, 5 }, { 6 }, { 7 }, { 8, 9, 10, 11 } }

local function present(page, s)
    if s < 0 or s > (MAX_SLOT[page] or 0) then return false end
    if page == 0 then
        if s == 2 then return truthy(fact["System.has_player"]) end
        return true
    elseif page == 1 then
        local st = tonumber(fact.wifi_state) or 1
        if s == 0 then return true end
        if s == 1 then return st == 0 or st == 2 or st == 4 end
        if s == 2 then return st ~= 0 end
        return s - 3 < wifi_n and st ~= 0
    elseif page == 2 then
        if s == 0 then return truthy(fact.bt_present) end
        if s == 1 then return truthy(fact.bt_on) end
        return s - 2 < bt_n
    end
    if s < 6 then return s < outs_c end
    return s - 6 < apps_n
end

local function first_present(page)
    for s = 0, MAX_SLOT[page] or 0 do
        if present(page, s) then return s end
    end
    return 0
end

local function step(delta)
    local page = page_n()
    local n = (MAX_SLOT[page] or 0) + 1
    local s = focus_n()
    for _ = 1, n do
        s = (s + delta) % n
        if present(page, s) then fact.cc_focus = s; return end
    end
end

ensure_valid = function()
    if not present(page_n(), focus_n()) then fact.cc_focus = first_present(page_n()) end
end

-- the overview is a grid: Up / Down go row to row (keeping the column where the row has several), Left / Right along a row
local col_mem = 1
local function row_of0(s)
    for r, row in ipairs(ROWS0) do
        for c, v in ipairs(row) do
            if v == s then return r, c end
        end
    end
    return 1, 1
end
local function move0(dir)
    local r, c = row_of0(focus_n())
    for _ = 1, #ROWS0 do
        r = (r - 1 + dir) % #ROWS0 + 1
        local row = ROWS0[r]
        local want = math.min(col_mem, #row)
        if present(0, row[want]) then fact.cc_focus = row[want]; return end
    end
end
local function side0(dir)
    local r, c = row_of0(focus_n())
    local row = ROWS0[r]
    local nc = c + dir
    if nc >= 1 and nc <= #row then
        fact.cc_focus = row[nc]
        col_mem = nc
    end
end

local function adjust(dir)
    local s = focus_n()
    if page_n() == 0 and s == 6 then
        local v = (tonumber(fact.disp_level) or 1) + dir * 0.05
        H.brightness_set(math.max(0.1, math.min(1, v)))
    elseif page_n() == 0 and s == 7 then
        local v = (tonumber(fact.snd_volume) or 0) + dir * 0.05
        H.volume_set(math.max(0, math.min(1, v)))
    elseif page_n() == 3 and s >= 6 then
        local id, vol = app_ids[s - 5], app_vols[s - 5]
        if id and vol then pcall(sys.call, "audio.app_volume", id, math.max(0, math.min(1, vol + dir * 0.05))) end
    end
end

local function go_back()
    require("topbar_hooks").focus()
    if fact.asking == true then H.wifi_cancel(); return end
    if page_n() ~= 0 then fact.cc_page = 0 else panel.close() end
end

local function leave(fn)           -- an action that hands over to something else: it closes the panel first
    fn()
    panel.close()
    fact.cc_page = 0
end

local function activate(by_space)
    local page, s = page_n(), focus_n()
    if page == 0 then
        if s == 0 then if by_space then H.toggle_wifi() else fact.cc_page = 1 end
        elseif s == 1 then if by_space then H.toggle_bt() else fact.cc_page = 2 end
        elseif s == 2 then emit("System.play_pause")
        elseif s == 3 then H.toggle_dnd()
        elseif s == 4 then H.toggle_dark()
        elseif s == 5 then leave(H.open_settings)
        elseif s == 7 then fact.cc_page = 3
        elseif s == 8 then leave(H.sc_search)
        elseif s == 9 then leave(H.sc_clip)
        elseif s == 10 then leave(H.sc_shot)
        elseif s == 11 then leave(H.sc_session) end
    elseif page == 1 then
        local st = tonumber(fact.wifi_state) or 1
        if s == 0 then H.toggle_wifi()
        elseif s == 1 then if st == 0 then H.wifi_power() else H.wifi_disconnect() end
        elseif s == 2 then H.wifi_rescan()
        else H.pick_network(s - 3) end
    elseif page == 2 then
        if s == 0 then H.bt_power()
        elseif s == 1 then H.bt_scan()
        else H.bt_action(s - 2) end
    else
        if s < 6 and out_ids[s + 1] then H.pick_output(out_ids[s + 1]) end
    end
end

local armed_enter, armed_space = false, false
base_on("cc_key", function(code)
    code = tonumber(code)
    if not panel_shown() or not code then return end
    if fact.asking == true then                   -- the password sheet owns the keys: only Escape (cancel) is ours
        armed_enter, armed_space = false, false
        if code == 9 then go_back() end
        return
    end
    ensure_valid()
    local page, s = page_n(), focus_n()
    if code == 9 then go_back()
    elseif code == 5 then step(1)
    elseif code == 6 then step(-1)
    elseif code == 1 or code == 2 then
        if page == 0 then move0(code == 1 and -1 or 1) else step(code == 1 and -1 or 1) end
    elseif code == 3 or code == 4 then
        local dir = code == 3 and -1 or 1
        if page == 0 then
            if s == 6 or s == 7 then adjust(dir)
            elseif s == 2 then emit(dir < 0 and "System.previous" or "System.next")
            elseif s == 0 and dir > 0 then fact.cc_page = 1
            elseif s == 1 and dir > 0 then fact.cc_page = 2
            else side0(dir) end
        elseif page == 3 and s >= 6 then adjust(dir)
        elseif dir < 0 then fact.cc_page = 0 end        -- Left on a sub-page: back
    elseif code == 10 then armed_enter = true
    elseif code == 11 then armed_space = true
    elseif code == 20 then
        if armed_enter then armed_enter = false; activate(false) end
    elseif code == 21 then
        if armed_space then armed_space = false; activate(true) end
    end
end)

-- one panel at a time

end
