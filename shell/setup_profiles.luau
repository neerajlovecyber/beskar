-- Portable setup profiles (C5, second increment): selective, data-only export / import of Appearance, frame / dock
-- preferences, dock pins and the widget desktop, applied across the three owners in STAGES with a recovery journal.
-- PURE controller: no IO, no timers, no scene state, no surface, no service, no globals. The HOST (Settings) moves
-- text and messages; this module decides, validates and remembers. Tests: lua tests/setup-profiles.lua
-- Runs under Luau and plain Lua: no bitwise operators, no integer division, no goto.
--
-- ══ What a setup contains ═════════════════════════════════════════════════════════════════════════════════════
--   { "kind": "beskar.setup", "version": 1, "sections": {
--       "appearance": { "values": { "appearance.mode": 1, "appearance.skin": 0, ... } },          owner settings
--       "frame":      { "values": { "frame.bar-style": 0, ..., "frame.output-name": "DP-1" } },    owner settings
--       "pins":       { "default": true }  |  { "list": ["org.gnome.Nautilus", "kitty"] },          owner topbar
--       "widgets":    { "snap": true, "cards": [ { id, out, kind, sz, x, y, opts?, stack? } ] } } } owner widgets
--   Every section is optional (selective). Values a file does not mention keep their live value. Only these ids exist
--   (M.FRAME_FIELDS, appearance ids come from preferences.APPEARANCE). NEVER portable, and refused with a message when a
--   file names them: commands, scripts, paths, URLs, credentials, Personal content (notes / to-dos), notification or
--   clipboard history, timers, display modes / arrangement, wallpaper files, other-app theming, derived palette colours,
--   plugins. Pins made from a running window (`app:<id>|<command line>`) hold a command: they are never exported, never
--   imported, and a local one is KEPT (appended) when an imported list replaces the portable pins.
--
-- ══ Host API ══════════════════════════════════════════════════════════════════════════════════════════════════
--   local SP  = require("setup_profiles")
--   local ctl = SP.new(adapter)
--     adapter.decode(text)      required: JSON text -> table (throws when malformed)      adapter.encode(t) optional
--     adapter.now()             optional: epoch seconds for journal stamps (0 when absent)
--     adapter.preferences       optional: the preferences module (default require("preferences"))
--     adapter.notify(status)    optional: called whenever ctl.status() changes
--     (a failed or stale step always rolls the already applied sections back: there is no "leave it half applied" mode)
--
--   LIVE STATE  (`live`, built by Settings from each owner's snapshot; a section the owner cannot answer yet is nil):
--     live.appearance = { values = <facts of P.appearance_snapshot>, palette = <usable palette | nil> }
--     live.frame      = { facts = { bar_style, pref_seconds, pref_weather, pref_tray, pref_workspaces, pref_bar_apps,
--                         pref_updates, dock_size_i, dock_delay_i, pref_dock_auto, bar_left_order, bar_right_order,
--                         module_output_policy, dock_output_policy, dock_show_delay, frame_output_name (TEXT) } }
--     live.pins       = { list = { pin strings as the dock file holds them } | nil = the automatic defaults,
--                         apps = { [desktop id] = true } optional: installed apps, to report missing pins }
--     live.widgets    = { ready = true, snap = bool, cards = { live card records } }
--     live.outputs    = { connected = { [NAME] = true } } optional: to report missing monitors
--
--   EXPORT  ctl.export(live, sections?)      -> text, doc, report | nil, failure, report
--           report = { included = {section...}, skipped = {{section, reason}}, excluded = {{section, message}} }
--   IMPORT  ctl.parse_import(text)           pure, strict, bounded -> { ok, doc, errors = {{path, code, message}} }
--           ctl.preview_import(text, live)   -> { ok, noop, token, order, sections = { name = { owner, noop, changes,
--                                               palette_refresh? } }, warnings = {{section, code, message, path}},
--                                               errors, message }.  Nothing is applied; a valid preview WITH changes is staged.
--           ctl.cancel_import()
--   APPLY   ctl.begin(token, live, { sections = {...}? })  -> { ok, journal_id, sections } | failure.  Refuses a stale
--                                               review (a section's live state changed since the preview), a missing owner
--                                               snapshot, an unrepresentable current state (the previous snapshot must be
--                                               lossless) and a journal over MAX_JOURNAL_BYTES: nothing has changed then.
--           ctl.next(live?)                    -> ACTION, see below.  Pull driver: call again after every answer.
--           ctl.persisted(seq, ok, why?)       answer to a `persist` action
--           ctl.ack(request, info)             answer to an `apply` action: info = { ok, untouched?, fp?, code?, message? }
--           ctl.timeout(request)               the owner did not answer: that step is of UNKNOWN state and is rolled back
--           ctl.retry()                        after `blocked` (a journal write failed): ask for the persist again
--           ctl.retry_rollback() / ctl.abandon()   after a rollback failed: try the failed sections again, or accept
--   UNDO    ctl.undo(live, { skip_stale = bool? })  one explicit undo of the last completed apply (also after a restart
--                                               once reconcile() loaded the journal). Each section must still be what the
--                                               apply left (fingerprint), unless skip_stale, which undoes only those.
--   RESTART ctl.reconcile(journal_text, live) -> { status, ... }   read the journal at startup (see below)
--           ctl.recover("rollback" | "keep", live)
--   ctl.status() -> { state, journal_id, op, steps = {{section, owner, state}}, message, blocked, undo_available, ... }
--
--   ACTIONS returned by ctl.next(live):
--     { kind = "persist", seq, text, journal_id }   write `text` ATOMICALLY (temp + rename) to the journal file, then call
--                                                   persisted(seq, true|false). No owner is touched before its "sent" entry
--                                                   is on disk; no result is acted on before it is on disk.
--     { kind = "apply", request, op = "apply"|"rollback"|"undo", section, owner, data, expect, force, palette_refresh,
--       text, journal_id, step }                    send to the section's OWNER (see below), then call ack(request, info).
--                                                   `data` is the section data; `text` the same as JSON (for a staging file).
--                                                   `expect` = fingerprint the owner must still hold (compare-and-swap) unless
--                                                   `force` (rollback). Owners answer with fp = SP.fingerprint(section, SP.snapshot(
--                                                   section, <their live state after the change>)).
--     { kind = "wait", reason = "persist" | "owner" | "blocked", request?, section?, owner? }
--     { kind = "finish", ok, code, message, applied = {...}, rolled_back = {...}, needs_attention = {{section, owner,
--       message}}, undo_available }                 the run is over (journal state done / rolled_back / rollback_failed /
--                                                   abandoned); needs_attention is non-empty only after a FAILED rollback
--     { kind = "idle" }
--
--   PURE HELPERS FOR OWNERS: SP.snapshot(section, raw_live, opts) -> data | nil, why (normalise an owner's live state),
--     SP.fingerprint(section, data) -> string, SP.validate_section(section, data, { local_pins = bool? }) -> data | nil,
--     errors, SP.to_facts(section, data) -> { fact = value } for the Settings sections.
--
-- ══ Owner operations the host must provide (the exact bridge) ═════════════════════════════════════════════════
--   SETTINGS (appearance, frame; coordinator and owner of both):
--     snapshot: facts above.  apply(data, expect, force): when not force and fingerprint(live) ~= expect answer
--       { ok=false, untouched=true, code="stale" } BEFORE changing anything; else set the facts through Settings' normal
--       apply (appearance: one undo entry as today; palette_refresh = true means colours are regenerated afterwards and
--       may finish after the ack; a rollback with data.palette restores it), set frame_output_name through its custom
--       text hook, save prefs.json / pleamar_shell.json through the existing serialised writer, and ACK ONLY WHEN THE
--       WRITE HAS COMMITTED. Facts only; never restarts or live-tests; never writes another owner's facts.
--   TOPBAR (pins): snapshot_pins() = the `pinned` list (nil when defaults) + installed app ids.
--     apply_pins(data, expect, force): data { default = true } deletes ~/.config/beskar/dock (back to defaults),
--       { list } writes it with the existing atomic writer. Needs one NEW function in topbar.luau: an apply that bypasses
--       the 150 ms-style debounce and calls back when the rename has finished (flush_pins' callback), because the ack
--       must mean "on disk". Compare-and-swap against the current list; a pin change racing it answers stale / untouched.
--   WIDGETS (widgets.json; its own process, so only SMALL messages cross): Settings writes the request data to a staging
--     file (request.text) under ~/.config/beskar/ and says `widgets` "emit setup_apply <request id>"; the widgets scene
--     reads that file (like personal_client), checks the id, validates with SP.validate_section("widgets", ...), compares
--     SP.fingerprint with `expect` (unless force) and answers stale / untouched BEFORE any change, then applies it exactly
--     like loading a saved layout (L.restore for connected outputs, cards on disconnected outputs kept hidden, stacks
--     normalised, ONE undo entry of widgets' own), saves widgets.json atomically and answers
--     `say settings "emit setup_ack <request id>|<ok 0/1>|<untouched 0/1>|<fp>|<code>"` once the file is written. A card
--     rejected by the owner's own rules is reported through a non-ok ack, never silently dropped.
--     snapshot: { ready, snap, cards (with opts and stack), connected outputs }.
--
--   Owners must handle requests ONE AT A TIME IN ORDER: after a timeout the controller sends a forced rollback, and a late
--   execution of the timed-out apply must not run after it. The `request` id carries the attempt number for that check.
--
-- ══ Recovery journal ══════════════════════════════════════════════════════════════════════════════════════════
--   One file, ~/.config/beskar/setup-journal.json (host-chosen), written whole and atomically by the host on every
--   `persist` action. Local, never exported (it may hold the user's own window pins). It carries, BEFORE any owner
--   is touched, the previous snapshot (`before`) and the target of every step. Steps are written "sent" before the
--   request leaves and "applied" / "failed" / "rolled_back" after the ack. There is NO claim of atomicity across
--   owners: a crash leaves some sections applied and some not, and the journal says which were in flight.
--   reconcile(text, live) at startup: terminal journals need nothing (a finished apply offers undo); otherwise each
--   unfinished step is compared with the live section: "untouched" (equals before), "applied" (equals the target or the
--   acked fingerprint), "diverged" (neither: partially applied, or changed since). Status "needs_recovery" lists them;
--   `waiting_for` names sections the live state did not carry yet (widgets start later): call again when available.
--   recover("rollback") restores `before` for applied / diverged steps (forced; warn about diverged), recover("keep")
--   accepts the current state (journal state "abandoned"). Both go through the same persisted / acknowledged pipeline.
--
-- ══ UI integration (Settings → General → "Portable setup", inside the existing Appearance/General tab, no new surface) ══
--   Export: section checkboxes (Appearance, Menu bar and dock, Pinned apps, Widgets) -> ctl.export -> clipboard (as the
--   appearance export does) + the report lines ("2 window pins left out: they contain commands").
--   Import: paste -> ctl.preview_import -> review list (changes per section with from/to, warnings in a second block, a
--   checkbox per section) -> "Apply" = ctl.begin + pump loop below. Show progress by status().steps; show the final
--   `finish` message; keep an "Undo setup" button while status().undo_available. On a failed rollback show
--   needs_attention with Retry / Accept current state. On startup call reconcile and show a banner for needs_recovery.
--   PUMP (host, one function, re-entered after every answer):
--     local act = ctl.next(live_now())           -- live_now() may be nil to skip coordinator-side stale checks
--     if act.kind == "persist" then write_journal(act.text, function(ok, why) ctl.persisted(act.seq, ok, why); pump() end)
--     elseif act.kind == "apply" then send_to_owner(act); (when the owner answers: ctl.ack(act.request, info); pump())
--          start a 10 s timer per request: on expiry ctl.timeout(act.request); pump()
--     elseif act.kind == "finish" then show(act) end
--
-- Limits: file import 64 KiB; 4 sections; 16 cards; 12 pins; fingerprints are rolling hashes (accident detection, not
-- security). A bounded checksum is not authentication: an import is data from a stranger and is always previewed first.

local M = {}

M.VERSION = 1
M.KIND = "beskar.setup"
M.JOURNAL_KIND = "beskar.setup-journal"
M.JOURNAL_VERSION = 1
M.SECTIONS = { "appearance", "frame", "pins", "widgets" }       -- the apply order; rollback is the reverse
M.OWNER = { appearance = "settings", frame = "settings", pins = "topbar", widgets = "widgets" }
M.TITLES = { appearance = "Appearance", frame = "Menu bar and dock", pins = "Pinned apps", widgets = "Widgets" }
M.MAX_IMPORT_BYTES = 65536
M.MAX_JOURNAL_BYTES = 131072
M.MAX_ERRORS = 12
M.MAX_WARNINGS = 24
-- Mirrors of the owners' bounds (a test compares them with widget_layouts / frame_options / widget_stacks)
M.MAX_PINS = 12
M.MAX_PIN_PORTABLE = 128
M.MAX_PIN_LOCAL = 512
M.MAX_CARDS = 16
M.MAX_CARD_ID = 2147483647
M.MAX_COORD = 100000
M.MAX_OUT = 64
M.MAX_KIND = 1000
M.MAX_UNKNOWN_OPTS = 8
M.MAX_STACK_MEMBERS = 8
M.MAX_STACK_ID = 2147483646
M.MAX_STACK_ORDER = 1000
M.MAX_OUTPUT_NAME = 64
M.OUTPUT_NAME_PATTERN = "^[%w_.:+%-]+$"

local MAX_DEPTH = 8

-- ── optional pure neighbours ─────────────────────────────────────
-- widgets_data is plain data; widget_stacks is pure. Both are loaded defensively: when one is missing or changes
-- shape, widget kinds count as unknown (kept) and stacks are checked by this module's own conservative rules.
local okd, Data = pcall(require, "widgets_data")
if not okd or type(Data) ~= "table" then Data = { KINDS = {}, OPTIONS = {}, OPTION_ORDER = {} } end
local KIND_BY_ID = {}
for _, k in ipairs(Data.KINDS or {}) do KIND_BY_ID[k.id] = k end
local oks, Stacks = pcall(require, "widget_stacks")
if not oks or type(Stacks) ~= "table" then Stacks = nil end
if Stacks and type(Stacks.MAX_MEMBERS) == "number" then M.MAX_STACK_MEMBERS = Stacks.MAX_MEMBERS end

-- ── generic helpers ──────────────────────────────────────────────

local function copy(v, depth)
    if type(v) ~= "table" then return v end
    depth = depth or 0
    if depth > MAX_DEPTH then return nil end
    local out = {}
    for k, x in pairs(v) do out[k] = copy(x, depth + 1) end
    return out
end

local function count_of(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

local function is_list(t) return type(t) == "table" and count_of(t) == #t end
local function is_obj(t) return type(t) == "table" and #t == 0 end

local function is_hex(s) return type(s) == "string" and s:match("^#%x%x%x%x%x%x$") ~= nil end

local function strict_int(v, lo, hi)
    if type(v) ~= "number" or v ~= v or v == math.huge or v == -math.huge then return nil end
    if v ~= math.floor(v) or math.abs(v) > 2 ^ 31 then return nil end
    if lo and (v < lo or v > hi) then return nil end
    return math.floor(v)
end

local function show(v)
    local s = type(v) == "table" and "<table>" or tostring(v)
    s = s:gsub("%c", "?")
    if #s > 40 then
        s = s:sub(1, 40)
        while #s > 0 and not utf8.len(s) do s = s:sub(1, -2) end
        s = s .. "..."
    end
    return s
end

local function fail(code, message, extra)
    local r = extra or {}
    r.ok, r.code, r.message = false, code, message
    return r
end

local function sorted_keys(t)
    local keys = {}
    for k in pairs(t) do
        if type(k) == "string" then keys[#keys + 1] = k end
    end
    table.sort(keys)
    return keys
end

-- JSON text with sorted keys; arrays only when non-empty. Also the canonical form behind fingerprints.
local ESC = { ['"'] = '\\"', ["\\"] = "\\\\", ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t" }
local function enc_str(s)
    return '"' .. s:gsub('[%c"\\]', function(c) return ESC[c] or string.format("\\u%04x", c:byte()) end) .. '"'
end
local function enc(v, depth)
    local t = type(v)
    if t == "boolean" then return tostring(v) end
    if t == "string" then return enc_str(v) end
    if t == "number" then
        if v ~= v or v == math.huge or v == -math.huge then return nil end
        if v == math.floor(v) and math.abs(v) < 2 ^ 53 then return string.format("%d", v) end
        return string.format("%.17g", v)
    end
    if t ~= "table" or depth > MAX_DEPTH + 2 then return nil end
    local n = #v
    local parts = {}
    if n > 0 and count_of(v) == n then
        for i = 1, n do
            local e = enc(v[i], depth + 1)
            if e == nil then return nil end
            parts[#parts + 1] = e
        end
        return "[" .. table.concat(parts, ", ") .. "]"
    end
    for _, k in ipairs(sorted_keys(v)) do
        local e = enc(v[k], depth + 1)
        if e ~= nil then parts[#parts + 1] = enc_str(k) .. ": " .. e end
    end
    return "{" .. table.concat(parts, ", ") .. "}"
end

-- two rolling hashes (arithmetic only: exact in doubles) + the length
local function hash_text(s)
    local h1, h2 = 5381, 52711
    for i = 1, #s do
        local b = s:byte(i)
        h1 = (h1 * 257 + b) % 2147483629
        h2 = (h2 * 131 + b + i) % 2147483587
    end
    return string.format("%08x%08x:%d", h1, h2, #s)
end

-- ── error / warning collectors ───────────────────────────────────

local function collector()
    local c = { errors = {}, warnings = {}, seen = {} }
    function c.err(path, code, message)
        if #c.errors < M.MAX_ERRORS then c.errors[#c.errors + 1] = { path = path, code = code, message = message }
        elseif #c.errors == M.MAX_ERRORS then c.errors[#c.errors + 1] = { path = "", code = "more", message = "More problems were found." } end
    end
    function c.warn(section, code, message, path)
        local key = section .. code .. message
        if c.seen[key] or #c.warnings >= M.MAX_WARNINGS then return end
        c.seen[key] = true
        c.warnings[#c.warnings + 1] = { section = section, code = code, message = message, path = path }
    end
    return c
end

-- ── field descriptors ────────────────────────────────────────────
-- type: bool | enum (integer min..max) | choice (integer from `choices`) | text (maxlen, pattern; "" allowed)

local ONOFF = { [false] = "Off", [true] = "On" }
local DELAY = { [0] = "Quick", "Standard", "Relaxed" }
M.FRAME_FIELDS = {
    { id = "frame.bar-style", fact = "bar_style", type = "enum", min = 0, max = 1, default = 0, label = "Menu bar style", labels = { [0] = "Notch", "Strip" } },
    { id = "frame.seconds", fact = "pref_seconds", type = "bool", default = false, label = "Seconds in the clock", labels = ONOFF },
    { id = "frame.weather", fact = "pref_weather", type = "bool", default = true, label = "Weather in the menu bar", labels = ONOFF },
    { id = "frame.tray", fact = "pref_tray", type = "bool", default = true, label = "Tray icons", labels = ONOFF },
    { id = "frame.workspaces", fact = "pref_workspaces", type = "bool", default = true, label = "Workspaces", labels = ONOFF },
    { id = "frame.bar-apps", fact = "pref_bar_apps", type = "bool", default = true, label = "App name in the menu bar", labels = ONOFF },
    { id = "frame.updates", fact = "pref_updates", type = "bool", default = true, label = "Update indicator", labels = ONOFF },
    { id = "frame.dock-size", fact = "dock_size_i", type = "enum", min = 0, max = 2, default = 1, label = "Dock icon size", labels = { [0] = "Small", "Standard", "Large" } },
    { id = "frame.dock-delay", fact = "dock_delay_i", type = "enum", min = 0, max = 2, default = 1, label = "Dock hide delay", labels = DELAY },
    { id = "frame.dock-auto", fact = "pref_dock_auto", type = "bool", default = true, label = "Hide the dock automatically", labels = ONOFF },
    { id = "frame.bar-left-order", fact = "bar_left_order", type = "enum", min = 0, max = 1, default = 0, label = "Left bar order" },
    { id = "frame.bar-right-order", fact = "bar_right_order", type = "enum", min = 0, max = 1, default = 0, label = "Right bar order" },
    { id = "frame.module-output-policy", fact = "module_output_policy", type = "enum", min = 0, max = 2, default = 0, label = "Bar modules on monitors" },
    { id = "frame.dock-output-policy", fact = "dock_output_policy", type = "enum", min = 0, max = 2, default = 0, label = "Dock on monitors" },
    { id = "frame.dock-show-delay", fact = "dock_show_delay", type = "enum", min = 0, max = 2, default = 0, label = "Dock reveal delay", labels = DELAY },
    { id = "frame.output-name", fact = "frame_output_name", type = "text", maxlen = M.MAX_OUTPUT_NAME, pattern = M.OUTPUT_NAME_PATTERN,
      default = "", label = "Frame monitor" },
}

-- one control value, exact type and range (an import is not a legacy file: nothing is coerced); v | nil, why
local function strict_value(f, raw)
    if f.type == "bool" then
        if type(raw) ~= "boolean" then return nil, "must be true or false (got " .. show(raw) .. ")" end
        return raw
    end
    if f.type == "text" then
        if type(raw) ~= "string" then return nil, "must be text (got " .. show(raw) .. ")" end
        if raw == "" then return "" end
        if #raw > f.maxlen then return nil, string.format("is longer than %d characters", f.maxlen) end
        if not raw:match(f.pattern) then return nil, "contains characters that are not allowed (use letters, digits and _ . : + -)" end
        return raw
    end
    local n = strict_int(raw)
    if n == nil then return nil, "must be a whole number (got " .. show(raw) .. ")" end
    if f.type == "enum" then
        if n < f.min or n > f.max then return nil, string.format("must be from %d to %d (got %s)", f.min, f.max, show(raw)) end
        return n
    end
    for _, c in ipairs(f.choices or {}) do
        if c == n then return n end
    end
    return nil, "is not one of the allowed choices (got " .. show(raw) .. ")"
end

local function label_of(f, v)
    if f.labels and f.labels[v] ~= nil then return f.labels[v] end
    if f.type == "text" then return v == "" and "Follow the focused monitor" or tostring(v) end
    return tostring(v)
end

-- ── the module that needs the preferences schema ─────────────────

local function appearance_fields(P)
    if not P or type(P.APPEARANCE) ~= "table" then return nil end
    local out = {}
    for _, a in ipairs(P.APPEARANCE) do
        local f = a.field
        out[#out + 1] = { id = a.id, fact = a.fact, type = f.type, min = f.min, max = f.max, choices = f.choices,
            default = f.default, label = a.label or a.id, labels = a.labels }
    end
    return out
end

-- ── the denied vocabulary (messages for what is never portable) ──

local DENIED = {
    "command", "exec", "script", "shell", "path", "file", "url", "token", "password", "secret", "credential",
    "content", "note", "todo", "clipboard", "notification", "history", "display", "output", "monitor", "timer",
    "wallpaper", "apps", "plugin", "palette", "areas", "mode",
}
local function unsupported_message(key)
    local lower = key:lower()
    for _, word in ipairs(DENIED) do
        if lower:find(word, 1, true) then
            return string.format("'%s' is not portable: commands, paths, credentials, personal content, history, display modes, timers, wallpaper files, app integration and generated colours are never imported.", show(key))
        end
    end
    return string.format("'%s' is not a supported setting.", show(key))
end

-- ══ section validators ═══════════════════════════════════════════
-- Each returns normalised data or nil (errors in `c`). `internal` (the journal) also accepts local-only content.

local function check_values(section, raw, fields, c, partial)
    local by_id = {}
    for _, f in ipairs(fields) do by_id[f.id] = f end
    local base = section .. ".values"
    if type(raw) ~= "table" or not is_obj(raw) then
        c.err(base, "type", "This section has no values.")
        return nil
    end
    local ok = true
    local n = 0
    for key in pairs(raw) do
        n = n + 1
        if type(key) ~= "string" or #key > 64 then
            c.err(base, "unsupported", "A setting has an invalid name."); ok = false
        elseif not by_id[key] then
            c.err(base .. "." .. show(key), "unsupported", unsupported_message(key)); ok = false
        end
    end
    if n == 0 then c.err(base, "empty", "This section contains no choices."); return nil end
    local values = {}
    for _, f in ipairs(fields) do
        local r = raw[f.id]
        if r ~= nil then
            local v, why = strict_value(f, r)
            if v == nil then c.err(base .. "." .. f.id, "value", (f.label or f.id) .. " " .. why .. "."); ok = false
            else values[f.id] = v end
        elseif not partial then
            c.err(base .. "." .. f.id, "missing", (f.label or f.id) .. " is missing."); ok = false
        end
    end
    if not ok then return nil end
    return { values = values }
end

local function check_palette(raw)
    if type(raw) ~= "table" or not is_obj(raw) then return nil end
    for k in pairs(raw) do
        if k ~= "style" and k ~= "src" and k ~= "dark" and k ~= "light" then return nil end
    end
    local out = { style = strict_int(raw.style, 0, 3) }
    if out.style == nil then return nil end
    if raw.src ~= nil then
        if not is_hex(raw.src) then return nil end
        out.src = raw.src:lower()
    end
    for _, mode in ipairs({ "dark", "light" }) do
        local s = raw[mode]
        if type(s) ~= "table" or not (is_hex(s.a) and is_hex(s.b) and is_hex(s.s)) then return nil end
        out[mode] = { a = s.a:lower(), b = s.b:lower(), s = s.s:lower() }
    end
    return out
end

local function pin_ok(p, local_mode)
    if type(p) ~= "string" or p == "" then return false, "is not text" end
    if local_mode then
        if #p > M.MAX_PIN_LOCAL then return false, "is too long" end
        if p:find("%c") or not p:find("%S") then return false, "has control characters" end
        return true
    end
    if p:match("^app:") or p:find("|", 1, true) or p:find("/", 1, true) or p:find("%s") then
        return false, "contains a command or a path, which a setup never carries"
    end
    if #p > M.MAX_PIN_PORTABLE then return false, "is too long" end
    if not p:match("^[%w_.+%-]+$") then return false, "is not a plain application id" end
    return true
end

local function check_pins(raw, c, local_mode)
    if type(raw) ~= "table" or not is_obj(raw) then c.err("pins", "type", "The pinned apps are not valid."); return nil end
    for k in pairs(raw) do
        if k ~= "default" and k ~= "list" then c.err("pins." .. show(k), "unsupported", unsupported_message(tostring(k))); return nil end
    end
    if raw.default ~= nil and raw.list ~= nil then c.err("pins", "type", "Choose either the automatic pins or a list."); return nil end
    if raw.default ~= nil then
        if raw.default ~= true then c.err("pins.default", "value", "default must be true."); return nil end
        return { default = true }
    end
    local list = raw.list
    if type(list) ~= "table" or not is_list(list) then c.err("pins.list", "type", "The pinned apps must be a list."); return nil end
    if #list > M.MAX_PINS then c.err("pins.list", "size", string.format("At most %d pinned apps are supported.", M.MAX_PINS)); return nil end
    local out, seen, ok = {}, {}, true
    for i, p in ipairs(list) do
        local good, why = pin_ok(p, local_mode)
        if not good then c.err("pins.list." .. i, "value", "Pin " .. i .. " " .. why .. "."); ok = false
        elseif seen[p] then c.err("pins.list." .. i, "duplicate", "Pin " .. i .. " is listed twice."); ok = false
        else seen[p] = true; out[#out + 1] = p end
    end
    if not ok then return nil end
    return { list = out }
end

-- ── widget cards ──

local function kind_def(kind) return KIND_BY_ID[kind] end

local function option_applies(def, kind)
    if not def.kinds then return true end
    for _, k in ipairs(def.kinds) do
        if k == kind then return true end
    end
    return false
end

local function key_index(def, v)
    for i, k in ipairs(def.keys) do
        if k == v then return i end
    end
end

-- validated, canonical opts (defaults dropped) | nil (none), ok
local function check_opts(kind, raw, path, c)
    if raw == nil then return nil, true end
    if type(raw) ~= "table" or not is_obj(raw) then c.err(path, "type", "Card options must be an object."); return nil, false end
    local known_kind = kind_def(kind) ~= nil
    local out, unknown, ok = {}, 0, true
    for _, key in ipairs(sorted_keys(raw)) do
        local v = raw[key]
        local def = Data.OPTIONS and Data.OPTIONS[key]
        if def and option_applies(def, kind) then
            local i = key_index(def, v)
            if not i then c.err(path .. "." .. key, "value", "The card option '" .. key .. "' has a value this Beskar does not know."); ok = false
            elseif i > 1 then out[key] = def.keys[i] end
        elseif def and known_kind then
            c.err(path .. "." .. key, "unsupported", "The card option '" .. key .. "' does not apply to this widget.")
            ok = false
        else
            -- an option this build does not know (or a kind it does not know): a plain bounded value is preserved
            if #key > 24 or not key:match("^[%a_][%w_]*$") then c.err(path, "unsupported", "A card option has an invalid name."); ok = false
            elseif not (type(v) == "boolean" or (type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge)
                or (type(v) == "string" and #v <= 32 and not v:find("%c"))) then
                c.err(path .. "." .. key, "type", "The card option '" .. key .. "' is not a plain value."); ok = false
            else
                unknown = unknown + 1
                if unknown > M.MAX_UNKNOWN_OPTS then c.err(path, "size", "A card has too many options."); ok = false
                else out[key] = v end
                c.warn("widgets", "unknown_option", "Some card options are unknown to this Beskar: they are kept as they are and may be ignored.", path)
            end
        end
    end
    if not ok then return nil, false end
    if next(out) == nil then return nil, true end
    return out, true
end

local CARD_KEYS = { id = true, out = true, kind = true, sz = true, x = true, y = true, opts = true, stack = true }

local function check_stack(raw, path, c)
    if raw == nil then return nil, true end
    if type(raw) ~= "table" or not is_obj(raw) then c.err(path, "type", "The stack record is not valid."); return nil, false end
    for k in pairs(raw) do
        if k ~= "id" and k ~= "i" and k ~= "on" then
            c.err(path .. "." .. show(k), "unsupported", "The stack record has an unknown field '" .. show(k) .. "'.")
            return nil, false
        end
    end
    local id, i = strict_int(raw.id, 1, M.MAX_STACK_ID), strict_int(raw.i, 1, M.MAX_STACK_ORDER)
    if not id or not i then c.err(path, "value", "The stack record has an invalid id or position."); return nil, false end
    if raw.on ~= nil and type(raw.on) ~= "boolean" then c.err(path .. ".on", "type", "The stack's active flag must be true or false."); return nil, false end
    return { id = id, i = i, on = raw.on == true or nil }, true
end

-- one card -> canonical card | nil (errors / warnings collected)
local function check_card(raw, path, c)
    if type(raw) ~= "table" or not is_obj(raw) then c.err(path, "type", "A widget card is not valid."); return nil end
    local ok = true
    for k in pairs(raw) do
        if not CARD_KEYS[k] then
            c.err(path .. "." .. show(k), "unsupported", "A card has an unknown field '" .. show(k) .. "'.")
            ok = false
        end
    end
    local id = strict_int(raw.id, 1, M.MAX_CARD_ID)
    if not id then c.err(path .. ".id", "value", "A card has no valid id."); ok = false end
    if type(raw.out) ~= "string" or #raw.out < 1 or #raw.out > M.MAX_OUT or raw.out:find("%c") then
        c.err(path .. ".out", "value", "A card names no valid monitor."); ok = false
    end
    local kind = strict_int(raw.kind, 1, M.MAX_KIND)
    if not kind then c.err(path .. ".kind", "value", "A card has no valid widget kind."); ok = false end
    local sz = strict_int(raw.sz, 0, 2)
    if not sz then c.err(path .. ".sz", "value", "A card has no valid size."); ok = false end
    local x, y = strict_int(raw.x, -M.MAX_COORD, M.MAX_COORD), strict_int(raw.y, -M.MAX_COORD, M.MAX_COORD)
    if not x or not y then c.err(path, "value", "A card has no valid position."); ok = false end
    local opts, opts_ok = check_opts(kind or 0, raw.opts, path .. ".opts", c)
    local stack, stack_ok = check_stack(raw.stack, path .. ".stack", c)
    if not (ok and opts_ok and stack_ok) then return nil end
    local card = { id = id, out = raw.out, kind = kind, sz = sz, x = x, y = y, opts = opts, stack = stack }
    return card
end

local function nearest_size(def, sz)
    local best, gap = def.def or def.sizes[1], 99
    for _, s in ipairs(def.sizes) do
        if math.abs(s - sz) < gap then best, gap = s, math.abs(s - sz) end
    end
    return best
end

local function card_locked(card) return card.opts ~= nil and card.opts.lock == true end

-- stack structure (own rules, then the owner's own `normalize` as an oracle): true | false, message
local function check_stacks(cards, c)
    local groups, order = {}, {}
    for _, card in ipairs(cards) do
        if card.stack then
            local g = groups[card.stack.id]
            if not g then g = {}; groups[card.stack.id] = g; order[#order + 1] = card.stack.id end
            g[#g + 1] = card
        end
    end
    local function bad(msg) c.err("widgets.cards", "stack", msg) return false end
    for _, id in ipairs(order) do
        local g = groups[id]
        if #g < 2 then return bad("A widget stack has only one member.") end
        if #g > M.MAX_STACK_MEMBERS then return bad(string.format("A widget stack has more than %d members.", M.MAX_STACK_MEMBERS)) end
        local active, orders, locks = 0, {}, 0
        for _, m in ipairs(g) do
            if m.stack.on then active = active + 1 end
            if orders[m.stack.i] then return bad("A widget stack repeats a page position.") end
            orders[m.stack.i] = true
            if m.out ~= g[1].out or m.x ~= g[1].x or m.y ~= g[1].y or m.sz ~= g[1].sz then
                return bad("The members of a widget stack do not share one footprint.")
            end
            if card_locked(m) then locks = locks + 1 end
        end
        if active ~= 1 then return bad("A widget stack must have exactly one active member.") end
        local positions = {}
        for _, m in ipairs(g) do positions[#positions + 1] = m.stack.i end
        table.sort(positions)
        for k, v in ipairs(positions) do
            if v ~= k then
                c.warn("widgets", "stack_renumbered", "A widget stack has gaps in its page order: Widgets renumbers the pages (their order is kept).")
                break
            end
        end
        if locks ~= 0 and locks ~= #g then return bad("Position lock must apply to a whole widget stack.") end
        for _, m in ipairs(g) do
            local def = kind_def(m.kind)
            if def then
                local fits = false
                for _, s in ipairs(def.sizes) do if s == m.sz then fits = true end end
                if not fits then return bad("A stacked widget does not support the stack's size.") end
            end
        end
    end
    if Stacks and type(Stacks.normalize) == "function" and #order > 0 then
        local probe = copy(cards)
        local okn, changed = pcall(Stacks.normalize, probe, function(kind) return kind_def(kind) or { sizes = { 0, 1, 2 } } end)
        if okn and changed then return bad("A widget stack is not consistent with Beskar's stack rules.") end
    end
    return true
end

-- strict widget section (a file, or a validated live snapshot) -> data | nil
local function check_widgets(raw, c, live)
    if type(raw) ~= "table" or not is_obj(raw) then c.err("widgets", "type", "The widget desktop is not valid."); return nil end
    for k in pairs(raw) do
        if k ~= "snap" and k ~= "cards" then
            c.err("widgets." .. show(k), "unsupported", k == "areas"
                and "Monitor sizes are machine-specific and are not imported."
                or unsupported_message(tostring(k)))
            return nil
        end
    end
    if raw.snap ~= nil and type(raw.snap) ~= "boolean" then c.err("widgets.snap", "type", "Grid snapping must be true or false."); return nil end
    local list = raw.cards
    if list == nil then list = {} end
    if type(list) ~= "table" or not is_list(list) then c.err("widgets.cards", "type", "The widget cards must be a list."); return nil end
    if #list > M.MAX_CARDS then c.err("widgets.cards", "size", string.format("At most %d widget cards are supported.", M.MAX_CARDS)); return nil end
    local cards, seen, ok = {}, {}, true
    for i, r in ipairs(list) do
        local card = check_card(r, "widgets.cards." .. i, c)
        if not card then ok = false
        elseif seen[card.id] then c.err("widgets.cards." .. i, "duplicate", "Two cards share the same id."); ok = false
        else seen[card.id] = true; cards[#cards + 1] = card end
    end
    if not ok then return nil end
    if not check_stacks(cards, c) then return nil end
    -- reports (never errors): unknown kinds are kept hidden until supported, sizes are adjusted by Widgets, absent monitors wait
    local connected = live and live.outputs and live.outputs.connected
    for i, card in ipairs(cards) do
        local def = kind_def(card.kind)
        local path = "widgets.cards." .. i
        if not def then
            c.warn("widgets", "unknown_kind", string.format("Widget kind %d is not known to this Beskar: it is kept and stays hidden until a version that knows it.", card.kind), path)
        elseif not card.stack then
            local fits = false
            for _, s in ipairs(def.sizes) do if s == card.sz then fits = true end end
            if not fits then
                c.warn("widgets", "size_adjusted", string.format("%s cannot be that size: Widgets will use the nearest one.", def.name), path)
            end
        end
        if connected and not connected[card.out] then
            c.warn("widgets", "missing_output", string.format("Monitor %s is not connected: its widgets are kept and appear when it returns.", show(card.out)), path)
        end
    end
    return { snap = raw.snap ~= false, cards = cards }
end

-- ══ live snapshots (what an owner is NOW), tolerant: they describe, they do not judge ══

local function live_values(fields, facts)
    local values = {}
    for _, f in ipairs(fields) do
        local v = nil
        if type(facts) == "table" and facts[f.fact] ~= nil then v = strict_value(f, facts[f.fact]) end
        if v == nil then v = f.default end
        values[f.id] = v
    end
    return values
end

-- the pins as the dock file holds them -> data | nil, why.  Lossless or nothing (the previous snapshot must restore).
local function live_pins(raw)
    if type(raw) ~= "table" then return nil, "no pins snapshot" end
    if raw.list == nil then return { default = true } end
    local c = collector()
    local data = check_pins({ list = raw.list }, c, true)
    if not data then return nil, c.errors[1] and c.errors[1].message or "pins" end
    return data
end

-- live widget desktop -> data, skipped (cards that could not be represented)
local function live_widgets(raw, c)
    if type(raw) ~= "table" or raw.ready == false then return nil, 0 end
    local cards, seen, skipped = {}, {}, 0
    local probe = collector()
    for i, r in ipairs(type(raw.cards) == "table" and raw.cards or {}) do
        local card = nil
        if type(r) == "table" then
            local clean = {}
            for k, v in pairs(r) do if CARD_KEYS[k] then clean[k] = v end end
            card = check_card(clean, "widgets.cards." .. i, probe)
        end
        if not card or seen[card.id] or #cards >= M.MAX_CARDS then skipped = skipped + 1
        else seen[card.id] = true; cards[#cards + 1] = card end
    end
    return { snap = raw.snap ~= false, cards = cards }, skipped
end

local function card_sig(card)
    local s = string.format("%s|%d|%d|%d|%d", card.out, card.kind, card.sz, card.x, card.y)
    if card.opts then s = s .. "|o" .. enc(card.opts, 0) end
    if card.stack then s = s .. string.format("|s%d%s", card.stack.i, card.stack.on and "*" or "") end
    return s
end

-- ── public pure helpers ──

function M.fingerprint(section, data)
    if type(data) ~= "table" then return nil end
    local canon
    if section == "appearance" or section == "frame" then
        canon = enc(data.values or {}, 0)
    elseif section == "pins" then
        canon = data.default and "default" or enc(data.list or {}, 0)
    elseif section == "widgets" then
        local sigs = {}
        for _, card in ipairs(data.cards or {}) do sigs[#sigs + 1] = card_sig(card) end
        table.sort(sigs)
        canon = (data.snap == false and "free;" or "snap;") .. table.concat(sigs, ";")
    else
        return nil
    end
    if not canon then return nil end
    return hash_text(section .. ":" .. canon)
end

-- one section in its normalised form from an owner's live state | nil, why
function M.snapshot(section, raw, opts)
    opts = opts or {}
    local P = opts.preferences
    if section == "appearance" then
        local fields = appearance_fields(P)
        if not fields or type(raw) ~= "table" then return nil, "unavailable" end
        local facts = raw.values or raw
        local snap = P.appearance_snapshot(facts, raw.palette)
        local data = { values = live_values(fields, snap.values) }
        if snap.palette then data.palette = copy(snap.palette) end
        return data
    elseif section == "frame" then
        if type(raw) ~= "table" then return nil, "unavailable" end
        return { values = live_values(M.FRAME_FIELDS, raw.facts or raw) }
    elseif section == "pins" then
        return live_pins(raw)
    elseif section == "widgets" then
        local data, skipped = live_widgets(raw)
        if not data then return nil, "unavailable" end
        if skipped > 0 then return nil, string.format("%d widget cards cannot be represented", skipped) end
        local c = collector()
        if not check_stacks(data.cards, c) then return nil, c.errors[1] and c.errors[1].message or "inconsistent stacks" end
        return data
    end
    return nil, "unknown section"
end

-- the strict validation an owner repeats before it applies a request | data | nil, errors
function M.validate_section(section, data, opts)
    opts = opts or {}
    local c = collector()
    local out
    if section == "appearance" then
        local fields = appearance_fields(opts.preferences)
        if not fields then c.err("appearance", "unavailable", "Appearance is not available."); return nil, c.errors end
        out = check_values(section, (data or {}).values, fields, c, true)
        if out and type(data) == "table" and data.palette ~= nil then
            local pal = check_palette(data.palette)
            if not pal then
                c.err("appearance.palette", "value", "The colour cache is not valid.")
                out = nil
            else
                out.palette = pal
            end
        end
    elseif section == "frame" then
        out = check_values(section, (data or {}).values, M.FRAME_FIELDS, c, true)
    elseif section == "pins" then
        out = check_pins(data, c, opts.local_pins == true)
    elseif section == "widgets" then
        out = check_widgets(data, c, opts.live)
    else
        c.err(tostring(section), "unsupported", "Unknown section.")
    end
    if not out or #c.errors > 0 then return nil, c.errors end
    return out, c.errors, c.warnings
end

-- the facts a Settings section sets (appearance and frame): { fact = value }
function M.to_facts(section, data, opts)
    local fields
    if section == "appearance" then fields = appearance_fields((opts or {}).preferences)
    elseif section == "frame" then fields = M.FRAME_FIELDS end
    local facts = {}
    if not fields or type(data) ~= "table" then return facts end
    for _, f in ipairs(fields) do
        local v = data.values and data.values[f.id]
        if v ~= nil then facts[f.fact] = v end
    end
    return facts
end

-- ══ the controller ═══════════════════════════════════════════════

local STEP_STATES = { pending = true, sent = true, applied = true, failed_clean = true, failed = true,
    rolling_back = true, rolled_back = true, rollback_failed = true }
local JOURNAL_STATES = { prepared = true, running = true, rolling_back = true, done = true, rolled_back = true,
    rollback_failed = true, abandoned = true }
local TERMINAL = { done = true, rolled_back = true, rollback_failed = true, abandoned = true }
local OPS = { apply = true, undo = true, recover = true }

function M.new(adapter)
    adapter = adapter or {}
    local P = adapter.preferences
    if P == nil then
        local okp, mod = pcall(require, "preferences")
        if okp then P = mod end
    end
    local notify = adapter.notify or function() end
    local now = adapter.now or function() return 0 end
    local ctl = {}

    local a_fields = appearance_fields(P)
    local function fields_of(section)
        if section == "appearance" then return a_fields end
        if section == "frame" then return M.FRAME_FIELDS end
    end

    local function decode(text)
        if type(adapter.decode) ~= "function" then error("setup_profiles: adapter.decode required", 3) end
        return pcall(adapter.decode, text)
    end
    local function text_of(doc)
        if type(adapter.encode) == "function" then
            local ok, out = pcall(adapter.encode, doc)
            if ok and type(out) == "string" then return out end
            return nil
        end
        return enc(doc, 0)
    end

    local staged, token_seq = nil, 0
    local run = nil                 -- the current journal run
    local last_done = nil           -- the journal of the last completed apply (undo source)
    local recovery = nil            -- a parsed unfinished journal waiting for a decision
    local journal_counter = 0
    local last_message = nil

    local function snapshot_of(section, live)
        local raw = live and live[section]
        if raw == nil then return nil, "unavailable" end
        return M.snapshot(section, raw, { preferences = P })
    end

    -- ── status ──
    function ctl.status()
        local s = { state = "idle", undo_available = last_done ~= nil, message = last_message, steps = {} }
        if staged then s.state = "preview"; s.token = staged.token end
        if recovery then s.state = "needs_recovery" end
        if run then
            local j = run.journal
            s.journal_id, s.op = j.id, j.op
            s.state = run.blocked and "blocked" or (TERMINAL[j.state] and (j.state == "done" and "done" or j.state) or "running")
            s.blocked = run.blocked and copy(run.blocked) or nil
            for i, st in ipairs(j.steps) do s.steps[i] = { section = st.section, owner = st.owner, state = st.state } end
            if run.failure then s.failure = copy(run.failure) end
        end
        return s
    end
    local function publish() notify(ctl.status()) end

    -- ── export ──
    function ctl.export(live, sections)
        local want = {}
        if sections == nil then
            for _, s in ipairs(M.SECTIONS) do want[#want + 1] = s end
        else
            for _, s in ipairs(sections) do
                if not M.OWNER[s] then return nil, fail("section", "Unknown section " .. show(s) .. "."), nil end
                want[#want + 1] = s
            end
        end
        local doc = { kind = M.KIND, version = M.VERSION, sections = {} }
        local report = { included = {}, skipped = {}, excluded = {} }
        for _, section in ipairs(M.SECTIONS) do
            local selected = false
            for _, w in ipairs(want) do if w == section then selected = true end end
            if selected then
                local raw = live and live[section]
                if section == "appearance" or section == "frame" then
                    local data, why = M.snapshot(section, raw, { preferences = P })
                    if not data then report.skipped[#report.skipped + 1] = { section = section, reason = why or "unavailable" }
                    else
                        doc.sections[section] = { values = copy(data.values) }
                        report.included[#report.included + 1] = section
                    end
                elseif section == "pins" then
                    if type(raw) ~= "table" then report.skipped[#report.skipped + 1] = { section = section, reason = "unavailable" }
                    elseif raw.list == nil then
                        doc.sections.pins = { default = true }
                        report.included[#report.included + 1] = section
                    else
                        local list, left_out = {}, 0
                        for _, p in ipairs(raw.list) do
                            if pin_ok(p, false) and #list < M.MAX_PINS then list[#list + 1] = p else left_out = left_out + 1 end
                        end
                        doc.sections.pins = { list = list }
                        report.included[#report.included + 1] = section
                        if left_out > 0 then
                            report.excluded[#report.excluded + 1] = { section = section, message = string.format(
                                "%d pinned %s left out: made from a running window, they contain a command line.", left_out, left_out == 1 and "app was" or "apps were") }
                        end
                    end
                elseif section == "widgets" then
                    local data, skipped = live_widgets(raw)
                    if not data then report.skipped[#report.skipped + 1] = { section = section, reason = "unavailable" }
                    else
                        local c = collector()
                        local checked = check_widgets({ snap = data.snap, cards = data.cards }, c, nil)
                        if not checked then
                            report.skipped[#report.skipped + 1] = { section = section, reason = c.errors[1] and c.errors[1].message or "invalid" }
                        else
                            doc.sections.widgets = { snap = checked.snap, cards = copy(checked.cards) }
                            report.included[#report.included + 1] = section
                            if skipped > 0 then
                                report.excluded[#report.excluded + 1] = { section = section, message = string.format(
                                    "%d widget %s left out because %s not valid.", skipped, skipped == 1 and "card was" or "cards were", skipped == 1 and "it is" or "they are") }
                            end
                        end
                    end
                end
            end
        end
        if next(doc.sections) == nil then return nil, fail("empty", "There is nothing to export."), report end
        local text = text_of(doc)
        if not text then return nil, fail("encode", "Could not write the export."), report end
        if #text > M.MAX_IMPORT_BYTES then return nil, fail("size", "The setup is too large to export."), report end
        -- belt and braces: what we export must import
        local re = ctl.parse_import(text)
        if not re.ok then return nil, fail("export", "The setup could not be verified: " .. tostring(re.message)), report end
        return text, doc, report
    end

    -- ── import ──
    local function parse_doc(doc, live)
        local c = collector()
        local function result()
            if #c.errors == 0 then return nil end
            return { ok = false, errors = c.errors, warnings = c.warnings, message = c.errors[1].message }
        end
        for key in pairs(doc) do
            if key ~= "kind" and key ~= "version" and key ~= "sections" then
                c.err(show(key), "unsupported", unsupported_message(tostring(key)))
            end
        end
        if doc.kind ~= M.KIND then
            c.err("kind", "kind", type(doc.kind) == "string" and doc.kind:match("^beskar%.")
                and "This is a different kind of Beskar file; only full setup files can be imported here."
                or "This is not a Beskar setup file.")
        end
        local version = strict_int(doc.version)
        if version == nil then c.err("version", "version", "The file has no valid version number.")
        elseif version > M.VERSION then c.err("version", "version", string.format("The file is version %d, written by a newer Beskar; this one reads version %d.", version, M.VERSION))
        elseif version < 1 then c.err("version", "version", "The file has an invalid version number.") end
        local raw = doc.sections
        local out = {}
        if type(raw) ~= "table" or not is_obj(raw) then
            c.err("sections", "type", "The file has no setup sections.")
        else
            if next(raw) == nil then c.err("sections", "empty", "The file contains no setup sections.") end
            for key in pairs(raw) do
                if type(key) ~= "string" or not M.OWNER[key] then
                    c.err("sections." .. show(key), "unsupported", unsupported_message(tostring(key)))
                end
            end
            for _, section in ipairs(M.SECTIONS) do
                local r = raw[section]
                if r ~= nil then
                    local fields = fields_of(section)
                    local data
                    if section == "appearance" or section == "frame" then
                        if not fields then c.err(section, "unavailable", "This section cannot be imported on this system.")
                        else
                            if type(r) ~= "table" or not is_obj(r) then c.err("sections." .. section, "type", "This section is not valid.")
                            else
                                for k in pairs(r) do
                                    if k ~= "values" then c.err("sections." .. section .. "." .. show(k), "unsupported", unsupported_message(tostring(k))) end
                                end
                                data = check_values("sections." .. section, r.values, fields, c, true)
                            end
                        end
                    elseif section == "pins" then data = check_pins(r, c, false)
                    elseif section == "widgets" then data = check_widgets(r, c, live) end
                    if data then out[section] = data end
                end
            end
        end
        local failed = result()
        if failed then return failed end
        return { ok = true, sections = out, version = version, warnings = c.warnings }
    end

    function ctl.parse_import(text)
        local function one(code, message) return { ok = false, errors = { { path = "", code = code, message = message } }, message = message } end
        if type(text) ~= "string" then return one("empty", "There is nothing to import.") end
        if #text > M.MAX_IMPORT_BYTES then
            return one("size", string.format("The file is too large for a setup (at most %d KB).", math.floor(M.MAX_IMPORT_BYTES / 1024)))
        end
        text = text:gsub("^\239\187\191", "")
        if not text:find("%S") then return one("empty", "There is nothing to import.") end
        if not text:match("^%s*{") then return one("format", "This is not a Beskar setup file (expected a JSON object).") end
        local ok, doc = decode(text)
        if not ok or type(doc) ~= "table" or (#doc > 0) then return one("format", "This is not a valid JSON object.") end
        return parse_doc(doc, nil)
    end

    -- plans ----------------------------------------------------------
    local function field_plan(section, cur, tgt)
        local plan = { changes = {} }
        for _, f in ipairs(fields_of(section) or {}) do
            local a, b = cur.values[f.id], tgt.values[f.id]
            if a ~= b then
                plan.changes[#plan.changes + 1] = { id = f.id, label = f.label or f.id, from = a, to = b,
                    from_label = label_of(f, a), to_label = label_of(f, b) }
            end
        end
        return plan
    end

    local function pins_plan(cur, tgt)
        local function names(d) if d.default then return {} end return d.list end
        local a, b = names(cur), names(tgt)
        local ina, inb = {}, {}
        for _, p in ipairs(a) do ina[p] = true end
        for _, p in ipairs(b) do inb[p] = true end
        local added, removed = {}, {}
        for _, p in ipairs(b) do if not ina[p] then added[#added + 1] = p end end
        for _, p in ipairs(a) do if not inb[p] then removed[#removed + 1] = (p:gsub("|.*$", " (window pin)")) end end
        local function label(d) return d.default and "Automatic" or string.format("%d pinned", #d.list) end
        local change = { id = "pins.list", label = "Pinned apps", from_label = label(cur), to_label = label(tgt), added = added, removed = removed }
        return { changes = { change } }
    end

    local function widgets_plan(cur, tgt)
        local have, want = {}, {}
        for _, card in ipairs(cur.cards) do local s = card_sig(card); have[s] = (have[s] or 0) + 1 end
        for _, card in ipairs(tgt.cards) do local s = card_sig(card); want[s] = (want[s] or 0) + 1 end
        local added, removed, kept = 0, 0, 0
        for s, n in pairs(want) do
            local h = have[s] or 0
            kept = kept + math.min(n, h)
            if n > h then added = added + (n - h) end
        end
        for s, n in pairs(have) do
            local w = want[s] or 0
            if n > w then removed = removed + (n - w) end
        end
        local changes = {}
        if added > 0 or removed > 0 then
            changes[#changes + 1] = { id = "widgets.cards", label = "Widget desktop", from_label = string.format("%d widgets", #cur.cards),
                to_label = string.format("%d widgets", #tgt.cards), added = added, removed = removed, kept = kept }
        end
        if cur.snap ~= tgt.snap then
            changes[#changes + 1] = { id = "widgets.snap", label = "Snap to grid", from = cur.snap, to = tgt.snap,
                from_label = ONOFF[cur.snap], to_label = ONOFF[tgt.snap] }
        end
        return { changes = changes }
    end

    local function plan_of(section, cur, tgt)
        local plan
        if section == "appearance" or section == "frame" then plan = field_plan(section, cur, tgt)
        elseif section == "pins" then plan = pins_plan(cur, tgt)
        else plan = widgets_plan(cur, tgt) end
        plan.noop = M.fingerprint(section, cur) == M.fingerprint(section, tgt)
        return plan
    end

    -- the target for a section: unmentioned values keep their live value; pins keep local window pins
    local function merge_target(section, cur, file, warn)
        if section == "appearance" or section == "frame" then
            local values = copy(cur.values)
            for id, v in pairs(file.values) do values[id] = v end
            return { values = values }
        elseif section == "pins" then
            if file.default then
                local n = 0
                for _, p in ipairs(cur.list or {}) do if not pin_ok(p, false) then n = n + 1 end end
                if n > 0 then
                    warn("pins", "local_pins_dropped", string.format("%d pin%s made from a running window will be removed; Undo restores %s.",
                        n, n == 1 and "" or "s", n == 1 and "it" or "them"))
                end
                return { default = true }
            end
            local list = copy(file.list)
            local local_pins = {}
            if cur.list then
                for _, p in ipairs(cur.list) do
                    if not pin_ok(p, false) then local_pins[#local_pins + 1] = p end
                end
            end
            local dropped = 0
            for _, p in ipairs(local_pins) do
                if #list < M.MAX_PINS then list[#list + 1] = p else dropped = dropped + 1 end
            end
            if #local_pins - dropped > 0 then
                warn("pins", "local_pins_kept", string.format("%d pin%s made from a running window %s kept after the imported ones.",
                    #local_pins - dropped, (#local_pins - dropped) == 1 and "" or "s", (#local_pins - dropped) == 1 and "is" or "are"))
            end
            if dropped > 0 then
                warn("pins", "local_pins_dropped", string.format("%d window pin%s would not fit (at most %d) and will be removed; Undo restores %s.",
                    dropped, dropped == 1 and "" or "s", M.MAX_PINS, dropped == 1 and "it" or "them"))
            end
            return { list = list }
        end
        return { snap = file.snap, cards = copy(file.cards) }
    end

    function ctl.cancel_import()
        local had = staged ~= nil
        staged = nil
        publish()
        return had
    end

    function ctl.preview_import(text, live)
        staged = nil
        local parsed = ctl.parse_import(text)
        if parsed.ok then
            -- re-run the widget checks with the live outputs (reports missing monitors)
            local ok, doc = decode((text:gsub("^\239\187\191", "")))
            if ok then parsed = parse_doc(doc, live) end
        end
        if not parsed.ok then
            publish()
            return { ok = false, errors = parsed.errors, warnings = parsed.warnings or {}, message = parsed.message }
        end
        local c = collector()
        for _, w in ipairs(parsed.warnings or {}) do c.warn(w.section, w.code, w.message, w.path) end
        local result = { ok = true, sections = {}, order = {}, errors = {}, noop = true }
        local targets, base = {}, {}
        for _, section in ipairs(M.SECTIONS) do
            local file = parsed.sections[section]
            if file then
                local cur, why = snapshot_of(section, live)
                if not cur then
                    publish()
                    return fail("not_ready", string.format("%s cannot be reviewed yet (%s).", M.TITLES[section], why or "unavailable"),
                        { errors = {}, warnings = c.warnings })
                end
                local tgt = merge_target(section, cur, file, c.warn)
                local plan = plan_of(section, cur, tgt)
                local entry = { owner = M.OWNER[section], noop = plan.noop, changes = plan.changes, title = M.TITLES[section] }
                if section == "appearance" then
                    for _, ch in ipairs(plan.changes) do
                        if ch.id ~= "appearance.mode" and ch.id ~= "appearance.skin" then entry.palette_refresh = true end
                    end
                end
                if section == "frame" and file.values["frame.output-name"] and file.values["frame.output-name"] ~= "" then
                    local name = file.values["frame.output-name"]
                    local connected = live and live.outputs and live.outputs.connected
                    if connected and not connected[name] then
                        c.warn("frame", "missing_output", string.format(
                            "Monitor %s is not connected. The frame follows the focused monitor until it returns; the name is kept.", name), "frame.output-name")
                    end
                end
                if section == "pins" and tgt.list then
                    local apps = live and live.pins and live.pins.apps
                    if apps then
                        for _, p in ipairs(tgt.list) do
                            if pin_ok(p, false) and not apps[p] and not apps[p .. ".desktop"] then
                                c.warn("pins", "missing_app", string.format("%s is not installed: its pin is kept and the dock hides it until it is.", show(p)), "pins.list")
                            end
                        end
                    end
                end
                result.sections[section] = entry
                result.order[#result.order + 1] = section
                targets[section] = tgt
                base[section] = M.fingerprint(section, cur)
                if not plan.noop then result.noop = false end
            end
        end
        result.warnings = c.warnings
        if result.noop then
            result.message = "No changes: the file matches your current setup."
            publish()
            return result
        end
        token_seq = token_seq + 1
        result.token = token_seq
        local n = 0
        for _, section in ipairs(result.order) do
            if not result.sections[section].noop then n = n + 1 end
        end
        result.message = string.format("%d section%s to review.", n, n == 1 and "" or "s")
        staged = { token = token_seq, targets = targets, base = base, order = result.order, noop = {} }
        for _, section in ipairs(result.order) do staged.noop[section] = result.sections[section].noop end
        publish()
        return result
    end

    -- ── the journal ──
    local function step_view(step)
        local s = { section = step.section, owner = step.owner, state = step.state, before = step.before, target = step.target,
            before_fp = step.before_fp, target_fp = step.target_fp }
        if step.after_fp then s.after_fp = step.after_fp end
        if step.detail then s.detail = step.detail end
        return s
    end

    local function journal_doc(j)
        local doc = { kind = M.JOURNAL_KIND, version = M.JOURNAL_VERSION, id = j.id, op = j.op, state = j.state, created = j.created,
            updated = now(), steps = {} }
        for i, st in ipairs(j.steps) do doc.steps[i] = step_view(st) end
        if j.failure then doc.failure = j.failure end
        return doc
    end

    local function journal_text(j)
        local text = text_of(journal_doc(j))
        if not text then return nil, "encode" end
        if #text > M.MAX_JOURNAL_BYTES then return nil, "size" end
        return text
    end

    local function new_journal(op, steps)
        journal_counter = journal_counter + 1
        return { id = string.format("%d-%d", now(), journal_counter), op = op, state = "prepared", created = now(), steps = steps }
    end

    local function make_step(section, before, target)
        return { section = section, owner = M.OWNER[section], state = "pending", before = before, target = target,
            before_fp = M.fingerprint(section, before), target_fp = M.fingerprint(section, target) }
    end

    local function start_run(journal, phase)
        run = { journal = journal, phase = phase or "forward", need_persist = true, persist_seq = 0, attempts = 0 }
        if phase == "rollback" then journal.state = "rolling_back" end
        publish()
    end

    local function short(s) return type(s) == "string" and s:sub(1, 120) or nil end

    -- begin ------------------------------------------------------------
    function ctl.begin(token, live, opts)
        if run and not (TERMINAL[run.journal.state] and run.finished) then
            return fail("busy", "A setup is already being applied.")
        end
        if not staged or staged.token ~= token then return fail("no_preview", "Review the file again before applying it.") end
        local s = staged
        local chosen = {}
        if opts and opts.sections then
            for _, name in ipairs(opts.sections) do
                if not s.targets[name] then staged = nil; publish(); return fail("section", "Section " .. show(name) .. " was not in the review.") end
                chosen[name] = true
            end
        else
            for _, name in ipairs(s.order) do chosen[name] = true end
        end
        local steps, stale, missing = {}, {}, {}
        for _, section in ipairs(M.SECTIONS) do
            if chosen[section] and not s.noop[section] then
                local cur, why = snapshot_of(section, live)
                if not cur then
                    missing[#missing + 1] = section .. " (" .. tostring(why) .. ")"
                elseif M.fingerprint(section, cur) ~= s.base[section] then
                    stale[#stale + 1] = M.TITLES[section]
                else
                    steps[#steps + 1] = make_step(section, cur, s.targets[section])
                end
            end
        end
        if #missing > 0 then
            return fail("not_ready", "Cannot read the current " .. table.concat(missing, ", ") .. ". Nothing was changed.")
        end
        if #stale > 0 then
            staged = nil
            publish()
            return fail("stale", table.concat(stale, ", ") .. " changed since the review. Review the file again.")
        end
        if #steps == 0 then staged = nil; publish(); return fail("noop", "No changes to apply.") end
        local j = new_journal("apply", steps)
        local text, why = journal_text(j)
        if not text then return fail(why == "size" and "too_large" or "encode", "The recovery journal for this setup would be too large. Nothing was changed.") end
        staged = nil
        start_run(j, "forward")
        local names = {}
        for i, st in ipairs(steps) do names[i] = st.section end
        return { ok = true, journal_id = j.id, sections = names }
    end

    -- undo ---------------------------------------------------------------
    function ctl.undo(live, opts)
        if run and not (TERMINAL[run.journal.state] and run.finished) then return fail("busy", "A setup is already being applied.") end
        if not last_done then return fail("none", "There is no setup to undo.") end
        local src = last_done
        local steps, stale = {}, {}
        for i = #src.steps, 1, -1 do
            local st = src.steps[i]
            if st.state == "applied" then
                local cur = snapshot_of(st.section, live)
                if not cur then return fail("not_ready", "Cannot read the current " .. M.TITLES[st.section] .. ". Nothing was changed.") end
                if M.fingerprint(st.section, cur) ~= (st.after_fp or st.target_fp) then
                    stale[#stale + 1] = M.TITLES[st.section]
                else
                    steps[#steps + 1] = make_step(st.section, cur, st.before)
                end
            end
        end
        if #stale > 0 and not (opts and opts.skip_stale) then
            return fail("stale", table.concat(stale, ", ") .. " changed after the setup was applied. Undo would overwrite those changes.", { stale = stale })
        end
        if #steps == 0 then return fail("noop", "Nothing is left to undo.") end
        local j = new_journal("undo", steps)
        if not journal_text(j) then return fail("too_large", "The recovery journal would be too large. Nothing was changed.") end
        start_run(j, "forward")
        run.undo_source = src
        run.stale_skipped = stale
        return { ok = true, journal_id = j.id, sections = (function() local n = {} for i, st in ipairs(steps) do n[i] = st.section end return n end)(), skipped = stale }
    end

    -- the pump -------------------------------------------------------------
    local function candidates(j)
        local list = {}
        for i = #j.steps, 1, -1 do
            local st = j.steps[i]
            if st.state == "applied" or st.state == "failed" or st.state == "sent" then list[#list + 1] = i end
        end
        return list
    end

    local function request_id(j, i, attempt) return string.format("%s:%d:%d", j.id, i, attempt) end

    local function palette_changed(step)
        if step.section ~= "appearance" then return false end
        for _, id in ipairs({ "appearance.wallpaper-colours", "appearance.accent", "appearance.palette" }) do
            if step.before.values[id] ~= step.target.values[id] then return true end
        end
        return false
    end

    local function begin_step_action(i, op)
        local j = run.journal
        local st = j.steps[i]
        run.attempts = run.attempts + 1
        local act = { kind = "apply", request = request_id(j, i, run.attempts), op = op, section = st.section, owner = st.owner,
            journal_id = j.id, step = i, force = op == "rollback" }
        if op == "rollback" then
            act.data = copy(st.before)
            st.state = "rolling_back"
        else
            act.data = copy(st.target)
            act.expect = st.before_fp
            st.state = "sent"
            if op == "apply" then act.palette_refresh = palette_changed(st) or nil end
        end
        act.text = text_of(act.data)
        run.release = act
    end

    local function finalize()
        local j = run.journal
        local applied, rolled, attention = {}, {}, {}
        for _, st in ipairs(j.steps) do
            if st.state == "applied" then applied[#applied + 1] = st.section end
            if st.state == "rolled_back" then rolled[#rolled + 1] = st.section end
            if st.state == "rollback_failed" then
                attention[#attention + 1] = { section = st.section, owner = st.owner, message = M.TITLES[st.section] .. " could not be restored: " .. (st.detail or "no answer from its owner") .. "." }
            end
        end
        local res
        if run.phase == "rollback" then
            if #attention > 0 then
                j.state = "rollback_failed"
                res = { kind = "finish", ok = false, code = "rollback_failed", applied = applied, rolled_back = rolled, needs_attention = attention,
                    message = "The setup could not be applied and not everything could be put back. " .. attention[1].message }
            elseif j.op == "recover" then
                j.state = "rolled_back"
                res = { kind = "finish", ok = true, code = "recovered", applied = applied, rolled_back = rolled, needs_attention = {},
                    message = "The interrupted setup was rolled back." }
            else
                j.state = "rolled_back"
                res = { kind = "finish", ok = false, code = run.failure and run.failure.code or "failed", applied = applied, rolled_back = rolled,
                    needs_attention = {}, rolled_back_all = true,
                    message = (run.failure and run.failure.message or "The setup failed.") .. " Everything that had changed was put back." }
            end
        else
            j.state = "done"
            if j.op == "undo" then
                res = { kind = "finish", ok = true, code = "undone", applied = applied, rolled_back = {}, needs_attention = {},
                    message = "The setup was undone." }
                if run.stale_skipped and #run.stale_skipped > 0 then
                    res.message = res.message .. " Left as they are because they changed since: " .. table.concat(run.stale_skipped, ", ") .. "."
                end
            else
                res = { kind = "finish", ok = true, code = "applied", applied = applied, rolled_back = {}, needs_attention = {},
                    message = "The setup was applied." }
            end
        end
        run.final = res
        run.need_persist = true
        run.finishing = true
    end

    local function next_work()
        local j = run.journal
        if run.phase == "forward" then
            for i, st in ipairs(j.steps) do
                if st.state == "pending" then
                    j.state = "running"
                    begin_step_action(i, j.op == "undo" and "undo" or "apply")
                    run.need_persist = true
                    return true
                end
            end
            finalize()
            return true
        end
        for _, i in ipairs(candidates(j)) do
            begin_step_action(i, "rollback")
            run.need_persist = true
            return true
        end
        finalize()
        return true
    end

    function ctl.next(live)
        if not run then return { kind = "idle" } end
        if run.blocked then return { kind = "wait", reason = "blocked", blocked = copy(run.blocked) } end
        if run.awaiting then return { kind = "wait", reason = "persist" } end
        if run.need_persist then
            local text, why = journal_text(run.journal)
            if not text then
                run.blocked = { code = why, message = "The recovery journal could not be written." }
                publish()
                return { kind = "wait", reason = "blocked", blocked = copy(run.blocked) }
            end
            run.persist_seq = run.persist_seq + 1
            run.awaiting = run.persist_seq
            run.need_persist = false
            return { kind = "persist", seq = run.persist_seq, text = text, journal_id = run.journal.id }
        end
        if run.release then
            local act = run.release
            run.release = nil
            run.inflight = act
            publish()
            return act
        end
        if run.inflight then
            return { kind = "wait", reason = "owner", request = run.inflight.request, section = run.inflight.section, owner = run.inflight.owner }
        end
        if run.finishing then
            local res = run.final
            if run.journal.state == "rollback_failed" then
                -- the run stays: retry_rollback / abandon continue it
                run.terminal_kept = true
            else
                run.finished = true
                if run.journal.op == "apply" and run.journal.state == "done" then last_done = copy(run.journal) end
                if run.journal.op == "undo" and run.journal.state == "done" then last_done = nil end
                res.undo_available = last_done ~= nil
            end
            res.undo_available = last_done ~= nil
            last_message = res.message
            run.finishing = nil
            run.reported = res
            publish()
            return res
        end
        if run.finished or run.terminal_kept then return { kind = "idle" } end
        -- coordinator-side compare-and-swap for the step about to be sent (the owner repeats it)
        if run.phase == "forward" and live then
            local j = run.journal
            for _, st in ipairs(j.steps) do
                if st.state == "pending" then
                    local cur = snapshot_of(st.section, live)
                    if cur and M.fingerprint(st.section, cur) ~= st.before_fp then
                        st.state = "failed_clean"
                        st.detail = "changed while the setup was running"
                        run.failure = { section = st.section, code = "stale", message = M.TITLES[st.section] .. " changed while the setup was being applied." }
                        run.phase = "rollback"
                        j.state = "rolling_back"
                        run.need_persist = true
                        return ctl.next(live)
                    end
                    break
                end
            end
        end
        next_work()
        return ctl.next(live)
    end

    function ctl.persisted(seq, ok, why)
        if not run or run.awaiting ~= seq then return false end
        run.awaiting = nil
        if ok then return true end
        local j = run.journal
        local touched = false
        for _, st in ipairs(j.steps) do if st.state ~= "pending" then touched = true end end
        if not touched and not run.release then
            -- nothing has been sent: abandon the run, nothing changed
            run = nil
            last_message = "The setup was not applied: the recovery journal could not be written."
            publish()
            return true
        end
        run.need_persist = true
        run.blocked = { code = "journal_write", message = "The recovery journal could not be written" .. (why and (": " .. tostring(why)) or "") .. ". No further step will run until it can." }
        publish()
        return true
    end

    function ctl.retry()
        if not run or not run.blocked then return false end
        run.blocked = nil
        run.need_persist = true
        publish()
        return true
    end

    local function on_result(request, info)
        if not run or not run.inflight or run.inflight.request ~= request then
            return fail("unknown_request", "That answer does not match a request in progress.")
        end
        local act = run.inflight
        run.inflight = nil
        local j = run.journal
        local st = j.steps[act.step]
        info = type(info) == "table" and info or {}
        if act.op == "rollback" then
            if info.ok == true then st.state = "rolled_back"; st.detail = nil
            else st.state = "rollback_failed"; st.detail = short(info.message) or short(info.code) end
        else
            if info.ok == true then
                st.state = "applied"
                local fp = type(info.fp) == "string" and #info.fp <= 40 and info.fp:match("^%x+:%d+$") and info.fp or nil
                st.after_fp = fp or st.target_fp
                st.detail = nil
            else
                st.state = info.untouched == true and "failed_clean" or "failed"
                st.detail = short(info.message) or short(info.code)
                run.failure = { section = st.section, code = tostring(info.code or "failed"):sub(1, 32),
                    message = M.TITLES[st.section] .. (info.code == "stale" and " changed while the setup was being applied."
                        or " could not be applied" .. (st.detail and (": " .. st.detail) or "") .. ".") }
                run.phase = "rollback"
                j.state = "rolling_back"
            end
        end
        run.need_persist = true
        publish()
        return { ok = true }
    end

    function ctl.ack(request, info) return on_result(request, info) end

    function ctl.timeout(request)
        local r = on_result(request, { ok = false, untouched = false, code = "timeout", message = "no answer from its owner" })
        return r
    end

    -- rollback failure follow-ups --------------------------------------------
    function ctl.retry_rollback()
        if not run or run.journal.state ~= "rollback_failed" then return fail("none", "There is nothing to retry.") end
        for _, st in ipairs(run.journal.steps) do
            if st.state == "rollback_failed" then st.state = "failed"; st.detail = nil end
        end
        run.terminal_kept, run.finished, run.finishing, run.final = nil, nil, nil, nil
        run.phase = "rollback"
        run.journal.state = "rolling_back"
        run.need_persist = true
        publish()
        return { ok = true }
    end

    function ctl.abandon()
        if not run or run.journal.state ~= "rollback_failed" then return fail("none", "There is nothing to accept.") end
        run.journal.state = "abandoned"
        run.final = { kind = "finish", ok = true, code = "abandoned", applied = {}, rolled_back = {}, needs_attention = {},
            message = "The current state was accepted as it is.", undo_available = last_done ~= nil }
        run.terminal_kept = nil
        run.finishing = true
        run.need_persist = true
        publish()
        return { ok = true }
    end

    -- ── restart reconciliation ──
    local function parse_journal(text)
        if type(text) ~= "string" or #text > M.MAX_JOURNAL_BYTES then return nil, "The recovery journal is missing or too large." end
        text = text:gsub("^\239\187\191", "")
        if not text:match("^%s*{") then return nil, "The recovery journal is not a JSON object." end
        local ok, doc = decode(text)
        if not ok or type(doc) ~= "table" or #doc > 0 then return nil, "The recovery journal could not be read." end
        if doc.kind ~= M.JOURNAL_KIND then return nil, "This is not a Beskar recovery journal." end
        local version = strict_int(doc.version)
        if not version or version > M.JOURNAL_VERSION then return nil, "The recovery journal was written by a newer Beskar." end
        if type(doc.id) ~= "string" or not doc.id:match("^[%w%-_]+$") or #doc.id > 48 then return nil, "The recovery journal has no valid id." end
        if not OPS[doc.op] or not JOURNAL_STATES[doc.state] then return nil, "The recovery journal has an unknown state." end
        if type(doc.steps) ~= "table" or not is_list(doc.steps) or #doc.steps < 1 or #doc.steps > #M.SECTIONS then
            return nil, "The recovery journal has no valid steps."
        end
        local j = { id = doc.id, op = doc.op, state = doc.state, created = strict_int(doc.created) or 0, steps = {} }
        local seen = {}
        for i, r in ipairs(doc.steps) do
            if type(r) ~= "table" or not M.OWNER[r.section] or seen[r.section] or not STEP_STATES[r.state] then
                return nil, "The recovery journal has an invalid step " .. i .. "."
            end
            seen[r.section] = true
            local before = M.validate_section(r.section, r.before, { preferences = P, local_pins = true })
            local target = M.validate_section(r.section, r.target, { preferences = P, local_pins = true })
            if not before or not target then return nil, "The recovery journal has unreadable data for " .. M.TITLES[r.section] .. "." end
            local st = { section = r.section, owner = M.OWNER[r.section], state = r.state, before = before, target = target,
                before_fp = M.fingerprint(r.section, before), target_fp = M.fingerprint(r.section, target) }
            if type(r.after_fp) == "string" and #r.after_fp <= 40 and r.after_fp:match("^%x+:%d+$") then st.after_fp = r.after_fp end
            st.detail = short(r.detail)
            j.steps[#j.steps + 1] = st
        end
        return j
    end

    function ctl.reconcile(text, live)
        recovery = nil
        local j, why = parse_journal(text)
        if not j then return { ok = false, status = "unreadable", message = why } end
        if TERMINAL[j.state] then
            if j.state == "done" and j.op == "apply" then
                last_done = copy(j)
                publish()
                return { ok = true, status = "complete", undo_available = true, journal_id = j.id, message = "The last setup finished; it can still be undone." }
            end
            return { ok = true, status = "complete", journal_id = j.id, undo_available = last_done ~= nil }
        end
        local rows, waiting, touched = {}, {}, false
        for i, st in ipairs(j.steps) do
            local actual
            if st.state == "pending" then
                actual = "untouched"
            else
                local cur = snapshot_of(st.section, live)
                if not cur then waiting[#waiting + 1] = st.section
                else
                    local fp = M.fingerprint(st.section, cur)
                    if fp == st.before_fp then actual = "untouched"
                    elseif fp == st.target_fp or (st.after_fp and fp == st.after_fp) then actual = "applied"
                    else actual = "diverged" end
                end
            end
            if actual and actual ~= "untouched" then touched = true end
            rows[i] = { section = st.section, owner = st.owner, journal_state = st.state, actual = actual }
        end
        if #waiting > 0 then
            return { ok = true, status = "needs_live", waiting_for = waiting, steps = rows, journal_id = j.id,
                message = "Waiting for " .. table.concat(waiting, ", ") .. " to answer before the interrupted setup can be checked." }
        end
        if not touched then
            -- nothing the journal sent reached an owner: it only needs closing
            recovery = { journal = j, rows = rows, clear_only = true }
            publish()
            return { ok = true, status = "needs_recovery", steps = rows, journal_id = j.id, nothing_changed = true,
                message = "A setup was interrupted before it changed anything." }
        end
        recovery = { journal = j, rows = rows }
        publish()
        return { ok = true, status = "needs_recovery", steps = rows, journal_id = j.id,
            message = "A setup was interrupted. Some sections may have changed." }
    end

    function ctl.recover(choice, live)
        if not recovery then return fail("none", "There is nothing to recover.") end
        local r = recovery
        local j = r.journal
        if choice == "keep" or r.clear_only then
            recovery = nil
            j.state = "abandoned"
            j.op = j.op
            run = { journal = j, phase = "forward", need_persist = true, persist_seq = 0, attempts = 0, finishing = true,
                final = { kind = "finish", ok = true, code = "kept", applied = {}, rolled_back = {}, needs_attention = {},
                    message = r.clear_only and "The interrupted setup had not changed anything." or "The current state was kept." } }
            publish()
            return { ok = true }
        end
        if choice ~= "rollback" then return fail("choice", "Choose rollback or keep.") end
        -- roll back what reached an owner: applied and diverged sections (forced)
        local steps = {}
        for i, st in ipairs(j.steps) do
            local actual = r.rows[i].actual
            if actual == "applied" or actual == "diverged" then
                st.state = "failed"           -- a rollback candidate
            else
                st.state = "failed_clean"
            end
            steps[#steps + 1] = st
        end
        local rj = new_journal("recover", steps)
        rj.id = j.id                         -- the journal on disk keeps its identity: it is replaced, not duplicated
        recovery = nil
        start_run(rj, "rollback")
        run.failure = { code = "recovered", message = "The interrupted setup was rolled back." }
        return { ok = true, journal_id = rj.id }
    end

    return ctl
end

return M
