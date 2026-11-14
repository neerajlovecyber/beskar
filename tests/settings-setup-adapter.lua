-- Run only this suite for the Settings adapter of portable setup profiles: lua tests/settings-setup-adapter.lua
-- Everything is injected: a virtual filesystem behind host.run, fake owners with answer modes, a manual timer queue.
-- The adapter's own sh scripts are also run for real, in a throwaway HOME (section 12).
package.path = "shell/?.luau;" .. package.path
local P = require("preferences")
local SP = require("setup_profiles")
local passed = 0
local function check(v, why) if not v then error("FAILED: " .. tostring(why), 2) end passed = passed + 1 end

-- ── a small strict JSON decoder / encoder (the scene passes pleamar's json) ──
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

local function encode(v)
    local t = type(v)
    if t == "boolean" then return tostring(v) end
    if t == "number" then return v == math.floor(v) and string.format("%d", v) or tostring(v) end
    if t == "string" then return '"' .. v:gsub('[%c"\\]', function(c) return string.format("\\u%04x", c:byte()) end) .. '"' end
    local n, parts = 0, {}
    for _ in pairs(v) do n = n + 1 end
    if n > 0 and n == #v then
        for k = 1, #v do parts[k] = encode(v[k]) end
        return "[" .. table.concat(parts, ",") .. "]"
    end
    local keys = {}
    for k in pairs(v) do keys[#keys + 1] = k end
    table.sort(keys)
    for _, k in ipairs(keys) do parts[#parts + 1] = encode(k) .. ":" .. encode(v[k]) end
    return "{" .. table.concat(parts, ",") .. "}"
end

local function copy(v)
    if type(v) ~= "table" then return v end
    local t = {}
    for k, x in pairs(v) do t[k] = copy(x) end
    return t
end

-- ── a fake world of owners (same shape as tests/setup-profiles.lua) ──
local function new_world()
    return {
        app = { appearance = 1, skin = 0, accent = 0, accent_auto = false, pal_style = 0 },
        palette = { style = 0, src = "#336699", dark = { a = "#112233", b = "#223344", s = "#334455" }, light = { a = "#aabbcc", b = "#bbccdd", s = "#ccddee" } },
        frame = { bar_style = 0, pref_seconds = false, pref_weather = true, pref_tray = true, pref_workspaces = true, pref_bar_apps = true,
            pref_updates = true, dock_size_i = 1, dock_delay_i = 1, pref_dock_auto = true, bar_left_order = 0, bar_right_order = 0,
            module_output_policy = 0, dock_output_policy = 0, dock_show_delay = 0, frame_output_name = "" },
        pins = { "org.gnome.Nautilus", "kitty", "app:zed|/usr/bin/zed --new" },
        apps = { ["org.gnome.Nautilus"] = true, kitty = true, firefox = true },
        widgets = { snap = true, cards = {
            { id = 1, out = "DP-1", kind = 1, sz = 1, x = 48, y = 72, opts = { date = "off" } },
            { id = 2, out = "DP-1", kind = 3, sz = 0, x = 48, y = 248, stack = { id = 1, i = 1, on = true } },
            { id = 3, out = "DP-1", kind = 4, sz = 0, x = 48, y = 248, stack = { id = 1, i = 2 } },
            { id = 4, out = "HDMI-A-1", kind = 5, sz = 1, x = 48, y = 72 },
        } },
        outputs = { ["DP-1"] = true, ["HDMI-A-1"] = true },
    }
end

local function diff_world()
    local w = new_world()
    w.app.skin = 2
    w.frame.bar_style = 1
    w.pins = { "firefox", "app:local-tool|/opt/tool --x" }
    w.widgets = { snap = true, cards = { { id = 1, out = "DP-1", kind = 2, sz = 0, x = 400, y = 72 } } }
    return w
end

local function live_of(w)
    return {
        appearance = { values = copy(w.app), palette = copy(w.palette) },
        frame = { facts = copy(w.frame) },
        pins = { list = w.pins and copy(w.pins) or nil, apps = w.apps },
        widgets = { ready = true, snap = w.widgets.snap, cards = copy(w.widgets.cards) },
        outputs = { connected = w.outputs },
    }
end

local function owner_fp(w, section)
    local live = live_of(w)
    return SP.fingerprint(section, assert(SP.snapshot(section, live[section], { preferences = P })))
end

local function owner_apply(w, act)
    local section = act.section
    if not act.force and act.expect and owner_fp(w, section) ~= act.expect then
        return { ok = false, untouched = true, code = "stale" }
    end
    local data, errs = SP.validate_section(section, act.data, { preferences = P, local_pins = true })
    if not data then return { ok = false, untouched = true, code = "invalid", message = errs[1].message } end
    if section == "appearance" then
        for fact, v in pairs(SP.to_facts("appearance", data, { preferences = P })) do w.app[fact] = v end
        if act.data.palette then w.palette = copy(act.data.palette) end
    elseif section == "frame" then
        for fact, v in pairs(SP.to_facts("frame", data)) do w.frame[fact] = v end
    elseif section == "pins" then
        w.pins = data.default and nil or copy(data.list)
    else
        w.widgets = { snap = data.snap, cards = copy(data.cards) }
    end
    return { ok = true, fp = owner_fp(w, section) }
end

-- ── the fake host ────────────────────────────────────────────────
local REQ, RESP, JOURNAL = "setup-widget-request.json", "setup-widget-response.json", "setup-journal.json"

-- modes (per section or "widgets" / "read_pins"): ok | stale | nack | queue | silent | (widgets only) stale-id | oldfile |
-- silent_apply | queue_apply ; modes.not_ready = preferences not loaded
local function env(world, shared, modes)
    local E = { w = world, fs = shared or {}, handlers = {}, fact = {},
        text = { setup_document = "", setup_status = "", setup_banner = "", setup_lines_title = "" }, model = {}, notes = {}, said = {},
        held = {}, wheld = {}, timers = {}, tick = 0, tid = 0, modes = modes or {}, log = {}, writes = {}, fail_write = {} }
    local function after(ms, fn)
        E.tid = E.tid + 1
        E.timers[E.tid] = { at = E.tick + ms, fn = fn }
        return E.tid
    end
    local function cancel(id) E.timers[id] = nil end
    function E.live_timers() local n = 0 for _ in pairs(E.timers) do n = n + 1 end return n end
    function E.advance(ms)
        local target = E.tick + ms
        while true do
            local best, bid
            for id, t in pairs(E.timers) do if t.at <= target and (not best or t.at < best.at) then best, bid = t, id end end
            if not best then break end
            E.timers[bid] = nil
            E.tick = math.max(E.tick, best.at)
            best.fn()
        end
        E.tick = target
    end
    -- widgets (its own process: a request file in, a response file out, then an event)
    local function widgets_handle(id)
        local req = decode(E.fs[REQ])
        if req.id ~= id then return end
        local resp
        if req.kind == "snapshot" then
            local names = {}
            for n in pairs(world.outputs) do names[#names + 1] = n end
            table.sort(names)
            resp = { id = id, ok = true, data = { ready = true, snap = world.widgets.snap, cards = copy(world.widgets.cards), connected = names } }
        else
            E.log[#E.log + 1] = "widgets:" .. (req.force and "force" or "apply")
            local r = owner_apply(world, { section = "widgets", data = req.data, expect = req.expect, force = req.force })
            r.id = id
            resp = r
        end
        E.fs[RESP] = encode(resp)
        E.handlers.setup_widgets_reply(id)
    end
    function E.release_widgets(id) widgets_handle(id) end
    local function say(scene, words)
        E.said[#E.said + 1] = scene .. ":" .. words
        local id = tonumber(words:match("^emit setup_request (%d+)$"))
        if scene ~= "widgets" or not id then return end
        local mode = E.modes.widgets or "ok"
        if mode == "silent_apply" then mode = decode(E.fs[REQ]).kind == "apply" and "silent" or "ok" end
        if mode == "queue_apply" then mode = decode(E.fs[REQ]).kind == "apply" and "queue" or "ok" end
        for _, earlier in ipairs(E.wheld) do assert(earlier ~= id, "request ids are unique") end
        assert(E.fs[REQ] and decode(E.fs[REQ]).id == id, "the request file holds the request being announced")
        E.wheld[#E.wheld + 1] = id
        if mode == "ok" then widgets_handle(id)
        elseif mode == "stale-id" then E.handlers.setup_widgets_reply(id + 1)
        elseif mode == "oldfile" then
            E.fs[RESP] = encode({ id = id - 1, ok = true, data = { ready = true, cards = {} } })
            E.handlers.setup_widgets_reply(id)
        end
    end
    -- files
    local function run(script, args, cb, opts)
        local function answer(out, code) cb(out, code) end
        if script:find("mktemp", 1, true) then
            local name, len, body = args[1], tonumber(args[2]), args[3]
            if body == "-" then body = opts and opts.input or "" end
            E.writes[#E.writes + 1] = name
            local n = E.fail_write[name]
            if n and n > 0 then E.fail_write[name] = n - 1; return answer("", 1) end
            if E.fail_nth and name == JOURNAL then
                E.jcount = (E.jcount or 0) + 1
                if E.jcount == E.fail_nth then return answer("", 1) end
            end
            if #body ~= len then return answer("", 5) end
            E.fs[name] = body
            return answer("", 0)
        elseif script:find("unreadable", 1, true) then
            local name = args[1]
            if E.fs[name] == nil then return answer("", 3) end
            E.fs[name .. ".unreadable.1"] = E.fs[name]; E.fs[name] = nil
            return answer("", 0)
        else
            local name, max = args[1], tonumber(args[2])
            if E.fs[name] == nil then return answer("", 3) end
            if #E.fs[name] > max then return answer("", 4) end
            return answer(E.fs[name], 0)
        end
    end
    -- owners (settings and topbar)
    local function owner(kind, act, cb)
        local mode = E.modes[act.section] or "ok"
        E.log[#E.log + 1] = act.op .. ":" .. act.section
        if act.op == "rollback" then
            if E.rollback_fail and E.rollback_fail[act.section] then return cb({ ok = false, code = "write_failed", message = "disk full" }) end
            return cb(owner_apply(world, act))
        end
        if mode == "ok" then cb(owner_apply(world, act))
        elseif mode == "stale" then cb({ ok = false, untouched = true, code = "stale" })
        elseif mode == "nack" then cb({ ok = false, untouched = false, code = "write_failed", message = "disk full" })
        elseif mode == "queue" or mode == "silent" then E.held[#E.held + 1] = { act = act, cb = cb } end
    end
    local host = {
        fact = E.fact, text = E.text, model = E.model, decode = decode, encode = encode, after = after, cancel = cancel,
        on = function(name, fn) E.handlers[name] = fn end,
        ready = function() return E.ready ~= false and not E.modes.not_ready end,
        now = function() return 1000 end,
        live_settings = function() return { appearance = { values = copy(world.app), palette = copy(world.palette) }, frame = { facts = copy(world.frame) } } end,
        apply_settings = function(act, cb) owner("settings", act, cb) end,
        read_pins = function(cb)
            if E.modes.read_pins == "silent" then return end
            cb({ list = world.pins and copy(world.pins) or nil, apps = world.apps })
        end,
        apply_pins = function(act, cb) owner("topbar", act, cb) end,
        run = run, say = say,
        clipboard = function(body, cb) E.clip = body; cb(E.clip_ok ~= false) end,
        notify = function(m) E.notes[#E.notes + 1] = m end,
    }
    E.setup = require("settings_setup")(P, host)
    function E.emit(name, ...) assert(E.handlers[name], "no handler " .. name)(...) end
    function E.paste(doc) E.text.setup_document = doc; E.handlers["text:setup_document"]() end
    return E
end

local function section_doc(text) return decode(text).sections end

local function lines_text(E)
    local t = {}
    for _, l in ipairs(E.model.setup_lines or {}) do t[#t + 1] = l.text end
    return table.concat(t, "\n")
end

local function step_states(E)
    local t = {}
    for _, s in ipairs(E.model.setup_steps or {}) do t[#t + 1] = s.name .. "=" .. s.state end
    return table.concat(t, ",")
end

local function journal_state(E) return E.fs[JOURNAL] and decode(E.fs[JOURNAL]).state end

-- a document from the standard world, for the other machine
local source = env(new_world())
source.emit("setup_export")
local DOC = source.text.setup_document
check(DOC and DOC ~= "" and source.clip == DOC, "export fills the field and the clipboard")

-- ── 1. startup, no journal ───────────────────────────────────────
do
    local E = env(new_world())
    check(E.setup.state.phase == "none", "no journal: phase none")
    check(E.fact.setup_ready == true and E.fact.setup_busy == false and E.fact.setup_can_undo == false, "ready with nothing to undo")
    check(E.fact.setup_export_count == 4 and #E.model.setup_export_rows == 4, "four export rows, all chosen")
    check(E.live_timers() == 0, "idle: no timer, no polling")
    check(#E.writes == 0, "nothing is written at startup")
end

-- ── 2. export ────────────────────────────────────────────────────
do
    local E = env(new_world())
    E.emit("setup_export_toggle", 1); E.emit("setup_export_toggle", 4)
    check(E.fact.setup_export_count == 2 and E.model.setup_export_rows[1].on == false and E.model.setup_export_rows[2].on == true, "toggles")
    E.emit("setup_export")
    local d = section_doc(E.text.setup_document)
    check(d.frame and d.pins and not d.appearance and not d.widgets, "selective export: frame and pins only")
    check(#d.pins.list == 2 and not E.text.setup_document:find("zed") and not E.text.setup_document:find("app:"), "no window pin leaves")
    check(E.clip == E.text.setup_document and E.text.setup_status:find("copied"), "copied")
    check(lines_text(E):find("Included: Menu bar and dock") and lines_text(E):find("left out"), "report lines")
    check(E.fact.setup_busy == false and E.live_timers() == 0, "export ends cleanly")
    E.emit("setup_export_toggle", 2); E.emit("setup_export_toggle", 3)
    E.emit("setup_export_toggle", 9); E.emit("setup_export_toggle", "x")
    E.emit("setup_export")
    check(E.text.setup_status:find("Choose what"), "nothing chosen is reported")
    E.clip_ok = false; E.emit("setup_export_toggle", 1)
    E.emit("setup_export")
    check(E.text.setup_status:find("clipboard"), "clipboard failure leaves the text selectable")
end

-- export while widgets is down: bounded wait, section left out with the reason
do
    local E = env(new_world())
    E.modes.widgets = "silent"
    E.emit("setup_export")
    check(E.fact.setup_busy == true and E.text.setup_document == "", "waiting for widgets")
    E.emit("setup_export")                                  -- a second press while busy does nothing harmful
    check(E.text.setup_status:find("still running"), "busy refuses a second step")
    E.advance(3000)
    check(E.fact.setup_busy == false and E.text.setup_document ~= "", "the snapshot timed out")
    local d = section_doc(E.text.setup_document)
    check(d.appearance and d.pins and not d.widgets, "widgets left out")
    check(lines_text(E):find("Left out: Widgets") and lines_text(E):find("did not answer in time"), "reason shown")
    check(E.model.setup_export_rows[4].sub:find("Not available"), "row shows the section is unavailable")
    check(E.live_timers() == 0, "no timer left over")
end

-- preferences not loaded: appearance and frame are reported, not invented
do
    local E = env(new_world())
    E.ready = false
    E.emit("setup_export")
    local d = section_doc(E.text.setup_document)
    check(not d.appearance and not d.frame and d.pins and d.widgets, "settings sections left out while preferences load")
    check(lines_text(E):find("Preferences are still loading"), "says why")
end

-- ── 3. review ────────────────────────────────────────────────────
do
    local E = env(diff_world())
    E.emit("setup_review_import")
    check(E.text.setup_status:find("Paste"), "empty field")
    E.paste("not json")
    E.emit("setup_review_import")
    check(E.fact.setup_reviewing == false and (lines_text(E):find("not a Beskar setup") or lines_text(E):find("JSON")), "garbage is refused with a message")
    check(E.text.setup_lines_title == "Cannot import", "title")
    local bad_doc, n_sub = DOC:gsub('"appearance.mode": ?1', '"appearance.mode": 7')
    check(n_sub == 1, "test document edited")
    E.paste(bad_doc)
    E.emit("setup_review_import")
    check(not E.fact.setup_reviewing and lines_text(E):find("must be from"), "out of range value named")
    E.paste(DOC)
    E.emit("setup_review_import")
    check(E.fact.setup_reviewing == true and E.fact.setup_review_count == 4 and #E.model.setup_review_rows == 4, "review with four sections")
    local text = lines_text(E)
    check(text:find("Appearance — %d+ change") and text:find("Menu bar style: Strip → Notch") and text:find("Widget desktop"), "review lines")
    check(#E.model.setup_lines <= 16, "bounded lines")
    E.emit("setup_review_toggle", 3); E.emit("setup_review_toggle", 3)
    check(E.fact.setup_review_count == 4, "toggle twice")
    E.emit("setup_review_toggle", 3)
    check(E.fact.setup_review_count == 3 and E.model.setup_review_rows[3].on == false, "toggle off")
    E.emit("setup_cancel")
    check(not E.fact.setup_reviewing and #E.model.setup_review_rows == 0 and E.fact.setup_has_lines == false, "cancel")
    -- editing the field discards the review
    E.paste(DOC); E.emit("setup_review_import"); check(E.fact.setup_reviewing, "again")
    E.paste(DOC .. " ")
    check(not E.fact.setup_reviewing, "editing the field clears the review")
    -- same machine: no-op
    local same = env(new_world())
    same.paste(DOC); same.emit("setup_review_import")
    check(not same.fact.setup_reviewing and same.text.setup_status:find("No changes"), "identical setup is a no-op")
    -- a section whose owner cannot answer
    local down = env(diff_world())
    down.modes.read_pins = "silent"
    down.paste(DOC); down.emit("setup_review_import"); down.advance(3000)
    check(not down.fact.setup_reviewing and down.text.setup_status:find("Pinned apps cannot be reviewed"), "owner down: reported")
    check(lines_text(down):find("The dock did not answer"), "with the reason")
end

-- ── 4. apply, steps, journal, undo ───────────────────────────────
local function applied_env()
    local E = env(diff_world())
    E.paste(DOC); E.emit("setup_review_import")
    check(E.fact.setup_reviewing, "reviewing")
    E.emit("setup_apply")
    return E
end

do
    local E = applied_env()
    check(E.fact.setup_running == false and E.text.setup_status:find("applied"), "applied: " .. tostring(E.text.setup_status))
    check(journal_state(E) == "done", "journal on disk is done")
    check(step_states(E) == "Appearance=Applied,Menu bar and dock=Applied,Pinned apps=Applied,Widgets=Applied", "steps: " .. step_states(E))
    check(E.fact.setup_can_undo == true and E.fact.setup_ready == true and not E.fact.setup_reviewing, "undo available")
    check(E.w.app.skin == 0 and E.w.frame.bar_style == 0, "settings applied")
    check(E.w.pins[1] == "org.gnome.Nautilus" and E.w.pins[2] == "kitty" and E.w.pins[3]:find("^app:local%-tool"), "imported pins + the local window pin kept")
    check(#E.w.widgets.cards == 4 and E.w.widgets.cards[2].stack.on == true, "widgets applied through the bridge")
    check(#E.wheld >= 2, "snapshot then apply, each announced after its file was written")
    local req = decode(E.fs[REQ])
    check(req.kind == "apply" and req.expect and req.force == false and math.type(req.id) == "integer" and req.id >= 1 and req.id <= 16777215, "request shape and 24-bit id (event payloads are f32)")
    check(E.live_timers() == 0, "no timers left")
    check(E.notes[#E.notes]:find("applied"), "notified")
    -- a later restart sees the finished journal and still offers undo
    local B = env(E.w, E.fs)
    check(B.setup.state.phase == "ok" and B.fact.setup_can_undo == true, "undo survives a restart")
    -- undo
    E.emit("setup_undo")
    check(E.text.setup_status:find("undone"), "undo status: " .. tostring(E.text.setup_status))
    check(E.w.app.skin == 2 and E.w.frame.bar_style == 1 and #E.w.pins == 2 and E.w.pins[1] == "firefox" and #E.w.widgets.cards == 1, "undone everywhere")
    check(E.fact.setup_can_undo == false and journal_state(E) == "done", "undo spent")
    E.emit("setup_undo")
    check(E.text.setup_status:find("no setup to undo") or E.text.setup_status:find("Nothing"), "second undo refused")
end

-- stale undo: a section changed after the apply; skip it explicitly
do
    local E = applied_env()
    E.w.frame.bar_style = 1                                 -- changed by hand after the setup
    E.emit("setup_undo")
    check(E.fact.setup_stale_undo == true and E.text.setup_status:find("would overwrite"), "stale undo refused")
    check(E.w.app.skin == 0, "nothing was undone")
    check(lines_text(E):find("Menu bar and dock changed"), "names the section")
    E.emit("setup_undo_skip")
    check(E.w.app.skin == 2 and E.w.frame.bar_style == 1 and #E.w.widgets.cards == 1, "the others were undone, the changed one kept")
    check(E.text.setup_status:find("Left as they are"), "says what stayed")
    check(E.fact.setup_stale_undo == false, "flag cleared")
end

-- ── 5. owner failures ────────────────────────────────────────────
do   -- stale at the second owner: the first one is put back
    local E = env(diff_world())
    E.modes.frame = "stale"
    E.paste(DOC); E.emit("setup_review_import"); E.emit("setup_apply")
    check(E.text.setup_status:find("put back") and E.text.setup_status:find("Menu bar and dock changed"), "stale: " .. tostring(E.text.setup_status))
    check(E.w.app.skin == 2 and E.w.frame.bar_style == 1 and E.w.widgets.cards[1].kind == 2, "everything as before")
    check(journal_state(E) == "rolled_back" and E.fact.setup_can_undo == false and E.fact.setup_attention == false, "rolled back journal")
    check(table.concat(E.log, ","):find("rollback:appearance"), "forced rollback sent")
end

do   -- an owner that never answers: timeout, rollback, late answer ignored
    local E = env(diff_world())
    E.modes.pins = "silent"
    E.paste(DOC); E.emit("setup_review_import"); E.emit("setup_apply")
    check(E.fact.setup_running == true and step_states(E):find("Pinned apps=Applying"), "waiting on pins")
    check(E.live_timers() == 1, "one guard timer")
    E.advance(9999)
    check(E.fact.setup_running == true, "not yet")
    E.advance(2)
    check(E.fact.setup_running == false and E.text.setup_status:find("put back"), "timeout rolled back: " .. tostring(E.text.setup_status))
    check(E.w.app.skin == 2 and E.w.frame.bar_style == 1, "settings restored")
    local held = table.remove(E.held, 1)
    held.cb({ ok = true })                                   -- the late answer
    check(E.fact.setup_running == false and journal_state(E) == "rolled_back", "late ack ignored")
    check(E.live_timers() == 0, "no timer left")
end

do   -- widgets never answers an apply (nor its forced rollback)
    local E = env(diff_world())
    E.paste(DOC); E.emit("setup_review_import")
    E.modes.widgets = "silent_apply"                        -- the snapshot answers: only the apply goes unanswered
    E.emit("setup_apply")
    check(E.fact.setup_running == true, "waiting on widgets")
    E.advance(10001)
    check(E.fact.setup_running == true and step_states(E):find("Widgets=Putting back"), "the forced rollback of widgets is asked next")
    E.advance(10001)                                         -- widgets is still silent: that rollback times out too
    check(E.fact.setup_running == false and E.fact.setup_attention == true and E.w.app.skin == 2 and E.w.pins[1] == "firefox",
        "the other sections were put back; widgets needs attention")
    check(lines_text(E):find("Widgets could not be restored"), "names the section: " .. lines_text(E))
end

do   -- a nack
    local E = env(diff_world())
    E.modes.pins = "nack"
    E.paste(DOC); E.emit("setup_review_import"); E.emit("setup_apply")
    check(E.text.setup_status:find("Pinned apps could not be applied: disk full"), "nack message: " .. tostring(E.text.setup_status))
    check(E.w.app.skin == 2, "put back")
end

-- ── 6. journal write failures ────────────────────────────────────
do   -- before anything was sent: nothing changes
    local E = env(diff_world())
    E.paste(DOC); E.emit("setup_review_import")
    E.fail_write[JOURNAL] = 1
    E.emit("setup_apply")
    check(E.fact.setup_running == false and E.text.setup_status:find("not applied"), "first journal write fails: " .. tostring(E.text.setup_status))
    check(E.w.app.skin == 2 and #E.log == 0, "no owner touched")
end

do   -- after a step was marked sent: blocked, then Retry
    local E = env(diff_world())
    E.paste(DOC); E.emit("setup_review_import")
    E.fail_nth = 2
    E.emit("setup_apply")
    check(E.fact.setup_blocked == true and E.fact.setup_running == true, "blocked")
    check(E.text.setup_banner:find("recovery journal"), "banner says why: " .. E.text.setup_banner)
    check(#E.log == 0 and E.w.app.skin == 2, "no owner is touched before its sent entry is on disk")
    E.emit("setup_retry")
    check(E.fact.setup_blocked == false and E.text.setup_status:find("applied"), "retry continues: " .. tostring(E.text.setup_status))
    check(E.w.app.skin == 0, "applied after retry")
end

do   -- a journal too large for an argument goes through stdin and still lands whole
    local E = env(new_world())
    local big = string.rep("x", 70000)
    local result
    E.setup.write_file(JOURNAL, big, function(ok) result = ok end)
    check(result == true and E.fs[JOURNAL] == big, "large text written whole through stdin")
    local small = "{}"
    E.setup.write_file(JOURNAL, small, function(ok) result = ok end)
    check(result == true and E.fs[JOURNAL] == small, "small text through the argument")
    check(E.setup.scripts.write:find('cat > "$t"', 1, true) and E.setup.scripts.write:find('-eq "$2"', 1, true), "the script verifies the length")
    E.setup.write_file(JOURNAL, "", function(ok) result = ok end)
    check(result == false, "an empty text is never written")
end

do   -- the review goes stale when something changes before Apply
    local E = env(diff_world())
    E.paste(DOC); E.emit("setup_review_import")
    check(E.fact.setup_reviewing, "reviewing")
    E.w.frame.pref_tray = false                              -- changed by hand after the review
    E.emit("setup_apply")
    check(E.text.setup_status:find("changed since the review") and not E.fact.setup_reviewing and #E.log == 0, "stale review: " .. tostring(E.text.setup_status))
    check(E.fact.setup_running == false and E.fact.setup_ready == true and E.w.app.skin == 2, "nothing changed, still usable")
    E.emit("setup_apply")
    check(E.text.setup_status:find("Review a setup first"), "apply without a review")
end

do   -- apply with nothing chosen, then one section only
    local E = env(diff_world())
    E.paste(DOC); E.emit("setup_review_import")
    for i = 1, 4 do E.emit("setup_review_toggle", i) end
    check(E.fact.setup_review_count == 0, "all off")
    E.emit("setup_apply")
    check(E.text.setup_status:find("at least one") and E.w.app.skin == 2, "refused")
    E.emit("setup_review_toggle", 2)
    E.emit("setup_apply")
    check(E.w.frame.bar_style == 0 and E.w.app.skin == 2, "only the chosen section applied")
    check(step_states(E) == "Menu bar and dock=Applied", "one step: " .. step_states(E))
end

do   -- exporting then importing the same machine's setup is a no-op, not a review
    local E = env(diff_world())
    E.emit("setup_export")
    E.emit("setup_review_import")
    check(E.fact.setup_reviewing == false, "own export reviews as no changes")
end

-- ── 7. widgets bridge ────────────────────────────────────────────
do
    local E = env(new_world())
    E.modes.widgets = "stale-id"                             -- an event for another id
    E.emit("setup_export")
    check(E.fact.setup_busy == true, "a foreign reply is ignored")
    E.advance(3000)
    check(E.fact.setup_busy == false and lines_text(E):find("Left out: Widgets"), "then the snapshot times out")
    local E2 = env(new_world())
    E2.modes.widgets = "oldfile"                             -- the right event, an older response file
    E2.emit("setup_export"); E2.advance(3000)
    check(lines_text(E2):find("Left out: Widgets"), "an older response file is not accepted")
    -- late reply to a timed-out request, then a fresh request
    local E3 = env(new_world())
    E3.modes.widgets = "queue"
    E3.emit("setup_export"); E3.advance(3000)
    local old = E3.wheld[1]
    check(E3.fact.setup_busy == false, "timed out")
    E3.emit("setup_export")
    local new = E3.wheld[2]
    check(new and new ~= old, "unique ids")
    E3.release_widgets(old)
    check(E3.fact.setup_busy == true, "the late reply of the first request does not answer the second")
    E3.release_widgets(new)
    check(E3.fact.setup_busy == false and section_doc(E3.text.setup_document).widgets, "the right reply does")
    check(math.type(new) == "integer" and new >= 1 and new <= 16777215, "bounded ids")
end

-- ── 8. interrupted setups at startup ─────────────────────────────
local function interrupted(mode_for)
    local E = env(diff_world())
    for k, v in pairs(mode_for) do E.modes[k] = v end
    E.paste(DOC); E.emit("setup_review_import"); E.emit("setup_apply")
    return E
end

do   -- crashed with pins in flight: appearance and frame applied
    local A = interrupted({ pins = "queue" })
    check(A.fact.setup_running and journal_state(A) == "running", "mid-flight journal")
    local B = env(A.w, A.fs)
    check(B.setup.state.phase == "recovery" and B.fact.setup_recovery == true, "recovery at startup")
    check(B.text.setup_banner:find("interrupted") and B.text.setup_banner:find("Appearance: changed"), "banner: " .. B.text.setup_banner)
    check(step_states(B):find("Appearance=Changed") and step_states(B):find("Widgets=Unchanged"), "rows: " .. step_states(B))
    check(B.fact.setup_ready == false, "apply gated")
    B.paste(DOC); B.emit("setup_review_import")
    if B.fact.setup_reviewing then
        B.emit("setup_apply")
        check(B.text.setup_status:find("Finish the interrupted setup"), "apply refused while recovery is pending")
    end
    B.emit("setup_undo")
    check(B.text.setup_status:find("Finish the interrupted"), "undo refused too")
    check(journal_state(B) == "running", "journal untouched until the user chooses")
    B.emit("setup_recover_rollback")
    check(B.fact.setup_running == false and B.fact.setup_recovery == false and B.w.app.skin == 2 and B.w.frame.bar_style == 1, "rolled back")
    check(journal_state(B) == "rolled_back", "journal closed: " .. tostring(journal_state(B)))
    check(B.fact.setup_ready == true, "ready again")
    local C = env(A.w, A.fs)
    check(C.setup.state.phase == "ok", "a closed journal needs nothing")
end

do   -- keep the current state
    local A = interrupted({ pins = "queue" })
    local B = env(A.w, A.fs)
    check(B.fact.setup_recovery == true, "recovery")
    B.emit("setup_recover_keep")
    check(journal_state(B) == "abandoned" and B.w.app.skin == 0 and B.fact.setup_ready, "kept")
end

do   -- the owner never received anything: only needs closing
    local A = interrupted({ appearance = "silent" })
    check(journal_state(A) == "running", "journal says sent")
    local B = env(A.w, A.fs)
    check(B.fact.setup_recovery == true and B.fact.setup_recovery_clean == true, "nothing changed: clean")
    check(B.text.setup_banner:find("before it changed anything"), "says so")
    B.emit("setup_recover_keep")
    check(journal_state(B) == "abandoned" and B.fact.setup_ready == true, "closed")
end

do   -- widgets not answering at startup: wait, then Check again
    local A = interrupted({ widgets = "queue_apply" })
    check(journal_state(A) == "running" and step_states(A):find("Widgets=Applying"), "widgets step in flight")
    local B = env(A.w, A.fs, { widgets = "silent" })
    B.advance(3000)
    check(B.setup.state.phase == "waiting" and B.fact.setup_waiting == true and B.fact.setup_ready == false, "waiting for widgets")
    check(B.text.setup_banner:find("Waiting") and B.text.setup_banner:find("Check again"), "banner: " .. B.text.setup_banner)
    check(journal_state(B) == "running", "nothing decided, nothing written")
    B.modes.widgets = "ok"
    B.emit("setup_recheck")
    check(B.setup.state.phase == "recovery" and B.fact.setup_recovery == true, "after Check again: recovery")
    check(step_states(B):find("Widgets=Changed") or step_states(B):find("Widgets=Unchanged"), "widgets row: " .. step_states(B))
end

do   -- preferences still loading: the reconcile waits for poke()
    local A = interrupted({ pins = "queue" })
    local B = env(A.w, A.fs, { not_ready = true })
    check(B.setup.state.phase == "waiting" and B.fact.setup_waiting == true, "preferences not ready: waiting, nothing decided")
    local jw = 0
    for _, n in ipairs(B.writes) do if n == JOURNAL then jw = jw + 1 end end
    check(journal_state(B) == "running" and jw == 0, "the journal is not touched")
    B.modes.not_ready = nil
    B.setup.poke()
    check(B.setup.state.phase == "recovery" and B.fact.setup_recovery == true, "poke after preferences load: " .. tostring(B.setup.state.phase))
end

-- ── 9. unreadable / newer journals are never overwritten ─────────
do
    for _, bad in ipairs({ "garbage", '{"kind":"beskar.setup-journal","version":99,"id":"1-1","op":"apply","state":"running","steps":[]}',
        encode({ kind = "beskar.setup", version = 1 }) }) do
        local fs = { [JOURNAL] = bad }
        local E = env(diff_world(), fs)
        check(E.setup.state.phase == "unreadable" and E.fact.setup_unreadable == true and E.fact.setup_ready == false, "unreadable: " .. bad:sub(1, 20))
        check(E.text.setup_banner:find("Nothing was changed") and E.text.setup_banner:find("Move it aside"), "banner")
        E.paste(DOC); E.emit("setup_review_import")
        E.emit("setup_apply")
        check(fs[JOURNAL] == bad and #E.log == 0, "never overwritten, never applied")
        E.emit("setup_export"); check(E.text.setup_document:find("beskar.setup"), "export still works")
        E.emit("setup_aside")
        check(E.text.setup_status:find("Press Move aside again") and fs[JOURNAL] == bad, "first press arms")
        E.emit("setup_aside")
        check(fs[JOURNAL] == nil and fs[JOURNAL .. ".unreadable.1"] == bad, "kept as a copy, not deleted")
        check(E.setup.state.phase == "none" and E.fact.setup_ready == true, "ready afterwards")
    end
    local fs = { [JOURNAL] = string.rep("a", 140000) }
    local E = env(diff_world(), fs)
    check(E.setup.state.phase == "unreadable", "oversized journal")
end

-- ── 10. a failed rollback needs attention ────────────────────────
do
    local E = env(diff_world())
    E.modes.frame = "stale"
    E.rollback_fail = { appearance = true }
    E.paste(DOC); E.emit("setup_review_import"); E.emit("setup_apply")
    check(E.fact.setup_attention == true and E.fact.setup_running == false, "attention")
    check(E.text.setup_lines_title == "Needs attention" and lines_text(E):find("could not be restored"), "lines: " .. lines_text(E))
    check(journal_state(E) == "rollback_failed", "journal says so")
    check(E.fact.setup_ready == false, "gated")
    E.emit("setup_dismiss")
    check(E.fact.setup_has_lines == true, "dismiss does not hide an open problem")
    local calls = #E.log
    E.paste(DOC); E.emit("setup_review_import"); E.emit("setup_apply")
    check(#E.log == calls, "no new apply while attention is pending")
    -- restart: offered as an interrupted rollback
    local B = env(E.w, E.fs)
    check(B.fact.setup_recovery == true and B.text.setup_banner:find("could not be fully put back"), "after a restart: " .. B.text.setup_banner)
    -- retry works once the owner is fine
    E.rollback_fail = nil
    E.emit("setup_retry_rollback")
    check(E.fact.setup_attention == false and E.w.app.skin == 2 and journal_state(E) == "rolled_back", "retry put it back")
end

do
    local E = env(diff_world())
    E.modes.frame = "stale"
    E.rollback_fail = { appearance = true }
    E.paste(DOC); E.emit("setup_review_import"); E.emit("setup_apply")
    E.emit("setup_accept")
    check(E.fact.setup_attention == false and journal_state(E) == "abandoned" and E.fact.setup_ready == true, "accept current state")
end

-- ── 11. bounds ───────────────────────────────────────────────────
do
    local E = applied_env()
    check(#E.model.setup_lines <= 16 and #E.model.setup_steps <= 4 and #E.model.setup_export_rows <= 4 and #E.model.setup_review_rows <= 4, "model sizes")
    check(#E.text.setup_status <= 230 and #E.text.setup_banner <= 270, "text sizes")
    -- hide is refused while an apply runs
    local R = env(diff_world())
    R.modes.pins = "silent"
    R.paste(DOC); R.emit("setup_review_import"); R.emit("setup_apply")
    R.emit("setup_show"); R.emit("setup_hide")
    check(R.fact.setup_open == true, "cannot close the page mid-apply")
    R.advance(10001)
    R.emit("setup_hide")
    check(R.fact.setup_open == false, "closes afterwards")
    check(R.live_timers() == 0, "no timers")
end

-- ── 12. the shell scripts, for real, in a throwaway HOME ─────────
do
    local function sh(cmd) local p = io.popen(cmd .. " 2>&1; echo \"__$?\""); local o = p:read("a"); p:close(); return o end
    local tmp = sh("mktemp -d"):match("^(.-)\n")
    local scripts = env(new_world()).setup.scripts
    local function save(name, body) local f = assert(io.open(tmp .. "/" .. name, "w")); f:write(body); f:close() end
    save("w.sh", scripts.write); save("r.sh", scripts.read); save("a.sh", scripts.aside)
    local function run(script, ...)
        local args = {}
        for _, a in ipairs({ ... }) do args[#args + 1] = "'" .. a .. "'" end
        local out = sh("HOME='" .. tmp .. "/home' sh '" .. tmp .. "/" .. script .. "' " .. table.concat(args, " "))
        return out:match("^(.*)__(%d+)\n$")
    end
    local out, code = run("w.sh", "setup-journal.json", "5", "hello")
    check(code == "0", "write: " .. tostring(out))
    out, code = run("r.sh", "setup-journal.json", "100")
    check(code == "0" and out == "hello", "read back")
    out, code = run("w.sh", "setup-journal.json", "9", "hello")
    check(code == "5", "a length mismatch fails and ...")
    out, code = run("r.sh", "setup-journal.json", "100")
    check(out == "hello", "... leaves the old file")
    out, code = run("r.sh", "setup-journal.json", "3")
    check(code == "4", "too large to read")
    out, code = run("r.sh", "missing.json", "100")
    check(code == "3", "missing is 3")
    check(sh("ls '" .. tmp .. "/home/.config/beskar' | grep -c tmp"):match("^0"), "no temp file left")
    local big = string.rep("y", 100000)
    local p = io.popen("HOME='" .. tmp .. "/home' sh '" .. tmp .. "/w.sh' setup-journal.json " .. #big .. " - ", "w")
    p:write(big); p:close()
    out, code = run("r.sh", "setup-journal.json", "200000")
    check(#out == 100000, "stdin write lands whole")
    sh("ln -s '" .. tmp .. "/w.sh' '" .. tmp .. "/home/.config/beskar/link.json'")
    out, code = run("r.sh", "link.json", "100")
    check(code == "4", "a symlink is refused")
    out, code = run("a.sh", "setup-journal.json")
    check(code == "0" and sh("ls '" .. tmp .. "/home/.config/beskar'"):find("setup%-journal.json.unreadable."), "aside keeps a copy")
    out, code = run("a.sh", "setup-journal.json")
    check(code == "3", "aside of nothing")
    sh("rm -rf '" .. tmp .. "'")
end

print(string.format("settings-setup-adapter: %d checks passed", passed))
