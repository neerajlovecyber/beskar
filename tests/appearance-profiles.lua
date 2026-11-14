-- Run only this suite for saved looks and appearance import / export: lua tests/appearance-profiles.lua
package.path = "shell/?.luau;" .. package.path
local P = require("preferences")
local AP = require("appearance_profiles")
local passed = 0
local function check(v, why) assert(v, why); passed = passed + 1 end

-- a small strict JSON decoder (the scene passes pleamar's json.decode; this one only feeds the tests)
local function decode(s)
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
                local e = s:sub(i + 1, i + 1)
                if e == "u" then out[#out + 1] = string.char(tonumber(s:sub(i + 2, i + 5), 16)); i = i + 6
                else out[#out + 1] = ({ n = "\n", r = "\r", t = "\t" })[e] or e; i = i + 2 end
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
                if s:sub(i, i) ~= ":" then error("colon expected at " .. i) end
                i = i + 1; t[k] = value(); ws()
                local d = s:sub(i, i); i = i + 1
                if d == "}" then return t end
                if d ~= "," then error("comma expected at " .. i) end
            end
        elseif c == "[" then
            local t = {}
            i = i + 1; ws()
            if s:sub(i, i) == "]" then i = i + 1; return t end
            while true do
                t[#t + 1] = value(); ws()
                local d = s:sub(i, i); i = i + 1
                if d == "]" then return t end
                if d ~= "," then error("comma expected at " .. i) end
            end
        elseif c == '"' then return str()
        elseif s:find("^true", i) then i = i + 4; return true
        elseif s:find("^false", i) then i = i + 5; return false
        elseif s:find("^null", i) then i = i + 4; return nil
        end
        local num = s:match("^-?%d+%.?%d*[eE]?[+-]?%d*", i)
        if not num or num == "" then error("unexpected '" .. c .. "' at " .. i) end
        i = i + #num
        return tonumber(num)
    end
    local v = value(); ws()
    if i <= #s then error("trailing text at " .. i) end
    return v
end

-- ── a fake host: run() is asynchronous, the test completes each call by hand ──
local function host(opts)
    opts = opts or {}
    local h = { calls = {}, notices = {} }
    h.adapter = {
        decode = decode,
        encode = opts.encode,
        notify = function(s) h.notices[#h.notices + 1] = s end,
        run = function(script, args, cb) h.calls[#h.calls + 1] = { script = script, args = args, cb = cb, done = false } end,
    }
    function h.pending()
        local n = 0
        for _, c in ipairs(h.calls) do if not c.done then n = n + 1 end end
        return n
    end
    function h.finish(i, out, code)
        local c = h.calls[i]
        assert(c and not c.done, "call " .. tostring(i) .. " is not pending")
        c.done = true
        c.cb(out, code)
    end
    function h.writes()
        local w = {}
        for _, c in ipairs(h.calls) do if c.script == AP.WRITE_SCRIPT then w[#w + 1] = c end end
        return w
    end
    function h.last()
        return h.calls[#h.calls]
    end
    return h
end

-- open a controller on a store with `text` (nil = no file)
local function opened(text, opts)
    local h = host(opts)
    local ctl = AP.new(P, h.adapter)
    local status
    ctl.open(function(s) status = s end)
    assert(#h.calls == 1 and h.calls[1].script == AP.READ_SCRIPT and h.calls[1].args[1] == "beskar/appearance-looks.json")
    if text == nil then h.finish(1, "", 3) else h.finish(1, text, 0) end
    return ctl, h, status
end

local live = { appearance = 2, skin = 1, accent = 3, accent_auto = true, pal_style = 2, hour12 = false, pref_apps = false }
local pal = { style = 2, src = "#AABBCC", dark = { a = "#112233", b = "#223344", s = "#334455" }, light = { a = "#eeeeee", b = "#dddddd", s = "#cccccc" } }

-- ── names ──
do
    check(AP.validate_name("  Evening  ") == "Evening", "name is trimmed")
    check(AP.validate_name("Café ☕ 日本語") == "Café ☕ 日本語", "unicode names are fine")
    check(select(2, AP.validate_name("   ")) == "name" and select(2, AP.validate_name("")) == "name", "empty names are refused")
    check(AP.validate_name(string.rep("a", 32)) and not AP.validate_name(string.rep("a", 33)), "32 characters, not 33")
    check(AP.validate_name(string.rep("日", 32)), "32 three-byte characters are 96 bytes: allowed")
    check(not AP.validate_name(string.rep("😀", 25)) and utf8.len(string.rep("😀", 25)) == 25, "96 bytes caps four-byte characters even under 32 characters")
    check(AP.validate_name(string.rep("😀", 24)), "24 four-byte characters are exactly 96 bytes")
    check(not AP.validate_name("bad\255name"), "invalid UTF-8 is refused")
    check(not AP.validate_name("two\nlines") and not AP.validate_name("tab\there") and not AP.validate_name("nul\0x"), "control characters are refused")
    check(not AP.validate_name("a\u{202e}b") and not AP.validate_name("a\u{85}b"), "direction and C1 characters are refused")
    check(not AP.validate_name(42) and not AP.validate_name(nil), "non-strings are refused")
end

-- ── a missing store: ready, nothing is written at load ──
local ctl, h, st = opened(nil)
check(st.state == "ready" and st.store == "missing" and st.writable and st.count == 0 and st.max == 16, "missing file starts ready")
check(#h.calls == 1 and #h.writes() == 0, "no write at load")
check(#ctl.list() == 0, "empty list")
check(#h.notices >= 2 and h.notices[1].state == "loading" and h.notices[#h.notices].state == "ready", "status is published: loading then ready")

-- ── save / duplicate / rename / update / delete ──
local r = ctl.save(" Evening ", live, pal, { palette = true })
check(r.ok and r.id == "l1" and r.look.name == "Evening" and r.palette_saved and r.look.pending, "save makes l1, with the palette cache")
check(r.look.values.appearance == 2 and r.look.values.accent_auto == true and r.look.values.hour12 == nil and r.look.values.pref_apps == nil, "only appearance values are kept")
check(r.look.summary == "Auto · Light Acrylic · Wallpaper colours (Neutral)", "summary: " .. r.look.summary)
check(#h.writes() == 1 and h.pending() == 1, "one write started")
local doc = decode(h.writes()[1].args[2])
check(h.writes()[1].args[1] == "beskar/appearance-looks.json" and doc.version == 1 and doc.seq == 1 and #doc.looks == 1, "store text: version 1, seq, looks")
check(doc.looks[1].values["appearance.mode"] == 2 and doc.looks[1].values["appearance.wallpaper-colours"] == true and doc.looks[1].values["appearance.palette"] == 2, "values keyed by stable control ids")
check(doc.looks[1].palette.dark.a == "#112233" and doc.looks[1].palette.src == "#aabbcc", "palette cache is stored normalised")
check(ctl.status().state == "saving" and ctl.status().pending, "status while saving")

-- changes while a write is in flight are coalesced into ONE following write
check(ctl.save("evening", live).code == "duplicate", "names are unique ignoring case")
local r2 = ctl.save("Quiet", { appearance = 0, skin = 2, accent = 6 })
local r3 = ctl.save("Loud", { appearance = 1, skin = 0, accent = 1 })
check(r2.id == "l2" and r3.id == "l3" and #h.writes() == 1, "no second write while the first runs")
check(ctl.rename(r3.id, "Louder").ok and ctl.rename("l3", "Louder").changed == false, "rename; renaming to the same name changes nothing")
check(ctl.rename("l3", "quiet").code == "duplicate" and ctl.rename("l9", "x").code == "missing" and ctl.rename("l3", "").code == "name", "rename validates")
local c3 = ctl.get("l1")
check(c3.pending and #ctl.list() == 3, "unsaved look is pending")
h.finish(2, "", 0)   -- first write done
check(#h.writes() == 2 and h.pending() == 1, "exactly one coalesced write follows")
local doc2 = decode(h.writes()[2].args[2])
check(#doc2.looks == 3 and doc2.looks[3].name == "Louder" and doc2.seq == 3, "the second write holds every change")
check(ctl.get("l1").pending == false and ctl.get("l3").pending, "committed look is no longer pending; later ones still are")
h.finish(#h.calls, "", 0)
check(ctl.status().state == "ready" and not ctl.status().pending and #h.writes() == 2, "idle after the last write")
for _, l in ipairs(ctl.list()) do check(not l.pending, "saved: " .. l.id) end

-- update replaces values (palette only when asked), no write when nothing changes
local up = ctl.update("l1", live, pal, { palette = true })
check(up.ok and up.changed == false and #h.writes() == 2, "identical update writes nothing")
up = ctl.update("l1", { appearance = 0, skin = 0, accent = 2, accent_auto = false, pal_style = 0 }, pal)
check(up.ok and up.changed and not up.palette_saved and not ctl.get("l1").has_palette and ctl.get("l1").values.accent == 2, "update drops the palette unless asked")
h.finish(#h.calls, "", 0)
check(ctl.update("l7", live).code == "missing", "update of an unknown look")
check(ctl.update("l1", live, { style = 1 }, { palette = true }).palette_skipped, "an unusable palette is skipped, the look still updates")
h.finish(#h.calls, "", 0)

local del = ctl.delete("l2")
check(del.ok and #ctl.list() == 2 and ctl.delete("l2").code == "missing", "delete")
h.finish(#h.calls, "", 0)
local again = ctl.save("Again", live)
check(again.id == "l4", "ids are not reused after a delete")
h.finish(#h.calls, "", 0)

-- ── the 16-look cap ──
do
    local c, hh = opened(nil)
    for i = 1, 16 do check(c.save("Look " .. i, { accent = i % 7 }).ok, "save " .. i) end
    check(c.save("One too many", live).code == "full" and #c.list() == 16, "17th look refused")
    check(#hh.writes() == 1, "still a single write in flight")
    hh.finish(2, "", 0)
    check(#hh.writes() == 2, "coalesced")
    hh.finish(3, "", 0)
    check(decode(hh.writes()[2].args[2]).looks[16].name == "Look 16", "all sixteen stored")
    check(c.delete("l1").ok and c.save("Replacement", live).ok, "room again after a delete")
end

-- ── failed save: memory vs file, no retry loop, explicit retry / discard ──
do
    local c, hh = opened(nil)
    c.save("Keep", live)
    hh.finish(2, "", 1)
    local s = c.status()
    check(s.state == "failed" and s.failed and s.pending and s.message:find("Retry"), "a failed save says so")
    check(#hh.writes() == 1 and hh.pending() == 0, "no automatic retry")
    check(c.list()[1].pending and #c.list() == 1, "the look stays in memory, marked unsaved")
    check(c.retry() and #hh.writes() == 2 and hh.pending() == 1, "retry writes again")
    hh.finish(3, "", 0)
    check(c.status().state == "ready" and not c.list()[1].pending, "retry succeeded")
    check(not c.retry(), "nothing to retry")

    c.save("Second", live)
    hh.finish(4, "", 1)
    check(c.status().state == "failed", "failed again")
    c.delete("l1")                           -- a new change after a failure tries once more
    check(#hh.writes() == 4 and hh.pending() == 1, "a new change triggers one new attempt")
    hh.finish(5, "", 1)
    check(c.discard_unsaved() and #c.list() == 1 and c.list()[1].name == "Keep" and c.status().state == "ready", "discard returns to the last saved state")
    -- the committed copy moves only on success: a failed write never commits
    local c2, h2 = opened(nil)
    c2.save("A", live)
    check(c2.discard_unsaved() == false, "cannot discard under a running write")
    h2.finish(2, "", 1)
    check(c2.discard_unsaved() and #c2.list() == 0, "memory returns to the committed (empty) store")
    check(#h2.writes() == 1, "nothing else was written")
end

-- ── damaged, newer, unreadable and oversize stores are protected ──
local function blocked(text, code, store)
    local c, hh, s = opened(text)
    if code then hh = hh end
    return c, hh, s
end
do
    local c, hh, s = opened("{ not json")
    check(s.state == "blocked" and s.store == "corrupt" and not s.writable and s.message:find("damaged"), "undecodable text is corrupt")
    check(c.save("Nope", live).code == "blocked" and c.rename("l1", "x").code == "blocked" and c.delete("l1").code == "blocked" and #hh.writes() == 0, "no mutation, no write")
    check(#c.list() == 0, "nothing listed from a damaged store")
    for _, bad in ipairs({ "", "   ", "[1]", "42", '"x"', "null", "{}", '{"version": "one"}', '{"version": 0, "looks": []}', '{"version": 1, "looks": 5}', '{"version": 1, "looks": {"a": 1}}' }) do
        local _, _, st2 = opened(bad)
        check(st2.store == "corrupt" and not st2.writable, "corrupt: " .. bad)
    end
    check(select(3, opened(string.rep(" ", AP.MAX_STORE_BYTES + 1))).store == "corrupt", "oversize text is corrupt")

    local cn, hn, sn = opened('{"version": 2, "looks": [{"id": "l1", "future": true}]}')
    check(sn.store == "newer" and not sn.writable and sn.state == "blocked" and cn.save("x", live).code == "blocked" and #hn.writes() == 0, "newer version is read-only")

    local cu, hu, su = (function()
        local hh2 = host()
        local cc = AP.new(P, hh2.adapter)
        local out
        cc.open(function(s2) out = s2 end)
        hh2.finish(1, nil, 4)
        return cc, hh2, out
    end)()
    check(su.store == "unreadable" and not su.writable and cu.save("x", live).code == "blocked" and #hu.writes() == 0, "unreadable file is protected")

    local ct, ht, st3 = opened('{"version": 1, "looks": [' .. string.rep('{"id":"l1"},', 16) .. '{"id":"l2"}]}')
    check(st3.store == "toomany" and not st3.writable and #ht.writes() == 0, "more than 16 entries is read-only")

    -- the user can move a CORRUPT file aside, then start fresh; other blocks have no recover
    local cr, hr = opened("garbage")
    local rec
    check(cr.recover("20261114T1015", function(ok, msg) rec = { ok, msg } end) == true and hr.last().script == AP.MOVE_ASIDE_SCRIPT, "recover runs the move script")
    check(hr.last().args[2] == "20261114T1015" and hr.last().args[1] == "beskar/appearance-looks.json", "recover arguments")
    check(cr.save("Early", live).code == "blocked", "still blocked while moving")
    hr.finish(#hr.calls, "", 5)
    check(rec[1] == false and cr.status().state == "blocked", "a refused move leaves the store blocked")
    cr.recover("a/b c")
    check(hr.last().args[2] == "abc", "stamp is a safe basename")
    hr.finish(#hr.calls, "", 0)
    check(cr.status().state == "ready" and cr.status().store == "missing" and cr.save("Fresh", live).ok, "after recovery the store is writable")
    check(select(1, opened('{"version": 2}')) and (function() local c2 = opened('{"version": 2}'); return c2.recover("x") end)() == false, "recover refuses a newer store")
end

-- ── held entries and load issues: nothing is silently discarded ──
do
    local text = '{"version": 1, "seq": 4, "future_top": {"keep": [1, 2]}, "looks": ['
        .. '{"id": "l1", "name": "Good", "values": {"appearance.mode": 0, "appearance.skin": 1, "appearance.wallpaper-colours": false, "appearance.accent": 4, "appearance.palette": 1}},'
        .. '{"id": "l2", "name": "Bad range", "values": {"appearance.mode": 9, "appearance.skin": 1, "appearance.wallpaper-colours": false, "appearance.accent": 4, "appearance.palette": 1}},'
        .. '{"id": "l3", "name": "Future key", "mood": "x", "values": {}},'
        .. '{"id": "l1", "name": "Dup id", "values": {"appearance.mode": 0, "appearance.skin": 1, "appearance.wallpaper-colours": false, "appearance.accent": 4, "appearance.palette": 1}},'
        .. '{"id": "l7", "name": "Bad palette", "values": {"appearance.mode": 1, "appearance.skin": 1, "appearance.wallpaper-colours": true, "appearance.accent": 4, "appearance.palette": 1}, "palette": {"style": 1, "dark": {"a": "red"}}},'
        .. '{"id": "x", "name": "Bad id", "values": {}},'
        .. '{"id": "l8", "name": "String int", "values": {"appearance.mode": "1", "appearance.skin": 1, "appearance.wallpaper-colours": false, "appearance.accent": 4, "appearance.palette": 1}}'
        .. ']}'
    local c, hh, s = opened(text)
    check(s.state == "ready" and s.writable and s.count == 2 and s.held == 5 and #s.issues == 6, "good entries load; others are held: " .. s.count .. "/" .. s.held .. "/" .. #s.issues)
    check(s.message:find("5 saved looks could not be understood"), "held message: " .. s.message)
    check(c.get("l1").name == "Good" and c.get("l7") and not c.get("l7").has_palette, "an invalid palette cache is dropped, the look kept")
    check(#hh.writes() == 0, "loading never writes")
    check(c.save("New", live).id == "l9", "a new id never reuses a held entry's id")
    hh.finish(2, "", 0)
    local out = decode(hh.writes()[1].args[2])
    check(#out.looks == 8 and out.future_top.keep[2] == 2 and out.seq == 9, "held entries and unknown top-level keys are written back")
    check(out.looks[4].id == "l2" and out.looks[4].values["appearance.mode"] == 9 and out.looks[5].mood == "x", "held entries are verbatim")
    for i = 1, 8 do check(c.save("Filler " .. i, live).ok, "filler " .. i) end    -- 2 + 5 held + New + 8 = 16
    check(c.save("Over", live).code == "full" and #c.list() == 11, "held entries count toward the cap")
    local c2 = opened(text)
    check(c2.discard_held().discarded == 5 and c2.status().held == 0, "held entries are dropped only on request")
end

-- ── palette cache exclusion ──
do
    local c, hh = opened(nil)
    local a = c.save("With", live, pal, { palette = true })
    local b = c.save("Without", live, pal)
    local d = c.save("Unusable", live, nil, { palette = true })
    check(a.palette_saved and not b.palette_saved and not b.palette_skipped and not d.palette_saved and d.palette_skipped, "palette only on request and only when usable")
    hh.finish(2, "", 0)
    local out = decode(hh.writes()[2].args[2])
    check(out.looks[1].palette and not out.looks[2].palette and not out.looks[3].palette, "stored palette follows the choice")
    local text, edoc = c.export_look("l1")
    check(edoc.palette == nil and not text:find('"palette"', 1, true) and not text:find("#112233"), "export never carries the palette cache")
    check(select(2, c.export_look("l9")).code == "missing", "export of an unknown look")
end

-- ── applying a look: one plan, one undo snapshot, palette restore ──
do
    local c, hh = opened(nil)
    c.save("Evening", live, pal, { palette = true })
    c.save("Plain", { appearance = 1, skin = 0, accent = 0, accent_auto = false, pal_style = 0 })
    hh.finish(2, "", 0); hh.finish(3, "", 0)
    local now = P.appearance_snapshot({ appearance = 1, skin = 0, accent = 0, accent_auto = false, pal_style = 0 }, nil)
    local ap = c.apply_look("l1", now)
    check(ap.ok and not ap.noop and #ap.plan.changes == 5 and ap.plan.values.accent == 3 and ap.plan.restore_palette.dark.a == "#112233", "plan to the saved look with its colours")
    check(P.snapshot_equal(ap.undo_snapshot, now) and ap.undo_snapshot ~= now, "one undo snapshot, a copy of the live look")
    check(ap.snapshot.palette ~= nil and ap.name == "Evening", "result carries the snapshot")
    ap.undo_snapshot.values.skin = 2
    check(now.values.skin == 0, "the host's snapshot is not aliased")
    local back = c.apply_look("l2", P.appearance_snapshot(live, pal))
    check(back.plan.restore_palette == nil and #back.plan.changes == 5, "a look without colours leaves the palette cache alone")
    local same = c.apply_look("l2", now)
    check(same.noop and same.message == "Already using this look." and same.plan.noop, "applying the current look is a no-op")
    check(c.apply_look("l9", now).code == "missing", "unknown look")
    check(c.matching(now) == "l2" and c.matching(P.appearance_snapshot(live, nil)) == "l1" and c.matching({ appearance = 0 }) == nil, "matching finds the look equal to the live one, palette ignored")
    check(c.apply_look("l1", { appearance = 1 }).ok, "current may be a plain facts table")
    check(#hh.writes() == 2, "applying a look never writes the store")
end

-- ── strict import ──
local ictl, ih = opened(nil)
local function parse(text) return ictl.parse_import(text) end
local function codes(res)
    local out = {}
    for _, e in ipairs(res.errors) do out[#out + 1] = e.code .. ":" .. e.path end
    table.sort(out)
    return table.concat(out, ",")
end
local good = '{"kind": "beskar.appearance", "version": 1, "values": {"appearance.mode": 0, "appearance.skin": 2, "appearance.wallpaper-colours": false, "appearance.accent": 5, "appearance.palette": 3}}'
local pr = parse(good)
check(pr.ok and pr.values.appearance == 0 and pr.values.skin == 2 and pr.values.accent_auto == false and pr.values.accent == 5 and pr.values.pal_style == 3, "a valid export parses to fact-keyed values")
check(parse('\239\187\191' .. good).ok, "BOM tolerated")
check(parse('{"kind": "beskar.appearance", "version": 1, "values": {"appearance.accent": 2.0}}').values.accent == 2, "integral floats are numbers")
check(parse('{"kind": "beskar.appearance", "version": 1, "values": {"appearance.accent": 2}}').values.skin == nil, "a partial file is allowed")

local function bad(text, want)
    local res = parse(text)
    local label = tostring(text):sub(1, 70)
    check(not res.ok and res.message and #res.errors >= 1, "rejected: " .. label)
    if want then check(codes(res) == want, "codes " .. codes(res) .. " ~= " .. want .. " for " .. label) end
    return res
end
bad("", "empty:")
bad(nil, "empty:")
bad("   ", "empty:")
bad("[1, 2]", "format:")
bad("not json", "format:")
bad("{ broken", "format:")
bad(string.rep(" ", AP.MAX_IMPORT_BYTES) .. "{}", "size:")
bad('{"kind": "beskar.appearance", "version": 1}', "type:values")
bad('{"kind": "beskar.appearance", "version": 1, "values": {}}', "empty:values")
bad('{"kind": "beskar.appearance", "version": 1, "values": [1]}', "type:values")
bad('{"kind": "beskar.appearance", "values": {"appearance.mode": 1}}', "version:version")
bad('{"kind": "beskar.appearance", "version": 2, "values": {"appearance.mode": 1}}', "version:version")
bad('{"kind": "beskar.appearance", "version": 0, "values": {"appearance.mode": 1}}', "version:version")
bad('{"kind": "beskar.appearance", "version": "1", "values": {"appearance.mode": 1}}', "version:version")
bad('{"kind": "beskar.appearance", "version": 1.5, "values": {"appearance.mode": 1}}', "version:version")
bad('{"version": 1, "values": {"appearance.mode": 1}}', "kind:kind")
bad('{"kind": "beskar.widgets", "version": 1, "values": {"appearance.mode": 1}}', "kind:kind")
check(bad('{"kind": "beskar.widgets", "version": 1, "values": {"appearance.mode": 1}}').message:find("different kind"), "a sibling kind is named")
local v2 = bad('{"kind": "beskar.appearance", "version": 2, "values": {"appearance.mode": 1}}')
check(v2.message:find("newer Beskar"), "newer versions say so")

-- unsupported keys are rejected before anything is considered, each one reported
local u = bad('{"kind": "beskar.appearance", "version": 1, "values": {"appearance.mode": 1}, "command": "rm -rf ~", "extra": 1}')
check(codes(u) == "unsupported:command,unsupported:extra" and u.errors[1].message:find("not portable") or u.errors[2].message:find("not portable"), "commands are named as not portable")
local u2 = bad('{"kind": "beskar.appearance", "version": 1, "values": {"appearance.mode": 1, "hour12": true, "appearance.accent": 2, "wallpaper_path": "/x", "pref_apps": false, "palette": {"dark": {}}}}')
check(codes(u2):find("unsupported:values.hour12") and codes(u2):find("unsupported:values.wallpaper_path") and codes(u2):find("unsupported:values.palette") and codes(u2):find("unsupported:values.pref_apps"), "unsupported value keys: " .. codes(u2))
for _, key in ipairs({ "command", "exec", "path", "token", "password", "content", "display_mode", "timer", "palette", "pref_apps", "wallpaper" }) do
    local res = bad('{"kind": "beskar.appearance", "version": 1, "values": {"' .. key .. '": 1}}')
    local msgs = {}
    for _, e in ipairs(res.errors) do msgs[#msgs + 1] = e.message end
    check(table.concat(msgs, " "):find("not portable"), "denied category: " .. key)
end
check(codes(bad('{"kind": "beskar.appearance", "version": 1, "values": {"appearance.density": 1}}')):find("unsupported:values.appearance.density"), "an unknown setting is simply unsupported")
check(not bad('{"kind": "beskar.appearance", "version": 1, "values": {"appearance.density": 1}}').errors[1].message:find("not portable"), "...without the portability warning")
check(not parse('{"kind": "beskar.appearance", "version": 1, "values": {"bad\\nkey": 1}}').errors[1].message:find("\n"), "messages never carry control characters")

-- types and ranges: strict, no coercion
bad('{"kind": "beskar.appearance", "version": 1, "values": {"appearance.mode": "1"}}', "value:values.appearance.mode")
bad('{"kind": "beskar.appearance", "version": 1, "values": {"appearance.mode": 3}}', "value:values.appearance.mode")
bad('{"kind": "beskar.appearance", "version": 1, "values": {"appearance.mode": -1}}', "value:values.appearance.mode")
bad('{"kind": "beskar.appearance", "version": 1, "values": {"appearance.mode": 1.5}}', "value:values.appearance.mode")
bad('{"kind": "beskar.appearance", "version": 1, "values": {"appearance.skin": true}}', "value:values.appearance.skin")
bad('{"kind": "beskar.appearance", "version": 1, "values": {"appearance.accent": 7}}', "value:values.appearance.accent")
bad('{"kind": "beskar.appearance", "version": 1, "values": {"appearance.wallpaper-colours": 1}}', "value:values.appearance.wallpaper-colours")
bad('{"kind": "beskar.appearance", "version": 1, "values": {"appearance.wallpaper-colours": "true"}}', "value:values.appearance.wallpaper-colours")
bad('{"kind": "beskar.appearance", "version": 1, "values": {"appearance.palette": 4}}', "value:values.appearance.palette")
bad('{"kind": "beskar.appearance", "version": 1, "values": {"appearance.palette": {"a": 1}}}', "value:values.appearance.palette")
local multi = bad('{"kind": "beskar.appearance", "version": 1, "values": {"appearance.mode": 9, "appearance.skin": 9, "appearance.accent": 9}}')
check(#multi.errors == 3 and multi.errors[1].message:find("must be from 0 to 2"), "every bad value is reported, with the allowed range")
check(bad('{"kind": "beskar.appearance", "version": 1, "values": {"appearance.wallpaper-colours": 1}}').errors[1].message:find("true or false"), "bool message")
local flood = {}
for i = 1, 40 do flood[#flood + 1] = '"x' .. i .. '": 1' end
local fr = bad('{"kind": "beskar.appearance", "version": 1, "values": {' .. table.concat(flood, ",") .. '}}')
check(#fr.errors <= 14 and fr.errors[#fr.errors].code == "more", "error lists are bounded")
local big = {}
for i = 1, 400 do big[#big + 1] = '"k' .. i .. '": 1' end
bad('{"kind": "beskar.appearance", "version": 1, "values": {' .. table.concat(big, ",") .. '}}' .. string.rep(" ", AP.MAX_IMPORT_BYTES), "size:")

-- ── export + round trip ──
do
    local text, edoc = ictl.export(live)
    check(edoc.kind == "beskar.appearance" and edoc.version == 1 and edoc.values["appearance.accent"] == 3 and edoc.values["appearance.wallpaper-colours"] == true, "export document")
    check(next(edoc.values, next(edoc.values)) ~= nil and (function() local n = 0 for _ in pairs(edoc.values) do n = n + 1 end return n end)() == #P.APPEARANCE, "all supported appearance choices")
    check(not text:find("hour12") and not text:find("apps") and not text:find('"palette"', 1, true) and #text < 700, "only appearance choices, bounded")
    local back = parse(text)
    check(back.ok, "own export parses")
    for fact, v in pairs(P.appearance_snapshot(live).values) do check(back.values[fact] == v, "round trip " .. fact) end
    -- an export of a look with a palette still has none
    check(not parse(select(1, ictl.export(P.appearance_snapshot(live, pal)))).values.palette, "snapshot palette never leaves")
    local pre = ictl.preview_import(text, P.appearance_snapshot({ appearance = 1 }, nil))
    check(pre.ok and #pre.plan.changes == 5 and pre.target.palette == nil and pre.plan.restore_palette == nil, "round trip against another look")
end

-- a host-supplied encoder replaces the built-in one
do
    local used = 0
    local c = opened(nil, { encode = function(t) used = used + 1; return "ENC:" .. tostring(t.kind or t.version) end })
    check(c.export(live) == "ENC:beskar.appearance" and used == 1, "adapter.encode is used for exports")
    local c2, h2 = opened(nil, { encode = function(t) return "{\"version\": 1, \"stub\": true}" end })
    c2.save("x", live)
    check(h2.writes()[1].args[2] == "{\"version\": 1, \"stub\": true}", "adapter.encode is used for the store")
    local c3, h3 = opened(nil, { encode = function() error("boom") end })
    c3.save("x", live)
    check(#h3.writes() == 0 and c3.status().state == "failed" and c3.status().message:find("encode"), "a failing encoder is a failed save, not a crash")
end

-- ── preview, no changes, stage, apply ──
do
    local c, hh = opened(nil)
    local cur = P.appearance_snapshot({ appearance = 1, skin = 0, accent = 0, accent_auto = false, pal_style = 0 }, pal)
    local calls = #hh.calls

    local none = c.preview_import(good:gsub('"appearance.mode": 0', '"appearance.mode": 1'):gsub('"appearance.skin": 2', '"appearance.skin": 0'):gsub('"appearance.accent": 5', '"appearance.accent": 0'):gsub('"appearance.palette": 3', '"appearance.palette": 0'), cur)
    check(none.ok and none.noop and none.token == nil and none.message:find("No changes") and #none.plan.changes == 0, "an import with no changes says so")
    check(c.apply_import(1, cur).code == "no_preview" and not c.status().import_staged, "nothing staged for a no-op")

    local pre = c.preview_import(good, cur)
    check(pre.ok and not pre.noop and pre.token and #pre.plan.changes == 4 and pre.palette_refresh and pre.target.values.skin == 2, "a preview lists the changes")
    check(pre.plan.changes[1].from_label == "Dark" and pre.plan.changes[1].to_label == "Light", "labels for review")
    check(#hh.calls == calls and c.status().import_staged, "preview reads and writes nothing; it is staged")
    check(c.apply_import(pre.token + 1, cur).code == "no_preview", "wrong token")
    local pre2 = c.preview_import(good, cur)
    check(c.apply_import(pre.token, cur).code == "no_preview", "an older preview is superseded")
    local ap = c.apply_import(pre2.token, cur)
    check(ap.ok and ap.values.skin == 2 and ap.restore_palette == nil and P.snapshot_equal(ap.undo_snapshot, cur) and #ap.plan.changes == 4, "explicit apply returns the plan and ONE undo snapshot")
    check(c.apply_import(pre2.token, cur).code == "no_preview" and not c.status().import_staged, "a preview applies once")

    local pre3 = c.preview_import(good, cur)
    local drift = P.appearance_snapshot({ appearance = 2, skin = 0, accent = 0 }, pal)
    check(c.apply_import(pre3.token, drift).code == "stale", "a look that changed since the review is refused")
    check(c.apply_import(pre3.token, cur).code == "no_preview", "stale clears the stage")

    local pre4 = c.preview_import(good, cur)
    check(c.cancel_import() and not c.cancel_import() and c.apply_import(pre4.token, cur).code == "no_preview", "cancel")

    -- an invalid file changes nothing: a staged preview is also dropped
    local pre5 = c.preview_import(good, cur)
    local badr = c.preview_import('{"kind": "beskar.appearance", "version": 1, "values": {"appearance.mode": 8}}', cur)
    check(not badr.ok and #badr.errors == 1 and badr.message and not c.status().import_staged and c.apply_import(pre5.token, cur).code == "no_preview", "invalid files stage nothing")
    check(#hh.calls == calls, "imports never touch the file adapter")

    -- partial file: the choices it does not mention stay
    local part = c.preview_import('{"kind": "beskar.appearance", "version": 1, "values": {"appearance.accent": 4}}', cur)
    check(part.ok and #part.plan.changes == 1 and part.plan.values.skin == 0 and part.target.values.accent == 4 and part.palette_refresh, "partial import changes only what it names")
    local modeonly = c.preview_import('{"kind": "beskar.appearance", "version": 1, "values": {"appearance.mode": 0}}', cur)
    check(modeonly.ok and not modeonly.palette_refresh, "no palette refresh when colour choices did not change")
    check(c.preview_import(nil, cur).errors[1].code == "empty", "a nil file is an error result, not a crash")
end

-- importing a look into the store goes through the normal save
do
    local c, hh = opened(nil)
    local cur = P.appearance_snapshot({}, nil)
    local pre = c.preview_import(good, cur)
    local saved = c.save("Imported", pre.target.values, nil)
    check(saved.ok and saved.look.values.skin == 2 and not saved.look.has_palette, "an imported look can be saved by name")
end

-- ── status notices and the module's own limits ──
do
    local c, hh = opened(nil)
    local n = #hh.notices
    c.save("A", live)
    local after_save = #hh.notices
    check(after_save > n and hh.notices[#hh.notices].state == "saving", "saving is published")
    hh.finish(2, "", 0)
    check(hh.notices[#hh.notices].state == "ready" and hh.notices[#hh.notices].count == 1, "ready is published")
    local ready_count = #hh.notices
    c.rename("l1", "A")
    check(#hh.notices == ready_count, "an unchanged rename publishes nothing new")
end

do
    -- not loaded: every mutation says so, and open() twice reads once
    local hh = host()
    local c = AP.new(P, hh.adapter)
    check(c.save("x", live).code == "not_ready" and c.delete("l1").code == "not_ready" and c.status().state == "unloaded", "mutations before open are refused")
    c.open(); c.open()
    check(#hh.calls == 1 and c.status().state == "loading" and c.save("x", live).code == "not_ready", "open reads once; loading refuses mutations")
    hh.finish(1, "", 3)
    check(c.status().state == "ready", "ready after the read")
end

do
    -- the module is a controller only: no IO, no timers, no surfaces
    local f = assert(io.open("shell/appearance_profiles.luau"))
    local src = f:read("a"); f:close()
    local code = src:gsub("%-%-[^\n]*", ""):gsub("%[=%[.-%]=%]", "")
    for _, banned in ipairs({ "io%.", "os%.", "spawn", "sys%.", "timer%.", "%.after%(", "%.every%(", "loadstring", "require%(\"json\"%)", "surface%s*[:=({]", "[^%.%w_]run%(" }) do
        check(not code:find(banned), "controller does not use " .. banned)
    end
    check(src:find("adapter%.run"), "all IO goes through the host adapter")
end

print(string.format("appearance-profiles: %d checks passed", passed))
