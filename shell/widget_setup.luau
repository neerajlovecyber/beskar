-- Widgets owner bridge for portable setup profiles (C5). Settings coordinates (shell/setup_profiles.luau); THIS module is
-- the widgets owner's half: it answers `snapshot` and `apply` requests about the full widget placement. Pure logic with a
-- host adapter (no globals, no scene access, no surface, no feed, no poller), so tests/widget-setup.lua runs it with a
-- fake host and, separately, inside the real shell/widgets.luau.
--
-- ══ The bridge (staged files + numeric events; CLI string payloads do not reliably deliver) ═════════════════
--   Settings writes   ~/.config/beskar/setup-widget-request.json   { id, kind = "snapshot" | "apply", data?, expect?, force? }
--     id      positive integer below 2^24 (the `emit` payload travels as a 32-bit float: larger ids arrive rounded and
--             answer `superseded`), unique per ATTEMPT (the coordinator's request id: a rollback has its own id)
--     data    the widgets section { snap, cards = [ { id, out, kind, sz, x, y, opts?, stack? } ] } (apply)
--     expect  fingerprint the live desktop must still have (setup_profiles.fingerprint("widgets", snapshot)); required
--             unless force
--     force   true for a rollback: no compare-and-swap, and the placement is restored EXACTLY (no reflow)
--   then sends        `emit setup_request <id>`                       (to the widgets scene; one number)
--   Widgets answers   ~/.config/beskar/setup-widget-response.json    { id, ok, untouched?, code?, message?, data?, fp? }
--   and ONLY AFTER that file is written says  `say settings "emit setup_widgets_reply <id>"`.
--   snapshot reply: ok, untouched = true, fp = fingerprint, data = { ready = true, snap, cards = [...] (opts and stacks
--     included), connected = { [NAME] = true } }  → live.widgets = { ready, snap, cards }, live.outputs = { connected }.
--   apply reply:    ok = true, fp = fingerprint of the desktop NOW (the coordinator's after_fp), sent only once the new
--     ~/.config/beskar/widgets.json has been written atomically.  ok = false carries `untouched` (true = nothing changed,
--     in memory or on disk) and `code`:
--       not_ready      widgets are still starting (no layout loaded / no output known)      untouched
--       bad_request    the request file is missing, unreadable, malformed, oversized          untouched
--       superseded     the request file holds another id, or a later request is already queued   untouched
--       unavailable    setup_profiles could not be loaded                                      untouched
--       unrepresentable the live desktop cannot be described exactly (so it cannot be undone)  untouched
--       invalid        setup_profiles.validate_section refused the data                        untouched
--       unsupported    applying would DROP cards (a widget kind this Beskar does not know)     untouched
--       stale          the live fingerprint is not `expect`                                    untouched
--       io             widgets.json could not be written (file and memory are unchanged)       untouched
--       timeout        the write did not finish in time: memory unchanged, the file may change   NOT untouched
--
-- ══ Guarantees ══════════════════════════════════════════════════════════════════════════════════════════════
--   · ONE request at a time, in the order the events arrived. A request that has been waiting while a later one arrived is
--     never executed late: an apply whose turn comes while another request is queued behind it (the coordinator gave up on
--     it) answers `superseded`; a request whose file now holds another id also answers `superseded`.
--   · Compare-and-swap, validation and the candidate are worked out in ONE synchronous step; from then until the answer
--     the owner's gate is up, so the user's own edits (and a saved-layout load) wait and replay AFTER the install instead
--     of being overwritten. Nothing is installed in memory before the file is written: a failed write changes nothing.
--   · The new widgets.json is written (serialised with every other write of the file), THEN installed (ONE undo step of
--     widgets' own: a forced rollback that finds that step still on top of the history and the desktop still as the apply
--     left it removes it instead of adding another), THEN the response file is written, THEN Settings is told.
--   · Disconnected-output cards are kept as records (hidden); connected outputs reflow through the saved-layout restore.
-- Runs under Luau and plain Lua.
local M = {}

M.MAX_REQUEST_BYTES = 131072
M.TIMEOUT_MS = 8000
M.DONE_KEEP = 16

local function is_id(v)
    return type(v) == "number" and v == v and v == math.floor(v) and v >= 1 and v <= 2 ^ 53
end

-- host = {
--   json = { encode, decode },
--   read_request = fn(cb)            cb(kind, text)  kind "ok" | "missing" | "toolarge" | "error"
--   write_response = fn(text, cb)    cb(ok)          atomic replace of the response file
--   notify = fn(id)                  tells Settings (only called after the response file is on disk)
--   ready = fn() -> bool             the desktop is loaded and the outputs are known
--   live = fn() -> { snap, cards }   the live desktop (cards are copies)
--   outputs = fn() -> { [NAME] = true }
--   restore = fn(layout, exact) -> cards, report          the saved-layout restore (exact = no reflow)
--   persist = fn(cards, snap, cb)    cb(ok, unknown)      write widgets.json for that desktop (atomic, serialised)
--   top_fp = fn() -> string | nil    fingerprint tag of the undo step on top, when a setup apply put it there
--   install = fn(cards, snap, how, tag)   how = "push" | "replace" | "none"; puts the desktop in place (the module lowers the gate AFTER it)
--   gate = fn(on)                    holds / replays the user's state-changing events
--   resave = fn()                    re-assert the memory state on disk (after a late or unknown write)
--   after = fn(ms, fn) -> handle     cancel = fn(handle)
--   profiles = fn() -> module | nil  setup_profiles (lazy)
-- }
function M.new(host)
    local ctl = {}
    local queue, running = {}, false
    local seen, done_order = {}, {}      -- ids queued / running / recently answered
    local SP

    local function remember(id)
        seen[id] = true
        done_order[#done_order + 1] = id
        while #done_order > M.DONE_KEEP do seen[table.remove(done_order, 1)] = nil end
    end

    local function profiles()
        if SP == nil then SP = host.profiles() or false end
        return SP or nil
    end

    -- ── answering: response file first, Settings only afterwards ──
    local function respond(id, body, cb)
        body.id = id
        local ok, text = pcall(host.json.encode, body)
        if not ok or type(text) ~= "string" then
            body = { id = id, ok = false, untouched = body.untouched == true, code = "io", message = "The answer could not be encoded" }
            text = host.json.encode(body)
        end
        local tries = 0
        local function write()
            tries = tries + 1
            host.write_response(text, function(wrote)
                if wrote then
                    host.notify(id)
                    cb()
                elseif tries < 2 then
                    write()
                else
                    cb()      -- no answer can be delivered: the coordinator times the request out and rolls back
                end
            end)
        end
        write()
    end

    local function refuse(id, code, message, cb, untouched)
        respond(id, { ok = false, untouched = untouched ~= false, code = code, message = message }, cb)
    end

    -- ── one job ──
    local function run_job(id, finish)
        local job = { done = false, phase = "read" }
        local timer
        local function conclude()
            if job.done then return end
            job.done = true
            if timer then host.cancel(timer); timer = nil end
            finish()
        end
        -- the watchdog answers a job that never completes; a late completion afterwards changes nothing
        timer = host.after(host.timeout_ms or M.TIMEOUT_MS, function()
            timer = nil
            if job.done then return end
            local was = job.phase
            job.done = true
            job.timed_out = true
            if was == "write" then
                host.gate(false)
                host.resave()
                respond(id, { ok = false, untouched = false, code = "timeout", message = "Widgets did not finish saving in time" }, finish)
            else
                respond(id, { ok = false, untouched = true, code = "timeout", message = "Widgets did not answer in time" }, finish)
            end
        end)
        local function reply(body) if not job.done then respond(id, body, conclude) end end
        local function deny(code, msg, untouched)
            if not job.done then refuse(id, code, msg, conclude, untouched) end
        end

        host.read_request(function(kind, text)
            if job.done then return end
            if kind ~= "ok" then
                return deny("bad_request", kind == "missing" and "There is no request file" or "The request file could not be read")
            end
            local okd, req = pcall(host.json.decode, text or "")
            if not okd or type(req) ~= "table" then return deny("bad_request", "The request is not valid JSON") end
            if req.id ~= id then
                return deny("superseded", "A newer request replaced this one")
            end
            if req.kind ~= "snapshot" and req.kind ~= "apply" then
                return deny("bad_request", "Unknown request kind")
            end
            local sp = profiles()
            if not sp then return deny("unavailable", "Setup profiles are not available") end
            if not host.ready() then return deny("not_ready", "Widgets are still starting") end

            local live = host.live()
            local cur, why = sp.snapshot("widgets", { ready = true, snap = live.snap, cards = live.cards })

            if req.kind == "snapshot" then
                if not cur then return deny("unrepresentable", why or "The widget desktop cannot be described") end
                return reply({ ok = true, untouched = true, fp = sp.fingerprint("widgets", cur),
                    data = { ready = true, snap = cur.snap, cards = cur.cards, connected = host.outputs() } })
            end

            -- ── apply ──
            -- a later request is already waiting: the coordinator gave this one up (timeout) and sent something else
            if #queue > 0 then return deny("superseded", "A later request is already waiting") end
            local force = req.force == true
            if not force and (type(req.expect) ~= "string" or req.expect == "") then
                return deny("bad_request", "An apply without `force` needs `expect`")
            end
            local data, errors = sp.validate_section("widgets", req.data)
            if not data then
                return deny("invalid", errors and errors[1] and errors[1].message or "The widget desktop is not valid")
            end
            if not force then
                if not cur then return deny("unrepresentable", why or "The widget desktop cannot be described") end
                if sp.fingerprint("widgets", cur) ~= req.expect then
                    return deny("stale", "The widgets changed since the setup was reviewed")
                end
            end
            local cards, rep = host.restore({ cards = data.cards, snap = data.snap }, force)
            if rep.skipped > 0 or #cards ~= #data.cards then
                return deny("unsupported", string.format("%d widget%s of a kind this Beskar does not know would be dropped",
                    rep.skipped, rep.skipped == 1 and "" or "s"))
            end
            local after = sp.snapshot("widgets", { ready = true, snap = data.snap, cards = cards })
            local after_fp = after and sp.fingerprint("widgets", after) or nil
            local before_fp = cur and sp.fingerprint("widgets", cur) or nil
            local tag = host.top_fp()
            -- how the undo history changes: nothing for a no-op; a forced step that is taking back the last setup
            -- apply (still on top, desktop still as that apply left it) removes that step; anything else adds one
            local how = "push"
            if before_fp ~= nil and before_fp == after_fp and live.snap == data.snap then how = "none"
            elseif force and tag ~= nil and before_fp == tag then how = "replace" end

            -- the gate is up from here: this step and the install below are separated only by the file write
            host.gate(true)
            job.phase = "write"
            host.persist(cards, data.snap, function(ok, unknown)
                if job.timed_out then
                    -- late: nothing is installed; the file may now hold a desktop memory does not, so memory wins
                    host.resave()
                    return
                end
                if job.done then return end
                if not ok then
                    host.gate(false)
                    if unknown then host.resave() end
                    return deny("io", "widgets.json could not be written", not unknown)
                end
                -- install first, THEN let the user's waiting edits replay on top of it (never the other way round)
                local okI, err = pcall(host.install, cards, data.snap, how, after_fp)
                host.gate(false)
                if not okI then
                    host.resave()
                    return deny("io", "The desktop could not be put in place: " .. tostring(err):sub(1, 80), false)
                end
                reply({ ok = true, fp = after_fp })
            end)
        end)
    end

    local function next_job()
        if running then return end
        local id = table.remove(queue, 1)
        if not id then return end
        running = true
        local ok, err = pcall(run_job, id, function()
            running = false
            next_job()
        end)
        if not ok then
            -- a bug must not wedge the queue: answer and go on
            running = false
            pcall(host.gate, false)
            pcall(respond, id, { ok = false, untouched = false, code = "error", message = tostring(err):sub(1, 120) }, function() next_job() end)
        end
    end

    -- `emit setup_request <id>`: the id as a number, or { id = n } from logic
    function ctl.request(p)
        if type(p) == "table" then p = p.id end
        local id = tonumber(p)
        if not is_id(id) then return false end
        if seen[id] then return false end          -- a repeated event never runs a request twice
        remember(id)
        queue[#queue + 1] = id
        next_job()
        return true
    end

    function ctl.pending() return #queue + (running and 1 or 0) end
    return ctl
end

return M
