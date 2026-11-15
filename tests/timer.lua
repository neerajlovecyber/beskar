-- Focused timer tests with fake clocks, storage and sockets; no real session changes.
package.path = "shell/?.luau;" .. package.path
local Timer = dofile("shell/timer_state.luau")
local passed = 0
local function check(value, message) assert(value, message); passed = passed + 1 end
local function copy(value)
    if type(value) ~= "table" then return value end
    local out = {}; for k, v in pairs(value) do out[k] = copy(v) end; return out
end
for input, seconds in pairs({ ["25"] = 1500, ["1h30"] = 5400, ["1h30m"] = 5400, ["1h2m3s"] = 3723, ["0:30"] = 30, ["45s"] = 45, ["24h"] = 86400, [" 5 m "] = 300 }) do
    check(Timer.parse(input) == seconds, "Parse " .. input)
end
for _, input in ipairs({ "", "0", "-2", "0s", "24h1s", "1m1h", "1s2s", "25:99", "abc5m", "1.5", "5m junk", "99999999999999999999999999999999999999999" }) do
    check(Timer.parse(input) == nil, "Reject " .. input)
end
local state = Timer.new()
check(Timer.apply(state, "start", 120, 1000) and state.deadline == 1120, "Start with epoch deadline")
check(Timer.remaining(state, 1041) == 79, "Delayed callbacks do not accumulate drift")
check(not Timer.apply(state, "tick", nil, 1041) and state.revision == 1, "Display ticks do not revise storage")
Timer.apply(state, "pause", nil, 1050)
check(state.status == "paused" and state.remaining == 70 and state.deadline == 0, "Pause preserves remaining time")
local restored = Timer.new(state)
check(Timer.remaining(restored, 9000) == 70, "A paused restart stays paused")
Timer.apply(restored, "resume", nil, 9000)
check(restored.deadline == 9070, "Resume computes a fresh deadline")
local changed, finished = Timer.apply(restored, "tick", nil, 20000)
check(changed and finished and restored.status == "done", "Sleep counts toward timer and finishes after resume")
local _, duplicate = Timer.apply(restored, "tick", nil, 20001)
check(not duplicate and not Timer.apply(Timer.new(restored), "tick", nil, 30000), "Saved completion is not repeated")
Timer.apply(restored, "dismiss", nil, 30000)
check(restored.status == "idle" and restored.remaining == 120, "Dismiss resets to last duration")
Timer.apply(restored, "start", 5, 100)
local rev = restored.revision
local _, due = Timer.apply(restored, "pause", nil, 105)
check(due and restored.status == "done" and restored.revision == rev + 1, "Pause at deadline completes instead")
Timer.apply(restored, "start", 5, 100)
check(Timer.remaining(restored, 90) == 5, "Backward wall clock adjustment cannot exceed chosen duration")
Timer.apply(restored, "cancel", nil, 101)
check(restored.status == "idle" and restored.deadline == 0, "Cancel clears deadline")
for _, saved in ipairs({ {}, { version = 2 }, { version = 1, revision = 0, status = "paused", duration = 5, remaining = 0, deadline = 0 }, { version = 1, revision = 0, status = "running", duration = 5, remaining = 5, deadline = 0 } }) do
    check(Timer.new(saved) == nil, "Reject invalid saved timer")
