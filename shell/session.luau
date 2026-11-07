-- Session dialog logic: shut down, restart, log out (with a 60 s countdown)

local timer_id = nil

local function clear_timer()
    if timer_id then
        cancel(timer_id)
        timer_id = nil
    end
end

on("confirm_action", function()
    clear_timer()
    fact.open = false
    local k = fact.kind or 0
    if k == 0 then
        log("Session: Powering off system...")
        run("systemctl", { "poweroff" }, function(_, code)
            if code ~= 0 then
                log("Session: poweroff failed with code", code)
            end
        end)
    elseif k == 1 then
        log("Session: Restarting system...")
        run("systemctl", { "reboot" }, function(_, code)
            if code ~= 0 then
                log("Session: reboot failed with code", code)
            end
        end)
    else
        log("Session: Logging out...")
        run("niri", { "msg", "action", "quit", "--skip-confirmation" })
    end
end)

on("fact:open", function()
    if fact.open == true then
        fact.countdown = 60
        clear_timer()
        -- Countdown loop
        local function tick()
            if fact.open ~= true then return end
            if fact.countdown > 1 then
                fact.countdown = fact.countdown - 1
                timer_id = after(1000, tick)
            else
                emit("confirm_action")
            end
        end
        timer_id = after(1000, tick)
    else
        clear_timer()
    end
end)
