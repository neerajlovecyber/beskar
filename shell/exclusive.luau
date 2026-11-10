-- One panel at a time, as in Marea (one card, one page): when a panel opens, the others close.
-- Each panel's logic calls `require("exclusive")("<its scene name>")`. The scene needs `say:<scene>`
-- for every other panel in its permissions (listed in PANELS).
-- A logic that opens its own panel (`fact.open = true` from Luau) does not trigger `on("fact:open")`, so the
-- merged scenes' sync events (`panel_sync`, `dlg_sync`) count too.
local PANELS = { "control_center", "notifications", "settings", "panels", "dock", "topbar", "overview" }

return function(me)
    local function opened()
        if fact.open == true or fact.open == 1 then
            for _, name in ipairs(PANELS) do
                if name ~= me then
                    pcall(sys.call, "say", name, "fact open false")
                end
            end
        end
    end
    on("fact:open", opened)
    pcall(on, "panel_sync", opened)
    pcall(on, "dlg_sync", opened)
end
