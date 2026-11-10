-- Overlays: every panel and window that opens over the desktop, in ONE scene (overlays.plm), one logic. The shared core is
-- panelcore.luau: ONE `fact.open` / `fact.open_screen` / `fact.cur` (the open one's id), reports to the frame
-- (topbar.luau) the panels whose glass it draws, and gives each part `panel.height(h)`, `panel.keep()`, `opened(fn)`,
-- `shown()`, `closed(fn)`. Parts: weather, music, dashboard, updates · spotlight, clipboard, wallpapers, widget_bar,
-- session, polkit · switcher, overview, welcome (ids in the table below). The capture picker is NOT here: it is its own
-- scene (capture.plm), started on demand by start.sh, so its full-screen buffers are not held while idle.
local module = require("panelcore")({ dashboard = 3, music = 9, weather = 15, updates = 16, spotlight = 4, wallpapers = 5, clipboard = 6, widget_bar = 10, session = 11, polkit = 12, switcher = 21, overview = 22, welcome = 24 })

-- the capture picker is its own scene, started on demand (start.sh capture-ensure), then told what to do
local function capture_start(mode, kind)
    run("sh", { "-c", '"$(cat "$HOME/.config/beskar/shell-dir")/shell/start.sh" capture-ensure' }, function()
        pcall(sys.call, "say", "capture", "fact mode " .. mode)
        pcall(sys.call, "say", "capture", "fact kind " .. kind)
        pcall(sys.call, "say", "topbar", "emit open_panel 11")
    end)
end

-- the apps / thumbnails services are watched ONCE and handed to every part that asks (`watch(name, fn)`)
local watchers, last = {}, {}
local function shared_watch(kind, fn)
    if not watchers[kind] then
        watchers[kind] = {}
        sys.watch(kind, function(v)
            last[kind] = { v }
            for _, f in ipairs(watchers[kind]) do f(v) end
        end)
    end
    table.insert(watchers[kind], fn)
    if last[kind] then fn(last[kind][1]) end
end


module("weather", function(panel, opened, shown)
    -- Weather panel logic: Open-Meteo forecast for the place in ~/.config/beskar/location ("LAT LON City"), and the place
    -- picker (your IP address, or a search through Open-Meteo's geocoding). Choosing a place writes that file and tells the
    -- other scenes that show the weather (top bar, dashboard, widgets) to read it again.
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
        fact.wx_loading = true
        locate(function(p)
            place = p
            if not p then
                fact.wx_loading = false
                text.wx_city = "Unknown place"
                return
            end
            text.wx_city = p.city or "Here"
            local url = string.format(
                "https://api.open-meteo.com/v1/forecast?latitude=%s&longitude=%s"
                .. "&current=temperature_2m,relative_humidity_2m,apparent_temperature,weather_code,wind_speed_10m,surface_pressure,is_day"
                .. "&hourly=temperature_2m,weather_code,is_day"
                .. "&daily=weather_code,temperature_2m_max,temperature_2m_min,sunrise,sunset,uv_index_max"
                .. "&timezone=auto&forecast_days=6",
                p.lat, p.lon)
            run("curl", { "-fsS", "--max-time", "8", url }, function(out, code)
                fact.wx_loading = false
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
                fact.wx_lo = lo_all
                fact.wx_hi = hi_all
                fact.wx_loaded = true
            end)
        end)
    end

    -- ── choosing a place ────────────────────────────────────────────
    local function save_place(lat, lon, city)
        run("sh", { "-c", 'mkdir -p "$HOME/.config/beskar" && printf "%s %s %s\\n" "$1" "$2" "$3" > "$HOME/.config/beskar/location"',
            "x", tostring(lat), tostring(lon), city }, function()
            fact.wx_loaded = false
            fact.wx_view = 0
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
        fact.wx_searching = true
        run("curl", { "-fsS", "--max-time", "6",
            "https://geocoding-api.open-meteo.com/v1/search?count=5&language=en&format=json&name=" .. urlencode(q) },
            function(out, code)
                fact.wx_searching = false
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
        fact.wx_q_has = q ~= ""
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
        fact.wx_view = 1
        text.wq = ""
        found = {}
        paint_places()
        text.w_source = place and ("Now: " .. (place.city or "Here")) or ""
    end)

    on("loc_back", function()
        fact.wx_view = 0
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
    opened(function()
        fact.wx_view = 0
        panel.height(VIEW_FORECAST_H)
        load()
    end)
    every(15 * 60 * 1000, load)
    panel.height(VIEW_FORECAST_H)
    load()
end)

module("music", function(panel, opened, shown)
    -- Music panel logic: the `media` service (MPRIS) → the card. The frame draws the glass (panel.luau reports the height).
    panel.height(196)

    local playing, pos, len, rate = false, 0, 0, 1

    local function clock(sec)
        sec = math.max(0, math.floor(sec or 0))
        return string.format("%d:%02d", sec // 60, sec % 60)
    end

    local function paint_time()
        text.time_pos = clock(pos)
        text.time_len = clock(len)
        fact.track_pos = pos
    end

    sys.watch("media", function(m)
        m = m or {}
        local title = m.title or ""
        playing = m.playing == true
        pos, len, rate = m.position or 0, m.length or 0, m.rate or 1
        fact.has_player = (m.player or "") ~= "" or title ~= ""
        fact.is_playing = playing
        fact.track_len = len
        fact.has_art = (m.art or "") ~= ""
        text.track_title = title ~= "" and title or "Unknown title"
        text.track_artist = m.artist or ""
        text.cover_art = m.art or ""
        paint_time()
    end)

    -- The player reports the position once; carry it on between reports.
    every(1000, function()
        if playing and len > 0 then
            pos = math.min(pos + rate, len)
            paint_time()
        end
    end)

    on("play_pause", function() pcall(sys.call, "media.toggle") end)
    on("previous", function() pcall(sys.call, "media.previous") end)
    on("next", function() pcall(sys.call, "media.next") end)
    on("seek", function(frac)
        if len > 0 then
            pcall(sys.call, "media.seek", math.floor((tonumber(frac) or 0) * len))
        end
    end)
end)

module("dashboard", function(panel, opened, shown)
    -- Dashboard ("Today") logic: greeting, month calendar, weather (same place as the top bar), CPU / memory / disk,
    -- uptime and the battery's real state. The frame draws the glass (panel.luau reports the height).
    local locate = require("location")
    local codes = require("weathercodes")

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
        if shown() then
            update_stats()
            update_battery()
        end
    end)
    opened(function()
        fact.cal_shift = 0
        refresh_all()
    end)
    on("refresh_stats", refresh_all)

    -- ── weather (the same place as the top bar; a click opens the weather panel) ──
    local function refresh_weather()
        locate(function(place)
            if not place then return end
            text.dw_city = place.city
            local url = string.format(
                "https://api.open-meteo.com/v1/forecast?latitude=%s&longitude=%s&current=temperature_2m,apparent_temperature,weather_code,is_day"
                .. "&daily=temperature_2m_max,temperature_2m_min&timezone=auto&forecast_days=1", place.lat, place.lon)
            run("curl", { "-fsS", "--max-time", "6", url }, function(out, code)
                if code ~= 0 or not out then return end
                local ok, d = pcall(json.decode, out)
                local cur = ok and type(d) == "table" and d.current
                if type(cur) ~= "table" or cur.temperature_2m == nil then return end
                text.dw_temp = string.format("%d°C", math.floor(cur.temperature_2m + 0.5))
                text.dw_cond = codes.words(cur.weather_code)
                text.dw_icon = codes.icon(cur.weather_code, cur.is_day)
                text.dw_feels = string.format("Feels like %d°", math.floor((cur.apparent_temperature or cur.temperature_2m) + 0.5))
                local day = d.daily
                if type(day) == "table" and day.temperature_2m_max and day.temperature_2m_max[1] then
                    text.dw_range = string.format("H %d°   L %d°",
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
end)

module("updates", function(panel, opened, shown)
    -- Updates panel logic: `checkupdates` (official repos) → the list, and "Update all" = one terminal with the update (see below).
    -- Tells the top bar the count (the arrow only shows when > 0).

    local function sh(script, cb, ...)
        run("sh", { "-c", script, "x", ... }, cb, cb == nil and { output = false } or nil)
    end

    local function resize()
        local n = tonumber(fact.up_n) or 0
        panel.height(70 + math.min(math.max(n, 1), 8) * 34 + 24 + (n < 1 and 70 or 0) + 36 + 20)
    end

    local function tell_bar(n)
        pcall(sys.call, "say", "topbar", "fact upd_n " .. n)
    end

    local fresh = false          -- checked within the last 5 minutes
    local helper = nil            -- the AUR helper found on this machine: paru, else yay (nil: no AUR part)
    sh("command -v paru >/dev/null && echo paru || { command -v yay >/dev/null && echo yay; }", function(out)
        local h = (out or ""):match("%a+")
        if h == "paru" or h == "yay" then helper = h end
    end)

    local function parse(out, aur, rows)
        local n = 0
        for line in (out or ""):gmatch("[^\n]+") do
            local name, old, new = line:match("^(%S+)%s+(%S+)%s+%->%s+(%S+)")
            if name then
                n = n + 1
                if #rows < 60 then rows[#rows + 1] = { name = name, ver = old .. " → " .. new, aur = aur } end
            end
        end
        return n
    end

    local function check()
        if fact.up_checking then return end
        fact.up_checking = true
        fact.up_failed = false
        sh("timeout 60 checkupdates 2>/dev/null", function(out, code)
            local rows = {}
            local n = parse(out, false, rows)
            local official_ok = code == 0 or code == 2
            local function finish(aur_n)
                fact.up_checking = false
                if official_ok then
                    model.up_pkgs = rows
                    fact.up_n = n + aur_n
                    fact.up_known = true
                    tell_bar(n + aur_n)
                    fresh = true
                    after(300000, function() fresh = false end)
                    if not fact.up_running then
                        local t = n + aur_n
                        text.up_status = t == 0 and "Up to date" or (t .. (t == 1 and " update available" or " updates available")
                            .. (aur_n > 0 and (" · " .. aur_n .. " from the AUR") or ""))
                    end
                elseif not fact.up_running then
                    text.up_status = "Could not reach the package servers"
                end
                resize()
            end
            if helper and official_ok then
                sh("timeout 60 " .. helper .. " -Qua 2>/dev/null", function(aout)
                    finish(parse(aout, true, rows))
                end)
            else
                finish(0)
            end
        end)
    end

    -- Update all: ONE terminal with one `sudo` session for everything (like iNiR): the AUR helper's -Syu does the official
    -- packages and the AUR ones (paru, else yay); without a helper, sudo pacman -Syu. The list is checked again when the
    -- terminal closes. (A polkit popup cannot do this with one password: pkexec asks again for every command.)
    local TERMINAL = [[
    run_in() {
        case "$1" in
            wezterm) wezterm start -- sh -c "$2" ;;
            foot|kitty|alacritty|ghostty|konsole|xterm|gnome-terminal|xfce4-terminal) "$1" -e sh -c "$2" ;;
        esac
    }
    CMD="$1"
    for t in "$TERMINAL" kitty foot alacritty ghostty wezterm konsole gnome-terminal xfce4-terminal xterm; do
        [ -n "$t" ] && command -v "$t" >/dev/null 2>&1 && { run_in "$t" "$CMD"; exit $?; }
    done
    exit 127
    ]]

    local function update()
        if fact.up_running then return end
        local cmd = helper and (helper .. " -Syu") or "sudo pacman -Syu"
        cmd = cmd .. "; echo; read -r -p 'Done. Press Enter to close.' _"
        fact.up_running = true
        text.up_status = "Updating in the terminal…"
        spawn("sh", { "-c", TERMINAL, "x", cmd }, function() end, function(_, code)
            fact.up_running = false
            if code == 127 then
                fact.up_failed = true
                text.up_status = "No terminal found (kitty, foot, alacritty…)"
            else
                fact.up_checking = false
                fresh = false
                check()
            end
        end)
    end

    on("do_check", check)
    on("do_update", update)
    -- the list is kept between checks: opening the panel shows it at once and only looks again when it is old
    opened(function()
        if not fact.up_running and not fresh then check() end
    end)

    resize()
    after(3000, check)
    every(30 * 60 * 1000, check)
end)

module("spotlight", function(panel, opened, shown, closed)
    -- Spotlight logic. What you type decides what is listed (best first):
    --   · a sum            `12*(3+4)`, `sqrt(2)`, `2^10`        → the result; Enter copies it
    --   · a web prefix     `g cats`, `yt lofi`, `gh pleamar`, `w niri`, `ddg x`   → search there (xdg-open)
    --   · `>` commands     `> lock`, `> shut down`, `> record`  → run it
    --   · applications     by name
    --   · nothing found    → "Search the web for …"
    -- Every row is an entry { name, sub, kind, icon, run }; `model.hits` shows them, `launch(i)` runs the i-th.

    local apps = {}
    local entries = {}

    local MAX_ROWS = 24       -- results kept (the list shows 7 and scrolls)
    local SEEN_ROWS = 7

    -- ── a small calculator (no loadstring in the sandbox) ───────────────────────────
    local FUNCS = { sqrt = math.sqrt, abs = math.abs, round = function(x) return math.floor(x + 0.5) end,
        floor = math.floor, ceil = math.ceil, sin = math.sin, cos = math.cos, tan = math.tan,
        log = math.log, ln = math.log, exp = math.exp }
    local CONSTS = { pi = math.pi, e = math.exp(1) }

    local function calc(src)
        local pos = 1
        local function peek()
            pos = src:find("%S", pos) or (#src + 1)
            return src:sub(pos, pos)
        end
        local expr
        local function atom()
            local c = peek()
            if c == "(" then
                pos = pos + 1
                local v = expr()
                if peek() ~= ")" then error("(") end
                pos = pos + 1
                return v
            elseif c == "-" then
                pos = pos + 1
                return -atom()
            elseif c == "+" then
                pos = pos + 1
                return atom()
            elseif c:match("[%d%.]") then
                local s, e = src:find("^%d*%.?%d+", pos)
                if not s then s, e = src:find("^%d+", pos) end
                if not s then error("n") end
                pos = e + 1
                return tonumber(src:sub(s, e))
            elseif c:match("%a") then
                local s, e = src:find("^%a+", pos)
                local name = src:sub(s, e):lower()
                pos = e + 1
                if CONSTS[name] then return CONSTS[name] end
                local f = FUNCS[name]
                if not f or peek() ~= "(" then error("f") end
                pos = pos + 1
                local v = expr()
                if peek() ~= ")" then error("(") end
                pos = pos + 1
                return f(v)
            end
            error("x")
        end
        local function power()
            local b = atom()
            if peek() == "^" then
                pos = pos + 1
                return b ^ power()
            end
            return b
        end
        local function term()
            local v = power()
            while true do
                local c = peek()
                if c == "*" or c == "x" then pos = pos + 1; v = v * power()
                elseif c == "/" then pos = pos + 1; v = v / power()
                elseif c == "%" then pos = pos + 1; v = v % power()
                else return v end
            end
        end
        expr = function()
            local v = term()
            while true do
                local c = peek()
                if c == "+" then pos = pos + 1; v = v + term()
                elseif c == "-" then pos = pos + 1; v = v - term()
                else return v end
            end
        end
        local v = expr()
        if peek() ~= "" then error("tail") end
        return v
    end

    local function fmt_number(v)
        if v ~= v or v == math.huge or v == -math.huge then return nil end
        if math.abs(v) >= 1e15 or (v ~= 0 and math.abs(v) < 1e-9) then
            return string.format("%.10g", v)
        end
        local s = string.format("%.10f", v):gsub("0+$", ""):gsub("%.$", "")
        return s
    end

    local function try_calc(q)
        if #q < 2 or not q:find("%d") then return nil end
        if not (q:find("[%+%-%*/%^%%x]") or q:find("%a+%(")) then return nil end   -- a plain number is not a sum
        if not q:match("^[%d%.%s%+%-%*/%^%%%(%)%a]+$") then return nil end
        local ok, v = pcall(calc, q)
        if not ok or type(v) ~= "number" then return nil end
        return fmt_number(v)
    end

    -- ── web ──────────────────────────────────────────────────────────
    local SITES = {
        g = { "Google", "https://www.google.com/search?q=%s", 1 },
        ddg = { "DuckDuckGo", "https://duckduckgo.com/?q=%s", 5 },
        yt = { "YouTube", "https://www.youtube.com/results?search_query=%s", 2 },
        gh = { "GitHub", "https://github.com/search?q=%s", 3 },
        w = { "Wikipedia", "https://en.wikipedia.org/w/index.php?search=%s", 4 },
        maps = { "Maps", "https://www.google.com/maps/search/%s", 6 },
    }
    -- longer names for the same sites
    SITES.google = SITES.g
    SITES.youtube = SITES.yt
    SITES.github = SITES.gh
    SITES.wiki = SITES.w
    SITES.wikipedia = SITES.w
    SITES.duckduckgo = SITES.ddg

    local HOMES = {
        g = "https://www.google.com", ddg = "https://duckduckgo.com", yt = "https://www.youtube.com",
        gh = "https://github.com", w = "https://en.wikipedia.org", maps = "https://www.google.com/maps",
    }

    local function urlencode(s)
        return (s:gsub("[^%w%-%._~]", function(c) return string.format("%%%02X", c:byte()) end))
    end

    local function open_url(url)
        run("xdg-open", { url }, nil, { output = false })
    end

    local function web_entry(site_key, term)
        local site = SITES[site_key]
        return {
            name = "Search " .. site[1] .. " for “" .. term .. "”", sub = site[1], kind = 2, icon = "󰖟", site = site[3],
            run = function() open_url(string.format(site[2], urlencode(term))) end,
        }
    end

    -- ── commands ─────────────────────────────────────────────────────
    local function say(scene, words)
        pcall(sys.call, "say", scene, words)
    end

    local function parse_timer_spec(s)
        local raw = s:lower():gsub("%s+", "")
        if raw == "" then return nil end
        if raw:match("^%d+$") then
            local m = tonumber(raw)
            if m and m > 0 then
                return m * 60, string.format("%d min", m)
            end
        end
        local h, m = raw:match("^(%d+)h(%d+)m?$")
        if h and m then
            local nh, nm = tonumber(h), tonumber(m)
            if nh and nm then
                return nh * 3600 + nm * 60, string.format("%dh %dm", nh, nm)
            end
        end
        local only_h = raw:match("^(%d+)h$")
        if only_h then
            local nh = tonumber(only_h)
            if nh and nh > 0 then return nh * 3600, string.format("%d hour", nh) end
        end
        local only_m = raw:match("^(%d+)m$")
        if only_m then
            local nm = tonumber(only_m)
            if nm and nm > 0 then return nm * 60, string.format("%d min", nm) end
        end
        local only_s = raw:match("^(%d+)s$")
        if only_s then
            local ns = tonumber(only_s)
            if ns and ns > 0 then return ns, string.format("%d sec", ns) end
        end
        local hours = tonumber(raw:match("(%d+)h")) or 0
        local mins = tonumber(raw:match("(%d+)m")) or 0
        local secs = tonumber(raw:match("(%d+)s")) or 0
        if hours > 0 or mins > 0 or secs > 0 then
            local total = hours * 3600 + mins * 60 + secs
            local parts = {}
            if hours > 0 then parts[#parts + 1] = hours .. "h" end
            if mins > 0 then parts[#parts + 1] = mins .. "m" end
            if secs > 0 then parts[#parts + 1] = secs .. "s" end
            return total, table.concat(parts, " ")
        end
        return nil
    end

    local COMMANDS = {
        { "Timer 5 min", "timer 5", function() say("topbar", "emit timer_start 300") end },
        { "Timer 10 min", "timer 10", function() say("topbar", "emit timer_start 600") end },
        { "Timer 25 min", "timer 25", function() say("topbar", "emit timer_start 1500") end },
        { "Lock Screen", "lock", function() say("lock", "fact locked true") end },
        { "Sleep", "suspend", function() run("systemctl", { "suspend" }, nil, { output = false }) end },
        { "Log Out…", "logout", function() fact.ses_kind = 2; say("topbar", "emit open_panel 5") end },
        { "Restart…", "reboot", function() fact.ses_kind = 1; say("topbar", "emit open_panel 5") end },
        { "Shut Down…", "poweroff", function() fact.ses_kind = 0; say("topbar", "emit open_panel 5") end },
        { "Take Screenshot", "screenshot", function() capture_start(2, 0) end },
        { "Select Area Screenshot", "area", function() capture_start(0, 0) end },
        { "Record Screen", "record", function() capture_start(0, 1) end },
        { "Clipboard History", "clipboard", function() say("topbar", "emit open_panel 2") end },
        { "Wallpapers", "wallpapers", function() say("topbar", "emit open_panel 3") end },
        { "Edit Widgets", "widgets", function() say("widgets", "emit edit_toggle") end },
        { "Settings", "settings", function() say("topbar", "emit open_panel 4") end },
        { "Notifications", "notifications", function() say("topbar", "emit open_notifications") end },
        { "Control Center", "control", function() say("topbar", "emit open_control_center") end },
        { "Music", "music", function() say("topbar", "emit open_music") end },
        { "Window Overview", "overview", function() say("topbar", "emit open_panel 10") end },
    }

    -- ── the list ─────────────────────────────────────────────────────
    local function paint()
        local rows = {}
        for i, e in ipairs(entries) do
            if i > MAX_ROWS then break end
            rows[i] = { name = e.name, sub = e.sub or "", kind = e.kind, site = e.site or 0, glyph = e.kind ~= 0 and e.icon or "", icon = e.kind == 0 and e.icon or "" }
        end
        model.hits = rows
        fact.sp_sel = 0
        panel.height(94 + math.min(math.max(#rows, 1), SEEN_ROWS) * 44)
    end

    local function build()
        local raw = text.query or ""
        local q = raw:gsub("^%s+", ""):gsub("%s+$", "")
        local low = q:lower()
        entries = {}

        -- `>` commands
        if q:sub(1, 1) == ">" then
            local want = low:sub(2):gsub("^%s+", "")
            for _, c in ipairs(COMMANDS) do
                if want == "" or c[1]:lower():find(want, 1, true) or c[2]:find(want, 1, true) then
                    entries[#entries + 1] = { name = c[1], sub = "Command", kind = 3, icon = "󰆍", run = c[3] }
                end
            end
            return
        end

        -- a timer countdown: `timer 7`, `timer 1h30`, `timer 25m`
        local tspec = low:match("^timer%s*(.*)$")
        if tspec and tspec ~= "" then
            local sec, desc = parse_timer_spec(tspec)
            if sec and sec > 0 then
                entries[#entries + 1] = {
                    name = "Timer " .. desc,
                    sub = "Start countdown · Enter to start",
                    kind = 3,
                    icon = "󰔛",
                    run = function()
                        say("topbar", "emit timer_start " .. sec)
                    end,
                }
            end
        end

        -- a sum
        local result = try_calc(q)
        if result then
            entries[#entries + 1] = {
                name = "= " .. result, sub = q .. "  ·  Enter copies", kind = 1, icon = "󰃬",
                run = function()
                    run("wl-copy", { result }, nil, { output = false })
                end,
            }
        end

        -- a web prefix: `yt lofi` searches there; the prefix alone (`yt`) offers to open the site
        local key = low:match("^(%a+)%s+.+$")
        if key and SITES[key] then
            entries[#entries + 1] = web_entry(key, q:match("^%a+%s+(.+)$"))
        end
        local bare = low:match("^(%a+)$")
        if bare and SITES[bare] then
            local site = SITES[bare]
            local home = HOMES[bare] or HOMES[(bare == "google" and "g") or (bare == "youtube" and "yt") or (bare == "github" and "gh") or (bare == "wiki" and "w") or (bare == "wikipedia" and "w") or (bare == "duckduckgo" and "ddg") or "g"]
            entries[#entries + 1] = {
                name = "Search " .. site[1], sub = "type what to look for, e.g. “" .. bare .. " cats”", kind = 2, icon = "󰖟", site = site[3],
                run = function() open_url(home) end,
            }
        end

        -- applications
        local n_apps = 0
        for _, a in ipairs(apps) do
            if #entries < MAX_ROWS and (low == "" or a.name:lower():find(low, 1, true)) then
                entries[#entries + 1] = {
                    name = a.name, kind = 0, icon = a.icon,
                    run = function()
                        log("Spotlight: launching", a.name, "→", a.exec)
                        sys.call("apps.launch", a.exec)
                    end,
                }
                n_apps = n_apps + 1
            end
        end

        -- commands, if the text names one ("lock", "record"), without the `>`
        if low ~= "" and #low >= 3 then
            for _, c in ipairs(COMMANDS) do
                if #entries < MAX_ROWS and (c[1]:lower():find(low, 1, true) or c[2]:find(low, 1, true)) then
                    entries[#entries + 1] = { name = c[1], sub = "Command", kind = 3, icon = "󰆍", run = c[3] }
                end
            end
        end

        -- nothing at all: the web
        if #entries == 0 and low ~= "" then
            entries[1] = web_entry("g", q)
        end
    end

    local function filter()
        build()
        paint()
    end

    -- Watch the system apps database (.desktop files on Linux)
    if not sys.watch("apps", function(list) apps = list or {}; filter() end) then
        entries = { { name = "Loading applications...", kind = 0, icon = "", run = function() end } }
        paint()
    end

    on("text:query", filter)

    on("launch", function(i)
        local e = entries[(tonumber(i) or 0) + 1]
        fact.open = false
        if e and e.run then
            after(150, e.run)
        end
    end)

    -- Reset query when closed
    closed(function()
        text.query = ""
        filter()
    end)
end)

module("clipboard", function(panel, opened, shown, closed)
    -- Clipboard history logic (cliphist + wl-copy). Everything goes through `run` (the sandbox has no io / os), and the
    -- frame draws the glass: this tells it how tall the list is.
    --
    --   history  `cliphist list`: up to 100 entries, stored by cliphist across restarts (start.sh keeps the watcher
    --            `wl-paste --watch cliphist -max-items 100 store` running)
    --   pins     text you pinned: stored by us (files.write) and never removed: not by Clear All, not by the 100 limit
    --   shown    pinned entries first, then the recent ones, filtered by the search; 8 rows at a time (wheel / arrows)


    local MAX_SHOWN = 8
    local MAX_HISTORY = 100

    local history = {}      -- { raw = the line cliphist printed, preview = text }
    local pins = {}         -- { text = full text }
    local view = {}         -- what the list can show now: { kind = "pin"|"hist", idx = n, preview = text }
    local off = 0           -- first row on screen (0-based)
    local CACHE = nil       -- ~/.cache/beskar/clipboard, where image thumbnails live
    local thumb_state = {}  -- cliphist id -> "making" | "ready"

    -- ── pins, on disk ────────────────────────────────────────────────
    do
        local ok, loaded = pcall(sys.ask, "files.read", "pins.json", "json")
        if ok and type(loaded) == "table" and type(loaded.items) == "table" then
            pins = loaded.items
        end
    end

    local saving = false
    local function save_pins()
        if saving then
            return
        end
        saving = true
        after(500, function()
            saving = false
            pcall(sys.call, "files.write", "pins.json", { items = pins })
        end)
    end

    -- ── what is shown ────────────────────────────────────────────────
    local function flat(s)
        return ((s or ""):gsub("[\r\n\t]+", " "):gsub("%s+", " "))
    end

    -- cliphist lists an image as "[[ binary data 40 KiB png 468x111 ]]": turn that into a readable label, and keep
    -- the id so a thumbnail can be made.
    local function image_label(preview)
        local size, fmt, w, h = preview:match("^%[%[ binary data (%S+ %S+) (%a+) (%d+)x(%d+) %]%]")
        if size then
            return string.format("Image · %s × %s · %s", w, h, size), fmt
        end
    end

    local function thumb_path(id)
        return CACHE and (CACHE .. "/" .. id .. ".png") or ""
    end

    local repaint

    local function make_thumb(id)
        if not CACHE or thumb_state[id] then
            return
        end
        thumb_state[id] = "making"
        local script = 'mkdir -p "$1" && { [ -f "$2" ] || cliphist decode "$3" | magick - -thumbnail 112x68 "$2"; }'
        run("sh", { "-c", script, "x", CACHE, thumb_path(id), tostring(id) }, function(_, code)
            if code == 0 then
                thumb_state[id] = "ready"
                repaint()
            else
                thumb_state[id] = nil
            end
        end)
    end

    local function rebuild(keep_off)
        local q = (text.clip_q or ""):lower()
        view = {}
        local pinned_text = {}
        for i, p in ipairs(pins) do
            pinned_text[p.text] = true
            local pv = flat(p.text)
            if q == "" or pv:lower():find(q, 1, true) then
                view[#view + 1] = { kind = "pin", idx = i, preview = pv }
            end
        end
        for i, h in ipairs(history) do
            if not pinned_text[h.preview] and (q == "" or h.preview:lower():find(q, 1, true)) then
                view[#view + 1] = { kind = "hist", idx = i, preview = flat(h.preview), image = h.image, id = h.id }
            end
        end
        if not keep_off then
            off = 0
        end
        off = math.max(0, math.min(off, math.max(0, #view - MAX_SHOWN)))
        local rows = {}
        for k = off + 1, math.min(#view, off + MAX_SHOWN) do
            local v = view[k]
            local is_img = v.image == true
            if is_img then
                make_thumb(v.id)
            end
            rows[#rows + 1] = {
                src = k - 1,
                preview = v.preview,
                pinned = v.kind == "pin",
                pinnable = v.kind == "pin" or not is_img,
                is_img = is_img,
                ready = is_img and thumb_state[v.id] == "ready",
                thumb = is_img and thumb_path(v.id) or "",
            }
        end
        model.clips = rows
        local n = #view
        text.clip_count = (q ~= "" and (n .. " found")) or (#history .. " saved" .. (#pins > 0 and (" · " .. #pins .. " pinned") or ""))
        text.clip_empty = (q ~= "") and "Nothing matches" or "Nothing copied yet"
        if #rows > 0 and (fact.clip_sel >= #rows or fact.clip_sel < 0) then
            fact.clip_sel = 0
        end
        panel.height(58 + (#rows == 0 and 130 or #rows * 46) + 84)   -- an empty list still has room for its message
    end

    repaint = function()
        rebuild(true)
    end

    local function refresh_history()
        run("sh", { "-c", "cliphist list 2>/dev/null | head -n " .. MAX_HISTORY }, function(out)
            local items = {}
            for line in (out or ""):gmatch("[^\n]+") do
                local id_s, preview = line:match("^(%d+)%s+(.*)$")
                if id_s and preview then
                    local label = image_label(preview)
                    items[#items + 1] = { raw = line, id = tonumber(id_s), preview = label or preview, image = label ~= nil }
                end
            end
            history = items
            rebuild(true)
        end)
    end

    opened(function()
        text.clip_q = ""
        refresh_history()
        rebuild(false)
    end)

    on("text:clip_q", function()
        rebuild(false)
    end)

    -- ── buttons ──────────────────────────────────────────────────────
    local function entry_at(src)
        return view[off + (tonumber(src) or 0) + 1]
    end

    on("copy_clip", function(i)
        local v = entry_at(i)
        fact.open = false
        if not v then
            return
        end
        if v.kind == "pin" then
            -- a pinned entry is the text itself
            run("sh", { "-c", 'printf "%s" "$1" | wl-copy', "x", pins[v.idx].text }, nil, { output = false })
        else
            -- a history entry goes back through cliphist (it knows the id) into the clipboard
            run("sh", { "-c", 'printf "%s" "$1" | cliphist decode | wl-copy', "x", history[v.idx].raw }, nil, { output = false })
        end
        run("notify-send", { "-a", "Clipboard", "-i", "edit-paste", "Copied", "Ready to paste" }, nil, { output = false })
    end)

    on("pin_clip", function(i)
        local v = entry_at(i)
        if not v then
            return
        end
        if v.kind == "pin" then
            table.remove(pins, v.idx)
            save_pins()
            rebuild(true)
        else
            -- the full text, decoded, is what is kept (the list only has a one-line preview)
            run("sh", { "-c", 'printf "%s" "$1" | cliphist decode', "x", history[v.idx].raw }, function(out)
                if out and out ~= "" then
                    table.insert(pins, 1, { text = out })
                    save_pins()
                    rebuild(true)
                end
            end)
        end
    end)

    on("clip_scroll", function(wheel)
        local step = (tonumber(wheel) or 0) > 0 and -1 or 1
        off = math.max(0, math.min(math.max(0, #view - MAX_SHOWN), off + step))
        rebuild(true)
    end)

    -- Keep the cursor in view when the arrows run past the ends of the 8 shown rows.
    on("fact:clip_sel", function()
        -- (the rows are the window; moving past it is handled by the wheel)
    end)

    on("clear_all", function()
        -- the history goes; pinned entries stay
        run("cliphist", { "wipe" }, nil, { output = false })
        history = {}
        rebuild(false)
        run("notify-send", { "-a", "Clipboard", "Clipboard cleared", "Pinned entries were kept" }, nil, { output = false })
    end)

    run("sh", { "-c", 'printf %s "$HOME"' }, function(out)
        if out and out ~= "" then
            CACHE = out .. "/.cache/beskar/clipboard"
            rebuild(true)
        end
    end)
    refresh_history()
end)

module("wallpapers", function(panel, opened, shown, closed)
    -- Wallpaper picker logic. Like Marea's: the folders are scanned, small copies are made once and cached,
    -- and the picture is painted by the wallpaper scene (wallpaper.plm), with a transition.
    --
    --   Mine      ~/Pictures/wallpapers, ~/Pictures/Wallpapers, ~/Wallpapers (never the rest of ~/Pictures, and never
    --             files named screenshot / mock)
    --   Built-in  the ones Beskar ships (copied to ~/.local/share/beskar/wallpapers by start.sh), /usr/share/wallpapers,
    --             /usr/share/backgrounds
    --
    -- The choice is remembered in ~/.config/beskar/wallpaper, which start.sh puts back at login.

    local PAGE = 5                  -- pictures on screen, in one row
    panel.height(250)               -- the strip's height, for the frame's glass

    local all = {}              -- { path, name, builtin }, in the order shown by "All"
    local view = {}             -- what the current tab shows
    local row = 0               -- the first picture on screen (0-based)
    local cur = 0               -- the picture the keyboard cursor is on (0-based, in `view`)
    local current = nil         -- path on now
    local HOME = ""
    local CACHE = ""
    local thumb_of = {}         -- path -> thumbnail path
    local state = {}            -- path -> "making" | "ready"

    -- ── names and paths ──────────────────────────────────────────────
    local function pretty(path)
        local name = path:match("([^/]+)$") or path
        name = name:gsub("%.[%w]+$", ""):gsub("[_%-]+", " ")
        if #name > 40 then
            name = name:sub(1, 38) .. "…"
        end
        return name
    end

    local function hash(str)
        local h = 5381
        for i = 1, #str do
            h = (h * 33 + str:byte(i)) % 4294967296
        end
        return string.format("%08x", h)
    end

    -- ── painting ─────────────────────────────────────────────────────
    local paint

    local function make_thumb(path)
        if state[path] then
            return
        end
        state[path] = "making"
        local thumb = thumb_of[path]
        local script = 'mkdir -p "$1" && { [ -f "$2" ] || magick -define jpeg:size=704x396 "$3" -thumbnail 352x198^ -gravity center -extent 352x198 -quality 80 "$2"; }'
        run("sh", { "-c", script, "x", CACHE, thumb, path }, function(_, code)
            if code == 0 then
                state[path] = "ready"
                paint()
            else
                state[path] = nil
            end
        end)
    end

    paint = function()
        local first = row + 1
        local rows = {}
        for i = first, math.min(#view, first + PAGE - 1) do
            local w = view[i]
            thumb_of[w.path] = thumb_of[w.path] or (CACHE .. "/" .. hash(w.path) .. ".jpg")
            make_thumb(w.path)
            rows[#rows + 1] = {
                name = w.name,
                thumb = thumb_of[w.path],
                ready = state[w.path] == "ready",
                current = w.path == current,
                builtin = w.builtin,
                sel = (first + #rows) == cur + 1,
            }
        end
        model.walls = rows
        fact.wall_total = #view
        fact.wall_row = row
        fact.wall_rows = math.max(1, #view - PAGE + 1)
        text.wall_hint = string.format("%d pictures", #view)
    end

    local function rebuild(tab)
        view = {}
        for _, w in ipairs(all) do
            if tab == 0 or (tab == 1 and not w.builtin) or (tab == 2 and w.builtin) then
                view[#view + 1] = w
            end
        end
        row = 0
        cur = 0
        paint()
    end

    local function show_current_row()
        for i, w in ipairs(view) do
            if w.path == current then
                row = math.max(0, math.min(i - 3, #view - PAGE))      -- the one in use, about the middle
                cur = i - 1
                return
            end
        end
    end

    -- ── what is on now ───────────────────────────────────────────────
    local function read_current(then_)
        run("sh", { "-c", 'cat "$HOME/.config/beskar/wallpaper" 2>/dev/null | head -1' }, function(out)
            local p = (out or ""):gsub("%s+$", "")
            if p ~= "" then
                current = p
            end
            if then_ then
                then_()
            end
        end)
    end

    -- ── scanning ─────────────────────────────────────────────────────
    local SCAN = [[
    H="$HOME"
    img() { fd -t f -e jpg -e jpeg -e png -e webp -S +120k -E "*[Ss]creenshot*" -E "*[Ss]creen_[Ss]hot*" -E "*mock*" "$@" 2>/dev/null; }
    for d in "$H/Pictures/wallpapers" "$H/Pictures/Wallpapers" "$H/Wallpapers" "$H/Imágenes/Wallpapers"; do
        [ -d "$d" ] && img --max-depth 3 . "$d" | sed 's/^/1|/'
    done
    [ -d "$H/.local/share/beskar/wallpapers" ] && img --max-depth 2 . "$H/.local/share/beskar/wallpapers" | sed 's/^/2|/'
    for d in /usr/share/wallpapers /usr/share/backgrounds; do
        [ -d "$d" ] && img --max-depth 3 . "$d" | sed 's/^/3|/'
    done
    printf 'HOME|%s\n' "$H"
    ]]

    local scanning = false
    local function scan()
        if scanning then
            return
        end
        scanning = true
        run("sh", { "-c", SCAN }, function(out, code)
            scanning = false
            if code ~= 0 or not out then
                return
            end
            local mine, built, system, seen = {}, {}, {}, {}
            for line in out:gmatch("[^\n]+") do
                local kind, path = line:match("^(%w+)|(.+)$")
                if kind == "HOME" then
                    HOME = path
                    CACHE = HOME .. "/.cache/beskar/wallpapers"
                elseif path and not seen[path] then
                    seen[path] = true
                    local entry = { path = path, name = pretty(path), builtin = kind ~= "1" }
                    if kind == "2" then
                        built[#built + 1] = entry
                    elseif kind == "3" then
                        system[#system + 1] = entry
                    else
                        mine[#mine + 1] = entry
                    end
                end
            end
            local function by_name(a, b) return a.name:lower() < b.name:lower() end
            table.sort(mine, by_name)
            table.sort(built, by_name)
            table.sort(system, by_name)
            all = {}
            for _, e in ipairs(mine) do all[#all + 1] = e end
            for _, e in ipairs(built) do all[#all + 1] = e end      -- Beskar's own first
            for _, e in ipairs(system) do all[#all + 1] = e end     -- then the system's
            read_current(function()
                rebuild(tonumber(fact.wall_tab) or 0)
                show_current_row()
                paint()
            end)
        end)
    end

    -- ── the accent that goes with a picture ─────────────────────────
    -- Take the most colourful of the picture's main colours and map its hue to the nearest of Beskar's
    -- accents (0 blue · 1 purple · 2 pink · 3 red · 4 orange · 5 green · 6 graphite for greys).
    local function accent_index(r, g, b)
        r, g, b = r / 255, g / 255, b / 255
        local mx, mn = math.max(r, g, b), math.min(r, g, b)
        local d = mx - mn
        local s = mx == 0 and 0 or d / mx
        if s < 0.18 or d == 0 then
            return 6, s, mx
        end
        local h
        if mx == r then h = ((g - b) / d) % 6 elseif mx == g then h = (b - r) / d + 2 else h = (r - g) / d + 4 end
        h = h * 60
        local idx
        if h < 15 or h >= 345 then idx = 3
        elseif h < 70 then idx = 4
        elseif h < 170 then idx = 5
        elseif h < 255 then idx = 0
        elseif h < 300 then idx = 1
        else idx = 2 end
        return idx, s, mx
    end

    -- The palette engine lives in settings.luau (matugen on the wallpaper, sent to every scene).
    local function accent_from(path)
        pcall(sys.call, "say", "settings", "text pal_src " .. path)
    end

    on("accent_now", function()
        if current then
            accent_from(current)
        end
    end)

    -- ── buttons ──────────────────────────────────────────────────────
    on("wall_tab_set", function(n)
        fact.wall_tab = tonumber(n) or 0
        rebuild(fact.wall_tab)
    end)

    on("wall_scroll", function(wheel)
        local max_off = math.max(0, #view - PAGE)
        local step = (tonumber(wheel) or 0) > 0 and -1 or 1
        local nxt = math.max(0, math.min(max_off, row + step))
        if nxt ~= row then
            row = nxt
            paint()
        end
    end)

    local function apply(w)
        if not w then
            return
        end
        current = w.path
        paint()
        -- Remember it (start.sh and the lock screen read this file) and let the wallpaper scene reveal it.
        run("sh", { "-c", 'mkdir -p "$HOME/.config/beskar" && printf "%s\\n" "$1" > "$HOME/.config/beskar/wallpaper"', "x", w.path }, nil, { output = false })
        pcall(sys.call, "say", "wallpaper", "text wp_new " .. w.path)
        if fact.accent_auto == true then
            accent_from(w.path)
        end
    end

    on("wall_pick", function(i)
        local idx = row + (tonumber(i) or 0)
        cur = idx
        apply(view[idx + 1])
    end)

    -- Arrows (on screen or on the keyboard). Left / Right move the cursor one picture and scroll to keep it in view;
    -- the arrow buttons turn a whole page; Enter applies the picture under the cursor.
    local function keep_in_view()
        local max_off = math.max(0, #view - PAGE)
        if cur < row then
            row = cur
        elseif cur >= row + PAGE then
            row = cur - PAGE + 1
        end
        row = math.max(0, math.min(max_off, row))
    end

    on("wall_move", function(d)
        if #view < 1 then
            return
        end
        cur = math.max(0, math.min(#view - 1, cur + (tonumber(d) or 0)))
        keep_in_view()
        paint()
    end)

    on("wall_page", function(d)
        if #view < 1 then
            return
        end
        local max_off = math.max(0, #view - PAGE)
        row = math.max(0, math.min(max_off, row + (tonumber(d) or 0) * PAGE))
        cur = math.max(row, math.min(row + PAGE - 1, cur + (tonumber(d) or 0) * PAGE))
        cur = math.max(0, math.min(#view - 1, cur))
        paint()
    end)

    on("wall_enter", function()
        apply(view[cur + 1])
    end)

    -- Opening the picker looks again (a new picture in the folder shows up) and lands on the one in use.
    opened(scan)

    scan()
end)

module("widget_bar", function(panel, opened, shown, closed)
    -- The widget bar's logic: it only forwards its buttons to the widgets scene (which owns every decision) and keeps
    -- edit mode and the bar in step (closing the bar by Esc ends edit mode).
    panel.height(132)

    local function widgets(words)
        pcall(sys.call, "say", "widgets", words)
    end

    on("wb_add", function(code) widgets("emit w_add " .. math.floor(tonumber(code) or 0)) end)
    on("wb_preset", function(n) widgets("emit w_preset " .. math.floor(tonumber(n) or 0)) end)
    on("wb_undo", function() widgets("emit w_undo") end)
    on("wb_tidy", function() widgets("emit w_tidy") end)
    on("wb_grid", function() widgets("emit w_grid") end)
    on("wb_done", function() widgets("emit edit_done") end)

    opened(function() widgets("emit w_bar_open") end)
    closed(function() widgets("emit edit_done") end)
    panel.keep()                 -- a click outside does not close it: you work on the desktop with it


    local DATA = require("widgets_data")
    local kinds, presets = {}, {}
    for _, k in ipairs(DATA.KINDS) do kinds[#kinds + 1] = { id = k.id, name = k.name, icon = k.icon } end
    for i, p in ipairs(DATA.PRESETS) do presets[#presets + 1] = { id = i, name = p.name } end
    model.kinds = kinds
    model.presets = presets
end)

module("session", function(panel, opened, shown, closed)
    -- Session dialog logic: shut down, restart, log out (with a 60 s countdown). Enter presses the highlighted button
    -- (the action by default); the dialog grows out of the dock like Spotlight.
    panel.height(250)
    local timer_id = nil

    local function clear_timer()
        if timer_id then
            cancel(timer_id)
            timer_id = nil
        end
    end

    on("confirm_action", function()
        clear_timer()
        fact.open = false
        local k = fact.ses_kind or 0
        if k == 0 then
            log("Session: Powering off system...")
            run("systemctl", { "poweroff" }, function(_, code)
                if code ~= 0 then log("Session: poweroff failed with code", code) end
            end)
        elseif k == 1 then
            log("Session: Restarting system...")
            run("systemctl", { "reboot" }, function(_, code)
                if code ~= 0 then log("Session: reboot failed with code", code) end
            end)
        else
            log("Session: Logging out...")
            run("niri", { "msg", "action", "quit", "--skip-confirmation" })
        end
    end)

    -- Countdown loop: runs while this dialog is the one shown
    opened(function()
        fact.ses_sel = 1          -- Enter presses the action by default
        fact.countdown = 60
        clear_timer()
        local function tick()
            if not shown() then return end
            if fact.countdown > 1 then
                fact.countdown = fact.countdown - 1
                timer_id = after(1000, tick)
            else
                emit("confirm_action")
            end
        end
        timer_id = after(1000, tick)
    end)
    closed(clear_timer)

    on("ses_enter", function()
        if not shown() then return end
        if (tonumber(fact.ses_sel) or 1) == 1 then
            emit("confirm_action")
        else
            fact.open = false
        end
    end)
    on("dismiss", function() if shown() then fact.open = false end end)
end)

module("polkit", function(panel, opened, shown, closed)
    -- The authentication agent. Watching the `polkit` service makes this process the session's agent (one per session).
    -- Requests come one at a time: `pending` (a program waits; polkit's message and whose password it takes), then
    -- `asking` (an answer is awaited; the prompt, secret or not), `error = "wrong"` after a bad one (three tries at most).
    panel.height(310)
    panel.keep()                 -- a click outside does not close it: it has to be answered or cancelled
    local pending = false

    local function open_on_focused_monitor()
        -- the frame knows which monitor has the focus (FOCUS_PANELS in topbar.luau toggles us there)
        pcall(sys.call, "say", "topbar", "emit open_panel 8")
    end

    sys.watch("polkit", function(p)
        p = p or {}
        local was_wrong = fact.pk_wrong == true
        text.pk_message = p.message or ""
        local prompt = p.prompt or ""
        prompt = prompt:gsub(":%s*$", "")
        text.pk_prompt = (prompt ~= "" and prompt) or ("Password for " .. (p.user or "administrator"))
        text.pk_info = p.info or ""
        fact.pk_secret = p.secret ~= false
        fact.pk_asking = p.asking == true
        fact.pk_wrong = p.error == "wrong"

        if p.pending == true then
            if not pending then
                pending = true
                text.password = ""
                if not shown() then open_on_focused_monitor() end
            end
        elseif pending then
            pending = false
            text.password = ""
            if shown() then fact.open = false end
        end

        if fact.pk_wrong and not was_wrong then
            text.password = ""
            emit("pk_shake")
        end
    end)

    on("pk_answer", function()
        if not shown() or fact.pk_asking ~= true then return end
        local pwd = text.password or ""
        text.password = ""
        pcall(sys.call, "polkit.answer", pwd)
    end)

    on("pk_cancel", function()
        if not shown() then return end
        text.password = ""
        pcall(sys.call, "polkit.cancel")
        fact.open = false
        pending = false
    end)

    -- closed by anything else (another panel took over): the program must be told it was dismissed
    closed(function()
        if pending then
            pending = false
            text.password = ""
            pcall(sys.call, "polkit.cancel")
        end
    end)
end)

module("switcher", function(panel, opened, shown, closed)
    local watch = shared_watch
    -- App switcher logic: windows from `niri msg -j windows` (most recently used first),
    -- previews from pleamar `thumbnails` service, icons from `apps` service.
    -- Opened by Super+Tab (start.sh appswitcher -> topbar picks monitor with focus).
    -- Tab / arrows move selection, Enter or click focuses window, Esc closes.

    local window_list = {}
    local by_key = {}
    local thumbnails_list = {}
    local thumbnails_by_id = {}

    local function lower(s)
        return string.lower(s or "")
    end

    watch("apps", function(list)
        by_key = {}
        for _, e in ipairs(list or {}) do
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
    end)

    local function icon_for(app_id)
        local k = lower(app_id)
        local e = by_key[k] or by_key[k:match("([^%.]+)$") or k]
        return (e and e.icon) or k
    end

    local function show_title(idx)
        local w = window_list[(tonumber(idx) or tonumber(fact.sw_sel) or 0) + 1]
        text.sel_title = w and w.title or ""
    end
    on("fact:sw_sel", function(v) show_title(v) end)

    local function focus_secs(w)
        local t = w.focus_timestamp
        if type(t) == "table" then
            return (t.secs or 0) + (t.nanos or 0) / 1e9
        end
        return 0
    end

    local function match_thumbnail(w, used_ids)
        -- 1. Try matching by string ID first (in niri, toplevel identifier is the window ID)
        local sid = tostring(w.id)
        if thumbnails_by_id[sid] and not used_ids[sid] then
            used_ids[sid] = true
            return thumbnails_by_id[sid]
        end
        -- 2. Match by title and app
        local w_title = w.title or ""
        local w_app = lower(w.app_id or "")
        for _, t in ipairs(thumbnails_list) do
            if not used_ids[t.id] then
                if lower(t.app or "") == w_app and (t.title or "") == w_title then
                    used_ids[t.id] = true
                    return t
                end
            end
        end
        -- 3. Match by app only
        for _, t in ipairs(thumbnails_list) do
            if not used_ids[t.id] then
                if lower(t.app or "") == w_app then
                    used_ids[t.id] = true
                    return t
                end
            end
        end
        return nil
    end

    local function request_visible_thumbnails()
        local want_ids = {}
        for _, w in ipairs(window_list) do
            if w.thumb_id and w.thumb_id ~= "" then
                table.insert(want_ids, w.thumb_id)
            end
        end
        if #want_ids > 0 then
            pcall(sys.call, "thumbnails.want", want_ids)
        end
    end

    local function update_window_thumbs()
        if #window_list == 0 then return end
        local used_ids = {}
        local changed = false
        for _, w in ipairs(window_list) do
            local t = match_thumbnail(w, used_ids)
            local pic = (t and t.picture) or ""
            local thumb_id = (t and t.id) or tostring(w.id)
            local has = (pic ~= "")
            if w.thumb ~= pic or w.has_thumb ~= has or w.thumb_id ~= thumb_id then
                w.thumb = pic
                w.has_thumb = has
                w.thumb_id = thumb_id
                changed = true
            end
        end
        if changed then
            model.sw_wins = window_list
            request_visible_thumbnails()
        end
    end

    watch("thumbnails", function(info)
        thumbnails_list = (info and info.list) or {}
        thumbnails_by_id = {}
        for _, t in ipairs(thumbnails_list) do
            if t.id and t.id ~= "" then
                thumbnails_by_id[t.id] = t
            end
        end
        if shown() then
            update_window_thumbs()
        end
    end)

    local function refresh_windows()
        run("niri", { "msg", "-j", "windows" }, function(out)
            local ok, all = pcall(json.decode, out or "")
            if not ok or type(all) ~= "table" then
                return
            end
            local wins = {}
            for _, w in ipairs(all) do
                local app = w.app_id or ""
                if app ~= "" and app ~= "pleamar" then
                    wins[#wins + 1] = {
                        id = w.id,
                        title = w.title or "",
                        app_id = app,
                        icon = icon_for(app),
                        t = focus_secs(w),
                        thumb = "",
                        has_thumb = false,
                        thumb_id = tostring(w.id),
                    }
                end
            end
            table.sort(wins, function(a, b) return a.t > b.t end) -- most recent first
            while #wins > 7 do
                table.remove(wins)
            end

            local used_ids = {}
            for _, w in ipairs(wins) do
                local t = match_thumbnail(w, used_ids)
                if t then
                    w.thumb_id = t.id
                    w.thumb = t.picture or ""
                    w.has_thumb = (w.thumb ~= "")
                end
            end

            window_list = wins
            model.sw_wins = wins
            request_visible_thumbnails()

            -- the first press goes to the previous window (current one is first)
            local first = (#wins > 1) and 1 or 0
            fact.sw_sel = first
            show_title(first)
        end)
    end

    opened(refresh_windows)
    closed(function() pcall(sys.call, "thumbnails.want") end)      -- stop asking when closed

    on("next_app", function()
        local count = #window_list
        if count > 0 then
            fact.sw_sel = (fact.sw_sel + 1) % count
        end
    end)

    on("prev_app", function()
        local count = #window_list
        if count > 0 then
            fact.sw_sel = (fact.sw_sel - 1 + count) % count
        end
    end)

    on("sw_switch_to", function(idx)
        fact.open = false
        pcall(sys.call, "thumbnails.want")
        local i = tonumber(idx) or fact.sw_sel or 0
        local target = window_list[i + 1]
        if target and target.id then
            run("niri", { "msg", "action", "focus-window", "--id", tostring(target.id) }, nil, { output = false })
        end
    end)
end)

module("overview", function(panel, opened, shown, closed)
    local watch = shared_watch
    -- macOS Window Overview (Mission Control HUD) logic
    -- Lists all windows of ALL workspaces as large previews using pleamar `thumbnails` service.
    -- Opened via start.sh overview -> topbar opens panel 10 on the monitor with focus.
    -- Click or Return focuses the selected window, Esc closes, arrow keys navigate the grid.


    local window_list = {}
    local by_key = {}
    local thumbnails_list = {}
    local thumbnails_by_id = {}

    local function lower(s)
        return string.lower(s or "")
    end

    watch("apps", function(list)
        by_key = {}
        for _, e in ipairs(list or {}) do
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
    end)

    local function icon_for(app_id)
        local k = lower(app_id)
        local e = by_key[k] or by_key[k:match("([^%.]+)$") or k]
        return (e and e.icon) or k
    end

    local function focus_secs(w)
        local t = w.focus_timestamp
        if type(t) == "table" then
            return (t.secs or 0) + (t.nanos or 0) / 1e9
        end
        return 0
    end

    local function match_thumbnail(w, used_ids)
        local sid = tostring(w.id)
        if thumbnails_by_id[sid] and not used_ids[sid] then
            used_ids[sid] = true
            return thumbnails_by_id[sid]
        end
        local w_title = w.title or ""
        local w_app = lower(w.app_id or "")
        for _, t in ipairs(thumbnails_list) do
            if not used_ids[t.id] then
                if lower(t.app or "") == w_app and (t.title or "") == w_title then
                    used_ids[t.id] = true
                    return t
                end
            end
        end
        for _, t in ipairs(thumbnails_list) do
            if not used_ids[t.id] then
                if lower(t.app or "") == w_app then
                    used_ids[t.id] = true
                    return t
                end
            end
        end
        return nil
    end

    local function request_live_thumbnails()
        local live_ids = {}
        for _, w in ipairs(window_list) do
            if w.thumb_id and w.thumb_id ~= "" then
                table.insert(live_ids, w.thumb_id)
            end
        end
        if #live_ids > 0 then
            pcall(sys.call, "thumbnails.live", live_ids)
        end
    end

    local function update_window_thumbs()
        if #window_list == 0 then return end
        local used_ids = {}
        local changed = false
        for _, w in ipairs(window_list) do
            local t = match_thumbnail(w, used_ids)
            local pic = (t and t.picture) or ""
            local thumb_id = (t and t.id) or tostring(w.id)
            local has = (pic ~= "")
            if w.thumb ~= pic or w.has_thumb ~= has or w.thumb_id ~= thumb_id then
                w.thumb = pic
                w.has_thumb = has
                w.thumb_id = thumb_id
                changed = true
            end
        end
        if changed then
            model.ov_wins = window_list
            request_live_thumbnails()
        end
    end

    watch("thumbnails", function(info)
        thumbnails_list = (info and info.list) or {}
        thumbnails_by_id = {}
        for _, t in ipairs(thumbnails_list) do
            if t.id and t.id ~= "" then
                thumbnails_by_id[t.id] = t
            end
        end
        if shown() then
            update_window_thumbs()
        end
    end)

    local function refresh_windows()
        run("niri", { "msg", "-j", "windows" }, function(out)
            local ok, all = pcall(json.decode, out or "")
            if not ok or type(all) ~= "table" then
                return
            end
            local wins = {}
            for _, w in ipairs(all) do
                local app = w.app_id or ""
                if app ~= "" and app ~= "pleamar" then
                    local ws_num = tonumber(w.workspace_id) or 0
                    wins[#wins + 1] = {
                        id = w.id,
                        title = w.title or "",
                        app_id = app,
                        ws = ws_num,
                        ws_label = ws_num > 0 and ("WS " .. tostring(ws_num)) or "",
                        icon = icon_for(app),
                        t = focus_secs(w),
                        thumb = "",
                        has_thumb = false,
                        thumb_id = tostring(w.id),
                    }
                end
            end
            -- Sort: all workspaces, most recent first
            table.sort(wins, function(a, b) return a.t > b.t end)
            while #wins > 16 do
                table.remove(wins)
            end

            local used_ids = {}
            for _, w in ipairs(wins) do
                local t = match_thumbnail(w, used_ids)
                if t then
                    w.thumb_id = t.id
                    w.thumb = t.picture or ""
                    w.has_thumb = (w.thumb ~= "")
                end
            end

            window_list = wins
            model.ov_wins = wins
            text.win_count_text = string.format("%d %s", #wins, #wins == 1 and "window" or "windows")

            fact.ov_sel = 0
            request_live_thumbnails()
        end)
    end

    opened(refresh_windows)
    closed(function() pcall(sys.call, "thumbnails.live") end)      -- stop asking when closed

    local COLS = 4

    on("next_win", function()
        local count = #window_list
        if count > 0 then
            fact.ov_sel = (fact.ov_sel + 1) % count
        end
    end)

    on("prev_win", function()
        local count = #window_list
        if count > 0 then
            fact.ov_sel = (fact.ov_sel - 1 + count) % count
        end
    end)

    on("down_win", function()
        local count = #window_list
        if count > 0 then
            local target = fact.ov_sel + COLS
            if target < count then
                fact.ov_sel = target
            end
        end
    end)

    on("up_win", function()
        local count = #window_list
        if count > 0 then
            local target = fact.ov_sel - COLS
            if target >= 0 then
                fact.ov_sel = target
            end
        end
    end)

    on("ov_switch_to", function(idx)
        fact.open = false
        pcall(sys.call, "thumbnails.live")
        local i = tonumber(idx) or fact.ov_sel or 0
        local target = window_list[i + 1]
        if target and target.id then
            run("niri", { "msg", "action", "focus-window", "--id", tostring(target.id) }, nil, { output = false })
        end
    end)
end)

module("welcome", function(panel, opened, shown, closed)
    -- First-run welcome. Shown once: when ~/.config/beskar/welcome-done is missing, a few seconds after the shell starts
    -- (the other scenes need to be up). Its choices are sent to Settings, which owns the look and saves it.
    local function say(scene, words)
        pcall(sys.call, "say", scene, words)
    end
    local function sh(script, cb, ...)
        run("sh", { "-c", script, "x", ... }, cb, cb == nil and { output = false } or nil)
    end

    local function show()
        fact.page = 0
        if not shown() then say("topbar", "emit open_panel 9") end     -- the frame picks the monitor with the focus
    end

    -- mirror what Settings has now, so the switches on page 2 start right
    sh('cat "$HOME/.config/pleamar_shell.json" "$HOME/.config/beskar/prefs.json" 2>/dev/null', function(out)
        out = out or ""
        fact.wl_mode = out:find('"dark_mode": *false') and 0 or 1
        local app = out:match('"appearance": *(%d)')
        if app then fact.wl_mode = tonumber(app) == 0 and 0 or (tonumber(app) == 2 and 2 or 1) end
        fact.wall_colours = out:find('"accent_auto": *true') ~= nil
        fact.theme_apps = not out:find('"apps": *false')
    end)

    -- first run?
    sh('[ -f "$HOME/.config/beskar/welcome-done" ] && echo done || echo first', function(out)
        if (out or ""):find("first") then
            after(7000, show)
        end
    end)

    on("wl_next", function() fact.page = math.min(2, (tonumber(fact.page) or 0) + 1) end)
    on("wl_back", function() fact.page = math.max(0, (tonumber(fact.page) or 0) - 1) end)

    on("wl_done", function()
        if shown() then fact.open = false end
        sh('mkdir -p "$HOME/.config/beskar" && : > "$HOME/.config/beskar/welcome-done"')
    end)

    on("choose_dark", function() fact.wl_mode = 1; say("settings", "emit set_mode 1") end)
    on("choose_light", function() fact.wl_mode = 0; say("settings", "emit set_mode 0") end)
    on("choose_auto", function() fact.wl_mode = 2; say("settings", "emit set_mode 2") end)
    on("toggle_colours", function()
        fact.wall_colours = not (fact.wall_colours == true)
        say("settings", "emit toggle_accent_auto")
    end)
    on("toggle_apps_pref", function()
        fact.theme_apps = not (fact.theme_apps == true)
        say("settings", "emit toggle_apps")
    end)

    -- `./beskar welcome` and Settings ask for it again
    on("show_again", show)
end)

-- opening one closes the other panels (Control Center, notifications, Settings …)
require("exclusive")("overlays")
