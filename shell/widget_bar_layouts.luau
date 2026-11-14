-- The widget bar's "Desktops" page (C4a UI). Pure logic: no globals, no scene access, so tests/widget-bar-layouts.lua
-- runs it with a fake host. dockpanels.luau binds it to the bar's facts / texts / model; Widgets stays the only owner
-- and writer of the layouts (shell/widget_layouts.luau): this module only reads the snapshot Widgets pushes into
-- `text wb_layouts` and asks Widgets, by `say`, to do things (`text wl_name <name>` then `emit wl_save`, `emit wl_load <id>`…).
--
-- Snapshot it understands (compact bridge form or the full `wl_snapshot`; `updated` / `snap` are never needed):
--   { v, rev, ready, state, writable, max, count, current, base, layouts = [ { id, name, cards, outputs } ],
--     status = { seq, ok, code, msg } }
local B = {}

B.VISIBLE = 5            -- rows drawn at once (the scene's model is `max 5`)
B.MAX = 24               -- layouts Widgets keeps
B.MAX_NAME = 32          -- characters (Widgets cuts longer names itself)
B.MAX_WIRE = 8192        -- bytes of snapshot text this side will parse
B.ARM_MS = 4000          -- how long "press again to confirm" lasts
B.BUSY_MS = 1800         -- how long buttons wait for Widgets to answer
B.BASELINE_MS = 1500     -- the snapshot Widgets resends when the bar opens is old news, not a new status

local function is_int(v, lo, hi)
    return type(v) == "number" and v == v and v == math.floor(v) and v >= lo and v <= hi
end
local function int_or(v, lo, hi, d) if is_int(v, lo, hi) then return v end return d end

-- Same cleaning Widgets applies to a name (control characters → spaces, runs collapse, trimmed, cut at MAX_NAME).
function B.clean(s)
    if type(s) ~= "string" then return nil end
    s = s:gsub("%c", " "):gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "")
    local n = utf8.len(s)
    if not n then return nil end
    if n > B.MAX_NAME then s = s:sub(1, utf8.offset(s, B.MAX_NAME + 1) - 1):gsub(" $", "") end
    if s == "" then return nil end
    return s
end
local function key(s) return s:lower() end

local function cut(s, n)
    if utf8.len(s) and utf8.len(s) > n then return s:sub(1, utf8.offset(s, n + 1) - 1) end
    return s
end

