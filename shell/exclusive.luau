-- One panel at a time, as in Marea (one card, one page): when a panel opens, the others close.
-- Each panel's logic calls `require("exclusive")("<its scene name>")`. The scene needs `say:<scene>`
-- for every other panel in its permissions (listed in PANELS).
local PANELS = { "spotlight", "clipboard", "control_center", "apple_menu", "notifications", "dashboard", "settings", "wallpapers" }

return function(me)
    on("fact:open", function(v)
        if v == true or v == 1 then
            for _, name in ipairs(PANELS) do
                if name ~= me then
                    pcall(sys.call, "say", name, "fact open false")
                end
            end
        end
    end)
end
