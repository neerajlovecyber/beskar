-- The authentication agent. Watching the `polkit` service makes this process the session's agent (one per session).
-- Requests come one at a time: `pending` (a program waits; polkit's message and whose password it takes), then
-- `asking` (an answer is awaited; the prompt, secret or not), `error = "wrong"` after a bad one (three tries at most).
local pending = false

local function open_on_focused_monitor()
    -- the frame knows which monitor has the focus (FOCUS_PANELS in topbar.luau toggles us there)
    pcall(sys.call, "say", "topbar", "emit open_panel 8")
end

sys.watch("polkit", function(p)
    p = p or {}
    local was_wrong = fact.pk_wrong == true
    text.pk_message = p.message or ""
    local prompt = p.prompt or ""
    prompt = prompt:gsub(":%s*$", "")
    text.pk_prompt = (prompt ~= "" and prompt) or ("Password for " .. (p.user or "administrator"))
    text.pk_info = p.info or ""
    fact.pk_secret = p.secret ~= false
    fact.pk_asking = p.asking == true
    fact.pk_wrong = p.error == "wrong"

    if p.pending == true then
        if not pending then
            pending = true
            text.password = ""
            if fact.open ~= true then open_on_focused_monitor() end
        end
    elseif pending then
        pending = false
        text.password = ""
        fact.open = false
    end

    if fact.pk_wrong and not was_wrong then
        text.password = ""
        emit("pk_shake")
    end
end)

on("pk_answer", function()
    if fact.pk_asking ~= true then return end
    local pwd = text.password or ""
    text.password = ""
    pcall(sys.call, "polkit.answer", pwd)
end)

on("pk_cancel", function()
    text.password = ""
    pcall(sys.call, "polkit.cancel")
    fact.open = false
    pending = false
end)

-- the password popup must not end up behind another panel (Settings, Control Center…): they close when it opens
require("exclusive")("polkit")
