-- The core of a scene that holds several MODAL windows centred on a monitor (dialogs.luau, modals.luau): one shared
-- `fact.open` / `fact.open_screen` / `fact.cur` (the window's id); only one is ever up.
--
--     local module = require("modalcore")({ session = 1, polkit = 2 }, "dlg_sync")
--     module("session", function(opened, closed, shown) … end)
--
-- `sync_event` is declared by the scene (`event dlg_sync ->` with `on change open { emit dlg_sync }` and the same for
-- `cur`): a logic that sets `fact.open` itself does not trigger `on("fact:open")`. `show_dialog(id)` and
-- `toggle_dialog(id)` events open by id (cur is set first).
return function(IDS, sync_event)
    local hooks_open, hooks_close = {}, {}
    local current = nil
    local fresh_timer = nil

    local function sync()
        local o = fact.open == true or fact.open == 1
        local id = o and (tonumber(fact.cur) or 0) or nil
        if id == current then return end
        local prev = current
        current = id
        if prev and hooks_close[prev] then hooks_close[prev]() end
        if id then
            -- a window that has just taken over gets a `blur` from the one it replaced: `fresh` (declared by the scene)
            -- lets its `on blur` rule ignore it
            if fresh_timer then cancel(fresh_timer) end
            pcall(function() fact.fresh = true end)
            fresh_timer = after(500, function() fresh_timer = nil; pcall(function() fact.fresh = false end) end)
        end
        if id and hooks_open[id] then hooks_open[id]() end
    end
    on("fact:open", sync)
    on("fact:cur", sync)
    on(sync_event, sync)

    local function show(id)
        fact.cur = id
        fact.open = true
        sync()
    end
    on("show_dialog", function(id) show(tonumber(id) or 1) end)
    on("toggle_dialog", function(id)
        id = tonumber(id) or 1
        if (fact.open == true or fact.open == 1) and tonumber(fact.cur) == id then
            fact.open = false
            sync()
        else
            show(id)
        end
    end)

    return function(name, init)
        local id = IDS[name]
        init(function(fn) hooks_open[id] = fn end, function(fn) hooks_close[id] = fn end, function() return current == id end)
    end
end
