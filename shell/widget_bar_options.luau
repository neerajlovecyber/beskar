-- The widget bar's "Card" page (C4b UI). Pure logic: no globals, no scene access, so a test can run it with a fake host.
-- dockpanels.luau binds it to the bar's facts / texts / model. Widgets stays the only owner of card options: this module
-- only reads the snapshot Widgets pushes into `text wb_card_options` and asks Widgets, by `say`, to change the SELECTED card
-- (`emit w_opt <option id * 10 + 1-based value index>`, `emit w_opt_reset`). It never edits a card itself.
--
-- Snapshot (widget_options.luau `snapshot`):
--   { v = 1, rev, editing, sel, kind, name, sz, nsz, out, lock,
--     options = [ { id, key, label, value, n, labels } ] (at most 4), st = { seq, ok, msg }? }
-- Anything outside these bounds is refused whole: the page then says the options are unavailable.
local B = {}

B.MAX_WIRE = 4096        -- bytes of snapshot text this side will parse (Widgets' own push limit is 3000)
B.MAX_OPTIONS = 4        -- rows the page draws (the scene's model is `max 4`)
B.MAX_CHOICES = 3        -- value buttons per row
B.MAX_TEXT = 40
local SIZE_NAME = { [0] = "Small", [1] = "Medium", [2] = "Large" }   -- widgets.plm: size 0 160×160 · 1 336×160 · 2 336×336

local function is_int(v, lo, hi)
    return type(v) == "number" and v == v and v == math.floor(v) and v >= lo and v <= hi
end

-- Controls → spaces, runs collapse, trimmed, cut at `n` characters. nil for a non-string or invalid UTF-8.
local function clean(s, n)
    if type(s) ~= "string" then return nil end
    s = s:gsub("%c", " "):gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "")
    local len = utf8.len(s)
    if not len then return nil end
    if len > n then s = s:sub(1, utf8.offset(s, n + 1) - 1):gsub(" $", "") end
    return s
end

-- text → the validated snapshot, or nil, reason.
function B.parse(text, json)
    if type(text) ~= "string" or text == "" or #text > B.MAX_WIRE then return nil, "size" end
    local ok, d = pcall(json.decode, text)
    if not ok or type(d) ~= "table" then return nil, "json" end
    if d.v ~= 1 then return nil, "version" end
    if not is_int(d.rev, 0, 2147483647) or type(d.editing) ~= "boolean" or not is_int(d.sel, 0, 2147483647) then return nil, "shape" end
    local s = { rev = d.rev, editing = d.editing, sel = d.sel, options = {}, lock = d.lock == true, sz = 0, nsz = 1, kind = 0, name = "" }
    if d.sel > 0 then
        if not is_int(d.kind, 0, 1000) or not is_int(d.sz, 0, 2) or not is_int(d.nsz, 1, 3) then return nil, "card" end
        s.kind, s.sz, s.nsz = d.kind, d.sz, d.nsz
        s.name = clean(d.name, B.MAX_TEXT)
        if not s.name then return nil, "name" end
        if d.out ~= nil then
            s.out = clean(d.out, 32)
            if not s.out then return nil, "out" end
        end
        if d.lock ~= nil and type(d.lock) ~= "boolean" then return nil, "lock" end
        local list = d.options == nil and {} or d.options
        if type(list) ~= "table" or #list > B.MAX_OPTIONS then return nil, "options" end
        local seen = {}
        for i = 1, #list do
            local o = list[i]
            if type(o) ~= "table" or not is_int(o.id, 1, 99) or seen[o.id] then return nil, "option" end
            seen[o.id] = true
            if not is_int(o.n, 2, B.MAX_CHOICES) or not is_int(o.value, 1, o.n) then return nil, "option" end
            local key = type(o.key) == "string" and #o.key <= 24 and o.key:match("^[%a_][%w_]*$") and o.key
            local label = clean(o.label, B.MAX_TEXT)
            if not key or not label or label == "" or type(o.labels) ~= "table" or #o.labels ~= o.n then return nil, "option" end
            local labels = {}
            for k = 1, o.n do
                labels[k] = clean(o.labels[k], 24)
                if not labels[k] or labels[k] == "" then return nil, "option" end
            end
            s.options[i] = { id = o.id, key = key, label = label, value = o.value, n = o.n, labels = labels }
        end
    elseif d.options ~= nil and (type(d.options) ~= "table" or #d.options > 0) then
        return nil, "options"
    end
    s.stack = { id = 0, n = 1, i = 1, m = {}, pick = {} }
    if d.sel > 0 and d.stack ~= nil then
        local st = d.stack
        if type(st) ~= "table" or not is_int(st.id, 0, 2147483646) or not is_int(st.n, 1, 8)
            or not is_int(st.i, 1, st.n) then return nil, "stack" end
        local function pairs_list(list, limit)
            if type(list) ~= "table" or #list > limit then return nil end
            local rows, seen = {}, {}
            for i, row in ipairs(list) do
                if type(row) ~= "table" or #row ~= 2 or not is_int(row[1], 1, 2147483647)
                    or not is_int(row[2], 1, 1000) or seen[row[1]] then return nil end
                seen[row[1]], rows[i] = true, { row[1], row[2] }
            end
            return rows
        end
        local members, picks = pairs_list(st.m, 8), pairs_list(st.pick, 15)
        if not members or not picks then return nil, "stack" end
        if st.id == 0 then
            if st.n ~= 1 or st.i ~= 1 or #members ~= 0 then return nil, "stack" end
        elseif st.n < 2 or #members ~= st.n or members[st.i][1] ~= d.sel then return nil, "stack" end
        for _, row in ipairs(picks) do
            if row[1] == d.sel then return nil, "stack" end
            for _, member in ipairs(members) do if row[1] == member[1] then return nil, "stack" end end
        end
        s.stack = { id = st.id, n = st.n, i = st.i, m = members, pick = picks }
    end
    if d.st ~= nil then
        local st = d.st
        if type(st) ~= "table" or not is_int(st.seq, 0, 2147483647) or type(st.ok) ~= "boolean" then return nil, "status" end
        local msg = st.msg == nil and "" or clean(st.msg, 160)
        if not msg then return nil, "status" end
        s.st = { seq = st.seq, ok = st.ok, msg = msg }
    end
    return s
end

-- host = { json, say(words) → bool, publish(view), page_changed(active) (optional) }
function B.controller(host)
    local c = {}
    local snap = nil
    local active = false        -- the Card page is the one showing
    local bar_open = false
    local last_sel = 0          -- the selection the last snapshot reported (a CHANGE to a positive one opens the page)
    local row_id = 0            -- the option whose row is selected (keys act on it)
    local last_seq, baseline = 0, true
    local status = { ok = true, msg = "" }
    local broken = false        -- the last snapshot could not be trusted
    local last_sig = nil
    local stack_target = 0

    local function options() return snap and snap.options or {} end
    local function row_of(id)
        for i, o in ipairs(options()) do if o.id == id then return i, o end end
    end
    local function selected_row()
        local i, o = row_of(row_id)
        if not i and #options() > 0 then i, o = 1, options()[1]; row_id = o.id end
        return i, o
    end
    local function has_card() return not broken and snap ~= nil and snap.editing and snap.sel > 0 end
    local function local_status(ok, msg) status = { ok = ok, msg = msg } end

    local function build()
        local v = { active = active, rows = {}, sel_id = 0, row = 0, status = status.msg, status_ok = status.ok }
        local card = has_card() and not broken
        v.has_card = card
        if broken then v.empty, v.hint = "Options unavailable", "The widgets sent something this bar cannot read"
        elseif not snap then v.empty, v.hint = "Waiting for the widgets…", ""
        elseif not card then v.empty, v.hint = "Select a widget", "Click a widget on the desktop to change its options"
        else v.empty, v.hint = "", "" end
        v.title, v.sub = "", ""
        if card then
            v.title = snap.name
            local parts = {}
            parts[#parts + 1] = SIZE_NAME[snap.sz]
            if snap.out and snap.out ~= "" then parts[#parts + 1] = snap.out end
            if snap.lock then parts[#parts + 1] = "Locked" end
            v.sub = table.concat(parts, "  ·  ")
            local ri = selected_row()
            v.row = ri or 0
            for i, o in ipairs(snap.options) do
                v.rows[i] = { id = o.id, label = o.label, value = o.value, n = o.n, sel = i == ri,
                    l1 = o.labels[1] or "", l2 = o.labels[2] or "", l3 = o.labels[3] or "" }
                if i == ri then v.sel_id = o.id end
                if o.value ~= 1 then v.can_reset = true end
            end
        end
        v.can_reset = v.can_reset == true
        v.stacked, v.stack_can_join, v.stack_can_unstack = false, false, false
        v.stack_target, v.stack_label, v.stack_position = 0, "No compatible widget", ""
        if card then
            local st = snap.stack
            local target
            for _, row in ipairs(st.pick) do if row[1] == stack_target then target = row end end
            target = target or st.pick[1]
            stack_target = target and target[1] or 0
            v.stack_target = stack_target
            v.stacked = st.id > 0
            v.stack_can_join = target ~= nil and not snap.lock
            v.stack_can_unstack = v.stacked and not snap.lock
            if target then
                local label = host.kind_name and host.kind_name(target[2]) or ("Widget " .. target[2])
                v.stack_label = label .. " #" .. target[1]
            end
            v.stack_position = v.stacked and ("Page " .. st.i .. " of " .. st.n) or "Choose another widget to share its place"
        end
        v.count = #v.rows
        return v
    end

    local function publish()
        local v = build()
        local ok, sig = pcall(host.json.encode, v)
        if not ok then sig = nil end
        if sig ~= nil and sig == last_sig then return end
        last_sig = sig
        host.publish(v)
    end

    local function set_active(on)
        if active == on then return end
        active = on
        if host.page_changed then host.page_changed(active) end
    end

    local function ask(words)
        if host.say(words) then return true end
        local_status(false, "Could not reach the widgets")
        publish()
        return false
    end

    -- ── incoming snapshot ──
    function c.snapshot(body)
        local s = B.parse(body, host.json)
        if not s then
            broken = true
            local_status(false, "Could not read the card options")
            publish()
            return
        end
        broken = false
        local was_sel = last_sel
        snap = s
        last_sel = (s.editing and s.sel > 0) and s.sel or 0
        if last_sel ~= was_sel then
            row_id = 0                                    -- another card: start at its first option
            local_status(true, "")
        end
        if s.st then
            if baseline then
                last_seq, baseline = s.st.seq, false        -- what Widgets said before the bar opened is old news
            elseif s.st.seq ~= last_seq then
                last_seq = s.st.seq
                local_status(s.st.ok, s.st.msg)
            end
        else
            baseline = false
        end
        -- a NEW positive selection while the bar is open opens the Card page; the tabs still let the user go back
        if bar_open and last_sel > 0 and last_sel ~= was_sel then set_active(true) end
        publish()
    end

    -- ── the bar ──
    function c.opened()
        bar_open = true
        snap, broken, last_sel, row_id = nil, false, 0, 0     -- Widgets resends its snapshot when the bar opens
        baseline = true
        status = { ok = true, msg = "" }
        set_active(false)
        publish()
    end
    function c.closed()
        bar_open = false
        status = { ok = true, msg = "" }
        set_active(false)
        publish()
    end
    function c.active() return active end
    function c.enter() set_active(true); publish() end
    function c.leave() set_active(false); publish() end

    -- ── rows ──
    function c.pick(id)
        id = math.floor(tonumber(id) or 0)
        if row_of(id) then row_id = id; publish() end
    end
    function c.move(delta)
        local list = options()
        if #list == 0 then return end
        delta = math.floor(tonumber(delta) or 0)
        local i = selected_row() or 1
        i = math.max(1, math.min(#list, i + delta))
        row_id = list[i].id
        publish()
    end

    -- ── asking Widgets ──
    -- code = option id * 10 + 1-based value index; only a value this snapshot offers is sent.
    function c.choose(code)
        code = tonumber(code)
        if not code or code ~= math.floor(code) or code < 10 then return false end
        local id, idx = math.floor(code / 10), code % 10
        local _, o = row_of(id)
        if not o or not has_card() or idx < 1 or idx > o.n then return false end
        row_id = o.id
        if o.value == idx then publish(); return true end
        return ask("emit w_opt " .. (id * 10 + idx))
    end
    function c.change(delta)                       -- Left / Right: step within the choices, no wrap
        local _, o = selected_row()
        if not o or not has_card() then return false end
        delta = (tonumber(delta) or 0) < 0 and -1 or 1
        local idx = math.max(1, math.min(o.n, o.value + delta))
        return c.choose(o.id * 10 + idx)
    end
    function c.cycle()                             -- Return: next value, wrapping
        local _, o = selected_row()
        if not o or not has_card() then return false end
        return c.choose(o.id * 10 + (o.value % o.n + 1))
    end
    function c.reset()
        if not has_card() then return false end
        return ask("emit w_opt_reset")
    end
    function c.stack_target(delta)
        if not has_card() or broken or #snap.stack.pick == 0 then return false end
        local list, index = snap.stack.pick, 1
        for i, row in ipairs(list) do if row[1] == stack_target then index = i end end
        stack_target = list[(index - 1 + ((tonumber(delta) or 1) < 0 and -1 or 1)) % #list + 1][1]
        publish()
        return true
    end
    function c.stack_join()
        local v = build()
        return v.stack_can_join and ask("emit w_stack " .. v.stack_target) or false
    end
    function c.stack_page(delta)
        if not has_card() or broken or snap.stack.id == 0 then return false end
        return ask("emit " .. ((tonumber(delta) or 1) < 0 and "w_page_prev " or "w_page_next ") .. snap.sel)
    end
    function c.stack_unstack()
        if not build().stack_can_unstack then return false end
        return ask("emit w_unstack " .. snap.sel)
    end

    function c.view() return build() end
    return c
end

return B
