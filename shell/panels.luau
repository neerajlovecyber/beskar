-- Panels (weather, music, today, updates): ONE scene (panels.plm), one logic; the shared core is panelcore.luau.
local module = require("panelcore")({ dashboard = 3, music = 9, weather = 15, updates = 16 })

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

-- one panel at a time: opening one of ours closes the others (Spotlight, Control Center, Settings …)
require("exclusive")("panels")
