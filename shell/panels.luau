-- The owner of the panel state (panels.plm). It is the old panelcore.luau without the panels' own hooks: it knows which panel
-- is open, tells the frame (topbar.luau, which draws the glass) and answers the panels' events. The panels' scenes
-- (overlays) read `Panels.open` / `Panels.cur` and hear them change to run their `opened` / `closed` hooks.
local heights, widths, keeps = {}, {}, {}
local KNOWN = { [1] = true, [2] = true, [3] = true, [4] = true, [5] = true, [6] = true, [9] = true, [10] = true, [11] = true,
    [12] = true, [15] = true, [16] = true, [21] = true, [22] = true, [24] = true }
local current = nil                -- the id shown now (open and cur), or nil
local fresh_timer = nil

local function say_topbar(words)
    pcall(sys.call, "say", "topbar", words)
end

local function sync()
    local o = fact.open == true or fact.open == 1
    local id = o and (tonumber(fact.cur) or 0) or nil
    if id ~= nil and not KNOWN[id] then id = nil end
    if id == current then return end
    local prev = current
    current = id
    if prev then say_topbar("emit panel_close " .. prev) end
    if id then
        -- a panel that has just taken over gets a `blur` from the one it replaced: `fresh` lets its `on blur` rule ignore it
        if fresh_timer then cancel(fresh_timer) end
        fact.fresh = true
        fresh_timer = after(500, function() fresh_timer = nil; fact.fresh = false end)
        if heights[id] then fact.panel_h = heights[id] end
        say_topbar("emit panel_open " .. id)
        if heights[id] then say_topbar("emit panel_height " .. (id * 10000 + heights[id])) end
        if widths[id] then say_topbar("emit panel_width " .. (id * 10000 + widths[id])) end
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
on("keep", function(id) keeps[tonumber(id) or 0] = true end)
on("height", function(v)
    v = tonumber(v) or 0
    local id, h = math.floor(v / 10000), v % 10000
    if heights[id] == h then return end
    heights[id] = h
    if current == id then
        fact.panel_h = h
        say_topbar("emit panel_height " .. v)
    end
end)
on("width", function(v)
    v = tonumber(v) or 0
    local id, w = math.floor(v / 10000), v % 10000
    if widths[id] == w then return end
    widths[id] = w
    if current == id then say_topbar("emit panel_width " .. v) end
end)

-- opening one closes the other windows (Settings, the power menu)
require("exclusive")("panels")
