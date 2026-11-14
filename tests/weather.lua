-- Run only this suite for the shared-weather seam: lua tests/weather.lua
package.path="shell/?.luau;"..package.path
local Data=require("weather_data")
local passed=0
local function check(v,why) assert(v,why);passed=passed+1 end
local function copy(v) if type(v)~="table" then return v end;local t={};for k,x in pairs(v) do t[k]=copy(x) end;return t end
local A={lat=51.5,lon=-0.12,city="City A"}
local B={lat=35.6,lon=139.6,city="City B"}
local C={lat=-33.8,lon=151.2,city="City C"}
local function response(temp)
    local d={timezone="Europe/London",current={time="2026-11-13T12:00",temperature_2m=temp or 12,weather_code=3,is_day=1,
        apparent_temperature=10,relative_humidity_2m=80,wind_speed_10m=15,surface_pressure=1012},
        hourly={time={},temperature_2m={},weather_code={},is_day={},precipitation_probability={}},
        daily={time={},temperature_2m_max={},temperature_2m_min={},weather_code={},sunrise={"2026-11-13T07:15"},sunset={"2026-11-13T16:20"},uv_index_max={2},precipitation_probability_max={}}}
    for i=1,24 do d.hourly.time[i]=string.format("2026-11-13T%02d:00",i-1);d.hourly.temperature_2m[i]=i;d.hourly.weather_code[i]=3;d.hourly.is_day[i]=1;d.hourly.precipitation_probability[i]=i end
    for i=1,6 do d.daily.time[i]=string.format("2026-11-%02d",12+i);d.daily.temperature_2m_max[i]=15;d.daily.temperature_2m_min[i]=5;d.daily.weather_code[i]=3;d.daily.precipitation_probability_max[i]=70 end
    return d
