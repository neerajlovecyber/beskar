-- Bounded forecast contract and presentation, shared by the owner and its readers.
local codes = require("weathercodes")
local M = { VERSION = 1, MAX_AGE = 900 }
local function number(v) return type(v) == "number" and v == v and math.abs(v) < 1e10 end
local function value(v) if number(v) then return v end end
function M.place(p)
    if type(p) ~= "table" then return nil end
    local lat, lon = tonumber(p.lat), tonumber(p.lon)
    if not number(lat) or not number(lon) or math.abs(lat) > 90 or math.abs(lon) > 180 then return nil end
    local city = type(p.city) == "string" and p.city:gsub("[%c]", " "):match("^%s*(.-)%s*$") or "Here"
    if #city > 160 then return nil end
    return { lat = lat, lon = lon, city = city ~= "" and city or "Here" }
end
function M.parse_place(s)
    local lat, lon, city = (s or ""):match("^%s*(%S+)%s+(%S+)%s*(.-)%s*$")
    return M.place({lat=lat,lon=lon,city=city})
end
function M.key(p) return p and string.format("%.6f,%.6f", p.lat, p.lon) or "" end
function M.url(p)
    return "https://api.open-meteo.com/v1/forecast?latitude=" .. p.lat .. "&longitude=" .. p.lon
        .. "&current=temperature_2m,relative_humidity_2m,apparent_temperature,weather_code,wind_speed_10m,surface_pressure,is_day"
        .. "&hourly=temperature_2m,weather_code,is_day,precipitation_probability"
        .. "&daily=weather_code,temperature_2m_max,temperature_2m_min,sunrise,sunset,uv_index_max,precipitation_probability_max"
        .. "&temperature_unit=celsius&wind_speed_unit=kmh&timezone=auto&forecast_days=6"
