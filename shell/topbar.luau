-- iNiR Top Bar Companion Logic (Niri Workspaces + Weather Fetch)
on("open_apple_menu", function()
    pcall(sys.call, "say", "apple_menu", "emit toggle")
end)

on("open_control_center", function()
    pcall(sys.call, "say", "control_center", "emit toggle")
end)

on("open_spotlight", function()
    pcall(sys.call, "say", "spotlight", "emit toggle")
end)

on("open_widgets", function()
    pcall(sys.call, "say", "widgets", "emit toggle")
end)

on("tray_activate", function(i)
    local it = model.icons and model.icons[i + 1]
    if it and it.key then
        pcall(sys.call, "tray.activate", it.key)
    end
end)

-- Fetch Niri Workspaces and Active Window
local function update_niri_state()
    local handle = io.popen("python3 -c \"import subprocess, json\ntry:\n    ws = json.loads(subprocess.check_output(['niri', 'msg', '-j', 'workspaces']))\n    f = next((w for w in ws if w.get('is_focused')), None)\n    if f:\n        print(f.get('idx', 1))\n    else:\n        print(1)\nexcept Exception:\n    print(1)\" 2>/dev/null")
    if handle then
        local idx = handle:read("*n")
        handle:close()
        if idx then
            fact.focused_ws = idx
        end
    end
end

-- Fetch Weather via Open-Meteo
local function update_weather()
    local handle = io.popen("python3 -c \"import urllib.request, json\ntry:\n    with urllib.request.urlopen('https://api.open-meteo.com/v1/forecast?latitude=28.61&longitude=77.20&current=temperature_2m,weather_code', timeout=3) as r:\n        d = json.loads(r.read().decode())['current']\n        t = round(d.get('temperature_2m', 16))\n        code = d.get('weather_code', 0)\n        icon = '󰖐'\n        if code == 0:\n            icon = '󰖙'\n        elif code in [1, 2, 3]:\n            icon = '󰖐'\n        elif code in [51, 53, 55, 61, 63, 65]:\n            icon = '󰖗'\n        elif code in [71, 73, 75]:\n            icon = '󰖘'\n        elif code >= 95:\n            icon = '󰙾'\n        print(f'{t}°|{icon}')\nexcept Exception:\n    print('16°|󰖐')\" 2>/dev/null")
    if handle then
        local out = handle:read("*l")
        handle:close()
        if out and out ~= "" then
            local temp, icon = out:match("([^|]+)|([^|]+)")
            if temp and icon then
                text.weather_temp = temp
                text.weather_icon = icon
            end
        end
    end
end

-- Initial update
pcall(update_niri_state)
pcall(update_weather)

-- Periodic update
local elapsed = 0
every(1000, function()
    elapsed = elapsed + 1
    pcall(update_niri_state)
    if elapsed % 600 == 0 then
        pcall(update_weather)
    end
end)
