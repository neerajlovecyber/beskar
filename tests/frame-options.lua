-- Run only this suite for the frame / dock options: lua tests/frame-options.lua
package.path = "shell/?.luau;" .. package.path
local F = require("frame_options")
local passed = 0
local function check(v, why) assert(v, why); passed = passed + 1 end
local function same(a, b)
    if #a ~= #b then return false end
    for i = 1, #a do if a[i] ~= b[i] then return false end end
    return true
end

-- Settings enums: bounded, defaults are the old behaviour
check(F.dock_icon(1) == 38 and F.peek_ms(1) == 2500, "Index 1 keeps the present icon size and delay")
check(F.dock_icon(0) == 32 and F.dock_icon(2) == 46, "Small / large icon sizes")
check(F.peek_ms(0) == 1200 and F.peek_ms(2) == 4500, "Quick / relaxed delays")
check(F.dock_icon(7) == 38 and F.dock_icon(-1) == 38 and F.dock_icon(1.5) == 38 and F.dock_icon("x") == 38 and F.dock_icon(nil) == 38,
    "Out-of-range sizes fall back to standard")
check(F.peek_ms(99) == 2500 and F.peek_ms(nil) == 2500, "Out-of-range delays fall back to standard")
check(F.flag(nil, true) == true and F.flag(false, true) == false and F.flag(1, false) == true and F.flag("no", true) == false,
    "Booleans default only when missing")

-- the move payload: named or positional, number or string id
local id, dir = F.parse_move({ id = 2, direction = -1 })
check(id == 2 and dir == -1, "Named payload")
id, dir = F.parse_move({ 0, 3 })
check(id == 0 and dir == 1, "Positional payload, any positive step is one step")
id, dir = F.parse_move({ id = "kitty", direction = "Left" })
check(id == "kitty" and dir == -1, "Pin string and word direction")
check(select(2, F.parse_move({ id = "kitty", direction = "right" })) == 1, "Right word")
check(F.parse_move({ id = 1, direction = 0 }) == nil, "Zero direction rejected")
check(F.parse_move({ id = 1, direction = "sideways" }) == nil, "Unknown direction word rejected")
check(F.parse_move({ id = -1, direction = 1 }) == nil and F.parse_move({ id = 1.5, direction = 1 }) == nil, "Bad item index rejected")
check(F.parse_move({ id = 12, direction = 1 }) == nil, "Index past the dock rejected")
check(F.parse_move({ id = "", direction = 1 }) == nil and F.parse_move({ id = "a\nb", direction = 1 }) == nil, "Empty / multi-line id rejected")
check(F.parse_move({ id = string.rep("x", 600), direction = 1 }) == nil, "Overlong id rejected")
check(F.parse_move(5) == nil and F.parse_move(nil) == nil and F.parse_move({ id = {}, direction = 1 }) == nil, "Non-table / non-scalar ids rejected")

-- a dock: pins A B (missing from the dock: file only) C, then two running apps
local pins = { "a", "b", "gone", "c", "app:x|x --run" }
local items = {
    { pinned = true, pin_pos = 1, pinstr = "a" },
    { pinned = true, pin_pos = 2, pinstr = "b" },
    { pinned = true, pin_pos = 4, pinstr = "c" },
    { pinned = true, pin_pos = 5, pinstr = "app:x|x --run" },
    { pinned = false },
    { pinned = false },
}
local fl = F.move_flags(items)
check(not fl[1].left and fl[1].right, "First pin cannot go left")
check(fl[2].left and fl[2].right, "Middle pin both ways")
check(fl[4].left and not fl[4].right, "Last pin cannot go right, running apps do not count")
check(not fl[5].left and not fl[5].right and not fl[6].left, "Running-only items never move")
check(not F.move_flags({ { pinned = true, pin_pos = 1, pinstr = "a" } })[1].left, "A single pin has nowhere to go")

