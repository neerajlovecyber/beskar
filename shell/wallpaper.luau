-- The wallpaper scene's logic: show the saved wallpaper at start, and reveal each new one the picker sends.
local shown = ""
local busy = false
local queued = nil

local function reveal(path)
    if path == "" or path == shown then return end
    if busy then queued = path return end
    busy = true
    text.wp_b_path = path
    after(450, function()              -- let the new picture load before it grows over the old one
        fact.wp_go = true
        after(1500, function()
            text.wp_a_path = path
            shown = path
            after(250, function()
                fact.wp_go = false
                busy = false
                if queued then
                    local nxt = queued
                    queued = nil
                    reveal(nxt)
                end
            end)
        end)
    end)
end

on("text:wp_new", function(path)
    path = (path or ""):gsub("%s+$", "")
    if path ~= "" then reveal(path) end
end)

run("sh", { "-c", 'cat "$HOME/.config/beskar/wallpaper" 2>/dev/null | head -1' }, function(out)
    local p = (out or ""):gsub("%s+$", "")
    if p ~= "" and shown == "" then
        shown = p
        text.wp_a_path = p
    end
end)
