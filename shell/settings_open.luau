-- Whether the Settings window is up: panel 30 of the Panels owner (the frame draws it, common/settings_panel.plm). `fact.open` is a
-- mirror kept for the Settings logic (and the smoke test); a fact the logic writes does not come back through `on("fact:open")` in
-- the same plugin, so whoever needs to know subscribes here: `require("settings_open").on(function(open) … end)`.
local M = { listeners = {} }

function M.on(fn) M.listeners[#M.listeners + 1] = fn end

function M.is_open()
    local o = fact["Panels.open"] == true or fact["Panels.open"] == 1
    return o and tonumber(fact["Panels.cur"]) == 30
end

local function sync()
    local now = M.is_open() and true or false
    if now == (fact.open == true) then return end
    fact.open = now
    for _, fn in ipairs(M.listeners) do fn(now) end
end
on("fact:Panels.open", sync)
on("fact:Panels.cur", sync)

-- the window closes itself (a button of the General tab, "Edit widgets", the session actions)
function M.close()
    emit("Panels.close_id", 30)
end

return M
