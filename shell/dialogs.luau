-- Dialogs (session, polkit, welcome): ONE scene (dialogs.plm), one logic. `fact.open` / `fact.open_screen` / `fact.cur`
-- (1 session, 2 polkit, 3 welcome) are shared: only one dialog is up. Each part gets `opened(fn)`, `closed(fn)` and
-- `shown()` (is MY dialog the one up). `toggle_dialog(id)` / `show_dialog(id)` come from topbar.luau, spotlight, start.sh.
local IDS = { session = 1, polkit = 2, welcome = 3 }
local hooks_open, hooks_close = {}, {}
local current = nil

local function sync()
    local o = fact.open == true or fact.open == 1
    local id = o and (tonumber(fact.cur) or 0) or nil
    if id == current then return end
    local prev = current
    current = id
    if prev and hooks_close[prev] then hooks_close[prev]() end
    if id and hooks_open[id] then hooks_open[id]() end
end
on("fact:open", sync)
on("fact:cur", sync)
on("dlg_sync", sync)

local function show(id)
    fact.cur = id
    fact.open = true
end
on("show_dialog", function(id) show(tonumber(id) or 1) end)
on("toggle_dialog", function(id)
    id = tonumber(id) or 1
    if (fact.open == true or fact.open == 1) and tonumber(fact.cur) == id then
        fact.open = false
    else
        show(id)
    end
end)

local function module(name, init)
    local id = IDS[name]
    init(function(fn) hooks_open[id] = fn end, function(fn) hooks_close[id] = fn end, function() return current == id end)
end

module("session", function(opened, closed, shown)
    -- Session dialog logic: shut down, restart, log out (with a 60 s countdown)

    local timer_id = nil

    local function clear_timer()
        if timer_id then
            cancel(timer_id)
            timer_id = nil
        end
    end

    on("confirm_action", function()
        clear_timer()
        fact.open = false
        local k = fact.kind or 0
        if k == 0 then
            log("Session: Powering off system...")
            run("systemctl", { "poweroff" }, function(_, code)
                if code ~= 0 then
                    log("Session: poweroff failed with code", code)
                end
            end)
        elseif k == 1 then
            log("Session: Restarting system...")
            run("systemctl", { "reboot" }, function(_, code)
                if code ~= 0 then
                    log("Session: reboot failed with code", code)
                end
            end)
        else
            log("Session: Logging out...")
            run("niri", { "msg", "action", "quit", "--skip-confirmation" })
        end
    end)

    -- Countdown loop: runs while this dialog is the one shown
    opened(function()
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
end)

module("polkit", function(opened, closed, shown)
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
                if not shown() then open_on_focused_monitor() end
            end
        elseif pending then
            pending = false
            text.password = ""
            if shown() then fact.open = false end
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
        if shown() then fact.open = false end
        pending = false
    end)
end)

module("welcome", function(opened, closed, shown)
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
        if not shown() then say("topbar", "emit open_panel 9") end     -- the frame picks the monitor with the focus
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
        if shown() then fact.open = false end
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
end)

-- a password dialog (or the session one) must not end up behind another panel: they close when it opens
require("exclusive")("dialogs")
