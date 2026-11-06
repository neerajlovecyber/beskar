-- Control Center companion logic

local function broadcast_theme()
    local dm = (fact.dark_mode == true or fact.dark_mode == 1)
    local dm_str = tostring(dm)
    local skin_str = tostring(fact.skin or 0)
    
    local scenes = {"topbar", "dock", "spotlight", "apple_menu", "widgets", "osd", "settings"}
    for _, s in ipairs(scenes) do
        pcall(sys.call, "say", s, "fact dark_mode " .. dm_str)
        pcall(sys.call, "say", s, "fact skin " .. skin_str)
    end

    -- Save to config file for persistence across restarts
    pcall(function()
        local home = os.getenv("HOME") or "/home/nsp"
        local f = io.open(home .. "/.config/pleamar_shell.json", "w")
        if f then
            f:write(string.format('{"dark_mode": %s, "skin": %s}\n', dm_str, skin_str))
            f:close()
        end
    end)

    -- Synchronize system color scheme
    pcall(function()
        local scheme = dm and "prefer-dark" or "prefer-light"
        os.execute("gsettings set org.gnome.desktop.interface color-scheme " .. scheme .. " 2>/dev/null &")
    end)
end

on("toggle_dark", function()
    local cur = (fact.dark_mode == true or fact.dark_mode == 1)
    fact.dark_mode = not cur
    broadcast_theme()
end)

on("set_dark_mode", function(val)
    fact.dark_mode = (val == true or val == 1)
    broadcast_theme()
end)

on("choose_skin", function(val)
    fact.skin = tonumber(val) or 0
    broadcast_theme()
end)

on("volume_set", function(val)
    sys.call("audio.volume", val)
end)

on("brightness_set", function(val)
    sys.call("brightness.level", val)
end)




on("pick_network", function(idx)
    log("Control Center: Picked network index", idx)
    local net = model.nets and model.nets[idx + 1]
    if net and net.ssid then
        log("Control Center: Connecting to SSID", net.ssid)
        sys.call("network.connect", net.ssid)
    end
end)


on("pick_output", function(id)
    log("Control Center: Switching default audio sink to ID", id)
    sys.call("audio.default", id)
end)


-- ── Wi-Fi radio ──────────────────────────────────────────────────
local wifi_radio = true
sys.watch("network", function(n)
    wifi_radio = not n or n.wifi ~= false
end)
on("toggle_wifi", function()
    pcall(sys.call, "network.wifi", not wifi_radio)
end)

-- ── Settings shortcut ────────────────────────────────────────────
on("open_settings", function()
    pcall(sys.call, "say", "settings", "emit toggle")
end)

-- ── Now playing ──────────────────────────────────────────────────
local playing, pos, len, rate = false, 0, 0, 1

local function clock(sec)
    sec = math.max(0, math.floor(sec or 0))
    return string.format("%d:%02d", sec // 60, sec % 60)
end

local function paint_time()
    text.time_pos = clock(pos)
    text.time_len = clock(len)
    fact.track_pos = pos
end

sys.watch("media", function(m)
    m = m or {}
    local title = m.title or ""
    local has = (m.player or "") ~= "" or title ~= ""
    playing = m.playing == true
    pos, len, rate = m.position or 0, m.length or 0, m.rate or 1
    fact.has_player = has
    fact.is_playing = playing
    fact.track_len = len
    fact.has_art = (m.art or "") ~= ""
    text.track_title = title ~= "" and title or "Unknown title"
    text.track_artist = m.artist or ""
    text.cover_art = m.art or ""
    paint_time()
end)

-- The player reports the position once; carry it on between reports.
every(1000, function()
    if playing and len > 0 then
        pos = math.min(pos + rate, len)
        paint_time()
    end
end)

on("play_pause", function() pcall(sys.call, "media.toggle") end)
on("previous", function() pcall(sys.call, "media.previous") end)
on("next", function() pcall(sys.call, "media.next") end)
on("seek", function(frac)
    if len > 0 then
        pcall(sys.call, "media.seek", math.floor((tonumber(frac) or 0) * len))
    end
end)

-- ── Bluetooth ────────────────────────────────────────────────────
-- Paired devices (connected first) and, while searching, the new ones near. Each row carries one
-- action: Connect / Disconnect / Pair. `busy` marks the one being worked on until its state changes.
local KINDS = {
    ["audio-headphones"] = 1, ["audio-headset"] = 1,
    ["input-mouse"] = 2, ["input-keyboard"] = 3, ["phone"] = 4,
    ["computer"] = 5, ["input-gaming"] = 6, ["audio-card"] = 7, ["audio-speakers"] = 7,
}
local bt_state, shown = {}, {}
local busy_address, busy_word, busy_ticks = nil, "", 0

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

    local present = bt_state.present ~= false
    fact.bt_present = present
    fact.bt_on = present and bt_state.powered == true
    fact.bt_scanning = bt_state.discovering == true
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

-- A device that never answers must not stay "working" forever.
every(2000, function()
    if busy_address then
        busy_ticks = busy_ticks + 1
        if busy_ticks > 10 then
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
on("fact:open", function(v)
    if not v and bt_state.discovering then
        pcall(sys.call, "bluetooth.scan", false)
    end
end)
