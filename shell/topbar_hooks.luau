-- The frame's plugin cannot emit an event to ITSELF ("plugin 'Topbar' has no event called 'Topbar.open_panel'"). The panels whose logic now
-- runs inside it (the Control Center, the Personal editor, Spotlight…) still need to ask the frame to open something, so topbar.luau
-- records each handler it registers here and they call it directly: `require("topbar_hooks").emit("Topbar.open_panel", 4)`.
local M = { handlers = {} }

function M.call(name, value)
    local fn = M.handlers[name]
    if fn then fn(value) end
end

-- like emit(), but a `Topbar.` event goes straight to the frame's own handler (anything else is a normal typed event)
function M.emit(event, value)
    local own = type(event) == "string" and event:match("^Topbar%.(.+)$")
    if own then M.call(own, value)
    elseif value ~= nil then emit(event, value)
    else emit(event) end
end

return M
