-- Personal-content invariants, isolated owner persistence, and widget restart protocol.
package.path = "shell/?.luau;" .. package.path
local Store = require("personal_store")
local count = 0
local function check(v, why) assert(v, why); count = count + 1 end
local function equal(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for k,v in pairs(a) do if not equal(v, b[k]) then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
end
local s = assert(Store.new())
local function apply(op,p) return s:apply(op,p,"2026-11-13 12:34") end
check(apply("add_note"), "Create note")
local first = s.data.notes[1].id
check(apply("edit_note", { id=first, text="Research\nSecond line — 日本語" }), "Unicode multiline edit")
check(s.data.notes[1].modified == "2026-11-13 12:34", "Modification time")
for i=1,100 do apply("edit_note", {id=first, text="Draft "..i}) end
check(#s.history == 2, "Typing a note coalesces into one content Undo")
check(apply("undo") and s.data.notes[1].text == "", "Undo returns to start of typing")
apply("edit_note", {id=first, text="Keep me"})
apply("add_note"); local second=s.data.notes[1].id
apply("remove_note", first)
check(apply("undo"), "Undo removal")
check(s.data.notes[2].id == first and s.data.notes[2].text == "Keep me", "Undo restores the right ID and content")
local next_id = s.data.next_id
apply("undo"); apply("add_note")
check(s.data.notes[1].id >= next_id, "Undo never reuses an exposed ID")
check(Store.featured(s.data).id == s.data.notes[1].id, "New note becomes widget preview")
apply("edit_note", {id=first, text="Most recently edited"})
check(Store.featured(s.data).id == first, "Editing an older note updates the widget preview")
local snap=s:snapshot(); snap.notes[1].text="External mutation"
check(s.data.notes[1].text ~= snap.notes[1].text, "Snapshots don't mutate the store")
check(not apply("edit_note", {id=999999, text="stale"}), "Stale editor ID cannot create a note")
check(not apply("edit_note", {id=second, text=string.rep("x",4097)}), "Reject oversized input")
for _,t in ipairs({"One", "Two", "Three"}) do apply("add_task", {text=t}) end
local one,two,three=s.data.tasks[1].id,s.data.tasks[2].id,s.data.tasks[3].id
apply("toggle_task",two)
check(s.data.tasks[2].done, "Complete a to-do")
apply("move_task",{id=three,delta=-1})
check(s.data.tasks[1].id == three and s.data.tasks[2].id==two, "Reorder active rows across completed rows")
apply("remove_task",two); apply("undo")
check(s.data.tasks[2].id==two and s.data.tasks[2].done, "Undo completed-item removal")
check(not apply("add_task",{text=" \n "}), "Reject empty to-do")
check(not apply("add_task",{text="one\ntwo"}), "To-do is one line")
local restored=assert(Store.new(s:snapshot()))
check(equal(restored:snapshot(),s:snapshot()), "Restart preserves data, order, IDs, revision and time")
for _,bad in ipairs({false, "broken", {version=99}, {version=1,revision=0,next_id=1,notes={},tasks={{id=1,text="x",modified="",done=false}}}}) do
    check(Store.new(bad)==nil, "Invalid saved data is rejected")
end
check(Store.new({version=1,revision=0,next_id=1,notes={bad="row"},tasks={}})==nil, "Non-array content cannot silently disappear")
check(Store.new({version=1,revision=0,next_id=1,notes={},tasks={},featured_id=8})==nil, "Reject a dangling featured note")
local bounded=assert(Store.new())
for i=1,Store.MAX_NOTES do bounded:apply("add_note",nil,"") end
check(not bounded:apply("add_note",nil,""), "Note limit")
for i=1,Store.MAX_TASKS do bounded:apply("add_task",{text="Task"},"") end
check(not bounded:apply("add_task",{text="extra"},""), "To-do limit")
check(#bounded.history==20, "Undo history bounded")

-- Run the real owner with an isolated files service and deterministic timers.
local function owner(saved,read_failure)
    local h={handlers={},timers={},writes={},says={},fact={},text={},disk=saved,fail=false}
    local env=setmetatable({fact=h.fact,text=h.text,require=require,json={encode=function(v) return v end},
        sys={ask=function() if read_failure then error("broken JSON") end; return saved end,
            call=function(service,a,b)
                if service=="files.write" then if h.fail then error("disk full") end; h.writes[#h.writes+1]=b; h.disk=b
                elseif service=="say" then h.says[#h.says+1]={a,b} end
            end,
            watch=function(_,f) f({year=2026,month=11,day=13,hour=12,minute=34}) end},
        on=function(n,f) h.handlers[n]=f end,
        after=function(_,f) h.timers[#h.timers+1]=f; return #h.timers end,
        cancel=function(i) h.timers[i]=false end}, {__index=_G})
    assert(loadfile("shell/personal.luau","t",env))()
    function h:fire(n,p) assert(self.handlers[n],n)(p) end
    function h:drain() local pending=self.timers; self.timers={}; for _,f in ipairs(pending) do if f then f() end end end
    return h
end
local h=owner(nil)
check(h.fact.ready and #h.writes==1, "Fresh owner creates one atomic snapshot")
h:fire("add_note"); local id=h.text.snapshot.notes[1].id
for i=1,60 do h:fire("edit_note",{id=id,text="Version "..i}) end
check(#h.writes==1, "Rapid changes do not write each keystroke")
h:drain()
check(#h.writes==2 and h.disk.notes[1].text=="Version 60", "Debounce persists newest content")
h.fail=true; h:fire("edit_note",{id=id,text="Unsaved"}); h:drain()
check(h.text.status:find("Could not save") and h.text.snapshot.notes[1].text=="Unsaved", "Failed save retains in-memory edits with status")
h.fail=false; h:drain()
check(h.disk.notes[1].text=="Unsaved", "Retry persists changes")
local resumed=owner(h.disk)
check(resumed.text.snapshot.notes[1].id==id and resumed.text.snapshot.notes[1].text=="Unsaved", "Owner restart restores content")
local before=#resumed.says
resumed:fire("resync",-1)
check(#resumed.says==before+1 and resumed.says[#resumed.says][1]=="widgets", "Widget restart requests current snapshot")
resumed:fire("resync",resumed.text.snapshot.revision)
check(#resumed.says==before+1, "Synced widget avoids redundant reads")
local broken=owner(nil,true)
check(not broken.fact.ready and #broken.writes==0 and broken.text.status:find("kept"), "Read failure never overwrites stored content")
local malformed=owner(false)
check(not malformed.fact.ready and #malformed.writes==0, "Malformed root never becomes empty saved content")
-- Bridge queues one follow-up read and validates stale replies without ever writing content.
local client={handlers={},reads={},says={},fact={},text={},model={},timers={}}
local client_env=setmetatable({fact=client.fact,text=client.text,model=client.model,require=require,
    json={decode=function(v) return v end},
    sys={ask=function(_,name) return name=="HOME" and "/fake home" or "/data home" end,
        call=function(service,scene,command)
            check(service=="say", "Widget bridge has no content writer")
            client.says[#client.says+1]={scene,command}
        end},
    on=function(n,f) client.handlers[n]=f end,
    after=function(_,f) client.timers[#client.timers+1]=f end,
    every=function(_,f) client.resync=f end,
    run=function(command,args,cb) client.reads[#client.reads+1]={command=command,args=args,cb=cb} end}, {__index=_G})
assert(loadfile("shell/personal_client.luau","t",client_env))()()
client.timers[1]()
check(client.says[1][2]=="emit resync -1", "Widget startup requests a full snapshot")
client.handlers.personal_changed(1); client.handlers.personal_changed(2); client.handlers.personal_changed(3)
check(#client.reads==1, "Only one widget snapshot read can be in flight")
check(client.reads[1].command=="cat" and client.reads[1].args[1]=="/data home/pleamar/personal/content.json", "Data-home path is passed as one argument")
client.reads[1].cb(h.disk,0)
check(#client.reads==2, "Overlapping revisions coalesce to one follow-up read")
check(client.text.personal_note=="Unsaved", "Bridge renders the saved featured note")
local stale=assert(Store.new()):snapshot()
client.reads[2].cb(stale,0)
check(client.text.personal_note=="Unsaved", "An older read cannot replace newer widget content")
client.resync()
check(client.says[#client.says][2]=="emit resync "..h.disk.revision, "Periodic resync carries loaded revision")
client.handlers.personal_toggle(2)
check(client.says[#client.says][1]=="personal" and client.says[#client.says][2]=="emit toggle_task 2", "Checkbox delegates mutation to owner")
print("Personal: "..count.." checks passed")
