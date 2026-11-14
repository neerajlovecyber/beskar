-- Read-only widget bridge. Only Weather makes forecast requests and writes these files.
return function()
    local Data=require("weather_data")
    local base=sys.ask("env","XDG_DATA_HOME")
    if not base or base=="" then base=(sys.ask("env","HOME") or "").."/.local/share" end
    local path=base.."/pleamar/weather/snapshot.json"
    local revision,reading,pending,last=-1,false,false,nil
    local function paint(unavailable)
        if not last then return end
        local display={}
        for k,v in pairs(last) do display[k]=v end
        if unavailable or (display.forecast and (os.time()<display.forecast.fetched_at or os.time()-display.forecast.fetched_at>=Data.MAX_AGE)) then
            display.stale=true;display.status="Cached · Weather service unavailable"
        end
        local v=Data.view(display,fact.hour12)
        text.weather_temp,text.weather_cond,text.weather_icon=v.bar_temp,v.condition,v.icon
        text.weather_city,text.weather_range,text.weather_status=v.city,v.range,v.status
        fact.weather_cached=display.forecast~=nil and display.stale
    end
    local function read()
        if reading then pending=true;return end
        reading=true
        run("cat",{path},function(out,code)
            reading=false
            local ok,s=pcall(json.decode,out or "")
            if code==0 and ok and Data.valid_snapshot(s) and s.revision>=revision then
                last=s;revision=s.revision;paint(false)
            elseif code~=0 or not ok or not Data.valid_snapshot(s) then paint(true) end
            if pending then pending=false;read() end
        end)
    end
    on("weather_changed",function(n) if tonumber(n)~=revision then read() end end)
    local function resync()
        local ok=pcall(sys.call,"say","weather","emit resync "..revision)
        paint(not ok)
    end
    on("weather_reload",function() pcall(sys.call,"say","weather","emit refresh") end)
    on("fact:hour12",function() paint(false) end)
    after(500,resync)
    every(15000,resync)
end
