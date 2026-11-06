-- Notification centre & widgets companion logic

local stats_cmd = [[sh -c "awk '{print int($1*15)}' /proc/loadavg; free | grep Mem | awk '{print int($3/$2*100)}'; df / | tail -1 | tr -d '%' | awk '{print $5}'; date +'%B:%d:%A'"]]

local function update_stats()
    pcall(run, "sh", {"-c", stats_cmd}, function(output, code)
        if code == 0 and output and #output > 0 then
            local lines = {}
            for line in output:gmatch("[^\r\n]+") do
                lines[#lines + 1] = line
            end
            if #lines >= 3 then
                local cpu = tonumber(lines[1]) or 15
                local mem = tonumber(lines[2]) or 42
                local disk = tonumber(lines[3]) or 55
                fact.cpu_pct = math.min(100, math.max(0, cpu))
                fact.mem_pct = math.min(100, math.max(0, mem))
                fact.disk_pct = math.min(100, math.max(0, disk))
            end
            if #lines >= 4 then
                local parts = {}
                for p in lines[4]:gmatch("[^:]+") do
                    parts[#parts + 1] = p
                end
                if #parts >= 3 then
                    text.cal_month = parts[1]:upper()
                    text.cal_day = parts[2]
                    text.cal_dow = parts[3]
                end
            end
        end
    end)
end

-- Update stats immediately and periodically every 5s while daemon runs
update_stats()
every(5000, function()
    if fact.open then
        update_stats()
    end
end)

on("fact:open", function(open)
    if open then
        update_stats()
    end
end)

on("refresh_stats", function()
    update_stats()
end)

-- ── weather (same place as the top bar) ──────────────────────────
local LAT, LON = 28.61, 77.20
local function icon_for(code)
    if code == 0 then return "󰖙"
    elseif code <= 3 then return "󰖐"
    elseif code == 45 or code == 48 then return "󰖑"
    elseif (code >= 51 and code <= 67) or (code >= 80 and code <= 82) then return "󰖗"
    elseif (code >= 71 and code <= 77) or code == 85 or code == 86 then return "󰖘"
    elseif code >= 95 then return "󰙾" end
    return "󰖐"
end
local function words_for(code)
    if code == 0 then return "Clear"
    elseif code <= 2 then return "Partly Cloudy"
    elseif code == 3 then return "Overcast"
    elseif code == 45 or code == 48 then return "Fog"
    elseif (code >= 51 and code <= 57) then return "Drizzle"
    elseif (code >= 61 and code <= 67) or (code >= 80 and code <= 82) then return "Rain"
    elseif (code >= 71 and code <= 77) or code == 85 or code == 86 then return "Snow"
    elseif code >= 95 then return "Thunderstorm" end
    return "Cloudy"
end

local function refresh_weather()
    local url = string.format(
        "https://api.open-meteo.com/v1/forecast?latitude=%s&longitude=%s&current=temperature_2m,weather_code&daily=temperature_2m_max,temperature_2m_min&timezone=auto&forecast_days=1",
        LAT, LON)
    run("curl", { "-fsS", "--max-time", "6", url }, function(out, code)
        if code ~= 0 or not out then return end
        local ok, d = pcall(json.decode, out)
        local cur = ok and type(d) == "table" and d.current
        if type(cur) ~= "table" or cur.temperature_2m == nil then return end
        local wc = cur.weather_code or 0
        text.weather_temp = string.format("%d°C", math.floor(cur.temperature_2m + 0.5))
        text.weather_cond = words_for(wc)
        text.weather_icon = icon_for(wc)
        local day = d.daily
        if type(day) == "table" and day.temperature_2m_max and day.temperature_2m_min then
            text.weather_range = string.format("H: %d° · L: %d°",
                math.floor(day.temperature_2m_max[1] + 0.5), math.floor(day.temperature_2m_min[1] + 0.5))
        end
    end)
end

refresh_weather()
every(15 * 60 * 1000, refresh_weather)

-- one panel at a time
require("exclusive")("dashboard")
