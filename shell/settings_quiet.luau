-- Settings edits saved hours; Activities owns temporary modes and Notifications owns delivery rules.
local text = require("keys_text")        -- the text fields are the Keys scene's
return function(changed, ready)
    local apps, selected, top = {}, 1, 0
    local function clock(n) return string.format("%02d:%02d", math.floor(n / 60), n % 60) end
    local function paint()
        apps = model["Notifications.quiet_apps"] or {}
        selected = math.max(1, math.min(#apps, selected))
        top = math.max(0, math.min(top, math.max(0, #apps - 5)))
        if selected <= top then top = selected - 1 elseif selected > top + 5 then top = selected - 5 end
        local rows = {}
        for i = top + 1, math.min(#apps, top + 5) do
            local r = apps[i]
            rows[#rows + 1] = { app = r.app, mode = r.mode, idx = i, sel = i == selected }
        end
        model.quiet_app_rows = rows
        text.quiet_app_range = #apps == 0 and "Senders appear here after a notification arrives" or ((top + 1) .. "–" .. math.min(top + 5, #apps) .. " of " .. #apps .. " senders")
    end
    local function hours()
        text.quiet_from = clock(tonumber(fact.quiet_start) or 1320)
        text.quiet_to = clock(tonumber(fact.quiet_end) or 420)
    end
    on("quiet_open", function() fact.quiet_edit = true; hours(); paint() end)
    on("quiet_close", function() fact.quiet_edit = false end)
    on("quiet_toggle", function()
        if not ready() then return end
        fact.quiet_enabled = not fact.quiet_enabled; changed()
    end)
    on("quiet_hours_save", function()
        if not ready() then return end
        local function minute(s)
            local h, m = tostring(s or ""):match("^(%d%d?):(%d%d)$")
            h, m = tonumber(h), tonumber(m)
            if h and m and h < 24 and m < 60 then return h * 60 + m end
        end
        local a, b = minute(text.quiet_from), minute(text.quiet_to)
        if not a or not b then text.quiet_edit_status = "Use 24-hour times, for example 22:00 and 07:00"; return end
        fact.quiet_start, fact.quiet_end = a, b; changed(); hours()
        text.quiet_edit_status = a == b and "Equal times disable the quiet window" or "Quiet hours saved · times use your local clock"
    end)
    on("quiet_mode", function(n)
        local name = ({ "focus", "presentation", "game" })[tonumber(n)]
        if name then emit("Activities.quiet_toggle", name) end
    end)
    on("quiet_app_step", function(d)
        selected = math.max(1, math.min(#apps, selected + ((tonumber(d) or 0) < 0 and -1 or 1))); paint()
    end)
    on("quiet_app_cycle", function(n)
        local row = apps[tonumber(n) or selected]
        if row then emit("Notifications.cycle_app_rule", row.app) end
    end)
    on("model:Notifications.quiet_apps", paint)
    on("fact:quiet_start", hours); on("fact:quiet_end", hours)
    return paint
end
