-- Run only this suite: lua tests/settings-store.lua      (from the repository root)
--
-- Tests shell/settings_store.luau against a MOCKED adapter. Nothing here touches the live shell.
--
-- Assumptions (explicit, so a failing check can be judged against them):
--   A1. adapter.run(script, args, cb) is asynchronous; cb(out, code) fires later, once. These tests never fire it
--       on their own: every callback is drained by hand with finish(), in any order a test chooses.
--   A2. Read script contract: exit 0 + stdout = file text, 3 = file does not exist, anything else = unreadable.
--   A3. The write script is "atomic temp + mv"; exit 0 = saved, non-zero = the old file is untouched.
--   A4. adapter.value(kind, base) builds the document to write from the CURRENT facts (as settings.luau does);
--       base is the last value known to be on disk (so unknown keys survive).
--   A5. Settings calls load() once per kind at start-up and may call save() at any time afterwards, also before the
--       loads finished (a fast click) and while a write is in flight.
--   A6. One write in flight at a time, across all kinds (serialized), and saves made while one is in flight collapse
--       into ONE follow-up write carrying the newest facts (coalesced).
--   A7. A failed write is not retried by itself (no tight loop on a full disk): only a new save or retry() writes.
--   A8. corrupt / newer / unreadable documents are never overwritten, whatever the caller does.
-- Section 9 runs the two real shell scripts with a throw-away $HOME to prove the exit codes A2/A3 really hold.

package.path = "shell/?.luau;" .. package.path
local P = require("preferences")
local make_store = require("settings_store")

