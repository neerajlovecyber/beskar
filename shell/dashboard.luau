-- Dashboard ("Today") logic: greeting, month calendar, weather (same place as the top bar), CPU / memory / disk,
-- uptime and the battery's real state. The frame draws the glass (panel.luau reports the height).
local locate = require("location")
local codes = require("weathercodes")
local panel = require("panel")("dashboard")

-- ── greeting and date ────────────────────────────────────────────
local user_name = nil
local function paint_greeting()
    local h = tonumber(os.date("%H")) or 12
    local g = h < 5 and "Good night" or h < 12 and "Good morning" or h < 18 and "Good afternoon" or "Good evening"
    text.greeting = user_name and (g .. ", " .. user_name) or g
end
run("sh", { "-c", 'n=$(getent passwd "$USER" | cut -d: -f5 | cut -d, -f1); [ -z "$n" ] && n="$USER"; echo "$n"' }, function(out)
    local n = (out or ""):gsub("%s+$", "")
    if n ~= "" then
        user_name = n:match("^(%S+)") or n
    end
    paint_greeting()
end)
paint_greeting()

local function paint_date()
    run("sh", { "-c", "date +'%A, %-d %B %Y'" }, function(out) text.today_text = (out or ""):gsub("%s+$", "") end)
end
paint_date()

-- ── the month calendar (Monday first) ────────────────────────────
local MONTHS = { "January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December" }

local function paint_calendar()
    local now = os.date("*t")
    local shift = tonumber(fact.cal_shift) or 0
    local y, m = now.year, now.month + shift
    y = y + math.floor((m - 1) / 12)
    m = (m - 1) % 12 + 1
    text.cal_title = MONTHS[m] .. " " .. y
    local first = os.time({ year = y, month = m, day = 1, hour = 12 })
    local lead = (tonumber(os.date("%w", first)) + 6) % 7                      -- days of the month before, Monday first
    local days = tonumber(os.date("%d", os.time({ year = y, month = m + 1, day = 0, hour = 12 })))
    local prev_days = tonumber(os.date("%d", os.time({ year = y, month = m, day = 0, hour = 12 })))
    local cells = {}
    local rows_needed = math.ceil((lead + days) / 7) * 7
    for i = 1, rows_needed do
        local d = i - lead
        if d < 1 then
            cells[i] = { d = tostring(prev_days + d), dim = true, today = false }
        elseif d > days then
            cells[i] = { d = tostring(d - days), dim = true, today = false }
        else
            cells[i] = { d = tostring(d), dim = false, today = (shift == 0 and d == now.day) }
        end
    end
    model.cells = cells
end
on("cal_prev", function() fact.cal_shift = (tonumber(fact.cal_shift) or 0) - 1; paint_calendar() end)
on("cal_next", function() fact.cal_shift = (tonumber(fact.cal_shift) or 0) + 1; paint_calendar() end)
on("cal_now", function() fact.cal_shift = 0; paint_calendar() end)
paint_calendar()

-- ── CPU, memory, disk, uptime ────────────────────────────────────
-- Real CPU use: /proc/stat read twice, 0.4 s apart.
local stats_cmd = [[
a=$(awk '/^cpu /{print $2+$3+$4+$5+$6+$7+$8, $5+$6}' /proc/stat); sleep 0.4
b=$(awk '/^cpu /{print $2+$3+$4+$5+$6+$7+$8, $5+$6}' /proc/stat)
echo "$a $b" | awk '{d=$3-$1; i=$4-$2; print (d>0) ? int((d-i)*100/d+0.5) : 0}'
awk '/MemTotal/{t=$2} /MemAvailable/{a=$2} END{print int((t-a)*100/t+0.5)}' /proc/meminfo
df / | awk 'NR==2{gsub("%","",$5); print $5}'
awk '{s=int($1); d=int(s/86400); h=int((s%86400)/3600); m=int((s%3600)/60); if (d>0) printf "Up %dd %dh", d, h; else if (h>0) printf "Up %dh %dm", h, m; else printf "Up %dm", m}' /proc/uptime
]]

