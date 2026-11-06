-- macOS App Switcher Companion Logic (niri / Wayland window switcher)

local window_list = {}

local function refresh_windows()
    -- Query windows from niri IPC
    local handle = io.popen("niri msg -j windows 2>/dev/null")
    if not handle then return end
    local content = handle:read("*a")
    handle:close()

    if not content or content == "" then return end

    -- Parse simple window json records
    local wins = {}
    for id_s, title, app_id in content:gmatch('"id":(%d+).-"title":"(.-)".-"app_id":"(.-)"') do
        if app_id ~= "" and app_id ~= "pleamar" then
            wins[#wins + 1] = {
                id = tonumber(id_s),
                title = title,
                app_id = app_id
            }
        end
        if #wins >= 7 then break end
    end

    window_list = wins
    model.wins = wins
    if #wins > 0 and (fact.sel >= #wins or fact.sel < 0) then
        fact.sel = 0
    end
end

on("fact:open", function()
    if fact.open == true then
        refresh_windows()
        -- Advance selection by 1 when opened (standard Cmd+Tab behavior)
        if #window_list > 1 then
            fact.sel = 1
        else
            fact.sel = 0
        end
    end
end)

on("next_app", function()
    local count = #window_list
    if count > 0 then
        fact.sel = (fact.sel + 1) % count
    end
end)

on("prev_app", function()
    local count = #window_list
    if count > 0 then
        fact.sel = (fact.sel - 1 + count) % count
    end
end)

on("switch_to", function(idx)
    fact.open = false
    local i = tonumber(idx) or fact.sel or 0
    local target = window_list[i + 1]
    if target and target.id then
        log("AppSwitcher: Focusing window ID", target.id, target.title)
        run("niri", { "msg", "action", "focus-window", "--id", tostring(target.id) })
    end
end)
