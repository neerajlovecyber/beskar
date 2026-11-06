-- Top bar logic: opens the other panels, tells the scene which niri workspace is focused and
-- what the weather is. It only reports facts; every command goes through `run`/`spawn`
-- (declared in topbar.plm's `permissions`), so nothing here blocks the logic thread.

local LAT, LON = 28.61, 77.20          -- weather location (Open-Meteo)
local WEATHER_EVERY_MS = 15 * 60 * 1000

-- ── panels ───────────────────────────────────────────────────────
local function toggle(panel)
    return function()
        pcall(sys.call, "say", panel, "emit toggle")
    end
end

on("open_apple_menu", toggle("apple_menu"))
on("open_control_center", toggle("control_center"))
on("open_spotlight", toggle("spotlight"))
on("open_widgets", toggle("widgets"))

-- ── tray ─────────────────────────────────────────────────────────
-- The service's list goes to the scene's `icons` model (it draws the picture). Reading the model
-- back gives each record with EVERYTHING it carried, `key` included, which is what
-- tray.activate / tray.secondary / tray.context need.
sys.watch("tray", function(list)
    model.icons = list or {}
end)

local function tray_action(call)
    return function(i)
        local it = model.icons and model.icons[(i or 0) + 1]
        if it and it.key then
            pcall(sys.call, call, it.key)
        end
    end
end

on("tray_activate", tray_action("tray.activate"))       -- left click
on("tray_secondary", tray_action("tray.secondary"))     -- middle click
on("tray_context", tray_action("tray.context"))         -- right click: the app's own menu

-- ── dock: launch an app, light the dot of the ones that are running ──
-- Same order as the DockItem(…, n) calls in topbar.plm. `cmd` must also be in `run:`; `ids` are
-- the app_ids niri reports for its windows (lower case).
local APPS = {
    { cmd = "kitty",            ids = { "kitty", "com.mitchellh.ghostty", "alacritty", "foot" } },
    { cmd = "nautilus",         ids = { "org.gnome.nautilus", "thunar", "org.kde.dolphin" } },
    { cmd = "code",             ids = { "code", "code-oss", "visual-studio-code" } },
    { cmd = "steam",            ids = { "steam" } },
    { cmd = "obsidian",         ids = { "obsidian" } },
    { cmd = "firefox",          ids = { "firefox", "chromium", "google-chrome" } },
    { cmd = "discord",          ids = { "discord", "vesktop" } },
    { cmd = "telegram-desktop", ids = { "org.telegram.desktop", "telegramdesktop" } },
}

on("launch", function(n)
    local app = APPS[n]
    if app then
        -- No callback and no output wanted: the app lives on its own, we do not wait for it.
        pcall(run, app.cmd, {}, nil, { output = false })
    end
end)

local function refresh_running()
    run("niri", { "msg", "-j", "windows" }, function(out, code)
        if code ~= 0 or not out then
            return
        end
        local ok, list = pcall(json.decode, out)
        if not ok or type(list) ~= "table" then
            return
        end
        local open = {}
        for _, w in ipairs(list) do
            open[string.lower(w.app_id or "")] = true
        end
        for n, app in ipairs(APPS) do
            local on_ = 0
            for _, id in ipairs(app.ids) do
                if open[id] then
                    on_ = 1
                    break
                end
            end
            fact["run_" .. n] = on_
        end
    end)
end

-- ── niri: the workspace each monitor shows ───────────────────────
-- `model mon` has one record per monitor, in the order of `niri msg outputs`.
local OUTPUTS = {}
local function refresh_workspaces()
    run("niri", { "msg", "-j", "workspaces" }, function(out, code)
        if code ~= 0 or not out then
            return
        end
        local ok, list = pcall(json.decode, out)
        if not ok or type(list) ~= "table" then
            return
        end
        local shown = {}
        for _, w in ipairs(list) do
            if w.is_active and w.output then
                shown[w.output] = w.idx or 1
            end
        end
        local recs = {}
        for i, name in ipairs(OUTPUTS) do
            recs[i] = { active = shown[name] or 1 }
        end
        model.mon = recs
    end)
end

local function refresh_niri()
    refresh_workspaces()
    refresh_running()
end

run("niri", { "msg", "-j", "outputs" }, function(out, code)
    local ok, o = pcall(json.decode, out or "")
    if code == 0 and ok and type(o) == "table" then
        for name in pairs(o) do
            OUTPUTS[#OUTPUTS + 1] = name
        end
        table.sort(OUTPUTS)
    end
    refresh_niri()
end)

-- niri prints one JSON object per event. Workspaces and windows are all that can change what we
-- show; ask niri again instead of reading the event.
local streaming = false
local function follow_niri()
    if streaming then
        return
    end
    streaming = true
    spawn("niri", { "msg", "-j", "event-stream" }, function(line)
        if line:find("Workspace", 1, true) or line:find("WindowOpenedOrChanged", 1, true) or line:find("WindowClosed", 1, true) then
            refresh_niri()
        end
    end, function()
        streaming = false      -- niri went away; the timer below retries
    end)
end

follow_niri()
every(5000, follow_niri)

-- ── weather ──────────────────────────────────────────────────────
local function icon_for(code)
    if code == 0 then
        return "󰖙"
    elseif code <= 3 then
        return "󰖐"
    elseif code == 45 or code == 48 then
        return "󰖑"
    elseif (code >= 51 and code <= 67) or (code >= 80 and code <= 82) then
        return "󰖗"
    elseif (code >= 71 and code <= 77) or code == 85 or code == 86 then
        return "󰖘"
    elseif code >= 95 then
        return "󰙾"
    end
    return "󰖐"
end

local function refresh_weather()
    local url = string.format(
        "https://api.open-meteo.com/v1/forecast?latitude=%s&longitude=%s&current=temperature_2m,weather_code",
        LAT, LON
    )
    run("curl", { "-fsS", "--max-time", "5", url }, function(out, code)
        if code ~= 0 or not out then
            return          -- keep the last reading
        end
        local ok, data = pcall(json.decode, out)
        local cur = ok and type(data) == "table" and data.current
        if type(cur) ~= "table" or cur.temperature_2m == nil then
            return
        end
        text.weather_temp = string.format("%d°", math.floor(cur.temperature_2m + 0.5))
        text.weather_icon = icon_for(cur.weather_code or 0)
    end)
end

refresh_weather()
every(WEATHER_EVERY_MS, refresh_weather)