local function update_stats()
    run("sh", { "-c", stats_cmd }, function(output, code)
        if code ~= 0 or not output or #output == 0 then return end
        local lines = {}
        for line in output:gmatch("[^\r\n]+") do lines[#lines + 1] = line end
        if #lines >= 3 then
            fact.cpu_pct = math.min(100, math.max(0, tonumber(lines[1]) or 0))
            fact.mem_pct = math.min(100, math.max(0, tonumber(lines[2]) or 0))
            fact.disk_pct = math.min(100, math.max(0, tonumber(lines[3]) or 0))
        end
        text.uptime_text = lines[4] or ""
    end)
end

-- ── the battery: the service only says "charging"; read the power supply for the real state ──
local BAT_CMD = [[
ac=0; for f in /sys/class/power_supply/A*/online /sys/class/power_supply/AC*/online; do [ -r "$f" ] && [ "$(cat "$f")" = 1 ] && ac=1; done
st=$(cat /sys/class/power_supply/BAT*/status 2>/dev/null | head -1)
t=$(upower -i "$(upower -e 2>/dev/null | grep -i BAT | head -1)" 2>/dev/null | awk -F: '/time to (empty|full)/{gsub(/^ +/,"",$2); print $2; exit}')
echo "$ac|$st|$t"
]]

local function update_battery()
    run("sh", { "-c", BAT_CMD }, function(out)
        local ac, st, tm = (out or ""):match("^(%d)|([^|]*)|(.*)$")
        if not ac then return end
        tm = (tm or ""):gsub("%s+$", "")
        fact.bat_ac = ac == "1"
        if st == "Charging" then
            text.bat_state = "Charging"
            text.bat_sub = tm ~= "" and (tm .. " until full") or "Power connected"
        elseif ac == "1" and st == "Full" then
            text.bat_state = "Fully charged"
            text.bat_sub = "Power connected"
        elseif ac == "1" then
            text.bat_state = "Plugged in"
            text.bat_sub = "Not charging (charge limit)"
        else
            text.bat_state = "On battery"
            text.bat_sub = tm ~= "" and (tm .. " left") or "Running on battery"
        end
    end)
end

local function refresh_all()
    paint_greeting()
    paint_date()
    update_stats()
    update_battery()
    paint_calendar()
end
refresh_all()
every(5000, function()
    if fact.open then
        update_stats()
        update_battery()
    end
end)
on("fact:open", function(open)
    if open then
        fact.cal_shift = 0
        refresh_all()
    end
end)
on("refresh_stats", refresh_all)

-- ── weather (the same place as the top bar; a click opens the weather panel) ──
local function refresh_weather()
    locate(function(place)
        if not place then return end
        text.weather_city = place.city
        local url = string.format(
            "https://api.open-meteo.com/v1/forecast?latitude=%s&longitude=%s&current=temperature_2m,apparent_temperature,weather_code,is_day"
            .. "&daily=temperature_2m_max,temperature_2m_min&timezone=auto&forecast_days=1", place.lat, place.lon)
        run("curl", { "-fsS", "--max-time", "6", url }, function(out, code)
            if code ~= 0 or not out then return end
            local ok, d = pcall(json.decode, out)
            local cur = ok and type(d) == "table" and d.current
            if type(cur) ~= "table" or cur.temperature_2m == nil then return end
            text.weather_temp = string.format("%d°C", math.floor(cur.temperature_2m + 0.5))
            text.weather_cond = codes.words(cur.weather_code)
            text.weather_icon = codes.icon(cur.weather_code, cur.is_day)
            text.weather_feels = string.format("Feels like %d°", math.floor((cur.apparent_temperature or cur.temperature_2m) + 0.5))
            local day = d.daily
            if type(day) == "table" and day.temperature_2m_max and day.temperature_2m_max[1] then
                text.weather_range = string.format("H %d°   L %d°",
                    math.floor(day.temperature_2m_max[1] + 0.5), math.floor(day.temperature_2m_min[1] + 0.5))
            end
        end)
    end)
end
refresh_weather()
every(15 * 60 * 1000, refresh_weather)
on("weather_reload", refresh_weather)
on("open_weather", function() pcall(sys.call, "say", "topbar", "emit open_weather") end)

-- ── tell the frame (it draws the glass) how tall the card is ──
local has_battery = true
local function push_height()
    panel.height(has_battery and 632 or 556)
end
sys.watch("battery", function(b)
    local present = not (b and b.present == false)
    if present ~= has_battery then
        has_battery = present
        push_height()
    end
end)
push_height()

-- one panel at a time
require("exclusive")("dashboard")
