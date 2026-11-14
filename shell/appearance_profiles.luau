-- Saved looks (C2b) and single-section Appearance import / export (C5, first increment).
-- Controller only: no scene state, no surface, no service, no timer, no polling. The HOST (Settings) supplies
-- the file adapter and applies the real preferences. Tests: lua tests/appearance-profiles.lua
--
--   local AP = require("appearance_profiles")
--   local ctl = AP.new(P, adapter)       P = require("preferences")
--     adapter.run(script, args, cb)      required for open/save: cb(stdout, exit_code), like settings_store
--     adapter.decode(text)               required for open/import: JSON text -> table (throws when malformed)
--     adapter.encode(table)              optional host JSON encoder -> text (a built-in sorted encoder is used otherwise)
--     adapter.notify(status)             optional: called whenever ctl.status() changes (publish it to a fact)
--
--   Appearance values are keyed by Settings' FACT names inside Lua (what P.appearance_snapshot returns) and by the
--   STABLE CONTROL IDS of P.APPEARANCE on disk and in export files (appearance.mode, appearance.skin,
--   appearance.wallpaper-colours, appearance.accent, appearance.palette).
--
--   Saved looks (file $HOME/.config/beskar/appearance-looks.json, version 1, at most 16):
--     ctl.open(cb)                       read the store ONCE (nothing is written at load); cb(status)
--     ctl.list()                         -> { {id, name, summary, values, has_palette, pending}, ... }
--     ctl.get(id)                        -> one list entry | nil
--     ctl.save(name, facts, pal, opts)   -> result       new look from Settings' facts; opts.palette = true keeps the
--                                                        cached colours (`pal`, a usable palette value) with the look
--     ctl.update(id, facts, pal, opts)   -> result       replace a look's values (palette kept only if opts.palette)
--     ctl.rename(id, name)               -> result
--     ctl.delete(id)                     -> result
--     ctl.apply_look(id, current)        -> result { snapshot, plan, undo_snapshot, noop }  `current` = the live snapshot
--                                                        (P.appearance_snapshot(facts, pal)); the host takes ONE undo
--                                                        entry from undo_snapshot, then applies plan.values and
--                                                        plan.restore_palette through Settings' normal apply
--     ctl.matching(current)              -> id | nil     the look whose values equal the live ones (palette ignored)
--     ctl.retry() / ctl.discard_unsaved() / ctl.discard_held() / ctl.recover(stamp, cb)
--   result = { ok = true, id?, ... } | { ok = false, code, message }  (message is user-facing)
--
--   Portable export / import (data only: version, kind, appearance choices; never palette cache, commands, paths,
--   credentials, content, displays, timers or app integration):
--     { "kind": "beskar.appearance", "version": 1, "values": { "appearance.mode": 1, "appearance.skin": 0, ... } }
--     ctl.export(current)                -> text, doc    ctl.export_look(id) -> text, doc | nil, result
--     ctl.parse_import(text)             -> { ok, values, errors = {{path, code, message}} }     pure, strict, bounded
--     ctl.preview_import(text, current)  -> { ok, noop, plan, target, token, summary, errors, message }
--                                           nothing is applied; a valid preview with changes is STAGED
--     ctl.apply_import(token, current)   -> { ok, plan, undo_snapshot, ... }  refused when stale/unknown; the host applies
--     ctl.cancel_import()
--   Cross-owner combined profiles are NOT part of this module.
--
--   Writes are serial and coalesced: changes are visible at once (`pending` = not yet in the file); the file text
--   is the whole store; the committed copy moves only when the host reports exit code 0. A failed write waits for
--   ctl.retry(). Corrupt / unreadable / newer / oversize stores are never overwritten (recover() moves a corrupt
--   file aside). Entries that cannot be understood are held verbatim and written back unchanged.

local M = {}

M.VERSION = 1
M.MAX_LOOKS = 16
M.MAX_NAME_CHARS = 32
M.MAX_NAME_BYTES = 96
M.MAX_STORE_BYTES = 262144
M.MAX_IMPORT_BYTES = 8192
M.FILE = "beskar/appearance-looks.json"
M.EXPORT_KIND = "beskar.appearance"
M.EXPORT_FILENAME = "beskar-appearance.json"

local MAX_ERRORS = 12
local MAX_DEPTH = 8

-- ── generic helpers ──────────────────────────────────────────────

local function copy(v, depth)
    if type(v) ~= "table" then return v end
    depth = depth or 0
    if depth > MAX_DEPTH then return nil end
    local out = {}
    for k, x in pairs(v) do out[k] = copy(x, depth + 1) end
    return out
