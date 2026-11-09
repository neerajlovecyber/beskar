-- Weather panel logic: Open-Meteo forecast for the place in ~/.config/beskar/location ("LAT LON City"), and the place
-- picker (your IP address, or a search through Open-Meteo's geocoding). Choosing a place writes that file and tells the
-- other scenes that show the weather (top bar, dashboard, widgets) to read it again.
local panel = require("panel")("weather")
local locate = require("location")
local codes = require("weathercodes")

local VIEW_FORECAST_H = 612
local place = nil           -- { lat, lon, city }
local found = {}            -- search results, as the picker lists them

local function urlencode(s)
    return (s:gsub("[^%w%-_%.~]", function(c) return string.format("%%%02X", c:byte()) end))
end

local function hour_text(h)
    if fact.hour12 == false then
        return string.format("%02d", h)
    end
    local ap = h < 12 and "AM" or "PM"
    local x = h % 12
    if x == 0 then x = 12 end
    return x .. " " .. ap
end

local function clock_of(iso)           -- "2026-11-09T06:31" → "6:31 AM" (or 06:31)
    local h, m = (iso or ""):match("T(%d+):(%d+)")
    if not h then return "--" end
    h = tonumber(h)
    if fact.hour12 == false then
        return string.format("%02d:%s", h, m)
    end
    local x = h % 12
    if x == 0 then x = 12 end
    return string.format("%d:%s %s", x, m, h < 12 and "AM" or "PM")
end

local function weekday(date, idx)      -- "2026-11-10" → "Tue"; the first one is "Today"
    if idx == 1 then return "Today" end
    local y, mo, d = (date or ""):match("(%d+)-(%d+)-(%d+)")
    if not y then return "--" end
    return os.date("%a", os.time({ year = tonumber(y), month = tonumber(mo), day = tonumber(d), hour = 12 }))
end

local function deg(v)
    return string.format("%d°", math.floor((v or 0) + 0.5))
end

-- ── the forecast ────────────────────────────────────────────────
local function load()
    fact.loading = true
    locate(function(p)
        place = p
        if not p then
            fact.loading = false
            text.weather_city = "Unknown place"
            return
        end
        text.weather_city = p.city or "Here"
        local url = string.format(
            "https://api.open-meteo.com/v1/forecast?latitude=%s&longitude=%s"
            .. "&current=temperature_2m,relative_humidity_2m,apparent_temperature,weather_code,wind_speed_10m,surface_pressure,is_day"
            .. "&hourly=temperature_2m,weather_code,is_day"
            .. "&daily=weather_code,temperature_2m_max,temperature_2m_min,sunrise,sunset,uv_index_max"
            .. "&timezone=auto&forecast_days=6",
            p.lat, p.lon)
        run("curl", { "-fsS", "--max-time", "8", url }, function(out, code)
            fact.loading = false
            if code ~= 0 or not out then return end
            local ok, d = pcall(json.decode, out)
            if not ok or type(d) ~= "table" or type(d.current) ~= "table" then return end
            local c, hr, dy = d.current, d.hourly or {}, d.daily or {}
            text.w_temp = deg(c.temperature_2m)
            text.w_icon = codes.icon(c.weather_code, c.is_day)
            text.w_cond = codes.words(c.weather_code)
            text.w_feels = "Feels like " .. deg(c.apparent_temperature)
            text.w_hum = string.format("%d%%", math.floor((c.relative_humidity_2m or 0) + 0.5))
            text.w_wind = string.format("%d km/h", math.floor((c.wind_speed_10m or 0) + 0.5))
            text.w_press = string.format("%d hPa", math.floor((c.surface_pressure or 0) + 0.5))
            if dy.temperature_2m_max and dy.temperature_2m_max[1] then
                text.w_range = string.format("H %s   L %s", deg(dy.temperature_2m_max[1]), deg(dy.temperature_2m_min[1]))
                text.w_uv = string.format("%d", math.floor((dy.uv_index_max and dy.uv_index_max[1] or 0) + 0.5))
                text.w_sunrise = clock_of(dy.sunrise and dy.sunrise[1])
                text.w_sunset = clock_of(dy.sunset and dy.sunset[1])
            end
            -- next 8 hours, from the current hour
            local rows = {}
            local nowh = (c.time or ""):sub(1, 13)
            local start = 1
            for i, t in ipairs(hr.time or {}) do
                if t:sub(1, 13) >= nowh then start = i break end
            end
            for i = start, math.min(#(hr.time or {}), start + 7) do
                local h = tonumber(hr.time[i]:match("T(%d+)")) or 0
                rows[#rows + 1] = {
                    t = i == start and "Now" or hour_text(h),
                    icon = codes.icon(hr.weather_code and hr.weather_code[i], hr.is_day and hr.is_day[i]),
                    temp = deg(hr.temperature_2m and hr.temperature_2m[i]),
                }
            end
            model.hours = rows
            -- next days
            local days, lo_all, hi_all = {}, 1e9, -1e9
            for i = 1, math.min(5, #(dy.time or {})) do
                local lo, hi = dy.temperature_2m_min[i], dy.temperature_2m_max[i]
                lo_all, hi_all = math.min(lo_all, lo), math.max(hi_all, hi)
                days[#days + 1] = { day = weekday(dy.time[i], i), icon = codes.icon(dy.weather_code[i], true),
                    lo = deg(lo), hi = deg(hi), lo_n = lo, hi_n = hi }
            end
            model.days = days
            fact.wk_lo = lo_all
            fact.wk_hi = hi_all
            fact.loaded = true
        end)
    end)
end

-- ── choosing a place ────────────────────────────────────────────
local function save_place(lat, lon, city)
    run("sh", { "-c", 'mkdir -p "$HOME/.config/beskar" && printf "%s %s %s\\n" "$1" "$2" "$3" > "$HOME/.config/beskar/location"',
        "x", tostring(lat), tostring(lon), city }, function()
        fact.loaded = false
        fact.view = 0
        panel.height(VIEW_FORECAST_H)
        load()
        -- the other scenes that show the weather read the place again
        for _, scene in ipairs({ "topbar", "dashboard", "widgets" }) do
            pcall(sys.call, "say", scene, "emit weather_reload")
        end
    end, { output = false })
end

local function paint_places()
    local rows = {}
    for i, p in ipairs(found) do
        rows[i] = { name = p.name, sub = p.sub }
    end
    model.places = rows
    panel.height(172 + math.max(#rows, 1) * 48 + 20)
end

local search_timer = nil
local function search(q)
    fact.searching = true
    run("curl", { "-fsS", "--max-time", "6",
        "https://geocoding-api.open-meteo.com/v1/search?count=5&language=en&format=json&name=" .. urlencode(q) },
        function(out, code)
            fact.searching = false
            if (text.wq or "") ~= q then return end         -- the field changed meanwhile
            found = {}
            if code == 0 and out then
                local ok, d = pcall(json.decode, out)
                if ok and type(d) == "table" and type(d.results) == "table" then
                    for _, r in ipairs(d.results) do
                        local sub = {}
                        if r.admin1 and r.admin1 ~= r.name then sub[#sub + 1] = r.admin1 end
                        if r.country then sub[#sub + 1] = r.country end
                        found[#found + 1] = { name = r.name, sub = table.concat(sub, ", "), lat = r.latitude, lon = r.longitude }
                    end
                end
            end
            paint_places()
        end)
end

on("text:wq", function(q)
    q = (q or ""):gsub("^%s+", ""):gsub("%s+$", "")
    fact.q_has = q ~= ""
    if search_timer then cancel(search_timer) search_timer = nil end
    if #q < 2 then
        found = {}
        paint_places()
        return
    end
    search_timer = after(450, function()
        search_timer = nil
        search(q)
    end)
end)

on("loc_change", function()
    fact.view = 1
    text.wq = ""
    found = {}
    paint_places()
    text.w_source = place and ("Now: " .. (place.city or "Here")) or ""
end)

on("loc_back", function()
    fact.view = 0
    panel.height(VIEW_FORECAST_H)
end)

on("loc_pick", function(i)
    local p = found[(tonumber(i) or -1) + 1]
    if p then
        save_place(p.lat, p.lon, p.name)
    end
end)

on("loc_ip", function()
    run("curl", { "-fsS", "--max-time", "6", "https://ipwho.is/?fields=success,latitude,longitude,city" }, function(body, code)
        local ok, d = pcall(json.decode, body or "")
        if code == 0 and ok and type(d) == "table" and d.success ~= false and d.latitude and d.longitude then
            save_place(d.latitude, d.longitude, d.city or "Here")
        else
            text.w_source = "Could not find your location from the IP address"
        end
    end)
end)

on("weather_reload", load)

-- refreshed when it opens (a stale panel is worse than none) and every 15 minutes
on("fact:open", function(v)
    if v == true or v == 1 then
        fact.view = 0
        panel.height(VIEW_FORECAST_H)
        load()
    end
end)
every(15 * 60 * 1000, load)
panel.height(VIEW_FORECAST_H)
load()

require("exclusive")("weather")
