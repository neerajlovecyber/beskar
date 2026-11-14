-- Named saved widget desktops (C4a). Pure logic: no globals, no scene access, so tests/widget-layouts.lua runs it
-- with a fake host. widgets.luau is the ONLY writer of ~/.config/beskar/widget-layouts.json and talks to this
-- module through `L.controller(host)`.
--
-- File (version 2), bounded: at most MAX_LAYOUTS layouts of at most MAX_CARDS cards, MAX_BYTES in all.
--   { version = 1, next_id = N, layouts = [ { id, name, created, updated, snap, areas = { NAME = { w, h } },
--                                             cards = [ { id, out, kind, sz, x, y, opts?, stack? } ] } ] }
-- A stacked card (C4c) also has `stack = { id, i, on? }`: stack id (per layout), page order, `on` on the shown face
-- (shell/widget_stacks.luau). Such a file is written as version 3, which an older Beskar refuses to overwrite (it reads
-- "newer" and keeps the file as it is); a layout set without stacks is still written as version 2.
-- Version 1 (before per-card options) is read as it is: its cards simply have no `opts`. Saving writes version 2, so
-- a Beskar that does not know `opts` refuses to overwrite the file instead of silently dropping them.
-- A layout holds PLACEMENT only: ids, kinds, sizes, positions, output names, the grid option and each card's own
-- options (position lock, clock date / seconds / format: shell/widget_options.luau). Never notes, to-dos,
-- timer deadlines or weather: those belong to Personal / Activities / Weather and a layout never touches them.
local Opts = require("widget_options")
local Stacks = require("widget_stacks")
local L = {}

L.VERSION = 3            -- the newest file this build reads (3 = stacks, C4c)
L.BASE_VERSION = 2       -- what a file WITHOUT stacked cards is still written as (an older Beskar keeps reading it)
L.SNAPSHOT_VERSION = 1   -- what the widget bar's snapshot says (`v`); independent of the file version
L.MAX_LAYOUTS = 24
L.MAX_CARDS = 16
L.MAX_NAME = 32          -- characters
L.MAX_NAME_BYTES = 96
L.MAX_BYTES = 100000     -- the whole file, in and out
L.MAX_COORD = 100000
L.MAX_OUT = 64

local function copy(v)
    if type(v) ~= "table" then return v end
    local t = {}
    for k, x in pairs(v) do t[k] = copy(x) end
    return t
end
L.copy = copy

-- IPC rows use positional fields [id, name, cards, outputs] so 24 UTF-8 names fit
-- the 4096-byte command limit without truncating display names. The full CLI snapshot is unchanged.
function L.bar_snapshot(snap)
    local bridge = {}
    for key, value in pairs(snap) do bridge[key] = value end
    local rows = {}
    for _, row in ipairs(snap.layouts or {}) do rows[#rows + 1] = { row.id, row.name, row.cards, row.outputs } end
    bridge.layouts = rows
    return bridge
end

local function is_int(v, lo, hi)
    return type(v) == "number" and v == v and v == math.floor(v) and v >= lo and v <= hi
end
local function is_num(v)
    return type(v) == "number" and v == v and v >= -L.MAX_COORD and v <= L.MAX_COORD
end
local function round(v) return math.floor(v + 0.5) end

local function is_array(t)
    if type(t) ~= "table" then return false end
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n == #t
end

-- ── names ──
-- Control characters become spaces, runs of spaces collapse, the ends are trimmed, long names are cut at
-- MAX_NAME characters. Returns the name, or nil and a status code.
function L.clean_name(s)
    if type(s) ~= "string" then return nil, "name_empty" end
    s = s:gsub("%c", " "):gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "")
    local n = utf8.len(s)
    if not n then return nil, "name_invalid" end
    if n > L.MAX_NAME then
        s = s:sub(1, utf8.offset(s, L.MAX_NAME + 1) - 1)
    end
    while #s > L.MAX_NAME_BYTES do
        s = s:sub(1, (utf8.offset(s, -1) or 1) - 1)
    end
    s = s:gsub(" $", "")
    if s == "" then return nil, "name_empty" end
    return s
