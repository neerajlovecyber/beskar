-- The info panels' logic: weather, music, today, the timer and the Personal editor. Their content is drawn inside the frame's own surface
local text = require("keys_text")     -- the text fields are the Keys scene's (keys_text.luau)
-- (common/info_panels.plm, timer_panel.plm, personal_editor.plm); topbar.luau calls this with its panel client.
return function(module)

local function close_panel() emit("Panels.close") end

module("weather", function(panel, opened, shown)
    -- The panel owns search/view state; Weather owns location and forecast acquisition.
    local Data=require("weather_data")
    local VIEW_FORECAST_H=692
    local found={}
    local function field_focus(on) if on then require("topbar_hooks").focus("wq") else require("topbar_hooks").focus() end end
    local function urlencode(value)
        return (value:gsub("[^%w%-_%.~]",function(c) return string.format("%%%02X",c:byte()) end))
    end
    local function paint_forecast()
        local ok,state=pcall(json.decode,text["Weather.snapshot"] or "")
        if not ok or not Data.valid_snapshot(state) then return end
        local v=Data.view(state,fact["Settings.hour12"])
        text.wx_city,text.w_temp,text.w_icon,text.w_cond=v.city,v.temp,v.icon,v.condition
        text.w_feels,text.w_range=v.feels,v.range
        text.w_hum,text.w_wind,text.w_press,text.w_uv=v.humidity,v.wind,v.pressure,v.uv
        text.w_sunrise,text.w_sunset,text.w_rain,text.w_status=v.sunrise,v.sunset,v.rain,v.status
        model.hours,model.days=v.hours,v.days
        fact.wx_lo,fact.wx_hi=v.lo,v.hi
        fact.wx_loaded,fact.wx_loading=state.forecast~=nil,state.loading
    end
    on("text:Weather.snapshot",paint_forecast)
    on("fact:Settings.hour12",paint_forecast)
    after(100,paint_forecast)

    -- ── choosing a place ────────────────────────────────────────────
    local function show_forecast()
        fact.wx_view=0; fact.wx_focus=-1; fact.wx_sel=0
        field_focus(false)
        panel.height(VIEW_FORECAST_H)
    end
    local function save_place(lat,lon,city)
        emit("Weather.choose_location",{lat=lat,lon=lon,city=city})
        show_forecast()
    end

    -- keyboard: wx_focus (forecast: -1 none, 0 Change, 1 Refresh) and wx_sel (places: -2 Back, -1 my location, 0.. a found place;
    -- the search field has the keys while wx_sel >= 0)
    local function set_sel(v)
        v = math.max(-2, math.min(v, math.max(#found - 1, 0)))
        fact.wx_sel = v
        field_focus(v >= 0)
    end
    local function paint_places()
        local rows = {}
        for i, p in ipairs(found) do
            rows[i] = { name = p.name, sub = p.sub }
        end
        model.places = rows
        if (tonumber(fact.wx_sel) or 0) >= 0 then fact.wx_sel = 0 end     -- new results: the first one is the one Enter picks
        panel.height(172 + math.max(#rows, 1) * 48 + 20)
    end

    local search_timer = nil
    local function search(q)
        fact.wx_searching = true
        run("curl", { "-fsS", "--max-time", "6",
            "https://geocoding-api.open-meteo.com/v1/search?count=5&language=en&format=json&name=" .. urlencode(q) },
            function(out, code)
                if (text.wq or ""):match("^%s*(.-)%s*$") ~= q then return end
                fact.wx_searching = false         -- the field changed meanwhile
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

    on("text:Keys.wq", function(q)
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

    local change_place, pick_place, use_ip
    function change_place()
        fact.wx_view = 1
        fact.wx_focus = -1
        text.wq = ""
        found = {}
        paint_places()
        set_sel(0)
        text.w_source = "Current location: " .. (text["Weather.city"] or "Choose a city")
    end
    on("loc_change", change_place)

    on("loc_back", show_forecast)

    function pick_place(i)
        local p = found[(tonumber(i) or -1) + 1]
        if p then
            save_place(p.lat, p.lon, p.name)
        end
    end
    on("loc_pick", pick_place)

    function use_ip()
        show_forecast()
        emit("Weather.use_ip")
    end
    on("loc_ip", use_ip)
    on("weather_reload",function() emit("Weather.refresh") end)

    -- keys (rules in common/info_panels.plm): 1 previous · 2 next · 6 activate (release of Enter / Space) · 7 Enter in the search field
    on("wx_nav", function(code)
        if not shown() then return end
        code = tonumber(code) or 0
        if (tonumber(fact.wx_view) or 0) == 0 then
            local f = tonumber(fact.wx_focus) or -1
            local last = fact.wx_loading and 0 or 1            -- "Refresh" is off while a forecast is loading
            if code == 2 then fact.wx_focus = f >= last and 0 or f + 1
            elseif code == 1 then fact.wx_focus = f <= 0 and last or f - 1
            elseif code == 6 then
                if f == 0 then change_place() elseif f == 1 and not fact.wx_loading then emit("weather_reload") end
            end
            return
        end
        local sel = tonumber(fact.wx_sel) or 0
        local top = math.max(#found - 1, 0)
        if code == 2 then set_sel(sel >= top and -2 or sel + 1)          -- Tab / Down walk Back → my location → places, and wrap
        elseif code == 1 then set_sel(sel <= -2 and top or sel - 1)
        elseif code == 7 then                                              -- Enter in the search field
            if sel >= 0 and found[sel + 1] then pick_place(sel) end
        elseif code == 6 then                                              -- Enter / Space on a button
            if sel == -2 then show_forecast() elseif sel == -1 then use_ip() end
        end
    end)
    opened(function()
        show_forecast()
        paint_forecast();emit("Weather.ensure")
    end)
    panel.height(VIEW_FORECAST_H)
end)


module("music", function(panel, opened, shown)
    -- Music panel logic: the `media` service (MPRIS) → the card. The frame draws the glass (panel.luau reports the height).
    panel.height(196)
    -- keys (rules in common/info_panels.plm); the player controls are the System scene's events. The release of the Enter that OPENED the
    -- panel (from Spotlight, a shortcut) must not toggle the player: key releases count only 350 ms after it opens.
    local armed = false
    opened(function() armed = false; after(350, function() armed = true end) end)
    on("mu_nav", function(code)
        if not shown() then return end
        code = tonumber(code) or 0
        if code == 1 then if armed then emit("System.play_pause") end
        elseif code == 2 then emit("System.previous")
        elseif code == 3 then emit("System.next")
        elseif code == 4 or code == 5 then
            local len = tonumber(fact["System.track_len"]) or 0
            if len > 0 then
                local pos = tonumber(fact["System.track_pos"]) or 0
                emit("System.seek", math.max(0, math.min(1, (pos + (code == 5 and 10 or -10)) / len)))
            end
        end
    end)
    -- (what is playing and the player controls are the System scene's: system.luau)
end)


module("dashboard", function(panel, opened, shown)
    -- Dashboard ("Today") logic: greeting, month calendar, weather (same place as the top bar), CPU / memory / disk,
    -- uptime and the battery's real state. The frame draws the glass (panel.luau reports the height).

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
    local Calendar = require("calendar")
    local function paint_calendar()
        local view = Calendar.month(tonumber(fact.cal_shift) or 0)
        text.cal_title, model.cal_month = view.title, {view}
    end
    on("cal_prev", function() fact.cal_shift = (tonumber(fact.cal_shift) or 0) - 1; paint_calendar() end)
    on("cal_next", function() fact.cal_shift = (tonumber(fact.cal_shift) or 0) + 1; paint_calendar() end)
    on("cal_now", function() fact.cal_shift = 0; paint_calendar() end)
    paint_calendar()

    -- keys (rules in common/info_panels.plm): focus ring 0 weather · 1 calendar · 2 notes · 3 to-dos (-1 none until the first move)
    on("d_nav", function(code)
        if not shown() then return end
        code = tonumber(code) or 0
        local f = tonumber(fact.d_focus) or -1
        if code == 2 then fact.d_focus = (f + 1) % 4
        elseif code == 1 then fact.d_focus = f < 0 and 3 or (f - 1) % 4
        elseif code == 3 then fact.cal_shift = (tonumber(fact.cal_shift) or 0) - 1; paint_calendar()
        elseif code == 4 then fact.cal_shift = (tonumber(fact.cal_shift) or 0) + 1; paint_calendar()
        elseif code == 5 then fact.cal_shift = 0; paint_calendar()
        elseif code == 6 then
            if f == 0 then
                fact.last_screen = tonumber(fact["Panels.open_screen"]) or 0         -- the monitor Today is on
                require("topbar_hooks").emit("Topbar.open_weather")
            elseif f == 1 then fact.cal_shift = 0; paint_calendar()
            elseif f == 2 then require("topbar_hooks").call("pe_open", 0)
            elseif f == 3 then require("topbar_hooks").call("pe_open", 1) end
        end
    end)

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
        fact.d_focus = -1
        refresh_all()
    end)
    on("refresh_stats", refresh_all)

    -- Today reads the same Weather owner directly in the scene.

    -- ── tell the frame (it draws the glass) how tall the card is ──
    local has_battery = true
    local function push_height()
        panel.height(has_battery and 788 or 712)
    end
    on("fact:System.bat.present", function(v)        -- the System scene holds the battery service
        local present = not (v == false or v == 0)
        if present ~= has_battery then
            has_battery = present
            push_height()
        end
    end)
    push_height()
end)


require("personal_editor")(module)

module("timer", require("timer_panel"))
end
