-- System Settings companion logic (Pleamar engine)

local wallpapers = {
    [0] = "/usr/share/wallpapers/cachyos-wallpapers/Liquid.png",
    [1] = "/usr/share/wallpapers/cachyos-wallpapers/Abstract.png",
    [2] = "/usr/share/wallpapers/cachyos-wallpapers/Cachy_Topography.jpg",
    [3] = "/usr/share/wallpapers/cachyos-wallpapers/Dimensions.png",
    [4] = "/usr/share/wallpapers/cachyos-wallpapers/Lines.png",
    [5] = "/usr/share/wallpapers/cachyos-wallpapers/DarkStreaks.png",
}

-- Scenes that follow the shared theme (shell/common/theme.plm) and so have an `accent` fact too.
local THEMED = { "topbar", "control_center", "notifications", "dashboard", "settings", "wallpapers",
                "spotlight", "clipboard", "session", "capture", "appswitcher", "lock" }
local PLAIN = {}

local function save_theme(dm_str, skin_str, accent_str, auto_str, h12_str)
    -- ~/.config/pleamar_shell.json is read by start.sh to restore the look after a restart.
    local json_text = string.format('{"dark_mode": %s, "skin": %s, "accent": %s, "accent_auto": %s, "hour12": %s}', dm_str, skin_str, accent_str, auto_str, h12_str)
    pcall(run, "sh", { "-c", "mkdir -p \"$HOME/.config\" && printf '%s\\n' '" .. json_text .. "' > \"$HOME/.config/pleamar_shell.json\"" }, nil, { output = false })
end

local function broadcast_theme()
    local dm = (fact.dark_mode == true or fact.dark_mode == 1)
    local dm_str = tostring(dm)
    local skin_str = tostring(fact.skin or 0)
    local accent_str = tostring(fact.accent or 0)
    local auto_str = tostring(fact.accent_auto == true)
    local h12_str = tostring(fact.hour12 ~= false)

    for _, s in ipairs(THEMED) do
        pcall(sys.call, "say", s, "fact dark_mode " .. dm_str)
        pcall(sys.call, "say", s, "fact skin " .. skin_str)
        pcall(sys.call, "say", s, "fact accent " .. accent_str)
        pcall(sys.call, "say", s, "fact accent_auto " .. auto_str)
        pcall(sys.call, "say", s, "fact hour12 " .. h12_str)
    end
    for _, s in ipairs(PLAIN) do
        pcall(sys.call, "say", s, "fact dark_mode " .. dm_str)
        pcall(sys.call, "say", s, "fact skin " .. skin_str)
    end
    save_theme(dm_str, skin_str, accent_str, auto_str, h12_str)
    -- GTK / libadwaita apps follow too
    pcall(run, "gsettings", { "set", "org.gnome.desktop.interface", "color-scheme", dm and "prefer-dark" or "prefer-light" }, nil, { output = false })
end

on("toggle_dark", function()
    local cur = (fact.dark_mode == true or fact.dark_mode == 1)
    fact.dark_mode = not cur
    broadcast_theme()
end)

on("toggle_hour12", function()
    fact.hour12 = not (fact.hour12 ~= false)
    broadcast_theme()
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
    if fact.accent_auto then
        pcall(sys.call, "say", "wallpapers", "emit accent_now")
    end
end)

on("volume_set", function(val)
    local v = tonumber(val) or 0.65
    sys.call("audio.volume", v)
end)

on("brightness_set", function(val)
    local b = tonumber(val) or 0.75
    sys.call("brightness.level", b)
end)

on("open_wallpapers", function()
    pcall(sys.call, "say", "topbar", "emit open_panel 3")
end)

on("run_update", function()
    log("System Settings: Launching system package upgrade...")
    spawn("kitty -e yay -Syu")
end)

on("toggle_wifi", function()
    sys.call("network.wifi.toggle")
end)

on("toggle_bt", function()
    sys.call("bluetooth.toggle")
end)

on("toggle_dnd", function()
    fact.dnd = not fact.dnd
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

-- ── Displays: what niri says is connected ───────────────────────
run("niri", { "msg", "-j", "outputs" }, function(out, code)
    local ok, o = pcall(json.decode, out or "")
    if code ~= 0 or not ok or type(o) ~= "table" then
        return
    end
    local names = {}
    for name in pairs(o) do
        names[#names + 1] = name
    end
    table.sort(names)
    fact.disp_count = math.min(2, #names)
    for i = 1, math.min(2, #names) do
        local d = o[names[i]]
        local make = ((d.model and d.model ~= "") and d.model or (d.make or "")):gsub("^%s+", ""):gsub("%s+$", "")
        text["disp_name_" .. (i - 1)] = (make ~= "" and make or "Display") .. " (" .. names[i] .. ")"
        local mode = d.modes and d.current_mode and d.modes[d.current_mode + 1]
        if mode then
            text["disp_mode_" .. (i - 1)] = string.format("%d × %d @ %d Hz", mode.width, mode.height, math.floor(mode.refresh_rate / 1000 + 0.5))
        end
    end
end)
