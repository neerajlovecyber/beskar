-- macOS Control Center Logic
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
    -- toggle wifi radio state
    sys.call("network.wifi.toggle")
end)

on("toggle_bt", function()
    -- toggle bluetooth powered state
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
