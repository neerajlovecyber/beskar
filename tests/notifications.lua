-- Focused notification overflow regression checks; no D-Bus or user history is used.
package.path = "shell/?.luau;" .. package.path
local passed = 0
local function check(value, message) assert(value, message); passed = passed + 1 end
local function fixture(grouped)
    local h = { fact = {["Settings.group_apps"] = grouped}, model = {}, handlers = {}, calls = {} }
    local history = {}
    for i = 1, 5 do history[i] = {title="Earlier "..i, body="Saved", time=os.time()} end
    local env = setmetatable({fact=h.fact, model=h.model, text={},
        on=function(name, fn) h.handlers[name]=fn end,
        after=function() return 1 end, every=function() end, cancel=function() end,
        emit=function() end, log=function() end,
        sys={ask=function(_, path) if path=="history.json" then return {items=history} end end,
            call=function(name, ...) h.calls[#h.calls+1]={name, ...} end,
            watch=function(name, fn) assert(name=="notifications"); h.receive=fn end}}, {__index=_G})
    assert(loadfile("shell/notif.luau", "t", env))()({height=function(n) h.height=n end}, function() end, function() return true end, function() end)
    function h:send(count, same_app)
        local rows = {}
        for i=1,count do rows[i]={id=i,app=same_app and "Mail" or "App "..i,title="Message "..i,body="Body",time=os.time()} end
        self.receive(rows)
    end
    return h
end
local h=fixture(false)
h:send(40)
check(h.height<=720, "A large inbox cannot grow beyond the notification surface")
check(h.fact.live_h==3520 and h.fact.notif_count==40, "Every waiting notification remains reachable")
check(#h.model.rows<=16 and h.model.rows[1].id==1, "Only the current scrolling window is rendered")
check(#h.model.past==5, "Earlier history is retained when the inbox overflows")
h.handlers.list_scrolled(1500)
local contains=false;for _,r in ipairs(h.model.rows) do if r.id==20 then contains=true end end
check(contains and h.model.rows[1].id>1, "Scrolling loads notifications beyond the previous fourteen-row limit")
h.handlers.list_scrolled(4000)
check(h.model.rows[#h.model.rows].id==40, "The final waiting card is reachable above history")
h.handlers.dismiss_notice(40)
check(h.calls[#h.calls][1]=="notifications.dismiss" and h.calls[#h.calls][2]==40, "A scrolled card dismisses its own notification")
h:send(1)
check(h.height<720 and h.model.rows[1].id==1, "Shrinking the inbox clamps a previously deep scroll")
h:send(0)
check(#h.model.rows==0 and #h.model.past==5 and h.height<720, "History alone uses a compact scrolling panel")
h.handlers.clear_past()
check(h.height==190 and #h.model.past==0, "Clearing the final history restores the empty state")
local groups=fixture(true)
groups:send(40,true)
check(#groups.model.rows==1 and groups.model.rows[1].kind==1, "A collapsed app remains a single stack")
groups.handlers.group_toggle(0)
check(groups.fact.live_h==3552 and groups.height<=720, "Expanding a large stack stays within the bounded panel")
groups.handlers.list_scrolled(3300)
check(groups.model.rows[#groups.model.rows].id>30, "Expanded groups scroll through all of their notifications")
groups.handlers.group_toggle(0)
check(#groups.model.rows==1 and groups.model.rows[1].kind==1 and groups.height<720, "Collapsing a scrolled stack clamps to its remaining content")
local mixed=fixture(true)
local input={}
for i=1,40 do input[#input+1]={id=i,app="App "..math.ceil(i/2),title="Message "..i,time=os.time()} end
mixed.receive(input)
for key=0,19 do mixed.handlers.group_toggle(key) end
mixed.handlers.list_scrolled(2000)
local rows=mixed.model.rows
check(#rows<=16 and rows[1].y<=2000 and rows[#rows].y+rows[#rows].h>=2642, "Variable-height group headers cannot leave gaps in the viewport")
print("Notifications: "..passed.." focused checks passed")
