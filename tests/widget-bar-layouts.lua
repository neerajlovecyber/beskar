-- The widget bar's Desktops page (C4a UI): lua tests/widget-bar-layouts.lua
-- Part 1 tests shell/widget_bar_layouts.luau with a fake host (snapshot parsing incl. the compact bridge form,
-- selection / paging, two-press confirmation, busy, status handling, what is asked of Widgets).
-- Part 2 compiles-in-text checks that dockpanels.plm / dockpanels.luau really wire the contract.
-- Nothing touches the real session, Widgets or ~/.config.
package.path = "shell/?.luau;" .. package.path
local B = dofile("shell/widget_bar_layouts.luau")
local passed = 0
local function check(v, why) if not v then error("FAILED: " .. why, 2) end passed = passed + 1 end
local function eq(a, b, why) if a ~= b then error("FAILED: " .. why .. " (got " .. tostring(a) .. ", wanted " .. tostring(b) .. ")", 2) end passed = passed + 1 end

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


-- ── a fake host ──
local function make()
    local h = { said = {}, timers = {}, views = {}, cleared = 0, pages = {}, say_ok = true }
    h.json = json
    h.say = function(words)
        if not h.say_ok then return false end
        h.said[#h.said + 1] = words
        return true
    end
    h.after = function(ms, fn) h.timers[#h.timers + 1] = { ms = ms, fn = fn } end
    h.publish = function(v) h.views[#h.views + 1] = v end
    h.clear_name = function() h.cleared = h.cleared + 1 end
    h.page_changed = function(p) h.pages[#h.pages + 1] = p end
    h.fire = function() local t = h.timers; h.timers = {}; for _, x in ipairs(t) do x.fn() end end
    h.ctl = B.controller(h)
    h.view = function() return h.ctl.view() end
    h.last_said = function() return h.said[#h.said] end
    return h
end

local function layouts(n, from)
    local t = {}
    for i = 1, n do t[i] = { id = (from or 0) + i, name = "Desk " .. ((from or 0) + i), cards = i % 17, outputs = 1 + i % 2 } end
    return t
end
local function snap_text(o)
    o = o or {}
    return json.encode({ v = 1, rev = o.rev or 1, ready = o.ready ~= false, state = o.state or "ok", writable = o.writable ~= false,
        max = 24, count = #(o.layouts or {}), current = o.current or 0, base = o.base or 0, layouts = o.layouts or {},
        status = { seq = o.seq or 0, ok = o.ok ~= false, code = o.code or "", msg = o.msg or "" } })
end

-- ── names ──
eq(B.clean("  a\tb  "), "a b", "clean collapses")
check(B.clean("   ") == nil, "blank is no name")
eq(utf8.len(B.clean(string.rep("é", 50))), 32, "cut at 32 characters")
check(B.clean(nil) == nil, "nil is no name")

-- ── parse ──
local v = B.parse(snap_text({ layouts = layouts(3), current = 2 }), json)
eq(#v.layouts, 3, "parsed three"); eq(v.current, 2, "current"); eq(v.layouts[1].cards, 1, "cards")
check(B.parse("not json", json) == nil, "garbage ignored")
check(B.parse(string.rep("x", 9000), json) == nil, "too long ignored")
check(B.parse(json.encode({ layouts = "x" }), json) == nil, "layouts must be a list")
-- tolerant: the full snapshot (with updated / snap) and an old-style entry without outputs
local full = json.encode({ v = 1, rev = 3, ready = true, state = "ok", writable = true, max = 24, count = 1, current = 0, base = 0,
    layouts = { { id = 7, name = "Full", cards = 2, outputs = 1, snap = true, updated = 1700000000 } }, status = { seq = 1, ok = true, code = "saved", msg = "Saved" } })
eq(B.parse(full, json).layouts[1].name, "Full", "full snapshot parses")
local many = {}
for i = 1, 40 do many[i] = { id = i, name = "n" .. i, cards = 1, outputs = 1 } end
eq(#B.parse(json.encode({ ready = true, layouts = many }), json).layouts, 24, "bounded to 24")
local bad = B.parse(json.encode({ ready = true, layouts = { { id = 1, name = "a" }, { id = 1, name = "dup" }, { id = "x", name = "b" }, { id = 2, name = "\n" } } }), json)
eq(#bad.layouts, 1, "duplicate / bad ids and blank names dropped")
-- the compact bridge form fits the IPC limit at the maximum (24 x 32-char names)
local worst = {}
for i = 1, 24 do worst[i] = { id = 2147483000 + i, name = string.rep("n", 32), cards = 16, outputs = 8 } end
local wire = snap_text({ layouts = worst, seq = 99999, msg = string.rep("m", 200) })
check(#wire < 4096 - #"text wb_layouts ", "24 maximal compact layouts fit one say (" .. #wire .. " bytes)")
check(#wire <= B.MAX_WIRE, "and the parser's own limit")

-- Real producer packing must also preserve 24 maximal UTF-8 / escaped names.
local L = dofile("shell/widget_layouts.luau")
local named = {}
for i = 1, 24 do named[i] = { id = 2147483000 + i, name = string.rep("界", 32), cards = 16, outputs = 16 } end
local original = json.decode(snap_text({ layouts = named, seq = 2147483647, msg = string.rep('"', 200) }))
local packed = json.encode(L.bar_snapshot(original))
check(#packed < 4000, "packed maximal UTF-8 names and escaped status fit the sender limit (" .. #packed .. ")")
local unpacked = B.parse(packed, json)
eq(#unpacked.layouts, 24, "all packed rows arrive")
eq(unpacked.layouts[24].name, named[24].name, "UTF-8 display names stay complete")
eq(original.layouts[1].name, named[1].name, "packing does not mutate the full snapshot")

-- ── an empty / waiting bar ──
local h = make()
v = h.view()
check(not v.ready and v.total == 0 and #v.rows == 0, "no snapshot: nothing to show")
check(v.hint:find("Waiting"), "waiting hint")
h.ctl.save()
check(#h.said == 0, "nothing is asked before Widgets answers")
eq(h.view().status, "Saved desktops are still loading", "says why")

-- ── a ready bar ──
h = make()
h.ctl.opened()
h.ctl.snapshot(snap_text({ layouts = layouts(12), current = 3, base = 5, seq = 4, msg = "stale" }))
v = h.view()
eq(v.total, 12, "12 layouts"); eq(#v.rows, 5, "5 rows drawn"); eq(v.rows[3].tag, "Current", "current tagged")
eq(v.sel_id, 3, "opens on the current layout")
eq(v.status, "", "the snapshot Widgets resends on open is not a new status")
h.ctl.snapshot(snap_text({ layouts = layouts(12), current = 0, base = 3, seq = 4 }))
eq(h.view().rows[3].tag, "Edited", "modified base is tagged Edited")
check(v.hint:find("Enter loads"), "Enter loads the selection when no name is typed")
eq(v.range, "1–5 of 12", "range")
-- keys: move / paging / wheel
h.ctl.move(1); eq(h.view().sel_id, 4, "Down"); h.ctl.move(-1); h.ctl.move(-1); eq(h.view().sel_id, 2, "Up")
h.ctl.move(-5); eq(h.view().sel_id, 1, "clamped at the first")
h.ctl.move(40); eq(h.view().sel_id, 12, "clamped at the last"); eq(h.view().top, 7, "the window follows the selection")
eq(h.view().rows[5].id, 12, "last row visible")
h.ctl.scroll(1); eq(h.view().top, 6, "wheel up shows earlier rows"); eq(h.view().sel_id, 12, "wheel keeps the selection")
eq(h.view().rows[1].id, 7, "rows follow the wheel (selection out of view stays out)")
h.ctl.scroll(-1); h.ctl.scroll(-1); eq(h.view().top, 7, "wheel stops at the end")
h.ctl.pick(2); eq(h.view().sel_id, 2, "click selects"); eq(h.view().top, 1, "and reveals it")
h.ctl.pick(999); eq(h.view().sel_id, 2, "unknown id ignored")

-- ── load: asked once, buttons wait for the answer ──
h.said = {}
h.ctl.load()
eq(#h.said, 1, "load says one thing"); eq(h.said[1], "emit wl_load 2", "load by id")
h.ctl.load(); eq(#h.said, 1, "a second press while waiting is ignored")
check(not h.view().can_load, "buttons are inactive while waiting")
h.ctl.snapshot(snap_text({ layouts = layouts(12), current = 2, base = 2, seq = 5, msg = "Loaded “Desk 2”" }))
eq(h.view().status, "Loaded “Desk 2”", "Widgets' words are shown"); check(h.view().status_ok, "ok status")
check(h.view().can_load, "buttons are back")
eq(h.view().rows[1].tag, "Current", "now current")
-- busy ends by itself when Widgets never answers
h.ctl.load(); check(not h.view().can_load, "waiting"); h.fire(); check(h.view().can_load, "released after the timeout")

-- ── save: name travels first; overwrite needs a second press ──
h = make()
h.ctl.opened(); h.ctl.snapshot(snap_text({ layouts = layouts(3) })); h.fire()
h.said = {}
h.ctl.submit(); eq(h.view().status, "Type a name to save this desktop", "Enter with nothing to do says so")
h.ctl.set_name("  Work   mode "); check(h.view().can_save and h.view().has_name, "can save a new name")
check(h.view().hint:find("“Work mode”"), "hint shows the cleaned name")
h.ctl.submit()
eq(h.said[1], "text wl_name Work mode", "name first, cleaned"); eq(h.said[2], "emit wl_save", "then the event")
check(not h.view().can_save, "waiting")
local w = layouts(3); w[4] = { id = 4, name = "Work mode", cards = 4, outputs = 1 }
h.ctl.snapshot(snap_text({ layouts = w, seq = 1, msg = "Saved “Work mode”", current = 4, base = 4 }))
eq(h.view().sel_id, 4, "the new desktop is selected"); eq(h.cleared, 2, "the name field is cleared (open + success)")
-- an existing name arms, a second press overwrites
h.said = {}
h.ctl.set_name("desk 2"); check(h.view().exists, "case-insensitive match"); check(h.view().hint:find("exists"), "hint warns")
h.ctl.save(); eq(#h.said, 0, "first press only arms"); eq(h.view().arm, 3, "armed"); check(h.view().hint:find("again"), "asks again")
h.ctl.set_name("desk 2 "); eq(h.view().arm, 3, "same name keeps the confirmation")
h.ctl.set_name("desk 22"); eq(h.view().arm, 0, "typing another name cancels")
h.ctl.set_name("Desk 2"); h.ctl.save(); h.ctl.save()
eq(h.said[1], "text wl_name Desk 2", "overwrite by name"); eq(h.said[2], "emit wl_save", "same event: Widgets updates")
-- failure keeps the typed name and says why
h.fire()
h.ctl.snapshot(snap_text({ layouts = w, seq = 2, ok = false, msg = "Could not write the layouts file" }))
check(not h.view().status_ok, "error status"); eq(h.view().status, "Could not write the layouts file", "error text")
eq(h.cleared, 2, "the name stays after a failure")
-- the arm expires
h.ctl.set_name("Desk 1"); h.ctl.save(); eq(h.view().arm, 3, "armed again"); h.fire(); eq(h.view().arm, 0, "confirmation times out")
-- Escape cancels a confirmation first, then closes
h.ctl.save(); eq(h.view().arm, 3, "armed"); check(h.ctl.escape(), "Esc consumed by the confirmation"); eq(h.view().arm, 0, "disarmed"); check(not h.ctl.escape(), "next Esc closes the bar")

-- ── update / delete confirm; rename / duplicate select ──
h = make()
h.ctl.opened(); h.ctl.snapshot(snap_text({ layouts = layouts(4) })); h.fire()
h.ctl.pick(2); h.said = {}
h.ctl.update(); eq(#h.said, 0, "update arms"); eq(h.view().arm, 1, "arm 1"); h.ctl.pick(3); eq(h.view().arm, 0, "moving the selection cancels")
h.ctl.update(); h.ctl.update(); eq(h.said[1], "emit wl_update 3", "second press updates the selected")
h.ctl.snapshot(snap_text({ layouts = layouts(4), seq = 1, msg = "Updated “Desk 3”" })); h.said = {}
h.ctl.delete(); eq(#h.said, 0, "delete arms"); check(h.view().hint:find("Delete again"), "says what it will do")
h.ctl.delete(); eq(h.said[1], "emit wl_delete 3", "second press deletes")
local after_del = layouts(4); table.remove(after_del, 3)
h.ctl.snapshot(snap_text({ layouts = after_del, seq = 2, msg = "Deleted “Desk 3”" }))
eq(h.view().sel_id, 4, "the neighbour is selected after a delete"); eq(h.view().total, 3, "list shrank")
h.said = {}
h.ctl.rename(); eq(h.view().status, "Type the new name first", "rename needs a name"); eq(#h.said, 0, "nothing sent")
h.ctl.set_name("Desk 1"); check(not h.view().can_rename, "a taken name cannot be a rename target"); h.ctl.rename(); eq(#h.said, 0, "refused locally")
h.ctl.set_name("Evening"); h.ctl.rename()
eq(h.said[1], "text wl_name Evening", "rename sends the name"); eq(h.said[2], "emit wl_rename 4", "for the selected id")
local ren = layouts(4); table.remove(ren, 3); ren[3].name = "Evening"
h.ctl.snapshot(snap_text({ layouts = ren, seq = 3, msg = "Renamed to “Evening”" }))
eq(h.view().sel_id, 4, "still selected"); eq(h.view().rows[3].name, "Evening", "shown")
h.said = {}
h.ctl.duplicate(); eq(h.said[1], "emit wl_duplicate 4", "duplicate by id")
local dup = {}; for i, l in ipairs(ren) do dup[i] = l end; dup[4] = { id = 9, name = "Evening copy", cards = 1, outputs = 1 }
h.ctl.snapshot(snap_text({ layouts = dup, seq = 4, msg = "Created “Evening copy”" }))
eq(h.view().sel_id, 9, "the copy is selected")

-- ── limits and read-only ──
h = make()
h.ctl.opened(); h.ctl.snapshot(snap_text({ layouts = layouts(24) })); h.fire()
h.ctl.set_name("Brand new"); check(not h.view().can_save, "full: a new name cannot be saved"); check(h.view().hint:find("24 desktops"), "says the limit")
h.ctl.set_name("Desk 3"); check(h.view().can_save, "full: an existing name can still be overwritten")
h.ctl.pick(1); check(not h.view().can_duplicate, "full: no duplicate")
h = make()
h.ctl.opened(); h.ctl.snapshot(snap_text({ layouts = layouts(2), writable = false, state = "newer" })); h.fire()
h.ctl.pick(1); h.ctl.set_name("x")
v = h.view()
check(v.can_load, "read-only still loads"); check(not v.can_save and not v.can_update and not v.can_delete and not v.can_rename and not v.can_duplicate, "read-only blocks every write")
check(v.hint:find("newer Beskar"), "explains why"); h.said = {}
h.ctl.delete(); h.ctl.save(); eq(#h.said, 0, "writes are not even sent"); check(h.view().status:find("newer"), "and the reason is shown")
h.ctl.load(); eq(h.said[1], "emit wl_load 1", "load works")
h = make()
h.ctl.opened(); h.ctl.snapshot(snap_text({ layouts = {}, ready = true })); h.fire()
eq(h.view().range, "No saved desktops yet", "empty list message")

-- ── unreachable Widgets ──
h = make()
h.ctl.opened(); h.ctl.snapshot(snap_text({ layouts = layouts(2) })); h.fire(); h.ctl.pick(1)
h.say_ok = false; h.ctl.load()
eq(h.view().status, "Could not reach the widgets", "say failure is shown"); check(not h.view().status_ok, "as an error"); check(h.view().can_load, "and does not leave the buttons stuck")
h.say_ok = true
h.ctl.set_name("n"); h.say_ok = false; h.ctl.save()
check(h.view().status:find("Could not reach"), "same for save")

-- ── tabs, open/close ──
h = make()
eq(h.view().page, 0, "starts on the widgets page")
h.ctl.tab(1); eq(h.view().page, 1, "tab"); eq(h.pages[#h.pages], 1, "page change is reported (the bar resizes)")
eq(h.last_said(), "emit wl_list", "a not-ready page asks Widgets to list")
h.ctl.snapshot(snap_text({ layouts = layouts(2), seq = 1, msg = "Layouts refreshed" }))
h.ctl.set_name("keep"); h.ctl.closed(); eq(h.view().page, 0, "closing returns to widgets"); eq(h.view().status, "", "clears status")
h.ctl.opened(); eq(h.view().page, 0, "reopens on widgets")
-- a snapshot that arrives long after opening is a real status
h.fire(); h.ctl.snapshot(snap_text({ layouts = layouts(2), seq = 2, msg = "Saved “x”" })); eq(h.view().status, "Saved “x”", "late status shows")
-- garbage snapshots never break the page
h.ctl.snapshot("{{{"); eq(h.view().status, "Could not read the saved desktops", "garbage is reported")
eq(h.view().total, 2, "and the last good list stays")

-- ── Part 2: the scene and the module wire the contract ──
local function slurp(p) local f = assert(io.open(p)); local s = f:read("a"); f:close(); return s end
local plm, luau = slurp("shell/common/dock_panels.plm"), slurp("shell/dock_panels.luau")
for _, name in ipairs({ "wb_tab", "wb_pick", "wb_save", "wb_load", "wb_rename", "wb_dup", "wb_update", "wb_delete", "wb_move", "wb_scroll", "wb_submit", "wb_escape" }) do
    check(plm:find("event " .. name .. " ->", 1, true), name .. " is declared with -> in the scene")
    check(luau:find('on("' .. name .. '"', 1, true), name .. " is handled by the logic")
end
check(plm:find('text wb_layouts = "{}"', 1, true), "wb_layouts is declared")
check(luau:find('on("text:wb_layouts"', 1, true), "wb_layouts is consumed with on text")
check(plm:find("model wb_rows max 5", 1, true), "the row model is bounded to the five visible rows")
check(plm:find("on submit wb_name", 1, true) and not plm:find("on key Return while Panels.cur == 10", 1, true), "Enter is the input's submit, not a second handler")
for _, k in ipairs({ "Down", "Up", "Tab", "Shift+Tab", "Next", "Prior", "Ctrl+Return", "F2", "F3", "F4", "F8" }) do
    check(plm:find("on key " .. k .. " while Panels.cur == 10 and wb_page == 1", 1, true), k .. " is a guarded key rule")
end
check(plm:find("on key Escape while Panels.cur == 10 and Panels.open_screen == screen.index { emit wb_escape }", 1, true), "Esc goes through the confirmation first")
check(luau:find('require("widget_bar_layouts")', 1, true), "the pure controller is used")
check(not luau:find("widget-layouts.json", 1, true), "the bar never touches the layouts file")
for _, p in ipairs({ "wb_preset", "wb_undo", "wb_tidy", "wb_grid", "wb_done" }) do check(plm:find("event " .. p .. " ->", 1, true), "existing " .. p .. " kept") end
check(plm:find('"Presets"', 1, true) and plm:find("for pr in presets", 1, true), "factory presets kept")

print("widget-bar-layouts: " .. passed .. " checks passed")
