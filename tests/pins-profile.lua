-- FIFO owner acknowledgements and the real atomic writer, in a throwaway HOME.
package.path = 'shell/?.luau;' .. package.path
local SP, Bridge, Store = require('setup_profiles'), require('pins_profile'), require('pins_store')
local n=0
local function check(v,m) if not v then error(m,2) end;n=n+1 end
local current, ready, busy = {'kitty'},true,false
local commits,replies,snaps={},{},{}
local c=Bridge.new({profiles=SP,current=function()return current end,ready=function()return ready end,busy=function()return busy end,
 commit=function(data,cb)commits[#commits+1]={data=data,cb=cb}end,set=function(list)current=list end,
 reply=function(info)replies[#replies+1]=info end,snapshot=function(info)snaps[#snaps+1]=info end})
local function fp(list)return SP.fingerprint('pins',SP.snapshot('pins',{list=list}))end
c.snapshot('read');check(snaps[1].ready and snaps[1].data.list[1]=='kitty','Snapshot reflects owner state')
local r={request='j:1:1',expect=fp(current),data={list={'foot'}}}
c.apply(r);check(#commits==1 and #replies==0 and current[1]=='kitty','No ack or memory change before commit')
c.apply(r);check(#commits==1,'In-flight duplicate is not queued twice')
c.apply({request='j:1:2',force=true,data={list={'kitty'}}});check(#commits==1,'Rollback waits behind the pending apply')
commits[1].cb(true);check(current[1]=='foot' and #commits==2 and replies[1].ok,'Commit changes memory then acknowledges')
commits[2].cb(true);check(current[1]=='kitty' and replies[2].ok,'Rollback runs after timed-out apply')
c.apply(r);check(#commits==2 and replies[3].ok,'Completed duplicates reuse their acknowledgement')
c.apply({request='j:2:1',expect='stale',data={list={'foot'}}});check(replies[4].code=='stale' and replies[4].untouched,'Stale requests change nothing')
c.apply({request='j:3:1',expect=fp(current),data={list={'app:bad|rm -rf anything'}}});check(replies[5].code=='not_portable','Imported command pins are refused')
c.apply({request='j:4:1',expect=fp(current),data={list={'foot'}}});commits[3].cb(false,'io');check(current[1]=='kitty' and replies[6].untouched,'Failed write keeps memory unchanged')
busy=true;c.apply({request='j:5:1',expect=fp(current),data={default=true}});check(replies[7].code=='busy','Local writes exclude profile changes');busy=false
ready=false;c.snapshot('loading');check(not snaps[2].ready,'Loading snapshots are unavailable');ready=true
check(not c.apply({request='bad',force='yes',data={default=true}}),'Force must be a boolean')
local function quote(v)return "'"..tostring(v):gsub("'","'\\''").."'"end
local temp=os.tmpname();os.remove(temp);assert(os.execute('mkdir -m 700 '..quote(temp)))
local function runner(cmd,args,cb)
 local out=temp..'/result';local words={'HOME='..quote(temp),cmd}
 for _,arg in ipairs(args)do words[#words+1]=quote(arg)end
 local ok,_,code=os.execute(table.concat(words,' ')..' > '..quote(out)..' 2>/dev/null')
 local f=assert(io.open(out,'rb'));local body=f:read('*a');f:close();cb(body,ok and 0 or code or 1)
end
local result,code,raw
Store.read(runner,function(ok,body)result,raw=ok,body end);check(result and raw==nil,'Missing file reads as defaults')
local literal="app:x|printf '$(no-command)'"
Store.write(runner,{list={'kitty',literal}},function(ok)result=ok end,{missing=true});check(result,'Missing file CAS creates the pin file')
Store.read(runner,function(ok,body)result,raw=ok,body end);check(result and raw=='kitty\n'..literal..'\n','Read preserves literal contents and trailing newline')
Store.write(runner,{list={'foot'}},function(ok,why)result,code=ok,why end,{body='wrong'});check(not result and code=='stale','Disk CAS refuses concurrent edits')
Store.write(runner,{list={'foot'}},function(ok)result=ok end,{body=raw});check(result,'Matching disk CAS commits')
local f=assert(io.open(temp..'/.config/beskar/dock.bak','rb'));check(f:read('*a')==raw,'Backup holds the previous exact contents');f:close()
Store.write(runner,{default=true},function(ok)result=ok end,{body='foot\n'});check(result and io.open(temp..'/.config/beskar/dock')==nil,'Default mode removes only the owned pin file')
local listing=assert(io.popen('ls -A '..quote(temp..'/.config/beskar'))):read('*a');check(not listing:find('tmp') and not listing:find('expect'),'No temporary files remain')
assert(os.execute('rm -rf '..quote(temp)))
print('pins-profile: '..n..' focused checks passed')
