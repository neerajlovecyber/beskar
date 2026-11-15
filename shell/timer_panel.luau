-- Panel presentation and keyboard focus; all timer mutations belong to Activities.
return function(panel, opened, shown, closed)
    local Timer = require("timer_state")
    local submitted, programmatic = false, nil
    local armed = false          -- the release of the Enter that opened the panel must not act on it
    local preset
    local function state() return tonumber(fact["Activities.timer_state"]) or 0 end
    local function editing() return state() == 0 or state() == 3 end
    local function draft()
        local seconds, formatted = Timer.parse(text.tm_duration or "")
        fact.tm_valid = seconds ~= nil
        fact.tm_seconds = seconds or 0
        text.tm_preview = formatted or "—:—"
        text.tm_hint = seconds and (formatted .. " · maximum 24 hours") or "Use minutes, 1h30m, or 0:30 · maximum 24 hours"
        return seconds
    end
    local function set_focus(index)
        fact.tm_focus = index
        if index == -1 then focus("tm_duration") else focus() end
    end
    local function sync()
        if not shown() then return end
        if not editing() and tonumber(fact.tm_focus) == -1 then set_focus(0) end
        draft()
    end
    local function primary()
        if not shown() or not fact["Activities.ready"] then return end
        if editing() then
            local seconds = draft()
            if not seconds then set_focus(-1); return end
            emit("Activities.start", seconds)
            set_focus(0)
        elseif state() == 1 then emit("Activities.pause")
        elseif state() == 2 then emit("Activities.resume") end
    end
    local function secondary()
        if not shown() then return end
        if state() == 0 then panel.close()
        elseif state() == 3 then emit("Activities.dismiss")
        else emit("Activities.cancel") end
    end
    on("tm_primary", primary)
    on("tm_secondary", secondary)
    on("tm_submit", function() if editing() then submitted = true; primary() end end)
    on("tm_activate", function()
        if submitted then submitted = false; return end
        if not armed then return end
        local f = tonumber(fact.tm_focus)
        if f == 1 then secondary()
        elseif f == 2 then preset(300)
        elseif f == 3 then preset(600)
        elseif f == 4 then preset(1500)
        else primary() end
    end)
    on("tm_move", function(delta)
        if not shown() then return end
        -- focus order: the duration field (-1), the three presets (2 3 4), then the two buttons (0 1); a running timer has only the buttons
        local order = editing() and { -1, 2, 3, 4, 0, 1 } or { 0, 1 }
        local at = 1
        for i, v in ipairs(order) do if v == (tonumber(fact.tm_focus) or order[1]) then at = i end end
        set_focus(order[(at - 1 + (tonumber(delta) or 1)) % #order + 1])
    end)
    function preset(seconds)
        if not shown() or not editing() then return end
        local presets = { [300] = true, [600] = true, [1500] = true }
        seconds = tonumber(seconds)
        if not presets[seconds] then return end
        programmatic = tostring(seconds / 60):gsub("%.0$", "")
        text.tm_duration = programmatic
        draft(); set_focus(0)
    end
    on("tm_preset", preset)
    on("text:tm_duration", function()
        if shown() and editing() then
            if text.tm_duration ~= programmatic then fact.tm_focus = -1 end
            programmatic = nil; draft()
        end
    end)
    on("fact:Activities.timer_state", sync)
    opened(function()
        submitted = false
        armed = false; after(350, function() armed = true end)
        if editing() then
            local duration = tonumber(fact["Activities.timer_duration"]) or 1500
            programmatic = duration % 60 == 0 and tostring(math.floor(duration / 60)) or (duration .. "s")
            text.tm_duration = programmatic
        end
        draft(); set_focus(editing() and -1 or 0)
    end)
    closed(function() focus() end)
    panel.height(350)
    draft()
end
