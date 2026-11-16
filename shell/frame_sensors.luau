-- The frame's polled sensors, split out of topbar.luau: the charger (a card when it is plugged in or out) and privacy (camera,
-- microphone, screen share: the bar's dots and a card when one starts). `env` hands over what the frame owns: `owner` (who has
-- the centre island), `PRIORITIES` and `card_open`. A card is shown only if nothing of a higher priority has the island.
return function(env)
    local owner, PRIORITIES, card_open = env.owner, env.PRIORITIES, env.card_open

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

    local POWER_SCRIPT = [[
    ac=0
    grep -q 1 /sys/class/power_supply/A*/online 2>/dev/null && ac=1
    echo "$ac $(cat /sys/class/power_supply/BAT*/status 2>/dev/null | head -1) $(cat /sys/class/power_supply/BAT*/capacity 2>/dev/null | head -1)"
    ]]

    local last_ac = nil
    local function poll_power()
        run("sh", { "-c", POWER_SCRIPT }, function(out)
            local ac, status, pct = (out or ""):match("^(%d) (.-) (%d+)%s*$")
            if not ac then return end
            local plugged = ac == "1"
            if fact.bat_ac ~= plugged then
                fact.bat_ac = plugged
            end
            if text.bat_status ~= status then
                text.bat_status = status
            end
            if last_ac ~= nil and plugged ~= last_ac then
                show_charging_activity(plugged, status, tonumber(pct) or 0)
            end
            last_ac = plugged
        end)
    end
    poll_power()
    every(6000, poll_power)

    -- ── privacy: camera and microphone in use ───────────────────────
    -- The camera is "in use" while some process has a /dev/video* node open (fuser); the microphone while some program
    -- is recording from a source (PipeWire / PulseAudio source-outputs). Nothing is recorded or logged here.
    local PRIVACY = [[
    cam=0
    fuser /dev/video* >/dev/null 2>&1 && cam=1
    mic=0
    pactl list short source-outputs 2>/dev/null | grep -q . && mic=1
    scr=0
    niri msg -j casts 2>/dev/null | grep -q '"' && scr=1
    echo "$cam $mic $scr"
    ]]

    local last_cam, last_mic = nil, nil

    local function show_privacy_activity(is_cam)
        if owner.cp and (PRIORITIES[owner.cp] or 0) > 20 then
            return
        end
        card_open(14, 3000, { glyph = is_cam and "󰄀" or "󰍬", title = is_cam and "Camera in use" or "Microphone in use", sub = "An app is using it right now", tone = is_cam and 1 or 2 })
    end

    local last_scr = nil
    local function poll_privacy()
        run("sh", { "-c", PRIVACY }, function(out)
            local cam, mic, scr = (out or ""):match("(%d) (%d) ?(%d?)")
            if cam then
                local is_cam = cam == "1"
                local is_mic = mic == "1"
                local is_scr = scr == "1"          -- niri is casting a screen or a window (a call, a recording through the portal)
                if fact.priv_scr ~= is_scr then fact.priv_scr = is_scr end
                if last_scr ~= nil and (not last_scr) and is_scr and not (owner.cp and (PRIORITIES[owner.cp] or 0) > 20) then
                    card_open(14, 3000, { glyph = "󰹑", title = "Screen is being shared", sub = "An app is casting your screen", tone = 3 })
                end
                last_scr = is_scr
                if fact.priv_cam ~= is_cam then
                    fact.priv_cam = is_cam
                end
                if fact.priv_mic ~= is_mic then
                    fact.priv_mic = is_mic
                end
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
    every(6000, poll_privacy)
end
