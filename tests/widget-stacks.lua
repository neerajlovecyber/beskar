-- Manual widget stacks (C4c): lua tests/widget-stacks.lua
-- Part 1: shell/widget_stacks.luau as pure logic (join, page, leave, normalize, sizes, lock, bar info).
-- Part 2: widgets.json / widget-layouts.json keep stacks (version 3 only when stacked; older files and newer files).
-- Part 3: the real shell/widgets.luau in a sandbox with a throw-away HOME (events, model, feeds, persistence, undo).
-- Nothing touches the real session or ~/.config.
package.path = "shell/?.luau;" .. package.path
local Data = dofile("shell/widgets_data.luau")
local KINDS = Data.KINDS
local O = dofile("shell/widget_options.luau")
local St = dofile("shell/widget_stacks.luau")
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

-- ══ part 1: the pure logic ══
local function card(id, kind, sz, x, y, out, opts) return { id = id, out = out or "A", kind = kind, sz = sz, x = x or 48, y = y or 72, opts = opts } end
local function desk()
    return { card(1, 3, 0, 48, 72), card(2, 5, 0, 224, 72), card(3, 8, 0, 400, 72), card(4, 6, 1, 48, 248), card(5, 3, 0, 48, 72, "B") }
end
local c = desk()
check(St.join_refusal(c, c[2], c[1], kind_of) == nil, "two compatible cards can stack")
check(St.join(c, c[2], c[1], kind_of), "join works")
check(c[1].stack and c[2].stack and c[1].stack.id == c[2].stack.id and not c[1].stack.on and c[2].stack.on, "the joined card becomes the shown face")
check(c[2].x == 48 and c[2].y == 72 and c[2].sz == 0 and c[2].out == "A", "the source takes the target's footprint")
check(c[1].stack.i == 1 and c[2].stack.i == 2 and St.active(c, c[1]) == c[2], "page order and the active face")
check(St.hidden(c[1]) and not St.hidden(c[2]) and not St.hidden(c[3]), "only the non-face member is hidden")
check(St.join(c, c[3], c[1], kind_of) and #St.members(c, c[1]) == 3 and c[3].stack.on and not c[2].stack.on, "a third joins at the end of the SAME stack (target may be any member)")
check(c[3].stack.i == 3 and St.next_id(c) == 2, "orders 1..3, next stack id")
check(St.join_refusal(c, c[1], c[3], kind_of) == "same", "already in one stack")
check(St.join_refusal(c, c[4], c[1], kind_of) == "size", "a kind that does not come in the stack's size is refused (music is medium only)")
check(St.join_refusal(c, c[5], c[1], kind_of) == "output", "stacks stay on one display")
check(St.join_refusal(c, nil, c[1], kind_of) == "missing", "missing")
local lk = desk(); lk[1].opts = { lock = true }
check(St.join_refusal(lk, lk[1], lk[2], kind_of) == "locked", "a locked card does not move into a stack")
check(St.join(lk, lk[2], lk[1], kind_of) and lk[2].opts and lk[2].opts.lock == true, "stacking ONTO a locked card locks the newcomer (the lock is stack-wide)")

-- paging
local p = St.page(c, c[1], 1)
check(p == c[1] and c[1].stack.on and not c[3].stack.on, "next wraps from the last to the first")
check(St.page(c, c[1], -1) == c[3] and St.page(c, c[1], -1) == c[2], "previous walks back")
check(St.page(c, c[4], 1) == nil, "a card that is not stacked does not page")
local ons = 0
for _, m in ipairs(c) do if m.stack and m.stack.on then ons = ons + 1 end end
check(ons == 1, "exactly one face")

-- leaving
local lv = desk(); St.join(lv, lv[2], lv[1], kind_of); St.join(lv, lv[3], lv[1], kind_of)
check(St.leave(lv, lv[3]) and lv[3].stack == nil and lv[2].stack.on and lv[2].stack.i == 2, "leaving the face shows a neighbour and closes up")
check(St.leave(lv, lv[1]) and lv[1].stack == nil and lv[2].stack == nil, "a stack left with one member dissolves")
check(not St.leave(lv, lv[1]), "leaving when not stacked is a no-op")

-- sizes: a stack is resized as a whole
local sz = desk(); St.join(sz, sz[2], sz[1], kind_of)
check(same(St.sizes(sz, sz[1], kind_of), { 0, 1, 2 }), "weather + system share three sizes")
sz[3].sz = 0; St.join(sz, sz[3], sz[1], kind_of)
check(same(St.sizes(sz, sz[1], kind_of), { 0, 1 }), "day (small, medium only) narrows the stack's sizes")
check(same(St.sizes(sz, sz[4], kind_of), { 1 }), "a loose card keeps its own kind's sizes")

-- lock
local sl = desk(); St.join(sl, sl[2], sl[1], kind_of)
sl[2].opts = { lock = true }
St.set_lock(sl, sl[2], true)
check(sl[1].opts and sl[1].opts.lock == true, "set_lock locks every member")
sl[1].opts.date = nil
St.set_lock(sl, sl[2], false)
check(sl[1].opts == nil, "…and unlocks them again, dropping an empty opts table")

-- info for the bar
local inf = St.info(c, c[4], kind_of)
check(inf.id == 0 and inf.n == 1 and #inf.m == 0, "a loose card: id 0, one page, no members")
local picks = {}
for _, e in ipairs(inf.pick) do picks[e[1]] = e[2] end
check(picks[1] == nil and picks[2] == nil and picks[5] == nil, "music (medium) can stack onto nothing here: wrong size, other display")
local c2 = desk()
St.join(c2, c2[2], c2[1], kind_of)
local inf2 = St.info(c2, c2[3], kind_of)
check(#inf2.pick == 2 and inf2.pick[1][1] == 2 and inf2.pick[1][2] == 5 and inf2.pick[2][1] == 4, "one pick per stack: its shown face as { card id, kind } (the day card may also join the medium music card: it draws medium)")
local inf3 = St.info(c2, c2[2], kind_of)
check(inf3.id == 1 and inf3.n == 2 and inf3.i == 2 and #inf3.m == 2 and inf3.m[1][1] == 1 and inf3.m[2][1] == 2 and inf3.pick[1][1] == 3, "stack info: id, count, page, members in page order, picks outside the stack")

-- normalize repairs hand-made data
local bad = desk()
bad[1].stack = { id = 7, i = 1, on = true }
bad[2].stack = { id = 7, i = 1, on = true }               -- two faces, same order
bad[3].stack = { id = 7, i = 9 }                           -- different position → leaves
bad[4].stack = { id = 8, i = 1 }                           -- alone → dissolves
bad[5].stack = "junk"
bad[2].x, bad[2].y = 48, 72
check(St.normalize(bad, kind_of), "normalize reports a repair")
check(bad[3].stack == nil and bad[4].stack == nil and bad[5].stack == nil, "a member elsewhere leaves, a lone card and junk lose the stack")
check(bad[1].stack and bad[2].stack and bad[1].stack.i == 1 and bad[2].stack.i == 2 and (bad[1].stack.on ~= nil) ~= (bad[2].stack.on ~= nil), "two faces become one, orders renumber")
check(not St.normalize(bad, kind_of), "a valid stack is left alone")
local sizes_bad = { card(1, 6, 1, 48, 72), card(2, 3, 1, 48, 72) }   -- music + weather medium: fine
sizes_bad[1].stack, sizes_bad[2].stack = { id = 1, i = 1, on = true }, { id = 1, i = 2 }
check(not St.normalize(sizes_bad, kind_of) and sizes_bad[1].stack, "kinds that share the size stay stacked")
sizes_bad[1].sz, sizes_bad[2].sz = 0, 0       -- music does not draw small
St.normalize(sizes_bad, kind_of)
check(sizes_bad[1].stack == nil and sizes_bad[2].stack == nil, "a face whose size its kind does not draw dissolves the stack")
local many = {}
for i = 1, 10 do many[i] = card(i, 3, 0); many[i].stack = { id = 1, i = i, on = (i == 1) or nil } end
St.normalize(many, kind_of)
local n_in = 0
for _, m in ipairs(many) do if m.stack then n_in = n_in + 1 end end
check(n_in == St.MAX_MEMBERS, "a stack never exceeds MAX_MEMBERS")
local lockn = desk(); St.join(lockn, lockn[2], lockn[1], kind_of); lockn[1].opts = { lock = true }; St.normalize(lockn, kind_of)
check(lockn[2].opts and lockn[2].opts.lock, "normalize makes the lock stack-wide")

-- ══ part 2: files ══
local st_cards = { card(1, 3, 0, 48, 72), card(2, 5, 0, 48, 72), card(3, 1, 1, 400, 72, "A", { lock = true }) }
st_cards[1].stack, st_cards[2].stack = { id = 1, i = 1 }, { id = 1, i = 2, on = true }
local f = O.encode_file(st_cards, 4, true)
check(f.version == 3 and f.cards[1].stack.id == 1 and f.cards[2].stack.on == true and f.cards[1].stack.on == nil and f.cards[3].stack == nil, "a desktop with a stack is written as version 3")
check(O.encode_file({ card(1, 3, 0) }, 2, true).version == 2, "…without one it is still version 2 (an older Beskar keeps reading it)")
local back = O.decode_file(json.decode(json.encode(f)), kind_of)
check(not back.newer and back.cards[1].stack.id == 1 and back.cards[2].stack.on and back.cards[3].stack == nil, "stacks round-trip through the file")
local hand = O.decode_file({ version = 3, next = 9, cards = {
    { id = 1, out = "A", kind = 3, sz = 0, x = 1, y = 1, stack = { id = 1, i = 1, on = true } },
    { id = 2, out = "A", kind = 5, sz = 0, x = 99, y = 1, stack = { id = 1, i = 2 } },
    { id = 3, out = "A", kind = 5, sz = 0, x = 5, y = 5, stack = { id = "x", i = -1 } } } }, kind_of)
check(hand.cards[1].stack == nil and hand.cards[2].stack == nil and hand.cards[3].stack == nil, "a damaged stack in the file is repaired on read, cards kept")
local fut = O.decode_file({ version = 9, next = 3, cards = {
    { id = 1, out = "A", kind = 3, sz = 0, x = 1, y = 1, stack = { id = 1, i = 1, on = true, future = "x" } },
    { id = 2, out = "A", kind = 5, sz = 0, x = 1, y = 1, stack = { id = 1, i = 2 } } } }, kind_of)
check(fut.newer and fut.cards[1].stack and fut.cards[2].stack and fut.cards[1].stack.future == nil, "a newer file's stacks are still read (what this build knows)")
check(O.snapshot(st_cards[2], { stack = function(cd) return St.info(st_cards, cd, kind_of) end }).stack.n == 2, "the options snapshot carries the stack")
check(O.snapshot(st_cards[2], {}).stack == nil, "…only when the host asks")

-- saved desktops
local lcards = { card(1, 3, 0, 48, 72), card(2, 5, 0, 48, 72), card(3, 1, 1, 400, 72) }
lcards[1].stack, lcards[2].stack = { id = 4, i = 1 }, { id = 4, i = 2, on = true }
local body = L.capture(lcards, true, { A = { 1920, 1080 } })
check(body.cards[1].stack and body.cards[1].stack.id == 4 and body.cards[2].stack.on, "a saved desktop captures stacks")
local store = L.new_store()
store.layouts[1] = { id = 1, name = "S", created = 1, updated = 1, snap = true, areas = {}, cards = body.cards }
local text = L.encode(store, json)
check(json.decode(text).version == 3, "a layouts file with a stack is version 3: an older Beskar reads it as newer and leaves it alone")
local plain = L.new_store(); plain.layouts[1] = { id = 1, name = "P", created = 1, updated = 1, snap = true, areas = {}, cards = { card(1, 3, 0) } }
check(json.decode(L.encode(plain, json)).version == 2, "…and without stacks it stays version 2")
local ls = L.decode(text, json)
check(ls and ls.layouts[1].cards[2].stack.on == true, "stacks survive decode")
check(L.signature(lcards) ~= L.signature({ card(1, 3, 0, 48, 72), card(2, 5, 0, 48, 72), card(3, 1, 1, 400, 72) }), "membership is part of what a layout is")
local flip = {}
for i, cd in ipairs(lcards) do flip[i] = L.copy(cd) end
flip[1].stack.on, flip[2].stack.on = true, nil
check(L.signature(lcards) == L.signature(flip), "…the shown face is not (paging never makes a layout look edited)")
-- restore: a stack is ONE footprint through clamp / reflow
local layout = ls.layouts[1]
layout.cards[1].x, layout.cards[1].y, layout.cards[2].x, layout.cards[2].y = 1700, 900, 1700, 900
local geom = { unit = 160, gap = 16, top = 40, side = 12, bottom = 60, ox = 48, oy = 72, def_w = 1920, def_h = 1080 }
local out, rep = L.restore(layout, { connected = { A = true }, sizes = { A = { 800, 600 } }, kind_of = kind_of, limit = 16, geom = geom })
check(out[1].stack and out[2].stack and rep.moved >= 1, "a stack is clamped onto a smaller screen as one footprint")
check(out[1].x == out[2].x and out[1].y == out[2].y and out[1].x <= 800 - 160 - 12, "members still share their place")
check(layout.cards[1].x == 1700, "the stored layout is untouched")
local gone = L.restore(layout, { connected = { A = true }, sizes = {}, kind_of = function(k) return k ~= 5 and KINDS[k] or nil end, limit = 16, geom = geom })
check(gone[1].stack == nil and #gone == 2, "a kind that is gone leaves a one-member stack as a plain card")
local away = L.restore(layout, { connected = { Z = true }, sizes = {}, kind_of = kind_of, limit = 16, geom = geom })
check(away[1].stack and away[2].stack and away[2].x == 1700, "a stack on a disconnected output is kept as it was")
check(L.bar_snapshot({ layouts = { { id = 1, name = "N", cards = 3, outputs = 1 } } }).layouts[1][2] == "N", "the bar's packed layout rows are unchanged")

-- ══ part 3: the real widgets.luau ══
-- defaults: ids 1 clock(M) · 2 weather(S) · 3 system(S) on HDMI-A-1, 4 clock · 5 weather · 6 system on DP-1
local function rows_on(w, scr) local n = 0; for _, r in ipairs(w.model.ws) do if r.scr == scr then n = n + 1 end end; return n end
reset_home()
local w = boot()
open_bar(w)
check(#w.model.ws == 6 and w.card(2).sn == 0 and w.card(2).si == 0, "unstacked cards have no pager")
w.fire("w_stack", 3)
check(w.bar().st and w.bar().st.ok == false and #w.model.ws == 6, "stacking with nothing selected is refused and the bar is told")
w.fire("w_configure", 2)
local b = w.bar()
check(b.stack and b.stack.n == 1 and b.stack.id == 0 and #b.stack.pick == 2 and b.stack.pick[1][1] == 1 and b.stack.pick[2][1] == 3 and b.stack.pick[2][2] == 5, "the bar's snapshot offers the cards on the same display whose size the card draws (clock M, system S), none on the other display")
w.fire("w_stack", 3)
check(#w.model.ws == 5 and w.card(3) == nil and w.card(2).sn == 2 and w.card(2).si == 2, "stacked: the hidden member leaves the model, the face carries its page")
check(w.card(2).x == 224 and w.card(2).y == 248 and w.fact.sel_id == 2, "the face sits on the stack's footprint, still selected")
local b2 = w.bar()
check(b2.stack.n == 2 and b2.stack.i == 2 and b2.stack.m[1][1] == 3 and b2.stack.m[2][1] == 2, "bar: members in page order")
w.run_timers()
local disk = w.saved()
local dc = {}
for _, k in ipairs(disk.cards) do dc[k.id] = k end
check(disk.version == 3 and dc[2].stack.on == true and dc[3].stack.i == 1 and dc[3].stack.on == nil and dc[3].x == 224 and dc[3].y == 248, "persisted as version 3 with membership, face and a shared footprint")
w.fire("w_undo")
w.run_timers()
check(#w.model.ws == 6 and w.card(3) and w.card(2).sn == 0 and w.saved().version == 2, "stacking is ONE undo step, and the file goes back to version 2")
w.fire("w_stack", 3)

-- paging works outside edit mode too, is saved, and is not an undo step
w.fire("edit_done")
check(w.fact.editing == false and w.card(2).si == 2, "edit mode ended")
w.fire("w_page_prev", 2)
check(w.card(3) and w.card(2) == nil and w.card(3).si == 1 and w.card(3).sn == 2 and w.card(3).x == 224, "previous: the other member is the face (outside edit mode)")
w.fire("w_page_next", 3)
check(w.card(2) and w.card(3) == nil, "next wraps back")
w.fire("w_page_next", 3)               -- an id of a HIDDEN member still pages its stack
check(w.card(3) and w.card(2) == nil, "a hidden member's id pages its stack")
w.run_timers()
local face_saved
for _, k in ipairs(w.saved().cards) do if k.stack and k.stack.on then face_saved = k.id end end
check(face_saved == 3, "the face is saved")
w.fire("w_undo")
check(#w.model.ws == 6 and w.card(2) and w.card(2).sn == 0, "Undo takes back the STACKING, not the paging")
open_bar(w)
w.fire("w_configure", 2)
w.fire("w_stack", 3)
w.fire("w_page_prev", 2)
check(w.card(3) and w.card(2) == nil and w.fact.sel_id == 3, "the selection follows the face while paging")
w.fire("w_page_next", 0)
check(w.card(2) and w.card(3) == nil and w.fact.sel_id == 2 and w.bar().sel == 2, "id 0 pages the SELECTED card's stack")

-- reload: the stack is back, with the same face
w.run_timers()
local kept = get("widgets.json")
check(w.card(2) and w.card(2).sn == 2, "(face before reload: weather)")
local w2 = boot()
check(#w2.model.ws == 5 and w2.card(2) and w2.card(3) == nil and w2.card(2).sn == 2 and w2.card(2).si == 2 and w2.card(2).x == 224, "after a restart the stack and its face come back")
check(w2.saved().version == 3, "…and is rewritten as version 3")

-- drag moves the whole stack; hidden members follow
open_bar(w2)
w2.fact.drag_id, w2.fact.drag_dx, w2.fact.drag_dy = 2, 400, 0
w2.fire("w_drop", 2)
local d = {}
for _, k in ipairs(w2.saved().cards) do d[k.id] = k end
w2.run_timers()
d = {}
for _, k in ipairs(w2.saved().cards) do d[k.id] = k end
check(d[2].x == d[3].x and d[2].y == d[3].y and d[2].x ~= 224, "dragging the face moves every member")
check(w2.card(2).x == d[2].x, "…and the face in the model")

-- resize is common to every member
w2.fire("w_configure", 2)
w2.fire("w_resize", 2)
w2.run_timers()
d = {}
for _, k in ipairs(w2.saved().cards) do d[k.id] = k end
check(d[2].sz == 1 and d[3].sz == 1 and w2.card(2).sz == 1, "resizing a stack resizes every member (weather + system: small → medium)")
w2.fire("w_resize", 2); w2.fire("w_resize", 2)
check(w2.card(2).sz == 0, "…cycling through the sizes they share")

-- lock is stack-wide, and a locked stack keeps its members
opt(w2, "lock", 2)
w2.run_timers()
d = {}
for _, k in ipairs(w2.saved().cards) do d[k.id] = k end
check(d[2].opts and d[2].opts.lock and d[3].opts and d[3].opts.lock and w2.card(2).locked == 1, "locking the face locks the whole stack")
w2.fire("w_unstack", 2)
check(w2.bar().st.ok == false and w2.card(2).sn == 2, "a locked stack refuses to be taken apart")
w2.fire("w_eject", 2)
check(w2.card(2).sn == 2, "…or to lose a member")
w2.fire("w_stack", 1)
check(w2.card(2).sn == 2, "…and a locked card cannot be stacked away")
opt(w2, "lock", 1)
check(w2.card(2).locked == 0, "unlocking the face unlocks the stack")

-- stacking refusals
w2.fire("w_add", 6)
local music
for _, r in ipairs(w2.model.ws) do if r.kind == 6 then music = r.id end end
w2.fire("w_configure", music)
w2.fire("w_stack", 2)
check(w2.bar().st.ok == false and w2.card(music).sn == 0 and w2.card(2).sn == 2, "a music card (medium only) cannot join a small stack")
w2.fire("w_remove", music)
w2.fire("w_configure", 5)
w2.fire("w_stack", 2)
check(w2.bar().st.ok == false and w2.card(5).sn == 0 and w2.card(2).sn == 2, "…nor a card on another display")
w2.fire("w_configure", 2)
w2.fire("w_stack", 3)
check(w2.card(2).sn == 2, "…stacking a member onto its own stack changes nothing")

-- eject / unstack
w2.fire("w_eject", 2)
check(w2.card(2) and w2.card(2).sn == 0 and w2.card(3) and w2.card(3).sn == 0, "ejecting from a pair leaves two plain cards")
check(not (w2.card(2).x == w2.card(3).x and w2.card(2).y == w2.card(3).y), "…on different cells")
w2.fire("w_undo")
check(w2.card(2).sn == 2 and w2.card(3) == nil, "ejecting is one undo step")

-- three in a stack: remove the face, unstack the rest
w2.fire("w_add", 8)                      -- a Day card (small by default) on the first display
local day
for _, r in ipairs(w2.model.ws) do if r.kind == 8 then day = r.id end end
check(day ~= nil and w2.card(day).sz == 0, "a Day card was added")
w2.fire("w_configure", day)
w2.fire("w_stack", 2)
check(w2.card(day) and w2.card(day).sn == 3 and w2.card(day).si == 3 and w2.card(2) == nil, "a third card joins the stack and is shown")
w2.fire("w_remove", day)
check(w2.card(2) and w2.card(2).sn == 2 and w2.card(2).si == 2 and w2.card(3) == nil, "removing the face keeps the other two stacked")
w2.fire("w_configure", 2)
w2.fire("w_unstack", 0)
check(w2.card(2) and w2.card(3) and w2.card(2).sn == 0 and w2.card(3).sn == 0, "unstack (id 0 = the selected card's) breaks the stack apart")
w2.fire("w_undo")
check(w2.card(2) and w2.card(2).sn == 2 and w2.card(3) == nil, "…as one undo step")

-- tidy keeps the stack together
w2.fire("w_tidy")
w2.run_timers()
d = {}
for _, k in ipairs(w2.saved().cards) do d[k.id] = k end
check(d[2].stack and d[3].stack and d[2].x == d[3].x and d[2].y == d[3].y, "Tidy up packs a stack as one footprint")

-- the 16-card bound counts hidden members
reset_home()
local f16 = {}
for i = 1, 16 do f16[i] = { id = i, out = "HDMI-A-1", kind = 3, sz = 0, x = 48 + (i - 1) % 8 * 176, y = 72 + math.floor((i - 1) / 8) * 176 } end
for i = 2, 5 do f16[i].x, f16[i].y = 48, 72; f16[i].stack = { id = 1, i = i }; end
f16[1].stack = { id = 1, i = 1, on = true }
put("widgets.json", json.encode({ version = 3, snap = true, next = 17, cards = f16 }))
local w3 = boot()
check(#w3.model.ws == 12 and w3.card(1).sn == 5, "16 cards, 5 of them one stack: 12 faces in the model")
open_bar(w3)
w3.fire("w_add", 3)
check(#w3.saved().cards == 16, "adding past 16 cards (hidden members count) is refused")

-- hidden members start no feed and no tick
reset_home()
put("widgets.json", json.encode({ version = 3, snap = true, next = 5, cards = {
    { id = 1, out = "HDMI-A-1", kind = 1, sz = 1, x = 48, y = 72, opts = { seconds = "on" }, stack = { id = 1, i = 1, on = true } },
    { id = 2, out = "HDMI-A-1", kind = 5, sz = 1, x = 48, y = 72, stack = { id = 1, i = 2 } },
    { id = 3, out = "HDMI-A-1", kind = 6, sz = 1, x = 400, y = 72 } } }))
local w4 = boot()
local function stats_feed() for _, j in ipairs(w4.everys) do if j.ms == 3000 and not j.canceled then return j end end end
check(w4.seconds_feed() ~= nil and stats_feed() == nil, "the face (a clock with seconds) ticks; the hidden system card starts no stats feed")
w4.fire("w_page_next", 1)
check(w4.seconds_feed() == nil and stats_feed() ~= nil, "paging to the system card stops the seconds tick and starts the stats feed")
w4.fire("w_page_next", 1)
check(w4.seconds_feed() ~= nil and stats_feed() == nil, "paging back reverses it: nothing runs for a hidden face")
local clocks = 0
for _, r in ipairs(w4.model.ws) do if r.kind == 1 then clocks = clocks + 1 end end
check(clocks == 1 and #w4.model.ws == 2, "the model holds only faces")

-- a file from a newer Beskar is kept before it is replaced
reset_home()
local newer_body = json.encode({ version = 5, snap = true, next = 4, cards = {
    { id = 1, out = "HDMI-A-1", kind = 3, sz = 0, x = 48, y = 72, stack = { id = 2, i = 1, on = true, flavour = "x" } },
    { id = 2, out = "HDMI-A-1", kind = 5, sz = 0, x = 48, y = 72, stack = { id = 2, i = 2 } } } })
put("widgets.json", newer_body)
local w5 = boot()
check(w5.card(1) and w5.card(1).sn == 2, "a newer file's stacks are read")
check(get("widgets.json.v5") == newer_body and w5.saved().version == 3, "…the original is kept beside it, and the live file is rewritten as version 3")

-- saved desktops keep stacks
reset_home()
local w6 = boot()
open_bar(w6)
w6.fire("w_configure", 2)
w6.fire("w_stack", 3)
w6.text.wl_name = "Stacked"
w6.fire("wl_save")
w6.run_timers()
local lf = json.decode(get("widget-layouts.json"))
check(lf.version == 3 and lf.layouts[1].cards[2].stack and lf.layouts[1].cards[2].stack.on == true, "the layouts file is version 3 and holds the stack")
local cur = json.decode(w6.text.wl_snapshot).current
check(cur == 1, "the live desktop IS the saved layout")
w6.fire("w_page_prev", 2)
check(json.decode(w6.text.wl_snapshot).current == 1, "paging does not make it look edited")
w6.fire("w_remove", 2)
w6.fire("w_remove", 3)
check(#w6.model.ws == 4, "(both members removed)")
w6.fire("wl_load", 1)
w6.run_timers()
check(w6.card(2) and w6.card(2).sn == 2 or w6.card(3) and w6.card(3).sn == 2, "loading the layout brings the stack back")
w6.fire("w_undo")
check(#w6.model.ws == 4, "…as one undo step")

os.execute("rm -rf " .. shq(HOME))
print(string.format("widget-stacks: %d checks passed", passed))
