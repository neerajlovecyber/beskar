-- Per-card widget options (C4b): lua tests/widget-options.lua
-- Part 1: shell/widget_options.luau as pure logic (schema, clean, migration, clock presentation, snapshot).
-- Part 2: saved desktops keep options (shell/widget_layouts.luau, version 1 files still load).
-- Part 3: the real shell/widgets.luau in a sandbox with a throw-away HOME (selection, events, lock rules, undo,
-- seconds feed, widgets.json migration). Nothing touches the real session or ~/.config.
package.path = "shell/?.luau;" .. package.path
local Data = dofile("shell/widgets_data.luau")
local KINDS = Data.KINDS
local O = dofile("shell/widget_options.luau")
local L = dofile("shell/widget_layouts.luau")
local passed = 0
local function check(v, why) if not v then error("FAILED: " .. why, 2) end passed = passed + 1 end
local function same(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for k, v in pairs(a) do if not same(v, b[k]) then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
end

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

-- ══ part 1: the pure module ══
check(O.FILE_VERSION == 3 and L.VERSION == 3 and O.BASE_VERSION == 2 and L.BASE_VERSION == 2, "files without stacks are version 2; stacks need version 3")
check(#O.defs(1) == 4 and #O.defs(3) == 1 and O.defs(3)[1].key == "lock", "a clock has four options, others only the lock")
check(O.defs(999)[1].key == "lock" and #O.defs(999) == 1, "an unknown kind still has the lock")

-- clean: only known, valid, non-default values survive
check(O.clean(1, nil) == nil and O.clean(1, "x") == nil and O.clean(1, {}) == nil, "nothing to keep → nil")
check(same(O.clean(1, { lock = true, date = "off", seconds = "on", format = "24" }), { lock = true, date = "off", seconds = "on", format = "24" }), "every supported option is kept")
check(O.clean(1, { lock = false, date = "inherit", seconds = "inherit", format = "inherit" }) == nil, "defaults are not stored")
check(O.clean(1, { date = "maybe", seconds = 3, format = "13", lock = "yes" }) == nil, "invalid values are dropped")
check(same(O.clean(1, { lock = true, bogus = 1 }), { lock = true }), "unknown keys of a known kind are dropped")
check(same(O.clean(3, { lock = true, date = "off" }), { lock = true }), "an option of another kind does not apply")
local alien = O.clean(77, { lock = true, stack = "a", pages = 3, rotate = false, bad = {}, ["bad key"] = 1, long = string.rep("x", 40) })
check(same(alien, { lock = true, stack = "a", pages = 3, rotate = false }), "an unknown kind keeps plain bounded values for later")
local many = {}
for i = 1, 20 do many["k" .. string.format("%02d", i)] = i end
local cut = O.clean(77, many)
local n = 0
for _ in pairs(cut) do n = n + 1 end
check(n == O.MAX_UNKNOWN_KEYS and cut.k01 == 1, "an unknown kind's keys are bounded and deterministic")
check(O.clean(77, { lock = false }) == nil, "an unknown kind's unlocked card has nothing to keep")

-- set / cycle / reset / codes
local c = { id = 1, kind = 1, sz = 1 }
check(O.set(c, "lock", 2) and c.opts.lock == true and O.locked(c), "lock on")
check(select(2, O.set(c, "lock", 2)) == false, "setting the same value changes nothing")
check(O.set(c, "lock", 1) and c.opts == nil and not O.locked(c), "back to default leaves a clean record")
check(select(2, O.set(c, "date", 9)) == "value" and not O.set(c, "date", 0) and not O.set(c, "date", 1.5), "bad value indexes are refused")
check(select(2, O.set({ kind = 3 }, "date", 2)) == "unsupported", "an option that does not apply to the kind is refused")
check(select(2, O.set(c, "nope", 1)) == "unknown", "unknown option")
O.set(c, "seconds", 2); O.cycle(c, "seconds"); check(c.opts.seconds == "off", "cycle: on → off")
O.cycle(c, "seconds"); check(c.opts == nil, "cycle wraps to the default and the record is clean again")
O.set(c, "format", 3); O.set(c, "date", 3); O.reset(c); check(c.opts == nil, "reset clears everything")
local def, idx = O.parse_code(23)
check(def.key == "date" and idx == 3, "code 23 = date, third value")
def, idx = O.parse_code(12)
check(def.key == "lock" and idx == 2, "code 12 = lock on")
check(O.parse_code(5) == nil and O.parse_code(99) == nil and O.parse_code("x") == nil and O.parse_code(1.5) == nil, "codes that name nothing")
check(O.sig({ b = 1, a = "x" }) == "a=x,b=1" and O.sig(nil) == "", "signature is ordered")

-- clock presentation: inherit follows the shell
local function eff(opts, sz, g) return O.clock({ sz = sz, opts = opts }, g or { hour12 = true, seconds = false }) end
check(eff(nil, 0).date == false and eff(nil, 1).date == true and eff(nil, 2).date == true, "inherited date line: medium and large only (as before)")
check(eff({ date = "on" }, 0).date == true and eff({ date = "off" }, 2).date == false, "date override")
check(eff(nil, 1).hour12 == true and eff(nil, 1, { hour12 = false }).hour12 == false and eff(nil, 1, {}).hour12 == true, "inherited format follows hour12")
check(eff({ format = "24" }, 1, { hour12 = true }).hour12 == false and eff({ format = "12" }, 1, { hour12 = false }).hour12 == true, "format override")
check(eff(nil, 1).seconds == false and eff(nil, 1, { seconds = true }).seconds == true, "inherited seconds follow the shell default")
check(eff({ seconds = "on" }, 1).seconds == true and eff({ seconds = "off" }, 1, { seconds = true }).seconds == false, "seconds override")
local t, a = O.split_time("2:05:09 PM"); check(t == "2:05:09" and a == "PM", "time with seconds splits")
t, a = O.split_time("14:05"); check(t == "14:05" and a == "", "24 h time splits")
t, a = O.split_time("2:05 PM"); check(t == "2:05" and a == "PM", "12 h time splits")

-- snapshot
local meta = { editing = true, name = function(k) return KINDS[k].name end, sizes = function(k) return #KINDS[k].sizes end }
local s0 = O.snapshot(nil, meta)
check(s0.sel == 0 and #s0.options == 0 and s0.editing == true and s0.v == O.SNAPSHOT_VERSION, "no selection: empty options")
local sc = O.snapshot({ id = 7, out = "A", kind = 1, sz = 1, opts = { lock = true, date = "off" } }, meta)
check(sc.sel == 7 and sc.name == "Clock" and sc.nsz == 3 and sc.lock == true and #sc.options == 4, "a clock card snapshot")
check(sc.options[1].key == "lock" and sc.options[1].value == 2 and sc.options[2].value == 3 and sc.options[3].value == 1, "values are 1-based indexes")
check(sc.options[2].n == 3 and sc.options[2].labels[3] == "Hide" and sc.options[1].id == 1, "labels and counts travel with it")
check(#json.encode(sc) < 1000, "the snapshot is small")
check(#O.snapshot({ id = 2, kind = 3, sz = 0, out = "A" }, meta).options == 1, "a weather card offers only the lock")

-- widgets.json: legacy, current, newer
local legacy = O.decode_file({ snap = false, next = 9, cards = { { id = 3, out = "A", kind = 1, sz = 1, x = 48, y = 72 }, { id = 4, out = "A", kind = 99, sz = 0, x = 1, y = 1 } } }, kind_of)
check(legacy.version == 1 and legacy.migrated and not legacy.newer and #legacy.cards == 1 and legacy.next == 9 and legacy.snap == false, "a legacy file (no version) is read: unknown kinds not loaded, next and snap kept")
check(legacy.cards[1].opts == nil and legacy.cards[1].x == 48, "legacy cards have no options")
local cur = O.decode_file({ version = 2, next = 4, cards = { { id = 1, out = "A", kind = 1, sz = 1, x = 5, y = 6, opts = { lock = true, seconds = "on", junk = 1 } } } }, kind_of)
check(not cur.migrated and not cur.newer and same(cur.cards[1].opts, { lock = true, seconds = "on" }), "a current file keeps clean options")
local newer = O.decode_file({ version = 7, cards = { { id = 1, out = "A", kind = 1, sz = 1, x = 5, y = 6, future = 1 } } }, kind_of)
check(newer.newer and newer.version == 7 and #newer.cards == 1, "a newer file is still read, and flagged")
local dup = O.decode_file({ version = 2, next = 2, cards = { { id = 1, out = "A", kind = 1, sz = 1 }, { id = 1, out = "A", kind = 2, sz = 0 }, { id = "x", out = "A", kind = 2, sz = 0 }, { out = "A", kind = 2, sz = 0 }, "junk", { id = 0, kind = 2 } } }, kind_of)
local ids, seen = {}, true
for _, k in ipairs(dup.cards) do if ids[k.id] or k.id < 1 then seen = false end ids[k.id] = true end
check(seen and #dup.cards == 5 and dup.next > 5, "missing / repeated ids get fresh ones; junk entries are skipped")
check(O.decode_file({}, kind_of) == nil and O.decode_file("x", kind_of) == nil and O.decode_file({ cards = "x" }, kind_of) == nil, "not a card file")
local enc = O.encode_file({ { id = 1, out = "A", kind = 1, sz = 1, x = 1, y = 2, opts = { lock = true } }, { id = 2, out = "A", kind = 2, sz = 0, x = 3, y = 4 } }, 3, true)
check(enc.version == 2 and enc.next == 3 and enc.snap == true and enc.cards[1].opts.lock == true and enc.cards[2].opts == nil, "encode writes version 2 and only real options")
local round = O.decode_file(json.decode(json.encode(enc)), kind_of)
check(same(round.cards[1].opts, { lock = true }) and round.cards[2].opts == nil and not round.migrated, "a file round-trips")

-- ══ part 2: saved desktops keep options ══
local function lcard(id, kind, x, y, opts) return { id = id, out = "A", kind = kind, sz = 1, x = x, y = y, opts = opts } end
local live = { lcard(1, 1, 48, 72, { lock = true, seconds = "on" }), lcard(2, 3, 48, 248), lcard(3, 77, 400, 72, { lock = true, stack = "x" }) }
local body = L.capture(live, true, { A = { 1920, 1080 } })
check(same(body.cards[1].opts, { lock = true, seconds = "on" }) and body.cards[2].opts == nil and same(body.cards[3].opts, { lock = true, stack = "x" }), "capture keeps each card's options (even an unknown kind's)")
local store = L.new_store()
store.layouts[1] = { id = 1, name = "Mine", created = 1, updated = 1, snap = true, areas = body.areas, cards = body.cards }
store.next_id = 2
local text = L.encode(store, json)
local back = L.decode(text, json)
check(back and same(back.layouts[1].cards[1].opts, { lock = true, seconds = "on" }) and back.layouts[1].cards[3].opts.stack == "x", "options survive encode → decode")
check(json.decode(text).version == 2, "the file is written as version 2")
local v1 = L.decode(json.encode({ version = 1, next_id = 2, layouts = { { id = 1, name = "Old", created = 1, updated = 1, snap = true, cards = { { id = 1, out = "A", kind = 1, sz = 1, x = 48, y = 72 } } } } }), json)
check(v1 and #v1.layouts == 1 and v1.layouts[1].cards[1].opts == nil, "a version 1 file still loads (no options)")
check(select(2, L.decode(json.encode({ version = 4, layouts = {} }), json)) == "newer", "version 4 is newer")
local GEOM = { unit = 160, gap = 16, top = 40, side = 12, bottom = 60, ox = 48, oy = 72, def_w = 1920, def_h = 1080 }
local cards = L.restore(back.layouts[1], { connected = { A = true }, sizes = { A = { 700, 500 } }, kind_of = kind_of, limit = 16, geom = GEOM })
local kept = true
for _, k in ipairs(cards) do if k.id == 1 and not (k.opts and k.opts.lock and k.opts.seconds == "on") then kept = false end end
check(kept and #cards == 2, "restore keeps options through a clamp / reflow (unknown kind is skipped, not erased from the store)")
check(back.layouts[1].cards[3].opts.lock == true and #back.layouts[1].cards == 3, "…and the stored layout is untouched")
check(L.signature({ lcard(1, 1, 48, 72) }) ~= L.signature({ lcard(1, 1, 48, 72, { lock = true }) }), "an option change makes the live desktop differ from its saved layout")
check(L.signature({ lcard(1, 1, 48, 72) }) == L.signature({ lcard(9, 1, 48, 72) }), "ids still do not matter; no options keeps the old signature shape")

-- ══ part 3: the real widgets.luau ══
local function shq(s) return "'" .. tostring(s):gsub("'", "'\\''") .. "'" end
local function sh_out(cmd) local p = assert(io.popen(cmd .. " 2>&1")); local out = p:read("a"); p:close(); return out end
local HOME = sh_out("mktemp -d"):gsub("%s+$", "")
assert(HOME:find("^/tmp/") or HOME:find("^/var/"), "temp dir expected")
local function reset_home() os.execute("rm -rf " .. shq(HOME) .. "/.config; mkdir -p " .. shq(HOME) .. "/.config/beskar") end
local function put(name, body) local f = assert(io.open(HOME .. "/.config/beskar/" .. name, "w")); f:write(body); f:close() end
local function get(name)
    local f = io.open(HOME .. "/.config/beskar/" .. name, "r")
    if not f then return nil end
    local body = f:read("a"); f:close(); return body
end
local function exists(name) return get(name) ~= nil end

local CLOCK = { minute = "05" }
local function boot()
    local w = { handlers = {}, afters = {}, everys = {}, says = {}, calls = {}, feed_calls = {},
        fact = { snap_on = true, editing = false, widgets_on = true, hour12 = true, can_undo = false }, text = {}, model = {} }
    local env
    env = setmetatable({
        fact = w.fact, text = w.text, model = w.model, json = json,
        on = function(n, fn) w.handlers[n] = fn end,
        every = function(ms, fn) local j = { ms = ms, fn = fn }; w.everys[#w.everys + 1] = j; return j end,
        after = function(ms, fn) local job = { ms = ms, fn = fn }; w.afters[#w.afters + 1] = job; return job end,
        cancel = function(job) if job then job.canceled = true end end,
        sys = {
            watch = function() end, ask = function() return "" end,
            call = function(name, scene, cmd)
                if name == "say" then w.says[#w.says + 1] = { scene, cmd } else w.calls[#w.calls + 1] = name end
            end,
        },
        run = function(cmd, args, cb)
            local out, code = "", 0
            if cmd == "sh" then
                local script = args[2]
                if script:find("pleamar_desktop.log", 1, true) then
                    out = "surface 5 on HDMI-A-1 · Widgets copy 0\nsurface 6 on DP-1 · Widgets copy 1\n"
                elseif script:find("niri msg", 1, true) then
                    out = '{"HDMI-A-1":{"logical":{"width":1920,"height":1080}},"DP-1":{"logical":{"width":1280,"height":720}}}'
                else
                    local c = { "HOME=" .. shq(HOME), "sh", "-c", shq(script) }
                    for i = 3, #args do c[#c + 1] = shq(args[i]) end
                    local p = assert(io.popen(table.concat(c, " ") .. " 2>/dev/null; echo \"::$?\""))
                    local all = p:read("a"); p:close()
                    out, code = all:match("^(.*)::(%d+)\n?$")
                    code = tonumber(code)
                end
            end
            if cb then cb(out, code) end
        end,
        require = function(name)
            if name == "clockfmt" then
                return function(h12, sec)
                    local base = (h12 == false and "14:" or "2:") .. CLOCK.minute .. (sec and ":09" or "")
                    return h12 == false and base or (base .. " PM")
                end
            end
            if name == "timer_client" then return function() return function(on) w.feed_calls[#w.feed_calls + 1] = on end end end
            if name == "personal_client" or name == "weather_client" then return function() end end
            local f = assert(loadfile("shell/" .. name .. ".luau", "t", env))
            return f()
        end,
    }, { __index = _G })
    env.os = setmetatable({ time = function() return 1700000000 end }, { __index = os })
    assert(loadfile("shell/widgets.luau", "t", env))()
    function w.run_timers()
        local guard = 0
        while guard < 50 do
            guard = guard + 1
            local pick
            for i, j in ipairs(w.afters) do if not j.canceled then if not pick or j.ms < w.afters[pick].ms then pick = i end end end
            if not pick then return end
            local j = table.remove(w.afters, pick)
            j.fn()
        end
    end
    function w.fire(n, p) w.handlers[n](p) end
    function w.card(id) for _, r in ipairs(w.model.ws) do if r.id == id then return r end end end
    function w.saved() return json.decode(get("widgets.json")) end
    function w.saved_card(id) for _, c in ipairs(w.saved().cards) do if c.id == id then return c end end end
    function w.bar()      -- the last snapshot pushed to the widget bar
        for i = #w.says, 1, -1 do
            local s = w.says[i]
            if s[1] == "topbar" and s[2]:find("^text wb_card_options ") then return json.decode(s[2]:gsub("^text wb_card_options ", "")) end
        end
    end
    function w.bar_count()
        local n = 0
        for _, s in ipairs(w.says) do if s[1] == "topbar" and s[2]:find("^text wb_card_options ") then n = n + 1 end end
        return n
    end
    function w.seconds_feed() for _, j in ipairs(w.everys) do if j.ms == 1000 and not j.canceled then return j end end end
    w.run_timers()
    return w
end
local function open_bar(w) w.fire("w_bar_open") end
local function opt(w, key, idx) w.fire("w_opt", O.def(key).id * 10 + idx) end

-- defaults: ids 1 clock · 2 weather · 3 system on HDMI-A-1, 4 clock · 5 weather · 6 system on DP-1
reset_home()
local w = boot()
check(#w.model.ws == 6 and w.card(1).locked == 0 and w.card(1).tm == "2:05" and w.card(1).ap == "PM" and w.card(1).dd == 1 and w.card(1).sec == 0, "a clock card carries its own time in the model")
check(w.card(1).dl ~= "" and w.card(2).tm == "" and w.card(2).dd == 0, "non-clock cards carry no clock text")
check(w.card(4).tm == "2:05" and w.text.w_time == "2:05" and w.text.w_ampm == "PM", "the legacy shared texts still work")
local disk = w.saved()
check(disk.version == 2 and #disk.cards == 6 and disk.cards[1].opts == nil, "defaults are saved as version 2 without options")
check(w.seconds_feed() == nil, "no seconds feed unless a clock shows seconds")

-- selection
w.fire("w_configure", 1)
check(w.fact.sel_id == 0 and w.bar() and w.bar().st and w.bar().st.ok == false, "selecting outside edit mode is refused and the bar is told")
open_bar(w)
check(w.fact.editing == true and w.fact.sel_id == 0, "the bar opening starts edit mode with no selection")
check(w.bar() and w.bar().sel == 0 and w.bar().editing == true, "the bar is told edit mode started")
w.fire("w_configure", 1)
local b = w.bar()
check(w.fact.sel_id == 1 and b.sel == 1 and b.name == "Clock" and #b.options == 4 and b.out == "HDMI-A-1" and b.nsz == 3, "w_configure selects a card and the bar gets its options")
check(w.text.card_options == json.encode(b) or json.decode(w.text.card_options).sel == 1, "the snapshot is also readable from the scene's text")
local n_says = w.bar_count()
w.fire("w_configure", 1)
check(w.bar_count() == n_says, "selecting the same card again pushes nothing")
open_bar(w)
check(w.bar_count() == n_says + 1 and w.bar().rev == b.rev and w.fact.sel_id == 1, "the bar opening again resends the same snapshot (same edit session: selection kept)")
w.fire("w_configure", 999)
check(w.fact.sel_id == 0 and w.bar().st.ok == false, "a card that does not exist selects nothing")
w.fire("w_configure", 2)
check(w.fact.sel_id == 2 and #w.bar().options == 1 and w.bar().options[1].key == "lock", "a weather card offers only the lock")
w.fire("w_configure", { id = 1 })
check(w.fact.sel_id == 1, "a table payload with id works too")
w.fire("w_configure", 0)
check(w.fact.sel_id == 0 and w.bar().sel == 0 and #w.bar().options == 0, "0 clears the selection")

-- options act on the explicit selection
opt(w, "lock", 2)
check(w.card(1).locked == 0 and w.bar().st.msg:find("Select"), "with no selection an option change does nothing and says why")
w.fire("w_configure", 1)
opt(w, "lock", 2)
check(w.card(1).locked == 1 and w.bar().lock == true and w.bar().options[1].value == 2, "lock on: model, snapshot")
opt(w, "date", 3)
check(w.card(1).dd == 0 and w.card(1).dl == "" and w.card(4).dd == 1, "hide the date: only this card changes")
opt(w, "format", 3)
check(w.card(1).tm == "14:05" and w.card(1).ap == "" and w.card(4).tm == "2:05" and w.card(4).ap == "PM", "24-hour override: only this card changes")
opt(w, "seconds", 2)
check(w.card(1).tm == "14:05:09" and w.card(1).sec == 1 and w.card(4).sec == 0 and w.card(4).tm == "2:05", "seconds override: digits carry them, the size flag is set")
local feed = w.seconds_feed()
check(feed and feed.ms == 1000, "a one-second feed starts for a visible clock with seconds")
local before = w.model.ws
feed.fn()
check(w.model.ws == before, "a tick with nothing new repaints nothing")
CLOCK.minute = "06"
feed.fn()
check(w.model.ws ~= before and w.card(1).tm == "14:06:09" and w.card(4).tm == "2:06", "a tick that changes the time pushes it, every clock card with it")
w.run_timers()
local saved = w.saved_card(1)
check(same(saved.opts, { lock = true, date = "off", seconds = "on", format = "24" }) and w.saved().version == 2, "options are saved with the card (version 2)")
check(w.saved_card(4).opts == nil, "other cards stay clean")

-- unsupported / invalid
w.fire("w_configure", 2)
opt(w, "date", 3)
check(w.card(2).dd == 0 and w.bar().st.ok == false and w.bar().st.msg:find("does not apply"), "a clock option on a weather card is refused")
w.fire("w_opt", 99)
check(w.bar().st.msg == "Unknown option", "an unknown option code")
w.fire("w_opt", 14)
check(w.bar().st.msg:find("Not a value"), "a value index out of range")
check(w.saved_card(2).opts == nil, "refusals change nothing")

-- table payloads, cycling, reset, undo
w.fire("w_configure", 4)
w.fire("w_opt", { opt = "format", value = "24" })
check(w.card(4).tm == "14:05" or w.card(4).tm == "14:06", "w_opt accepts {opt, value} with names")
w.fire("w_opt", { opt = 4, value = 1 })
check(w.card(4).tm == "2:06", "…and numeric ids")
w.fire("w_opt", { opt = "lock", value = true })
check(w.card(4).locked == 1 and w.bar().lock == true, "a boolean names the lock value")
w.fire("w_opt", { opt = "lock", value = 1 })
check(w.card(4).locked == 0, "…and so does its index")
w.fire("w_opt_next", 3)
check(w.card(4).sec == 1, "w_opt_next cycles seconds: inherit → on")
w.fire("w_opt_next", 3); w.fire("w_opt_next", 3)
check(w.card(4).sec == 0, "…wraps back to inherit")
w.fire("w_opt_next", 77)
check(w.bar().st.msg == "Unknown option", "w_opt_next with an unknown option")
opt(w, "seconds", 2)
check(w.card(4).sec == 1, "seconds on card 4")
w.fire("w_opt_reset")
check(w.card(4).sec == 0 and w.bar().options[3].value == 1 and w.card(1).locked == 1, "reset clears the selected card only")
w.fire("w_undo")
check(w.card(4).sec == 1, "reset is one undo step")
w.fire("w_undo"); w.fire("w_undo")
w.fire("w_configure", 4)
check(w.bar().sel == 4, "undo keeps a selection whose card still exists")

-- the seconds feed follows cards, the option and the shell's default
w.fire("w_configure", 1)
w.fire("w_opt_reset")
w.fire("w_configure", 4)
w.fire("w_opt_reset")
check(w.seconds_feed() == nil, "no seconds in effect → no feed")
w.fact.clock_seconds = true
w.fire("fact:clock_seconds")
check(w.seconds_feed() ~= nil and w.card(1).sec == 1 and w.card(4).sec == 1, "the shell's default makes Automatic clocks show seconds (and starts the feed)")
w.fire("w_configure", 4)
opt(w, "seconds", 3)
check(w.card(4).sec == 0 and w.card(1).sec == 1 and w.seconds_feed() ~= nil, "Hide wins over the default")
w.fact.widgets_on = false
w.fact.editing = false
w.fire("fact:widgets_on")
check(w.seconds_feed() == nil, "hidden widgets tick nothing")
w.fact.widgets_on = true
w.fire("fact:widgets_on")
check(w.seconds_feed() ~= nil, "shown again → feed again")
w.fact.clock_seconds = false
w.fire("fact:clock_seconds")
check(w.seconds_feed() == nil and w.card(1).sec == 0, "default off → the feed is cancelled")
w.fact.editing = true

-- lock rules
reset_home()
put("widgets.json", json.encode({ version = 2, snap = true, next = 20, cards = {
    { id = 1, out = "HDMI-A-1", kind = 1, sz = 1, x = 48, y = 72, opts = { lock = true } },
    { id = 2, out = "HDMI-A-1", kind = 3, sz = 0, x = 48, y = 248 },
    { id = 3, out = "HDMI-A-1", kind = 2, sz = 0, x = 1700, y = 72, opts = { lock = true } },
    { id = 4, out = "HDMI-A-1", kind = 5, sz = 0, x = 500, y = 500 },
    { id = 5, out = "HDMI-A-1", kind = 4, sz = 0, x = 900, y = 700, opts = { lock = true } },
} }))
local k = boot()
open_bar(k)
check(k.card(1).locked == 1 and k.card(3).locked == 1 and k.card(2).locked == 0, "locks load from widgets.json")
k.fact.drag_id, k.fact.drag_dx, k.fact.drag_dy = 1, 200, 100
k.fire("w_drop", 1)
check(k.card(1).x == 48 and k.card(1).y == 72 and k.fact.drag_id == 0 and k.fact.drag_dx == 0, "a locked card does not move on drop; the drag is cleared")
k.fact.drag_id, k.fact.drag_dx, k.fact.drag_dy = 4, 300, 0
k.fire("w_drop", 4)
check(k.card(4).x ~= 500, "an unlocked card still moves")
-- resize of a locked card stays in place
k.fire("w_resize", 1)
check(k.card(1).sz == 0 and k.card(1).x == 48 and k.card(1).y == 72, "locked resize: medium → large does not fit (it would hit the card below) → next size that fits, in place")
k.fire("w_resize", 1)
check(k.card(1).sz == 1 and k.card(1).x == 48 and k.card(1).y == 72, "…and cycles on in place")
k.fire("w_resize", 3)
check(k.card(3).sz == 0 and k.bar().st and k.bar().st.msg:find("Locked in place"), "a locked card with no size that fits stays as it is and says so")
k.fire("w_tidy")
check(k.card(1).x == 48 and k.card(1).y == 72 and k.card(3).x == 1700 and k.card(5).x == 900 and k.card(5).y == 700, "Tidy up leaves locked cards where they are")
local clash = false
for _, a in ipairs(k.model.ws) do
    for _, c2 in ipairs(k.model.ws) do
        if a.id < c2.id and a.scr == c2.scr then
            local function wd(r) return r.sz == 0 and 160 or 336 end
            local function ht(r) return r.sz == 2 and 336 or 160 end
            if a.x < c2.x + wd(c2) and a.x + wd(a) > c2.x and a.y < c2.y + ht(c2) and a.y + ht(a) > c2.y then clash = true end
        end
    end
end
check(not clash, "…and the others are packed around them without overlap")
k.fire("w_remove", 5)
check(k.card(5) == nil, "a locked card can still be removed (position lock only)")
k.fire("w_undo")
check(k.card(5) and k.card(5).locked == 1, "…and undo brings its lock back")
k.fire("w_configure", 5)
k.fire("w_remove", 5)
check(k.fact.sel_id == 0 and k.bar().sel == 0, "removing the selected card clears the selection")
k.fire("w_undo")
k.fire("w_configure", 5)
check(k.fact.sel_id == 5, "reselect after undo")
k.fire("w_preset", 5)
check(k.fact.sel_id == 0 and #k.model.ws == 0, "a preset replaces the desktop and clears the selection")
k.fire("w_undo")
check(k.card(5) and k.card(5).locked == 1 and k.card(1).locked == 1, "one undo brings the locked desktop back")
k.fire("w_configure", 1)
k.fire("edit_done")
check(k.fact.editing == false and k.fact.sel_id == 0 and k.bar().sel == 0 and k.bar().editing == false, "leaving edit mode clears the selection")
k.fire("w_configure", 1)
check(k.fact.sel_id == 0, "…and nothing can be selected outside it")

-- widgets.json migration
reset_home()
put("widgets.json", json.encode({ version = 1, snap = false, next = 7, cards = {
    { id = 1, out = "HDMI-A-1", kind = 1, sz = 1, x = 100, y = 100 }, { id = 6, out = "DP-1", kind = 3, sz = 0, x = 48, y = 72 } } }))
local m = boot()
check(#m.model.ws == 2 and m.card(1).x == 100 and m.card(1).locked == 0 and m.fact.snap_on == false, "a legacy file loads as it was (positions, Grid off)")
local mj = m.saved()
check(mj.version == 2 and mj.snap == false and mj.next == 7 and #mj.cards == 2 and mj.cards[1].opts == nil and mj.cards[1].x == 100, "…and is rewritten as version 2 with nothing lost")
check(not exists("widgets.json.v1") and not exists("widgets.json.v2"), "no copy is made for a legacy or current file")
reset_home()
put("widgets.json", json.encode({ snap = true, cards = { { id = 2, out = "DP-1", kind = 3, sz = 0, x = 48, y = 72 } } }))
m = boot()
check(m.card(2) and m.saved().version == 2, "a file with no version at all counts as legacy")
reset_home()
put("widgets.json", "not json {")
m = boot()
check(#m.model.ws == 6, "a corrupt file falls back to the defaults (as before)")
reset_home()
local newer_body = json.encode({ version = 5, snap = true, next = 3, cards = { { id = 1, out = "HDMI-A-1", kind = 1, sz = 1, x = 48, y = 72, opts = { lock = true, flavour = "x" } } } })
put("widgets.json", newer_body)
m = boot()
check(m.card(1) and m.card(1).locked == 1, "a newer file is read for what this build understands")
check(exists("widgets.json.v5") and get("widgets.json.v5") == newer_body, "the newer file is kept beside it before the first save")
check(m.saved().version == 2, "…and the live file is then rewritten in the current version")
m = boot()
check(get("widgets.json.v5") == newer_body, "the kept copy is never replaced by a later start")

-- saved desktops keep options, one undo step, and a version 1 layouts file still loads
reset_home()
put("widgets.json", json.encode({ version = 2, snap = true, next = 3, cards = {
    { id = 1, out = "HDMI-A-1", kind = 1, sz = 1, x = 48, y = 72, opts = { lock = true, seconds = "on" } },
    { id = 2, out = "HDMI-A-1", kind = 3, sz = 0, x = 48, y = 248 } } }))
put("widget-layouts.json", json.encode({ version = 1, next_id = 2, layouts = { { id = 1, name = "Legacy", created = 1, updated = 1, snap = true,
    cards = { { id = 1, out = "HDMI-A-1", kind = 1, sz = 0, x = 48, y = 72 } } } } }))
local d = boot()
check(d.text.wl_status ~= nil and #json.decode(d.text.wl_snapshot).layouts == 1 and json.decode(d.text.wl_snapshot).v == 1, "a version 1 layouts file loads; the bar's snapshot keeps its own version")
d.text.wl_name = "With options"
d.fire("wl_save")
d.run_timers()
local lf = json.decode(get("widget-layouts.json"))
check(lf.version == 2 and #lf.layouts == 2, "saving rewrites the layouts file as version 2 (the old layout is kept)")
check(same(lf.layouts[2].cards[1].opts, { lock = true, seconds = "on" }) and lf.layouts[2].cards[2].opts == nil and lf.layouts[1].cards[1].opts == nil, "the saved desktop holds each card's options")
open_bar(d)
d.fire("w_configure", 1)
d.fire("w_opt_reset")
check(d.card(1).locked == 0 and d.card(1).sec == 0, "options reset on the live desktop")
d.fire("wl_load", 2)
d.run_timers()
check(d.card(1).locked == 1 and d.card(1).sec == 1 and d.fact.sel_id == 0, "loading the saved desktop restores the options and clears the selection")
check(d.seconds_feed() ~= nil, "…and the seconds feed follows")
d.fire("w_undo")
check(d.card(1).locked == 0 and d.card(1).sec == 0, "the load was ONE undo step: the options are back as before the load")
local snap = json.decode(d.text.wl_snapshot)
check(snap.current == 0, "the live desktop no longer matches the saved one after an option change")
d.fire("wl_load", 2)
snap = json.decode(d.text.wl_snapshot)
check(snap.current == 2, "…and matches it again after loading")
opt(d, "date", 3)
snap = json.decode(d.text.wl_snapshot)
check(snap.current == 2, "(no selection: the refused option change leaves the desktop matching)")
d.fire("w_configure", 1)
opt(d, "date", 3)
snap = json.decode(d.text.wl_snapshot)
check(snap.current == 0, "an option change makes the live desktop differ from its saved layout")

os.execute("rm -rf " .. shq(HOME))
print(string.format("widget-options: %d checks passed", passed))
