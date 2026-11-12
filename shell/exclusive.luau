-- One panel at a time, as in Marea (one card, one page): when a window opens, the others close.
-- A scene's logic calls `require("exclusive")("<its scene name>")`; the others are asked to close with a typed event
-- (the scene must say `uses scene` for them). A logic that opens its own panel (`fact.open = true` from Luau) does not
-- trigger `on("fact:open")`, so the sync events (`panel_sync`, `dlg_sync`) count too.
local CLOSERS = { settings = "Settings.close", panels = "Panels.close", topbar = "Topbar.close_menu" }

return function(me)
    local function opened()
        if fact.open == true or fact.open == 1 then
            for name, ev in pairs(CLOSERS) do
                if name ~= me then emit(ev) end
            end
        end
    end
    on("fact:open", opened)
    pcall(on, "panel_sync", opened)
    pcall(on, "dlg_sync", opened)
end
