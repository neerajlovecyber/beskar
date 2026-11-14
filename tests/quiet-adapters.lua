-- Quiet-policy adapter checks: notif.luau (delivery, rules, store) and activities.luau (temporary modes), with fake services.
package.path = "shell/?.luau;" .. package.path
local passed = 0
local function check(value, message) assert(value, message); passed = passed + 1 end

-- ── Notifications ────────────────────────────────────────────────
local function fixture(opts)
    opts = opts or {}
    local h = { fact = { ["Settings.group_apps"] = false, dnd = false }, model = {}, text = {}, handlers = {}, calls = {}, emits = {},
        files = opts.files or {}, timers = {}, fail_write = false }
    local env = setmetatable({ fact = h.fact, model = h.model, text = h.text,
        on = function(name, fn) h.handlers[name] = fn end,
        after = function(ms, fn) h.timers[#h.timers + 1] = fn; return #h.timers end,
        every = function(ms, fn) h.tick = fn end, cancel = function() end,
        emit = function(name, v) h.emits[#h.emits + 1] = { name, v } end, log = function() end,
        sys = { ask = function(_, path) return h.files[path] end,
            call = function(name, ...)
                h.calls[#h.calls + 1] = { name, ... }
                if name == "files.write" then
                    if h.fail_write then error("disk full") end
                    h.files[select(1, ...)] = select(2, ...)
                end
            end,
            watch = function(name, fn) assert(name == "notifications", "no new watchers: " .. name); h.receive = fn end } }, { __index = _G })
    h.opened = function() end
    assert(loadfile("shell/notif.luau", "t", env))()({ height = function() end }, function(fn) h.opened = fn end, function() return false end, function() end)
    function h:send(list) self.receive(list) end
    function h:flush() local t = self.timers; self.timers = {}; for _, fn in ipairs(t) do fn() end end
    function h:banners() local n = 0; for _, e in ipairs(self.emits) do if e[1] == "Topbar.panel_open" then n = n + 1 end end; return n end
    return h
end
local function note(id, app, extra)
    local n = { id = id, app = app, title = "T" .. id, body = "B", time = os.time(), urgency = 1 }
    for k, v in pairs(extra or {}) do n[k] = v end
    return n
end

local h = fixture()
h:send({})                                         -- the first list is not news
check(h.fact.quiet == false and h.text.quiet_status == "", "starts not quiet")
h:send({ note(1, "Mail") })
check(h:banners() == 1, "a normal notification raises a banner")

-- manual DND stays manual; policies layer on top and end without touching it
h = fixture(); h:send({})
h.handlers.set_dnd(true)
check(h.fact.dnd == true and h.fact.quiet == true and h.text.quiet_label == "Do Not Disturb", "manual DND is quiet")
h.fact["Activities.quiet_focus"] = true; h.handlers["fact:Activities.quiet_focus"]()
check(h.fact.dnd == true and h.text.quiet_label == "Do Not Disturb · Focus", "a policy adds a reason, never rewrites dnd")
h.fact["Activities.quiet_focus"] = false; h.handlers["fact:Activities.quiet_focus"]()
check(h.fact.dnd == true and h.fact.quiet == true, "ending the policy keeps the manual choice")
h.handlers.set_dnd(false)
check(h.fact.quiet == false and h.fact.dnd == false, "manual off ends quiet when nothing else holds it")
h.fact["Activities.quiet_game"] = true; h.handlers["fact:Activities.quiet_game"]()
h.handlers.set_dnd(true); h.handlers.set_dnd(false)
check(h.fact.quiet == true and h.fact.dnd == false, "manual changes during a mode survive, and the mode keeps its quiet")
h.fact["Activities.quiet_game"] = false; h.handlers["fact:Activities.quiet_game"]()
check(h.fact.quiet == false and h.fact.dnd == false, "ending the mode restores the user's (off) choice")

-- quiet suppresses banners but not delivery; held counter; reset when the centre opens
h = fixture(); h:send({})
h.handlers.set_dnd(true)
h:send({ note(1, "Mail") })
check(h:banners() == 0 and h.fact.notif_count == 1 and #h.model.rows == 1, "quiet: no banner, still listed and counted")
check(h.fact.held_count == 1 and h.text.quiet_status:find("1 held"), "held count appears in the status")
h:send({ note(2, "Mail"), note(1, "Mail") })
check(h.fact.held_count == 2, "each held banner is counted once")
h:send({ note(2, "Mail"), note(1, "Mail") })
check(h.fact.held_count == 2, "a repeated list adds nothing")
h.opened()
check(h.fact.held_count == 0, "opening the centre clears the held count")
h.handlers.set_dnd(false)
check(h.text.quiet_status == "", "status clears with quiet")
h:send({ note(3, "Timer"), note(2, "Mail"), note(1, "Mail") })
check(h:banners() == 0, "a Timer notification still never raises a banner")

-- quiet starting hides a visible banner
h = fixture(); h:send({}); h:send({ note(1, "Mail") })
local before = #h.emits
h.fact["Activities.quiet_presentation"] = true; h.handlers["fact:Activities.quiet_presentation"]()
local closed = false
for i = before + 1, #h.emits do if h.emits[i][1] == "Topbar.panel_close" then closed = true end end
check(closed, "an explicit mode hides the banner already showing")

-- quiet hours come from Settings facts and the existing 30 s tick; missing facts are harmless
h = fixture(); h:send({})
local now = os.date("*t"); local minute = now.hour * 60 + now.min
h.fact["Settings.quiet_enabled"] = true
h.fact["Settings.quiet_start"] = (minute - 1) % 1440
h.fact["Settings.quiet_end"] = (minute + 5) % 1440
h.tick()
check(h.fact.quiet == true and h.text.quiet_label == "Quiet hours", "the tick starts quiet hours inside the window")
h.fact["Settings.quiet_enabled"] = false; h.tick()
check(h.fact.quiet == false, "disabling hours ends it on the next tick")
h.fact["Settings.quiet_start"], h.fact["Settings.quiet_end"] = (minute + 10) % 1440, (minute + 20) % 1440
h.fact["Settings.quiet_enabled"] = true; h.tick()
check(h.fact.quiet == false, "outside the window is not quiet")
h = fixture(); h.tick()
check(h.fact.quiet == false, "no Settings quiet facts means not quiet")

-- per-app rules
h = fixture(); h:send({})
h.handlers.set_app_rule({ app = "Chat", mode = "no_banner" })
h:send({ note(1, "Chat") })
check(h:banners() == 0 and h.fact.notif_count == 1 and h.fact.held_count == 1 and #h.model.toast == 0, "no_banner: listed and counted, no banner, not in the banner model")
h.handlers.set_app_rule({ app = "Chat", mode = "muted" })
check(h.fact.notif_count == 0, "muted: not counted on the bell")
check(h.calls[#h.calls][1] == "say" and h.calls[#h.calls][3]:find("notif_count 0"), "the lock screen count follows")
check(#h.model.rows == 1, "muted notifications stay in the centre")
h:send({ note(2, "Mail"), note(1, "Chat") })
check(h:banners() == 1 and h.model.toast[1].app == "Mail", "the banner shows the newest app that may banner")
h:send({ note(3, "Chat"), note(2, "Mail"), note(1, "Chat") })
check(h.model.toast[1].id == 2, "a newer muted notification does not take the banner card")
check(h.fact.rules_n == 1 and h.model.quiet_apps[1].app == "Chat" and h.model.quiet_apps[1].mode == 2 and h.model.quiet_apps[1].rule, "Settings model lists the rule")
check(h.model.quiet_apps[2].app == "Mail" and h.model.quiet_apps[2].mode == 0 and not h.model.quiet_apps[2].rule, "and recent senders without one")
h:flush()
check(h.files["quiet.json"] and h.files["quiet.json"].apps[1].app == "Chat" and h.files["quiet.json"].apps[1].mode == "muted", "rules are saved through the files service")
h.handlers.cycle_app_rule("Chat")
check(h.fact.rules_n == 0, "cycling muted returns to normal")
h.handlers.set_app_rule({ app = "A", mode = "muted" }); h.handlers.set_app_rule({ app = "B", mode = "no_banner" })
h.handlers.clear_app_rule("A"); check(h.fact.rules_n == 1, "clear_app_rule removes one")
h.handlers.clear_app_rules(); check(h.fact.rules_n == 0, "clear_app_rules removes all")
h.handlers.set_app_rule({ app = "", mode = "muted" })
check(h.text.rules_status ~= "" and h.fact.rules_n == 0, "an unusable name reports a status and changes nothing")
h.handlers.set_app_rule("Chat"); check(h.text.rules_status:find("needs"), "a malformed payload is reported")
-- a rule applies on restart
h:flush()
local again
h = fixture(); h.handlers.set_app_rule({ app = "Chat", mode = "muted" }); h:flush()
again = fixture({ files = h.files }); again:send({}); again:send({ note(1, "Chat") })
check(again:banners() == 0 and again.fact.notif_count == 0, "a saved rule is honoured after a restart")
-- store failures retry and never lose the in-memory rule
h = fixture(); h.fail_write = true
h.handlers.set_app_rule({ app = "Chat", mode = "muted" }); h:flush()
check(h.text.rules_status:find("Retrying") and h.fact.rules_n == 1, "a failed save reports and keeps the rule")
h.fail_write = false; h:flush()
check(h.text.rules_status == "" and h.files["quiet.json"].apps[1].app == "Chat", "the retry saves it")
-- an unreadable store is preserved: no overwrite, no changes
local corrupt = { version = 9, apps = "junk" }
h = fixture({ files = { ["quiet.json"] = corrupt } })
check(h.text.rules_status:find("kept"), "an unreadable store is reported")
h:send({})
h.handlers.set_app_rule({ app = "Chat", mode = "muted" }); h:flush()
check(h.fact.rules_n == 0 and h.files["quiet.json"] == corrupt, "an unreadable store is neither changed nor overwritten")

-- ── Activities ───────────────────────────────────────────────────
local function activities()
    local a = { fact = {}, text = {}, handlers = {}, emits = {}, files = {} }
    local env = setmetatable({ fact = a.fact, text = a.text,
        on = function(name, fn) a.handlers[name] = fn end,
        after = function() return 1 end, cancel = function() end,
        emit = function(name, v) a.emits[#a.emits + 1] = { name, v } end,
        sys = { ask = function(_, path) return a.files[path] end, call = function(name, ...) if name == "files.write" then a.files[select(1, ...)] = select(2, ...) end end } }, { __index = _G })
    assert(loadfile("shell/activities.luau", "t", env))()
    return a
end
local a = activities()
check(a.fact.quiet_n == 0 and a.text.quiet_text == "" and a.fact.timer_state == 0, "starts with no mode and an idle timer")
a.handlers.quiet_start("focus"); a.handlers.quiet_start("game")
check(a.fact.quiet_focus and a.fact.quiet_game and not a.fact.quiet_presentation and a.fact.quiet_n == 2 and a.text.quiet_text == "Focus · Game", "start is explicit, per mode")
a.handlers.quiet_toggle("focus"); check(not a.fact.quiet_focus and a.fact.quiet_game, "toggle changes one mode")
a.handlers.quiet_stop("game"); check(a.fact.quiet_n == 0, "stop ends a mode")
a.handlers.quiet_start("nonsense"); check(a.text.quiet_error ~= "" and a.fact.quiet_n == 0, "an unknown mode is reported")
a.handlers.quiet_start("presentation"); check(a.text.quiet_error == "" and a.fact.quiet_presentation, "a good call clears the error")
a.handlers.quiet_stop_all(); check(a.fact.quiet_n == 0, "stop_all ends everything")
-- the timer is unchanged by quiet modes
a.handlers.start(60)
check(a.fact.timer_state == 1 and a.fact.timer_duration == 60 and a.files["timer.json"].status == "running", "timer start still works and saves")
a.handlers.quiet_start("focus")
check(a.fact.timer_state == 1 and a.files["timer.json"].status == "running", "quiet modes do not touch the timer")
a.handlers.cancel(); check(a.fact.timer_state == 0, "timer cancel unaffected")
-- an unreadable timer file cannot disable quiet modes
local broken = { fact = {}, text = {}, handlers = {} }
local env = setmetatable({ fact = broken.fact, text = broken.text, on = function(n, f) broken.handlers[n] = f end,
    after = function() return 1 end, cancel = function() end, emit = function() end,
    sys = { ask = function() return { version = 99 } end, call = function() end } }, { __index = _G })
assert(loadfile("shell/activities.luau", "t", env))()
broken.handlers.quiet_start("game")
check(broken.fact.quiet_game == true and broken.text.storage_status ~= "", "quiet modes work when the timer file is unreadable")

print("Quiet adapters: " .. passed .. " focused checks passed")
