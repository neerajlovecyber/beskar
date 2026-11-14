-- Sole owner of location changes and forecast acquisition; views never poll the weather API.
local Data=require("weather_data")
local function read(name)
    local ok,v=pcall(sys.ask,"files.read",name,"json");return ok and v or nil
end
local previous=read("snapshot.json")
local state={version=1,revision=Data.valid_snapshot(previous) and previous.revision or 0,loading=false,stale=true,status="Loading weather…"}
local cache=read("cache.json")
if type(cache)=="table" and cache.version==1 and Data.valid_forecast(cache.forecast) then
    state.forecast,state.location=cache.forecast,cache.forecast.location
    state.status="Cached forecast"
end
local epoch,fetching,pending,last_attempt=0,false,nil,0
local saving,pending_save=false,nil
local locating=false
local snapshot_dirty=false
local request_forecast,choose,resolve_ip
local function notify() pcall(sys.call,"say","widgets","emit weather_changed "..state.revision) end
local function persist_snapshot()
    if pcall(sys.call,"files.write","snapshot.json",state) then snapshot_dirty=false;notify()
    else snapshot_dirty=true end
end
local function publish()
    state.revision=state.revision+1
    local v=Data.view(state,false)
    text.snapshot=json.encode(state)
    text.city,text.temp,text.bar_temp,text.icon=v.city,v.temp,v.bar_temp,v.icon
    text.condition,text.feels,text.range,text.status=v.condition,v.feels,v.range,v.status
    fact.loaded,fact.loading,fact.stale=state.forecast~=nil,state.loading,state.stale
    persist_snapshot()
end
local function failure(message)
    state.loading=false;state.stale=true
    state.status=state.forecast and ("Cached · "..message) or message
    publish()
end
request_forecast=function(force)
    if not state.location or saving or locating then return end
    local now=os.time()
    local fresh=state.forecast and Data.key(state.forecast.location)==Data.key(state.location)
        and now-state.forecast.fetched_at>=0 and now-state.forecast.fetched_at<Data.MAX_AGE
    if not force and fresh and not state.stale then
        if state.loading or state.stale then state.loading=false;state.stale=false;state.status="Open-Meteo";publish() end
        return
    end
    if fetching then
        if fetching.epoch~=epoch then pending={epoch=epoch,place=state.location} end
        return
    end
    if not force and now-last_attempt<60 then return end
    local token,p=epoch,state.location
    fetching={epoch=token};last_attempt=now
    state.loading=true;state.stale=state.stale or not fresh;state.status=state.stale and "Cached · Refreshing…" or "Refreshing…"
    if not state.forecast then state.status="Loading the forecast…" end
    publish()
    run("curl",{"-fsS","--connect-timeout","3","--max-time","8",Data.url(p)},function(out,code)
        fetching=false
        if token==epoch then
            local ok,decoded=pcall(json.decode,out or "")
            local forecast=code==0 and ok and Data.normalize(decoded,p,os.time()) or nil
            if forecast then
                state.forecast=forecast;state.loading=false;state.stale=false;state.status="Open-Meteo"
                if not pcall(sys.call,"files.write","cache.json",{version=1,forecast=forecast}) then
                    state.status="Open-Meteo · Could not save the offline cache"
                end
                publish()
            else failure("Refresh failed; retrying shortly") end
        end
        local queued=pending;pending=nil
        if queued and queued.epoch==epoch and Data.key(queued.place)==Data.key(state.location) then request_forecast(true) end
    end)
end
local function activate(p)
    state.location=p
    if state.forecast and Data.key(state.forecast.location)~=Data.key(p) then state.forecast=nil end
    local age=state.forecast and os.time()-state.forecast.fetched_at
    state.stale=not age or age<0 or age>=Data.MAX_AGE
    state.loading=true;state.status="Loading the forecast…";last_attempt=0
    publish()
end
local function save_location(job)
    saving=true
    local p=job.place
    run("sh",{"-c",'mkdir -p "$HOME/.config/beskar" && printf "%s %s %s\\n" "$1" "$2" "$3" > "$HOME/.config/beskar/location.tmp" && mv "$HOME/.config/beskar/location.tmp" "$HOME/.config/beskar/location"',"x",tostring(p.lat),tostring(p.lon),p.city},function(_,code)
        saving=false
        if job.epoch==epoch then
            if code==0 then request_forecast(true) else failure("Could not save the location") end
        end
        if pending_save then local next_job=pending_save;pending_save=nil;save_location(next_job) end
    end)
end
choose=function(p)
    p=Data.place(p)
    if not p then failure("Invalid location");return end
    epoch=epoch+1;pending=nil;locating=false;activate(p)
    local job={epoch=epoch,place=p}
    if saving then pending_save=job else save_location(job) end
end
resolve_ip=function()
    epoch=epoch+1;local token=epoch;pending=nil;locating=true
    state.loading=true;state.status="Finding your location…";publish()
    run("curl",{"-fsS","--connect-timeout","3","--max-time","6","https://ipwho.is/?fields=success,latitude,longitude,city"},function(out,code)
        if token~=epoch then return end
        locating=false
        local ok,d=pcall(json.decode,out or "")
        local p=code==0 and ok and type(d)=="table" and d.success~=false and Data.place({lat=d.latitude,lon=d.longitude,city=d.city}) or nil
        if p then choose(p) else failure("Could not find your location; choose a city") end
    end)
end
local function resolve_location()
    epoch=epoch+1;local token=epoch;pending=nil;locating=true
    run("sh",{"-c",'if [ -f "$HOME/.config/beskar/location" ]; then head -n 1 "$HOME/.config/beskar/location"; else exit 3; fi'},function(out,code)
        if token~=epoch then return end
        locating=false
        local p=code==0 and Data.parse_place(out) or nil
        if p then activate(p);request_forecast(false)
        elseif code==3 then resolve_ip()
        else failure("Invalid location file; choose a city") end
    end)
end
on("choose_location",choose)
on("use_ip",resolve_ip)
on("reload_location",resolve_location)
on("refresh",function() request_forecast(true) end)
on("ensure",function() request_forecast(false) end)
on("resync",function(rev) if snapshot_dirty then persist_snapshot() elseif tonumber(rev)~=state.revision then notify() end end)
every(60000,function()
    if snapshot_dirty then persist_snapshot() end
    request_forecast(false)
end)
publish()
resolve_location()
