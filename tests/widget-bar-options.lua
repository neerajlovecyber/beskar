-- The widget bar's Card page (C4b UI): lua tests/widget-bar-options.lua
-- Part 1 runs shell/widget_bar_options.luau with a fake host (snapshot bounds, selection, auto-enter, what is asked of
-- Widgets). Part 2 checks that dockpanels.plm / dockpanels.luau wire the contract. No session, Widgets or config is touched.
package.path = "shell/?.luau;" .. package.path
local B = dofile("shell/widget_bar_options.luau")
local passed = 0
local function check(v, why) if not v then error("FAILED: " .. why, 2) end passed = passed + 1 end
local function eq(a, b, why) if a ~= b then error("FAILED: " .. why .. " (got " .. tostring(a) .. ", wanted " .. tostring(b) .. ")", 2) end passed = passed + 1 end

-- a fake json: texts are keys into a registry of tables (the parser only calls decode; the controller only encodes to compare)
local registry, counter = {}, 0
local function enc(v)
    if type(v) ~= "table" then return tostring(v) end
    local keys = {}
    for k in pairs(v) do keys[#keys + 1] = tostring(k) end
    table.sort(keys)
    local out = {}
    for _, k in ipairs(keys) do out[#out + 1] = k .. "=" .. enc(v[k] ~= nil and v[k] or v[tonumber(k)]) end
    return "{" .. table.concat(out, ",") .. "}"
end
local json = { encode = enc, decode = function(s) if registry[s] == nil then error("bad json") end return registry[s] end }
local function wire(t) counter = counter + 1; local k = "T" .. counter; registry[k] = t; return k end

local function clock(extra)
    local s = { v = 1, rev = 1, editing = true, sel = 3, kind = 1, name = "Clock", sz = 1, nsz = 3, out = "HDMI-A-1", lock = false,
        options = {
            { id = 1, key = "lock", label = "Lock position", value = 1, n = 2, labels = { "Unlocked", "Locked" } },
            { id = 2, key = "date", label = "Date line", value = 1, n = 3, labels = { "Automatic", "Show", "Hide" } },
            { id = 3, key = "seconds", label = "Seconds", value = 1, n = 3, labels = { "Automatic", "Show", "Hide" } },
            { id = 4, key = "format", label = "Time format", value = 1, n = 3, labels = { "Automatic", "12-hour", "24-hour" } },
        } }
    for k, v in pairs(extra or {}) do s[k] = v end
    return s
end

-- ── parse bounds ──
local function parses(t) return B.parse(wire(t), json) end
local s = parses(clock())
check(s and #s.options == 4 and s.name == "Clock" and s.sz == 1 and s.out == "HDMI-A-1", "a full snapshot parses")
check(parses({ v = 1, rev = 4, editing = true, sel = 0, options = {} }), "no selection is fine")
check(parses({ v = 1, rev = 4, editing = false, sel = 0 }), "options may be absent with no selection")
check(not B.parse("", json) and not B.parse(nil, json) and not B.parse(string.rep("x", B.MAX_WIRE + 1), json), "empty, missing and oversize text are refused")
check(not B.parse("nope", json), "undecodable text is refused")
for name, bad in pairs({
    version = clock({ v = 2 }), rev = clock({ rev = -1 }), rev_frac = clock({ rev = 1.5 }), editing = clock({ editing = "yes" }),
    sel = clock({ sel = -3 }), kind = clock({ kind = 5000 }), sz = clock({ sz = 3 }), nsz = clock({ nsz = 0 }), name = clock({ name = 5 }),
    out = clock({ out = {} }), lock = clock({ lock = 1 }), options = clock({ options = "x" }), st = clock({ st = { seq = -1, ok = true } }),
    st_ok = clock({ st = { seq = 1, ok = "no" } }), nolabelcount = clock({ options = { { id = 1, key = "lock", label = "L", value = 1, n = 2, labels = { "a" } } } }),
    value_hi = clock({ options = { { id = 1, key = "lock", label = "L", value = 3, n = 2, labels = { "a", "b" } } } }),
    n_hi = clock({ options = { { id = 1, key = "lock", label = "L", value = 1, n = 4, labels = { "a", "b", "c", "d" } } } }),
    n_lo = clock({ options = { { id = 1, key = "lock", label = "L", value = 1, n = 1, labels = { "a" } } } }),
    dup = clock({ options = { { id = 1, key = "lock", label = "L", value = 1, n = 2, labels = { "a", "b" } }, { id = 1, key = "date", label = "D", value = 1, n = 2, labels = { "a", "b" } } } }),
    key = clock({ options = { { id = 1, key = "bad key!", label = "L", value = 1, n = 2, labels = { "a", "b" } } } }),
    id = clock({ options = { { id = 0, key = "lock", label = "L", value = 1, n = 2, labels = { "a", "b" } } } }),
    blank_label = clock({ options = { { id = 1, key = "lock", label = "  ", value = 1, n = 2, labels = { "a", "b" } } } }),
    five = clock({ options = (function() local t = {} for i = 1, 5 do t[i] = { id = i, key = "k" .. i, label = "L", value = 1, n = 2, labels = { "a", "b" } } end return t end)() }),
    orphan = { v = 1, rev = 1, editing = true, sel = 0, options = { { id = 1 } } },
}) do check(not parses(bad), "refused: " .. name) end
local long = parses(clock({ name = string.rep("é", 100) .. "\n" }))
check(long and utf8.len(long.name) == B.MAX_TEXT, "a long name is cut by characters and stripped of control characters")
local noisy = parses(clock({ options = { { id = 1, key = "lock", label = "Lock\tposition", value = 1, n = 2, labels = { "Unlocked", "Locked" } } } }))
eq(noisy.options[1].label, "Lock position", "control characters in a label become spaces")

-- ── controller ──
local function host()
    local h = { said = {}, views = {}, pages = {}, ok = true }
    h.json = json
    function h.say(w) h.said[#h.said + 1] = w; return h.ok end
    function h.publish(v) h.views[#h.views + 1] = v end
    function h.page_changed(a) h.pages[#h.pages + 1] = a end
    function h.view() return h.views[#h.views] end
    h.ctl = B.controller(h)
    return h
end
local h = host()
h.ctl.opened()
eq(h.view().empty, "Waiting for the widgets…", "before any snapshot the page waits")
h.ctl.snapshot(wire({ v = 1, rev = 1, editing = true, sel = 0, options = {} }))
eq(h.view().empty, "Select a widget", "nothing selected: the empty state says what to do")
check(not h.view().has_card and #h.view().rows == 0 and not h.view().can_reset, "no rows, no reset")
check(not h.ctl.active(), "an empty snapshot does not open the page")
-- a new positive selection opens the Card page
h.ctl.snapshot(wire(clock()))
check(h.ctl.active() and h.pages[#h.pages] == true, "a new selection opens the Card page")
local v = h.view()
check(v.has_card and v.count == 4 and v.title == "Clock" and v.sub == "Medium  ·  HDMI-A-1", "title and subtitle describe the card")
check(v.rows[1].sel and v.row == 1 and v.sel_id == 1 and v.rows[2].l3 == "Hide", "the first row is selected and rows carry their labels")
-- the user returns to another tab: the page stays away until the selection CHANGES
h.ctl.leave(); check(not h.ctl.active(), "the user can leave")
h.ctl.snapshot(wire(clock({ rev = 2 })))
check(not h.ctl.active(), "a snapshot for the same card does not pull the user back")
h.ctl.snapshot(wire(clock({ rev = 3, sel = 7, name = "Weather", options = {} })))
check(h.ctl.active(), "selecting a different card opens the page again")
h.ctl.snapshot(wire({ v = 1, rev = 4, editing = true, sel = 0, options = {} }))
h.ctl.leave()
h.ctl.snapshot(wire(clock({ rev = 5 })))
check(h.ctl.active(), "re-selecting after a deselect opens it")
-- keys
h.said = {}
h.ctl.move(1); eq(h.view().sel_id, 2, "Down selects the next option")
h.ctl.move(99); eq(h.view().sel_id, 4, "selection stops at the last row")
h.ctl.move(-99); eq(h.view().sel_id, 1, "and at the first")
h.ctl.move(1)
check(h.ctl.change(1) and h.said[#h.said] == "emit w_opt 22", "Right asks Widgets for the next value of the selected option")
check(h.ctl.change(-1) and #h.said == 1, "Left on the first value changes nothing and sends nothing")
check(h.ctl.cycle() and h.said[#h.said] == "emit w_opt 22", "Return cycles")
h.ctl.snapshot(wire(clock({ rev = 6, options = { { id = 1, key = "lock", label = "Lock position", value = 1, n = 2, labels = { "Unlocked", "Locked" } },
    { id = 2, key = "date", label = "Date line", value = 3, n = 3, labels = { "Automatic", "Show", "Hide" } },
    { id = 3, key = "seconds", label = "Seconds", value = 1, n = 3, labels = { "Automatic", "Show", "Hide" } },
    { id = 4, key = "format", label = "Time format", value = 1, n = 3, labels = { "Automatic", "12-hour", "24-hour" } } } })))
eq(h.view().sel_id, 2, "the selected row survives a snapshot of the same card")
check(h.view().can_reset, "a non-default value enables Reset")
h.ctl.cycle(); eq(h.said[#h.said], "emit w_opt 21", "the last value wraps to the default")
local before = #h.said
h.ctl.change(1)
eq(#h.said, before, "Right on the last value sends nothing")
eq(h.said[#h.said], "emit w_opt 21", "clamping preserves the last requested cycle")
-- direct choice (a chip press)
h.said = {}
check(h.ctl.choose(41) and #h.said == 0, "an unchanged chip resolves without forwarding")
h.said = {}
h.ctl.choose(42); eq(h.said[1], "emit w_opt 42", "a chip press asks for exactly its code")
eq(h.view().sel_id, 4, "and selects that row")
h.said = {}
for _, bad in ipairs({ 0, 9, 10, 15, 25, 99, 51, -21, 2.5, "x", 24 + 10 }) do h.ctl.choose(bad) end
eq(#h.said, 0, "unknown options, impossible values and junk are never forwarded")
h.ctl.choose(41); eq(#h.said, 0, "choosing the value it already has sends nothing")
h.ctl.reset(); eq(h.said[1], "emit w_opt_reset", "Reset is forwarded")
-- no card / not editing
h.ctl.snapshot(wire({ v = 1, rev = 7, editing = false, sel = 5, kind = 1, name = "Clock", sz = 0, nsz = 3, options = {} }))
check(not h.view().has_card, "a selection while not editing is not a card")
h.said = {}
check(not h.ctl.cycle() and not h.ctl.change(1) and not h.ctl.reset() and #h.said == 0, "nothing is sent without a selected card")
-- a bad snapshot
h.ctl.snapshot("not registered")
eq(h.view().empty, "Options unavailable", "an unreadable snapshot is reported")
check(h.view().status == "Could not read the card options" and not h.view().status_ok, "with a status")
local sent_before = #h.said
check(not h.ctl.cycle() and not h.ctl.reset() and #h.said == sent_before, "bad snapshots cannot mutate the previously selected card")
h.ctl.snapshot(wire(clock({ rev = 8 })))
check(h.view().has_card, "and the next good one recovers")
-- say failure
h.ok = false
h.ctl.cycle()
eq(h.view().status, "Could not reach the widgets", "an unreachable Widgets is reported, not hidden")
h.ok = true
-- Widgets' own status: the first one after opening is old news
h = host(); h.ctl.opened()
h.ctl.snapshot(wire(clock({ st = { seq = 4, ok = false, msg = "Old news" } })))
eq(h.view().status, "", "the status carried at open is not shown")
h.ctl.snapshot(wire(clock({ rev = 2, st = { seq = 5, ok = false, msg = "Select a widget first" } })))
check(h.view().status == "Select a widget first" and not h.view().status_ok, "a new status is shown")
h.ctl.snapshot(wire(clock({ rev = 3, sel = 9, st = { seq = 5, ok = false, msg = "Select a widget first" } })))
eq(h.view().status, "", "a different card clears the status")
-- closing and reopening start fresh
h.ctl.closed(); check(not h.ctl.active(), "closing leaves the Card page")
h.ctl.opened(); eq(h.view().empty, "Waiting for the widgets…", "reopening forgets the last card until Widgets answers")
h.ctl.snapshot(wire(clock()))
check(h.ctl.active(), "and the first selection after reopening opens the page")
-- a card selected before the bar opened never opens the page by itself (not open)
h = host()
h.ctl.snapshot(wire(clock()))
check(not h.ctl.active(), "a snapshot while the bar is closed does not open the page")

-- Stack choices stay bounded and are requests to Widgets, never a second owner.
h = host();h.ctl.opened()
local available = {id=0,n=1,i=1,m={},pick={{8,3},{9,4}}}
h.ctl.snapshot(wire(clock({stack=available})))
check(h.view().stack_can_join and h.view().stack_target == 8, "first compatible target is offered")
check(h.ctl.stack_target(1) and h.view().stack_target == 9, "keyboard/pointer can cycle targets")
h.ctl.stack_join();eq(h.said[#h.said], "emit w_stack 9", "Stack forwards only an offered target")
h.ctl.snapshot(wire(clock({rev=2,stack={id=0,n=1,i=1,m={},pick={{8,3}}}})))
eq(h.view().stack_target,8,"a disappearing target selects the first remaining choice")
check(not h.ctl.stack_page(1) and not h.ctl.stack_unstack(), "single cards cannot page or unstack")
h.ctl.snapshot(wire(clock({rev=3,sel=5,stack={id=2,n=2,i=1,m={{5,1},{8,3}},pick={}}})))
check(h.view().stacked and h.view().stack_can_unstack and h.view().stack_position=="Page 1 of 2", "stack position is reported")
h.ctl.stack_page(1);eq(h.said[#h.said],"emit w_page_next 5","page uses the snapshot card ID")
h.ctl.stack_page(-1);eq(h.said[#h.said],"emit w_page_prev 5","previous page forwards")
h.ctl.stack_unstack();eq(h.said[#h.said],"emit w_unstack 5","Unstack is an owner request")
h.ctl.snapshot(wire(clock({rev=4,sel=5,lock=true,stack={id=2,n=2,i=1,m={{5,1},{8,3}},pick={{9,4}}}})))
check(not h.ctl.stack_join() and not h.ctl.stack_unstack(),"locked stacks cannot be joined or split from the bar")
check(h.ctl.stack_page(1),"a locked stack may still be paged")
for _, stack in ipairs({
    {id=0,n=2,i=1,m={},pick={}}, {id=2,n=2,i=1,m={{8,3},{5,1}},pick={}},
    {id=2,n=2,i=1,m={{5,1},{5,1}},pick={}}, {id=0,n=1,i=1,m={},pick={{5,1}}},
    {id=0,n=1,i=1,m={},pick={{8,3},{8,3}}}, {id=2,n=9,i=1,m={},pick={}},
}) do
    check(B.parse(wire(clock({sel=5,stack=stack})),json)==nil,"invalid stack snapshots are rejected")
end
h.ctl.snapshot("bad");sent_before=#h.said
check(not h.ctl.stack_join() and not h.ctl.stack_page(1) and not h.ctl.stack_unstack() and #h.said==sent_before,
    "invalidated snapshots never send stale stack commands")

-- ── Part 2: the scene and the module wire the contract ──
local function slurp(p) local f = assert(io.open(p)); local x = f:read("a"); f:close(); return x end
local plm, luau = slurp("shell/common/dock_panels.plm"), slurp("shell/dock_panels.luau")
for _, name in ipairs({ "wb_opt", "wb_opt_pick", "wb_opt_move", "wb_opt_change", "wb_opt_cycle", "wb_opt_reset" }) do
    check(plm:find("event " .. name .. " ->", 1, true), name .. " is declared with ->")
    check(luau:find('on("' .. name .. '"', 1, true), name .. " is handled")
end
check(plm:find('text wb_card_options = "{}"', 1, true) and luau:find('on("text:wb_card_options"', 1, true), "the snapshot text is declared and consumed")
check(plm:find("model wb_opts max 4", 1, true), "the option model is bounded to four rows")
for _, k in ipairs({ "Down", "Up", "Left", "Right", "Tab", "Shift+Tab" }) do
    check(plm:find("on k_" .. k:lower():gsub("%W+", "_") .. " while Panels.cur == 10 and wb_page == 2", 1, true), k .. " is a guarded Card key")
end
check(plm:find("on k_return while wb_page == 2 and Panels.cur == 10", 1, true) and plm:find("on k_kp_enter while wb_page == 2 and Panels.cur == 10", 1, true), "Return and keypad Enter cycle on the Card page")
check(plm:find('Chip("Card", wb_page == 2, wb_tab, 2', 1, true), "a Card tab exists")
check(plm:find("wb_page == 2 { fld_req = 0; fld_seq = fld_seq + 1 }", 1, true), "the name field is blurred on the Card page")
check(plm:find("RowFrame(752", 1, true) and plm:find("EmptyState(400, 140", 1, true), "shared RowFrame and EmptyState are used")
check(luau:find("PAGE_H = { [0] = 176, [1] = 272, [2] = 336 }", 1, true), "the Card page fits options and stack controls")
check(luau:find('require("widget_bar_options")', 1, true), "the pure controller is used")
check(luau:find("emit w_opt", 1, true) == nil, "dockpanels.luau never composes option events itself")
print("widget-bar-options: " .. passed .. " checks passed")
