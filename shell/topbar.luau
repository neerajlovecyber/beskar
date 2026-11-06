-- Top bar logic: opens the other panels, tells the scene which niri workspace is focused and
-- what the weather is. It only reports facts; every command goes through `run`/`spawn`
-- (declared in topbar.plm's `permissions`), so nothing here blocks the logic thread.

local locate = require("location")      -- where you are (see location.luau)
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
on("open_notifications", toggle("notifications"))
on("open_dashboard", toggle("dashboard"))

-- Open the Control Center straight on a page (1 Wi-Fi, 2 Bluetooth).
local function open_cc_page(n)
    return function()
        pcall(sys.call, "say", "control_center", "fact page " .. n)
        pcall(sys.call, "say", "control_center", "fact open true")
    end
end
on("open_cc_wifi", open_cc_page(1))
on("open_cc_bt", open_cc_page(2))

-- ── tray ─────────────────────────────────────────────────────────
-- The service's list goes to the scene's `icons` model (it draws the picture). Reading the model
-- back gives each record with EVERYTHING it carried, `key` included, which is what
-- tray.activate / tray.secondary / tray.context need.
-- Tray items that stay out of the bar: the shell already has its own network and Bluetooth
-- indicators (and the Control Center), so nm-applet and blueman would only repeat them. Chrome's
-- background icon never goes away while it runs. Add an item's `id` here to hide it too
-- (`id`s: nm-applet, blueman, chrome_status_icon_1, Cachy-Update, …).
local HIDE = { ["nm-applet"] = true, ["blueman"] = true, ["chrome_status_icon_1"] = true, ["Cachy-Update"] = true }

sys.watch("tray", function(list)
    local shown = {}
    for _, it in ipairs(list or {}) do
        if not HIDE[it.id or ""] and it.status ~= "Passive" then
            shown[#shown + 1] = it
        end
    end
    model.icons = shown
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

-- Last answers from niri, combined into `model.mon` (workspace shown + how many windows it holds).
local WS, WINS = {}, {}
local build_dock

-- ── dock: the apps you pinned, plus the ones running ─────────────
-- Pinned apps are the lines of ~/.config/beskar/dock (desktop ids: org.gnome.Nautilus, kitty, …); edit it by
-- hand or right-click an icon → "Keep in Dock". With no file the dock shows two: a file manager and a terminal.
local pinned = nil          -- list of desktop ids, nil = the defaults
local entries = {}          -- desktop entries (apps service)
local by_key = {}           -- lower-case id / wmclass / last part of the id → entry
local items = {}            -- what the dock shows now, in model order

local function lower(s)
    return string.lower(s or "")
end

local function index_entries(list)
    entries = list or {}
    by_key = {}
    for _, e in ipairs(entries) do
        local id = lower(e.id):gsub("%.desktop$", "")
        by_key[id] = e
        if e.wmclass and e.wmclass ~= "" then
            by_key[lower(e.wmclass)] = e
        end
        local last = id:match("([^%.]+)$")
        if last and not by_key[last] then
            by_key[last] = e
        end
    end
end

local function entry_for(app_id)
    local k = lower(app_id)
    return by_key[k] or by_key[k:match("([^%.]+)$") or k]
end

local FILE_MANAGERS = { "org.gnome.nautilus", "nautilus", "thunar", "org.kde.dolphin", "dolphin", "nemo", "pcmanfm", "pcmanfm-qt" }
local TERMINALS = { "kitty", "com.mitchellh.ghostty", "ghostty", "alacritty", "foot", "org.wezfurlong.wezterm", "wezterm", "org.gnome.terminal", "konsole", "xterm" }

local function default_of(preferred, category)
    for _, id in ipairs(preferred) do
        if by_key[id] then
            return by_key[id]
        end
    end
    for _, e in ipairs(entries) do
        if (e.categories or ""):find(category, 1, true) then
            return e
        end
    end
end

local function default_pins()
    local out = {}
    local files = default_of(FILE_MANAGERS, "FileManager")
    local term = default_of(TERMINALS, "TerminalEmulator")
    if files then out[#out + 1] = files.id end
    if term then out[#out + 1] = term.id end
    return out
end

local function save_pins(list)
    pinned = list
    local script = 'mkdir -p "$HOME/.config/beskar" && : > "$HOME/.config/beskar/dock" && for a in "$@"; do printf "%s\\n" "$a" >> "$HOME/.config/beskar/dock"; done'
    local args = { "-c", script, "x" }
    for _, id in ipairs(list) do
        args[#args + 1] = id
    end
    run("sh", args, nil, { output = false })
end

local function name_of(e)
    return (e.local_name and e.local_name ~= "") and e.local_name or e.name or e.id
end

build_dock = function()
    local pins = pinned or default_pins()
    local groups, order = {}, {}
    for _, w in ipairs(WINS) do
        local e = entry_for(w.app_id)
        local key = e and lower(e.id) or ("app:" .. lower(w.app_id))
        local g = groups[key]
        if not g then
            g = { entry = e, app_id = w.app_id or "", wins = {} }
            groups[key] = g
            order[#order + 1] = key
        end
        g.wins[#g.wins + 1] = w.id
    end
    local list, used = {}, {}
    for _, id in ipairs(pins) do
        local e = by_key[lower(id)]
        if e and not used[lower(e.id)] and #list < 12 then
            local key = lower(e.id)
            used[key] = true
            list[#list + 1] = { entry = e, name = name_of(e), icon = e.icon or "", pinned = true,
                                wins = groups[key] and groups[key].wins or {} }
        end
    end
    for _, key in ipairs(order) do
        if not used[key] and #list < 12 then
            local g = groups[key]
            local e = g.entry
            list[#list + 1] = { entry = e, name = e and name_of(e) or g.app_id, icon = e and e.icon or lower(g.app_id),
                                pinned = false, wins = g.wins }
        end
    end
    items = list
    local rows = {}
    for i, it in ipairs(list) do
        rows[i] = { icon = it.icon, name = it.name, running = #it.wins > 0, pinned = it.pinned, canpin = it.entry ~= nil }
    end
    model.dock_items = rows
end

local function launch(entry)
    local exec = (entry.exec or ""):gsub("%%[%a%%]", ""):gsub("%s+$", "")
    if exec ~= "" then
        pcall(sys.call, "apps.launch", exec)
    end
end

on("dock_click", function(i)
    local it = items[(i or 0) + 1]
    if not it then
        return
    end
    if #it.wins > 0 then
        run("niri", { "msg", "action", "focus-window", "--id", tostring(it.wins[1]) }, nil, { output = false })
    elseif it.entry then
        launch(it.entry)
    end
end)

on("dock_pin", function(i)
    local it = items[(i or 0) + 1]
    if not it or not it.entry then
        return
    end
    local current = {}
    for _, id in ipairs(pinned or default_pins()) do
        current[#current + 1] = id
    end
    local out, found = {}, false
    for _, id in ipairs(current) do
        if lower(id) == lower(it.entry.id) then
            found = true               -- unpin: leave it out
        else
            out[#out + 1] = id
        end
    end
    if not found then
        out[#out + 1] = it.entry.id    -- pin
    end
    save_pins(out)
    build_dock()
end)

on("dock_quit", function(i)
    local it = items[(i or 0) + 1]
    if not it then
        return
    end
    for _, wid in ipairs(it.wins) do
        run("niri", { "msg", "action", "close-window", "--id", tostring(wid) }, nil, { output = false })
    end
end)

sys.watch("apps", function(list)
    index_entries(list)
    build_dock()
end)

-- ~/.config/beskar/dock, read now and every few seconds so a hand edit shows up
local function read_pins()
    run("sh", { "-c", 'if [ -f "$HOME/.config/beskar/dock" ]; then cat "$HOME/.config/beskar/dock"; else echo "__none__"; fi' }, function(out)
        if not out then
            return
        end
        local list, none = {}, false
        for line in out:gmatch("[^\n]+") do
            if line == "__none__" then
                none = true
            elseif line:match("%S") then
                list[#list + 1] = line:gsub("^%s+", ""):gsub("%s+$", "")
            end
        end
        local new = (not none) and list or nil
        local same = (new == nil and pinned == nil)
        if new and pinned and #new == #pinned then
            same = true
            for k = 1, #new do
                if new[k] ~= pinned[k] then same = false end
            end
        end
        if not same then
            pinned = new
            build_dock()
        end
    end)
end
read_pins()
every(5000, read_pins)

local OUTPUTS = {}
local function push_mon()
    local shown, busy = {}, {}
    for _, w in ipairs(WS) do
        if w.is_active and w.output then
            shown[w.output] = w.idx or 1
            busy[w.output] = w.id
        end
    end
    local count = {}
    for _, win in ipairs(WINS) do
        if win.workspace_id then
            count[win.workspace_id] = (count[win.workspace_id] or 0) + 1
        end
    end
    local recs = {}
    for i, name in ipairs(OUTPUTS) do
        recs[i] = { active = shown[name] or 1, busy = count[busy[name] or -1] or 0 }
    end
    model.mon = recs
end

local function refresh_running()
    run("niri", { "msg", "-j", "windows" }, function(out, code)
        if code ~= 0 or not out then
            return
        end
        local ok, list = pcall(json.decode, out)
        if not ok or type(list) ~= "table" then
            return
        end
        WINS = list
        push_mon()
        build_dock()
    end)
end

-- ── niri: the workspace each monitor shows ───────────────────────
-- `model mon` has one record per monitor, in the order of `niri msg outputs`.
local function refresh_workspaces()
    run("niri", { "msg", "-j", "workspaces" }, function(out, code)
        if code ~= 0 or not out then
            return
        end
        local ok, list = pcall(json.decode, out)
        if not ok or type(list) ~= "table" then
            return
        end
        WS = list
        push_mon()
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
    locate(function(place)
        if not place then
            return          -- no place yet: keep the last reading
        end
        local url = string.format(
            "https://api.open-meteo.com/v1/forecast?latitude=%s&longitude=%s&current=temperature_2m,weather_code",
            place.lat, place.lon
        )
        run("curl", { "-fsS", "--max-time", "5", url }, function(out, code)
            if code ~= 0 or not out then
                return
            end
            local ok, data = pcall(json.decode, out)
            local cur = ok and type(data) == "table" and data.current
            if type(cur) ~= "table" or cur.temperature_2m == nil then
                return
            end
            text.weather_temp = string.format("%d°", math.floor(cur.temperature_2m + 0.5))
            text.weather_icon = icon_for(cur.weather_code or 0)
        end)
    end)
end

refresh_weather()
every(WEATHER_EVERY_MS, refresh_weather)
