-- Desktop widgets: logic. The cards live in CARDS (this file is the only writer of ~/.config/beskar/widgets.json);
-- `model.ws` is what the scene draws. Feeds (weather, system, calendar) run only while a card needs them.
--
--   card = { id, out = "HDMI-A-1", kind, sz (0 small · 1 medium · 2 large), x, y, opts? }
--   kinds: 1 clock · 2 date · 3 weather · 4 battery · 5 system · 6 media · 7 month calendar
--   opts (C4b, only what differs from the default; schema in widgets_data.luau, logic in widget_options.luau):
--     lock = true (position lock) · clock: date = "on"|"off", seconds = "on"|"off", format = "12"|"24"
--   stack (C4c, only while stacked): { id, i, on } — cards of one stack share a footprint (out, x, y, sz); only the member
--     with `on` is in the model (so only it is drawn, clickable and fed). Logic: shell/widget_stacks.luau.

-- Portable setup (C5): `emit setup_request <id>` + staged request / response files, answered by shell/widget_setup.luau
-- (snapshot + compare-and-swap apply of the whole placement; the protocol is documented there). Every widgets.json write is
-- serialised through `write_widgets`; while an apply is in flight the user's edits wait (`guarded`) and replay after it.
local clockfmt = require("clockfmt")

local UNIT, GAP = 160, 16
local GRID = 16
local TOP_SAFE, SIDE_SAFE = 40, 12     -- the frame's ring and top bar

local DATA = require("widgets_data")
local KINDS, PRESETS = DATA.KINDS, DATA.PRESETS
local Opts = require("widget_options")
local Stacks = require("widget_stacks")
require("style_options").follow_motion({ fact = fact, on = on })
local function kind_of(id)
    return KINDS[id]
end

local function say(scene, cmd)
    pcall(sys.call, "say", scene, cmd)
end
local function sh(script, cb, ...)
    run("sh", { "-c", script, "x", ... }, cb, cb == nil and { output = false } or nil)
end

-- ── which copy of the scene is on which monitor (pleamar logs it at start; see topbar.luau) ──
local OUTPUTS = {}          -- index (1-based) → name
local SIZES = {}            -- name → { w, h } logical
local CARDS = {}
local NEXT_ID = 1
local HISTORY = {}
local push_bar
local loaded = false
local timer_feed = require("timer_client")()

local function width_of(sz) return sz == 0 and UNIT or (UNIT * 2 + GAP) end
local function height_of(sz) return sz == 2 and (UNIT * 2 + GAP) or UNIT end

local function index_of(out)
    for i, n in ipairs(OUTPUTS) do
        if n == out then return i - 1 end
    end
    return -1
end

local function copy_card(c)
    return { id = c.id, out = c.out, kind = c.kind, sz = c.sz, x = c.x, y = c.y, opts = Opts.copy(c.opts),
        stack = Stacks.copy(c.stack) }
end

-- The cards a monitor shows (the model holds at most 16). A stack shows ONE card: its active member. The hidden members
-- are not in the model, so they draw nothing, catch no click and start no feed or tick (see start_feeds / wants_seconds).
local function visible()
    local list = {}
    for _, c in ipairs(CARDS) do
        local scr = index_of(c.out)
        if scr >= 0 and #list < 16 and not Stacks.hidden(c) then list[#list + 1] = { c = c, scr = scr } end
    end
    return list
end

-- ── clock cards: each shows its OWN time (format / seconds / date line options, default = inherit) ──
-- `fact.hour12` is the shell's 12/24 h choice; `fact.clock_seconds` is the default for seconds on widget clocks
-- (false until the shell says otherwise: `say widgets "fact clock_seconds true"`). At most four time strings are
-- formatted per refresh, however many clock cards exist.
local DATE_LONG = ""
local function clock_globals()
    return { hour12 = fact.hour12, seconds = fact.clock_seconds == true }
end
local function clock_fields(c, memo)
    local e = Opts.clock(c, clock_globals())
    local key = (e.hour12 and "1" or "0") .. (e.seconds and "1" or "0")
    local t = memo[key]
    if not t then
        local time, ampm = Opts.split_time(clockfmt(e.hour12, e.seconds))
        t = { time = time, ampm = ampm }
        memo[key] = t
    end
    return { tm = t.time, ap = t.ampm, dl = e.date and DATE_LONG or "", dd = e.date and 1 or 0, sec = e.seconds and 1 or 0 }
end
local function clock_part(f) return f.tm .. "|" .. f.ap .. "|" .. f.dl .. "|" .. f.dd .. "|" .. f.sec end

