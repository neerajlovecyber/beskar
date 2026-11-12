-- The panels' side of the shared panel state (panels.plm owns it). Same API as the old panelcore.luau, so every panel part
-- keeps its shape:
--
--     local module = require("panelclient")({ weather = 15, music = 9 })
--     module("weather", function(panel, opened, shown, closed)
--         panel.height(612)            -- this panel's glass height (the frame draws the glass)
--         panel.width(400)             -- optional: its width, when it depends on its content
--         panel.keep()                 -- optional: it survives a click outside
--         opened(function() … end)     -- it was just opened (or became the one shown)
--         closed(function() … end)     -- it was just closed (or another took its place)
--         if shown() then … end        -- is MY panel the one up
--     end)
--
-- It reads `Panels.open` / `Panels.cur` (a scene writes only its own facts) and asks for changes with `say` (pleamar 0.8-exp.3:
-- an event emitted by a scene's LOGIC reaches the other scene's .plm rules but not its logic, so `emit("Panels.height")` from
-- here would never arrive; the .plm rules of overlays DO `emit Panels.close`). The `say` strings go to panels.luau's events.
return function(IDS)
    local hooks_open, hooks_close = {}, {}
    local heights, widths = {}, {}
    local current = nil
    local function ask(words) pcall(sys.call, "say", "panels", words) end

    local function sync()
        local o = fact["Panels.open"] == true or fact["Panels.open"] == 1
        local id = o and (tonumber(fact["Panels.cur"]) or 0) or nil
        if id ~= nil and not (hooks_open[id] or hooks_close[id] or heights[id]) then id = nil end
        if id == current then return end
        local prev = current
        current = id
        if prev and hooks_close[prev] then hooks_close[prev]() end
        if id and hooks_open[id] then hooks_open[id]() end
    end
    on("fact:Panels.open", sync)
    on("fact:Panels.cur", sync)

    return function(name, init)
        local id = IDS[name]
        local panel = {}
        function panel.height(h)
            h = math.floor(h)
            if heights[id] == h then return end
            heights[id] = h
            ask("emit height " .. (id * 10000 + h))
        end
        function panel.width(w)
            w = math.floor(w)
            if widths[id] == w then return end
            widths[id] = w
            ask("emit width " .. (id * 10000 + w))
        end
        function panel.keep() ask("emit keep " .. id) end
        function panel.close() ask("emit close") end
        init(panel,
            function(fn) hooks_open[id] = fn end,
            function() return current == id end,
            function(fn) hooks_close[id] = fn end)
    end
end
