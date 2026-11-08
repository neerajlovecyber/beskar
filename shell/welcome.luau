-- First-run welcome. Shown once: when ~/.config/beskar/welcome-done is missing, a few seconds after the shell starts
-- (the other scenes need to be up). Its choices are sent to Settings, which owns the look and saves it.
local function say(scene, words)
    pcall(sys.call, "say", scene, words)
end
local function sh(script, cb, ...)
    run("sh", { "-c", script, "x", ... }, cb, cb == nil and { output = false } or nil)
end

local function show()
    fact.page = 0
    if fact.open ~= true then say("topbar", "emit open_panel 9") end     -- the frame picks the monitor with the focus
end

-- mirror what Settings has now, so the switches on page 2 start right
sh('cat "$HOME/.config/pleamar_shell.json" "$HOME/.config/beskar/prefs.json" 2>/dev/null', function(out)
    out = out or ""
    fact.mode = out:find('"dark_mode": *false') and 0 or 1
    local app = out:match('"appearance": *(%d)')
    if app then fact.mode = tonumber(app) == 0 and 0 or (tonumber(app) == 2 and 2 or 1) end
    fact.wall_colours = out:find('"accent_auto": *true') ~= nil
    fact.theme_apps = not out:find('"apps": *false')
end)

-- first run?
sh('[ -f "$HOME/.config/beskar/welcome-done" ] && echo done || echo first', function(out)
    if (out or ""):find("first") then
        after(7000, show)
    end
end)

on("wl_next", function() fact.page = math.min(2, (tonumber(fact.page) or 0) + 1) end)
on("wl_back", function() fact.page = math.max(0, (tonumber(fact.page) or 0) - 1) end)

on("wl_done", function()
    fact.open = false
    sh('mkdir -p "$HOME/.config/beskar" && : > "$HOME/.config/beskar/welcome-done"')
end)

on("choose_dark", function() fact.mode = 1; say("settings", "emit set_mode 1") end)
on("choose_light", function() fact.mode = 0; say("settings", "emit set_mode 0") end)
on("choose_auto", function() fact.mode = 2; say("settings", "emit set_mode 2") end)
on("toggle_colours", function()
    fact.wall_colours = not (fact.wall_colours == true)
    say("settings", "emit toggle_accent_auto")
end)
on("toggle_apps_pref", function()
    fact.theme_apps = not (fact.theme_apps == true)
    say("settings", "emit toggle_apps")
end)

-- `./beskar welcome` and Settings ask for it again
on("show_again", show)