local clock_sig = ""        -- what the model's clock fields say now: a refresh pushes only when this changes
local function push()
    local recs, memo, parts = {}, {}, {}
    local pages = Stacks.index_map(CARDS)
    for _, row in ipairs(visible()) do
        local c = row.c
        local page = pages[c.id]
        local r = { id = c.id, scr = row.scr, kind = c.kind, sz = c.sz, x = c.x, y = c.y,
            locked = Opts.locked(c) and 1 or 0, sn = page and page.n or 0, si = page and page.i or 0,
            tm = "", ap = "", dl = "", dd = 0, sec = 0 }
        if c.kind == 1 then
            local f = clock_fields(c, memo)
            r.tm, r.ap, r.dl, r.dd, r.sec = f.tm, f.ap, f.dl, f.dd, f.sec
            parts[#parts + 1] = clock_part(f)
        end
        recs[#recs + 1] = r
    end
    clock_sig = table.concat(parts, "\n")
    model.ws = recs
end

local function refresh_clock()
    local memo, parts = {}, {}
    for _, row in ipairs(visible()) do
        if row.c.kind == 1 then parts[#parts + 1] = clock_part(clock_fields(row.c, memo)) end
    end
    if table.concat(parts, "\n") ~= clock_sig then push() end
end

local have = {}             -- kind → true while some card shows it (feeds follow this)
local start_feeds           -- defined below

-- ── saving (debounced, atomic) ──
-- EVERY write of widgets.json goes through one queue, one at a time and in order (the debounced save, leaving edit mode, a
-- portable-setup apply): an older write can never land after a newer one. A body is text, or a function evaluated when
-- the write STARTS (so a queued save always writes the newest desktop).
local WIDGETS_WRITE = 'd="$HOME/.config/beskar"; f="$d/widgets.json"; t="$f.tmp"; '
    .. 'mkdir -p "$d" && printf \'%s\\n\' "$1" > "$t" || { rm -f "$t"; exit 1; }; sync "$t" 2>/dev/null; '
    .. 'mv -f "$t" "$f" || { rm -f "$t"; exit 1; }'
local write_queue, write_busy = {}, false
local function write_pump()
    if write_busy then return end
    local item = table.remove(write_queue, 1)
    if not item then return end
    write_busy = true
    local body = item.body
    if type(body) == "function" then
        local ok, b = pcall(body)
        body = ok and b or nil
    end
    local function settle(ok, code)
        write_busy = false
        if item.cb then item.cb(ok, code) end
        write_pump()
    end
    if type(body) ~= "string" then settle(false, 1); return end
    sh(WIDGETS_WRITE, function(_, code) settle(code == 0, code) end, body)
end
local function write_widgets(body, cb)
    write_queue[#write_queue + 1] = { body = body, cb = cb }
    write_pump()
end
local save_timer = nil
local function save_now()
    write_widgets(function() return json.encode(Opts.encode_file(CARDS, NEXT_ID, fact.snap_on and true or false)) end)
end
local function save()
    if save_timer then cancel(save_timer) end
    save_timer = after(400, function() save_timer = nil; save_now() end)
end

-- A history step is { cards = [...], snap = bool|nil }: `snap` is only set by a saved-layout load, which also changes
-- the grid option; every other step leaves the Grid toggle alone (it only changes how the next drops land).
local function snapshot(with_snap)
    local copy = {}
    for _, c in ipairs(CARDS) do copy[#copy + 1] = copy_card(c) end
    local step = { cards = copy }
    if with_snap then step.snap = fact.snap_on and true or false end
    HISTORY[#HISTORY + 1] = step
    if #HISTORY > 20 then table.remove(HISTORY, 1) end
    fact.can_undo = #HISTORY > 0
    push_bar()
end

function push_bar()
    say("topbar", "fact snap_on " .. tostring(fact.snap_on and true or false))
    say("topbar", "fact can_undo " .. tostring(fact.can_undo and true or false))
end

local layouts            -- the saved-desktops controller (below)
local push_options       -- the selected card's options → the widget bar (below)
local function changed()
    push_bar()
    push()
    start_feeds()
    save()
    push_options()
    if layouts then layouts.touch() end
end

-- ── placing ──
-- The grid is the card grid itself: cells of one small card (160) with a 16 px gap, so any two cards on it are
-- exactly one gap apart whatever their sizes (a medium is two cells wide, a large two by two).
local PITCH = UNIT + GAP
local OX, OY = 48, 72

local function overlaps(c, x, y, w, h)
    local cw, ch = width_of(c.sz), height_of(c.sz)
    return x < c.x + cw and x + w > c.x and y < c.y + ch and y + h > c.y
end

local function bounds(c)
    local sz = SIZES[c.out]
    local w, h = width_of(c.sz), height_of(c.sz)
    return (sz and sz[1] or 1920) - w - SIDE_SAFE, (sz and sz[2] or 1080) - h - SIDE_SAFE - 60
end

local function clamp_card(c)
    local maxx, maxy = bounds(c)
    c.x = math.max(SIDE_SAFE, math.min(c.x, maxx))
    c.y = math.max(TOP_SAFE, math.min(c.y, maxy))
end

local function blocked(c, x, y)
    local w, h = width_of(c.sz), height_of(c.sz)
    for _, o in ipairs(CARDS) do
        if o ~= c and not Stacks.same(o, c) and o.out == c.out and overlaps(o, x - GAP / 2, y - GAP / 2, w + GAP, h + GAP) then
            return true
        end
    end
    return false
end

-- Put a card on the nearest free cell to where it was dropped.
local function snap_card(c)
    if not fact.snap_on then
        c.x, c.y = math.floor(c.x + 0.5), math.floor(c.y + 0.5)
        clamp_card(c)
        return
    end
    local maxx, maxy = bounds(c)
    local cols = math.max(0, math.floor((maxx - OX) / PITCH))
    local rows = math.max(0, math.floor((maxy - OY) / PITCH))
    local best, bx, by = nil, c.x, c.y
    for r = 0, rows do
        for q = 0, cols do
            local x, y = OX + q * PITCH, OY + r * PITCH
            if not blocked(c, x, y) then
                local d = (x - c.x) ^ 2 + (y - c.y) ^ 2
                if not best or d < best then best, bx, by = d, x, y end
            end
        end
    end
    c.x, c.y = bx, by
end

local function free_spot(out, sz)
    local probe = { out = out, sz = sz, x = 0, y = 0 }
    local w, h = width_of(sz), height_of(sz)
    local screen = SIZES[out] or { 1920, 1080 }
    local y = OY
    while y + h < screen[2] - 80 do
        local x = OX
        while x + w < screen[1] - 20 do
            if not blocked(probe, x, y) then return x, y, true end
            x = x + PITCH
        end
        y = y + PITCH
    end
    return OX, OY, false
end

local function add_card(out, kind, sz, x, y)
    local k = kind_of(kind)
    if not k then return end
    local size = sz or k.def
    local cx, cy = x, y
    if not cx then cx, cy = free_spot(out, size) end
    CARDS[#CARDS + 1] = { id = NEXT_ID, out = out, kind = kind, sz = size, x = cx, y = cy }
    NEXT_ID = NEXT_ID + 1
end

local function defaults()
    CARDS = {}
    for _, out in ipairs(OUTPUTS) do
        add_card(out, 1, 1, 48, 72)
        add_card(out, 3, 0, 48, 248)
        add_card(out, 5, 0, 224, 248)
    end
end

local SEL = 0       -- the card whose options the widget bar shows (0 = none); only while editing
local opt_fail      -- tells the bar why a request was refused (below)

-- The portable-setup gate (shell/widget_setup.luau): while the owner applies a setup (compare-and-swap check -> file write
-- -> install, a few milliseconds) the user's state-changing events WAIT and replay, in order, AFTER the install, so a drag or
-- a removal made meanwhile is applied on top of the new desktop and never overwritten by it.
local gate_up, deferred = false, {}
local function guarded(fn)
    return function(p)
        if not gate_up then fn(p); return end
        if #deferred >= 64 then opt_fail("A setup is being applied: try again in a moment"); return end
        deferred[#deferred + 1] = function() fn(p) end
    end
end
local function set_gate(on)
    gate_up = on
    if on then return end
    local list = deferred
    deferred = {}
    for _, f in ipairs(list) do pcall(f) end
end

-- ── presets: whole desktops in one click (applied to every monitor) ──
on("w_preset", guarded(function(n)
    local p = PRESETS[tonumber(n) or 0]
    if not p then return end
    snapshot()
    CARDS = {}
    for _, out in ipairs(OUTPUTS) do
        for _, c in ipairs(p.cards) do add_card(out, c[1], c[2], c[3], c[4]) end
    end
    for _, c in ipairs(CARDS) do clamp_card(c) end
    SEL = 0          -- a preset replaces the whole desktop, locked cards included (one undo step brings it back)
    changed()
end))

-- ── edit mode ──
local function set_editing(on)
    if (fact.editing == true or fact.editing == 1) == on then return end
    fact.editing = on
    SEL = 0
    start_feeds()
    if on then
        HISTORY = {}
        fact.can_undo = false
    else
        say("panels", "emit close_id 10")
        save_now()
    end
    push_options()
end

local function find(id)
    for i, c in ipairs(CARDS) do
        if c.id == id then return c, i end
    end
end

-- ── per-card options (C4b) ──
-- Selection: pressing a card while arranging selects it (`w_configure(id)`; 0 = none). The widget bar shows the
-- selected card's options from `text wb_card_options` (a compact JSON snapshot this file pushes with `say`, also
-- readable with `--say widgets "get card_options"`) and changes them with the events below. Options always act on
-- the explicit current selection, never on a card that merely sits under the pointer.
--   emit w_configure <id>      select card <id> (0 clears); only while editing
--   emit w_opt <code>          code = option id * 10 + value index (1 = default): 12 lock, 23 hide date, 32 show seconds…
--   emit w_opt_next <id>       next value of option <id> for the selected card (wraps)
--   emit w_opt_reset           every option of the selected card back to its default
-- Each change is one undo step (`w_undo`). Position lock locks POSITION only: dragging, Tidy up and a saved layout's
-- reflow leave a locked card where it is (a layout that must fit a smaller screen still clamps it on screen);
-- resizing is allowed but happens in place; removing is allowed; a preset or Reset replaces the whole desktop.
local OPT_PUSH = { scene = "topbar", text = "wb_card_options" }
local opt_status = { seq = 0, ok = true, msg = "" }
local opt_last, opt_rev, opt_body = nil, 0, "{}"

local function editing_now() return fact.editing == true or fact.editing == 1 end

function push_options(force)
    local c
    if SEL ~= 0 and editing_now() then c = find(SEL) end
    -- the card that is selected is the one that is shown: a stack's options follow its face
    if c and Stacks.hidden(c) then c = Stacks.active(CARDS, c); SEL = c.id end
    if not c then SEL = 0 end
    fact.sel_id = SEL
    local snap = Opts.snapshot(c, {
        editing = editing_now(),
        name = function(k) local kd = kind_of(k); return kd and kd.name or "" end,
        sizes = function(k) local kd = kind_of(k); return kd and #kd.sizes or 1 end,
        stack = function(card) return Stacks.info(CARDS, card, kind_of) end,
    })
    if opt_status.seq > 0 then snap.st = { seq = opt_status.seq, ok = opt_status.ok, msg = opt_status.msg } end
    snap.rev = 0
    local ok, sig = pcall(json.encode, snap)
    if not ok then return end
    if sig ~= opt_last then
        opt_last = sig
        opt_rev = opt_rev + 1
        snap.rev = opt_rev
        local ok2, body = pcall(json.encode, snap)
        if not ok2 then return end
        opt_body = body
    elseif not force then
        return
    end
    text.card_options = opt_body
    -- the IPC command is limited to 4096 bytes; the snapshot is a few hundred
    if #opt_body < 3000 then say(OPT_PUSH.scene, "text " .. OPT_PUSH.text .. " " .. opt_body) end
end

function opt_fail(msg)
    opt_status = { seq = opt_status.seq + 1, ok = false, msg = msg }
    push_options()
end

local function selected()
    if SEL == 0 or not editing_now() then return nil end
    return (find(SEL))
end

on("w_configure", function(p)
    if type(p) == "table" then p = p.id end
    local id = math.floor(tonumber(p) or 0)
    if id ~= 0 then
        if not editing_now() then opt_fail("Open Edit Widgets to configure a widget"); return end
        if not find(id) then SEL = 0; opt_fail("That widget no longer exists"); return end
    end
    SEL = id
    push_options()
end)

local function apply_option(def, idx)
    local c = selected()
    if not c then opt_fail("Select a widget first"); return end
    if not Opts.applies(def, c.kind) then opt_fail(def.label .. " does not apply to this widget"); return end
    if type(idx) ~= "number" or idx ~= math.floor(idx) or idx < 1 or idx > #def.keys then opt_fail("Not a value of " .. def.label); return end
    if Opts.index(c, def.key) == idx then return end
    snapshot()
    Opts.set(c, def.key, idx)
    if def.key == "lock" then Stacks.set_lock(CARDS, c, Opts.locked(c)) end    -- a stack is locked as a whole
    changed()
end

on("w_opt", guarded(function(p)
    local def, idx
    if type(p) == "table" then
        def = type(p.opt) == "string" and Opts.def(p.opt) or Opts.by_id(tonumber(p.opt) or 0)
        -- a value is its name ("off", "24": names win over numbers) or its 1-based index
        if def and type(p.value) == "string" then idx = Opts.key_index(def, p.value) or tonumber(p.value)
        elseif def and type(p.value) == "boolean" then idx = Opts.key_index(def, p.value)
        else idx = tonumber(p.value) end
    else
        def, idx = Opts.parse_code(p)
    end
    if not def then opt_fail("Unknown option"); return end
    apply_option(def, idx)
end))

on("w_opt_next", guarded(function(p)
    if type(p) == "table" then p = p.id or p.opt end
    local def = Opts.by_id(math.floor(tonumber(p) or 0))
    if not def then opt_fail("Unknown option"); return end
    local c = selected()
    if not c then opt_fail("Select a widget first"); return end
    apply_option(def, Opts.index(c, def.key) % #def.keys + 1)
end))

on("w_opt_reset", guarded(function()
    local c = selected()
    if not c then opt_fail("Select a widget first"); return end
    if not c.opts then return end
    snapshot()
    Opts.reset(c)
    Stacks.set_lock(CARDS, c, false)
    changed()
end))

-- Edit mode and the widget bar (widget_bar.plm, grown out of the dock) open and close together: the bar opening
-- starts edit mode (`w_bar_open`), and asking for edit mode opens the bar through the frame (it picks the monitor).
on("edit_toggle", function()
    if fact.editing == true or fact.editing == 1 then
        set_editing(false)
    else
        say("topbar", "emit open_panel 7")
    end
end)
on("w_bar_open", function()
    set_editing(true)
    push_bar()
    push_options(true)
    if layouts then layouts.resend() end
end)
on("edit_done", function() set_editing(false) end)

on("w_drop", guarded(function(id)
    local c = find(id)
    local dx, dy = tonumber(fact.drag_dx) or 0, tonumber(fact.drag_dy) or 0
    -- a locked card never moves (the scene does not even start the drag; this is the owner's own guard)
    if c and not Opts.locked(c) and (math.abs(dx) > 2 or math.abs(dy) > 2) then
        snapshot()
        c.x, c.y = c.x + dx, c.y + dy
        snap_card(c)
        Stacks.sync(CARDS, c)
        push()
        save()
        if layouts then layouts.touch() end
    end
    fact.drag_id = 0
    fact.drag_dx = 0
    fact.drag_dy = 0
end))

on("w_add", guarded(function(code)
    local scr, kind = math.floor(code / 100), code % 100
    local out = OUTPUTS[scr + 1] or OUTPUTS[1]
    if not out or #CARDS >= 16 then return end
    snapshot()
    add_card(out, kind)
    changed()
end))

on("w_remove", guarded(function(id)
    local c, i = find(id)
    if not c then return end
    snapshot()
    Stacks.leave(CARDS, c)       -- the rest of its stack closes up (a neighbour is shown when it was the face)
    table.remove(CARDS, i)
    changed()
end))

-- ── stacks (C4c) ──
-- Cards of compatible size share ONE footprint; only the shown member ("face") is drawn, clickable and fed. Manual paging.
-- Events (a card id arrives as the event's number or as `{ id = n }`; all work from the CLI: `--say widgets "emit w_page_next 4"`):
--   emit w_stack <target id>   stack the SELECTED card onto <target> (any member of the target's stack; same display, a
--                              size the card's kind draws, not locked); it joins at the end and becomes the shown face
--   emit w_page_next <id>      show the next member of <id>'s stack (0 = the selected card's); works outside edit mode too
--   emit w_page_prev <id>      the previous one (both wrap, no undo step: paging is a view state, saved with the file)
--   emit w_unstack <id>        break the whole stack apart: the face stays, the others go to free grid cells (one undo step)
--   emit w_eject <id>          take one member out to a free cell (it is a normal card again)
-- The bar learns what is possible from the selected card's snapshot (`stack` key of text wb_card_options, see
-- Stacks.info): { id, n, i, m = [[card id, kind]…], pick = [[card id, kind]…] }. A refusal is reported through `st` like
-- the option errors. Position lock is stack-wide; Undo restores membership and the face together with everything else.
local STACK_WHY = {
    missing = "That widget no longer exists", same = "Those widgets are already in one stack",
    output = "Stack widgets that sit on the same display", locked = "Unlock a widget before stacking it",
    size = "That widget does not come in the stack's size", full = "A stack holds up to " .. Stacks.MAX_MEMBERS .. " widgets",
}
local function card_arg(p)
    if type(p) == "table" then p = p.id or p.target end
    local id = math.floor(tonumber(p) or 0)
    if id ~= 0 then return find(id) end
    return selected()
end
local function place_out(c)
    local x, y, found = free_spot(c.out, c.sz)
    if not found then return false end
    c.x, c.y = x, y
    return true
end
local function rollback()      -- take back the history step of a change that could not be completed
    local last = table.remove(HISTORY)
    if last then CARDS = last.cards end
    fact.can_undo = #HISTORY > 0
    push_bar()
end

on("w_stack", guarded(function(p)
    local src = selected()
    if not src then opt_fail("Select a widget first"); return end
    if type(p) == "table" then p = p.target or p.id end
    local tgt = find(math.floor(tonumber(p) or 0))
    local why = Stacks.join_refusal(CARDS, src, tgt, kind_of)
    if why then opt_fail(STACK_WHY[why] or "Cannot stack these widgets"); return end
    snapshot()
    Stacks.join(CARDS, src, tgt, kind_of)
    SEL = src.id
    changed()
end))

local function page(p, delta)
    local c = card_arg(p)
    local shown = c and Stacks.page(CARDS, c, delta)
    if not shown then
        if editing_now() then opt_fail("That widget is not in a stack") end
        return
    end
    local cur = SEL ~= 0 and find(SEL) or nil
    if cur and Stacks.same(cur, shown) then SEL = shown.id end
    changed()
end
on("w_page_next", guarded(function(p) page(p, 1) end))
on("w_page_prev", guarded(function(p) page(p, -1) end))

on("w_unstack", guarded(function(p)
    local c = card_arg(p)
    if not c or not c.stack then opt_fail("That widget is not in a stack"); return end
    if Opts.locked(c) then opt_fail("Unlock the stack to take it apart"); return end
    local face = Stacks.active(CARDS, c)
    snapshot()
    for _, m in ipairs(Stacks.members(CARDS, c)) do
        if m ~= face then
            Stacks.leave(CARDS, m)
            if not place_out(m) then rollback(); opt_fail("No room to unstack here"); return end
        end
    end
    changed()
end))

on("w_eject", guarded(function(p)
    local c = card_arg(p)
    if not c or not c.stack then opt_fail("That widget is not in a stack"); return end
    if Opts.locked(c) then opt_fail("Unlock the stack to take a widget out"); return end
    snapshot()
    Stacks.leave(CARDS, c)
    if not place_out(c) then rollback(); opt_fail("No room to take it out here"); return end
    changed()
end))

-- Would card `c` still fit where it stands at size `sz`? (work area, and with Grid on also free of other cards)
local function fits_in_place(c, sz)
    local was = c.sz
    c.sz = sz
    local maxx, maxy = bounds(c)
    local ok = c.x <= maxx and c.y <= maxy and not (fact.snap_on and blocked(c, c.x, c.y))
    c.sz = was
    return ok
end

on("w_resize", guarded(function(id)
    local c = find(id)
    if not c then return end
    -- a stack is resized as a whole: only sizes every member draws
    local sizes = Stacks.sizes(CARDS, c, kind_of)
    if #sizes < 2 then
        if c.stack then opt_fail("The widgets in this stack share only one size") end
        return
    end
    local at = 1
    for i, sz in ipairs(sizes) do
        if sz == c.sz then at = i end
    end
    if Opts.locked(c) then
        -- Position lock only locks the position: size changes stay allowed, but in place. The next size that fits
        -- where the card stands is used; if none does, nothing changes and the bar is told why.
        local picked
        for step = 1, #sizes - 1 do
            local sz = sizes[(at - 1 + step) % #sizes + 1]
            if fits_in_place(c, sz) then picked = sz; break end
        end
        if not picked then
            opt_fail("Locked in place: no other size fits here")
            return
        end
        snapshot()
        c.sz = picked
        Stacks.sync(CARDS, c)
        changed()
        return
    end
    snapshot()
    c.sz = sizes[at % #sizes + 1]
    snap_card(c)
    Stacks.sync(CARDS, c)
    changed()
end))

on("w_undo", guarded(function()
    local last = table.remove(HISTORY)
    if not last then return end
    CARDS = last.cards
    if last.snap ~= nil then fact.snap_on = last.snap end
    fact.can_undo = #HISTORY > 0
    changed()
end))

on("w_reset", guarded(function()
    snapshot()
    defaults()
    SEL = 0
    changed()
end))

-- Tidy up: every card back on the grid, packed from the top left in reading order.
local function tidy()
    snapshot()
    local by_out = {}
    for _, c in ipairs(CARDS) do
        -- locked cards stay exactly where they are and act as obstacles for the others
        -- a stack is ONE footprint: only its face is packed, its members follow
        if not Opts.locked(c) and not Stacks.hidden(c) then
            by_out[c.out] = by_out[c.out] or {}
            table.insert(by_out[c.out], c)
        end
    end
    local was = fact.snap_on
    fact.snap_on = true
    for _, list in pairs(by_out) do
        table.sort(list, function(a, b)
            if math.abs(a.y - b.y) > 60 then return a.y < b.y end
            return a.x < b.x
        end)
        for _, c in ipairs(list) do
            c.x, c.y = -10000, -10000
            for _, m in ipairs(Stacks.members(CARDS, c) or {}) do m.x, m.y = -10000, -10000 end
        end
        for _, c in ipairs(list) do
            c.x, c.y = free_spot(c.out, c.sz)
            Stacks.sync(CARDS, c)
        end
    end
    fact.snap_on = was
    changed()
end
on("w_tidy", guarded(tidy))

on("w_grid", guarded(function()
    fact.snap_on = not fact.snap_on
    push_bar()
    save()
end))

on("w_open", function(code)
    if fact.editing then return end
    code = tonumber(code) or 0
    local kind, screen = code % 100, math.floor(code / 100)
    if kind == 10 or kind == 11 or kind == 12 then
        -- Each process can number screens differently. Send the ordinal of the output NAME
        -- in a sorted list, which the frame maps back through its own screen table.
        local names, ordinal = {}, nil
        for _, name in ipairs(OUTPUTS) do names[#names + 1] = name end
        table.sort(names)
        for i, name in ipairs(names) do if name == OUTPUTS[screen + 1] then ordinal = i - 1 end end
        if ordinal then
            if kind == 12 then say("topbar", "emit open_timer_output " .. ordinal)
            else say("topbar", "emit pe_open " .. (1000 + ordinal * 100 + (kind == 11 and 1 or 0))) end
        end
    elseif kind == 1 or kind == 2 or kind == 3 or kind == 5 or kind == 7 then
        say("topbar", "emit open_dashboard")
    end
end)

-- ── media ──
local playing = false
sys.watch("media", function(m)
    m = m or {}
    local title = m.title or ""
    playing = m.playing == true
    fact.has_player = (m.player or "") ~= "" or title ~= ""
    fact.is_playing = playing
    text.track_title = title ~= "" and title or "Unknown title"
    text.track_artist = m.artist or ""
    text.cover_art = m.art or ""
end)
on("w_vol", function(v) sys.call("audio.volume", v) end)
on("w_bri", function(v) sys.call("brightness.level", math.max(0.05, tonumber(v) or 1)) end)
on("w_play", function() sys.call("media.toggle") end)
on("w_next", function() sys.call("media.next") end)
on("w_prev", function() sys.call("media.previous") end)

-- ── clock, date, calendar ──
local last_day = ""
local function paint_clock()
    -- the shell's own time (the legacy texts); each clock card paints its own through the model (push)
    local time, ampm = Opts.split_time(clockfmt(fact.hour12))
    text.w_time = time
    text.w_ampm = ampm
    local hh, mm, ss = tonumber(os.date("%H")), tonumber(os.date("%M")), tonumber(os.date("%S"))
    local used = hh * 3600 + mm * 60 + ss
    fact.day_pct = math.floor(used * 100 / 86400)
    local left = 86400 - used
    text.day_left = string.format("%dh %dm left", math.floor(left / 3600), math.floor(left % 3600 / 60))
    local day = os.date("%Y-%m-%d")
    if day ~= last_day then
        last_day = day
        text.w_month = os.date("%B"):upper()
        text.w_day = tostring(tonumber(os.date("%d")))
        text.w_dow = os.date("%A")
        text.w_datelong = os.date("%A, %B ") .. tonumber(os.date("%d"))
        DATE_LONG = text.w_datelong
        local view = require("calendar").month(0)
        text.cal_title, model.cal_month = view.title, {view}
    end
    refresh_clock()
end
paint_clock()
every(15000, paint_clock)
on("fact:hour12", paint_clock)
-- the shell's default for seconds on widget clocks (cards set to Automatic follow it); the seconds feed follows it too
on("fact:clock_seconds", function() start_feeds(); refresh_clock() end)

-- Weather comes from the read-only snapshot client below.

-- ── system ──
local STATS = [[
a=$(awk '/^cpu /{print $2+$3+$4+$5+$6+$7+$8, $5+$6}' /proc/stat); sleep 0.4
b=$(awk '/^cpu /{print $2+$3+$4+$5+$6+$7+$8, $5+$6}' /proc/stat)
echo "$a $b" | awk '{d=$3-$1; i=$4-$2; print (d>0) ? int((d-i)*100/d+0.5) : 0}'
awk '/MemTotal/{t=$2} /MemAvailable/{a=$2} END{print int((t-a)*100/t+0.5)}' /proc/meminfo
df / | awk 'NR==2{gsub("%","",$5); print $5}'
awk '{s=int($1); d=int(s/86400); h=int((s%86400)/3600); m=int((s%3600)/60); if (d>0) printf "%dd %dh %dm\n", d, h, m; else printf "%dh %dm\n", h, m}' /proc/uptime
]]
local stats_busy = false
local function refresh_stats()
    if stats_busy then return end
    stats_busy = true
    run("sh", { "-c", STATS }, function(out, code)
        stats_busy = false
        if code ~= 0 or not out then return end
        local l = {}
        for line in out:gmatch("[^\r\n]+") do l[#l + 1] = line end
        if #l >= 3 then
            fact.cpu_pct = math.min(100, tonumber(l[1]) or 0)
            fact.mem_pct = math.min(100, tonumber(l[2]) or 0)
            fact.disk_pct = math.min(100, tonumber(l[3]) or 0)
        end
        if l[4] then text.up_text = l[4] end
    end)
end

-- Feeds follow the cards: a timer exists only while something on a desktop uses it.
local timers = {}
-- A clock that shows seconds needs a one-second repaint; nothing else does (the shared 15 s tick covers minutes).
-- It exists only while some clock card is on a connected output, shown (or being arranged), with seconds in effect.
local function wants_seconds()
    if not (fact.widgets_on == true or fact.editing == true) then return false end
    local g = clock_globals()
    for _, row in ipairs(visible()) do
        if row.c.kind == 1 and Opts.clock(row.c, g).seconds then return true end
    end
    return false
end
function start_feeds()
    have = {}
    for _, c in ipairs(CARDS) do
        if index_of(c.out) >= 0 and not Stacks.hidden(c) then have[c.kind] = true end
    end
    local want_sec = wants_seconds()
    if want_sec and not timers.seconds then
        timers.seconds = every(1000, refresh_clock)
    elseif not want_sec and timers.seconds then
        cancel(timers.seconds)
        timers.seconds = nil
    end
    timer_feed(have[12] == true and (fact.widgets_on == true or fact.editing == true))
    if have[5] and not timers.stats then
        refresh_stats()
        timers.stats = every(3000, refresh_stats)
    elseif not have[5] and timers.stats then
        cancel(timers.stats)
        timers.stats = nil
    end
end

-- ── start: screens, outputs, then the saved layout ──
local function load_layout()
    sh('cat "$HOME/.config/beskar/widgets.json" 2>/dev/null', function(out)
        local ok, d = pcall(json.decode, out or "")
        CARDS = {}
        local file = ok and Opts.decode_file(d, kind_of) or nil
        local function finish()
            loaded = true
            for _, c in ipairs(CARDS) do clamp_card(c) end
            changed()      -- also rewrites the file in the current version (a version 1 file is migrated here)
        end
        if file then
            CARDS = file.cards
            NEXT_ID = file.next
            if not file.snap then fact.snap_on = false end
            if file.newer then
                -- written by a newer Beskar: read what this build understands, but keep the original beside it
                -- (once per version) before the first save replaces it
                sh('f="$HOME/.config/beskar/widgets.json"; [ -e "$f.v$1" ] || cp -- "$f" "$f.v$1"', function() finish() end,
                    tostring(math.floor(file.version)))
                return
            end
        else
            defaults()
        end
        finish()
    end)
end

local function learn(tries)
    -- in the one-process desktop the log lines say which scene each surface is (`surface 9 on HDMI-A-1 · … · Widgets copy 1`);
    -- as its own process (older layout) the widgets' own log has `surface N on NAME`
    local script = "if grep -q 'surface [0-9]* on .* Widgets' /tmp/pleamar_desktop.log 2>/dev/null; then "
        .. "grep 'surface [0-9]* on .* Widgets' /tmp/pleamar_desktop.log | head -8; "
        .. "else grep 'surface [0-9]* on' /tmp/pleamar_widgets.log 2>/dev/null | head -8; fi"
    sh(script, function(out)
        local map = {}
        local n = 0
        for line in (out or ""):gmatch("[^\n]+") do
            local name = line:match("surface %d+ on (%S+)")
            if name then
                local copy = line:match("Widgets copy (%d+)")
                local idx = copy and tonumber(copy) or (line:find("Widgets", 1, true) and 0 or nil)
                if idx == nil then idx = tonumber(line:match("surface (%d+) on")) or n end
                map[idx + 1] = name
                n = n + 1
            end
        end
        if #map > 0 then
            OUTPUTS = map
            fact.nscreens = #map
            sh("niri msg -j outputs 2>/dev/null", function(o)
                local ok, d = pcall(json.decode, o or "")
                if ok and type(d) == "table" then
                    for name, info in pairs(d) do
                        local lm = info.logical
                        if lm then SIZES[name] = { lm.width, lm.height } end
                    end
                end
                if loaded then changed() else load_layout() end
            end)
        elseif tries > 0 then
            after(2000, function() learn(tries - 1) end)
        else
            OUTPUTS = { "eDP-1" }
            load_layout()
        end
    end)
end
after(1200, function() learn(8) end)

-- ── saved desktops (C4a) ──
-- Named layouts of this desktop in ~/.config/beskar/widget-layouts.json; THIS file is its only writer. The logic
-- (validation, limits, restore with clamp / reflow, the queue) is shell/widget_layouts.luau; here are only the
-- host hooks. Events (all CLI-compatible: a name travels in `text wl_name`, an id as the event's number):
--   text wl_name <name>  then  emit wl_save | wl_rename <id>      emit wl_update <id>   emit wl_load <id>
--   emit wl_duplicate <id>   emit wl_delete <id>   emit wl_list   emit wl_get <id>
-- Reading: `get wl_snapshot` (compact JSON, also pushed to the widget bar), `get wl_status`, `get wl_detail` (after wl_get).
-- Loading puts the saved desktop in place as ONE undo step (`w_undo`); Personal / Activities content and running
-- timers are never touched: only where their cards sit changes.
local Layouts = require("widget_layouts")
local LAYOUT_READ = 'f="$HOME/.config/beskar/widget-layouts.json"; [ -e "$f" ] || exit 3; [ -r "$f" ] || exit 4; '
    .. '[ "$(wc -c < "$f")" -le ' .. Layouts.MAX_BYTES .. ' ] || exit 5; cat "$f"'
local LAYOUT_WRITE = 'd="$HOME/.config/beskar"; f="$d/widget-layouts.json"; t="$f.tmp"; '
    .. 'mkdir -p "$d" && printf \'%s\\n\' "$1" > "$t" || { rm -f "$t"; exit 1; }; sync "$t" 2>/dev/null; '
    .. 'mv -f "$t" "$f" || { rm -f "$t"; exit 1; }'
local LAYOUT_BACKUP = 'f="$HOME/.config/beskar/widget-layouts.json"; '
    .. 'for b in "$f".corrupt-*; do [ -e "$b" ] && cmp -s "$f" "$b" && exit 0; done; cp -- "$f" "$f.corrupt-$1"'
-- Where the bar listens (a scene never writes another's text: the bar declares `wb_layouts` and takes this say).
local LAYOUT_PUSH = { scene = "topbar", text = "wb_layouts" }

local function layout_context()
    local connected = {}
    for _, name in ipairs(OUTPUTS) do connected[name] = true end
    return { connected = connected, sizes = SIZES, kind_of = kind_of, limit = 16,
        geom = { unit = UNIT, gap = GAP, top = TOP_SAFE, side = SIDE_SAFE, bottom = 60, ox = OX, oy = OY, def_w = 1920, def_h = 1080 } }
end

layouts = Layouts.controller({
    json = json,
    now = function() return os.time() end,
    read = function(cb)
        sh(LAYOUT_READ, function(out, code)
            if code == 0 then cb("ok", out or "")
            elseif code == 3 then cb("missing")
            elseif code == 5 then cb("toolarge")
            else cb("error") end
        end)
    end,
    write = function(body, cb)
        sh(LAYOUT_WRITE, function(_, code) cb(code == 0) end, body)
    end,
    backup = function(cb)
        sh(LAYOUT_BACKUP, function(_, code) cb(code == 0) end, tostring(os.time()))
    end,
    ready = function() return loaded and #OUTPUTS > 0 and not gate_up end,
    capture = function() return { cards = CARDS, snap = fact.snap_on and true or false, sizes = SIZES } end,
    context = layout_context,
    apply = function(cards, snap)
        snapshot(true)
        CARDS = cards
        SEL = 0
        for _, c in ipairs(CARDS) do
            if c.id >= NEXT_ID then NEXT_ID = c.id + 1 end
        end
        fact.snap_on = snap and true or false
        changed()
    end,
    cards = function() return CARDS end,
    publish = function(snap, body, status)
        text.wl_snapshot = body
        text.wl_status = status.msg
        fact.wl_rev = snap.rev
        fact.wl_count = snap.count
        fact.wl_ready = snap.ready
        fact.wl_error = status.ok == false
        -- The IPC command is limited to 4096 bytes. The bar needs names/counts,
        -- not timestamps/options; keep the full snapshot available to CLI callers.
        local bridge = require("widget_layouts").bar_snapshot(snap)
        local ok, compact = pcall(json.encode, bridge)
        if ok and #compact < 4000 then say(LAYOUT_PUSH.scene, "text " .. LAYOUT_PUSH.text .. " " .. compact) end
    end,
})

-- An id arrives as the event's number (CLI) or as a field of a table (logic); a name as `text wl_name`, a string
-- payload or a table field. The name text is consumed at once so a later call never reuses a stale one.
local function layout_id(p)
    if type(p) == "table" then p = p.id end
    return math.floor(tonumber(p) or 0)
end
local function layout_name(p)
    local name = text.wl_name or ""
    if type(p) == "table" and type(p.name) == "string" then name = p.name
    elseif type(p) == "string" and tonumber(p) == nil and p ~= "" then name = p end
    text.wl_name = ""
    return name
end
on("wl_save", function(p) layouts.save(layout_name(p)) end)
on("wl_update", function(p) layouts.update(layout_id(p)) end)
on("wl_load", guarded(function(p) layouts.load(layout_id(p)) end))
on("wl_rename", function(p) local id = layout_id(p); layouts.rename(id, layout_name(p)) end)
on("wl_duplicate", function(p) layouts.duplicate(layout_id(p)) end)
on("wl_delete", function(p) layouts.delete(layout_id(p)) end)
on("wl_list", function() layouts.refresh() end)
on("wl_get", function(p)
    local l = layouts.read(layout_id(p))
    local ok, body = pcall(json.encode, l or {})
    text.wl_detail = ok and body or "{}"
end)
after(400, layouts.start)

-- ── portable setup bridge (C5, shell/widget_setup.luau; the exact protocol is documented there) ──
-- Settings stages ~/.config/beskar/setup-widget-request.json and sends `emit setup_request <id>`; this file answers in
-- ~/.config/beskar/setup-widget-response.json and only then says `emit setup_widgets_reply <id>` to settings. The request
-- file is read, the response written, and widgets.json replaced ATOMICALLY; nothing here polls or subscribes to anything.
local SETUP_REQUEST_READ = 'f="$HOME/.config/beskar/setup-widget-request.json"; [ -e "$f" ] || exit 3; '
    .. '[ -f "$f" ] && [ -r "$f" ] || exit 4; [ "$(wc -c < "$f")" -le ' .. require("widget_setup").MAX_REQUEST_BYTES .. ' ] || exit 5; cat "$f"'
local SETUP_RESPONSE_WRITE = 'd="$HOME/.config/beskar"; f="$d/setup-widget-response.json"; t="$f.tmp"; '
    .. 'mkdir -p "$d" && printf \'%s\\n\' "$1" > "$t" || { rm -f "$t"; exit 1; }; sync "$t" 2>/dev/null; '
    .. 'mv -f "$t" "$f" || { rm -f "$t"; exit 1; }'
local function next_id_after(cards)
    local nid = NEXT_ID
    for _, c in ipairs(cards) do
        if c.id >= nid then nid = c.id + 1 end
    end
    return nid
end
local setup = require("widget_setup").new({
    json = json,
    profiles = function()
        local ok, m = pcall(require, "setup_profiles")
        return ok and type(m) == "table" and m or nil
    end,
    read_request = function(cb)
        sh(SETUP_REQUEST_READ, function(out, code)
            if code == 0 then cb("ok", out or "")
            elseif code == 3 then cb("missing")
            elseif code == 5 then cb("toolarge")
            else cb("error") end
        end)
    end,
    write_response = function(body, cb)
        sh(SETUP_RESPONSE_WRITE, function(_, code) cb(code == 0) end, body)
    end,
    notify = function(id) say("settings", "emit setup_widgets_reply " .. math.floor(id)) end,
    ready = function() return loaded and #OUTPUTS > 0 end,
    live = function()
        local cards = {}
        for _, c in ipairs(CARDS) do cards[#cards + 1] = copy_card(c) end
        return { snap = fact.snap_on and true or false, cards = cards }
    end,
    outputs = function()
        local map = {}
        for _, name in ipairs(OUTPUTS) do map[name] = true end
        return map
    end,
    restore = function(layout, exact)
        local ctx = layout_context()
        if exact then ctx.connected = {} end        -- a rollback puts every card back exactly where it was (no reflow)
        return Layouts.restore(layout, ctx)
    end,
    persist = function(cards, snap, cb)
        local ok, body = pcall(json.encode, Opts.encode_file(cards, next_id_after(cards), snap))
        if not ok then cb(false, false); return end
        write_widgets(body, function(wrote, code)
            cb(wrote, not wrote and (code == nil or code >= 128))
        end)
    end,
    top_fp = function()
        local top = HISTORY[#HISTORY]
        return top and top.setup_fp or nil
    end,
    install = function(cards, snap, how, tag)
        if how == "replace" then table.remove(HISTORY)
        elseif how == "push" then
            snapshot(true)           -- ONE undo step of widgets' own: the desktop as it was, with its grid option
            HISTORY[#HISTORY].setup_fp = tag
        end
        CARDS = cards
        SEL = 0
        NEXT_ID = next_id_after(cards)
        fact.snap_on = snap and true or false
        fact.can_undo = #HISTORY > 0
        changed()
        if save_timer then cancel(save_timer); save_timer = nil end      -- the file already holds exactly this desktop
    end,
    gate = set_gate,
    resave = function() save() end,
    after = after,
    cancel = cancel,
})
on("setup_request", function(p) setup.request(p) end)

require("personal_client")()

require("weather_client")()

-- A supervised restart of this process starts with the default look: ask Settings ONCE for the current theme, custom
-- style and reduce-motion facts (it answers with the same broadcast the other themed scenes get). No repeated poll.
after(250, function() pcall(sys.call, "say", "settings", "emit theme_sync") end)

on("fact:widgets_on", start_feeds)
on("fact:editing", start_feeds)