end
check(Timer.format(3723) == "1:02:03" and Timer.format(0) == "0:00", "Format hour and zero readouts")
local function owner(saved, unreadable)
    local h = { now = 1000, files = { ["timer.json"] = copy(saved) }, writes = 0, says = {}, events = {}, jobs = {}, handlers = {}, fail_write = false }
    local env = setmetatable({ fact = {}, text = {}, require = function(n) if n == "timer_state" then return Timer end; return require(n) end,
        os = { time = function() return h.now end },
        on = function(n, fn) h.handlers[n] = fn end,
        emit = function(n, v) h.events[#h.events + 1] = { n, v } end,
        after = function(ms, fn) local job = { ms = ms, fn = fn }; h.jobs[#h.jobs + 1] = job; return job end,
        cancel = function(job) job.canceled = true end,
        sys = { ask = function(_, name) if unreadable then error("unreadable") end; return copy(h.files[name]) end,
            call = function(service, name, value)
                if service == "files.write" then
                    if h.fail_write then error("disk full") end
                    h.files[name] = copy(value); h.writes = h.writes + 1
                else h.says[#h.says + 1] = { name, value } end
            end }
    }, { __index = _G })
    h.fact, h.text = env.fact, env.text
    assert(loadfile("shell/activities.luau", "t", env))()
    function h:fire(n, v) assert(self.handlers[n], n)(v) end
    function h:advance(seconds)
        self.now = self.now + seconds
        local jobs = self.jobs; self.jobs = {}
        for _, job in ipairs(jobs) do if not job.canceled then job.fn() end end
    end
    return h
end
local h = owner()
check(h.writes == 1 and h.fact.ready, "Create one initial snapshot")
h:fire("start", 60)
local writes = h.writes
h:advance(17)
check(h.fact.timer_remaining == 43 and h.writes == writes, "Owner ticks derive deadline without disk writes")
h:fire("pause")
check(h.files["timer.json"].status == "paused", "Persist pause immediately")
local recovered = owner(h.files["timer.json"])
check(recovered.fact.timer_state == 2 and recovered.fact.timer_remaining == 43 and #recovered.jobs == 0, "Paused recovery has no active timer")
h:fire("resume"); h:advance(50)
check(h.fact.timer_state == 3 and #h.events == 1 and h.events[1][1] == "Topbar.timer_finished", "Finish once through typed frame event")
check(h.files["timer.json"].status == "done", "Save terminal state before completion")
h:advance(30); h:fire("pause")
check(#h.events == 1, "Repeated callbacks cannot duplicate completion")
local finished_owner = owner(h.files["timer.json"])
check(#finished_owner.events == 0 and #finished_owner.jobs == 0, "Restart after completion does not alert again")
h:fire("start", 5); h.fail_write = true; h:advance(6)
check(h.fact.timer_state == 3 and #h.events == 1 and h.text.storage_status ~= "", "Failed persistence retains completion without alert duplication")
h.fail_write = false; h:advance(2)
check(#h.events == 2 and h.files["timer.json"].status == "done", "Retry saves and delivers completion once")
local malformed = owner({ version = 99 })
check(not malformed.fact.ready and malformed.writes == 0, "Malformed state is preserved instead of overwritten")
check(not owner(nil, true).fact.ready, "Unreadable storage leaves timer unavailable")
local overdue = Timer.new(); Timer.apply(overdue, "start", 5, 100)
local due_owner = owner(overdue)
check(due_owner.fact.timer_state == 3 and #due_owner.events == 1, "Restart with an expired running deadline completes once")

local function panel()
    local h = { handlers = {}, events = {}, visible = true, focused = nil }
    local env = setmetatable({ fact = { ["Activities.ready"] = true, ["Activities.timer_state"] = 0, tm_focus = -1 }, text = { tm_duration = "25" },
        on = function(n, fn) h.handlers[n] = fn end,
        after = function(ms, fn) h.timers = h.timers or {}; h.timers[#h.timers + 1] = fn end,
        emit = function(n, v) h.events[#h.events + 1] = { n, v } end }, { __index = _G })
    -- the field is the Keys scene's (keys_text.luau) and focus goes through topbar_hooks: both stand in as the plain env here
    env.require = function(n)
        if n == "keys_text" then return env.text end
        if n == "topbar_hooks" then return { focus = function(f) h.focused = f end } end
        return Timer
    end
    assert(loadfile("shell/timer_panel.luau", "t", env))()({ height = function(n) h.height = n end, close = function() h.visible = false end },
        function(fn) h.open = fn end, function() return h.visible end, function(fn) h.close = fn end)
    h.fact, h.text = env.fact, env.text
    function h:fire(n, value) self.handlers[n](value) end
    return h
end
local p = panel(); p.open()
check(p.focused == "tm_duration" and p.height == 350, "Idle opens with duration field focused")
p:fire("tm_activate"); p:fire("tm_move", 1); p:fire("tm_activate")
check(#p.events == 0, "The release of the Enter that opened the panel does nothing")
for _, fn in ipairs(p.timers) do fn() end            -- 350 ms later key releases count
p:fire("tm_move", -1)
check(p.fact.tm_focus == -1 and p.focused == "tm_duration", "Shift Tab from the first preset returns to the duration field")
p:fire("tm_submit"); p.fact["Activities.timer_state"] = 1; p:fire("tm_activate")
check(#p.events == 1 and p.events[1][1] == "Activities.start", "Submitting and releasing Enter starts without immediately pausing")
p:fire("tm_activate")
check(p.events[2][1] == "Activities.pause", "Next Enter pauses active timer")
p.fact["Activities.timer_state"] = 2; p:fire("tm_activate")
check(p.events[3][1] == "Activities.resume", "Next Enter resumes paused timer")
p:fire("tm_move", -1)
check(p.fact.tm_focus == 1, "Shift Tab wraps across active controls")
p:fire("tm_activate")
check(p.events[4][1] == "Activities.cancel", "Selected secondary action cancels")
p.fact["Activities.timer_state"] = 0; p.text.tm_duration = "bad"; p:fire("text:Keys.tm_duration"); p:fire("tm_primary")
check(#p.events == 4 and not p.fact.tm_valid and p.focused == "tm_duration", "Invalid custom duration does not dispatch")
p:fire("tm_preset", 300)
check(p.text.tm_duration == "5" and p.fact.tm_seconds == 300, "Preset updates the existing duration input")
p:fire("tm_move", 1)
check(p.fact.tm_focus == 1, "Tab reaches the secondary idle action")
p:fire("tm_move", 1)
check(p.fact.tm_focus == -1 and p.focused == "tm_duration", "Tab cycles back to the input")

local function client()
    local h = { now = 1000, requests = {}, jobs = {}, handlers = {}, says = {}, fail = false }
    local env = setmetatable({ fact = {}, text = {}, require = function() return Timer end,
        os = { time = function() return h.now end }, json = { decode = copy },
        on = function(n, fn) h.handlers[n] = fn end,
        after = function(ms, fn) local j = { ms = ms, fn = fn }; h.jobs[#h.jobs + 1] = j; return j end,
        every = function(ms, fn) local j = { ms = ms, fn = fn }; h.jobs[#h.jobs + 1] = j; return j end,
        cancel = function(j) j.canceled = true end,
        run = function(_, _, cb) h.requests[#h.requests + 1] = cb end,
        sys = { ask = function(_, name) if name == "HOME" then return "/fake" end end,
            call = function(_, scene, cmd) if h.fail then error("disconnected") end; h.says[#h.says + 1] = { scene, cmd } end }
    }, { __index = _G })
    h.enable = assert(loadfile("shell/timer_client.luau", "t", env))()()
    h.fact, h.text = env.fact, env.text
    return h
end
local c = client()
check(#c.requests == 0 and #c.jobs == 0, "No timer widget means no timer bridge reads or polling")
c.enable(true)
local running = Timer.new(); Timer.apply(running, "start", 60, 1000)
c.requests[1](running, 0)
check(c.text.tw_time == "1:00" and c.fact.tw_state == 1, "Widget uses owner's saved deadline")
c.now = 1020
local display_jobs = {}; for _, job in ipairs(c.jobs) do display_jobs[#display_jobs + 1] = job end
for _, job in ipairs(display_jobs) do if job.ms == 1000 and not job.canceled then job.completed = true; job.fn() end end
check(c.text.tw_time == "0:40" and #c.requests == 1, "Widget display ticks need no socket or disk reads")
c.handlers.tw_primary()
check(c.says[#c.says][2] == "emit pause", "Widget pause reaches the owner")
c.enable(false)
local active = 0; for _, job in ipairs(c.jobs) do if not job.canceled and not job.completed then active = active + 1 end end
check(active == 0, "Removing or hiding timer widget stops its timers")
c.handlers.timer_changed(99)
check(#c.requests == 1, "Hidden widgets ignore timer transition reads")
c.enable(true)
check(#c.requests == 2, "Re-enabling refreshes the snapshot")
print("timer: " .. passed .. " checks passed")
