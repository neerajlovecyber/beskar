-- The dialogs: session (shut down / restart / log out), the polkit password dialog and the first-run welcome (dialogs.plm).
local module = require("panelclient")({ session = 11, polkit = 12, welcome = 24 })

local function close_panel() emit("Panels.close") end

module("session", function(panel, opened, shown, closed)
    -- Session dialog logic: shut down, restart, log out (with a 60 s countdown). Enter presses the highlighted button
    -- (the action by default); the dialog grows out of the dock like Spotlight.
    panel.height(250)
    local timer_id = nil

    local function clear_timer()
        if timer_id then
            cancel(timer_id)
            timer_id = nil
        end
    end

    on("confirm_action", function()
        clear_timer()
        close_panel()
        local k = fact.ses_kind or 0
        if k == 0 then
            log("Session: Powering off system...")
            run("systemctl", { "poweroff" }, function(_, code)
                if code ~= 0 then log("Session: poweroff failed with code", code) end
            end)
        elseif k == 1 then
            log("Session: Restarting system...")
            run("systemctl", { "reboot" }, function(_, code)
                if code ~= 0 then log("Session: reboot failed with code", code) end
            end)
        else
            log("Session: Logging out...")
            run("niri", { "msg", "action", "quit", "--skip-confirmation" })
        end
    end)

    -- Countdown loop: runs while this dialog is the one shown
    opened(function()
        fact.ses_sel = 1          -- Enter presses the action by default
        fact.countdown = 60
        clear_timer()
        local function tick()
            if not shown() then return end
            if fact.countdown > 1 then
                fact.countdown = fact.countdown - 1
                timer_id = after(1000, tick)
            else
                emit("confirm_action")
            end
        end
        timer_id = after(1000, tick)
    end)
    closed(clear_timer)

    on("ses_enter", function()
        if not shown() then return end
        if (tonumber(fact.ses_sel) or 1) == 1 then
            emit("confirm_action")
        else
            close_panel()
        end
    end)
    on("dismiss", function() if shown() then close_panel() end end)
end)


module("polkit", function(panel, opened, shown, closed)
    -- The authentication agent. Watching the `polkit` service makes this process the session's agent (one per session).
    -- Requests come one at a time: `pending` (a program waits; polkit's message and whose password it takes), then
    -- `asking` (an answer is awaited; the prompt, secret or not), `error = "wrong"` after a bad one (three tries at most).
    panel.height(310)
    panel.keep()                 -- a click outside does not close it: it has to be answered or cancelled
    local pending = false

    local function open_on_focused_monitor()
        -- the frame knows which monitor has the focus (FOCUS_PANELS in topbar.luau toggles us there)
        emit("Topbar.open_panel", 8)
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
                if not shown() then open_on_focused_monitor() end
            end
        elseif pending then
            pending = false
            text.password = ""
            if shown() then close_panel() end
        end

        if fact.pk_wrong and not was_wrong then
            text.password = ""
            emit("pk_shake")
        end
    end)

    on("pk_answer", function()
        if not shown() or fact.pk_asking ~= true then return end
        local pwd = text.password or ""
        text.password = ""
        pcall(sys.call, "polkit.answer", pwd)
    end)

    on("pk_cancel", function()
        if not shown() then return end
        text.password = ""
        pcall(sys.call, "polkit.cancel")
        close_panel()
        pending = false
    end)

    -- closed by anything else (another panel took over): the program must be told it was dismissed
    closed(function()
        if pending then
            pending = false
            text.password = ""
            pcall(sys.call, "polkit.cancel")
        end
    end)
end)


module("welcome", function(panel, opened, shown, closed)
    -- First-run welcome. Shown once: when ~/.config/beskar/welcome-done is missing, a few seconds after the shell starts
    -- (the other scenes need to be up). Its choices are sent to Settings, which owns the look and saves it.
    panel.height(460)
    panel.width(640)
    panel.keep()                          -- a click outside does not close the welcome
    local function say(scene, words)
        pcall(sys.call, "say", scene, words)
    end
    local function sh(script, cb, ...)
        run("sh", { "-c", script, "x", ... }, cb, cb == nil and { output = false } or nil)
    end

    local function show()
        fact.page = 0
        if not shown() then emit("Topbar.open_panel", 9) end     -- the frame picks the monitor with the focus
    end

    -- mirror what Settings has now, so the switches on page 2 start right
    sh('cat "$HOME/.config/pleamar_shell.json" "$HOME/.config/beskar/prefs.json" 2>/dev/null', function(out)
        out = out or ""
        fact.wl_mode = out:find('"dark_mode": *false') and 0 or 1
        local app = out:match('"appearance": *(%d)')
        if app then fact.wl_mode = tonumber(app) == 0 and 0 or (tonumber(app) == 2 and 2 or 1) end
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
        if shown() then close_panel() end
        sh('mkdir -p "$HOME/.config/beskar" && : > "$HOME/.config/beskar/welcome-done"')
    end)

    on("choose_dark", function() fact.wl_mode = 1; emit("Settings.set_mode", 1) end)
    on("choose_light", function() fact.wl_mode = 0; emit("Settings.set_mode", 0) end)
    on("choose_auto", function() fact.wl_mode = 2; emit("Settings.set_mode", 2) end)
    on("toggle_colours", function()
        fact.wall_colours = not (fact.wall_colours == true)
        emit("Settings.toggle_accent_auto")
    end)
    on("toggle_apps_pref", function()
        fact.theme_apps = not (fact.theme_apps == true)
        emit("Settings.toggle_apps")
    end)

    -- `./beskar welcome` and Settings ask for it again
    on("show_again", show)
end)