end

local function deep_equal(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for k, v in pairs(a) do
        if not deep_equal(v, b[k]) then return false end
    end
    for k in pairs(b) do
        if a[k] == nil then return false end
    end
    return true
end

local function is_array(t)
    return type(t) == "table" and #t > 0
end

local function is_hex(s)
    return type(s) == "string" and s:match("^#%x%x%x%x%x%x$") ~= nil
end

-- a short, printable rendering of an untrusted key / value for a message
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

local function strict_int(v)
    if type(v) ~= "number" or v ~= v or v == math.huge or v == -math.huge then return nil end
    if v ~= math.floor(v) or math.abs(v) > 2 ^ 31 then return nil end
    return math.floor(v)
end

local function fail(code, message, extra)
    local r = extra or {}
    r.ok, r.code, r.message = false, code, message
    return r
end

-- ── names ────────────────────────────────────────────────────────

-- trimmed name | nil, code, message.  1..32 Unicode characters, at most 96 bytes, valid UTF-8, no control or
-- direction-changing characters (they could disguise a name in a list).
function M.validate_name(name)
    if type(name) ~= "string" then return nil, "name", "Give the look a name." end
    local s = name:gsub("^%s+", ""):gsub("%s+$", "")
    if s == "" then return nil, "name", "Give the look a name." end
    local n = utf8.len(s)
    if not n then return nil, "name", "The name is not valid text." end
    if n > M.MAX_NAME_CHARS then
        return nil, "name", string.format("Use at most %d characters for the name.", M.MAX_NAME_CHARS)
    end
    if #s > M.MAX_NAME_BYTES then
        return nil, "name", string.format("The name is too long (at most %d bytes).", M.MAX_NAME_BYTES)
    end
    for _, c in utf8.codes(s) do
        if c < 32 or c == 127 or (c >= 0x80 and c <= 0x9f) or c == 0x200e or c == 0x200f
            or (c >= 0x2028 and c <= 0x202e) or (c >= 0x2066 and c <= 0x2069) or c == 0xfeff then
            return nil, "name", "The name cannot contain control or direction characters."
        end
    end
    return s
end

local function name_key(name) return name:lower() end

-- ── JSON text (built-in sorted encoder; arrays only when non-empty) ──

local ESC = { ['"'] = '\\"', ["\\"] = "\\\\", ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t" }

local function enc_str(s)
    return '"' .. s:gsub('[%c"\\]', function(c) return ESC[c] or string.format("\\u%04x", c:byte()) end) .. '"'
end

local function enc_num(n)
    if n == math.floor(n) and math.abs(n) < 2 ^ 53 then return string.format("%d", n) end
    return string.format("%.17g", n)
end

local function enc(v, depth)
    local t = type(v)
    if t == "boolean" then return tostring(v) end
    if t == "string" then return enc_str(v) end
    if t == "number" then
        if v ~= v or v == math.huge or v == -math.huge then return nil end
        return enc_num(v)
    end
    if t ~= "table" or depth > MAX_DEPTH + 2 then return nil end
    local n, count = #v, 0
    for _ in pairs(v) do count = count + 1 end
    local parts = {}
    if n > 0 and count == n then
        for i = 1, n do
            local e = enc(v[i], depth + 1)
            if e == nil then return nil end
            parts[#parts + 1] = e
        end
        return "[" .. table.concat(parts, ", ") .. "]"
    end
    local keys = {}
    for k in pairs(v) do
        if type(k) == "string" then keys[#keys + 1] = k end
    end
    table.sort(keys)
    for _, k in ipairs(keys) do
        local e = enc(v[k], depth + 1)
        if e ~= nil then parts[#parts + 1] = enc_str(k) .. ": " .. e end
    end
    return "{" .. table.concat(parts, ", ") .. "}"
end

-- shell scripts (host adapter.run passes args as $1, $2: nothing is interpolated into the script)
local READ_SCRIPT = [=[
p="$HOME/.config/$1"
if [ ! -e "$p" ] && [ ! -L "$p" ]; then exit 3; fi
[ -f "$p" ] && [ -r "$p" ] || exit 4
n=$(wc -c < "$p") || exit 4
[ "$n" -le 1048576 ] || exit 4
cat "$p"
]=]

local WRITE_SCRIPT = [=[
set -eu
umask 077
p="$HOME/.config/$1"
mkdir -p "$(dirname "$p")"
t=$(mktemp "$p.tmp.XXXXXX")
trap 'rm -f "$t"' EXIT HUP INT TERM
printf '%s\n' "$2" > "$t"
if [ -e "$p" ]; then cp -p -- "$p" "$p.bak"; fi
mv -f -- "$t" "$p"
]=]

local MOVE_ASIDE_SCRIPT = [=[
set -eu
p="$HOME/.config/$1"
q="$p.corrupt-$2"
[ -f "$p" ] || exit 3
[ ! -e "$q" ] && [ ! -L "$q" ] || exit 5
mv -- "$p" "$q"
]=]

M.READ_SCRIPT, M.WRITE_SCRIPT, M.MOVE_ASIDE_SCRIPT = READ_SCRIPT, WRITE_SCRIPT, MOVE_ASIDE_SCRIPT

-- ── the controller ───────────────────────────────────────────────

function M.new(P, adapter)
    assert(type(P) == "table" and type(P.APPEARANCE) == "table" and P.appearance_plan, "appearance_profiles: preferences module required")
    adapter = adapter or {}
    local notify = adapter.notify or function() end
    local ctl = {}

    local members = P.APPEARANCE
    local by_id, by_fact = {}, {}
    for _, a in ipairs(members) do by_id[a.id], by_fact[a.fact] = a, a end

    local function text_of(doc)
        if type(adapter.encode) == "function" then
            local ok, out = pcall(adapter.encode, doc)
            if ok and type(out) == "string" then return out end
            return nil
        end
        return enc(doc, 0)
    end

    -- ── strict values ──
    -- one control value, exact type and range (no coercion: an import is not a legacy file); v | nil, message
    local function strict_value(a, raw)
        local f = a.field
        if f.type == "bool" then
            if type(raw) ~= "boolean" then return nil, "must be true or false (got " .. show(raw) .. ")" end
            return raw
        end
        local n = strict_int(raw)
        if n == nil then return nil, "must be a whole number (got " .. show(raw) .. ")" end
        if f.type == "enum" then
            if n < f.min or n > f.max then
                return nil, string.format("must be from %d to %d (got %s)", f.min, f.max, show(raw))
            end
            return n
        end
        for _, c in ipairs(f.choices or {}) do
            if c == n then return n end
        end
        return nil, "is not one of the allowed choices (got " .. show(raw) .. ")"
    end

    local function label_of(a, v)
        if a.field.format == "hex" then return v == -1 and "Preset colour" or string.format("#%06x", v) end
        return (a.labels and a.labels[v]) or tostring(v)
    end

    local function summary_of(values)
        local parts = { label_of(by_fact.appearance, values.appearance), label_of(by_fact.skin, values.skin) }
        if values.accent_auto then
            parts[#parts + 1] = "Wallpaper colours (" .. label_of(by_fact.pal_style, values.pal_style) .. ")"
        else
            local custom = by_fact.custom_accent and values.custom_accent ~= -1
            parts[#parts + 1] = custom and label_of(by_fact.custom_accent, values.custom_accent) or label_of(by_fact.accent, values.accent)
        end
        return table.concat(parts, " · ")
    end

    -- a strict palette cache | nil, message
    local PALETTE_KEYS = { style = true, src = true, dark = true, light = true }
    local function strict_palette(raw)
        if type(raw) ~= "table" or is_array(raw) then return nil, "not an object" end
        for k in pairs(raw) do
            if not PALETTE_KEYS[k] then return nil, "unknown key " .. show(k) end
        end
        local out = {}
        local style, why = strict_value(by_fact.pal_style, raw.style)
        if style == nil then return nil, "style " .. (why or "missing") end
        out.style = style
        if raw.src ~= nil then
            if not is_hex(raw.src) then return nil, "src is not #rrggbb" end
            out.src = raw.src:lower()
        end
        for _, mode in ipairs({ "dark", "light" }) do
            local set = raw[mode]
            if type(set) ~= "table" or is_array(set) then return nil, mode .. " colours missing" end
            for k in pairs(set) do
                if k ~= "a" and k ~= "b" and k ~= "s" then return nil, mode .. " has unknown key " .. show(k) end
            end
            if not (is_hex(set.a) and is_hex(set.b) and is_hex(set.s)) then return nil, mode .. " colours are not #rrggbb" end
            out[mode] = { a = set.a:lower(), b = set.b:lower(), s = set.s:lower() }
        end
        return out
    end

    -- the live state as a snapshot; accepts a snapshot { values, palette } or a plain facts table
    local function to_snapshot(current)
        if type(current) == "table" and type(current.values) == "table" then
            return P.appearance_snapshot(current.values, current.palette)
        end
        return P.appearance_snapshot(current, nil)
    end

    local function values_to_ids(values)
        local out = {}
        for _, a in ipairs(members) do out[a.id] = values[a.fact] end
        return out
    end

    -- ── store documents ──
    local function empty_doc() return { looks = {}, held = {}, seq = 0, extra = {} } end

    local function copy_doc(doc)
        return { looks = copy(doc.looks), held = copy(doc.held), seq = doc.seq, extra = copy(doc.extra) }
    end

    local function entry_to_json(e)
        local j = { id = e.id, name = e.name, values = values_to_ids(e.values) }
        if e.palette then j.palette = copy(e.palette) end
        return j
    end

    local function encode_doc(doc)
        local top = {}
        for k, v in pairs(doc.extra) do top[k] = v end
        top.version, top.seq = M.VERSION, doc.seq
        local arr = {}
        for _, e in ipairs(doc.looks) do arr[#arr + 1] = entry_to_json(e) end
        for _, raw in ipairs(doc.held) do arr[#arr + 1] = raw end
        if #arr > 0 then top.looks = arr else top.looks = nil end
        local text = text_of(top)
        if not text then return nil, "encode" end
        if #text > M.MAX_STORE_BYTES then return nil, "size" end
        return text
    end

    local ENTRY_KEYS = { id = true, name = true, values = true, palette = true }

    -- one stored entry -> entry, warning | nil, problem
    local function parse_entry(raw, seen)
        if type(raw) ~= "table" or is_array(raw) then return nil, "not an object" end
        for k in pairs(raw) do
            if not ENTRY_KEYS[k] then return nil, "unknown key " .. show(k) end
        end
        local id = raw.id
        if type(id) ~= "string" or #id > 12 or not id:match("^l%d+$") then return nil, "bad id" end
        if seen[id] then return nil, "duplicate id " .. id end
        local name, _, why = M.validate_name(raw.name)
        if not name then return nil, why end
        if type(raw.values) ~= "table" or is_array(raw.values) then return nil, "values missing" end
        local values = {}
        for key in pairs(raw.values) do
            if not by_id[key] then return nil, "unknown value " .. show(key) end
        end
        for _, a in ipairs(members) do
            local value = raw.values[a.id]
            if value == nil then
                if not a.optional then return nil, "missing " .. a.id end
                value = a.field.default -- original five-choice looks predate additive style controls
            end
            local v, msg = strict_value(a, value)
            if v == nil then return nil, a.id .. " " .. msg end
            values[a.fact] = v
        end
        local entry = { id = id, name = name, values = values }
        local warning
        if raw.palette ~= nil then
            local pal = strict_palette(raw.palette)
            if pal then entry.palette = pal else warning = "palette cache dropped" end
        end
        return entry, warning
    end

    -- text -> { status, detail, doc, writable, issues }
    local function parse_store(text)
        local res = { issues = {} }
        local function bad(status, detail)
            res.status, res.detail, res.doc, res.writable = status, detail, empty_doc(), false
            return res
        end
        if #text > M.MAX_STORE_BYTES then return bad("corrupt", "file is too large") end
        text = text:gsub("^\239\187\191", "")
        if not text:find("%S") then return bad("corrupt", "file is empty") end
        if not text:match("^%s*{") then return bad("corrupt", "not a JSON object") end
        if type(adapter.decode) ~= "function" then error("appearance_profiles: adapter.decode required", 2) end
        local ok, doc = pcall(adapter.decode, text)
        if not ok then return bad("corrupt", tostring(doc)) end
        if type(doc) ~= "table" or is_array(doc) then return bad("corrupt", "not a JSON object") end
        local version = strict_int(doc.version)
        if version == nil then return bad("corrupt", "version missing") end
        if version > M.VERSION then return bad("newer", "written by a newer version (" .. version .. ")") end
        if version < 1 then return bad("corrupt", "bad version") end

        local out = empty_doc()
        for k, v in pairs(doc) do
            if k ~= "version" and k ~= "seq" and k ~= "looks" and type(k) == "string" then out.extra[k] = copy(v) end
        end
        local list = doc.looks
        if list == nil then list = {} end
        if type(list) ~= "table" then return bad("corrupt", "looks is not a list") end
        local count = 0
        for _ in pairs(list) do count = count + 1 end
        if count ~= #list then return bad("corrupt", "looks is not a list") end
        if #list > M.MAX_LOOKS then return bad("toomany", "more than " .. M.MAX_LOOKS .. " looks") end

        local seen, top = {}, 0
        for i, raw in ipairs(list) do
            local entry, problem = parse_entry(raw, seen)
            if not entry then
                out.held[#out.held + 1] = copy(raw)
                res.issues[#res.issues + 1] = { index = i, problem = problem }
            else
                seen[entry.id] = true
                out.looks[#out.looks + 1] = entry
                top = math.max(top, tonumber(entry.id:sub(2)) or 0)
                if problem then res.issues[#res.issues + 1] = { index = i, id = entry.id, problem = problem } end
            end
        end
        -- a held entry may carry an id: never reuse one
        for _, raw in ipairs(out.held) do
            local n = type(raw) == "table" and type(raw.id) == "string" and tonumber(raw.id:match("^l(%d+)$"))
            if n then top = math.max(top, n) end
        end
        out.seq = math.max(strict_int(doc.seq) or 0, top)
        res.status, res.doc, res.writable = "ok", out, true
        return res
    end

    -- ── controller state ──
    local loaded, loading = false, false
    local store_status, store_detail = nil, nil
    local writable = false
    local committed, working = empty_doc(), empty_doc()
    local rev, saved_rev = 0, 0
    local busy, failed, last_error = false, false, nil
    local load_issues = {}
    local staged, token_seq = nil, 0
    local last_key = nil

    local BLOCKED = {
        corrupt = "The saved looks file is damaged. It was left untouched; move it aside to start fresh.",
        unreadable = "The saved looks file could not be read. It was left untouched.",
        newer = "Saved looks were written by a newer Beskar and are read-only here.",
        toomany = "The saved looks file holds more than 16 looks. It is read-only until you trim it by hand.",
    }

    local function status()
        local pending = rev ~= saved_rev
        local state
        if not loaded then state = loading and "loading" or "unloaded"
        elseif not writable then state = "blocked"
        elseif failed then state = "failed"
        elseif busy or pending then state = "saving"
        else state = "ready" end
        local message = ""
        if state == "failed" then message = last_error or "Could not save looks; your changes are kept here. Retry."
        elseif state == "blocked" then message = BLOCKED[store_status] or "Saved looks are read-only."
        elseif state == "loading" then message = "Loading saved looks…"
        elseif state == "saving" then message = "Saving looks…"
        elseif #working.held > 0 then
            message = string.format("%d saved look%s could not be understood and %s kept untouched.",
                #working.held, #working.held == 1 and "" or "s", #working.held == 1 and "is" or "are")
        end
        return {
            state = state, store = store_status, detail = store_detail, writable = writable,
            saving = busy, failed = failed, pending = pending,
            count = #working.looks, held = #working.held, max = M.MAX_LOOKS,
            message = message, issues = copy(load_issues), import_staged = staged ~= nil,
        }
    end

    local function publish()
        local s = status()
        local key = table.concat({ s.state, tostring(s.store), s.message, tostring(s.pending), s.count, s.held }, "|")
        if key == last_key then return end
        last_key = key
        notify(s)
    end

    ctl.status = status

    local pump
    pump = function()
        if busy or not loaded or not writable or rev == saved_rev then publish(); return end
        local text, why = encode_doc(working)
        if not text then
            failed = true
            last_error = why == "size" and "The saved looks are too large to write." or "Could not encode the saved looks."
            publish()
            return
        end
        local snapshot, snap_rev = copy_doc(working), rev
        busy, failed = true, false
        publish()
        adapter.run(WRITE_SCRIPT, { M.FILE, text }, function(_, code)
            busy = false
            if code == 0 then
                committed, saved_rev, last_error, failed = snapshot, snap_rev, nil, false
                pump()    -- later changes were coalesced behind this write
                return
            end
            -- memory stays as it was; no tight retry loop on a full or read-only disk
            failed = true
            last_error = "Could not save looks; your changes are kept here. Retry."
            publish()
        end)
    end

    function ctl.open(cb)
        if loaded or loading then
            if cb then cb(status()) end
            return
        end
        assert(type(adapter.run) == "function", "appearance_profiles: adapter.run required")
        loading = true
        publish()
        adapter.run(READ_SCRIPT, { M.FILE }, function(out, code)
            loading = false
            local res
            if code == 3 then
                res = { status = "missing", doc = empty_doc(), writable = true, issues = {} }
            elseif code ~= 0 or type(out) ~= "string" then
                res = { status = "unreadable", detail = "could not read the file", doc = empty_doc(), writable = false, issues = {} }
            else
                res = parse_store(out)
            end
            loaded = true
            store_status, store_detail, writable = res.status, res.detail, res.writable
            committed, working = res.doc, copy_doc(res.doc)
            rev, saved_rev, load_issues = 0, 0, res.issues
            publish()
            if cb then cb(status()) end
        end)
    end

    -- ── queries ──
    local function find(id)
        for i, e in ipairs(working.looks) do
            if e.id == id then return e, i end
        end
    end

    local function committed_entry(id)
        for _, e in ipairs(committed.looks) do
            if e.id == id then return e end
        end
    end

    local function describe(e)
        local c = committed_entry(e.id)
        return {
            id = e.id, name = e.name, summary = summary_of(e.values), values = copy(e.values),
            has_palette = e.palette ~= nil, palette = copy(e.palette),
            pending = c == nil or not deep_equal(c, e),
        }
    end

    function ctl.list()
        local out = {}
        for _, e in ipairs(working.looks) do out[#out + 1] = describe(e) end
        return out
    end

    function ctl.get(id)
        local e = find(id)
        return e and describe(e) or nil
    end

    function ctl.matching(current)
        local cur = to_snapshot(current)
        for _, e in ipairs(working.looks) do
            if #P.appearance_plan(cur, { values = e.values }).changes == 0 then return e.id end
        end
    end

    -- ── mutations ──
    local function writable_check()
        if not loaded then return fail("not_ready", "Saved looks are still loading.") end
        if not writable then return fail("blocked", BLOCKED[store_status] or "Saved looks are read-only.") end
    end

    local function changed()
        rev = rev + 1
        failed = false
        pump()
    end

    local function name_taken(name, except_id)
        local key = name_key(name)
        for _, e in ipairs(working.looks) do
            if e.id ~= except_id and name_key(e.name) == key then return true end
        end
        return false
    end

    -- values and the optional palette cache from Settings' facts
    local function capture(facts, pal, opts)
        local snap = P.appearance_snapshot(facts, pal)
        local palette, skipped
        if opts and opts.palette then
            if snap.palette then palette = strict_palette(snap.palette) end
            if not palette then skipped = true end
        end
        return snap.values, palette, skipped
    end

    function ctl.save(name, facts, pal, opts)
        local blocked = writable_check()
        if blocked then return blocked end
        local clean, code, msg = M.validate_name(name)
        if not clean then return fail(code, msg) end
        if #working.looks + #working.held >= M.MAX_LOOKS then
            return fail("full", string.format("You can keep up to %d saved looks. Delete one first.", M.MAX_LOOKS))
        end
        if name_taken(clean) then return fail("duplicate", "A look with that name already exists.") end
        local values, palette, skipped = capture(facts, pal, opts)
        working.seq = working.seq + 1
        local entry = { id = "l" .. working.seq, name = clean, values = values, palette = palette }
        working.looks[#working.looks + 1] = entry
        changed()
        return { ok = true, id = entry.id, look = describe(entry), palette_saved = palette ~= nil, palette_skipped = skipped or false }
    end

    function ctl.update(id, facts, pal, opts)
        local blocked = writable_check()
        if blocked then return blocked end
        local e = find(id)
        if not e then return fail("missing", "That look no longer exists.") end
        local values, palette, skipped = capture(facts, pal, opts)
        local same = deep_equal(e.values, values) and deep_equal(e.palette, palette)
        if not same then
            e.values, e.palette = values, palette
            changed()
        end
        return { ok = true, id = id, look = describe(e), changed = not same, palette_saved = palette ~= nil, palette_skipped = skipped or false }
    end

    function ctl.rename(id, name)
        local blocked = writable_check()
        if blocked then return blocked end
        local e = find(id)
        if not e then return fail("missing", "That look no longer exists.") end
        local clean, code, msg = M.validate_name(name)
        if not clean then return fail(code, msg) end
        if name_taken(clean, id) then return fail("duplicate", "A look with that name already exists.") end
        local same = clean == e.name
        if not same then
            e.name = clean
            changed()
        end
        return { ok = true, id = id, look = describe(e), changed = not same }
    end

    function ctl.delete(id)
        local blocked = writable_check()
        if blocked then return blocked end
        local _, i = find(id)
        if not i then return fail("missing", "That look no longer exists.") end
        table.remove(working.looks, i)
        changed()
        return { ok = true, id = id }
    end

    -- the user's explicit choice to drop entries this version cannot understand
    function ctl.discard_held()
        local blocked = writable_check()
        if blocked then return blocked end
        local n = #working.held
        if n == 0 then return { ok = true, discarded = 0 } end
        working.held = {}
        changed()
        return { ok = true, discarded = n }
    end

    function ctl.retry()
        if not (loaded and writable and failed and not busy) then return false end
        failed = false
        pump()
        return true
    end

    -- forget changes that could not be saved (busy writes cannot be cancelled)
    function ctl.discard_unsaved()
        if busy or not loaded then return false end
        working = copy_doc(committed)
        rev, failed, last_error = saved_rev, false, nil
        publish()
        return true
    end

    -- move a corrupt store aside; only a store the user cannot recover otherwise. cb(ok, message)
    function ctl.recover(stamp, cb)
        local function done(ok, message)
            if cb then cb(ok, message) end
            return ok, message
        end
        if not loaded or store_status ~= "corrupt" then return done(false, "Nothing to recover.") end
        if busy then return done(false, "Wait for the current save to finish.") end
        local safe = tostring(stamp or ""):gsub("[^%w%-]", "")
        if safe == "" then safe = "backup" end
        busy = true
        publish()
        adapter.run(MOVE_ASIDE_SCRIPT, { M.FILE, safe }, function(_, code)
            busy = false
            if code == 0 then
                store_status, store_detail, writable = "missing", nil, true
                committed, working = empty_doc(), empty_doc()
                rev, saved_rev, failed, last_error, load_issues = 0, 0, false, nil, {}
                publish()
                return done(true, "The damaged file was moved aside as appearance-looks.json.corrupt-" .. safe .. ".")
            end
            publish()
            return done(false, "Could not move the damaged file aside; it was left untouched.")
        end)
        return true
    end

    -- ── applying a look ──
    function ctl.apply_look(id, current)
        if not loaded then return fail("not_ready", "Saved looks are still loading.") end
        local e = find(id)
        if not e then return fail("missing", "That look no longer exists.") end
        local cur = to_snapshot(current)
        local target = { values = copy(e.values), palette = copy(e.palette) }
        local plan = P.appearance_plan(cur, target)
        return {
            ok = true, id = id, name = e.name, snapshot = target, plan = plan, noop = plan.noop,
            undo_snapshot = copy(cur),
            message = plan.noop and "Already using this look." or nil,
        }
    end

    -- ── portable export ──
    local function export_doc(values)
        return { kind = M.EXPORT_KIND, version = M.VERSION, values = values_to_ids(values) }
    end

    function ctl.export(current)
        local doc = export_doc(to_snapshot(current).values)
        local text = text_of(doc)
        if not text then return nil, fail("encode", "Could not write the export.") end
        return text, doc
    end

    function ctl.export_look(id)
        local e = find(id)
        if not e then return nil, fail("missing", "That look no longer exists.") end
        local doc = export_doc(e.values)
        local text = text_of(doc)
        if not text then return nil, fail("encode", "Could not write the export.") end
        return text, doc
    end

    -- ── strict import ──
    local DENIED = {
        "command", "exec", "script", "shell", "path", "file", "url", "token", "password", "secret", "credential",
        "content", "note", "clipboard", "notification", "display", "output", "monitor", "timer",
        "wallpaper", "apps", "plugin", "palette",
    }
    local function unsupported_message(key)
        local lower = key:lower()
        for _, word in ipairs(DENIED) do
            if lower:find(word, 1, true) then
                return string.format("'%s' is not portable: commands, paths, credentials, content, displays, timers, app integration and generated colours are never imported.", show(key))
            end
        end
        return string.format("'%s' is not a supported appearance setting.", show(key))
    end

    function ctl.parse_import(text)
        local errors = {}
        local function add(path, code, message)
            if #errors < MAX_ERRORS then errors[#errors + 1] = { path = path, code = code, message = message }
            elseif #errors == MAX_ERRORS then errors[#errors + 1] = { path = "", code = "more", message = "More problems were found." } end
        end
        local function result()
            if #errors == 0 then return nil end
            return { ok = false, errors = errors, message = errors[1].message }
        end
        if type(text) ~= "string" then add("", "empty", "There is nothing to import."); return result() end
        if #text > M.MAX_IMPORT_BYTES then
            add("", "size", string.format("The file is too large for an appearance setup (at most %d KB).", math.floor(M.MAX_IMPORT_BYTES / 1024)))
            return result()
        end
        text = text:gsub("^\239\187\191", "")
        if not text:find("%S") then add("", "empty", "There is nothing to import."); return result() end
        if not text:match("^%s*{") then add("", "format", "This is not a Beskar setup file (expected a JSON object)."); return result() end
        if type(adapter.decode) ~= "function" then error("appearance_profiles: adapter.decode required", 2) end
        local ok, doc = pcall(adapter.decode, text)
        if not ok or type(doc) ~= "table" or is_array(doc) then
            add("", "format", "This is not a valid JSON object.")
            return result()
        end

        for key in pairs(doc) do
            if key ~= "kind" and key ~= "version" and key ~= "values" then
                add(show(key), "unsupported", unsupported_message(tostring(key)))
            end
        end
        if doc.kind ~= M.EXPORT_KIND then
            add("kind", "kind", type(doc.kind) == "string" and doc.kind:match("^beskar%.")
                and "This is a different kind of Beskar setup file; only appearance files can be imported here."
                or "This is not a Beskar appearance file.")
        end
        local version = strict_int(doc.version)
        if version == nil then
            add("version", "version", "The file has no valid version number.")
        elseif version > M.VERSION then
            add("version", "version", string.format("The file is version %d, written by a newer Beskar; this one reads version %d.", version, M.VERSION))
        elseif version < 1 then
            add("version", "version", "The file has an invalid version number.")
        end

        local values = {}
        local raw = doc.values
        if type(raw) ~= "table" or is_array(raw) then
            add("values", "type", "The file has no appearance values.")
        else
            local count = 0
            for key in pairs(raw) do
                count = count + 1
                if type(key) ~= "string" or #key > 64 then
                    add("values", "unsupported", "The file has an invalid setting name.")
                elseif not by_id[key] then
                    add("values." .. show(key), "unsupported", unsupported_message(key))
                end
            end
            if count > #members + 8 then add("values", "size", "The file has too many settings.") end
            if count == 0 then add("values", "empty", "The file contains no appearance choices.") end
            for _, a in ipairs(members) do
                if raw[a.id] ~= nil then
                    local v, why = strict_value(a, raw[a.id])
                    if v == nil then add("values." .. a.id, "value", (a.label or a.id) .. " " .. why .. ".")
                    else values[a.fact] = v end
                end
            end
        end
        local failed_result = result()
        if failed_result then return failed_result end
        return { ok = true, values = values, version = version }
    end

    function ctl.cancel_import()
        local had = staged ~= nil
        staged = nil
        publish()
        return had
    end

    -- validate, plan against the live look and STAGE the result; nothing is applied or written
    function ctl.preview_import(text, current)
        staged = nil
        local parsed = ctl.parse_import(text)
        if not parsed.ok then
            publish()
            return { ok = false, errors = parsed.errors, message = parsed.message }
        end
        local cur = to_snapshot(current)
        local merged = copy(cur.values)    -- values the file does not mention stay as they are
        for fact, v in pairs(parsed.values) do merged[fact] = v end
        local target = { values = merged, palette = nil }   -- generated colours are derived afterwards, never imported
        local plan = P.appearance_plan(cur, target)
        local result = {
            ok = true, noop = plan.noop, plan = plan, target = target, errors = {},
            summary = summary_of(merged),
        }
        if plan.noop then
            result.message = "No changes: the file matches your current look."
            publish()
            return result
        end
        -- generated colours may finish after the apply
        for _, c in ipairs(plan.changes) do
            if c.fact == "accent" or c.fact == "accent_auto" or c.fact == "pal_style" then result.palette_refresh = true end
        end
        token_seq = token_seq + 1
        result.token = token_seq
        result.message = string.format("%d change%s to review.", #plan.changes, #plan.changes == 1 and "" or "s")
        staged = { token = token_seq, target = copy(target), base = copy(cur.values) }
        publish()
        return result
    end

    -- the explicit second step: re-checks that the live look is still what was reviewed
    function ctl.apply_import(token, current)
        if not staged or staged.token ~= token then
            return fail("no_preview", "Review the file again before applying it.")
        end
        local cur = to_snapshot(current)
        local s = staged
        staged = nil
        if not deep_equal(cur.values, s.base) then
            publish()
            return fail("stale", "Your appearance changed since the review. Review the file again.")
        end
        local plan = P.appearance_plan(cur, s.target)
        publish()
        if plan.noop then return fail("noop", "No changes to apply.") end
        return {
            ok = true, plan = plan, snapshot = s.target, values = plan.values,
            restore_palette = plan.restore_palette, undo_snapshot = copy(cur),
        }
    end

    return ctl
end

return M