local passed, failures = 0, {}
local function check(v, why)
    if v then passed = passed + 1 else failures[#failures + 1] = why; print("  FAIL: " .. why) end
end
local section = ""
local function head(name) section = name; print("-- " .. name) end

-- ── a small strict JSON decoder (the scene passes pleamar's json.decode) ──
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

-- ── the harness: a mocked adapter whose callbacks are drained by hand ──
local FILE = { theme = "pleamar_shell.json", prefs = "beskar/prefs.json", palette = "beskar/palette.json" }
local KIND_OF = {}
for k, f in pairs(FILE) do KIND_OF[f] = k end

local function harness()
    local h = { pending = {}, log = {}, notes = {}, facts = {}, applied = {}, value_calls = {} }
    local adapter = {}
    function adapter.run(script, args, cb)
        local call = { script = script, args = args, cb = cb, file = args[1], seq = #h.log + 1 }
        call.is_write = script:find("mktemp", 1, true) ~= nil
        call.kind = KIND_OF[call.file]
        call.text = call.is_write and args[2] or nil
        h.log[#h.log + 1] = call
        h.pending[#h.pending + 1] = call
    end
    adapter.decode = decode
    adapter.notify = function(m) h.notes[#h.notes + 1] = m end
    -- A4: from the live facts, exactly as settings.luau does (palette extras are exercised in section 5)
    adapter.value = function(kind, base)
        h.value_calls[#h.value_calls + 1] = kind
        return P.from_facts(kind, h.facts, base)
    end
    h.store = make_store(P, adapter)

    function h.pend(filter)
        local out = {}
        for _, c in ipairs(h.pending) do
            if (filter == nil) or (filter == "write" and c.is_write) or (filter == "read" and not c.is_write) or filter == c.kind then
                out[#out + 1] = c
            end
        end
        return out
    end
    function h.writes_in_flight() return #h.pend("write") end
    function h.finish(call, out, code)
        for i, c in ipairs(h.pending) do
            if c == call then table.remove(h.pending, i); call.cb(out, code); return end
        end
        error("call is not pending")
    end
    function h.writes_issued() local n = 0; for _, c in ipairs(h.log) do if c.is_write then n = n + 1 end end; return n end
    function h.last_note() return h.notes[#h.notes] end
    -- load one kind and complete its read with `text` (nil text -> code 4, "" with code 3 = missing)
    function h.load(kind, how)
        h.store.load(kind, function(s)
            h.applied[#h.applied + 1] = s
            -- what Settings' apply does: facts take the loaded values
            for name, v in pairs(P.to_facts(kind, s.value)) do h.facts[name] = v end
        end)
        local call = h.pend("read")[#h.pend("read")]
        assert(call and call.kind == kind, "a read for " .. kind .. " is pending")
        if how == "missing" then h.finish(call, "", 3)
        elseif how == "unreadable" then h.finish(call, "", 4)
        elseif type(how) == "table" then h.finish(call, how.out, how.code)
        else h.finish(call, how, 0) end
        return h.store.state(kind)
    end
    function h.load_all(t)
        for _, k in ipairs(P.KINDS) do h.load(k, t and t[k] or "missing") end
    end
    return h
end

local function deep_equal(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for k, v in pairs(a) do if not deep_equal(v, b[k]) then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
end

---------------------------------------------------------------------------------------------------------------
head("1. loads are asynchronous: nothing is known, applied or writable until the read completes")
do
    local h = harness()
    for _, k in ipairs(P.KINDS) do h.store.load(k, function(s) h.applied[#h.applied + 1] = s end) end
    check(#h.pend("read") == 3 and #h.applied == 0, "three reads requested, nothing applied yet")
    check(h.store.state("theme") == nil and not h.store.ready(), "no state and not ready before any read completes")
    for _, c in ipairs(h.pend("read")) do
        check(c.args[1] == P.spec(c.kind).file and #c.args == 1, "read gets exactly the document's relative file: " .. tostring(c.args[1]))
        check(not c.script:find("mktemp", 1, true), "a read script never writes")
    end
    -- complete OUT OF ORDER: palette, theme, prefs
    local by = {}
    for _, c in ipairs(h.pend("read")) do by[c.kind] = c end
    h.finish(by.palette, '{"style": 2}', 0)
    check(#h.applied == 1 and h.applied[1].kind == "palette" and h.applied[1].value.style == 2, "apply fires per completion, in completion order")
    check(not h.store.ready(), "not ready while two kinds are still loading")
    h.finish(by.theme, "", 3)
    h.finish(by.prefs, '{"appearance": 0}', 0)
    check(h.store.ready(), "ready once all three are loaded and writable")
    check(h.store.state("prefs").value.appearance == 0 and h.store.state("theme").status == "missing", "states are kept per kind")
    check(h.writes_issued() == 0, "loading never writes")
end

---------------------------------------------------------------------------------------------------------------
head("2. an edit before the load completes must not reach disk ahead of what the file holds")
do
    local h = harness()
    h.store.load("prefs", function(s)
        h.applied[#h.applied + 1] = s
        for name, v in pairs(P.to_facts("prefs", s.value)) do h.facts[name] = v end
    end)
    h.facts.pref_seconds = true                         -- the user is quicker than the disk
    check(h.store.save("prefs") == true, "save before load is accepted (deferred)")
    check(h.writes_issued() == 0, "no write is issued before the file was read (it would erase unknown keys)")
    check(#h.value_calls == 0, "the document is not even built before the file is known")
    h.finish(h.pend("read")[1], '{"appearance": 0, "future_key": {"keep": [1, 2]}}', 0)
    local w = h.pend("write")[1]
    if w then
        local doc = decode(w.text)
        check(doc.future_key and doc.future_key.keep[2] == 2, "the deferred write still carries the unknown key read from disk")
        check(doc.appearance == 0, "...and the value read from disk")
    end
    -- OBSERVATION (not an assert): Settings' apply() runs before the deferred write and overwrites the facts, so the
    -- pre-load edit is lost and an otherwise pointless write follows. Report text shows what the user ended up with.
    print("   note: pre-load edit pref_seconds=true -> facts after apply: " .. tostring(h.facts.pref_seconds) ..
        "; writes issued after load: " .. h.writes_issued())

    -- a pre-load save against a protected file must be DROPPED, not replayed later after a repair
    local g = harness()
    g.facts.pref_seconds = true
    g.store.save("prefs")
    g.store.load("prefs", function() end)
    g.finish(g.pend("read")[1], "{ broken", 0)
    check(g.writes_issued() == 0, "pre-load save + corrupt file: nothing written")
    -- the user repairs the file and Settings reloads
    g.store.load("prefs", function() end)
    g.finish(g.pend("read")[1], '{"appearance": 2}', 0)
    check(g.writes_issued() == 0, "a stale pre-load save is not replayed after the file was repaired and reloaded")
end

---------------------------------------------------------------------------------------------------------------
head("3. serialized and coalesced writes")
do
    local h = harness()
    h.load_all()
    h.facts.skin, h.facts.pref_seconds, h.facts.pal_style = 2, true, 1
    check(h.store.save("theme") and h.store.save("prefs") and h.store.save("palette"), "three saves accepted")
    check(h.writes_in_flight() == 1 and h.writes_issued() == 1, "only ONE write in flight for three dirty kinds")
    check(h.pend("write")[1].kind == "theme", "KINDS order decides: theme first")
    check(decode(h.pend("write")[1].text).skin == 2, "the first write carries the saved value")
    h.finish(h.pend("write")[1], "", 0)
    check(h.writes_in_flight() == 1 and h.pend("write")[1].kind == "prefs", "completing one starts the next kind")
    check(h.pend("write")[1].file == "beskar/prefs.json", "prefs is written to its own file")
    h.finish(h.pend("write")[1], "", 0)
    check(h.writes_in_flight() == 1 and h.pend("write")[1].kind == "palette", "then palette")
    h.finish(h.pend("write")[1], "", 0)
    check(h.writes_in_flight() == 0 and h.writes_issued() == 3, "exactly one write per kind, then idle")
    check(h.last_note() == "", "idle store reports no status")

    -- coalescing: many saves while one write is in flight -> exactly one follow-up carrying the NEWEST facts
    local c = harness()
    c.load_all()
    c.facts.banner_i = 0
    c.store.save("prefs")
    local first = c.pend("write")[1]
    check(decode(first.text).banner_i == 0, "write 1 holds the value at save time")
    for v = 1, 3 do c.facts.banner_i = v; c.store.save("prefs") end
    check(c.writes_issued() == 1, "saves during a write issue no new run (coalesced)")
    check(c.writes_in_flight() == 1, "still one in flight")
    c.facts.banner_i = 2                                       -- final state differs from the last save's
    c.finish(first, "", 0)
    check(c.writes_issued() == 2, "exactly one follow-up for any number of queued saves")
    check(decode(c.pend("write")[1].text).banner_i == 2, "the follow-up is built when it starts, from the newest facts")
    c.finish(c.pend("write")[1], "", 0)
    check(c.writes_issued() == 2 and c.writes_in_flight() == 0, "nothing more is written")
    check(c.store.state("prefs").value.banner_i == 2, "state.value tracks the last successfully written document")

    -- an in-flight write for one kind does not swallow a save of the same kind made after it started
    local d = harness()
    d.load_all()
    d.facts.hour12 = false
    d.store.save("theme")
    local w1 = d.pend("write")[1]
    d.facts.hour12 = true
    d.store.save("theme")
    d.finish(w1, "", 0)
    check(decode(d.pend("write")[1].text).hour12 == true, "an edit made while the older write ran is not lost")

    -- status notifications: saving while busy, cleared at the end
    local s = harness()
    s.load_all()
    s.store.save("theme")
    check(s.last_note() == "Saving preferences…", "status says saving while a write is in flight")
    s.finish(s.pend("write")[1], "", 0)
    check(s.last_note() == "", "status is cleared when the queue drains")
end

---------------------------------------------------------------------------------------------------------------
head("4. a failed write is visible, not retried by itself, and retry() works")
do
    local h = harness()
    h.load_all({ prefs = '{"appearance": 2, "future": {"x": [1, 2, 3]}}' })
    h.facts.pref_tray = false
    h.store.save("prefs")
    local before = h.store.state("prefs").value
    h.finish(h.pend("write")[1], "disk full", 1)
    check(h.writes_in_flight() == 0 and h.writes_issued() == 1, "no automatic retry after a failure (no tight loop)")
    check((h.last_note() or ""):find("Could not save beskar/prefs.json", 1, true) ~= nil, "failure message names the file: " .. tostring(h.last_note()))
    check((h.last_note() or ""):find("previous file kept", 1, true) ~= nil, "failure message says the old file is kept")
    check(h.store.state("prefs").value == before and h.store.state("prefs").value.tray == true, "state.value keeps the last GOOD document on failure")
    check(h.store.ready(), "a failed save does not make the store unwritable")
    h.store.retry()
    check(h.writes_in_flight() == 1 and h.writes_issued() == 2, "retry() writes again")
    local doc = decode(h.pend("write")[1].text)
    check(doc.tray == false and doc.future.x[3] == 3 and doc.appearance == 2, "retry carries the current facts AND the unknown keys of the last good file")
    h.finish(h.pend("write")[1], "", 0)
    check(h.last_note() == "" and h.store.state("prefs").error == nil, "success clears the error")
    h.store.retry()
    check(h.writes_issued() == 2, "retry() with nothing failed writes nothing")

    -- a failing second retry stays failed with one write per retry
    local g = harness()
    g.load_all()
    g.store.save("theme"); g.finish(g.pend("write")[1], "", 1)
    for n = 1, 3 do
        g.store.retry()
        check(g.writes_in_flight() == 1, "retry " .. n .. " issues one write")
        g.finish(g.pend("write")[1], "", 1)
        check(g.writes_in_flight() == 0, "failed retry " .. n .. " does not loop")
    end
    check(g.writes_issued() == 4, "1 save + 3 retries = 4 writes")

    -- a fresh edit after a failure writes on its own, and then there is nothing left to retry
    local e = harness()
    e.load_all()
    e.store.save("theme"); e.finish(e.pend("write")[1], "", 1)
    e.facts.skin = 1
    e.store.save("theme")
    check(e.writes_in_flight() == 1, "a new edit after a failure writes immediately")
    e.finish(e.pend("write")[1], "", 0)
    e.store.retry()
    check(e.writes_issued() == 2, "after a later success nothing is left to retry")

    -- one failing kind must not block the others, and its message does not hide behind theirs
    local m = harness()
    m.load_all()
    m.store.save("theme"); m.store.save("prefs")
    m.finish(m.pend("write")[1], "", 1)                       -- theme fails
    check(m.writes_in_flight() == 1 and m.pend("write")[1].kind == "prefs", "the next kind is still written after a failure")
    m.finish(m.pend("write")[1], "", 0)
    check((m.last_note() or ""):find("pleamar_shell.json", 1, true) ~= nil, "the failed kind's error is still shown after another kind saved")
    m.store.save("palette"); m.finish(m.pend("write")[1], "", 1)
    check((m.last_note() or ""):find(" · ", 1, true) ~= nil and (m.last_note() or ""):find("palette.json", 1, true) ~= nil, "two failures are reported together")

    -- race: retry pressed twice before the first retry answers must not queue a duplicate write
    local r = harness()
    r.load_all()
    r.store.save("theme"); r.finish(r.pend("write")[1], "", 1)
    r.store.retry()
    r.store.retry()                                            -- impatient second click while the first is in flight
    r.finish(r.pend("write")[1], "", 0)
    check(r.writes_issued() == 2, "double retry() results in ONE retry write, not a duplicate (issued " .. r.writes_issued() .. ")")
end

---------------------------------------------------------------------------------------------------------------
head("5. protected documents are never overwritten: corrupt / newer / unreadable / empty")
local function protected_case(name, how, expect_status, expect_msg)
    local h = harness()
    h.facts.skin = 2
    local s = h.load("theme", how)
    check(s.status == expect_status, name .. ": status " .. expect_status .. " (got " .. tostring(s.status) .. ")")
    check(not s.writable, name .. ": not writable")
    check(h.store.save("theme") == false, name .. ": save() refuses")
    check(h.writes_issued() == 0, name .. ": no write issued by save()")
    h.store.retry()
    check(h.writes_issued() == 0, name .. ": retry() does not write it either")
    check(not h.store.ready(), name .. ": store is not ready")
    check(#h.applied == 1 and h.applied[1].status == expect_status, name .. ": apply still receives defaults/state exactly once")
    local note = h.last_note() or ""
    check(note:find("pleamar_shell.json", 1, true) ~= nil, name .. ": the user is told which file: " .. note)
    if expect_msg then check(note:find(expect_msg, 1, true) ~= nil, name .. ": message mentions '" .. expect_msg .. "': " .. note) end
    check(note:find("(nil)", 1, true) == nil, name .. ": message has no leaked 'nil'")
    -- the other documents keep working
    h.load("prefs", "missing")
    h.facts.pref_seconds = true
    check(h.store.save("prefs") and h.writes_in_flight() == 1 and h.pend("write")[1].kind == "prefs", name .. ": other kinds still save")
    check(h.pend("write")[1].file ~= "pleamar_shell.json", name .. ": and never the protected file")
    return h, s
end
protected_case("corrupt", "{ nope", "corrupt", "could not be read")
protected_case("array root", "[1, 2]", "corrupt", "could not be read")
protected_case("unreadable (exit 4)", { out = "", code = 4 }, "unreadable", "left as it is")
protected_case("unreadable (read crashed, exit 127)", { out = "sh: boom", code = 127 }, "unreadable", "left as it is")
protected_case("unreadable (nil output, exit 0)", { out = nil, code = 0 }, "unreadable", "left as it is")
do
    local _, s = protected_case("newer", '{"version": 7, "skin": 1, "from_the_future": {"a": [true]}}', "newer", "newer Beskar")
    check(s.value.version == 7 and s.value.skin == 1 and s.value.from_the_future.a[1] == true, "newer: values and unknown keys are read, version kept")
    -- an empty existing file is damaged, not "fresh" (a truncated write): protect it too
    protected_case("empty file", { out = "", code = 0 }, "corrupt", nil)
    protected_case("whitespace-only file", { out = " \n\t\n", code = 0 }, "corrupt", nil)
end
do
    -- a missing file (exit 3) is the ONE normal first-run case and is writable
    local h = harness()
    local s = h.load("theme", "missing")
    check(s.status == "missing" and s.writable and s.error == nil and (h.last_note() or "") == "", "missing: writable, no complaint")
    h.facts.skin = 1
    h.store.save("theme")
    local doc = decode(h.pend("write")[1].text)
    check(doc.version == 1 and doc.skin == 1 and doc.dark_mode == true, "missing: first save writes a versioned complete document")
    -- invalid keys are repaired by defaults, reported once, writable
    local g = harness()
    local t = g.load("prefs", '{"appearance": 9, "seconds": true}')
    check(t.status == "ok" and t.writable and (t.error or ""):find("1 invalid value", 1, true) ~= nil, "ok-with-issues is writable and noted: " .. tostring(t.error))
    g.facts.pref_seconds = true
    g.store.save("prefs")
    g.finish(g.pend("write")[1], "", 0)
    check(g.store.state("prefs").error == nil, "a successful save clears the load-time notice")
    -- a protected document that was loaded but then something else edits and a write for ANOTHER kind fails
    local k = harness()
    k.load("prefs", "{ broken")
    k.load("theme", "missing")
    k.store.save("theme"); k.finish(k.pend("write")[1], "", 1)
    k.store.retry()
    for _, c in ipairs(k.log) do check(not (c.is_write and c.kind == "prefs"), "retry never writes the protected kind") end
end

---------------------------------------------------------------------------------------------------------------
head("6. legacy documents round-trip with unknown keys")
do
    local h = harness()
    -- what start.sh / older code left behind: unversioned, partial, plus keys this build has never heard of
    local legacy_prefs = '{"appearance": 0, "banner_i": 3, "zz_future_size": 48, "future": {"list": [1, 2, {"deep": true}], "name": "it\'s \\"x\\"\\tend"}, "tags": ["a", "b"]}'
    local s = h.load("prefs", legacy_prefs)
    check(s.legacy and s.status == "ok" and s.writable and #s.issues == 0, "legacy file loads clean")
    check(table.concat(s.unknown, ",") == "future,tags,zz_future_size", "unknown names are listed")
    check(h.facts.banner_i == 3 and h.facts.appearance == 0, "known keys became facts")
    h.facts.pref_seconds = true                           -- the one change the user makes
    h.store.save("prefs")
    local w = h.pend("write")[1]
    check(not w.text:find("'", 1, true), "written text is safe for a single-quoted shell: no apostrophe")
    check(not w.text:find("\n", 1, true), "written text is one line")
    local doc = decode(w.text)
    check(doc.version == 1, "legacy file is upgraded with a version on write")
    check(doc.seconds == true and doc.appearance == 0 and doc.banner_i == 3, "changed + untouched known keys")
    check(doc.zz_future_size == 48 and doc.tags[2] == "b" and doc.future.list[3].deep == true, "unknown keys survive the write")
    check(doc.future.name == "it's \"x\"\tend", "unknown string with quote / apostrophe / tab survives byte for byte")
    check(doc.weather == true and doc.tray == true, "keys absent from the legacy file are written with their defaults")
    h.finish(w, "", 0)
    -- the written text is a fixed point: load it again and nothing changes
    local again = harness()
    local s2 = again.load("prefs", w.text)
    check(not s2.legacy and #s2.issues == 0 and table.concat(s2.unknown, ",") == "future,tags,zz_future_size", "re-reading what was written: versioned, clean, same unknown keys")
    again.store.save("prefs")
    check(again.pend("write")[1].text == w.text, "saving unchanged facts reproduces the identical text (stable round trip)")
    check(deep_equal(h.store.state("prefs").value.future, s2.value.future), "state.value after success equals what a fresh read gives")

    -- theme, as start.sh writes it (two keys only)
    local t = harness()
    t.load("theme", '{"dark_mode": false, "skin": 2}')
    t.facts.accent = 4
    t.store.save("theme")
    local td = decode(t.pend("write")[1].text)
    check(td.dark_mode == false and td.skin == 2 and td.accent == 4 and td.hour12 == true and td.version == 1, "legacy theme: kept choices, new choice, defaults for the rest")
    check(t.pend("write")[1].text:match('"dark_mode": *(%a*)') == "false" and t.pend("write")[1].text:match('"skin": *(%d*)') == "2", "start.sh grep patterns still match what we write")

    -- an invalid legacy value is replaced by the default, the neighbours stay
    local bad = harness()
    bad.load("prefs", '{"appearance": 7, "tray": false, "mystery": 1}')
    bad.facts.pref_seconds = true
    bad.store.save("prefs")
    local bd = decode(bad.pend("write")[1].text)
    check(bd.appearance == 1 and bd.tray == false and bd.mystery == 1, "invalid value -> default; valid neighbour and unknown key kept")

    -- palette keeps its colours when only the style changes, and mock value() adds PAL like settings.luau does
    local p = harness()
    local good = '{"style": 1, "src": "#AABBCC", "dark": {"a": "#112233", "b": "#445566", "s": "#778899"}, "light": {"a": "#ffffff", "b": "#eeeeee", "s": "#dddddd"}, "cache_note": "x"}'
    p.load("palette", good)
    p.facts.pal_style = 3
    p.store.save("palette")
    local pd = decode(p.pend("write")[1].text)
    check(pd.style == 3 and pd.src == "#aabbcc" and pd.dark.a == "#112233" and pd.light.s == "#dddddd" and pd.cache_note == "x", "palette: style change keeps cached colours and unknown keys")
end

---------------------------------------------------------------------------------------------------------------
head("7. the document is not shared with the caller (no aliasing between state and facts)")
do
    local h = harness()
    h.load_all({ prefs = '{"appearance": 2, "future": {"a": 1}}' })
    local s = h.store.state("prefs")
    local snapshot = deep_equal(s.value, P.normalize("prefs", { appearance = 2, future = { a = 1 } }))
    check(snapshot, "state.value is the normalised document")
    h.facts.appearance = 0
    check(h.store.state("prefs").value.appearance == 2, "changing a fact does not change the stored value before a successful save")
    h.store.save("prefs")
    h.facts.appearance = 1                                    -- changes after the write started
    h.finish(h.pend("write")[1], "", 0)
    check(h.store.state("prefs").value.appearance == 0, "state.value is what was WRITTEN (0), not what the facts say now (1)")
end

---------------------------------------------------------------------------------------------------------------
head("8. unusual completions")
do
    -- a write that reports exit 0 with no output is fine; non-number code is a failure
    local h = harness()
    h.load_all()
    h.store.save("theme")
    h.finish(h.pend("write")[1], nil, nil)
    check(h.store.state("theme").error ~= nil, "code == nil (adapter failure) is treated as a failed save, not as success")
    -- a save() for a kind that has an unrelated read still pending is deferred, not dropped
    local g = harness()
    g.store.load("theme", function() end)
    g.store.save("theme")
    check(g.writes_issued() == 0, "deferred while its read is pending")
    g.finish(g.pend("read")[1], '{"skin": 1}', 0)
    check(g.writes_issued() == 1, "the deferred save is issued once the read completed (it was not dropped)")
end

---------------------------------------------------------------------------------------------------------------
head("9. the real read / write scripts honour the exit-code contract (throw-away $HOME, real sh)")
do
    local ok_env = pcall(function() return io.popen end)
    local probe = ok_env and io.popen("command -v sh mktemp wc cp mv 2>/dev/null | wc -l")
    local have = probe and tonumber(probe:read("*a")) or 0
    if probe then probe:close() end
    if have < 5 then
        print("   skipped: sh toolchain not available")
    else
        local function q(s) return "'" .. tostring(s):gsub("'", "'\\''") .. "'" end
        local p = io.popen("mktemp -d")
        local home = p:read("*l"); p:close()
        assert(home and home ~= "" and home:find("^/"), "temporary HOME")
        local h = harness()
        h.load_all()
        h.store.save("prefs")
        local write_script = h.pend("write")[1].script
        h.finish(h.pend("write")[1], "", 0)
        h.store.load("prefs", function() end)
        local read_script = h.pend("read")[#h.pend("read")].script
        local function sh(script, ...)
            local args = { ... }
            for i, a in ipairs(args) do args[i] = q(a) end
            local cmd = string.format("cd %s && HOME=%s sh -c %s settings-store %s 2>/dev/null; echo \"::$?\"", q(home), q(home), q(script), table.concat(args, " "))
            local f = io.popen(cmd)
            local out = f:read("*a"); f:close()
            local body, code = out:match("^(.*)::(%d+)\n$")
            return body, tonumber(code)
        end
        -- setup / inspection helper: paths are ABSOLUTE inside the throw-away home, $HOME of this process is never used
        local function sh_ok(cmd) local f = io.popen("cd " .. q(home) .. " && " .. cmd .. " 2>/dev/null"); local o = f:read("*a"); f:close(); return o end
        local real = os.getenv("HOME")
        assert(real and home ~= real and not (real:find(home, 1, true)), "temporary home must not be the real one")
        local cfg = home .. "/.config"

        local _, code = sh(read_script, "beskar/prefs.json")
        check(code == 3, "read of a missing file exits 3 (got " .. tostring(code) .. ")")
        sh_ok("mkdir -p " .. cfg .. "/beskar/dirdoc.json")
        _, code = sh(read_script, "beskar/dirdoc.json")
        check(code == 4, "read of a directory exits 4 (unreadable), not 3 (got " .. tostring(code) .. ")")
        sh_ok("head -c 1048577 /dev/zero | tr '\\0' 'a' > " .. cfg .. "/big.json")
        _, code = sh(read_script, "big.json")
        check(code == 4, "a file above 1 MiB exits 4 (got " .. tostring(code) .. ")")
        sh_ok("ln -s " .. cfg .. "/nowhere " .. cfg .. "/dangling.json")
        _, code = sh(read_script, "dangling.json")
        check(code == 4, "a dangling symlink is unreadable (4), not 'missing' (got " .. tostring(code) .. ")")

        local text = '{"version": 1, "appearance": 0}'
        local _, wcode = sh(write_script, "beskar/prefs.json", text)
        check(wcode == 0, "write succeeds (got " .. tostring(wcode) .. ")")
        local body, rcode = sh(read_script, "beskar/prefs.json")
        check(rcode == 0 and body == text .. "\n", "read returns exactly what was written plus one newline")
        check(sh_ok("stat -c %a " .. cfg .. "/beskar/prefs.json"):match("^600") ~= nil, "document is private (0600)")
        check(sh_ok("ls " .. cfg .. "/beskar/prefs.json.bak 2>&1"):find("prefs.json.bak", 1, true) == nil, "first write: no .bak yet (nothing to back up)")
        sh(write_script, "beskar/prefs.json", '{"version": 1, "appearance": 2}')
        check(sh_ok("cat " .. cfg .. "/beskar/prefs.json.bak") == text .. "\n", "second write keeps the previous file as .bak")
        check(sh_ok("ls " .. cfg .. "/beskar | grep -c 'tmp'"):match("^0") ~= nil, "no temp files are left behind")
        -- unusual characters in the document never go through a shell parser
        local weird = '{"note": "it\\u0027s $(touch pwned) `x` \\"q\\""}'
        sh(write_script, "beskar/prefs.json", weird)
        check(sh_ok("cat " .. cfg .. "/beskar/prefs.json") == weird .. "\n", "shell metacharacters are written literally")
        check(sh_ok("ls " .. home .. "/pwned 2>&1; ls " .. cfg .. "/pwned 2>&1"):find("No such") ~= nil, "no command substitution happened")
        -- failure leaves the old file untouched and no temp file
        if sh_ok("id -u"):match("^0") then
            print("   skipped read-only directory case (running as root)")
        else
            sh_ok("chmod 500 " .. cfg .. "/beskar")
            local before = sh_ok("cat " .. cfg .. "/beskar/prefs.json")
            local _, c = sh(write_script, "beskar/prefs.json", '{"version": 1, "appearance": 1}')
            check(c ~= 0, "write into a read-only directory fails (code " .. tostring(c) .. ")")
            check(sh_ok("cat " .. cfg .. "/beskar/prefs.json") == before, "a failed write leaves the old file untouched")
            sh_ok("chmod 700 " .. cfg .. "/beskar")
        end
        os.execute("rm -rf " .. q(home))
    end
end

head("10. committed-write acknowledgements follow the serialized queue")
do
    local h, answers = harness(), {}
    h.load_all()
    h.facts.skin=2;h.store.save("theme");h.facts.pref_tray=false;h.store.save("prefs")
    h.store.flush(function(ok, why) answers[#answers+1]={ok,why} end)
    check(#answers==0,"flush waits while the first file is being written")
    h.finish(h.pend("write")[1],"",0)
    check(#answers==0,"a committed first file does not acknowledge pending preferences")
    h.finish(h.pend("write")[1],"",0)
    check(#answers==1 and answers[1][1] and h.store.state("prefs").value.tray==false,"acknowledge once after all pending files commit")
    h.store.save("theme");h.store.flush(function(ok,why) answers[#answers+1]={ok,why} end)
    h.finish(h.pend("write")[1],"disk full",1)
    check(#answers==2 and not answers[2][1] and answers[2][2]:find("Could not save"),"failed persistence never sends a successful ack")
    h.store.retry();h.store.flush(function(ok) answers[#answers+1]={ok} end)
    h.finish(h.pend("write")[1],"",0)
    check(#answers==3 and answers[3][1],"retry can be acknowledged after its new write commits")
    local g=harness();g.load_all({prefs="{broken"})
    local result
    g.store.flush(function(ok) result=ok end)
    check(result==false,"a protected preference document refuses commit acknowledgement")
end

print(string.format("settings-store: %d checks passed, %d failed", passed, #failures))
if #failures > 0 then
    for _, f in ipairs(failures) do print("  - " .. f) end
    os.exit(1)
end