end
local now=os.time()
local normalized=assert(Data.normalize(response(),A,now))
check(#normalized.hours==8 and normalized.hours[1].time=="2026-11-13T12:00","Only eight current/future hours")
check(#normalized.days==5,"Bounded five-day forecast")
local snapshot={version=1,revision=1,forecast=normalized,location=A,stale=false,loading=false,status="Open-Meteo"}
check(Data.valid_snapshot(snapshot),"Validate a normalized snapshot")
local v=Data.view(snapshot,false)
check(v.temp=="12°C" and v.wind=="15 km/h","Explicit and consistent units")
check(v.rain=="Rain chance today: 70%" and v.hours[1].rain=="13%","Daily and hourly rain chance")
check(v.sunrise=="07:15" and Data.view(snapshot,true).sunrise=="7:15 AM","Clock preference reformats without fetching")
check(v.status:find("Updated"),"Last update is displayed")
local missing=response();missing.current.relative_humidity_2m=nil
check(Data.view({forecast=Data.normalize(missing,A,now),location=A,status="Open-Meteo"}).humidity=="--","Missing values are not invented as zero")
check(not Data.normalize({},A,now),"Reject incomplete response")
check(not Data.place({lat=91,lon=0,city="Bad"}),"Reject invalid latitude")
check(not Data.place({lat=0,lon=181,city="Bad"}),"Reject invalid longitude")
check(Data.parse_place('51.5 -0.12 City with spaces').city=="City with spaces","Existing location file remains supported")
check(Data.url(A):find("temperature_unit=celsius",1,true) and Data.url(A):find("precipitation_probability",1,true),"Forecast request declares units and precipitation fields")
snapshot.stale=true
check(Data.view(snapshot).bar_temp=="~12°C" and Data.view(snapshot).condition:find("Cached"),"Cached readings are visibly marked")
snapshot.stale=false

local function owner(cache,previous,start_time)
    local h={handlers={},requests={},files={['cache.json']=cache,['snapshot.json']=previous},timers={},says={},text={},fact={},now=start_time or now,fail_write=false}
    local env=setmetatable({require=require,text=h.text,fact=h.fact,json={encode=copy,decode=function(x) if type(x)~="table" then error("bad JSON") end;return copy(x) end},
        os=setmetatable({time=function() return h.now end},{__index=os}),
        sys={ask=function(_,name) return copy(h.files[name]) end,call=function(service,name,payload)
            if service=="files.write" then if h.fail_write then error("disk full") end;h.files[name]=copy(payload)
            else h.says[#h.says+1]={name,payload} end
        end},
        on=function(n,fn) h.handlers[n]=fn end,
        every=function(_,fn) h.timers[#h.timers+1]=fn end,
        run=function(cmd,args,cb) h.requests[#h.requests+1]={cmd=cmd,args=args,cb=cb,done=false} end}, {__index=_G})
    assert(loadfile("shell/weather.luau","t",env))()
    function h:fire(n,p) self.handlers[n](p) end
    function h:reply(i,out,code) local r=assert(self.requests[i]);check(not r.done,"Each callback completes once");r.done=true;r.cb(out,code or 0) end
    function h:forecasts() local list={};for i,r in ipairs(self.requests) do if r.cmd=="curl" and r.args[#r.args]:find("/v1/forecast",1,true) then list[#list+1]=i end end;return list end
    return h
end
local h=owner()
h:reply(1,"51.5 -0.12 City A",0)
check(#h:forecasts()==1,"Startup starts one forecast request")
h:fire("ensure");h:fire("ensure");h:fire("refresh")
check(#h:forecasts()==1,"Four consumers and repeated refresh coalesce while in flight")
local f=h:forecasts()[1]
check(table.concat(h.requests[f].args," "):find("%-%-max%-time 8")~=nil,"Forecast request is time bounded")
h:reply(f,response(),0)
check(h.fact.loaded and not h.fact.stale and h.text.temp=="12°C","Publish successful forecast")
check(h.files['cache.json'].forecast.location.city=="City A","Persist last-good forecast")
local count=#h:forecasts();h:fire("ensure");h.timers[1]()
check(#h:forecasts()==count,"Opening readers and timer do not refetch fresh data")
h:fire("refresh");h:reply(h:forecasts()[2],"offline",28)
check(h.fact.stale and h.text.temp=="12°C" and h.text.condition:find("Cached"),"Offline retains labeled last-good data")
h:fire("ensure")
check(#h:forecasts()==2,"Failure retry obeys backoff")
h.now=h.now+61;h.timers[1]()
check(#h:forecasts()==3 and h.fact.stale,"Retry keeps cached labeling until success")
h:reply(h:forecasts()[3],response(13),0)
check(not h.fact.stale and h.text.temp=="13°C","Successful retry clears cached status")

h:fire("refresh");local old=h:forecasts()[4]
h:fire("choose_location",B)
check(not h.fact.loaded and h.text.city=="City B" and h.text.temp=="--°C","Location change cannot relabel old weather as the new city")
local saveB=#h.requests;h:reply(saveB,"",0)
check(#h:forecasts()==4,"New location queues behind the old in-flight forecast")
h:reply(old,response(99),0)
check(h.text.temp=="--°C" and #h:forecasts()==5,"Old location reply is rejected before queued fetch")
h:reply(h:forecasts()[5],response(20),0)
check(h.text.city=="City B" and h.text.temp=="20°C","New location reaches shared state")

-- Two rapid choices cannot race their on-disk location writes.
h:fire("choose_location",A);local saveA=#h.requests
h:fire("choose_location",C)
check(#h.requests==saveA,"Location writes serialize")
h:reply(saveA,"",0);local saveC=#h.requests
check(h.requests[saveC].cmd=="sh" and h.requests[saveC].args[#h.requests[saveC].args]=="City C","Newest location is written last")
h:reply(saveC,"",0);h:reply(h:forecasts()[6],response(25),0)
check(h.text.city=="City C" and h.text.temp=="25°C","Latest location wins rapid changes")

local restarted=owner(h.files['cache.json'],h.files['snapshot.json'],h.now)
check(restarted.fact.loaded and restarted.fact.stale,"Restart immediately restores labeled cached content")
restarted:reply(1,"-33.8 151.2 City C",0)
check(#restarted:forecasts()==0 and not restarted.fact.stale,"Fresh matching cache avoids restart fetch")
local rev=restarted.files['snapshot.json'].revision
check(rev>h.files['snapshot.json'].revision,"Snapshot revision advances across owner restart")
local before=#restarted.says;restarted:fire("resync",-1)
check(#restarted.says==before+1 and #restarted:forecasts()==0,"Widget restart requests snapshot without network traffic")
restarted:fire("resync",rev)
check(#restarted.says==before+1,"Up-to-date widget avoids redundant reads")
local broken=owner({version=1,forecast={bad=true}})
check(not broken.fact.loaded,"Invalid disk cache cannot fabricate weather")
broken:reply(1,"malformed location",0)
check(#broken:forecasts()==0 and broken.text.status:find("Invalid location"),"Invalid explicit location is reported without IP overwrite")
-- Location resolution must not accidentally refetch the previous city's forecast.
restarted:fire("use_ip");local ip=#restarted.requests
restarted:fire("ensure");restarted:fire("refresh")
check(#restarted:forecasts()==0,"Readers cannot fetch the old city during IP resolution")
restarted:fire("choose_location",A);local save=#restarted.requests
restarted:reply(ip,{success=true,latitude=B.lat,longitude=B.lon,city=B.city},0)
check(restarted.text.city=="City A","An old IP lookup cannot replace an explicit city choice")
restarted:reply(save,"",0)
restarted.fail_write=true
restarted:reply(restarted:forecasts()[1],response(),0)
check(restarted.fact.loaded and restarted.text.status:find("Could not save"),"Disk failure retains successful in-memory weather")
restarted.fail_write=false;restarted:fire("resync",-1)
check(restarted.files['snapshot.json'].forecast.location.city=="City A","Resync retries a failed snapshot save")
local future=owner(h.files['cache.json'],nil,h.now-60)
future:reply(1,"-33.8 151.2 City C",0)
check(future.fact.stale and #future:forecasts()==1,"A future cache timestamp is stale after a clock change")

-- Exercise the separate-process read-only bridge without network or a real desktop.
local client={handlers={},reads={},says={},fact={hour12=false},text={},now=h.now}
local env=setmetatable({require=require,fact=client.fact,text=client.text,
    json={decode=function(x) if type(x)~="table" then error("bad JSON") end;return copy(x) end},
    os=setmetatable({time=function() return client.now end},{__index=os}),
    sys={ask=function(_,name) return name=="XDG_DATA_HOME" and "/data home" or "/home/test" end,
        call=function(_,scene,command) if client.unavailable then error("not running") end;client.says[#client.says+1]={scene,command} end},
    on=function(n,fn) client.handlers[n]=fn end,
    after=function(_,fn) client.start=fn end,every=function(_,fn) client.resync=fn end,
    run=function(cmd,args,cb) client.reads[#client.reads+1]={cmd=cmd,args=args,cb=cb} end},{__index=_G})
assert(loadfile("shell/weather_client.luau","t",env))()()
client.start()
check(client.says[1][2]=="emit resync -1","Widget restart asks the owner for its snapshot")
client.handlers.weather_changed(1);client.handlers.weather_changed(2);client.handlers.weather_changed(3)
check(#client.reads==1 and client.reads[1].cmd=="cat","Widget notifications coalesce into one read, never a forecast request")
check(client.reads[1].args[1]=="/data home/pleamar/weather/snapshot.json","Snapshot path is passed as one argument")
client.reads[1].cb(h.files['snapshot.json'],0)
check(#client.reads==2 and client.text.weather_temp=="25°C","Widget paints owner's current forecast and coalesces follow-up reads")
local older=copy(h.files['snapshot.json']);older.revision=0;older.forecast.current.temp=99
client.reads[2].cb(older,0)
check(client.text.weather_temp=="25°C","Older snapshot cannot replace newer widget weather")
client.resync()
check(client.says[#client.says][2]=="emit resync "..h.files['snapshot.json'].revision,"Periodic resync carries the loaded revision")
client.unavailable=true;client.resync()
check(client.fact.weather_cached and client.text.weather_temp=="~25°C","Owner outage visibly marks widget data as cached")
client.unavailable=false;client.now=client.now+Data.MAX_AGE+1;client.resync()
check(client.fact.weather_cached,"Aging data remains visibly cached even if the socket responds")
client.handlers.weather_reload()
check(client.says[#client.says][2]=="emit refresh","Explicit widget refresh delegates to the owner")
print("Weather: "..passed.." focused checks passed")
