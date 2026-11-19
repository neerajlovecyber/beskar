-- The panels' text fields live in the Keys scene (keys.plm): pleamar gives the keyboard only to the FIRST copy of a `screens: each`
-- surface, so the frame cannot hold them on a second monitor. The frame's panel logic keeps writing `text.query = ""` and reading
-- `text.query`: `local text = require("keys_text")` makes those names read `Keys.<field>` and write through `Keys.set_text`; every
-- other name is the frame's own text. A written value is remembered until the Keys scene reports it, so a read straight after a write
-- sees it.
local real = text
local FIELDS = { wq = true, pe_draft = true, pe_new_task = true, tm_duration = true, query = true, clip_q = true,
    wb_name = true, password = true, wifi_pw = true,
    side_q = true, bind_q = true, look_name = true, look_document = true, quiet_from = true, quiet_to = true, shortcut_key = true,
    custom_accent_edit = true, frame_output_edit = true }
local written = {}

return setmetatable({}, {
    __index = function(_, k)
        if not FIELDS[k] then return real[k] end
        local now = real["Keys." .. k]
        if written[k] ~= nil then
            if now == written[k] then written[k] = nil else return written[k] end
        end
        return now
    end,
    __newindex = function(_, k, v)
        if not FIELDS[k] then real[k] = v; return end
        v = tostring(v or "")
        written[k] = v
        emit("Keys.set_text", { name = k, value = v })
    end,
})
