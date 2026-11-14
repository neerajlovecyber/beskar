-- Saved widget desktops (C4a): lua tests/widget-layouts.lua
-- Part 1 tests shell/widget_layouts.luau with a fake host (storage failures, malformed files, restore, queue).
-- Part 2 runs the real shell/widgets.luau in a sandbox with a throw-away HOME, so the shell scripts that read,
-- write atomically and back up the file really run. Nothing touches the real session or ~/.config.
package.path = "shell/?.luau;" .. package.path
local L = dofile("shell/widget_layouts.luau")
local KINDS = dofile("shell/widgets_data.luau").KINDS
local passed = 0
local function check(v, why) if not v then error("FAILED: " .. why, 2) end passed = passed + 1 end
local function copy(v) if type(v) ~= "table" then return v end local t = {} for k, x in pairs(v) do t[k] = copy(x) end return t end
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

local GEOM = { unit = 160, gap = 16, top = 40, side = 12, bottom = 60, ox = 48, oy = 72, def_w = 1920, def_h = 1080 }
local function kind_of(id) return KINDS[id] end

-- ── names ──
check(L.clean_name("  My\t  desk \n") == "My desk", "whitespace and control characters collapse")
check(L.clean_name("") == nil and select(2, L.clean_name("  \t ")) == "name_empty", "blank names are refused")
check(select(2, L.clean_name(42)) == "name_empty", "non-text names are refused")
check(select(2, L.clean_name("bad\xff")) == "name_invalid", "invalid UTF-8 is refused")
local long = L.clean_name(string.rep("é", 60))
check(utf8.len(long) == L.MAX_NAME and #long <= L.MAX_NAME_BYTES, "long names are cut on a character boundary")
check(utf8.len(L.clean_name(string.rep("日", 60))) <= L.MAX_NAME, "wide names stay within the byte bound too")

-- ── decoding malformed / hostile files ──
local function card(id, out, kind, sz, x, y) return { id = id, out = out or "A", kind = kind or 1, sz = sz or 1, x = x or 48, y = y or 72 } end
local function layout(id, name, cards) return { id = id, name = name, created = 1, updated = 1, snap = true, cards = cards or { card(1) } } end
local function dec(d) return L.decode(json.encode(d), json) end
check(select(2, L.decode("not json", json)) == "corrupt", "garbage is corrupt")
check(select(2, L.decode("[1,2]", json)) == "corrupt", "wrong top level is corrupt")
check(select(2, L.decode("", json)) == "corrupt", "empty text is corrupt")
check(select(2, dec({ layouts = {} })) == "corrupt", "missing version is corrupt")
check(select(2, dec({ version = 4, layouts = {} })) == "newer", "newer version is reported, not rewritten")
check(select(2, dec({ version = 1, layouts = "x" })) == "corrupt", "layouts must be a list")
check(select(2, L.decode(string.rep(" ", L.MAX_BYTES + 1), json)) == "too_large", "oversized file is refused")
local big = {}
for i = 1, L.MAX_CARDS + 1 do big[i] = card(i) end
local store, rep = dec({ version = 1, next_id = 3, layouts = {
    layout(1, "Good"),
    layout(2, "Too many", big),
    layout(3, "Dup ids", { card(1), card(1, "B") }),
    layout(4, "Bad size", { card(1, "A", 1, 7) }),
    layout(5, "Bad coord", { card(1, "A", 1, 1, "x", 5) }),
    layout(6, "Bad out", { card(1, "") }),
    layout(1, "Same id"),
    layout(7, "good"),            -- same name as "Good", ignoring case
    { id = 8, name = "No cards" },
    "junk",
} })
check(store and #store.layouts == 1 and store.layouts[1].name == "Good", "only the trustworthy layout survives")
check(rep.dropped == 9, "every unusable layout is counted")
check(store.next_id >= 9, "ids of dropped layouts are never reused")
local many = {}
for i = 1, L.MAX_LAYOUTS + 5 do many[i] = layout(i, "L" .. i) end
store, rep = dec({ version = 1, layouts = many })
check(#store.layouts == L.MAX_LAYOUTS and rep.dropped == 5, "more than the layout limit is cut and counted")
store = dec({ version = 1, next_id = 1, layouts = { layout(5, "Five") } })
check(store.next_id == 6, "a next_id below the highest id is repaired")
store = dec({ version = 1, layouts = { { id = 1, name = "Floats", snap = false, cards = { card(1, "A", 1, 1, 48.4, 72.6) }, areas = { A = { w = 1920, h = 1080 }, B = { w = -1, h = 4 } } } } })
check(store.layouts[1].cards[1].x == 48 and store.layouts[1].cards[1].y == 73 and store.layouts[1].snap == false, "positions round, snap option kept")
check(store.layouts[1].areas.A.w == 1920 and store.layouts[1].areas.B == nil, "bad output areas are ignored")

-- ── round trip ──
local s1 = L.new_store()
s1.layouts[1] = { id = 1, name = "Desk “one”", created = 5, updated = 9, snap = false, areas = { A = { w = 1920, h = 1080 } }, cards = { card(1), card(2, "B", 12, 1, 500, 300) } }
s1.next_id = 2
local text = assert(L.encode(s1, json))
local s2, r2 = L.decode(text, json)
check(same(s1, s2) and r2.dropped == 0, "encode → decode is lossless")
local saved_max = L.MAX_BYTES
L.MAX_BYTES = 50
check(select(2, L.encode(s1, json)) == "too_large", "encoding past the byte bound is refused")
L.MAX_BYTES = saved_max

-- ── capture ──
local body, skipped = L.capture({ card(1), card(1, "B", 3, 0), card(0, "A", 5, 0), { id = 4, out = "A", kind = 1, sz = 9, x = 0, y = 0 }, card(5, nil), },
    true, { A = { 1920, 1080 }, Z = { 800, 600 } })
check(#body.cards == 4 - 0 and skipped == 1, "invalid cards are skipped and counted")
local ids = {}
for _, c in ipairs(body.cards) do check(not ids[c.id] and c.id >= 1, "captured ids are unique and positive"); ids[c.id] = true end
check(body.areas.A and not body.areas.Z, "only outputs the layout uses record an area")
local sixteen, seventeen = {}, {}
for i = 1, 17 do seventeen[i] = card(i); if i <= 16 then sixteen[i] = card(i) end end
check(L.capture(sixteen, true, {}) ~= nil and L.capture(seventeen, true, {}) == nil, "the card bound is enforced at capture")
local content = L.capture({ { id = 1, out = "A", kind = 10, sz = 1, x = 0, y = 0, note = "secret note", deadline = 99, forecast = {} } }, true, {})
local flat = json.encode(content)
check(not flat:find("secret") and not flat:find("deadline") and not flat:find("forecast"), "no Personal / timer / weather content is captured")

-- ── restore ──
local function ctx(connected, sizes, limit)
    local c = {}
    for _, n in ipairs(connected) do c[n] = true end
    return { connected = c, sizes = sizes or {}, kind_of = kind_of, geom = GEOM, limit = limit }
end
local lay = layout(1, "R", {
    card(1, "A", 1, 1, 48, 72), card(2, "A", 99, 0, 10, 10), card(3, "A", 6, 2, 100, 100),      -- unknown kind, bad size for a Music card
    card(4, "GONE", 1, 1, 7000, 9000),                                                       -- disconnected output
    card(5, "A", 4, 0, 1500, 900), card(6, "A", 4, 0, 1700, 900),                            -- both clamp onto the same spot
})
local before = copy(lay)
local cards, rep2 = L.restore(lay, ctx({ "A" }, { A = { 1280, 720 } }))
check(same(lay, before), "restore never rewrites the stored layout")
check(rep2.skipped == 1 and #cards == 5, "unknown kinds are skipped")
local by = {}
for _, c in ipairs(cards) do by[c.id] = c end
check(by[3].sz == 1 and rep2.adjusted == 1, "an unsupported size becomes a supported one")
check(by[4].out == "GONE" and by[4].x == 7000 and by[4].y == 9000 and rep2.hidden == 1, "disconnected-output records are kept as stored")
local W, H = 1280, 720
for _, id in ipairs({ 1, 3, 5, 6 }) do
    local c = by[id]
    local w = c.sz == 0 and 160 or 336
    local h = c.sz == 2 and 336 or 160
    check(c.x >= 12 and c.y >= 40 and c.x + w <= W - 12 and c.y + h <= H - 12 - 60, "card " .. id .. " fits the smaller work area")
end
local function overlap(a, b)
    local aw, ah = a.sz == 0 and 160 or 336, a.sz == 2 and 336 or 160
    local bw, bh = b.sz == 0 and 160 or 336, b.sz == 2 and 336 or 160
    return a.x < b.x + bw and a.x + aw > b.x and a.y < b.y + bh and a.y + ah > b.y
end
check(not overlap(by[5], by[6]), "cards squeezed together by the clamp are reflowed apart")
check(rep2.moved >= 2, "moved cards are counted")
local fine, rep3 = L.restore(layout(1, "Fine", { card(1, "A", 1, 1, 48, 72), card(2, "A", 3, 0, 400, 300) }), ctx({ "A" }, { A = { 1920, 1080 } }))
check(rep3.moved == 0 and fine[1].x == 48, "a big enough output changes nothing")
local _, rep4 = L.restore(layout(1, "Tiny", { card(1, "A", 7, 2, 0, 0), card(2, "A", 7, 2, 0, 0) }), ctx({ "A" }, { A = { 300, 300 } }))
check(rep4.crowded >= 1, "a card that cannot fit anywhere is reported, not dropped")
local _, rep5 = L.restore(lay, ctx({ "A" }, nil, 2))
check(rep5.skipped >= 4, "the live card limit is respected")

-- ── the controller with a fake host ──
local function make_host(o)
    o = o or {}
    local h = { disk = o.disk, writes = 0, backups = 0, applied = {}, published = {}, ready = true, manual = o.manual, pend = {},
        cards = copy(o.cards or { card(1, "A", 1, 1, 48, 72), card(2, "A", 3, 0, 48, 248), card(3, "B", 12, 1, 48, 72) }),
        snap = true, now = 1000, inflight = 0, max_inflight = 0, fail_write = false, backup_ok = true, history = {} }
    local function later(fn) if h.manual then h.pend[#h.pend + 1] = fn else fn() end end
    function h.flush() while #h.pend > 0 do table.remove(h.pend, 1)() end end
    local host = { json = json, now = function() return h.now end }
    host.read = function(cb)
        later(function()
            if h.read_error then cb("error")
            elseif h.disk == nil then cb("missing")
            elseif #h.disk > L.MAX_BYTES then cb("toolarge")
            else cb("ok", h.disk) end
        end)
    end
    host.write = function(body, cb)
        h.inflight = h.inflight + 1
        h.max_inflight = math.max(h.max_inflight, h.inflight)
        later(function()
            h.inflight = h.inflight - 1
            if h.fail_write then cb(false) else h.disk = body; h.writes = h.writes + 1; cb(true) end
        end)
    end
    host.backup = function(cb) later(function() h.backups = h.backups + 1; h.backed = h.disk; cb(h.backup_ok) end) end
    host.ready = function() return h.ready end
    host.capture = function() return { cards = h.cards, snap = h.snap, sizes = { A = { 1920, 1080 }, B = { 1920, 1080 } } } end
    host.context = function() return ctx(h.connected or { "A", "B" }, h.sizes or { A = { 1920, 1080 }, B = { 1920, 1080 } }) end
    host.apply = function(cards, snap)
        h.history[#h.history + 1] = { cards = copy(h.cards), snap = h.snap }
        h.applied[#h.applied + 1] = { cards = copy(cards), snap = snap }
        h.cards, h.snap = cards, snap
    end
    host.cards = function() return h.cards end
    host.publish = function(snap, body, status) h.published[#h.published + 1] = { snap = snap, body = body, status = status } end
    h.ctl = L.controller(host)
    return h
end
local function last(h) return h.published[#h.published].snap end

local h = make_host()
h.ctl.start()
check(last(h).ready and last(h).writable and last(h).count == 0, "a missing file starts an empty, writable store")
h.ctl.save("  Work  ")
check(h.writes == 1 and last(h).count == 1 and last(h).status.code == "saved" and last(h).status.ok, "save writes and reports")
local file = L.decode(h.disk, json)
check(#file.layouts == 1 and #file.layouts[1].cards == 3 and file.layouts[1].name == "Work", "the file holds the layout placements")
check(last(h).current == 1 and last(h).base == 1, "the saved layout is current")
h.cards[1].x = 500
h.ctl.touch()
check(last(h).current == 0 and last(h).base == 1, "moving a card makes the desktop differ from its layout")
h.ctl.update(1)
check(last(h).current == 1 and L.find(L.decode(h.disk, json), 1).cards[1].x == 500, "update overwrites the layout with the desktop")
local revs = last(h).rev
h.ctl.touch(); h.ctl.touch()
check(last(h).rev == revs, "touching an unchanged desktop publishes nothing new")

-- name rules
h.ctl.save("work")
check(last(h).status.code == "updated" and last(h).count == 1, "saving the same name (any case) replaces, never duplicates")
h.ctl.save("")
check(last(h).status.code == "name_empty" and not last(h).status.ok, "blank save is refused with a clear code")
h.ctl.save("Other")
h.ctl.rename(2, "WORK")
check(last(h).status.code == "name_taken", "rename onto another layout's name is refused")
h.ctl.rename(2, "Evening")
check(last(h).status.code == "renamed" and L.find(L.decode(h.disk, json), 2).name == "Evening", "rename persists")
h.ctl.rename(2, "EVENING")
check(last(h).status.code == "renamed", "a rename may change only the case of its own name")
h.ctl.rename(99, "x")
check(last(h).status.code == "not_found", "renaming a missing layout is reported")
h.ctl.duplicate(1); h.ctl.duplicate(1)
local names = {}
for _, l in ipairs(last(h).layouts) do names[l.name] = true end
check(names["work copy"], "duplicate names the copy after the layout it copies")
check(last(h).count == 4, "duplicates are real extra layouts")
local ln = last(h).layouts
check(ln[3].name ~= ln[4].name and ln[3].name:find("copy") and ln[4].name:find("copy 2"), "repeated duplicates get distinct names")
h.ctl.save(string.rep("x", 31))
h.ctl.duplicate(5)
local dn = last(h).layouts[6].name
check(utf8.len(dn) <= L.MAX_NAME and dn:find("copy"), "a duplicate of a long name stays within the limit")
h.ctl.delete(5); h.ctl.delete(6)
h.ctl.delete(3)
check(last(h).status.code == "deleted" and last(h).count == 3, "delete removes and persists")
h.ctl.delete(3)
check(last(h).status.code == "not_found", "deleting twice is reported")
check(#L.decode(h.disk, json).layouts == 3, "the disk agrees with memory after deletes")

-- the layout limit
local hl = make_host()
hl.ctl.start()
for i = 1, L.MAX_LAYOUTS do hl.ctl.save("n" .. i) end
check(last(hl).count == L.MAX_LAYOUTS, "the limit can be reached")
hl.ctl.save("one more")
check(last(hl).status.code == "limit" and last(hl).count == L.MAX_LAYOUTS, "past the limit is refused")
hl.ctl.duplicate(1)
check(last(hl).status.code == "limit", "duplicate respects the limit")
hl.ctl.save("N1")
check(last(hl).status.code == "updated", "replacing at the limit is still allowed")
local snap_text = hl.published[#hl.published].body
check(#snap_text < 3500, "the snapshot of a full store stays a bounded single say line (" .. #snap_text .. " bytes)")
check(#L.encode(L.decode(hl.disk, json), json) < L.MAX_BYTES // 2 + 1, "a full store is well inside the file bound")

-- storage failure leaves memory and disk the same
local hf = make_host()
hf.ctl.start()
hf.ctl.save("Keep")
local disk_before = hf.disk
hf.fail_write = true
hf.ctl.save("Lost")
check(last(hf).status.code == "io" and not last(hf).status.ok and last(hf).count == 1, "a failed write is reported and not remembered")
hf.ctl.delete(1)
check(last(hf).count == 1 and hf.disk == disk_before, "a failed delete changes nothing")
hf.fail_write = false
hf.ctl.save("Lost")
check(last(hf).status.code == "saved" and last(hf).count == 2, "the next attempt succeeds")

-- operations are serialised
local hm = make_host({ manual = true })
hm.ctl.start()
hm.flush()
hm.ctl.save("First"); hm.ctl.save("Second"); hm.ctl.save("Third")
hm.ctl.rename(1, "Renamed")
check(hm.max_inflight <= 1 and #hm.pend == 1, "only one write is in flight")
hm.flush()
check(hm.max_inflight == 1 and hm.writes == 4, "queued operations each write once, in order")
local fin = L.decode(hm.disk, json)
check(#fin.layouts == 3 and fin.layouts[1].name == "Renamed" and fin.layouts[3].name == "Third", "the last write holds every queued change")
hm.ctl.save("A"); hm.ctl.delete(2)
hm.flush()
check(L.find(L.decode(hm.disk, json), 2) == nil, "an operation queued behind another sees its result")

-- corrupt / newer / unreadable / partial files
local hc = make_host({ disk = "{broken" })
hc.ctl.start()
check(hc.backups == 1 and hc.backed == "{broken", "a corrupt file is copied aside first")
check(last(hc).state == "corrupt" and last(hc).writable and not last(hc).status.ok, "…and the store starts empty, with the problem visible")
hc.ctl.save("Fresh")
check(last(hc).status.code == "saved" and #L.decode(hc.disk, json).layouts == 1, "saving after recovery works")
local hb = make_host({ disk = "{broken" })
hb.backup_ok = false
hb.ctl.start()
check(not last(hb).writable, "without a safe copy, nothing may overwrite the file")
hb.ctl.save("Nope")
check(last(hb).status.code == "read_only" and hb.disk == "{broken" and hb.writes == 0, "read-only refuses writes and keeps the bytes")
local newer = json.encode({ version = 4, layouts = {} })
local hn = make_host({ disk = newer })
hn.ctl.start()
hn.ctl.delete(1); hn.ctl.save("x")
check(last(hn).state == "newer" and hn.disk == newer and hn.writes == 0 and hn.backups == 0, "a file from a newer version is never touched")
local hu = make_host({ disk = "x" })
hu.read_error = true
hu.ctl.start()
hu.ctl.save("x")
check(last(hu).state == "unreadable" and hu.writes == 0, "an unreadable file is not overwritten")
local hp = make_host({ disk = json.encode({ version = 1, layouts = { layout(1, "Good"), layout(2, "Bad", { card(1, "A", 1, 9) }) } }) })
hp.ctl.start()
check(hp.backups == 1 and last(hp).count == 1 and last(hp).writable and last(hp).status.code == "partial", "a partly unusable file keeps a copy and the good layouts")
-- refresh picks up an edited file, and can recover a read-only state
local hr = make_host({ disk = "{broken" })
hr.backup_ok = false
hr.ctl.start()
hr.disk = json.encode({ version = 1, layouts = { layout(1, "Hand fixed") } })
hr.ctl.refresh()
check(last(hr).writable and last(hr).count == 1 and last(hr).status.code == "refreshed", "refresh re-reads the file and recovers")

-- loading
local hld = make_host()
hld.ctl.start()
hld.ctl.save("Day")
hld.cards = { card(7, "A", 1, 1, 48, 72) }
hld.snap = false
hld.ctl.load(1)
check(#hld.applied == 1 and #hld.applied[1].cards == 3 and hld.applied[1].snap == true, "load applies the saved cards and the grid option")
check(hld.history[1].snap == false and #hld.history[1].cards == 1, "the prior desktop (and its grid option) reaches the undo step")
check(last(hld).status.code == "loaded" and last(hld).current == 1, "a loaded layout is current")
hld.ctl.load(42)
check(last(hld).status.code == "not_found" and #hld.applied == 1, "loading a missing layout applies nothing")
hld.ready = false
hld.ctl.load(1)
check(last(hld).status.code == "not_ready" and #hld.applied == 1, "no load or save before the desktop is ready")
hld.ctl.save("early")
check(last(hld).status.code == "not_ready" and #L.decode(hld.disk, json).layouts == 1, "…and nothing is written")
hld.ready = true
local stored = copy(L.decode(hld.disk, json).layouts[1])
hld.connected, hld.sizes = { "A" }, { A = { 800, 600 } }
hld.ctl.load(1)
local ap = hld.applied[#hld.applied]
check(#ap.cards == 3 and last(hld).status.msg:find("kept for disconnected"), "a disconnected output's card stays in the loaded desktop")
check(same(stored, L.decode(hld.disk, json).layouts[1]), "restoring onto a smaller display leaves the saved original alone")
check(last(hld).current == 1, "a restored desktop counts as current")
local hall = make_host({ disk = json.encode({ version = 1, layouts = { layout(1, "Old", { card(1, "A", 77, 0) }) } }) })
hall.ctl.start()
hall.ctl.load(1)
check(last(hall).status.code == "unusable" and #hall.applied == 0, "a layout with nothing showable does not wipe the desktop")
local hs = make_host()
hs.ctl.start()
hs.ctl.save("S")
hs.ctl.delete(1)
check(last(hs).current == 0 and last(hs).base == 0, "deleting the current layout clears it")
local before_resend = #hs.published
hs.ctl.resend()
check(#hs.published == before_resend + 1 and hs.published[#hs.published].snap.rev == last(hs).rev, "resend hands the same revision to the bar again")
check(hs.ctl.read(999) == nil and hs.ctl.read(1) == nil, "reading a missing layout gives nothing")
hs.ctl.save("T")
local detail = hs.ctl.read(2)
check(detail and #detail.cards == 3 and detail.name == "T", "read returns one layout with its cards")

-- ── part 2: the real widgets.luau in a sandbox with a throw-away HOME ──
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
local function list(pattern) return sh_out("ls " .. shq(HOME .. "/.config/beskar") .. " | grep -c " .. shq(pattern)):gsub("%s+$", "") end

local function boot()
    local w = { handlers = {}, afters = {}, says = {}, calls = {}, feed_calls = {}, fact = { snap_on = true, editing = false, widgets_on = true, hour12 = true, can_undo = false },
        text = {}, model = {} }
    local env
    env = setmetatable({
        fact = w.fact, text = w.text, model = w.model, json = json,
        on = function(n, fn) w.handlers[n] = fn end,
        every = function() return {} end,
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
            if name == "clockfmt" then return function() return "2:05 PM" end end
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
    function w.snapshot() return json.decode(w.text.wl_snapshot) end
    function w.saved_cards() return json.decode(get("widgets.json")).cards end
    w.run_timers()
    return w
end

reset_home()
local w = boot()
check(#w.model.ws == 6 and w.snapshot().ready and w.snapshot().count == 0, "widgets boot with defaults and an empty layout list")
w.text.wl_name = "Work"
w.fire("wl_save")
w.run_timers()
check(w.text.wl_name == "" and w.fact.wl_count == 1 and w.fact.wl_error == false, "save consumes the name text")
local disk = json.decode(get("widget-layouts.json"))
check(disk.version == 2 and #disk.layouts == 1 and #disk.layouts[1].cards == 6 and disk.layouts[1].snap == true, "the real atomic write produced the versioned file")
check(get("widget-layouts.json.tmp") == nil, "no temp file is left behind")
check(disk.layouts[1].areas["DP-1"].w == 1280, "output work areas are recorded")
local pushed
for _, s in ipairs(w.says) do if s[1] == "topbar" and s[2]:find("^text wb_layouts ") then pushed = s[2] end end
check(pushed and json.decode(pushed:gsub("^text wb_layouts ", "")).count == 1, "the bar is sent the snapshot")
-- change the desktop, then load: the whole load is ONE undo step that also returns the grid option
local before_cards = w.saved_cards()
w.fire("w_remove", w.model.ws[1].id)
w.fire("w_grid")
w.run_timers()
check(w.fact.snap_on == false and #w.saved_cards() == 5, "desktop edited (card removed, grid off)")
w.fire("wl_load", 1)
w.run_timers()
check(#w.saved_cards() == 6 and w.fact.snap_on == true and #w.model.ws == 6, "load restores cards and the grid option")
check(w.fact.can_undo == true and w.snapshot().current == 1, "load can be undone and is current")
w.fire("w_undo")
w.run_timers()
check(#w.saved_cards() == 5 and w.fact.snap_on == false, "undo returns the previous desktop and its grid option")
w.fire("w_undo")
w.run_timers()
check(w.fact.snap_on == false and #w.saved_cards() == 6, "the earlier card edit undoes too; the Grid toggle is not part of ordinary steps")
-- ordinary undo does not flip the grid
w.fire("w_grid"); w.fire("w_remove", w.model.ws[1].id); w.fire("w_undo")
check(w.fact.snap_on == true, "ordinary undo steps leave the grid toggle alone")
-- timers: placement only
w.fire("w_add", 12)       -- screen 0, kind 12: the Timer card
w.fire("wl_list")
w.text.wl_name = "WithTimer"
w.fire("wl_save")
w.run_timers()
w.fire("w_remove", w.model.ws[#w.model.ws].id)
w.fire("wl_load", 2)
w.run_timers()
local has_timer = false
for _, c in ipairs(w.saved_cards()) do if c.kind == 12 then has_timer = true end end
check(has_timer and w.feed_calls[#w.feed_calls] == true, "a timer card returns on load and its display feed restarts")
w.fire("wl_load", 1)
w.run_timers()
for _, s in ipairs(w.says) do check(s[1] ~= "activities", "layout operations never talk to the timer owner") end
for _, n in ipairs(w.calls) do check(not n:find("timer") and not n:find("activities"), "…nor call a timer service") end
-- CLI-compatible payloads
w.text.wl_name = "Renamed by CLI"
w.fire("wl_rename", 1)
w.fire("wl_duplicate", 1)
w.fire("wl_get", 1)
w.run_timers()
check(json.decode(get("widget-layouts.json")).layouts[1].name == "Renamed by CLI", "rename through text + numeric event works")
check(#json.decode(get("widget-layouts.json")).layouts == 3 and json.decode(w.text.wl_detail).name == "Renamed by CLI", "duplicate and get work")
w.fire("wl_delete", 3)
w.fire("wl_rename", 1)             -- no name text left: refused, nothing renamed to a stale value
w.run_timers()
check(w.snapshot().status.code == "name_empty" and json.decode(get("widget-layouts.json")).layouts[1].name == "Renamed by CLI", "a stale name is never reused")

-- a stored layout with a disconnected output and a huge position restores without losing the record
reset_home()
put("widget-layouts.json", json.encode({ version = 1, next_id = 2, layouts = { { id = 1, name = "Roaming", created = 1, updated = 1, snap = true,
    cards = { card(1, "HDMI-A-1", 1, 1, 48, 72), card(2, "DP-1", 3, 0, 1500, 900), card(3, "HDMI-A-9", 5, 1, 4000, 3000) } } } }))
local stored_file = get("widget-layouts.json")
local w2 = boot()
check(w2.snapshot().count == 1 and w2.snapshot().state == "ok", "an existing file is read by the shell script")
w2.fire("wl_load", 1)
w2.run_timers()
local got = {}
for _, c in ipairs(w2.saved_cards()) do got[c.id] = c end
check(#w2.model.ws == 2 and got[3] and got[3].out == "HDMI-A-9" and got[3].x == 4000 and got[3].y == 3000, "hidden output record is kept and not shown")
check(got[2].x == 1280 - 160 - 12 and got[2].y == 720 - 160 - 12 - 60, "a card on the smaller connected display is clamped")
check(get("widget-layouts.json") == stored_file, "the saved layout file is untouched by a load")

-- corrupt file: copied aside once, original kept until a save, nothing duplicated on later starts
reset_home()
put("widget-layouts.json", "{definitely not json")
local w3 = boot()
check(list("widget-layouts.json.corrupt-") == "1" and get("widget-layouts.json") == "{definitely not json", "corrupt file is backed up and left in place")
check(w3.snapshot().state == "corrupt" and w3.snapshot().writable, "the bar can see the problem")
boot()
check(list("widget-layouts.json.corrupt-") == "1", "restarting does not pile up identical backups")
w3.text.wl_name = "After"
w3.fire("wl_save")
w3.run_timers()
check(json.decode(get("widget-layouts.json")).layouts[1].name == "After", "a save after recovery replaces the corrupt file")
-- newer file untouched
reset_home()
put("widget-layouts.json", '{"version":9,"layouts":[]}')
local w4 = boot()
w4.text.wl_name = "X"
w4.fire("wl_save")
w4.run_timers()
check(get("widget-layouts.json") == '{"version":9,"layouts":[]}\n' or get("widget-layouts.json") == '{"version":9,"layouts":[]}', "a newer file is not overwritten")
check(w4.snapshot().state == "newer" and w4.snapshot().status.code == "read_only", "…and the refusal is explained")

os.execute("rm -rf " .. shq(HOME))
print(string.format("widget-layouts: %d checks passed", passed))
