-- The scene side of a panel that grows out of a bar island (see common/morph.plm).
--
--     local panel = require("panel")("control_center")
--     panel.height(434)          -- whenever the content's height changes
--
-- It reports to the frame (topbar.plm), which draws the glass: when the panel opens and closes, and how tall
-- it is. The frame arbitrates when two panels share an island (the Control Center and the notifications both
-- use the right one: whichever opened last owns it).
local IDS = { control_center = 1, notifications = 2, dashboard = 3 }

return function(name)
    local id = IDS[name]
    local P = { h = nil }

    local function say(words)
        pcall(sys.call, "say", "topbar", words)
    end

    on("fact:open", function(v)
        if v == true or v == 1 then
            say("emit panel_open " .. id)
            if P.h then
                say("emit panel_height " .. (id * 10000 + P.h))
            end
        else
            say("emit panel_close " .. id)
        end
    end)

    function P.height(h)
        h = math.floor(h)
        if h ~= P.h then
            P.h = h
            fact.panel_h = h
            say("emit panel_height " .. (id * 10000 + h))
        end
    end

    return P
end
