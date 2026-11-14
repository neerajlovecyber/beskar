-- Widgets owner bridge for portable setup (C5): lua tests/widget-setup.lua
-- Part 1 tests shell/widget_setup.luau with a fake host whose every step can be held and released (ordering, stale,
-- timeouts, failed writes, late answers). Part 2 runs the REAL shell/widgets.luau in a sandbox with a throw-away HOME and a
-- `run` whose callbacks can be held, so the request / response files and the atomic widgets.json write really happen.
-- Nothing touches the live session, its sockets or ~/.config.
package.path = "shell/?.luau;" .. package.path
local SP = require("setup_profiles")
local Setup = require("widget_setup")
local L = require("widget_layouts")
local KINDS = require("widgets_data").KINDS
local passed = 0
local function check(v, why) if not v then error("FAILED: " .. tostring(why), 2) end passed = passed + 1 end
local function copy(v) if type(v) ~= "table" then return v end local t = {} for k, x in pairs(v) do t[k] = copy(x) end return t end

-- ── a small JSON codec (the shell's json is not available here) ──
local json = {}
local function enc(v)
    local t = type(v)
    if t == "number" then return v == math.floor(v) and string.format("%d", v) or string.format("%.14g", v) end
    if t == "boolean" then return tostring(v) end
    if t == "string" then
        return '"' .. v:gsub('[%c"\\]', function(c)
            local map = { ['"'] = '\\"', ["\\"] = "\\\\", ["\n"] = "\\n", ["\t"] = "\\t", ["\r"] = "\\r" }
            return map[c] or string.format("\\u%04x", c:byte())
        end) .. '"'
    end
    if t == "table" then
        local n = 0
        for _ in pairs(v) do n = n + 1 end
        if n == #v then
            local out = {}
            for i, x in ipairs(v) do out[i] = enc(x) end
            return "[" .. table.concat(out, ",") .. "]"
        end
        local keys = {}
        for k in pairs(v) do keys[#keys + 1] = tostring(k) end
        table.sort(keys)
        local out = {}
        for _, k in ipairs(keys) do out[#out + 1] = enc(k) .. ":" .. enc(v[k]) end
        return "{" .. table.concat(out, ",") .. "}"
    end
    error("cannot encode " .. t)
end
function json.encode(v) return enc(v) end
function json.decode(s)
    local i = 1
    local function ws() i = s:find("%S", i) or #s + 1 end
    local value
    local function str()
        local out = {}
        i = i + 1
        while true do
            local c = s:sub(i, i)
            if c == "" then error("unterminated string") end
            if c == '"' then i = i + 1; return table.concat(out) end
            if c == "\\" then
                local n = s:sub(i + 1, i + 1)
                local map = { n = "\n", t = "\t", r = "\r", ['"'] = '"', ["\\"] = "\\", ["/"] = "/" }
                if n == "u" then out[#out + 1] = utf8.char(tonumber(s:sub(i + 2, i + 5), 16)); i = i + 6
                else out[#out + 1] = assert(map[n], "bad escape"); i = i + 2 end
            else out[#out + 1] = c; i = i + 1 end
        end
    end
    function value()
        ws()
        local c = s:sub(i, i)
        if c == "{" then
            local t = {}
            i = i + 1; ws()
            if s:sub(i, i) == "}" then i = i + 1; return t end
            while true do
                ws(); local k = str(); ws()
                assert(s:sub(i, i) == ":", "expected :"); i = i + 1
                t[k] = value(); ws()
                local d = s:sub(i, i); i = i + 1
                if d == "}" then return t end
                assert(d == ",", "expected ,")
            end
        elseif c == "[" then
            local t = {}
            i = i + 1; ws()
            if s:sub(i, i) == "]" then i = i + 1; return t end
            while true do
                t[#t + 1] = value(); ws()
                local d = s:sub(i, i); i = i + 1
                if d == "]" then return t end
                assert(d == ",", "expected ,")
            end
        elseif c == '"' then return str()
        elseif s:sub(i, i + 3) == "true" then i = i + 4; return true
        elseif s:sub(i, i + 4) == "false" then i = i + 5; return false
        elseif s:sub(i, i + 3) == "null" then i = i + 4; return nil
        else
            local num = s:match("^-?%d+%.?%d*[eE]?[+-]?%d*", i)
            assert(num and num ~= "", "bad value at " .. i)
            i = i + #num
            return tonumber(num)
        end
    end
    local v = value()
    ws()
    assert(i > #s, "trailing text")
    return v
end

local function kind_of(id) return KINDS[id] end
local function card(id, out, kind, sz, x, y, extra)
    local c = { id = id, out = out or "A", kind = kind or 1, sz = sz or 1, x = x or 48, y = y or 72 }
    for k, v in pairs(extra or {}) do c[k] = v end
    return c
end
local GEOM = { unit = 160, gap = 16, top = 40, side = 12, bottom = 60, ox = 48, oy = 72, def_w = 1920, def_h = 1080 }
local function fp_of(snap, cards)
    return SP.fingerprint("widgets", assert(SP.snapshot("widgets", { ready = true, snap = snap, cards = cards })))
end

-- ═════════════ part 1: the module with a fake host ═════════════
local function make_host(o)
    o = o or {}
    local h = { log = {}, notified = {}, timers = {}, held = {}, cards = o.cards or { card(1, "A", 1, 1, 48, 72), card(2, "A", 3, 0, 48, 248) },
        snap = true, connected = o.connected or { A = true }, sizes = { A = { 1920, 1080 }, B = { 1280, 720 } },
        files = { request = nil, response = nil }, installed = {}, gate_state = false, top = nil, resaves = 0,
        hold = {}, fail = {}, ready = true }
    local function trace(s) h.log[#h.log + 1] = s end
    local host = { json = json }
    function host.profiles() return SP end
    function host.after(ms, fn) local t = { ms = ms, fn = fn }; h.timers[#h.timers + 1] = t; return t end
    function host.cancel(t) if t then t.canceled = true end end
    -- a step is held when h.hold[name] is set; h.release(name) then lets the OLDEST held one through
    local function step(name, fn)
        if h.hold[name] then h.held[#h.held + 1] = { name = name, fn = fn } else fn() end
    end
    function h.release(name)
        for i, e in ipairs(h.held) do
            if e.name == name then table.remove(h.held, i); e.fn(); return true end
        end
        return false
    end
    function host.read_request(cb)
        trace("read")
        step("read", function()
            if h.files.request == nil then cb("missing") else cb("ok", h.files.request) end
        end)
    end
    function host.write_response(text, cb)
        step("response", function()
            if h.fail.response and h.fail.response > 0 then h.fail.response = h.fail.response - 1; cb(false); return end
            h.files.response = text
            trace("response")
            cb(true)
        end)
    end
    function host.notify(id)
        trace("notify " .. id)
        h.notified[#h.notified + 1] = { id = id, response = h.files.response and json.decode(h.files.response) }
    end
    function host.ready() return h.ready end
    function host.live() return { snap = h.snap, cards = copy(h.cards) } end
    function host.outputs() return copy(h.connected) end
    function host.restore(layout, exact)
        local ctx = { connected = exact and {} or h.connected, sizes = h.sizes, kind_of = kind_of, limit = 16, geom = GEOM }
        return L.restore(layout, ctx)
    end
    function host.persist(cards, snap, cb)
        trace("persist")
        step("persist", function()
            if h.fail.persist then cb(false, h.fail.unknown == true); return end
            h.disk = { cards = copy(cards), snap = snap }
            trace("persisted")
            cb(true)
        end)
    end
    function host.top_fp() return h.top end
    function host.install(cards, snap, how, tag)
        if h.fail.install then error("boom") end
        trace("install " .. how)
        h.cards, h.snap = copy(cards), snap
        h.installed[#h.installed + 1] = { how = how, tag = tag }
        if how == "push" then h.top = tag elseif how == "replace" then h.top = nil end
    end
    function host.gate(on) h.gate_state = on; trace(on and "gate up" or "gate down") end
    function host.resave() h.resaves = h.resaves + 1; trace("resave") end
    h.ctl = Setup.new(host)
    function h.request(id, req)
        h.files.request = req ~= nil and json.encode(req) or nil
        return h.ctl.request(id)
    end
    function h.fire_timer(ms)
        for _, t in ipairs(h.timers) do
            if t.ms == ms and not t.canceled then t.canceled = true; t.fn(); return true end
        end
        return false
    end
    function h.last() return h.notified[#h.notified] and h.notified[#h.notified].response end
    function h.snapshot_fp() return fp_of(h.snap, h.cards) end
    return h
end
local function index(log, s) for i, v in ipairs(log) do if v == s then return i end end end

-- snapshot
local h = make_host()
h.request(1, { id = 1, kind = "snapshot" })
local r = h.last()
check(r and r.id == 1 and r.ok == true and r.untouched == true and #r.data.cards == 2 and r.data.snap == true and r.data.connected.A == true,
    "a snapshot answers with the cards, the grid option and the connected outputs")
check(r.fp == h.snapshot_fp(), "the snapshot's fingerprint is setup_profiles' own")
check(#h.notified == 1 and h.notified[1].response.id == 1, "Settings is told only once the response is in place")
h.ready = false
h.request(2, { id = 2, kind = "snapshot" })
check(h.last().code == "not_ready" and h.last().untouched == true and h.last().ok == false, "a snapshot before the desktop is ready is refused")
h.ready = true

-- apply: order of events and the answer
local target = { snap = false, cards = { card(1, "A", 1, 2, 100, 100), card(7, "A", 5, 1, 400, 400, {}) } }
local before_fp = h.snapshot_fp()
h = make_host()
before_fp = h.snapshot_fp()
h.request(3, { id = 3, kind = "apply", data = target, expect = before_fp })
r = h.last()
check(r.ok == true and r.id == 3 and not r.untouched, "a valid apply answers ok")
local li = {}
for i, v in ipairs(h.log) do li[v] = li[v] or i end
check(li["gate up"] < li.persist and li.persist < li.persisted and li.persisted < li["install push"] and li["install push"] < li["gate down"]
    and li["gate down"] < li.response and li.response < li["notify 3"], "gate, write, install, gate off, response file, THEN the notice")
check(#h.cards == 2 and h.cards[2].id == 7 and h.snap == false and r.fp == h.snapshot_fp(), "the target is in place and its fingerprint is acked")
check(h.installed[1].how == "push" and h.installed[1].tag == r.fp, "the undo step is tagged with the acked fingerprint")
check(h.disk.snap == false and #h.disk.cards == 2, "the persisted desktop is the target")

-- stale: nothing happens
h = make_host()
local fp0 = h.snapshot_fp()
h.cards[1].x = 60                       -- the user moved a card after the review
h.request(4, { id = 4, kind = "apply", data = target, expect = fp0 })
r = h.last()
check(r.ok == false and r.code == "stale" and r.untouched == true, "a changed desktop answers stale / untouched")
check(not index(h.log, "persist") and not index(h.log, "gate up") and #h.installed == 0, "…before any gate, write or install")
h.request(5, { id = 5, kind = "apply", data = target })
check(h.last().code == "bad_request" and h.last().untouched == true, "an apply needs `expect` unless it is forced")
h.request(6, { id = 6, kind = "apply", data = { snap = true, cards = { { id = 1 } } }, expect = fp0 })
check(h.last().code == "invalid" and h.last().untouched == true, "a card setup_profiles refuses is invalid")
h.request(7, { id = 7, kind = "bogus" })
check(h.last().code == "bad_request", "an unknown request kind is refused")

-- unsupported kinds would drop cards: refused whole
h = make_host()
h.request(8, { id = 8, kind = "apply", data = { snap = true, cards = { card(1, "A", 1, 1, 48, 72), card(2, "A", 99, 1, 48, 248) } }, expect = h.snapshot_fp() })
r = h.last()
check(r.ok == false and r.code == "unsupported" and r.untouched == true and not index(h.log, "persist") and #h.cards == 2, "a widget kind this Beskar does not know refuses the apply instead of dropping it")

-- disconnected outputs: kept; connected reflow; a forced rollback is exact
h = make_host({ connected = { A = true }, cards = { card(1, "A", 1, 1, 48, 72), card(2, "B", 1, 1, 48, 72) } })
local far = { snap = true, cards = { card(1, "A", 3, 0, 9000, 9000), card(2, "B", 1, 1, 9000, 9000) } }
h.request(9, { id = 9, kind = "apply", data = far, expect = h.snapshot_fp() })
check(h.last().ok == true, "a desktop with a disconnected output applies")
local got = {}
for _, c in ipairs(h.cards) do got[c.id] = c end
check(got[2] and got[2].out == "B" and got[2].x == 9000 and got[2].y == 9000, "the card on the disconnected output keeps its record exactly")
check(got[1].x == 1920 - 160 - 12 and got[1].y == 1080 - 160 - 12 - 60, "a card on a connected output is clamped through the layout restore")
local exact = { snap = true, cards = { card(1, "A", 3, 0, 9000, 9000) } }
h.request(10, { id = 10, kind = "apply", data = exact, force = true })
check(h.last().ok == true and h.cards[1].x == 9000 and h.cards[1].y == 9000, "a forced (rollback) apply restores exactly, with no reflow")

-- undo history decisions
h = make_host()
h.request(11, { id = 11, kind = "apply", data = target, expect = h.snapshot_fp() })
local after_tag = h.last().fp
check(h.top == after_tag, "the apply left its undo step on top")
h.request(12, { id = 12, kind = "apply", data = { snap = true, cards = copy(h.cards) }, force = true })
check(h.installed[2].how == "push" or h.installed[2].how == "none" or h.installed[2].how == "replace", "a forced apply has a defined history rule")
local h2 = make_host()
h2.request(13, { id = 13, kind = "apply", data = target, expect = h2.snapshot_fp() })
local before_data = { snap = true, cards = { card(1, "A", 1, 1, 48, 72), card(2, "A", 3, 0, 48, 248) } }
h2.request(14, { id = 14, kind = "apply", data = before_data, force = true })
check(h2.installed[2].how == "replace" and h2.top == nil, "taking back the setup apply (still on top, desktop untouched since) replaces its undo step")
local h3 = make_host()
h3.request(15, { id = 15, kind = "apply", data = target, expect = h3.snapshot_fp() })
h3.cards[1].x = 77                        -- the user edited after the apply
h3.request(16, { id = 16, kind = "apply", data = before_data, force = true })
check(h3.installed[2].how == "push", "…but after a later user edit the rollback is a step of its own")
local h4 = make_host()
h4.request(17, { id = 17, kind = "apply", data = { snap = true, cards = copy(h4.cards) }, expect = h4.snapshot_fp() })
check(h4.installed[1].how == "none", "applying exactly what is there adds no undo step")

-- a failed write: nothing changed, gate down, answer after the failure
h = make_host()
h.fail.persist = true
h.request(20, { id = 20, kind = "apply", data = target, expect = h.snapshot_fp() })
r = h.last()
check(r.ok == false and r.code == "io" and r.untouched == true and #h.installed == 0 and not h.gate_state and #h.cards == 2 and h.resaves == 0,
    "a failed widgets.json write changes nothing and says so (untouched)")
check(index(h.log, "gate down") < index(h.log, "response"), "the gate is lowered before the answer")
h.fail.unknown = true
h.request(21, { id = 21, kind = "apply", data = target, expect = h.snapshot_fp() })
check(h.last().untouched == false and h.resaves == 1 and #h.installed == 0, "a write of unknown outcome is NOT untouched, and memory is re-asserted on disk")
h.fail.persist, h.fail.unknown = nil, nil

-- the response file cannot be written: retried once; no notice without a file
h = make_host()
h.fail.response = 1
h.request(22, { id = 22, kind = "snapshot" })
check(#h.notified == 1 and h.notified[1].id == 22, "a failed response write is retried once")
h.fail.response = 2
h.request(23, { id = 23, kind = "snapshot" })
check(#h.notified == 1, "no notice is ever sent without a response file (the coordinator times out)")
h.request(24, { id = 24, kind = "snapshot" })
check(#h.notified == 2 and h.notified[2].id == 24, "…and the queue goes on")

-- the request file belongs to another request
h = make_host()
h.files.request = json.encode({ id = 31, kind = "snapshot" })
h.ctl.request(30)
check(h.last().code == "superseded" and h.last().id == 30 and h.last().untouched == true, "a request whose file holds another id is superseded")
h.files.request = nil
h.ctl.request(32)
check(h.last().code == "bad_request", "a missing request file is refused")
check(h.ctl.request(32) == false and #h.notified == 2, "a repeated event never runs a request twice")
check(h.ctl.request("x") == false and h.ctl.request(0) == false and h.ctl.request(1.5) == false and h.ctl.request(nil) == false, "ids must be positive integers")

-- ONE request at a time, in order; a late apply never runs after the request that replaced it
h = make_host()
h.hold.read = true
local fp = h.snapshot_fp()
h.files.request = json.encode({ id = 40, kind = "apply", data = target, expect = fp })
h.ctl.request(40)
h.files.request = json.encode({ id = 41, kind = "apply", data = { snap = true, cards = { card(1, "A", 1, 1, 48, 72), card(2, "A", 3, 0, 48, 248) } }, force = true })
h.ctl.request(41)
check(#h.held == 1 and h.ctl.pending() == 2, "the second request waits while the first is still reading")
h.hold.read = false
h.release("read")
check(h.notified[1].id == 40 and h.notified[1].response.code == "superseded" and not index(h.log, "persist" ) or index(h.log, "persist") > index(h.log, "notify 40"),
    "the first (timed-out) apply does not run once its file was replaced and a later request waits")
check(h.notified[2] and h.notified[2].id == 41 and h.notified[2].response.ok == true, "the forced rollback then runs, strictly after")
check(h.cards[2].id == 2, "…and the desktop ends as the rollback says")

-- same, with the file still holding the old request: the queued-behind rule
h = make_host()
h.hold.read = true
h.files.request = json.encode({ id = 50, kind = "apply", data = target, expect = h.snapshot_fp() })
h.ctl.request(50)
h.ctl.request(51)
h.hold.read = false
h.release("read")          -- 50 reads its own request while 51 is queued behind it
check(h.notified[1].response.code == "superseded" and #h.installed == 0, "an apply with a later request already queued is not executed")
check(h.notified[2].id == 51, "the later request is then answered in order")

-- timeout in the write phase: answer not-untouched, nothing installed, a late write changes memory nothing
h = make_host()
h.hold.persist = true
h.request(60, { id = 60, kind = "apply", data = target, expect = h.snapshot_fp() })
check(h.gate_state == true and #h.held == 1, "the gate is up while the file is being written")
h.files.request = json.encode({ id = 61, kind = "apply", data = { snap = true, cards = { card(1, "A", 1, 1, 48, 72), card(2, "A", 3, 0, 48, 248) } }, force = true })
h.ctl.request(61)
check(h.ctl.pending() == 2 and #h.notified == 0, "a rollback requested meanwhile waits its turn")
check(h.fire_timer(Setup.TIMEOUT_MS), "the watchdog fires")
check(h.notified[1].id == 60 and h.notified[1].response.code == "timeout" and h.notified[1].response.untouched == false and h.resaves == 1,
    "the owner gives up on the write: timeout, NOT untouched, memory re-asserted on disk")
check(index(h.log, "gate down") < index(h.log, "response"), "…and the gate is lowered before the answer")
check(#h.held == 2, "the rollback has started behind it (its own write is held too)")
h.hold.persist = false
h.release("persist")       -- the late write of request 60
local pushed = 0
for _, i in ipairs(h.installed) do if i.how == "push" then pushed = pushed + 1 end end
check(pushed == 0 and #h.installed == 0, "a write that finishes after its timeout is never installed")
h.release("persist")       -- request 61
check(h.notified[#h.notified].id == 61 and h.notified[#h.notified].response.ok == true and h.cards[2].id == 2 and h.resaves == 2,
    "the rollback runs after it and wins; the late write only re-asserts memory")
check(h.log[#h.log] == "notify 61" and not h.gate_state, "the gate ends down")

-- a read that never answers: the job times out untouched and the next one runs
h = make_host()
h.hold.read = true
h.files.request = json.encode({ id = 70, kind = "snapshot" })
h.ctl.request(70)
h.ctl.request(71)
h.fire_timer(Setup.TIMEOUT_MS)
check(h.notified[1].id == 70 and h.notified[1].response.code == "timeout" and h.notified[1].response.untouched == true, "a stuck read times out untouched")
h.hold.read = false
h.files.request = json.encode({ id = 71, kind = "snapshot" })
while h.release("read") do end
check(h.notified[#h.notified].id == 71 and h.notified[#h.notified].response.ok == true, "the next request is answered")
local idx_before = #h.notified
h.release("read")
check(#h.notified == idx_before, "a late read of a timed-out job answers nothing more")

-- an install that throws cannot wedge the gate or the queue
h = make_host()
h.fail.install = true
h.request(80, { id = 80, kind = "apply", data = target, expect = h.snapshot_fp() })
check(h.last().ok == false and h.last().untouched == false and not h.gate_state and h.resaves == 1, "a failing install lowers the gate, re-asserts memory and answers not-untouched")
h.fail.install = nil
h.request(81, { id = 81, kind = "snapshot" })
check(h.last().ok == true, "the queue is not wedged")

print(string.format("widget-setup part 1: %d checks passed", passed))

-- ═════════════ part 2: the real widgets.luau, throw-away HOME, held callbacks ═════════════
local function shq(s) return "'" .. tostring(s):gsub("'", "'\\''") .. "'" end
local function sh_out(cmd) local p = assert(io.popen(cmd .. " 2>&1")); local out = p:read("a"); p:close(); return out end
local HOME = sh_out("mktemp -d"):gsub("%s+$", "")
assert(HOME:find("^/tmp/") or HOME:find("^/var/"), "temp dir expected")
local function reset_home()
    os.execute("rm -rf " .. shq(HOME) .. "/.config; mkdir -p " .. shq(HOME) .. "/.config/beskar")
end
local function put(name, body)
    local f = assert(io.open(HOME .. "/.config/beskar/" .. name, "w")); f:write(body); f:close()
end
local function get(name)
    local f = io.open(HOME .. "/.config/beskar/" .. name, "r")
    if not f then return nil end
    local body = f:read("a"); f:close(); return body
end

local function boot()
    local w = { handlers = {}, afters = {}, says = {}, calls = {}, fact = { snap_on = true, editing = false, widgets_on = true, hour12 = true, can_undo = false },
        text = {}, model = {}, held = {}, hold = false, fail_widgets_write = false, said_after = {} }
    local env
    local function exec(args)
        local script = args[2]
        if script:find("pleamar_desktop.log", 1, true) then
            return "surface 5 on HDMI-A-1 · Widgets copy 0\nsurface 6 on DP-1 · Widgets copy 1\n", 0
        elseif script:find("niri msg", 1, true) then
            return '{"HDMI-A-1":{"logical":{"width":1920,"height":1080}},"DP-1":{"logical":{"width":1280,"height":720}}}', 0
        elseif w.fail_widgets_write and script:find('f="$d/widgets.json"', 1, true) then
            return "", 1
        end
        local c = { "HOME=" .. shq(HOME), "sh", "-c", shq(script) }
        for i = 3, #args do c[#c + 1] = shq(args[i]) end
        local p = assert(io.popen(table.concat(c, " ") .. " 2>/dev/null; echo \"::$?\""))
        local all = p:read("a"); p:close()
        local out, code = all:match("^(.*)::(%d+)\n?$")
        return out, tonumber(code)
    end
    env = setmetatable({
        fact = w.fact, text = w.text, model = w.model, json = json,
        on = function(n, fn) w.handlers[n] = fn end,
        every = function() return {} end,
        after = function(ms, fn) local job = { ms = ms, fn = fn }; w.afters[#w.afters + 1] = job; return job end,
        cancel = function(job) if job then job.canceled = true end end,
        sys = {
            watch = function() end, ask = function() return "" end,
            call = function(name, scene, cmd)
                if name == "say" then
                    -- what the response file held at the moment Settings was told
                    local resp = get("setup-widget-response.json")
                    w.says[#w.says + 1] = { scene, cmd, response = resp and json.decode(resp) }
                else w.calls[#w.calls + 1] = name end
            end,
        },
        run = function(cmd, args, cb)
            local function go() local out, code = exec(args); if cb then cb(out, code) end end
            if cmd == "sh" then
                if w.hold then w.held[#w.held + 1] = { go = go, script = args[2] } else go() end
            elseif cb then cb("", 0) end
        end,
        require = function(name)
            if name == "clockfmt" then return function() return "2:05 PM" end end
            if name == "timer_client" then return function() return function() end end end
            if name == "personal_client" or name == "weather_client" then return function() end end
            local f = assert(loadfile("shell/" .. name .. ".luau", "t", env))
            return f()
        end,
    }, { __index = _G })
    env.os = setmetatable({ time = function() return 1700000000 end }, { __index = os })
    assert(loadfile("shell/widgets.luau", "t", env))()
    function w.run_timers(skip)
        local guard = 0
        while guard < 50 do
            guard = guard + 1
            local pick
            for i, j in ipairs(w.afters) do
                if not j.canceled and j.ms ~= skip and (not pick or j.ms < w.afters[pick].ms) then pick = i end
            end
            if not pick then return end
            local j = table.remove(w.afters, pick)
            j.fn()
        end
    end
    function w.fire(n, p) w.handlers[n](p) end
    function w.flush()                      -- release held callbacks (oldest first) until none is left
        while #w.held > 0 do table.remove(w.held, 1).go() end
    end
    function w.release_one() local e = table.remove(w.held, 1); if e then e.go() end end
    function w.cards_saved() return json.decode(get("widgets.json")).cards end
    function w.request(req)
        put("setup-widget-request.json", json.encode(req))
        w.fire("setup_request", req.id)
    end
    function w.reply() return get("setup-widget-response.json") and json.decode(get("setup-widget-response.json")) end
    function w.replies_for(id)
        local n = 0
        for _, s in ipairs(w.says) do if s[1] == "settings" and s[2] == "emit setup_widgets_reply " .. id then n = n + 1 end end
        return n
    end
    function w.fp() w.request({ id = 9000 + #w.says, kind = "snapshot" }); w.flush(); return w.reply().fp, w.reply().data end
    w.run_timers()
    return w
end

reset_home()
local w = boot()
check(#w.model.ws == 6, "widgets boot with the default desktop")
local theme_sync = false
for _, s in ipairs(w.says) do if s[1] == "settings" and s[2] == "emit theme_sync" then theme_sync = true end end
check(theme_sync, "a restart asks Settings once for the look (theme_sync)")

-- snapshot, through the real files
w.request({ id = 1, kind = "snapshot" })
local resp = w.reply()
check(resp.id == 1 and resp.ok == true and resp.untouched == true and #resp.data.cards == 6 and resp.data.connected["HDMI-A-1"] == true
    and resp.data.connected["DP-1"] == true and resp.data.snap == true, "the snapshot is in the response file")
check(resp.fp == SP.fingerprint("widgets", SP.snapshot("widgets", { ready = true, snap = resp.data.snap, cards = resp.data.cards })), "its fingerprint is setup_profiles'")
local last_say = w.says[#w.says]
check(last_say[2] == "emit setup_widgets_reply 1" and last_say.response and last_say.response.id == 1, "Settings is told only after the response file exists")
check(get("setup-widget-response.json.tmp") == nil, "no temp file is left behind")
w.fire("setup_request", 1)
check(w.replies_for(1) == 1, "a repeated event does not answer twice")
put("setup-widget-request.json", json.encode({ id = 5, kind = "snapshot" }))
w.fire("setup_request", 2)
check(w.reply().id == 2 and w.reply().code == "superseded", "a request file with another id answers superseded")

-- apply
local snap_fp, snap_data = w.fp()
local before_cards = w.cards_saved()
local ids = {}
for _, c in ipairs(snap_data.cards) do ids[#ids + 1] = c.id end
local target_cards = copy(snap_data.cards)
table.remove(target_cards, 1)
target_cards[1].x, target_cards[1].y = 304, 72
target_cards[#target_cards + 1] = { id = 40, out = "HDMI-A-9", kind = 4, sz = 0, x = 5000, y = 5000, opts = { lock = true } }
local target = { snap = false, cards = target_cards }
w.request({ id = 10, kind = "apply", data = target, expect = snap_fp })
resp = w.reply()
check(resp.id == 10 and resp.ok == true and resp.fp, "an apply is answered ok with the new fingerprint")
local saved = json.decode(get("widgets.json"))
check(#saved.cards == 6 and saved.snap == false and saved.next >= 41, "widgets.json holds the new desktop (grid option and next id too)")
local disc
for _, c in ipairs(saved.cards) do if c.id == 40 then disc = c end end
check(disc and disc.out == "HDMI-A-9" and disc.x == 5000 and disc.opts.lock == true, "the disconnected output's card is kept with its options")
check(#w.model.ws == 5 and w.fact.snap_on == false and w.fact.can_undo == true, "the connected cards are shown (5), the grid option follows, one undo step exists")
local new_fp, new_data = w.fp()
check(new_fp == resp.fp, "the acked fingerprint is what a fresh snapshot reports")

-- ONE own undo step
w.fire("w_undo")
w.run_timers()
check(w.fact.snap_on == true and #w.cards_saved() == 6 and w.fact.can_undo == false, "one Undo returns the previous desktop and its grid option")
local fp_undone = w.fp()
check(fp_undone == snap_fp, "…exactly")

-- apply, then the coordinator's forced rollback takes that step off the history instead of adding another
w.request({ id = 11, kind = "apply", data = target, expect = snap_fp })
check(w.reply().ok == true and w.fact.can_undo == true, "applied again")
w.request({ id = 12, kind = "apply", data = { snap = true, cards = snap_data.cards }, force = true })
check(w.reply().ok == true and w.fact.can_undo == false and w.fp() == snap_fp, "a forced rollback restores the desktop exactly and consumes the apply's undo step")

-- stale
local before_file = get("widgets.json")
w.fire("w_remove", w.model.ws[1].id)
w.run_timers()
local after_edit_file = get("widgets.json")
w.request({ id = 13, kind = "apply", data = target, expect = snap_fp })
resp = w.reply()
check(resp.ok == false and resp.code == "stale" and resp.untouched == true and get("widgets.json") == after_edit_file and #w.model.ws == 5, "a desktop edited since the review answers stale and nothing changes")

-- unsupported kind
local fp5, d5 = w.fp()
local bad = copy(d5.cards)
bad[#bad + 1] = { id = 77, out = "HDMI-A-1", kind = 99, sz = 1, x = 48, y = 600 }
w.request({ id = 14, kind = "apply", data = { snap = true, cards = bad }, expect = fp5 })
check(w.reply().code == "unsupported" and w.reply().untouched == true and get("widgets.json") == after_edit_file, "a kind this Beskar does not know refuses the apply")
w.request({ id = 15, kind = "apply", data = { snap = true, cards = { { id = 1 } } }, expect = fp5 })
check(w.reply().code == "invalid", "an invalid desktop is refused")

-- persistence failure: no ack of success, memory and file unchanged, the UI is not stuck
w.fail_widgets_write = true
local count_before, undo_before = #w.model.ws, w.fact.can_undo
w.request({ id = 16, kind = "apply", data = target, expect = fp5 })
resp = w.reply()
check(resp.ok == false and resp.code == "io" and resp.untouched == true, "a failed widgets.json write answers io / untouched")
check(#w.model.ws == count_before and w.fact.can_undo == undo_before and get("widgets.json") == after_edit_file and get("widgets.json.tmp") == nil,
    "memory, history and the file are unchanged")
w.fail_widgets_write = false
w.fire("w_remove", w.model.ws[1].id)
check(#w.model.ws == count_before - 1, "the user's own edits work again at once (the gate is down)")
w.run_timers()

-- the gate: edits made while an apply is in flight wait and replay AFTER the install
reset_home()
w = boot()
local fpg, dg = w.fp()
local tg = copy(dg.cards)
local victim = tg[2].id
tg[2].x, tg[2].y = 400, 400
w.hold = true
w.request({ id = 20, kind = "apply", data = { snap = true, cards = tg }, expect = fpg })
w.release_one()                                   -- the request file is read: compare, candidate, gate up, write queued
check(#w.held == 1 and w.held[1].script:find("widgets.json", 1, true), "the candidate's write is in flight")
local n_before = #w.model.ws
w.fire("w_remove", victim)                        -- the user acts meanwhile
w.fire("w_resize", tg[1].id)
check(#w.model.ws == n_before, "the user's edit waits while the write is in flight")
w.release_one()                                   -- the write lands: install, gate down, the waiting edits replay
check(#w.model.ws == n_before - 1, "…and replays on top of the new desktop")
w.flush()
resp = w.reply()
check(resp.ok == true and resp.fp == SP.fingerprint("widgets", SP.snapshot("widgets", { ready = true, snap = true, cards = tg })),
    "the answer describes the desktop the apply installed (before the replayed edits)")
w.hold = false
w.run_timers()
local final = {}
for _, c in ipairs(w.cards_saved()) do final[c.id] = c end
check(final[victim] == nil, "the replayed removal reached the file")
check(w.fact.can_undo == true, "history has the apply's step and the user's later steps")

-- a saved-layout load during the gate waits too
w.fire("w_reset")
w.text.wl_name = "Mine"
w.fire("wl_save")
w.run_timers()
fpg, dg = w.fp()
w.fire("w_remove", w.model.ws[1].id)
w.run_timers()
fpg, dg = w.fp()
w.hold = true
w.request({ id = 21, kind = "apply", data = { snap = true, cards = {} }, expect = fpg })
w.release_one()
local n_gate = #w.model.ws
w.fire("wl_load", 1)
check(#w.model.ws == n_gate, "a saved-layout load fired during the apply waits")
w.flush()
w.hold = false
w.run_timers()
check(w.reply().ok == true and #w.model.ws == 6, "the load that waited ran after the install (it replaced the empty desktop with the saved one)")

-- timeout ordering with real files: a late apply write cannot land after its rollback
reset_home()
w = boot()
fpg, dg = w.fp()
local target_t = copy(dg.cards)
table.remove(target_t, 1)
local before_t = copy(dg.cards)
w.hold = true
w.request({ id = 30, kind = "apply", data = { snap = true, cards = target_t }, expect = fpg })
w.release_one()                                   -- read done; its widgets.json write is now held
check(#w.held == 1, "the write is held")
local timeout_job
for _, j in ipairs(w.afters) do if j.ms == Setup.TIMEOUT_MS and not j.canceled then timeout_job = j end end
check(timeout_job, "the owner has a watchdog on the request")
put("setup-widget-request.json", json.encode({ id = 31, kind = "apply", data = { snap = true, cards = before_t }, force = true }))
w.fire("setup_request", 31)                       -- the coordinator timed out 30 and sent the rollback
timeout_job.canceled = true
timeout_job.fn()                                  -- ...and the owner's watchdog fires
w.flush()                                         -- the late write, then the response of 30, then 31 runs
w.hold = false
w.run_timers()
check(w.replies_for(30) == 1 and w.replies_for(31) == 1, "both requests were answered once")
check(w.reply().id == 31 and w.reply().ok == true, "the last answer is the rollback's")
check(#w.cards_saved() == 6 and #w.model.ws == 6, "the file and memory end as the rollback says, not as the late apply wrote")
local fpe = w.fp()
check(fpe == fpg, "…exactly the original desktop")

os.execute("rm -rf " .. shq(HOME))
print(string.format("widget-setup: %d checks passed", passed))