end
local function name_key(s) return s:lower() end

-- ── cards ──
local function norm_card(c)
    if type(c) ~= "table" then return nil end
    if not is_int(c.id, 1, 2147483647) then return nil end
    if type(c.out) ~= "string" or #c.out < 1 or #c.out > L.MAX_OUT or c.out:find("%c") then return nil end
    if not is_int(c.kind, 1, 1000) or not is_int(c.sz, 0, 2) then return nil end
    if not is_num(c.x) or not is_num(c.y) then return nil end
    return { id = c.id, out = c.out, kind = c.kind, sz = c.sz, x = round(c.x), y = round(c.y), opts = Opts.clean(c.kind, c.opts),
        stack = Stacks.clean(c.stack) }
end

local function norm_areas(a)
    local out, n = {}, 0
    if type(a) ~= "table" then return out end
    for name, v in pairs(a) do
        if n < 8 and type(name) == "string" and #name >= 1 and #name <= L.MAX_OUT and not name:find("%c")
            and type(v) == "table" and is_int(v.w, 1, 20000) and is_int(v.h, 1, 20000) then
            out[name] = { w = v.w, h = v.h }
            n = n + 1
        end
    end
    return out
end

-- One stored layout; nil and a reason when it cannot be trusted.
local function norm_layout(r)
    if type(r) ~= "table" then return nil, "not a table" end
    if not is_int(r.id, 1, 2147483647) then return nil, "bad id" end
    local name = L.clean_name(r.name)
    if not name then return nil, "bad name" end
    if not is_array(r.cards) then return nil, "bad cards" end
    if #r.cards > L.MAX_CARDS then return nil, "more than " .. L.MAX_CARDS .. " cards" end
    local cards, seen = {}, {}
    for i, c in ipairs(r.cards) do
        local n = norm_card(c)
        if not n then return nil, "bad card " .. i end
        if seen[n.id] then return nil, "duplicate card id " .. n.id end
        seen[n.id] = true
        cards[#cards + 1] = n
    end
    Stacks.normalize(cards)         -- structure only (kinds are not known here); `restore` also checks sizes
    local created = is_int(r.created, 0, 4102444800) and r.created or 0
    local updated = is_int(r.updated, 0, 4102444800) and r.updated or created
    return { id = r.id, name = name, created = created, updated = updated, snap = r.snap ~= false,
        areas = norm_areas(r.areas), cards = cards }
end

-- ── the store ──
function L.new_store() return { version = L.VERSION, next_id = 1, layouts = {} } end

function L.find(store, id)
    for i, l in ipairs(store.layouts) do
        if l.id == id then return l, i end
    end
end
local function find_name(store, key, except)
    for _, l in ipairs(store.layouts) do
        if l.id ~= except and name_key(l.name) == key then return l end
    end
end

-- text → store. On failure: nil, code ("corrupt" | "newer" | "too_large"), message. A readable file with some
-- unusable layouts still loads: the usable ones come back and `report.dropped` counts the rest (the caller keeps a
-- copy of the file before it ever overwrites it).
function L.decode(text, json)
    if type(text) ~= "string" then return nil, "corrupt", "no text" end
    if #text > L.MAX_BYTES then return nil, "too_large", "file is larger than " .. L.MAX_BYTES .. " bytes" end
    local ok, d = pcall(json.decode, text)
    if not ok or type(d) ~= "table" then return nil, "corrupt", "not valid JSON" end
    if not is_int(d.version, 1, 1000000) then return nil, "corrupt", "no version" end
    if d.version > L.VERSION then return nil, "newer", "saved by a newer Beskar (version " .. d.version .. ")" end
    local raw = d.layouts == nil and {} or d.layouts
    if not is_array(raw) then return nil, "corrupt", "layouts is not a list" end
    local store = L.new_store()
    local report = { dropped = 0, reasons = {} }
    local ids, names = {}, {}
    local function drop(why)
        report.dropped = report.dropped + 1
        if #report.reasons < 3 then report.reasons[#report.reasons + 1] = why end
    end
    local max_id = 0
    for _, r in ipairs(raw) do
        local l, why = norm_layout(r)
        if not l then drop(why)
        elseif ids[l.id] then drop("duplicate layout id " .. l.id)
        elseif names[name_key(l.name)] then drop("duplicate name " .. l.name)
        elseif #store.layouts >= L.MAX_LAYOUTS then drop("more than " .. L.MAX_LAYOUTS .. " layouts")
        else
            ids[l.id], names[name_key(l.name)] = true, true
            store.layouts[#store.layouts + 1] = l
            if l.id > max_id then max_id = l.id end
        end
    end
    -- the highest id of anything the file named, so a dropped layout's id is never reused by accident
    for _, r in ipairs(raw) do
        if type(r) == "table" and is_int(r.id, 1, 2147483647) and r.id > max_id then max_id = r.id end
    end
    store.next_id = (is_int(d.next_id, 1, 2147483647) and d.next_id > max_id) and d.next_id or (max_id + 1)
    return store, report
end

-- store → text, or nil and a code.
function L.encode(store, json)
    local layouts, version = {}, L.BASE_VERSION
    for _, l in ipairs(store.layouts) do
        local cards = {}
        for _, c in ipairs(l.cards) do
            cards[#cards + 1] = { id = c.id, out = c.out, kind = c.kind, sz = c.sz, x = c.x, y = c.y, opts = copy(c.opts),
                stack = Stacks.copy(c.stack) }
            if c.stack then version = L.VERSION end
        end
        layouts[#layouts + 1] = { id = l.id, name = l.name, created = l.created, updated = l.updated,
            snap = l.snap and true or false, areas = copy(l.areas or {}), cards = cards }
    end
    local ok, text = pcall(json.encode, { version = version, next_id = store.next_id, layouts = layouts })
    if not ok or type(text) ~= "string" then return nil, "io" end
    if #text > L.MAX_BYTES then return nil, "too_large" end
    return text
end

-- ── capture: the live desktop → a layout body ──
-- cards: the live list (hidden cards on disconnected outputs included). Ids that are not usable or repeat get a fresh
-- one inside the layout; cards without a usable output / kind / size are left out and counted.
function L.capture(cards, snap, sizes)
    if type(cards) ~= "table" then return nil, "not_ready" end
    if #cards > L.MAX_CARDS then return nil, "too_many_cards" end
    local out, used, skipped, loose, outs = {}, {}, 0, {}, {}
    for _, c in ipairs(cards) do
        local fixed = type(c) == "table" and copy(c) or nil
        if fixed then fixed.id = is_int(fixed.id, 1, 2147483647) and fixed.id or 1 end
        local n = fixed and norm_card(fixed)
        if not n then skipped = skipped + 1
        else
            if is_int(c.id, 1, 2147483647) and not used[c.id] then used[c.id] = true
            else loose[#loose + 1] = n end
            out[#out + 1] = n
            outs[n.out] = true
        end
    end
    local nextid = 1
    for _, n in ipairs(loose) do
        while used[nextid] do nextid = nextid + 1 end
        n.id = nextid
        used[nextid] = true
    end
    Stacks.normalize(out)
    local areas = {}
    for name in pairs(outs) do
        local s = sizes and sizes[name]
        if s and is_int(s[1], 1, 20000) and is_int(s[2], 1, 20000) then areas[name] = { w = s[1], h = s[2] } end
    end
    return { snap = snap ~= false, cards = out, areas = norm_areas(areas) }, skipped
end

-- Position-kind-options signature that ignores ids: tells whether the live desktop still IS a layout.
function L.signature(cards)
    local parts = {}
    for _, c in ipairs(cards or {}) do
        local o = Opts.sig(c.opts)
        parts[#parts + 1] = string.format("%s|%d|%d|%d|%d", tostring(c.out), c.kind or 0, c.sz or 0, round(c.x or 0), round(c.y or 0))
            .. (o ~= "" and ("|" .. o) or "") .. (c.stack and ("|" .. Stacks.sig(c)) or "")
    end
    table.sort(parts)
    return table.concat(parts, ";")
end

-- ── restore: a layout → cards for the connected outputs ──
-- ctx = { connected = { NAME = true }, sizes = { NAME = { w, h } }, kind_of = fn(id), limit = 16,
--         geom = { unit, gap, top, side, bottom, ox, oy, def_w, def_h } }
-- The stored layout is never changed. Cards on an output that is not connected come back as they were stored
-- (they stay in the live list, hidden, and show again when the output returns). Cards on a connected output are
-- clamped into its work area; a card that had to move and now collides is put on the nearest free grid cell.
local function nearest_allowed(k, sz)
    local best, gap = k.def or k.sizes[1], 99
    for _, s in ipairs(k.sizes) do
        if s == sz then return s, false end
        if math.abs(s - sz) < gap then best, gap = s, math.abs(s - sz) end
    end
    return best, true
end

local function reflow(list, size, g, rep)
    local pitch = g.unit + g.gap
    local function wh(c) return (c.sz == 0 and g.unit or (g.unit * 2 + g.gap)), (c.sz == 2 and (g.unit * 2 + g.gap) or g.unit) end
    local W, H = size and size[1] or g.def_w, size and size[2] or g.def_h
    local function lim(c)
        local w, h = wh(c)
        return W - w - g.side, H - h - g.side - g.bottom
    end
    local fixed, moved = {}, {}
    for _, c in ipairs(list) do
        local maxx, maxy = lim(c)
        local nx = math.max(g.side, math.min(c.x, maxx))
        local ny = math.max(g.top, math.min(c.y, maxy))
        if nx ~= c.x or ny ~= c.y then
            c.x, c.y = nx, ny
            moved[#moved + 1] = c
            if maxx < g.side or maxy < g.top then rep.crowded = rep.crowded + 1 end
        else
            fixed[#fixed + 1] = c
        end
    end
    local placed = {}
    for _, c in ipairs(fixed) do placed[#placed + 1] = c end
    local function hits(c, x, y, pad)
        local w, h = wh(c)
        for _, o in ipairs(placed) do
            local ow, oh = wh(o)
            if x - pad < o.x + ow and x + w + pad > o.x and y - pad < o.y + oh and y + h + pad > o.y then return true end
        end
        return false
    end
    table.sort(moved, function(a, b)
        if a.y ~= b.y then return a.y < b.y end
        if a.x ~= b.x then return a.x < b.x end
        return a.id < b.id
    end)
    for _, c in ipairs(moved) do
        rep.moved = rep.moved + 1
        if hits(c, c.x, c.y, 0) then
            local maxx, maxy = lim(c)
            local cols = math.max(0, math.floor((maxx - g.ox) / pitch))
            local rows = math.max(0, math.floor((maxy - g.oy) / pitch))
            local found
            for _, pad in ipairs({ g.gap / 2, 0 }) do
                local best
                for r = 0, rows do
                    for q = 0, cols do
                        local x, y = g.ox + q * pitch, g.oy + r * pitch
                        if not hits(c, x, y, pad) then
                            local d = (x - c.x) ^ 2 + (y - c.y) ^ 2
                            if not best or d < best.d then best = { d = d, x = x, y = y } end
                        end
                    end
                end
                if best then found = best; break end
            end
            if found then c.x, c.y = found.x, found.y else rep.crowded = rep.crowded + 1 end
        end
        placed[#placed + 1] = c
    end
end

function L.restore(layout, ctx)
    local g = ctx.geom
    local rep = { skipped = 0, adjusted = 0, moved = 0, crowded = 0, hidden = 0, total = 0 }
    local cards, by_out, order = {}, {}, {}
    for _, c in ipairs(layout.cards) do
        if not ctx.kind_of(c.kind) or #cards >= (ctx.limit or L.MAX_CARDS) then
            rep.skipped = rep.skipped + 1
        else
            cards[#cards + 1] = copy(c)
        end
    end
    -- A stack is ONE footprint: it is resized as a whole (a size every member draws, the nearest to the stored one),
    -- and members that no longer fit it (a kind that is gone, a size nobody shares) leave the stack where they stand.
    Stacks.normalize(cards, ctx.kind_of)
    local done = {}
    for _, n in ipairs(cards) do
        if n.stack then
            if not done[n.stack.id] then
                done[n.stack.id] = true
                local face = Stacks.active(cards, n)
                local sizes = Stacks.sizes(cards, face, ctx.kind_of)
                if #sizes > 0 then
                    local sz, changed = nearest_allowed({ sizes = sizes, def = sizes[1] }, face.sz)
                    if changed then
                        for _, m in ipairs(Stacks.members(cards, face)) do m.sz = sz; rep.adjusted = rep.adjusted + 1 end
                    end
                end
            end
        else
            local sz, changed = nearest_allowed(ctx.kind_of(n.kind), n.sz)
            if changed then n.sz = sz; rep.adjusted = rep.adjusted + 1 end
        end
    end
    -- Only the shown face of a stack takes part in the reflow (its members follow it afterwards): they share a
    -- footprint, so laying them out one by one would push them apart.
    local faces = {}
    for _, n in ipairs(cards) do
        if not Stacks.hidden(n) then
            if ctx.connected[n.out] then
                if not by_out[n.out] then by_out[n.out] = {}; order[#order + 1] = n.out end
                table.insert(by_out[n.out], n)
                if n.stack then faces[#faces + 1] = n end
            end
        end
        if not ctx.connected[n.out] then rep.hidden = rep.hidden + 1 end
    end
    for _, out in ipairs(order) do
        local s = ctx.sizes and ctx.sizes[out]
        reflow(by_out[out], s and { s[1] or s.w, s[2] or s.h } or nil, g, rep)
    end
    for _, face in ipairs(faces) do Stacks.sync(cards, face) end
    rep.total = #cards
    return cards, rep
end

-- ── snapshot (what the widget bar reads) ──
local function describe(l)
    local outs, n = {}, 0
    for _, c in ipairs(l.cards) do
        if not outs[c.out] then outs[c.out] = true; n = n + 1 end
    end
    return { id = l.id, name = l.name, cards = #l.cards, outputs = n, snap = l.snap and true or false, updated = l.updated }
end
L.describe = describe

-- ── the controller ──
-- host = {
--   json = { encode, decode },  now = fn() → epoch seconds,
--   read = fn(cb)       cb(kind, text)   kind "ok" | "missing" | "toolarge" | "error"
--   write = fn(text, cb)  cb(ok)         atomic replace of the file
--   backup = fn(cb)     cb(ok)           keep a copy of the file as it is now (before a recovery overwrites it)
--   ready = fn() → bool                  the live desktop is loaded
--   capture = fn() → { cards, snap, sizes }
--   context = fn() → { connected, sizes, kind_of, geom }
--   apply = fn(cards, snap)              puts a restored desktop in place and records the undo step
--   cards = fn() → live cards (for `current`)
--   publish = fn(snapshot_table, snapshot_json, status)   called whenever the snapshot changes
-- }
-- Everything that changes state runs one at a time on a queue; an operation that writes changes the in-memory
-- store only after the write succeeded, so a failed write leaves memory and disk the same and says why.
local MESSAGES = {
    saved = "Saved “%s”", updated = "Updated “%s”", loaded = "Loaded “%s”", renamed = "Renamed to “%s”",
    duplicated = "Created “%s”", deleted = "Deleted “%s”", refreshed = "Layouts refreshed",
}
local ERRORS = {
    name_empty = "Give the layout a name", name_invalid = "That name is not valid text", name_taken = "A layout with that name exists",
    limit = "You can keep " .. L.MAX_LAYOUTS .. " layouts: delete one first", not_found = "That layout no longer exists",
    not_ready = "Widgets are still starting", read_only = "Layouts are read-only until the saved file is fixed",
    io = "Could not write the layouts file", too_large = "Layouts file would be too large",
    too_many_cards = "The desktop has more than " .. L.MAX_CARDS .. " cards", unusable = "Nothing in that layout can be shown",
}

function L.controller(host)
    local ctl = {}
    local store = L.new_store()
    local state, state_msg = "loading", ""   -- loading | ok | corrupt | newer | unreadable | too_large
    local writable = false
    local rev, last_sig = 0, ""
    local status = { seq = 0, ok = true, code = "", msg = "" }
    local base_id, base_sig = 0, nil
    local queue, running = {}, false

    local function current_id()
        if base_id == 0 or base_sig == nil then return 0 end
        local sig = L.signature(host.cards())
        return sig == base_sig and base_id or 0
    end

    local function snapshot_table()
        local list = {}
        for i, l in ipairs(store.layouts) do list[i] = describe(l) end
        return { v = L.SNAPSHOT_VERSION, rev = rev, ready = state ~= "loading", state = state, writable = writable, max = L.MAX_LAYOUTS,
            count = #list, current = current_id(), base = base_id, layouts = list,
            status = { seq = status.seq, ok = status.ok, code = status.code, msg = status.msg } }
    end

    local function publish()
        local snap = snapshot_table()
        snap.rev = 0
        local ok, sig = pcall(host.json.encode, snap)
        if not ok then return end
        if sig ~= last_sig then
            -- the revision is part of the text; compare without it, so an unchanged state never republishes
            last_sig = sig
            rev = rev + 1
            snap.rev = rev
            local ok2, text = pcall(host.json.encode, snap)
            if ok2 then host.publish(snap, text, snap.status) end
        end
    end

    local function say_status(ok, code, msg)
        status = { seq = status.seq + 1, ok = ok, code = code, msg = msg }
    end
    local function fail(code, extra)
        say_status(false, code, (ERRORS[code] or code) .. (extra and (": " .. extra) or ""))
        publish()
    end
    local function succeed(code, name, extra)
        say_status(true, code, string.format(MESSAGES[code] or code, name or "") .. (extra or ""))
        publish()
    end

    local function persist(next_store, cb)
        local text, why = L.encode(next_store, host.json)
        if not text then cb(false, why or "io"); return end
        host.write(text, function(ok)
            if ok then store = next_store end
            cb(ok, ok and nil or "io")
        end)
    end

    local function next_job()
        if running then return end
        local job = table.remove(queue, 1)
        if not job then return end
        running = true
        local done = false
        local function finish()
            if done then return end
            done = true
            running = false
            next_job()
        end
        local ok, err = pcall(job, finish)
        if not ok then
            fail("io", tostring(err))
            finish()
        end
    end
    local function enqueue(job)
        queue[#queue + 1] = job
        next_job()
    end

    local function need_write(finish)
        if writable then return true end
        fail("read_only", state_msg ~= "" and state_msg or nil)
        finish()
        return false
    end

    -- Read (or re-read) the file. Corrupt or partly unusable files are copied aside before anything can overwrite them.
    local function read_job(code_ok)
        return function(finish)
            host.read(function(kind, text)
                local function settle(s, w, msg)
                    state, writable, state_msg = s, w, msg or ""
                    if s == "ok" then
                        if code_ok then succeed("refreshed") else publish() end
                    else
                        say_status(false, s, "Layouts file: " .. (msg or s))
                        publish()
                    end
                    finish()
                end
                if kind == "missing" then
                    store = L.new_store()
                    return settle("ok", true)
                elseif kind == "toolarge" then
                    return settle("too_large", false, "file is too large")
                elseif kind ~= "ok" then
                    return settle("unreadable", false, "cannot be read")
                end
                local s, why, msg = L.decode(text, host.json)
                if not s then
                    if why == "newer" then return settle("newer", false, msg) end
                    if why == "too_large" then return settle("too_large", false, msg) end
                    store = L.new_store()
                    host.backup(function(saved)
                        if saved then settle("corrupt", true, msg .. "; a copy was kept")
                        else settle("corrupt", false, msg .. "; could not keep a copy") end
                    end)
                    return
                end
                store = s
                if why and why.dropped > 0 then
                    host.backup(function(saved)
                        local m = why.dropped .. " unusable layout(s) skipped" .. (why.reasons[1] and (" (" .. why.reasons[1] .. ")") or "")
                        if saved then
                            state, writable, state_msg = "ok", true, ""
                            say_status(true, "partial", m .. "; a copy of the file was kept")
                        else
                            state, writable, state_msg = "corrupt", false, m .. "; could not keep a copy"
                            say_status(false, "corrupt", "Layouts file: " .. state_msg)
                        end
                        publish()
                        finish()
                    end)
                    return
                end
                settle("ok", true)
            end)
        end
    end

    -- ── operations ──
    local function capture_live(finish)
        if not host.ready() then fail("not_ready"); finish(); return nil end
        local live = host.capture()
        local body, why = L.capture(live.cards, live.snap, live.sizes)
        if not body then fail(why or "not_ready"); finish(); return nil end
        return body, live
    end

    function ctl.start()
        publish()
        enqueue(read_job(false))
    end
    function ctl.refresh() enqueue(read_job(true)) end

    function ctl.save(name)
        enqueue(function(finish)
            if not need_write(finish) then return end
            local nm, why = L.clean_name(name)
            if not nm then fail(why); finish(); return end
            local body, live = capture_live(finish)
            if not body then return end
            local nxt, now = copy(store), host.now()
            local existing = find_name(nxt, name_key(nm))
            local id, code
            if existing then
                existing.name, existing.snap, existing.areas, existing.cards, existing.updated = nm, body.snap, body.areas, body.cards, now
                id, code = existing.id, "updated"
            else
                if #nxt.layouts >= L.MAX_LAYOUTS then fail("limit"); finish(); return end
                id = nxt.next_id
                nxt.next_id = id + 1
                nxt.layouts[#nxt.layouts + 1] = { id = id, name = nm, created = now, updated = now, snap = body.snap, areas = body.areas, cards = body.cards }
                code = "saved"
            end
            local sig = L.signature(live.cards)
            persist(nxt, function(ok, err)
                if ok then base_id, base_sig = id, sig; succeed(code, nm) else fail(err) end
                finish()
            end)
        end)
    end

    function ctl.update(id)
        enqueue(function(finish)
            if not need_write(finish) then return end
            if not L.find(store, id) then fail("not_found"); finish(); return end
            local body, live = capture_live(finish)
            if not body then return end
            local nxt = copy(store)
            local l = L.find(nxt, id)
            l.snap, l.areas, l.cards, l.updated = body.snap, body.areas, body.cards, host.now()
            local sig = L.signature(live.cards)
            persist(nxt, function(ok, err)
                if ok then base_id, base_sig = id, sig; succeed("updated", l.name) else fail(err) end
                finish()
            end)
        end)
    end

    function ctl.load(id)
        enqueue(function(finish)
            local l = L.find(store, id)
            if not l then fail("not_found"); finish(); return end
            if not host.ready() then fail("not_ready"); finish(); return end
            local cards, rep = L.restore(l, host.context())
            if #l.cards > 0 and #cards == 0 then fail("unusable"); finish(); return end
            host.apply(cards, l.snap)
            base_id, base_sig = id, L.signature(host.cards())
            local bits = {}
            if rep.skipped > 0 then bits[#bits + 1] = rep.skipped .. " unavailable widget(s) skipped" end
            if rep.adjusted > 0 then bits[#bits + 1] = rep.adjusted .. " resized to a supported size" end
            if rep.moved > 0 then bits[#bits + 1] = rep.moved .. " moved to fit" end
            if rep.crowded > 0 then bits[#bits + 1] = rep.crowded .. " could not fit" end
            if rep.hidden > 0 then bits[#bits + 1] = rep.hidden .. " kept for disconnected display(s)" end
            succeed("loaded", l.name, #bits > 0 and (" · " .. table.concat(bits, " · ")) or "")
            ctl.last_restore = rep
            finish()
        end)
    end

    function ctl.rename(id, name)
        enqueue(function(finish)
            if not need_write(finish) then return end
            local nm, why = L.clean_name(name)
            if not nm then fail(why); finish(); return end
            if not L.find(store, id) then fail("not_found"); finish(); return end
            if find_name(store, name_key(nm), id) then fail("name_taken"); finish(); return end
            local nxt = copy(store)
            local l = L.find(nxt, id)
            l.name, l.updated = nm, host.now()
            persist(nxt, function(ok, err)
                if ok then succeed("renamed", nm) else fail(err) end
                finish()
            end)
        end)
    end

    function ctl.duplicate(id)
        enqueue(function(finish)
            if not need_write(finish) then return end
            local src = L.find(store, id)
            if not src then fail("not_found"); finish(); return end
            if #store.layouts >= L.MAX_LAYOUTS then fail("limit"); finish(); return end
            local nxt, now = copy(store), host.now()
            -- "<name> copy", then "<name> copy 2"…; the base is cut so the whole name stays within the limit
            local nm
            for n = 1, L.MAX_LAYOUTS + 2 do
                local tail = n == 1 and " copy" or (" copy " .. n)
                local base = src.name
                local room = L.MAX_NAME - utf8.len(tail)
                if utf8.len(base) > room then base = base:sub(1, utf8.offset(base, room + 1) - 1) end
                local try = L.clean_name(base .. tail)
                if try and not find_name(nxt, name_key(try)) then nm = try; break end
            end
            if not nm then fail("name_taken"); finish(); return end
            local rec = copy(src)
            rec.id, rec.name, rec.created, rec.updated = nxt.next_id, nm, now, now
            nxt.next_id = nxt.next_id + 1
            nxt.layouts[#nxt.layouts + 1] = rec
            persist(nxt, function(ok, err)
                if ok then succeed("duplicated", nm) else fail(err) end
                finish()
            end)
        end)
    end

    function ctl.delete(id)
        enqueue(function(finish)
            if not need_write(finish) then return end
            local src = L.find(store, id)
            if not src then fail("not_found"); finish(); return end
            local nxt = copy(store)
            local _, i = L.find(nxt, id)
            table.remove(nxt.layouts, i)
            persist(nxt, function(ok, err)
                if ok then
                    if base_id == id then base_id, base_sig = 0, nil end
                    succeed("deleted", src.name)
                else fail(err) end
                finish()
            end)
        end)
    end

    -- The live desktop changed: `current` may no longer match. Cheap, no queue, publishes only on change.
    function ctl.touch()
        if state ~= "loading" then publish() end
    end

    -- Hand the current snapshot to the host again without a revision change (the bar just opened).
    function ctl.resend()
        local text = ctl.snapshot_text()
        host.publish(snapshot_table(), text, status)
    end

    -- ── reading ──
    function ctl.snapshot() return snapshot_table() end
    function ctl.snapshot_text()
        local snap = snapshot_table()
        snap.rev = rev
        local ok, text = pcall(host.json.encode, snap)
        return ok and text or "{}"
    end
    -- one layout's cards (copy), for the bar's preview or a script
    function ctl.read(id)
        local l = L.find(store, id)
        if not l then return nil end
        local out = copy(l)
        out.cards_n = #l.cards
        return out
    end
    function ctl.state() return state, writable, state_msg end
    return ctl
end

return L
