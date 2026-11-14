-- Settings adapter for portable setup profiles (C5): selective export, strict review / import, the Apply pump over the
-- pure controller (setup_profiles.luau), asynchronous owner acknowledgements with a timeout, Undo, startup
-- reconciliation of an interrupted setup and explicit recovery. It owns NO surface, service watcher or polling loop:
-- every timer here is a one-shot guard of a request in flight (10 s per apply, 3 s per snapshot) and is cancelled when
-- the answer arrives. All file IO goes through host.run. Tests: lua tests/settings-setup.lua
--
--   local setup = require("settings_setup")(preferences, host)     -- returns the adapter object (see the end)
--
-- ══ HOST (the parent, Settings, supplies it) ═══════════════════════════════════════════════════════════════════
--   host.live_settings()            -> { appearance = { values = <facts>, palette = <PAL|nil> }, frame = { facts = <facts incl.
--                                      frame_output_name> } }   a table without the keys while preferences are not loaded
--   host.apply_settings(act, cb)    act = { op, section = "appearance"|"frame", data, expect, force, palette_refresh, request }
--                                      cb(info) with info = { ok, untouched?, fp?, code?, message? }. ACK ONLY WHEN THE WRITE
--                                      COMMITTED (settings_store.flush). May call cb synchronously or later; exactly-once is
--                                      enforced here, a late answer after the timeout is ignored.
--   host.read_pins(cb)              cb(raw | nil, why?) raw = { list = {pin strings} | nil = automatic, apps = { [id] = true } }
--   host.apply_pins(act, cb)        act = { op, section = "pins", data, expect, force, request }; cb(info) as above
--   host.ready()                    true when the preferences files are loaded and writable
--   host.run(script, args, cb, opts) the sandbox `run` over `sh -c script <name> args…`; cb(out, code). opts is the sandbox's
--                                   run option table (only { input = <text> } is used, for texts too large for an argument);
--                                   a host that drops opts only makes those large writes FAIL SAFE (the script verifies the length)
--   host.say(scene, words)          `say` to another PROCESS (used once: widgets "emit setup_request <id>")
--   host.clipboard(text, cb)        cb(ok) MUST be called                                  (optional: no clipboard → text stays in the field)
--   host.notify(message)            optional toast-style message for results that need to be seen
--   host.now()                      optional epoch seconds (journal stamps); default: a per-session constant
--   Optional injections (defaults = the logic globals): host.decode, host.encode (json), host.after, host.cancel, host.on,
--   host.fact, host.text, host.model.
--
-- ══ FILES (under ~/.config/beskar/) ═══════════════════════════════════════════════════════════════════════════
--   setup-journal.json            the recovery journal. Written whole and atomically (temp + rename) on every persist action.
--   setup-widget-request.json     written by this adapter only; { id, kind = "snapshot"|"apply", data?, expect?, force? }
--   setup-widget-response.json    written by Widgets only; { id, ok, untouched?, code?, message?, data?, fp? }
--   The widgets bridge: write the request, say widgets "emit setup_request ID", wait for the numeric event
--   Settings.setup_widgets_reply(ID), read the response and check its id. One request at a time (queued), ids are unique
--   integers below 2^24 (event payloads are f32), a late or foreign answer is ignored. Widgets / Topbar owned files are never written here.
--
-- ══ UI DECLARATIONS for settings.plm (docs/UI at the end of this file) ═════════════════════════════════════════
return function(P, host)
    local SP = require("setup_profiles")
    local unpack = table.unpack or unpack

    local APPLY_MS, SNAPSHOT_MS = 10000, 3000
    local JOURNAL_FILE, REQUEST_FILE, RESPONSE_FILE = "setup-journal.json", "setup-widget-request.json", "setup-widget-response.json"
    local MAX_ID = 16777215                 -- numeric event payloads travel as 32-bit floats: ids above 2^24 arrive rounded
    local ARG_LIMIT = 60000
    local MAX_LINES, MAX_STATUS = 16, 220

    local fact_t = host.fact or fact
    local text_t = host.text or text
    local model_t = host.model or model
    local on_ = host.on or on

    -- ── helpers ──────────────────────────────────────────────────────────────
    local function clip(s, n)
        if type(s) ~= "string" then return nil end
        s = s:gsub("%c", " ")
        if #s > n then
            s = s:sub(1, n)
            while #s > 0 and not utf8.len(s) do s = s:sub(1, -2) end
            s = s .. "…"
        end
        return s
    end

    local function decode(s)
        local d = host.decode or (json and json.decode)
        if not d then error("settings_setup: no json decoder") end
        return d(s)
    end
    local function encoder() return host.encode or (json and json.encode) end

    local function now()
        if host.now then
            local ok, v = pcall(host.now)
            if ok and type(v) == "number" then return math.floor(v) end
        end
        return 0
    end

    local session_seed = 0
    do
        local ok, r = pcall(math.random, 1, 1000000)
        session_seed = ((now() % 1000003) * 7919 + (ok and r or 0)) % MAX_ID
    end
    local id_counter = 0
    local function next_id()
        id_counter = id_counter + 1
        return ((session_seed + id_counter) % MAX_ID) + 1          -- 1 .. 2^24-1
    end

    local function timer(ms, fn)
        local t = { live = true }
        local a = host.after or after
        if not a then return t end
        t.h = a(ms, function()
            if t.live then t.live = false; fn() end
        end)
        return t
    end
    local function untimer(t)
        if t and t.live then
            t.live = false
            local c = host.cancel or cancel
            if c and t.h ~= nil then pcall(c, t.h) end
        end
    end

    local function setf(name, value) fact_t[name] = value end
    local function sett(name, value) text_t[name] = value end

    local ERROR_LABELS = {
        stale = "changed while the setup was running",
        timeout = "did not answer in time",
        write_failed = "could not be saved",
        journal_write = "the recovery journal could not be written",
        unavailable = "is not available",
        bad_reply = "sent an answer that could not be read",
        host_error = "reported an internal error",
        encode = "could not be prepared",
        invalid = "refused the data as invalid",
        busy = "is busy with another change",
        not_ready = "is not ready yet",
    }
    local function reason(code, message)
        local m = clip(message, 120)
        if m and m ~= "" then return m end
        return ERROR_LABELS[code] or (code and clip(tostring(code), 32)) or "failed"
    end

    -- a whitelisted owner answer (never trust more than the exact fields)
    local function clean_info(i)
        if type(i) ~= "table" then return { ok = false, untouched = false, code = "bad_reply", message = ERROR_LABELS.bad_reply } end
        local out = { ok = i.ok == true, untouched = i.untouched == true }
        if type(i.fp) == "string" and #i.fp <= 40 and i.fp:match("^%x+:%d+$") then out.fp = i.fp end
        if i.code ~= nil then out.code = clip(tostring(i.code), 32) end
        if not out.ok then out.message = reason(out.code, i.message) end
        return out
    end

    -- ── files (every one through host.run) ───────────────────────────────────
    local READ_SCRIPT = [=[
p="$HOME/.config/beskar/$1"
if [ ! -e "$p" ] && [ ! -L "$p" ]; then exit 3; fi
[ -f "$p" ] && [ ! -L "$p" ] && [ -r "$p" ] || exit 4
n=$(wc -c < "$p" | tr -d ' ') || exit 4
[ "$n" -le "$2" ] || exit 4
cat "$p"
]=]
    local WRITE_SCRIPT = [=[
set -eu
umask 077
d="$HOME/.config/beskar"
p="$d/$1"
mkdir -p "$d"
t=$(mktemp "$p.tmp.XXXXXX")
trap 'rm -f "$t"' EXIT HUP INT TERM
if [ "$3" = "-" ]; then cat > "$t"; else printf '%s' "$3" > "$t"; fi
[ "$(wc -c < "$t" | tr -d ' ')" -eq "$2" ] || exit 5
sync "$t" 2>/dev/null || true
mv -f -- "$t" "$p"
]=]
    local ASIDE_SCRIPT = [=[
set -eu
p="$HOME/.config/beskar/$1"
if [ ! -e "$p" ] && [ ! -L "$p" ]; then exit 3; fi
mv -- "$p" "$p.unreadable.$(date +%s)"
]=]

    local function read_file(name, max, cb)
        host.run(READ_SCRIPT, { name, tostring(max) }, function(out, code)
            if code == 0 and type(out) ~= "string" then out = "" end
            cb(out, code)
        end)
    end
    local function write_file(name, body, cb)
        if type(body) ~= "string" or body == "" then cb(false, "empty"); return end
        local inline = #body <= ARG_LIMIT
        host.run(WRITE_SCRIPT, { name, tostring(#body), inline and body or "-" }, function(_, code)
            cb(code == 0, code ~= 0 and ("exit " .. tostring(code)) or nil)
        end, (not inline) and { input = body } or nil)
    end

    -- ── the controller ───────────────────────────────────────────────────────
    local ctl
    local pump
    local paint

    local S = {                      -- all adapter state, bounded
        phase = "loading",           -- journal phase: loading | none | loaded | unreadable | waiting | recovery | ok
        journal_text = nil,
        journal_note = nil,          -- banner text of the phase
        rows = nil,                  -- recovery rows { section, actual }
        clean_only = false,
        busy = false,
        running = false,
        attention = nil,             -- { message... } of a failed rollback
        preview = nil,               -- the staged review (SP preview result)
        review_on = {},              -- section -> bool (chosen to apply)
        export_on = { appearance = true, frame = true, pins = true, widgets = true },
        show_steps = false,
        lines = {},
        lines_title = "",
        last_live = nil,
        last_problems = {},
        stale_undo = nil,
        armed = nil,
        seen_message = nil,
        reconciling = false,
        doc_mark = nil,
    }

    local function status(message)
        sett("setup_status", clip(message or "", MAX_STATUS))
    end

    local function set_lines(title, list)
        local out = {}
        for i, l in ipairs(list) do
            if i > MAX_LINES then break end
            if i == MAX_LINES and #list > MAX_LINES then
                out[i] = { kind = 4, text = string.format("… and %d more", #list - MAX_LINES + 1) }
            else
                out[i] = { kind = l.kind, text = clip(l.text, 200) }
            end
        end
        S.lines = out
        S.lines_title = title or ""
        model_t.setup_lines = out
        sett("setup_lines_title", S.lines_title)
        setf("setup_has_lines", #out > 0)
    end

    local function clear_lines() set_lines("", {}) end

    local function settings_live()
        if host.ready and not host.ready() then return {} end
        local ok, st = pcall(host.live_settings)
        if not ok or type(st) ~= "table" then return {} end
        return { appearance = st.appearance, frame = st.frame }
    end

    -- ── widgets bridge ───────────────────────────────────────────────────────
    local wq, wcur = {}, nil
    local w_next

    local function w_finish(e, resp, why)
        if e.done then return end
        e.done = true
        untimer(e.timer)
        if wcur == e then wcur = nil end
        e.cb(resp, why)
        w_next()
    end

    function w_next()
        if wcur then return end
        local e = table.remove(wq, 1)
        if not e then return end
        if e.done then return w_next() end
        wcur = e
        e.id = next_id()
        e.stage = "write"
        e.timer = timer(e.ms, function() w_finish(e, nil, "timeout") end)
        local body = e.build(e.id)
        if not body then w_finish(e, nil, "encode"); return end
        write_file(REQUEST_FILE, body, function(ok)
            if wcur ~= e or e.done then return end
            if not ok then w_finish(e, nil, "write_failed"); return end
            e.stage = "wait"
            if host.say then pcall(host.say, "widgets", "emit setup_request " .. e.id) end
        end)
    end

    -- returns a cancel function. cb(resp | nil, why) exactly once
    local function w_send(build, ms, cb)
        local e = { build = build, ms = ms, cb = cb }
        wq[#wq + 1] = e
        w_next()
        return function()
            if e.done then return end
            e.done = true
            untimer(e.timer)
            if wcur == e then wcur = nil; w_next() end
        end
    end

    local function w_response(doc)
        local r = { id = doc.id, ok = doc.ok == true, untouched = doc.untouched == true }
        if doc.code ~= nil then r.code = clip(tostring(doc.code), 32) end
        if doc.message ~= nil then r.message = clip(tostring(doc.message), 120) end
        if type(doc.fp) == "string" and #doc.fp <= 40 and doc.fp:match("^%x+:%d+$") then r.fp = doc.fp end
        if type(doc.data) == "table" then r.data = doc.data end
        return r
    end

    on_("setup_widgets_reply", function(id)
        local n = tonumber(id)
        local e = wcur
        if not e or e.stage ~= "wait" or n ~= e.id then return end          -- stale or foreign: ignored
        e.stage = "read"
        read_file(RESPONSE_FILE, 131072, function(out, code)
            if wcur ~= e or e.done then return end
            if code ~= 0 then w_finish(e, nil, "bad_reply"); return end
            local ok, doc = pcall(decode, out)
            if not ok or type(doc) ~= "table" or doc.id ~= e.id then
                e.stage = "wait"                                              -- an older file: keep waiting (bounded by the timer)
                return
            end
            w_finish(e, w_response(doc))
        end)
    end)

    local function quote(s)
        return '"' .. tostring(s):gsub('[%c"\\]', function(c) return string.format("\\u%04x", c:byte()) end) .. '"'
    end

    -- ── collecting owner snapshots ───────────────────────────────────────────
    local col = nil

    local function connected_map(c)
        if type(c) ~= "table" then return nil end
        local map = {}
        local n = 0
        for k, v in pairs(c) do
            if type(k) == "number" and type(v) == "string" then map[v] = true; n = n + 1
            elseif type(k) == "string" and v == true then map[k] = true; n = n + 1 end
            if n >= 64 then break end
        end
        return map
    end

    local function collect(cb)
        if col then col.cbs[#col.cbs + 1] = cb; return end
        col = { cbs = { cb }, live = {}, problems = {}, pending = 2 }
        local mine = col
        local live, problems = mine.live, mine.problems
        local function done_one()
            mine.pending = mine.pending - 1
            if mine.pending > 0 then return end
            if col == mine then col = nil end
            S.last_live, S.last_problems = live, problems
            for _, f in ipairs(mine.cbs) do f(live, problems) end
        end
        if host.ready and not host.ready() then
            problems.settings = "Preferences are still loading."
        else
            local st = settings_live()
            live.appearance, live.frame = st.appearance, st.frame
            if not live.appearance or not live.frame then problems.settings = "Preferences are not available." end
        end
        -- pins (Topbar): host callback, exactly once, guarded
        local pins_done = false
        local pt
        local function pins_cb(raw, why)
            if pins_done then return end
            pins_done = true
            untimer(pt)
            if type(raw) == "table" then live.pins = raw
            else problems.pins = reason("unavailable", why and ("The dock did not answer (" .. tostring(why) .. ")") or "The dock did not answer.") end
            done_one()
        end
        pt = timer(SNAPSHOT_MS, function() pins_cb(nil, "timeout") end)
        local okp, err = pcall(host.read_pins, pins_cb)
        if not okp then pins_cb(nil, err) end
        -- widgets: the file bridge
        w_send(function(id) return string.format('{"id": %d, "kind": "snapshot"}', id) end, SNAPSHOT_MS, function(resp, why)
            local d = resp and resp.ok and resp.data
            if type(d) == "table" and d.ready ~= false then
                live.widgets = { ready = true, snap = d.snap, cards = d.cards }
                local map = connected_map(d.connected)
                if map then live.outputs = { connected = map } end
            elseif resp and resp.ok and type(d) == "table" then
                problems.widgets = "Widgets is still starting."
            else
                problems.widgets = (resp and not resp.ok) and ("Widgets answered: " .. reason(resp.code, resp.message))
                    or ("Widgets " .. (ERROR_LABELS[why] or "is not available") .. ".")
            end
            done_one()
        end)
    end

    -- ── status painting ──────────────────────────────────────────────────────
    local STEP_TEXT = { pending = { "Waiting", 0 }, sent = { "Applying…", 0 }, applied = { "Applied", 1 }, failed_clean = { "Not applied", 2 },
        failed = { "Failed", 3 }, rolling_back = { "Putting back…", 0 }, rolled_back = { "Put back", 2 }, rollback_failed = { "Needs attention", 3 } }
    local ACTUAL_TEXT = { untouched = { "Unchanged", 1 }, applied = { "Changed", 2 }, diverged = { "Changed, differently", 3 } }

    local function gate_message(for_apply)
        if S.busy then return "Another step is still running." end
        if S.running then return "A setup is being applied." end
        if S.phase == "loading" then return "Checking the last setup…" end
        if S.phase == "unreadable" then return "The recovery journal cannot be read. Move it aside to continue." end
        if S.phase == "waiting" then return "Waiting to check an interrupted setup." end
        if S.phase == "recovery" then return "Finish the interrupted setup first: roll back or keep." end
        if S.attention then return "Resolve the setup that needs attention first." end
        local st = ctl.status()
        if st.state == "blocked" then return "Retry writing the recovery journal first." end
        return nil
    end

    function paint()
        local st = ctl.status()
        local gate = gate_message(true)
        setf("setup_busy", S.busy)
        setf("setup_running", S.running)
        setf("setup_ready", gate == nil)
        setf("setup_blocked", st.state == "blocked")
        setf("setup_attention", S.attention ~= nil)
        setf("setup_recovery", S.phase == "recovery")
        setf("setup_recovery_clean", S.phase == "recovery" and S.clean_only)
        setf("setup_unreadable", S.phase == "unreadable")
        setf("setup_waiting", S.phase == "waiting")
        setf("setup_can_undo", st.undo_available == true and S.phase ~= "recovery" and S.phase ~= "unreadable")
        setf("setup_stale_undo", S.stale_undo ~= nil)
        setf("setup_reviewing", S.preview ~= nil)
        local nchosen = 0
        for _, on in pairs(S.review_on) do if on then nchosen = nchosen + 1 end end
        setf("setup_review_count", S.preview and nchosen or 0)
        local nexp = 0
        for _, section in ipairs(SP.SECTIONS) do if S.export_on[section] then nexp = nexp + 1 end end
        setf("setup_export_count", nexp)
        -- banner
        local banner = ""
        if st.state == "blocked" and st.blocked then banner = st.blocked.message
        elseif S.phase == "loading" then banner = ""
        elseif S.journal_note and (S.phase == "unreadable" or S.phase == "waiting" or S.phase == "recovery") then banner = S.journal_note end
        sett("setup_banner", clip(banner, 260))
        -- progress / recovery rows
        local steps = {}
        if S.phase == "recovery" and S.rows then
            for _, r in ipairs(S.rows) do
                local label = ACTUAL_TEXT[r.actual] or { "Not checked yet", 0 }
                steps[#steps + 1] = { name = SP.TITLES[r.section], state = label[1], tone = label[2] }
            end
        elseif S.show_steps then
            for _, s in ipairs(st.steps or {}) do
                local label = STEP_TEXT[s.state] or { tostring(s.state), 0 }
                steps[#steps + 1] = { name = SP.TITLES[s.section] or s.section, state = label[1], tone = label[2] }
            end
        end
        model_t.setup_steps = steps
    end

    local function section_rows()
        local export, review = {}, {}
        local info = {
            appearance = "Light or dark, skin, accent and style choices",
            frame = "Menu bar and dock options",
            pins = "Dock apps (window pins stay on this machine)",
            widgets = "Widget cards and layout",
        }
        local live = S.last_live
        for i, section in ipairs(SP.SECTIONS) do
            local sub = info[section]
            if live then
                local data, why
                if section == "pins" then data = type(live.pins) == "table" and true or nil; why = S.last_problems.pins
                else
                    data, why = SP.snapshot(section, live[section], { preferences = P })
                    if not data then why = S.last_problems[section == "widgets" and "widgets" or "settings"] or why end
                end
                if not data then sub = "Not available right now" .. (why and (": " .. clip(tostring(why), 70)) or "") end
            end
            export[i] = { id = i, name = SP.TITLES[section], sub = sub, on = S.export_on[section] == true }
            local entry = S.preview and S.preview.sections[section]
            if entry then
                review[#review + 1] = { id = i, name = SP.TITLES[section], on = S.review_on[section] == true and not entry.noop,
                    sub = entry.noop and "No changes" or string.format("%d change%s", #entry.changes, #entry.changes == 1 and "" or "s"), avail = not entry.noop }
            end
        end
        model_t.setup_export_rows = export
        model_t.setup_review_rows = review
    end

    local function repaint()
        section_rows()
        paint()
    end

    -- ── pump ─────────────────────────────────────────────────────────────────
    local pend = {}
    local pumping, again = false, false

    local function write_journal(act)
        write_file(JOURNAL_FILE, act.text, function(ok, why)
            ctl.persisted(act.seq, ok, why)
            pump()
        end)
    end

    local function on_finish(res)
        S.running = false
        S.show_steps = true
        S.last_live = nil
        status(res.message)
        local lines = {}
        if res.needs_attention and #res.needs_attention > 0 then
            S.attention = {}
            for _, a in ipairs(res.needs_attention) do
                S.attention[#S.attention + 1] = a.message
                lines[#lines + 1] = { kind = 3, text = a.message }
            end
            lines[#lines + 1] = { kind = 4, text = "Retry putting them back, or accept the current state as it is." }
            set_lines("Needs attention", lines)
        else
            S.attention = nil
            clear_lines()
        end
        S.stale_undo = nil
        repaint()
        if host.notify then pcall(host.notify, res.message) end
    end

    local function dispatch(act)
        local rq = act.request
        local rec = {}
        pend[rq] = rec
        local function settle(info, timed_out)
            if pend[rq] ~= rec then return end
            pend[rq] = nil
            untimer(rec.timer)
            if rec.cancel then rec.cancel() end
            if timed_out then ctl.timeout(rq) else ctl.ack(rq, clean_info(info)) end
            pump()
        end
        rec.timer = timer(APPLY_MS, function() settle(nil, true) end)
        local request = { request = rq, op = act.op, section = act.section, data = act.data, expect = act.expect, force = act.force,
            palette_refresh = act.palette_refresh }
        if act.owner == "settings" then
            local ok, err = pcall(host.apply_settings, request, function(info) settle(info) end)
            if not ok then settle({ ok = false, untouched = false, code = "host_error", message = clip(tostring(err), 100) }) end
        elseif act.owner == "topbar" then
            local ok, err = pcall(host.apply_pins, request, function(info) settle(info) end)
            if not ok then settle({ ok = false, untouched = false, code = "host_error", message = clip(tostring(err), 100) }) end
        else
            if type(act.text) ~= "string" then
                settle({ ok = false, untouched = true, code = "encode" }); return
            end
            local expect = type(act.expect) == "string" and act.expect:match("^%x+:%d+$") and act.expect or nil
            rec.cancel = w_send(function(id)
                return string.format('{"id": %d, "kind": "apply", "data": %s%s, "force": %s}', id, act.text,
                    expect and (', "expect": ' .. quote(expect)) or "", act.force and "true" or "false")
            end, APPLY_MS, function(resp, why)
                if not resp then
                    if why == "timeout" then settle(nil, true)
                    elseif why == "write_failed" or why == "encode" then
                        settle({ ok = false, untouched = true, code = why })
                    else settle({ ok = false, untouched = false, code = why }) end
                    return
                end
                settle({ ok = resp.ok, untouched = resp.untouched, fp = resp.fp, code = resp.code, message = resp.message })
            end)
        end
    end

    local function pump_once()
        for _ = 1, 32 do
            local act = ctl.next(settings_live())
            if act.kind == "persist" then write_journal(act); return
            elseif act.kind == "apply" then dispatch(act); return
            elseif act.kind == "finish" then on_finish(act); return
            else
                if act.kind == "idle" then S.running = false end
                repaint(); return
            end
        end
    end

    function pump()
        if pumping then again = true; return end
        pumping = true
        repeat
            again = false
            pump_once()
        until not again
        pumping = false
    end

    ctl = SP.new({
        decode = decode,
        preferences = P,
        now = function() local n = now(); return n > 0 and n or session_seed end,      -- unique journal ids even without a clock
        notify = function(st)
            if st.message ~= S.seen_message then
                S.seen_message = st.message
                if st.message then status(st.message) end
            end
            if paint then paint() end
        end,
    })

    -- ── journal at startup ───────────────────────────────────────────────────
    local function normalized(text)
        -- A journal that ended as "rollback_failed" is re-read as an interrupted rollback, so the user is offered
        -- the same explicit choices (roll back again / keep) after a restart.
        local enc = encoder()
        local ok, doc = pcall(decode, (text:gsub("^\239\187\191", "")))
        if ok and type(doc) == "table" and doc.state == "rollback_failed" and type(doc.steps) == "table" and enc then
            doc.state = "rolling_back"
            for _, st in ipairs(doc.steps) do
                if type(st) == "table" and st.state == "rollback_failed" then st.state = "failed" end
            end
            local okc, out = pcall(enc, doc)
            if okc and type(out) == "string" then return out, true end
        end
        return text, false
    end

    local function describe_rows(rows)
        local parts = {}
        for _, r in ipairs(rows or {}) do
            local label = ACTUAL_TEXT[r.actual] or { "not checked yet", 0 }
            parts[#parts + 1] = SP.TITLES[r.section] .. ": " .. label[1]:lower()
        end
        return table.concat(parts, " · ")
    end

    local function apply_reconcile(r, from_failed_rollback)
        if r.ok == false or r.status == "unreadable" then
            S.phase = "unreadable"
            S.journal_note = (r.message or "The recovery journal cannot be read.") .. " Nothing was changed. Move it aside to apply setups again."
        elseif r.status == "needs_live" then
            S.phase = "waiting"
            S.journal_note = (r.message or "Waiting for the owners to answer.") .. " Use Check again when they are running."
        elseif r.status == "needs_recovery" then
            S.phase = "recovery"
            S.rows = r.steps
            S.clean_only = r.nothing_changed == true
            if r.nothing_changed then
                S.journal_note = "A setup was interrupted before it changed anything."
            else
                S.journal_note = (from_failed_rollback and "A setup could not be fully put back. " or "A setup was interrupted. ")
                    .. describe_rows(r.steps) .. "."
            end
            if host.notify then pcall(host.notify, "A setup needs your attention in Settings.") end
        else
            S.phase = "ok"
            S.journal_note = nil
        end
    end

    local function try_reconcile()
        if S.reconciling then return end
        if S.phase ~= "loaded" and S.phase ~= "waiting" then return end
        S.reconciling = true
        local text, was_failed = normalized(S.journal_text)
        local r = ctl.reconcile(text, settings_live())
        if r.status ~= "needs_live" then
            S.reconciling = false
            apply_reconcile(r, was_failed)
            repaint()
            return
        end
        collect(function(live)
            S.reconciling = false
            local r2 = ctl.reconcile(text, live)
            apply_reconcile(r2, was_failed)
            repaint()
        end)
    end

    local function load_journal()
        S.phase = "loading"
        read_file(JOURNAL_FILE, SP.MAX_JOURNAL_BYTES, function(out, code)
            if code == 3 then
                S.phase, S.journal_text = "none", nil
            elseif code ~= 0 then
                S.phase = "unreadable"
                S.journal_note = "The recovery journal could not be read (too large or not a plain file). Nothing was changed. Move it aside to apply setups again."
            else
                S.phase, S.journal_text = "loaded", out
            end
            repaint()
            try_reconcile()
        end)
    end

    -- ── operations ───────────────────────────────────────────────────────────
    local function begin_op()
        if S.busy then status("Another step is still running."); return false end
        if S.running then status("A setup is being applied."); return false end
        S.busy = true
        paint()
        return true
    end
    local function end_op() S.busy = false; paint() end

    local function clear_review()
        S.preview, S.review_on = nil, {}
        ctl.cancel_import()
        model_t.setup_review_rows = {}
    end

    local function chosen_sections()
        local list = {}
        for _, section in ipairs(SP.SECTIONS) do
            if S.review_on[section] then list[#list + 1] = section end
        end
        return list
    end

    local function change_text(ch)
        local t = (ch.label or ch.id or "Change")
        if ch.from_label ~= nil or ch.to_label ~= nil then
            t = t .. ": " .. tostring(ch.from_label or "") .. " → " .. tostring(ch.to_label or "")
        end
        local parts = {}
        local added = type(ch.added) == "table" and #ch.added or ch.added
        local removed = type(ch.removed) == "table" and #ch.removed or ch.removed
        if type(added) == "number" and added > 0 then parts[#parts + 1] = "+" .. added end
        if type(removed) == "number" and removed > 0 then parts[#parts + 1] = "−" .. removed end
        if type(ch.kept) == "number" and ch.kept > 0 then parts[#parts + 1] = ch.kept .. " kept" end
        if #parts > 0 then t = t .. " (" .. table.concat(parts, ", ") .. ")" end
        return t
    end

    local function review_lines(r)
        local out = {}
        local warn_rows = math.min(#r.warnings, 3) + (#r.warnings > 3 and 1 or 0)
        local avail = MAX_LINES - warn_rows
        local sections = {}
        for _, section in ipairs(r.order) do sections[#sections + 1] = section end
        local budget = avail - #sections
        for i, section in ipairs(sections) do
            local entry = r.sections[section]
            local n = #entry.changes
            local head = entry.title .. (entry.noop and " — no changes" or string.format(" — %d change%s", n, n == 1 and "" or "s"))
            if entry.palette_refresh and not entry.noop then head = head .. " · colours regenerate afterwards" end
            out[#out + 1] = { kind = 0, text = head }
            if not entry.noop then
                local quota = math.max(1, math.floor(budget / (#sections - i + 1)))
                if n <= quota then
                    for _, ch in ipairs(entry.changes) do out[#out + 1] = { kind = 1, text = change_text(ch) } end
                    budget = budget - n
                else
                    for k = 1, quota - 1 do out[#out + 1] = { kind = 1, text = change_text(entry.changes[k]) } end
                    out[#out + 1] = { kind = 4, text = string.format("… and %d more changes", n - quota + 1) }
                    budget = budget - quota
                end
            end
        end
        for i, w in ipairs(r.warnings) do
            if i > 3 then out[#out + 1] = { kind = 4, text = string.format("… and %d more notes", #r.warnings - 3) }; break end
            out[#out + 1] = { kind = 2, text = "Note: " .. w.message }
        end
        return out
    end

    local function error_lines(r)
        local out = {}
        for _, e in ipairs(r.errors or {}) do out[#out + 1] = { kind = 3, text = e.message } end
        if #out == 0 and r.message then out[1] = { kind = 3, text = r.message } end
        for _, w in ipairs(r.warnings or {}) do out[#out + 1] = { kind = 2, text = "Note: " .. w.message } end
        return out
    end

    local function do_export()
        if not begin_op() then return end
        local chosen = {}
        for _, section in ipairs(SP.SECTIONS) do if S.export_on[section] then chosen[#chosen + 1] = section end end
        if #chosen == 0 then status("Choose what to include."); end_op(); return end
        status("Reading the current setup…")
        collect(function(live, problems)
            local body, doc, report = ctl.export(live, chosen)
            local lines = {}
            for _, section in ipairs(report and report.included or {}) do
                lines[#lines + 1] = { kind = 1, text = "Included: " .. SP.TITLES[section] }
            end
            for _, s in ipairs(report and report.skipped or {}) do
                local why = problems[s.section == "widgets" and "widgets" or (s.section == "pins" and "pins" or "settings")] or s.reason
                lines[#lines + 1] = { kind = 2, text = "Left out: " .. SP.TITLES[s.section] .. " — " .. tostring(why) }
            end
            for _, x in ipairs(report and report.excluded or {}) do lines[#lines + 1] = { kind = 2, text = x.message } end
            if not body then
                set_lines("Export", lines)
                status(doc and doc.message or "Could not export the setup.")
                end_op(); repaint(); return
            end
            set_lines("Export", lines)
            S.doc_mark = body
            sett("setup_document", body)
            clear_review()
            local copy_done, copy_guard = false, nil
            local function copied(ok)
                if copy_done then return end
                copy_done = true
                untimer(copy_guard)
                status(ok and "Setup copied to the clipboard · paste it into a file to share" or "Could not reach the clipboard: select the field and copy it")
                end_op(); repaint()
            end
            if host.clipboard then
                -- a clipboard helper that never reports back must not leave the page busy for ever
                copy_guard = timer(3000, function() copied(false) end)
                local okc = pcall(host.clipboard, body, copied)
                if not okc then copied(false) end
            else
                status("Setup is in the field: select it and copy it")
                end_op(); repaint()
            end
        end)
    end

    local function do_review()
        if S.busy or S.running then status(gate_message() or ""); return end
        local doc = text_t.setup_document or ""
        if not doc:find("%S") then status("Paste a setup document first."); return end
        begin_op()
        clear_review(); S.stale_undo = nil
        status("Reading the current setup…")
        collect(function(live, problems)
            local r = ctl.preview_import(doc, live)
            if not r.ok then
                local lines = error_lines(r)
                if r.code == "not_ready" then
                    for _, k in ipairs({ "settings", "pins", "widgets" }) do
                        if problems[k] then lines[#lines + 1] = { kind = 2, text = problems[k] } end
                    end
                end
                set_lines("Cannot import", lines)
                status(r.message or "This setup cannot be imported.")
            elseif r.noop then
                set_lines("Review", review_lines(r))
                status(r.message)
            else
                S.preview = r
                S.review_on = {}
                for _, section in ipairs(r.order) do
                    S.review_on[section] = not r.sections[section].noop
                end
                set_lines("Review", review_lines(r))
                status((r.message or "") .. " Choose the sections to apply, then Apply.")
            end
            end_op(); repaint()
        end)
    end

    local function do_apply()
        if not S.preview then status("Review a setup first."); return end
        local gate = gate_message()
        if gate then status(gate); return end
        local sections = chosen_sections()
        if #sections == 0 then status("Choose at least one section to apply."); return end
        for _, s in ipairs(sections) do
            if (s == "appearance" or s == "frame") and host.ready and not host.ready() then
                status("Preferences are unavailable, so Appearance and Menu bar settings cannot be applied."); return
            end
        end
        begin_op()
        status("Checking the current state…")
        local token = S.preview.token
        collect(function(live)
            local r = ctl.begin(token, live, { sections = sections })
            S.busy = false
            if not r.ok then
                status(r.message)
                if r.code == "stale" or r.code == "no_preview" or r.code == "section" or r.code == "noop" then clear_review() end
                S.last_live = nil
                repaint(); return
            end
            S.preview, S.review_on = nil, {}
            S.running, S.show_steps = true, true
            clear_lines()
            status("Applying…")
            repaint()
            pump()
        end)
    end

    local function do_undo(skip)
        local gate = gate_message()
        if gate then status(gate); return end
        begin_op()
        collect(function(live)
            local r = ctl.undo(live, skip and { skip_stale = true } or nil)
            S.busy = false
            if not r.ok then
                S.stale_undo = (r.code == "stale") and (r.stale or {}) or nil
                status(r.message)
                if r.code == "stale" then
                    local lines = {}
                    for _, n in ipairs(r.stale or {}) do lines[#lines + 1] = { kind = 2, text = n .. " changed after the setup was applied." } end
                    set_lines("Undo", lines)
                end
                repaint(); return
            end
            S.stale_undo = nil
            clear_review(); clear_lines()
            S.running, S.show_steps = true, true
            status("Undoing…")
            repaint()
            pump()
        end)
    end

    -- ── events ───────────────────────────────────────────────────────────────
    on_("setup_show", function()
        setf("setup_open", true)
        try_reconcile()
        repaint()
    end)
    on_("setup_hide", function()
        if S.busy or S.running then return end
        clear_review(); clear_lines(); S.show_steps = false; S.armed = nil
        setf("setup_open", false)
        repaint()
    end)
    on_("setup_export_toggle", function(i)
        local section = SP.SECTIONS[tonumber(i) or 0]
        if not section then return end
        S.export_on[section] = not S.export_on[section]
        repaint()
    end)
    on_("setup_review_toggle", function(i)
        local section = SP.SECTIONS[tonumber(i) or 0]
        local entry = section and S.preview and S.preview.sections[section]
        if not entry or entry.noop or S.running then return end
        S.review_on[section] = not S.review_on[section]
        repaint()
    end)
    on_("setup_export", do_export)
    on_("setup_review_import", do_review)
    on_("setup_cancel", function()
        if S.running or S.busy then return end
        clear_review(); clear_lines(); status(""); repaint()
    end)
    on_("setup_apply", do_apply)
    on_("setup_undo", function() do_undo(false) end)
    on_("setup_undo_skip", function() if S.stale_undo then do_undo(true) end end)
    on_("setup_retry", function()
        if ctl.retry() then pump() end
        repaint()
    end)
    on_("setup_retry_rollback", function()
        if not S.attention then return end
        local r = ctl.retry_rollback()
        if r.ok then S.attention, S.running = nil, true; clear_lines(); status("Putting things back…"); repaint(); pump() end
    end)
    on_("setup_accept", function()
        if not S.attention then return end
        local r = ctl.abandon()
        if r.ok then S.attention = nil; repaint(); pump() end
    end)
    local function recover(choice)
        if S.phase ~= "recovery" or S.busy or S.running then return end
        local r = ctl.recover(choice, S.last_live or settings_live())
        if not r.ok then status(r.message); return end
        S.phase, S.rows, S.journal_note = "ok", nil, nil           -- the recovery run owns the state now
        S.running, S.show_steps = true, true
        status(choice == "keep" and "Closing the interrupted setup…" or "Putting things back…")
        repaint()
        pump()
    end
    on_("setup_recover_rollback", function() recover("rollback") end)
    on_("setup_recover_keep", function() recover("keep") end)
    on_("setup_recheck", function()
        if S.busy or S.running then return end
        if S.phase == "waiting" or S.phase == "unreadable" or S.phase == "loading" or S.phase == "loaded" then
            if S.phase == "waiting" and S.journal_text then try_reconcile() else load_journal() end
        end
        repaint()
    end)
    on_("setup_aside", function()
        if S.phase ~= "unreadable" or S.busy then return end
        if S.armed ~= "aside" then
            S.armed = "aside"
            status("Press Move aside again to keep a copy of the journal and start fresh.")
            timer(4000, function() if S.armed == "aside" then S.armed = nil; status("") end end)
            return
        end
        S.armed = nil
        S.busy = true
        host.run(ASIDE_SCRIPT, { JOURNAL_FILE }, function(_, code)
            S.busy = false
            if code == 0 or code == 3 then
                S.phase, S.journal_text, S.journal_note = "none", nil, nil
                status("The old journal was moved aside (setup-journal.json.unreadable.*).")
            else
                status("Could not move the journal aside.")
            end
            repaint()
        end)
        paint()
    end)
    on_("setup_dismiss", function()
        if S.busy or S.running or S.attention then return end
        clear_lines(); S.show_steps = false; status(""); repaint()
    end)
    on_("text:setup_document", function()
        if text_t.setup_document == S.doc_mark then return end
        if S.preview then clear_review(); clear_lines() end
        S.stale_undo = nil
        repaint()
    end)

    -- ── init ─────────────────────────────────────────────────────────────────
    model_t.setup_export_rows = {}
    model_t.setup_review_rows = {}
    model_t.setup_steps = {}
    model_t.setup_lines = {}
    for _, name in ipairs({ "setup_open", "setup_busy", "setup_running", "setup_ready", "setup_reviewing", "setup_blocked", "setup_attention",
        "setup_recovery", "setup_recovery_clean", "setup_unreadable", "setup_waiting", "setup_can_undo", "setup_stale_undo", "setup_has_lines" }) do
        setf(name, false)
    end
    setf("setup_review_count", 0)
    setf("setup_export_count", #SP.SECTIONS)
    repaint()
    load_journal()

    local A = { ctl = ctl, state = S }
    -- The parent calls this when preferences finished loading (and may call it any time): re-checks a waiting journal.
    function A.poke()
        if S.phase == "waiting" or S.phase == "loaded" then try_reconcile() end
        repaint()
    end
    function A.pump() pump() end
    A.write_file = write_file                                        -- (tests)
    A.scripts = { read = READ_SCRIPT, write = WRITE_SCRIPT, aside = ASIDE_SCRIPT }
    return A
end

--[[ ═══ UI for settings.plm (Settings → General → "Portable setup"; no new surface) ═══════════════════════════════
Declarations (inside `scene Settings`):

    fact setup_open = false          fact setup_busy = false         fact setup_running = false     fact setup_ready = false
    fact setup_reviewing = false     fact setup_blocked = false      fact setup_attention = false   fact setup_recovery = false
    fact setup_recovery_clean = false fact setup_unreadable = false  fact setup_waiting = false     fact setup_can_undo = false
    fact setup_stale_undo = false    fact setup_has_lines = false    fact setup_review_count = 0    fact setup_export_count = 0
    text setup_document = ""         text setup_status = ""          text setup_banner = ""         text setup_lines_title = ""
    model setup_export_rows max 4 { id: number; name: text; sub: text; on: bool }
    model setup_review_rows max 4 { id: number; name: text; sub: text; on: bool; avail: bool }
    model setup_steps max 4 { name: text; state: text; tone: number }          // tone 0 neutral · 1 good · 2 warn · 3 bad
    model setup_lines max 16 { kind: number; text: text }                      // kind 0 section head · 1 change · 2 note · 3 problem · 4 more
    event setup_show ->  event setup_hide ->  event setup_export_toggle ->  event setup_review_toggle ->
    event setup_export ->  event setup_review_import ->  event setup_cancel ->  event setup_apply ->
    event setup_undo ->  event setup_undo_skip ->  event setup_retry ->  event setup_retry_rollback ->  event setup_accept ->
    event setup_recover_rollback ->  event setup_recover_keep ->  event setup_recheck ->  event setup_aside ->
    event setup_dismiss ->  event setup_widgets_reply ->               // reply: Widgets' `emit Settings.setup_widgets_reply(ID)`

Layout (one sub-page like the saved looks: an ActionRow "Portable setup" → "Open…" emits setup_show, Back emits setup_hide; show the
page while `setup_open`; Escape → setup_hide while setup_open and not setup_running):
  1. Banner (only while setup_banner ≠ ""): a Plate in warn tone with the text; below it, per fact: Roll back / Keep current state
     (setup_recovery; label the second "Dismiss" when setup_recovery_clean; hide Roll back then), Check again (setup_waiting or
     setup_unreadable), Move aside (setup_unreadable, two-press confirm), Retry (setup_blocked).
  2. "Share this setup": setup_export_rows as RowFrame + Switch rows (emit setup_export_toggle(r.id)); Btn "Copy setup"
     (enabled: setup_busy == false and setup_export_count > 0) → setup_export.
  3. "Import a setup": input setup_document (submit → setup_review_import) + Btn "Review" (enabled: setup_ready) → setup_review_import.
  4. Review: while setup_reviewing, setup_review_rows with Switch (on) emit setup_review_toggle(r.id), rows with avail=false dimmed;
     Btn "Apply" (enabled: setup_reviewing and setup_ready and setup_review_count > 0) → setup_apply, Btn "Cancel" → setup_cancel;
     Ctrl+Return while setup_reviewing → setup_apply.
  5. setup_lines under a SectionLabel(setup_lines_title): each row text, colour by kind (0 ink bold, 1 ink, 2 warn, 3 danger, 4 ink_sub);
     the list is at most 16 rows tall (fixed height, no scroll needed).
  6. Progress: setup_steps rows (name + state Pill, tone → neutral/ok/warn/danger) shown while the model is non-empty.
  7. Result actions: Undo setup (enabled: setup_can_undo and setup_ready) → setup_undo; Undo anyway, keep changed sections
     (setup_stale_undo) → setup_undo_skip; Retry putting back / Accept current state (setup_attention) → setup_retry_rollback / setup_accept;
     Dismiss (setup_has_lines and not setup_running) → setup_dismiss.
  8. setup_status (font_caption, ink_sub, 2 lines) at the bottom.
Hide every other control while setup_running except the progress rows and status (no second apply can start: the adapter refuses it too).
Events setup_widgets_reply must be declared with `->` (numeric payload: the request id).

Wiring in settings.luau:
    local setup = require("settings_setup")(preferences, { live_settings = …, apply_settings = …, read_pins = …, apply_pins = …,
        ready = preference_store.ready, run = function(script, args, cb, opts) run("sh", { "-c", script, "setup", unpack(args) }, cb, opts) end,
        say = say, clipboard = function(body, cb) run("sh", { "-c", 'printf "%s" "$1" | wl-copy', "setup-export", body }, function(_, code) cb(code == 0) end) end,
        notify = …, now = …, decode = json.decode })
    …and call setup.poke() when preference_store becomes ready.
]]
