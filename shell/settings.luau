-- System Settings logic. Every control in settings.plm lands here.
--   look      mode (light / dark / auto), glass, accent  → broadcast to every scene and saved (pleamar_shell.json)
--   prefs     bar / dock / notification options          → saved in ~/.config/beskar/prefs.json, pushed to the scenes
--   system    sound, brightness, displays (niri msg), Wi-Fi, Bluetooth, updates, shortcuts (read from niri's config)

local THEMED = { "topbar", "control_center", "notifications", "dashboard", "settings", "wallpapers",
                "spotlight", "clipboard", "session", "capture", "appswitcher", "lock", "music" }

local function say(scene, words)
    pcall(sys.call, "say", scene, words)
end

local function sh(script, cb, ...)
    run("sh", { "-c", script, "x", ... }, cb, cb == nil and { output = false } or nil)
end

-- ── the sidebar ──────────────────────────────────────────────────
local CATS = {
    { 0, "󰏘", 0, "Appearance" }, { 1, "󰍹", 1, "Displays" }, { 2, "󰕾", 2, "Sound" }, { 3, "󰤨", 3, "Wi-Fi" },
    { 4, "󰂯", 4, "Bluetooth" }, { 5, "󰒎", 5, "Notifications" }, { 6, "󰍜", 6, "Menu Bar & Dock" },
    { 7, "󰸉", 7, "Wallpaper" }, { 8, "󰌌", 8, "Shortcuts" }, { 9, "󰋚", 9, "General" }, { 10, "󰚰", 10, "Software Update" },
}
local TITLES = {}
for _, c in ipairs(CATS) do
    TITLES[c[1]] = c[4]
end

local function paint_cats()
    local q = (text.side_q or ""):lower()
    local rows = {}
    for _, c in ipairs(CATS) do
        if q == "" or c[4]:lower():find(q, 1, true) then
            rows[#rows + 1] = { idx = c[1], icon = c[2], tint = c[3], name = c[4] }
        end
    end
    model.cats = rows
end
paint_cats()
on("text:side_q", paint_cats)

-- ── theme: mode, glass, accent, clock format ─────────────────────
local function save_theme(dm_str, skin_str, accent_str, auto_str, h12_str)
    -- ~/.config/pleamar_shell.json is read by start.sh to restore the look after a restart.
    local json_text = string.format('{"dark_mode": %s, "skin": %s, "accent": %s, "accent_auto": %s, "hour12": %s}', dm_str, skin_str, accent_str, auto_str, h12_str)
    sh("mkdir -p \"$HOME/.config\" && printf '%s\\n' '" .. json_text .. "' > \"$HOME/.config/pleamar_shell.json\"")
end

local function broadcast_theme()
    local dm = (fact.dark_mode == true or fact.dark_mode == 1)
    local dm_str = tostring(dm)
    local skin_str = tostring(fact.skin or 0)
    local accent_str = tostring(fact.accent or 0)
    local auto_str = tostring(fact.accent_auto == true)
    local h12_str = tostring(fact.hour12 ~= false)
    for _, s in ipairs(THEMED) do
        if s ~= "settings" then
            say(s, "fact dark_mode " .. dm_str)
            say(s, "fact skin " .. skin_str)
            say(s, "fact accent " .. accent_str)
            say(s, "fact accent_auto " .. auto_str)
            say(s, "fact hour12 " .. h12_str)
        end
    end
    save_theme(dm_str, skin_str, accent_str, auto_str, h12_str)
    -- GTK / libadwaita apps follow too
    pcall(run, "gsettings", { "set", "org.gnome.desktop.interface", "color-scheme", dm and "prefer-dark" or "prefer-light" }, nil, { output = false })
end

-- ── prefs (bar, dock, notifications) ─────────────────────────────
local BANNER_MS = { [0] = 3000, [1] = 5500, [2] = 8000, [3] = 12000 }
local prefs_pending = false

local function b(v)
    return v == true or v == 1
end

local function save_prefs()
    local j = string.format(
        '{"appearance": %d, "seconds": %s, "weather": %s, "tray": %s, "dock_auto": %s, "banners": %s, "banner_i": %d}',
        tonumber(fact.appearance) or 1, tostring(b(fact.pref_seconds)), tostring(b(fact.pref_weather)), tostring(b(fact.pref_tray)),
        tostring(b(fact.pref_dock_auto)), tostring(b(fact.banners)), tonumber(fact.banner_i) or 1)
    sh('mkdir -p "$HOME/.config/beskar" && printf "%s\\n" "$1" > "$HOME/.config/beskar/prefs.json"', nil, j)
end

local function push_prefs()
    say("topbar", "fact pref_seconds " .. tostring(b(fact.pref_seconds)))
    say("topbar", "fact pref_weather " .. tostring(b(fact.pref_weather)))
    say("topbar", "fact pref_tray " .. tostring(b(fact.pref_tray)))
    say("topbar", "fact pref_dock_auto " .. tostring(b(fact.pref_dock_auto)))
    say("notifications", "fact banners " .. tostring(b(fact.banners)))
    say("notifications", "fact banner_ms " .. tostring(BANNER_MS[tonumber(fact.banner_i) or 1] or 5500))
    say("notifications", "fact dnd " .. tostring(b(fact.dnd)))
end

local function changed_pref()
    save_prefs()
    push_prefs()
end

local function load_prefs()
    sh('cat "$HOME/.config/beskar/prefs.json" 2>/dev/null', function(out)
        local ok, p = pcall(json.decode, out or "")
        if ok and type(p) == "table" then
            if p.appearance ~= nil then fact.appearance = tonumber(p.appearance) or 1 end
            if p.seconds ~= nil then fact.pref_seconds = p.seconds == true end
            if p.weather ~= nil then fact.pref_weather = p.weather == true end
            if p.tray ~= nil then fact.pref_tray = p.tray == true end
            if p.dock_auto ~= nil then fact.pref_dock_auto = p.dock_auto == true end
            if p.banners ~= nil then fact.banners = p.banners == true end
            if p.banner_i ~= nil then fact.banner_i = tonumber(p.banner_i) or 1 end
        end
        -- the other scenes may still be starting: push now and once more a little later
        push_prefs()
        after(3000, push_prefs)
        after(8000, push_prefs)
    end)
end
-- the theme file start.sh restores: pick the clock format up from it too
sh('cat "$HOME/.config/pleamar_shell.json" 2>/dev/null', function(out)
    local ok, t = pcall(json.decode, out or "")
    if ok and type(t) == "table" and t.hour12 ~= nil then
        fact.hour12 = t.hour12 == true
    end
    load_prefs()
end)

-- ── Appearance ───────────────────────────────────────────────────
local function auto_dark()
    local h = tonumber(os.date("%H")) or 12
    return h >= 19 or h < 7
end

local function apply_mode(announce)
    local m = tonumber(fact.appearance) or 1
    local dark = (m == 1) or (m == 2 and auto_dark())
    local was = b(fact.dark_mode)
    fact.dark_mode = dark
    if announce or dark ~= was then
        broadcast_theme()
    end
end

on("set_mode", function(n)
    fact.appearance = tonumber(n) or 1
    apply_mode(true)
    save_prefs()
end)

-- the Control Center's dark-mode tile
on("set_dark_mode", function(v)
    fact.appearance = (tonumber(v) or 1) == 1 and 1 or 0
    apply_mode(true)
    save_prefs()
end)

every(60000, function()
    if tonumber(fact.appearance) == 2 then
        apply_mode(false)
    end
end)

on("choose_skin", function(val)
    fact.skin = tonumber(val) or 0
    broadcast_theme()
end)

-- Picked by hand: that ends "match the wallpaper".
on("choose_accent", function(val)
    fact.accent = tonumber(val) or 0
    fact.accent_auto = false
    broadcast_theme()
end)

-- Picked by wallpapers.luau from the wallpaper (only while "match the wallpaper" is on).
on("auto_accent", function(val)
    if fact.accent_auto == true then
        fact.accent = tonumber(val) or 0
        broadcast_theme()
    end
end)

on("toggle_accent_auto", function()
    fact.accent_auto = not (fact.accent_auto == true)
    broadcast_theme()
end)

-- ── Menu bar & dock ──────────────────────────────────────────────
on("toggle_hour12", function()
    fact.hour12 = not (fact.hour12 ~= false)
    broadcast_theme()
end)
on("toggle_seconds", function() fact.pref_seconds = not b(fact.pref_seconds); changed_pref() end)
on("toggle_weather", function() fact.pref_weather = not b(fact.pref_weather); changed_pref() end)
on("toggle_tray", function() fact.pref_tray = not b(fact.pref_tray); changed_pref() end)
on("toggle_dock_auto", function() fact.pref_dock_auto = not b(fact.pref_dock_auto); changed_pref() end)

-- ── Notifications ────────────────────────────────────────────────
on("toggle_dnd", function() fact.dnd = not b(fact.dnd); changed_pref() end)
on("toggle_banners", function() fact.banners = not b(fact.banners); changed_pref() end)
on("banner_secs_pick", function(n) fact.banner_i = tonumber(n) or 1; changed_pref() end)
on("clear_notif_history", function() say("notifications", "emit clear_past") end)

-- ── Sound ────────────────────────────────────────────────────────
local out_ids = {}
sys.watch("audio", function(a)
    a = a or {}
    fact.in_level = a.input or 0
    local rows = {}
    out_ids = {}
    for _, o in ipairs(a.outputs or {}) do
        if #rows < 4 then
            out_ids[#rows + 1] = o.id
            rows[#rows + 1] = { name = o.name or "Output", def = o.default == true }
        end
    end
    model.outs = rows
end)

on("volume_set", function(val) pcall(sys.call, "audio.volume", tonumber(val) or 0) end)
on("input_set", function(val) pcall(sys.call, "audio.input", tonumber(val) or 0) end)
on("toggle_mute", function() pcall(sys.call, "audio.mute") end)
on("pick_out", function(i)
    local id = out_ids[(tonumber(i) or 0) + 1]
    if id ~= nil then
        pcall(sys.call, "audio.default", id)
    end
end)
on("brightness_set", function(val) pcall(sys.call, "brightness.level", math.max(0.05, tonumber(val) or 1)) end)

-- ── Wi-Fi / Bluetooth ────────────────────────────────────────────
local net_state = {}
sys.watch("network", function(n)
    net_state = n or {}
    fact.wifi_on = net_state.wifi ~= false
    if net_state.wifi == false then
        text.wifi_line = "Off"
    elseif net_state.online and net_state.name and net_state.name ~= "" then
        text.wifi_line = "Connected to " .. net_state.name
    else
        text.wifi_line = "Not connected"
    end
end)
on("toggle_wifi", function() pcall(sys.call, "network.wifi", net_state.wifi == false) end)

local bt_state = {}
sys.watch("bluetooth", function(s)
    bt_state = s or {}
    fact.bt_on = bt_state.powered == true
    if not fact.bt_on then
        text.bt_line = "Off"
    else
        local names = {}
        for _, d in ipairs(bt_state.devices or {}) do
            if d.connected then
                names[#names + 1] = d.name or d.address or "device"
            end
        end
        text.bt_line = #names > 0 and ("Connected: " .. table.concat(names, ", ")) or "On, nothing connected"
    end
end)
on("toggle_bt", function() pcall(sys.call, "bluetooth.power", not (bt_state.powered == true)) end)

local function open_in_cc(ev)
    fact.open = false
    after(250, function() say("topbar", "emit " .. ev) end)
end
on("open_wifi_panel", function() open_in_cc("open_cc_wifi") end)
on("open_bt_panel", function() open_in_cc("open_cc_bt") end)

-- ── Wallpaper ────────────────────────────────────────────────────
local function load_wallpaper()
    sh('cat "$HOME/.config/beskar/wallpaper" 2>/dev/null', function(out)
        local path = (out or ""):match("([^\n]+)")
        if path and path ~= "" then
            text.wall_path = path
            text.wall_name = path:match("([^/]+)$") or path
            fact.wall_ready = true
        else
            text.wall_name = "Not chosen yet"
            fact.wall_ready = false
        end
    end)
end

on("open_wallpapers", function()
    fact.open = false
    after(250, function() say("topbar", "emit open_panel 3") end)
end)

-- ── Displays (niri) ──────────────────────────────────────────────
local outputs, disp_names, disp_sel = {}, {}, 0
local SCALES = { 1, 1.25, 1.5, 2 }
local res_opts, hz_opts = {}, {}

local function paint_displays()
    local rows = {}
    for i, name in ipairs(disp_names) do
        local d = outputs[name]
        local make = ((d.model and d.model ~= "") and d.model or (d.make or "")):gsub("^%s+", ""):gsub("%s+$", "")
        local mode = d.modes and d.current_mode and d.modes[d.current_mode + 1]
        rows[#rows + 1] = {
            name = name, title = make ~= "" and make or "Display", sel = (i - 1) == disp_sel,
            mode = mode and string.format("%d × %d @ %d Hz", mode.width, mode.height, math.floor(mode.refresh_rate / 1000 + 0.5)) or "",
        }
        if #rows >= 4 then break end
    end
    model.disps = rows

    local name = disp_names[disp_sel + 1]
    local d = name and outputs[name]
    res_opts, hz_opts = {}, {}
    local resl, hzl = {}, {}
    if d and d.modes then
        local cur = d.modes[(d.current_mode or 0) + 1]
        local seen_res, seen_hz = {}, {}
        local mods = {}
        for _, m in ipairs(d.modes) do mods[#mods + 1] = m end
        table.sort(mods, function(a, c)
            if a.width * a.height ~= c.width * c.height then return a.width * a.height > c.width * c.height end
            return a.refresh_rate > c.refresh_rate
        end)
        for _, m in ipairs(mods) do
            local key = m.width .. "x" .. m.height
            if not seen_res[key] and #res_opts < 4 then
                seen_res[key] = true
                res_opts[#res_opts + 1] = m
                resl[#resl + 1] = { label = m.width .. " × " .. m.height, cur = cur and cur.width == m.width and cur.height == m.height }
            end
            if cur and m.width == cur.width and m.height == cur.height then
                local hz = math.floor(m.refresh_rate / 1000 + 0.5)
                if not seen_hz[hz] and #hz_opts < 5 then
                    seen_hz[hz] = true
                    hz_opts[#hz_opts + 1] = m
                    hzl[#hzl + 1] = { label = hz .. " Hz", cur = cur.refresh_rate == m.refresh_rate }
                end
            end
        end
        local sc = d.logical and d.logical.scale or 1
        local si = 0
        for i, v in ipairs(SCALES) do
            if math.abs(v - sc) < 0.01 then si = i - 1 end
        end
        fact.disp_scale_i = si
    end
    model.reslist = resl
    model.hzlist = hzl
end

local function refresh_displays()
    run("niri", { "msg", "-j", "outputs" }, function(out, code)
        local ok, o = pcall(json.decode, out or "")
        if code ~= 0 or not ok or type(o) ~= "table" then
            return
        end
        outputs, disp_names = o, {}
        for name in pairs(o) do
            disp_names[#disp_names + 1] = name
        end
        table.sort(disp_names)
        if disp_sel >= #disp_names then disp_sel = 0 end
        paint_displays()
    end)
end

local function niri_output(args)
    local name = disp_names[disp_sel + 1]
    if not name then return end
    local full = { "msg", "output", name }
    for _, a in ipairs(args) do full[#full + 1] = a end
    run("niri", full, function() after(1500, refresh_displays) end)
end

on("disp_pick", function(i) disp_sel = tonumber(i) or 0; paint_displays() end)
on("disp_scale", function(i)
    local v = SCALES[(tonumber(i) or 0) + 1]
    if v then niri_output({ "scale", tostring(v) }) end
end)
local function mode_arg(m)
    return string.format("%dx%d@%.3f", m.width, m.height, m.refresh_rate / 1000)
end
on("disp_res", function(i)
    local m = res_opts[(tonumber(i) or 0) + 1]
    if m then niri_output({ "mode", mode_arg(m) }) end
end)
on("disp_hz", function(i)
    local m = hz_opts[(tonumber(i) or 0) + 1]
    if m then niri_output({ "mode", mode_arg(m) }) end
end)

-- ── Shortcuts: read from niri's own config ───────────────────────
local all_binds, bind_view, boff = {}, {}, 0
local MAX_BINDS = 9

local function pretty_keys(k)
    k = k:gsub("Mod", "Super"):gsub("Comma", ","):gsub("Period", "."):gsub("Slash", "/"):gsub("Return", "Enter"):gsub("BracketLeft", "["):gsub("BracketRight", "]"):gsub("Print", "PrtSc")
    k = k:gsub("XF86Audio", ""):gsub("XF86MonBrightness", "Brightness "):gsub("Raise", "Up "):gsub("Lower", "Down ")
    return (k:gsub("%+", " + "))
end

local function humanize(action)
    local w = action:match("^([%w%-]+)") or action
    return (w:gsub("%-", " "):gsub("^%l", string.upper))
end

local function parse_binds(src)
    local map, order = {}, {}
    local inside = false
    for line in (src or ""):gmatch("[^\n]+") do
        local t = line:gsub("^%s+", "")
        if t:match("^binds%s*{") then
            inside = true
        elseif inside and t:match("^}%s*$") then
            inside = false
        elseif inside and not t:match("^//") then
            local key, attrs, body = t:match("^([%w_%+]+)%s*(.-)%s*{%s*(.-)%s*}%s*$")
            if key then
                local title = attrs:match('hotkey%-overlay%-title="([^"]*)"')
                local what = title
                if not what then
                    local act = body:gsub(";%s*$", "")
                    local spawned = act:match('^spawn%s+"[^"]*"%s+"([^"]*)"')
                    what = spawned and humanize(spawned) or humanize(act)
                end
                if not map[key] then order[#order + 1] = key end
                map[key] = what
            end
        end
    end
    local list = {}
    for _, k in ipairs(order) do
        list[#list + 1] = { keys = pretty_keys(k), what = map[k] }
    end
    table.sort(list, function(a, c) return a.what:lower() < c.what:lower() end)
    return list
end

local function paint_binds(reset)
    local q = (text.bind_q or ""):lower()
    bind_view = {}
    for _, e in ipairs(all_binds) do
        if q == "" or e.what:lower():find(q, 1, true) or e.keys:lower():find(q, 1, true) then
            bind_view[#bind_view + 1] = e
        end
    end
    if reset then boff = 0 end
    boff = math.max(0, math.min(boff, math.max(0, #bind_view - MAX_BINDS)))
    local rows = {}
    for i = boff + 1, math.min(#bind_view, boff + MAX_BINDS) do
        rows[#rows + 1] = bind_view[i]
    end
    model.binds = rows
    text.bind_count = (#bind_view) .. " shortcuts"
end

local function load_binds()
    sh('cat "$HOME/.config/niri/dms/binds.kdl" "$HOME/.config/niri/config.kdl" 2>/dev/null', function(out)
        all_binds = parse_binds(out)
        paint_binds(true)
    end)
end
on("text:bind_q", function() paint_binds(true) end)
on("bind_scroll", function(wheel)
    boff = boff + ((tonumber(wheel) or 0) > 0 and -1 or 1)
    paint_binds(false)
end)

-- ── Software update (pacman) ─────────────────────────────────────
local function check_updates()
    fact.up_checking = true
    text.up_title = "Checking…"
    text.up_sub = "Asking the package servers"
    sh('timeout 40 checkupdates 2>/dev/null', function(out, code)
        fact.up_checking = false
        local rows, n = {}, 0
        for line in (out or ""):gmatch("[^\n]+") do
            local name, old, new = line:match("^(%S+)%s+(%S+)%s+%->%s+(%S+)")
            if name then
                n = n + 1
                if #rows < 6 then
                    rows[#rows + 1] = { name = name, ver = old .. " → " .. new }
                end
            end
        end
        model.ups = rows
        fact.up_n = n
        if n == 0 then
            text.up_title = "Your system is up to date"
            text.up_sub = (code ~= 0 and code ~= 2) and "Could not reach the package servers" or "Nothing to install"
        else
            text.up_title = n .. (n == 1 and " update available" or " updates available")
            text.up_sub = (n > #rows) and ("Showing the first " .. #rows .. ". Update all installs everything.") or "Ready to install"
        end
    end)
end
on("check_updates", check_updates)
on("run_update", function()
    pcall(run, "kitty", { "-e", "sh", "-c", "paru -Syu || yay -Syu || sudo pacman -Syu; echo; read -p 'Done. Press Enter.' _" }, nil, { output = false })
end)
on("open_updates_tab", function() fact.tab = 10 end)

-- ── navigation ───────────────────────────────────────────────────
on("pick_cat", function(i) fact.tab = tonumber(i) or 0 end)
on("fact:tab", function(v)
    local t = tonumber(v) or 0
    text.pane_title = TITLES[t] or "Settings"
    if t == 1 then refresh_displays()
    elseif t == 7 then load_wallpaper()
    elseif t == 8 then load_binds()
    elseif t == 10 and (fact.up_n or 0) == 0 then check_updates()
    end
end)
on("fact:open", function(v)
    if v == true or v == 1 then
        local t = tonumber(fact.tab) or 0
        text.side_q = ""
        text.pane_title = TITLES[t] or "Settings"
        if t == 1 then refresh_displays() elseif t == 7 then load_wallpaper() elseif t == 8 then load_binds() end
        apply_mode(false)
    end
end)

-- ── About This PC: read the machine, once ────────────────────────
run("sh", { "-c", [=[
. /etc/os-release 2>/dev/null
echo "${PRETTY_NAME:-Linux}"
grep -m1 'model name' /proc/cpuinfo | cut -d: -f2 | sed 's/^ *//' | sed "s/\$/ ($(nproc) threads)/"
(lspci 2>/dev/null | grep -E 'VGA|3D|Display' | sed -E 's/^[^ ]+ [^:]+: *//; s/ \(rev.*//; s/.*\[([^]]*)\].*/\1/' | cut -c1-40 | paste -sd'+' | sed 's/+/ + /g') || true
awk '/MemTotal/ {printf "%.1f GB\n", $2/1048576}' /proc/meminfo
uname -r
df -h / --output=size,avail | tail -1 | awk '{print $1 " (" $2 " available)"}'
]=] }, function(out, code)
    if code ~= 0 or not out then
        return
    end
    local lines = {}
    for l in string.gmatch(out, "([^\n]*)\n?") do
        lines[#lines + 1] = l
    end
    text.about_os = lines[1] ~= "" and lines[1] or "Linux"
    text.about_cpu = lines[2] or ""
    text.about_gpu = (lines[3] and lines[3] ~= "") and lines[3] or "—"
    text.about_mem = lines[4] or ""
    text.about_kernel = lines[5] or ""
    text.about_disk = lines[6] or ""
end)

-- one panel at a time
require("exclusive")("settings")

-- ── who is logged in: the full name if the account has one, else the login name ──
local function load_user_name()
    run("sh", { "-c", 'n=$(getent passwd "$(id -un)" | cut -d: -f5 | cut -d, -f1); [ -n "$n" ] && echo "$n" || id -un' }, function(out)
        local n = (out or ""):match("([^\n]+)")
        if n and n ~= "" then
            text.user_name = n
        end
    end)
end
load_user_name()

