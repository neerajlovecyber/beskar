-- Read-only bridge for timer widgets. Snapshot on transitions; local display ticks only
-- while a visible timer card is running. No per-second socket messages or disk reads.
return function()
    local Timer = require("timer_state")
    local base = sys.ask("env", "XDG_DATA_HOME")
    if not base or base == "" then base = (sys.ask("env", "HOME") or "") .. "/.local/share" end
    local path = base .. "/pleamar/activities/timer.json"
    local active, state, revision = false, nil, -1
    local reading, pending, display_tick, reconnect = false, false, nil, nil
    local function paint()
        if display_tick then cancel(display_tick); display_tick = nil end
        if not active or not state then return end
        local remaining = Timer.remaining(state, os.time())
        local number = ({ idle = 0, running = 1, paused = 2, done = 3 })[state.status]
        -- The owner publishes the actual transition; an overdue local readout waits for it.
        fact.tw_ready = true
        fact.tw_state = number
        text.tw_time = Timer.format(remaining)
        text.tw_status = ({ idle = "Ready", running = "Running", paused = "Paused", done = "Time’s up" })[state.status]
        fact.tw_progress = state.status == "idle" and 0 or 1 - remaining / state.duration
        if state.status == "running" and remaining > 0 then display_tick = after(1000, function() display_tick = nil; paint() end) end
    end
    local function read()
        if not active then return end
        if reading then pending = true; return end
        reading = true
        run("cat", { path }, function(out, code)
            reading = false
            if active and code == 0 then
                local ok, saved = pcall(json.decode, out or "")
                local checked = ok and Timer.new(saved) or nil
                if checked then state, revision = checked, checked.revision; paint()
                else fact.tw_ready = false; text.tw_status = "Saved timer unavailable" end
            end
            if pending then pending = false; read() end
        end)
    end
    local function resync()
        if not active then return end
        local ok = pcall(sys.call, "say", "activities", "emit resync " .. revision)
        if not ok then fact.tw_ready = false; text.tw_status = "Timer service unavailable"
        elseif state then fact.tw_ready = true end
    end
    on("timer_changed", function(n) if active and tonumber(n) ~= revision then read() end end)
    on("tw_primary", function()
        if not active or not state or fact.editing then return end
        local op = ({ idle = "start " .. state.duration, running = "pause", paused = "resume", done = "start " .. state.duration })[state.status]
        pcall(sys.call, "say", "activities", "emit " .. op)
    end)
    on("tw_cancel", function()
        if active and state and not fact.editing then pcall(sys.call, "say", "activities", "emit cancel") end
    end)
    return function(wanted)
        wanted = wanted == true
        if wanted == active then return end
        active = wanted
        if active then
            read(); resync(); paint()
            reconnect = every(15000, resync)
        else
            if display_tick then cancel(display_tick); display_tick = nil end
            if reconnect then cancel(reconnect); reconnect = nil end
        end
    end
end