local out = F.plan_move(items, pins, 1, 1)                       -- B right → swaps with the next VISIBLE pin (c)
check(same(out, { "a", "c", "gone", "b", "app:x|x --run" }), "Swap with the next visible pin; the hidden one keeps its place")
check(same(pins, { "a", "b", "gone", "c", "app:x|x --run" }), "The input list is never changed")
out = F.plan_move(items, pins, "c", -1)                          -- by pin string
check(same(out, { "a", "c", "gone", "b", "app:x|x --run" }), "A pin string names the same item")
out = F.plan_move(items, pins, "APP:X|X --RUN", -1)
check(same(out, { "a", "b", "gone", "app:x|x --run", "c" }), "String match falls back to case-insensitive; command pin keeps its text")
check(select(2, F.plan_move(items, pins, 0, -1)) == "at the edge", "No move past the first pin")
check(select(2, F.plan_move(items, pins, 3, 1)) == "at the edge", "No move past the last pin")
check(select(2, F.plan_move(items, pins, 4, -1)) == "not a pinned item", "A running-only item cannot be reordered")
check(select(2, F.plan_move(items, pins, 9, -1)) == "not a pinned item", "Unknown index")
check(select(2, F.plan_move(items, pins, "nothing", 1)) == "not a pinned item", "A string that is not a pin adds nothing")
check(select(2, F.plan_move(items, { "a", "z", "gone", "c", "app:x|x --run" }, 0, 1)) == "stale", "Stale item list is refused")
local one = F.plan_move({ items[1], items[2] }, { "a", "b" }, 0, 1)
check(same(one, { "b", "a" }), "Two pins swap")

-- the snapshot for Settings: visible pinned items only, dock order, no commands
local snap = F.snapshot(items)
check(#snap == 4 and snap[1].index == 0 and snap[3].index == 2 and snap[4].index == 3, "Snapshot holds the pinned items with their dock indexes")
check(snap[4].pin == "app:x" and not snap[4].pin:find("run", 1, true), "A command pin is sent without its command line")
check(snap[1].pin == "a" and not snap[1].mvl and snap[1].mvr and snap[2].mvl and snap[2].mvr and snap[4].mvl and not snap[4].mvr, "Move flags travel with the rows")
check(#F.snapshot({ { pinned = false, name = "running" } }) == 0, "Running-only items are not listed")
local many = {}
for i = 1, 20 do many[i] = { pinned = true, pin_pos = i, pinstr = "p" .. i, name = "n" } end
check(#F.snapshot(many) == 12, "At most twelve rows")
check(F.clean_name("  Fire\nfox\t\0 ") == "Fire fox", "Names lose control characters and padding")
check(utf8.len(F.clean_name(string.rep("é", 200))) == F.MAX_NAME, "Names are bounded to 64 characters including the ellipsis")
check(F.clean_name("bad\255byte") ~= nil and F.clean_name(nil) == "", "Invalid UTF-8 and nil are safe")
check(F.pin_label("app:T3Code|/opt/x --flag") == "app:T3Code" and F.pin_label("kitty") == "kitty", "Labels never carry a command")
check(#F.pin_label(string.rep("x", 400)) == 128, "Labels are bounded")
out = F.plan_move(items, pins, "app:x", -1)
check(same(out, { "a", "b", "gone", "app:x|x --run", "c" }), "The command-free label names the same pin")

check(F.output_visible(0, "missing", "A", {"A","B"}, "B"), "All includes every output")
check(F.output_visible(1, "A", "B", {"A","B"}, "B"), "Focused follows the connected focus")
check(not F.output_visible(1, "A", "A", {"A","B"}, "B"), "Focused excludes other outputs")
check(F.output_visible(2, "A", "A", {"A","B"}, "B"), "Named uses the saved name")
check(F.output_visible(2, "gone", "B", {"A","B"}, "B"), "Missing named output falls back to focus")
check(F.output_visible(2, "gone", "A", {"A","B"}, "gone"), "Missing focus falls back to first connected output")
check(not F.output_visible(2, "gone", "B", {"A","B"}, "gone"), "Fallback is a single output")
check(F.show_ms(0)==0 and F.show_ms(1)==150 and F.show_ms(2)==350 and F.show_ms(99)==0, "Reveal delays are bounded with immediate default")

local timers, reveals, delay = {}, 0, 0
local edge = F.edge_controller({ delay=function() return delay end, after=function(ms, cb) timers[#timers+1]={ms=ms,cb=cb} end, reveal=function() reveals=reveals+1 end })
edge.enter();check(reveals==1 and #timers==0, "Immediate reveal schedules no timer")
delay=2;edge.enter();check(timers[1].ms==350 and reveals==1, "Delayed reveal waits before opening")
edge.leave();timers[1].cb();check(reveals==1, "Leaving the edge cancels the pending reveal")
delay=1;edge.enter();edge.enter();timers[2].cb();check(reveals==1, "A newer enter invalidates the previous timer")
timers[3].cb();check(reveals==2, "The current timer emits exactly one reveal")

print(string.format("frame-options: %d checks passed", passed))
