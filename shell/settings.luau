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
local THEMED = { "topbar", "control_center", "notifications", "dashboard", "settings" }
local PLAIN = { "spotlight", "apple_menu", "osd", "clipboard", "session", "capture" }

local function save_theme(dm_str, skin_str, accent_str)
    -- ~/.config/pleamar_shell.json is read by start.sh to restore the look after a restart.
    local json_text = string.format('{"dark_mode": %s, "skin": %s, "accent": %s}', dm_str, skin_str, accent_str)
    pcall(run, "sh", { "-c", "mkdir -p \"$HOME/.config\" && printf '%s\\n' '" .. json_text .. "' > \"$HOME/.config/pleamar_shell.json\"" }, nil, { output = false })
end

local function broadcast_theme()
    local dm = (fact.dark_mode == true or fact.dark_mode == 1)
    local dm_str = tostring(dm)
    local skin_str = tostring(fact.skin or 0)
    local accent_str = tostring(fact.accent or 0)

    for _, s in ipairs(THEMED) do
        pcall(sys.call, "say", s, "fact dark_mode " .. dm_str)
        pcall(sys.call, "say", s, "fact skin " .. skin_str)
        pcall(sys.call, "say", s, "fact accent " .. accent_str)
    end
    for _, s in ipairs(PLAIN) do
        pcall(sys.call, "say", s, "fact dark_mode " .. dm_str)
        pcall(sys.call, "say", s, "fact skin " .. skin_str)
    end
    save_theme(dm_str, skin_str, accent_str)
    -- GTK / libadwaita apps follow too
    pcall(run, "gsettings", { "set", "org.gnome.desktop.interface", "color-scheme", dm and "prefer-dark" or "prefer-light" }, nil, { output = false })
end

on("toggle_dark", function()
    local cur = (fact.dark_mode == true or fact.dark_mode == 1)
    fact.dark_mode = not cur
    broadcast_theme()
end)

on("choose_skin", function(val)
    fact.skin = tonumber(val) or 0
    broadcast_theme()
end)

on("choose_accent", function(val)
    fact.accent = tonumber(val) or 0
    broadcast_theme()
end)

on("volume_set", function(val)
    local v = tonumber(val) or 0.65
    sys.call("audio.volume", v)
end)

on("brightness_set", function(val)
    local b = tonumber(val) or 0.75
    sys.call("brightness.level", b)
end)

on("apply_wallpaper", function(idx)
    local i = tonumber(idx) or 0
    fact.wall_choice = i
    local path = wallpapers[i]
    if path then
        log("System Settings: Applying wallpaper", path)
        -- Ensure awww-daemon is up and set the image
        os.execute("pgrep awww-daemon >/dev/null || (awww-daemon & sleep 0.2)")
        os.execute(string.format("awww img '%s' 2>/dev/null &", path))
    end
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
