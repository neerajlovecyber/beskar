-- macOS Control Center Companion Logic

local function broadcast_theme()
    local dm = (fact.dark_mode == true or fact.dark_mode == 1)
    local dm_str = tostring(dm)
    local skin_str = tostring(fact.skin or 0)
    
    local scenes = {"topbar", "dock", "spotlight", "apple_menu"}
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

on("play_pause", function()
    sys.call("media.toggle")
end)

on("toggle_wifi", function()
    sys.call("network.wifi.toggle")
end)

on("toggle_bt", function()
    sys.call("bluetooth.toggle")
end)

on("pick_network", function(idx)
    log("Control Center: Picked network index", idx)
    local net = model.nets and model.nets[idx + 1]
    if net and net.ssid then
        log("Control Center: Connecting to SSID", net.ssid)
        sys.call("network.connect", net.ssid)
    end
end)

on("pick_device", function(idx)
    log("Control Center: Picked bluetooth device index", idx)
    local dev = model.gadgets and model.gadgets[idx + 1]
    if dev and dev.address then
        log("Control Center: Connecting to BT device", dev.name, dev.address)
        sys.call("bluetooth.connect", dev.address)
    end
end)

on("pick_output", function(id)
    log("Control Center: Switching default audio sink to ID", id)
    sys.call("audio.default", id)
end)
