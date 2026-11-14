-- Session panel controller. All mutable state stays in Dialogs; no additional owner or watcher.
local Hooks = require("topbar_hooks")        -- the frame cannot emit to itself: its own events are called directly
return function(panel, opened, shown, closed)
    local actions = {
        { label = "Lock", glyph = "󰌾", detail = "Lock your screen", kind = -1, danger = false },
        { label = "Sleep", glyph = "󰤄", detail = "Put the computer to sleep", kind = 3, danger = false },
        { label = "Log Out", glyph = "󰍃", detail = "End your session", kind = 2, danger = false },
        { label = "Restart", glyph = "󰜉", detail = "Restart the computer", kind = 1, danger = false },
        { label = "Shut Down", glyph = "󰐥", detail = "Turn off the computer", kind = 0, danger = true },
    }
    model.ses_actions = actions
    panel.height(250)
    local timer_id, from_menu = nil, true
    local perform

    local function clear_timer()
        if timer_id then cancel(timer_id); timer_id = nil end
    end
    local function select(index)
        fact.ses_index = index % #actions
        text.ses_detail = actions[fact.ses_index + 1].detail
    end
    local function prepare_menu()
        clear_timer()
        from_menu = true
        fact.ses_mode = 0
        fact.ses_sel = 0
        select(0)
    end
    local function confirmation(kind, menu)
        clear_timer()
        from_menu = menu
        fact.ses_mode = 1
        fact.ses_kind = kind
        fact.ses_sel = 0
        fact.countdown = 60
        local function tick()
            if not shown() or fact.ses_mode ~= 1 then return end
            if fact.countdown > 1 then
                fact.countdown = fact.countdown - 1
                timer_id = after(1000, tick)
            else
                perform()
            end
        end
        -- Browsing the menu never starts an automatic session action.
        if kind < 3 and shown() then timer_id = after(1000, tick) end
    end
    local function cancel_choice()
        clear_timer()
        if fact.ses_mode == 1 and from_menu then
            fact.ses_mode = 0
            fact.ses_sel = 0
        else
            panel.close()
        end
    end
    local function activate(index)
        if not shown() or fact.ses_mode ~= 0 then return end
        index = tonumber(index)
        if not index or index % 1 ~= 0 or not actions[index + 1] then return end
        select(index)
        local action = actions[index + 1]
        if action.kind < 0 then
            panel.close()
            after(150, function() pcall(sys.call, "say", "lock", "fact locked true") end)
        else
            confirmation(action.kind, true)
        end
    end

    on("prepare_menu", prepare_menu)
    Hooks.handlers.prepare_menu = prepare_menu           -- the frame (topbar.luau) calls these directly: it cannot emit to itself
    local function set_kind(value)
        local kind = tonumber(type(value) == "table" and (value.k or value[1]) or value)
        if kind and kind % 1 == 0 and kind >= 0 and kind <= 3 then confirmation(kind, false) end
    end
    on("set_kind", set_kind)
    Hooks.handlers.set_kind = set_kind
    on("fact:ses_index", function(index)
        local action = actions[(tonumber(index) or 0) + 1]
        if action then text.ses_detail = action.detail end
    end)
    on("ses_move", function(delta)
        if not shown() then return end
        delta = tonumber(delta) or 0
        if fact.ses_mode == 0 then select((tonumber(fact.ses_index) or 0) + delta)
        else fact.ses_sel = 1 - (tonumber(fact.ses_sel) or 0) end
    end)
    on("ses_choose", activate)
    on("ses_cancel", function() if shown() then cancel_choice() end end)
    on("dismiss", function() if shown() then cancel_choice() end end)
    on("ses_enter", function()
        if not shown() then return end
        if fact.ses_mode == 0 then activate(fact.ses_index)
        elseif fact.ses_sel == 1 then perform()
        else cancel_choice() end
    end)
    perform = function()
        if not shown() or fact.ses_mode ~= 1 then return end
        local kind = tonumber(fact.ses_kind)
        if not kind or kind % 1 ~= 0 or kind < 0 or kind > 3 then return end
        clear_timer()
        panel.close()
        if kind == 0 then run("systemctl", { "poweroff" })
        elseif kind == 1 then run("systemctl", { "reboot" })
        elseif kind == 2 then run("niri", { "msg", "action", "quit", "--skip-confirmation" })
        else run("systemctl", { "suspend" }) end
    end
    on("confirm_action", perform)
    opened(function()
        if fact.ses_mode == 1 then confirmation(fact.ses_kind, from_menu)
        else prepare_menu() end
    end)
    closed(function()
        clear_timer()
        fact.ses_mode = 0
    end)
    prepare_menu()
end