-- text → view of the snapshot, or nil when it cannot be trusted.
function B.parse(text, json)
    if type(text) ~= "string" or text == "" or #text > B.MAX_WIRE then return nil end
    local ok, d = pcall(json.decode, text)
    if not ok or type(d) ~= "table" or type(d.layouts) ~= "table" then return nil end
    local list, seen = {}, {}
    for _, l in ipairs(d.layouts) do
        if #list >= B.MAX then break end
        if type(l) == "table" and l.id == nil and #l == 4 then l = { id = l[1], name = l[2], cards = l[3], outputs = l[4] } end
        if type(l) == "table" and is_int(l.id, 1, 2147483647) and not seen[l.id] and type(l.name) == "string" then
            local nm = B.clean(l.name)
            if nm then
                seen[l.id] = true
                list[#list + 1] = { id = l.id, name = nm, cards = int_or(l.cards, 0, 1000, 0), outputs = int_or(l.outputs, 0, 1000, 0) }
            end
        end
    end
    local st = type(d.status) == "table" and d.status or {}
    return {
        rev = int_or(d.rev, 0, 2147483647, 0),
        ready = d.ready == true,
        state = type(d.state) == "string" and d.state or "loading",
        writable = d.writable == true,
        max = int_or(d.max, 1, 1000, B.MAX),
        count = int_or(d.count, 0, 1000, #list),
        current = int_or(d.current, 0, 2147483647, 0),
        base = int_or(d.base, 0, 2147483647, 0),
        layouts = list,
        status = { seq = int_or(st.seq, 0, 2147483647, 0), ok = st.ok ~= false,
            code = type(st.code) == "string" and st.code or "", msg = type(st.msg) == "string" and cut(st.msg, 240) or "" },
    }
end

local function plural(n, one, many) return n .. " " .. (n == 1 and one or many) end
local function meta(l)
    if l.cards == 0 then return "empty" end
    local m = plural(l.cards, "widget", "widgets")
    if l.outputs > 1 then m = m .. " · " .. plural(l.outputs, "display", "displays") end
    return m
end

local READ_ONLY = {
    newer = "Read-only: saved by a newer Beskar",
    too_large = "Read-only: the layouts file is too large",
    unreadable = "Read-only: the layouts file cannot be read",
    corrupt = "Read-only: the layouts file needs fixing",
}

-- host = { json, say(words) → bool, after(ms, fn), publish(view), clear_name(), page_changed(page) (optional) }
function B.controller(host)
    local c = {}
    local snap = nil
    local page, name = 0, ""
    local sel_id, top = 0, 0
    local arm = { kind = 0, id = 0, token = 0 }   -- 1 update the selected · 2 delete the selected · 3 overwrite the named one
    local status = { ok = true, msg = "" }
    local last_seq, baseline, baseline_token = 0, false, 0
    local busy, busy_token = false, 0
    local pending = nil       -- what was asked and is waiting for Widgets' status: { op, name, index }
    local last_sig = nil

    local function layouts() return snap and snap.layouts or {} end
    local function index_of(id)
        for i, l in ipairs(layouts()) do if l.id == id then return i end end
    end
    local function by_name(nm, except)
        if not nm then return nil end
        local k = key(nm)
        for _, l in ipairs(layouts()) do
            if l.id ~= except and key(l.name) == k then return l end
        end
    end
    local function clamp_top()
        top = math.max(0, math.min(top, math.max(0, #layouts() - B.VISIBLE)))
    end
    -- bring the selected row into the window (after the selection changes, never after a wheel turn)
    local function reveal()
        local i = index_of(sel_id)
        if i then
            if i - 1 < top then top = i - 1 elseif i > top + B.VISIBLE then top = i - B.VISIBLE end
        end
        clamp_top()
    end

    -- ── the view ──
    local function build()
        local list = layouts()
        local n = #list
        clamp_top()
        local ready = snap ~= nil and snap.ready
        local writable = ready and snap.writable
        local clean = B.clean(name)
        local named = by_name(clean)
        local sel = index_of(sel_id) and list[index_of(sel_id)] or nil
        local free = busy == false
        local full = snap ~= nil and n >= snap.max
        local rows = {}
        for i = top + 1, math.min(n, top + B.VISIBLE) do
            local l = list[i]
            local tag = ""
            if snap.current == l.id then tag = "Current" elseif snap.base == l.id and snap.current ~= l.id then tag = "Edited" end
            rows[#rows + 1] = { id = l.id, name = l.name, meta = meta(l), tag = tag, sel = l.id == sel_id }
        end
        local v = {
            page = page, rows = rows, total = n, top = top, sel_id = sel and sel.id or 0, has_sel = sel ~= nil,
            arm = arm.kind, exists = named ~= nil, has_name = clean ~= nil, ready = ready and true or false,
            can_save = writable and clean ~= nil and free and (named ~= nil or not full) or false,
            can_load = ready and sel ~= nil and free or false,
            can_rename = writable and sel ~= nil and clean ~= nil and free and not by_name(clean, sel and sel.id) or false,
            can_duplicate = writable and sel ~= nil and free and not full or false,
            can_update = writable and sel ~= nil and free or false,
            can_delete = writable and sel ~= nil and free or false,
            status = status.msg, status_ok = status.ok,
        }
        -- the range under the list
        if not snap then v.range = ""
        elseif n == 0 then v.range = "No saved desktops yet"
        elseif n <= B.VISIBLE then v.range = n .. " of " .. snap.max
        else v.range = (top + 1) .. "–" .. math.min(n, top + B.VISIBLE) .. " of " .. n end
        if snap and snap.count > n then v.range = v.range .. " · " .. (snap.count - n) .. " not shown" end
        -- one hint line: why something is unavailable, or what Enter will do
        local hint
        if not snap then hint = "Waiting for the widgets…"
        elseif not ready then hint = "Loading saved desktops…"
        elseif not snap.writable then hint = READ_ONLY[snap.state] or "Read-only until the layouts file is fixed"
        elseif arm.kind == 1 and sel then hint = "Press Update again to replace “" .. sel.name .. "” with this desktop"
        elseif arm.kind == 2 and sel then hint = "Press Delete again to remove “" .. sel.name .. "”"
        elseif arm.kind == 3 and named then hint = "Press Save again to replace “" .. named.name .. "”"
        elseif clean and named then hint = "“" .. named.name .. "” exists: Save replaces it after a second press"
        elseif clean and full then hint = "You can keep " .. snap.max .. " desktops: delete one first"
        elseif clean then hint = "Enter saves this desktop as “" .. clean .. "”"
        elseif sel then hint = "Enter loads “" .. sel.name .. "”; type a name to save instead"
        else hint = "Type a name and press Enter to save this desktop" end
        v.hint = hint
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

    -- ── arm / busy ──
    local function disarm()
        if arm.kind ~= 0 then arm.kind, arm.id = 0, 0; arm.token = arm.token + 1 end
    end
    local function arm_for(kind, id)
        arm.kind, arm.id = kind, id
        arm.token = arm.token + 1
        local tk = arm.token
        host.after(B.ARM_MS, function()
            if arm.token == tk and arm.kind ~= 0 then arm.kind, arm.id = 0, 0; publish() end
        end)
    end
    local function set_busy()
        busy = true
        busy_token = busy_token + 1
        local tk = busy_token
        host.after(B.BUSY_MS, function()
            if busy and busy_token == tk then busy = false; publish() end
        end)
    end
    local function local_status(ok, msg) status = { ok = ok, msg = msg } end

    -- Ask Widgets. `texts` goes first (the name travels in `text wl_name`), then the event; both or nothing.
    local function ask(event, id, with_name, op)
        if with_name then
            if not host.say("text wl_name " .. with_name) then
                local_status(false, "Could not reach the widgets"); publish(); return false
            end
        end
        if not host.say("emit " .. event .. (id and (" " .. id) or "")) then
            local_status(false, "Could not reach the widgets"); publish(); return false
        end
        pending = op
        set_busy()
        return true
    end

    -- ── incoming snapshot ──
    function c.snapshot(body)
        local s = B.parse(body, host.json)
        if not s then
            local_status(false, "Could not read the saved desktops")
            publish()
            return
        end
        local old_ids = {}
        for _, l in ipairs(layouts()) do old_ids[l.id] = true end
        local old_index = index_of(sel_id)
        snap = s
        local seq = s.status.seq
        if baseline then
            last_seq = seq
            baseline = false
            if sel_id == 0 and s.current ~= 0 then sel_id = s.current end   -- opened before the first snapshot
        elseif seq ~= last_seq then
            last_seq = seq
            busy = false
            busy_token = busy_token + 1
            if s.status.msg ~= "" then local_status(s.status.ok, s.status.msg) end
            local p = pending
            pending = nil
            if p and s.status.ok then
                if p.op == "save" or p.op == "rename" then
                    local hit = by_name(p.name)
                    if hit then sel_id = hit.id end
                    name = ""
                    host.clear_name()
                    disarm()
                elseif p.op == "duplicate" then
                    for _, l in ipairs(s.layouts) do
                        if not old_ids[l.id] then sel_id = l.id; break end
                    end
                end
            end
            if p and p.op == "delete" and s.status.ok then disarm() end
        end
        -- the selected layout vanished (deleted here or elsewhere): the neighbour takes its place
        if sel_id ~= 0 and not index_of(sel_id) then
            local n = #s.layouts
            sel_id = n > 0 and s.layouts[math.max(1, math.min(old_index or 1, n))].id or 0
            disarm()
        end
        reveal()
        publish()
    end

    -- ── the bar ──
    function c.opened()
        page, name = 0, ""
        top = 0
        disarm()
        busy, pending = false, nil
        status = { ok = true, msg = "" }
        host.clear_name()
        sel_id = snap and snap.current or 0
        reveal()
        baseline = true
        baseline_token = baseline_token + 1
        local tk = baseline_token
        host.after(B.BASELINE_MS, function() if baseline_token == tk then baseline = false end end)
        publish()
    end
    function c.closed()
        page, name = 0, ""
        disarm()
        busy, pending = false, nil
        status = { ok = true, msg = "" }
        host.clear_name()
        publish()
    end

    function c.tab(n)
        n = (n == 1) and 1 or 0
        if n == page then publish(); return end
        page = n
        disarm()
        if page == 1 and (not snap or not snap.ready) then host.say("emit wl_list") end
        if host.page_changed then host.page_changed(page) end
        publish()
    end

    function c.set_name(s)
        s = type(s) == "string" and s or ""
        if s == name then return end
        name = s
        if arm.kind == 3 then
            local still = by_name(B.clean(name))
            if not (still and still.id == arm.id) then disarm() end
        end
        publish()
    end

    -- ── list ──
    function c.pick(id)
        id = math.floor(tonumber(id) or 0)
        if not index_of(id) then return end
        if id ~= sel_id then disarm() end
        sel_id = id
        reveal()
        publish()
    end
    function c.move(delta)
        local list = layouts()
        local n = #list
        if n == 0 then return end
        delta = math.floor(tonumber(delta) or 0)
        local i = index_of(sel_id)
        if not i then i = delta > 0 and 0 or n + 1 end
        i = math.max(1, math.min(n, i + delta))
        if list[i].id ~= sel_id then disarm() end
        sel_id = list[i].id
        reveal()
        publish()
    end
    function c.page(dir) c.move((dir < 0 and -1 or 1) * B.VISIBLE) end
    function c.scroll(wheel)
        top = top + ((tonumber(wheel) or 0) > 0 and -1 or 1)
        clamp_top()
        publish()
    end

    -- ── actions ──
    local function selected()
        local i = index_of(sel_id)
        return i and layouts()[i] or nil
    end
    local function writable()
        if not snap or not snap.ready then local_status(false, "Saved desktops are still loading"); publish(); return false end
        if not snap.writable then local_status(false, READ_ONLY[snap.state] or "Saved desktops are read-only"); publish(); return false end
        return true
    end

    function c.save()
        if busy then return end
        if not writable() then return end
        local clean = B.clean(name)
        if not clean then local_status(false, "Give the desktop a name first"); publish(); return end
        local named = by_name(clean)
        if named then
            if not (arm.kind == 3 and arm.id == named.id) then
                arm_for(3, named.id)
                local_status(true, "")
                publish()
                return
            end
        elseif #layouts() >= snap.max then
            local_status(false, "You can keep " .. snap.max .. " desktops: delete one first"); publish(); return
        end
        disarm()
        ask("wl_save", nil, clean, { op = "save", name = clean })
        publish()
    end

    function c.load()
        if busy then return end
        if not snap or not snap.ready then local_status(false, "Saved desktops are still loading"); publish(); return end
        local sel = selected()
        if not sel then local_status(false, "Select a saved desktop first"); publish(); return end
        disarm()
        ask("wl_load", sel.id, nil, { op = "load" })
        publish()
    end

    function c.rename()
        if busy then return end
        if not writable() then return end
        local sel = selected()
        if not sel then local_status(false, "Select a saved desktop first"); publish(); return end
        local clean = B.clean(name)
        if not clean then local_status(false, "Type the new name first"); publish(); return end
        if by_name(clean, sel.id) then local_status(false, "A desktop with that name exists"); publish(); return end
        disarm()
        ask("wl_rename", sel.id, clean, { op = "rename", name = clean })
        publish()
    end

    function c.duplicate()
        if busy then return end
        if not writable() then return end
        local sel = selected()
        if not sel then local_status(false, "Select a saved desktop first"); publish(); return end
        if #layouts() >= snap.max then local_status(false, "You can keep " .. snap.max .. " desktops: delete one first"); publish(); return end
        disarm()
        ask("wl_duplicate", sel.id, nil, { op = "duplicate" })
        publish()
    end

    function c.update()
        if busy then return end
        if not writable() then return end
        local sel = selected()
        if not sel then local_status(false, "Select a saved desktop first"); publish(); return end
        if not (arm.kind == 1 and arm.id == sel.id) then
            arm_for(1, sel.id)
            local_status(true, "")
            publish()
            return
        end
        disarm()
        ask("wl_update", sel.id, nil, { op = "update" })
        publish()
    end

    function c.delete()
        if busy then return end
        if not writable() then return end
        local sel = selected()
        if not sel then local_status(false, "Select a saved desktop first"); publish(); return end
        if not (arm.kind == 2 and arm.id == sel.id) then
            arm_for(2, sel.id)
            local_status(true, "")
            publish()
            return
        end
        disarm()
        ask("wl_delete", sel.id, nil, { op = "delete", index = index_of(sel.id) })
        publish()
    end

    -- Enter in the name field: save when a name is typed, otherwise load the selected desktop.
    function c.submit()
        if B.clean(name) then c.save()
        elseif selected() then c.load()
        else local_status(false, "Type a name to save this desktop"); publish() end
    end

    -- Esc: a pending confirmation is cancelled first; true = consumed (the bar stays open).
    function c.escape()
        if arm.kind ~= 0 then disarm(); local_status(true, ""); publish(); return true end
        return false
    end

    function c.view() return build() end
    return c
end

return B
