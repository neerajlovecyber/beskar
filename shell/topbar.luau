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

-- ── dock: launch an app ──────────────────────────────────────────
-- Same order as the DockItem(…, n) calls in topbar.plm. Each name must also be in `run:`.
local APPS = { "kitty", "nautilus", "code", "steam", "obsidian", "firefox", "discord", "telegram-desktop" }

on("launch", function(n)
    local cmd = APPS[n]
    if cmd then
        -- No callback and no output wanted: the app lives on its own, we do not wait for it.
        pcall(run, cmd, {}, nil, { output = false })
    end
end)

-- ── niri: focused workspace ──────────────────────────────────────
local function refresh_workspace()
    run("niri", { "msg", "-j", "workspaces" }, function(out, code)
        if code ~= 0 or not out then
            return
        end
        local ok, list = pcall(json.decode, out)
        if not ok or type(list) ~= "table" then
            return
        end
        for _, w in ipairs(list) do
            if w.is_focused then
                fact.focused_ws = w.idx or 1
                return
            end
        end
    end)
end

refresh_workspace()

-- niri prints one JSON object per event. Only workspace events can change what we show, and the
-- stream names the workspace by id, so ask niri for the idx again instead of guessing.
local streaming = false
local function follow_niri()
    if streaming then
        return
    end
    streaming = true
    spawn("niri", { "msg", "-j", "event-stream" }, function(line)
        if line:find("Workspace", 1, true) then
            refresh_workspace()
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
