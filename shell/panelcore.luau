-- The core of a scene that holds several panels growing out of the bar / dock (panels.luau, dock.luau): ONE shared
-- morph state (`fact.open`, `fact.open_screen`, `fact.cur` = the open panel's id, `fact.panel_h`) because only one is
-- ever open. It reports to the frame (topbar.luau) which panel is open and how tall it is, and runs each part's hooks.
--
--     local module = require("panelcore")({ weather = 15, music = 9 })
--     module("weather", function(panel, opened, shown, closed)
--         panel.height(612)            -- this panel's height (the frame's glass)
--         opened(function() … end)     -- it was just opened (or became the one shown)
--         closed(function() … end)     -- it was just closed (or another took its place)
--         if shown() then … end        -- is MY panel the one up
--     end)
--
-- A logic that sets `fact.open` itself does not trigger `on("fact:open")`: the scene declares
-- `on change open { emit panel_sync }` and `on change cur { emit panel_sync }` (morph_core.plm does the first).
-- Events `toggle_dock(id)` / `show_panel(id)` / `close_panel(id)` open and close by id (cur is set first).
return function(IDS)
    local heights, hooks_open, hooks_close = {}, {}, {}
    local current = nil                -- the id shown now (open and cur), or nil
    local fresh_timer = nil

    local function say_topbar(words)
        pcall(sys.call, "say", "topbar", words)
    end

    local function sync()
        local o = fact.open == true or fact.open == 1
        local id = o and (tonumber(fact.cur) or 0) or nil
        if id ~= nil and not heights[id] and not hooks_open[id] and not hooks_close[id] then id = nil end
        if id == current then return end
        local prev = current
        current = id
        if prev then
            say_topbar("emit panel_close " .. prev)
            if hooks_close[prev] then hooks_close[prev]() end
        end
        if id then
            -- a panel that has just taken over gets a `blur` from the one it replaced: `fresh` (declared by the scene)
            -- lets its `on blur` rule ignore that one
            if fresh_timer then cancel(fresh_timer) end
            pcall(function() fact.fresh = true end)
            fresh_timer = after(500, function() fresh_timer = nil; pcall(function() fact.fresh = false end) end)
            if heights[id] then fact.panel_h = heights[id] end
            say_topbar("emit panel_open " .. id)
            if heights[id] then say_topbar("emit panel_height " .. (id * 10000 + heights[id])) end
            if hooks_open[id] then hooks_open[id]() end
        end
    end
    on("fact:open", sync)
    on("fact:cur", sync)
    on("panel_sync", sync)

    local function show(id)
        fact.cur = id
        fact.open = true
        sync()
    end
    on("show_panel", function(id) show(tonumber(id) or 0) end)
    on("toggle_dock", function(id)
        id = tonumber(id) or 0
        if current == id then
            fact.open = false
        else
            show(id)
        end
    end)
    on("close_panel", function(id)             -- close it only if it is the one shown (a click outside, the widgets scene)
        if current == (tonumber(id) or 0) then fact.open = false end
    end)
    on("outside_close", function()              -- a click on nothing: closes the open panel (except `keep` ones)
        if current ~= nil and not (heights.keep and heights.keep[current]) then fact.open = false end
    end)

    return function(name, init)
        local id = IDS[name]
        local panel = {}
        function panel.height(h)
            h = math.floor(h)
            if heights[id] == h then return end
            heights[id] = h
            if current == id then
                fact.panel_h = h
                say_topbar("emit panel_height " .. (id * 10000 + h))
            end
        end
        function panel.keep() heights.keep = heights.keep or {}; heights.keep[id] = true end   -- survives a click outside
        init(panel,
            function(fn) hooks_open[id] = fn end,
            function() return current == id end,
            function(fn) hooks_close[id] = fn end)
    end
end
