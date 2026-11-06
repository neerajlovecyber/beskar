-- macOS Bezel On-Screen Display (OSD) Companion Logic

local dismiss_timer = nil

local function show_osd(kind, level, muted)
    fact.kind = kind
    fact.level = math.min(1, math.max(0, level or 0))
    fact.muted = (muted == true)
    fact.open = true

    if dismiss_timer then
        pcall(cancel, dismiss_timer)
        dismiss_timer = nil
    end

    dismiss_timer = after(1500, function()
        fact.open = false
        dismiss_timer = nil
    end)
end

-- Watch audio updates from the system/sound server
local last_vol = nil
local last_mute = nil
pcall(sys.watch, "audio", function(data)
    if data and data.volume ~= nil then
        local vol = data.volume
        local mute = (data.muted == true)
        if last_vol ~= nil and (math.abs(vol - last_vol) > 0.005 or mute ~= last_mute) then
            show_osd(0, vol, mute)
        end
        last_vol = vol
        last_mute = mute
    end
end)

-- Watch display brightness updates
local last_br = nil
pcall(sys.watch, "brightness", function(data)
    if data and data.level ~= nil then
        local br = data.level
        if last_br ~= nil and math.abs(br - last_br) > 0.005 then
            show_osd(1, br, false)
        end
        last_br = br
    end
end)

on("popup", function()
    show_osd(fact.kind or 0, fact.level or 0.5, fact.muted or false)
end)

on("volume_up", function()
    pcall(sys.call, "audio.step", 0.05)
    local cur = last_vol or fact.level or 0.5
    local nxt = math.min(1, cur + 0.05)
    last_vol = nxt
    last_mute = false
    show_osd(0, nxt, false)
end)

on("volume_down", function()
    pcall(sys.call, "audio.step", -0.05)
    local cur = last_vol or fact.level or 0.5
    local nxt = math.max(0, cur - 0.05)
    last_vol = nxt
    last_mute = false
    show_osd(0, nxt, false)
end)

on("volume_mute", function()
    pcall(sys.call, "audio.mute")
    last_mute = not (last_mute or false)
    show_osd(0, last_vol or fact.level or 0.5, last_mute)
end)

on("brightness_up", function()
    local cur = last_br or fact.level or 0.5
    local nxt = math.min(1, cur + 0.05)
    pcall(sys.call, "brightness.level", nxt)
    last_br = nxt
    show_osd(1, nxt, false)
end)

on("brightness_down", function()
    local cur = last_br or fact.level or 0.5
    local nxt = math.max(0.05, cur - 0.05)
    pcall(sys.call, "brightness.level", nxt)
    last_br = nxt
    show_osd(1, nxt, false)
end)
