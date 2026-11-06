-- macOS Clipboard Manager Companion Logic (cliphist + wl-copy)

local clip_items = {}

local function refresh_clips()
    local handle = io.popen("cliphist list 2>/dev/null | head -n 8")
    if not handle then return end
    local items = {}
    for line in handle:lines() do
        local id_s, preview = line:match("^(%d+)%s+(.*)$")
        if id_s and preview then
            items[#items + 1] = {
                id = tonumber(id_s),
                preview = preview,
                full = line
            }
        end
    end
    handle:close()

    clip_items = items
    model.clips = items
    if #items > 0 and (fact.sel >= #items or fact.sel < 0) then
        fact.sel = 0
    end
end

on("fact:open", function()
    if fact.open == true then
        refresh_clips()
    end
end)

on("copy_clip", function(idx)
    fact.open = false
    local i = tonumber(idx) or fact.sel or 0
    local target = clip_items[i + 1]
    if target and target.full then
        log("Clipboard: Restoring clip snippet to clipboard:", target.preview)
        -- Pipe specific cliphist entry back into wl-copy
        local cmd = string.format("echo %q | cliphist decode | wl-copy &", target.full)
        os.execute(cmd)
        os.execute("notify-send -a 'Clipboard' 'Snippet Copied' 'Copied to clipboard and ready to paste' -i edit-paste &")
    end
end)

on("clear_all", function()
    log("Clipboard: Wiping cliphist database...")
    os.execute("cliphist wipe")
    clip_items = {}
    model.clips = {}
    fact.open = false
    os.execute("notify-send -a 'Clipboard' 'Clipboard Cleared' 'All saved history has been removed' &")
end)
