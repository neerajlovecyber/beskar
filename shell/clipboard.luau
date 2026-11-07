-- Clipboard history logic (cliphist + wl-copy). Everything goes through `run` (the sandbox has no io / os), and the
-- frame draws the glass: this tells it how tall the list is.
local panel = require("panel")("clipboard")
local clip_items = {}

local function paint()
    model.clips = clip_items
    panel.height(56 + math.max(#clip_items, 1) * 46 + 34)
end
paint()

local function refresh_clips()
    run("sh", { "-c", "cliphist list 2>/dev/null | head -n 8" }, function(out)
        local items = {}
        for line in (out or ""):gmatch("[^\n]+") do
            local id_s, preview = line:match("^(%d+)%s+(.*)$")
            if id_s and preview then
                items[#items + 1] = { id = tonumber(id_s), preview = preview, full = line }
            end
        end
        clip_items = items
        if #items > 0 and (fact.sel >= #items or fact.sel < 0) then
            fact.sel = 0
        end
        paint()
    end)
end

on("fact:open", function(v)
    if v == true or v == 1 then
        refresh_clips()
    end
end)

on("copy_clip", function(idx)
    fact.open = false
    local i = tonumber(idx) or fact.sel or 0
    local target = clip_items[i + 1]
    if target and target.full then
        -- the entry goes back through cliphist (it knows the id) into the clipboard
        run("sh", { "-c", 'printf "%s" "$1" | cliphist decode | wl-copy', "x", target.full }, nil, { output = false })
        run("notify-send", { "-a", "Clipboard", "-i", "edit-paste", "Snippet copied", "Ready to paste" }, nil, { output = false })
    end
end)

on("clear_all", function()
    run("cliphist", { "wipe" }, nil, { output = false })
    clip_items = {}
    paint()
    fact.open = false
    run("notify-send", { "-a", "Clipboard", "Clipboard cleared", "All saved history has been removed" }, nil, { output = false })
end)

-- one panel at a time
require("exclusive")("clipboard")
