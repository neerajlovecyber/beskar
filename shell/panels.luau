-- The owner of the panel state (panels.plm). It is the old panelcore.luau without the panels' own hooks: it knows which panel
-- is open, tells the frame (topbar.luau, which draws the glass) and answers the panels' events. The panels' scenes
-- (the panel scenes) read `Panels.open` / `Panels.cur` and hear them change to run their `opened` / `closed` hooks.
local heights, widths, keeps = {}, {}, {}
local KNOWN = { [1] = true, [2] = true, [3] = true, [4] = true, [5] = true, [6] = true, [9] = true, [10] = true, [11] = true,
    [12] = true, [15] = true, [16] = true, [21] = true, [22] = true, [24] = true }
local current = nil                -- the id shown now (open and cur), or nil
local fresh_timer = nil

-- (typed events to the frame, topbar.luau; pleamar 0.8-exp.5 delivers a scene's logic events to the other scene's logic)

local function sync()
    local o = fact.open == true or fact.open == 1
    local id = o and (tonumber(fact.cur) or 0) or nil
    if id ~= nil and not KNOWN[id] then id = nil end
    if id == current then return end
    local prev = current
    current = id
    if prev then emit("Topbar.panel_close", prev) end
    if id then
        -- a panel that has just taken over gets a `blur` from the one it replaced: `fresh` lets its `on blur` rule ignore it
        if fresh_timer then cancel(fresh_timer) end
        fact.fresh = true
        fresh_timer = after(500, function() fresh_timer = nil; fact.fresh = false end)
        if heights[id] then fact.panel_h = heights[id] end
        emit("Topbar.panel_open", id)
        if heights[id] then emit("Topbar.panel_height", { id = id, h = heights[id] }) end
        if widths[id] then emit("Topbar.panel_width", { id = id, w = widths[id] }) end
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

on("show", function(id) show(tonumber(id) or 0) end)
on("toggle", function(id)
    id = tonumber(id) or 0
    if current == id then fact.open = false else show(id) end
end)
on("close", function() fact.open = false end)
on("close_id", function(id)
    if current == (tonumber(id) or 0) then fact.open = false end
end)
on("outside_close", function()
    if current ~= nil and not keeps[current] then fact.open = false end
end)
on("set_screen", function(v)
    fact.open_screen = tonumber(v and v.s) or 0
    text.panel_mon = (v and v.name) or ""
end)
on("set_toast_mon", function(name) text.toast_mon = name or "" end)
on("keep", function(id) keeps[tonumber(id) or 0] = true end)
on("height", function(v)
    local id, h = tonumber(v and v.id) or 0, math.floor(tonumber(v and v.h) or 0)
    if heights[id] == h then return end
    heights[id] = h
    if current == id then
        fact.panel_h = h
        emit("Topbar.panel_height", { id = id, h = h })
    end
end)
on("width", function(v)
    local id, w = tonumber(v and v.id) or 0, math.floor(tonumber(v and v.w) or 0)
    if widths[id] == w then return end
    widths[id] = w
    if current == id then emit("Topbar.panel_width", { id = id, w = w }) end
end)

-- opening one closes the other windows (Settings, the power menu)
require("exclusive")("panels")