end
local function iso(s) return type(s)=="string" and #s<=40 and s:match("^%d%d%d%d%-%d%d%-%d%d") ~= nil end
function M.normalize(d, p, now)
    if type(d) ~= "table" or type(d.current) ~= "table" or not M.place(p) then return nil end
    local c = d.current
    local hr,dy=type(d.hourly)=="table" and d.hourly or {},type(d.daily)=="table" and d.daily or {}
    if not number(c.temperature_2m) or not number(c.weather_code) or not iso(c.time) then return nil end
    local out = { location=M.place(p), fetched_at=now, timezone=type(d.timezone)=="string" and d.timezone or "",
        current={ temp=c.temperature_2m, code=c.weather_code, day=c.is_day ~= 0, feels=value(c.apparent_temperature),
            humidity=value(c.relative_humidity_2m), wind=value(c.wind_speed_10m), pressure=value(c.surface_pressure) }, hours={}, days={} }
    local function at(t,i) return type(t)=="table" and t[i] or nil end
    for i, t in ipairs(type(hr.time)=="table" and hr.time or {}) do
        local temp, code = at(hr.temperature_2m,i), at(hr.weather_code,i)
        if iso(t) and t:sub(1,13)>=c.time:sub(1,13) and number(temp) and number(code) and #out.hours<8 then
            out.hours[#out.hours+1]={time=t,temp=temp,code=code,day=at(hr.is_day,i)~=0,rain=value(at(hr.precipitation_probability,i))}
        end
    end
    for i,t in ipairs(type(dy.time)=="table" and dy.time or {}) do
        local lo,hi,code=at(dy.temperature_2m_min,i),at(dy.temperature_2m_max,i),at(dy.weather_code,i)
        if iso(t) and number(lo) and number(hi) and lo<=hi and number(code) and #out.days<5 then
            out.days[#out.days+1]={time=t,lo=lo,hi=hi,code=code,rain=value(at(dy.precipitation_probability_max,i))}
        end
    end
    out.sunrise=iso(at(dy.sunrise,1)) and at(dy.sunrise,1) or nil
    out.sunset=iso(at(dy.sunset,1)) and at(dy.sunset,1) or nil
    out.uv=value(at(dy.uv_index_max,1))
    return out
end
function M.valid_forecast(f)
    if type(f)~="table" or not M.place(f.location) or not number(f.fetched_at) or type(f.current)~="table"
        or not number(f.current.temp) or not number(f.current.code) or type(f.hours)~="table" or #f.hours>8
        or type(f.days)~="table" or #f.days>5 or type(f.timezone)~="string" or #f.timezone>100 then return false end
    for _,k in ipairs({"feels","humidity","wind","pressure"}) do if f.current[k]~=nil and not number(f.current[k]) then return false end end
    for _,h in ipairs(f.hours) do
        if type(h)~="table" or not iso(h.time) or not number(h.temp) or not number(h.code) or (h.rain~=nil and not number(h.rain)) then return false end
    end
    for _,d in ipairs(f.days) do
        if type(d)~="table" or not iso(d.time) or not number(d.lo) or not number(d.hi) or d.lo>d.hi or not number(d.code)
            or (d.rain~=nil and not number(d.rain)) then return false end
    end
    if f.uv~=nil and not number(f.uv) then return false end
    if f.sunrise~=nil and not iso(f.sunrise) then return false end
    if f.sunset~=nil and not iso(f.sunset) then return false end
    return true
end
function M.valid_snapshot(s)
    return type(s)=="table" and s.version==M.VERSION and number(s.revision) and s.revision>=0
        and type(s.status)=="string" and #s.status<=300 and type(s.loading)=="boolean" and type(s.stale)=="boolean"
        and (s.location==nil or M.place(s.location)~=nil)
        and (s.forecast==nil or (M.valid_forecast(s.forecast) and M.key(s.location)==M.key(s.forecast.location)))
end
local function deg(v,unit) return number(v) and (string.format("%d°",math.floor(v+0.5)) .. (unit and "C" or "")) or "--" end
local function metric(v,suffix) return number(v) and string.format("%d%s",math.floor(v+0.5),suffix or "") or "--" end
local function clock(iso,hour12,hour_only)
    local h,m=(iso or ""):match("T(%d%d):(%d%d)")
    if not h then return "--" end
    h=tonumber(h)
    if hour12==false then return hour_only and string.format("%02d",h) or string.format("%02d:%s",h,m) end
    return (h%12==0 and 12 or h%12) .. (hour_only and "" or ":"..m) .. (h<12 and " AM" or " PM")
end
function M.view(s,hour12)
    local f=s.forecast
    local v={city=s.location and s.location.city or "Choose a location",temp="--°C",bar_temp="--°C",icon="󰅟",condition=s.status,
        feels="",range="",humidity="--",wind="--",pressure="--",uv="--",sunrise="--",sunset="--",rain="Rain chance: --",
        status=s.status,hours={},days={},lo=0,hi=1}
    if not f then return v end
    local c=f.current
    v.temp=deg(c.temp,true);v.bar_temp=(s.stale and "~" or "")..v.temp
    v.icon=codes.icon(c.code,c.day);v.condition=codes.words(c.code)..(s.stale and " · Cached" or "")
    v.feels=c.feels and "Feels like "..deg(c.feels,true) or ""
    v.humidity=metric(c.humidity,"%");v.wind=metric(c.wind," km/h");v.pressure=metric(c.pressure," hPa");v.uv=metric(f.uv)
    v.sunrise=clock(f.sunrise,hour12);v.sunset=clock(f.sunset,hour12)
    if f.days[1] then v.range="H "..deg(f.days[1].hi).."   L "..deg(f.days[1].lo);v.rain="Rain chance today: "..metric(f.days[1].rain,"%") end
    for _,h in ipairs(f.hours) do v.hours[#v.hours+1]={t=clock(h.time,hour12,true),icon=codes.icon(h.code,h.day),temp=deg(h.temp),rain=metric(h.rain,"%")} end
    local lo,hi=1e9,-1e9
    for i,d in ipairs(f.days) do
        local y,m,day=d.time:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)")
        local label=i==1 and "Today" or os.date("%a",os.time({year=tonumber(y),month=tonumber(m),day=tonumber(day),hour=12}))
        lo,hi=math.min(lo,d.lo),math.max(hi,d.hi)
        v.days[#v.days+1]={day=label,icon=codes.icon(d.code,true),lo=deg(d.lo),hi=deg(d.hi),lo_n=d.lo,hi_n=d.hi}
    end
    if #v.days>0 then v.lo,v.hi=lo,hi end
    local format=hour12==false and "%H:%M" or "%I:%M %p"
    local updated=os.date(format,f.fetched_at)
    if hour12~=false then updated=updated:gsub("^0","") end
    v.status=s.status.." · Updated "..updated
    return v
end
return M
