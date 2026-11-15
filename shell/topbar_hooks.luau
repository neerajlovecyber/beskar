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

-- Focus a panel's text field (or none): the fields are the Keys scene's, which focuses the one named by `fld_req` whenever `fld_seq`
-- changes (keys.plm). Numbers: 1 wq · 2 pe_draft · 3 pe_new_task · 4 tm_duration · 5 query · 6 clip_q · 7 wb_name · 8 password · 9 wifi_pw.
local FIELD = { wq = 1, pe_draft = 2, pe_new_task = 3, tm_duration = 4, query = 5, clip_q = 6, wb_name = 7, password = 8, wifi_pw = 9 }
function M.focus(name)
    fact.fld_req = FIELD[name or ""] or 0
    fact.fld_seq = (tonumber(fact.fld_seq) or 0) + 1
end

return M
