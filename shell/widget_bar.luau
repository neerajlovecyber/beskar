-- The widget bar's logic: it only forwards its buttons to the widgets scene (which owns every decision) and keeps
-- edit mode and the bar in step (closing the bar by Esc ends edit mode).
local panel = require("panel")("widget_bar")
panel.height(132)

local function widgets(words)
    pcall(sys.call, "say", "widgets", words)
end

on("wb_add", function(code) widgets("emit w_add " .. math.floor(tonumber(code) or 0)) end)
on("wb_preset", function(n) widgets("emit w_preset " .. math.floor(tonumber(n) or 0)) end)
on("wb_undo", function() widgets("emit w_undo") end)
on("wb_tidy", function() widgets("emit w_tidy") end)
on("wb_grid", function() widgets("emit w_grid") end)
on("wb_done", function() widgets("emit edit_done") end)

on("fact:open", function(v)
    if v == true or v == 1 then
        widgets("emit w_bar_open")
    else
        widgets("emit edit_done")
    end
end)

require("exclusive")("widget_bar")

local DATA = require("widgets_data")
local kinds, presets = {}, {}
for _, k in ipairs(DATA.KINDS) do kinds[#kinds + 1] = { id = k.id, name = k.name, icon = k.icon } end
for i, p in ipairs(DATA.PRESETS) do presets[#presets + 1] = { id = i, name = p.name } end
model.kinds = kinds
model.presets = presets
