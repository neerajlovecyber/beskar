-- Run from the repository root: lua tests/session-menu.lua
-- Commands and lock requests are captured; this never changes the real session.
package.loaded.topbar_hooks = { handlers = {}, call = function() end, emit = function() end }   -- session_menu.luau registers its handlers with the frame
local passed = 0
local function check(value, message)
    assert(value, message)
    passed = passed + 1
end
local function controller()
    local state = { visible = false, handlers = {}, jobs = {}, commands = {}, locks = {} }
    fact, text, model = { ses_mode = 0, ses_sel = 0, ses_index = 0 }, {}, {}
    function on(name, fn) state.handlers[name] = fn end
    function after(ms, fn)
        local job = { ms = ms, fn = fn }
        state.jobs[#state.jobs + 1] = job
        return job
    end
    function cancel(job) job.canceled = true end
    function emit(name, value)
        error("Controller must call its own handlers directly: " .. name)
    end
    function run(command, args) state.commands[#state.commands + 1] = { command, args } end
    sys = { call = function(...) state.locks[#state.locks + 1] = { ... } end }
    local open_hook, close_hook
    local function close()
        state.visible = false
        close_hook()
    end
    dofile("shell/session_menu.luau")(
        { height = function(h) state.height = h end, close = close },
        function(fn) open_hook = fn end,
        function() return state.visible end,
        function(fn) close_hook = fn end)
    function state.open() state.visible = true; open_hook() end
    state.close = close
    function state.send(name, value) state.handlers[name](value) end
    function state.flush()
        local jobs = state.jobs
        state.jobs = {}
        for _, job in ipairs(jobs) do if not job.canceled then job.fn() end end
    end
    return state
end

local s = controller()
s.open()
check(#model.ses_actions == 5 and s.height == 250, "Five actions reuse the existing panel height")
check(fact.ses_mode == 0 and fact.ses_index == 0, "Opening defaults to the chooser and Lock")
check(#s.jobs == 0, "Browsing does not start a shutdown countdown")
s.send("ses_move", -1)
check(fact.ses_index == 4, "Previous wraps to Shut Down")
s.send("ses_move", 1)
check(fact.ses_index == 0, "Next wraps back to Lock")
s.send("ses_move", 3)
check(fact.ses_index == 3 and text.ses_detail == "Restart the computer", "Navigation updates the selected description")
s.send("ses_enter")
check(fact.ses_mode == 1 and fact.ses_kind == 1 and fact.ses_sel == 0, "Restart enters confirmation on Cancel")
check(#s.commands == 0 and #s.locks == 0, "Choosing Restart does not execute it")
s.send("ses_enter")
check(s.visible and fact.ses_mode == 0 and fact.ses_index == 3, "Cancel returns to the selected menu action")
s.flush()
check(#s.commands == 0, "Canceled countdown cannot execute later")
s.send("ses_enter")
s.send("ses_move", 1)
s.send("ses_enter")
check(not s.visible and s.commands[1][1] == "systemctl" and s.commands[1][2][1] == "reboot", "Explicit confirmation dispatches reboot")
s.send("confirm_action")
check(#s.commands == 1, "Hidden panel ignores stale confirmation events")

for kind, expected in pairs({ [0] = "poweroff", [1] = "reboot", [2] = "msg", [3] = "suspend" }) do
    s = controller()
    s.send("set_kind", { k = kind })
    s.open()
    check(fact.ses_mode == 1 and fact.ses_kind == kind, "Legacy typed confirmation preserves kind " .. kind)
    s.send("ses_move", 1)
    s.send("ses_enter")
    check(s.commands[1][2][1] == expected, "Kind dispatches its own command " .. kind)
    if kind == 2 then check(s.commands[1][2][4] == "--skip-confirmation", "Logout uses niri rather than another compositor") end
end

s = controller(); s.open(); s.send("ses_choose", 1)
check(fact.ses_kind == 3 and fact.ses_mode == 1 and #s.jobs == 0, "Sleep confirms without an automatic timer")
s.send("ses_cancel")
check(s.visible and fact.ses_mode == 0, "Escape from confirmation returns to the chooser")
s.send("ses_cancel")
check(not s.visible, "Escape from the chooser closes it")

s = controller(); s.open(); s.send("ses_choose", 0)
check(not s.visible and #s.commands == 0, "Lock closes the menu without a system power command")
s.flush()
check(s.locks[1][1] == "say" and s.locks[1][2] == "lock" and s.locks[1][3] == "fact locked true", "Lock routes to the existing locker")
s = controller(); s.open(); s.send("ses_choose", 99); s.send("set_kind", 99)
check(fact.ses_mode == 0 and #s.commands == 0, "Unknown action IDs are inert")
s.send("ses_choose", 4); s.close(); s.flush()
check(#s.commands == 0, "Closing a confirmation cancels its countdown")
s = controller(); s.open(); s.send("ses_choose", 4)
for _ = 1, 60 do s.flush() end
check(not s.visible and #s.commands == 1 and s.commands[1][2][1] == "poweroff", "Existing explicit shutdown confirmation countdown fires once")

print("Session menu: " .. passed .. " checks passed")
