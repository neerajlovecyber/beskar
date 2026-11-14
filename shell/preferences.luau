-- Preference documents: schema, validation, defaults, Appearance snapshot / reset / undo. PURE: no IO, no scene state.
-- The scene reads files and passes text in; it writes the text this module returns. Tests: lua tests/preferences.lua
--
--   Documents (kind -> file, relative to $HOME/.config):  theme  -> pleamar_shell.json
--                                                        prefs  -> beskar/prefs.json
--                                                        palette-> beskar/palette.json
--   Every normalised value is a table keyed by the FILE's own key names (what start.sh greps for stays valid),
--   carries `version = 1`, and keeps unknown keys (deep-copied) so a future option is never erased.
--
--   M.VERSION                          current schema version (1). Unversioned files are "legacy" and read as version 1.
--   M.spec(kind)                       { file, fields = { {key, fact, type, default, min, max, choices, labels, ...} } }
--   M.defaults(kind)                   fresh normalised value with every default
--   M.read(kind, text, decode)         -> result: parse + normalise one document, see below
--   M.normalize(kind, doc)             -> value, issues, info{legacy, newer, unknown}   (doc = decoded table)
--   M.encode(kind, value)              -> text | nil, issues   one line, `"key": value`, sorted unknown keys, safe
--                                         inside single quotes (' is written '); validates before writing
--   M.to_facts(kind, value)            -> { factname = value }   (lock_min becomes lock_i, an index)
--   M.from_facts(kind, facts, base)    -> value, issues   rebuild a document from Settings' facts; `base` (the last
--                                         read value) supplies unknown keys, palette colours and any fact not given
--   M.palette_usable(value)            true when both `dark` and `light` colour sets are present and valid
--   M.describe(result)                 -> short user-facing recovery/notice string | nil
--   M.recovery_name(kind, stamp)       -> "prefs.json.corrupt-<stamp>" basename to move a bad file aside to
--   Appearance group (mode, skin, accent source + choice, palette style) -- values are keyed by FACT name:
--   M.APPEARANCE                       { {id, fact, kind, key, label, labels}, ... } in application order
--   M.appearance_defaults()            -> snapshot of the defaults
--   M.appearance_snapshot(facts, pal)  -> snapshot { values = {appearance, skin, accent, accent_auto, pal_style},
--                                         palette = deep copy of a USABLE palette value or nil }
--   M.appearance_plan(current, target) -> { changes, values, restore_palette, noop }; reset = plan(current, defaults),
--                                         undo = plan(current, snapshot taken before the reset)
--   M.snapshot_equal(a, b)             values + palette equality
--
-- read() result: { kind, status, value, issues, legacy, unknown, writable, detail }
--   status "ok"         parsed; invalid KEYS were replaced by defaults and listed in `issues` {key, problem, got, used}
--          "missing"    no file / blank text: `value` = defaults, writable
--          "unreadable" text == nil (the scene could not read it): defaults, NOT writable
--          "corrupt"    undecodable, or not a JSON object: defaults, NOT writable (move the file aside first)
--          "newer"      `version` above M.VERSION: known keys normalised, NOT writable (never downgrade it)
--   legacy = no `version` key.  unknown = sorted names of preserved unknown keys.

local M = {}

M.VERSION = 1

local LOCK_MINUTES = { 0, 3, 5, 10, 15 }
local MODE_LABELS = { [0] = "Light", "Dark", "Auto" }
local SKIN_LABELS = { [0] = "Liquid Glass", "Light Acrylic", "Classic Solid" }
local ACCENT_LABELS = { [0] = "Blue", "Purple", "Pink", "Red", "Orange", "Green", "Graphite" }
local STYLE_LABELS = { [0] = "Tonal", "Vibrant", "Neutral", "Soft" }
local ONOFF = { [false] = "Off", [true] = "On" }

-- type: bool | enum (integer min..max) | choice (integer from `choices`).  fact = Settings' fact name.
local SPECS = {
    theme = {
        file = "pleamar_shell.json",
        fields = {
            { key = "dark_mode", fact = "dark_mode", type = "bool", default = true, labels = { [false] = "Light", [true] = "Dark" } },
            { key = "skin", fact = "skin", type = "enum", min = 0, max = 2, default = 0, label = "Skin", labels = SKIN_LABELS },
            { key = "accent", fact = "accent", type = "enum", min = 0, max = 6, default = 0, label = "Accent colour", labels = ACCENT_LABELS },
            { key = "accent_auto", fact = "accent_auto", type = "bool", default = false, label = "Colours from the wallpaper", labels = ONOFF },
            { key = "custom_accent", fact = "custom_accent", type = "enum", min = -1, max = 16777215, default = -1, label = "Custom accent", format = "hex" },
            { key = "style_text", fact = "style_text", type = "enum", min = 0, max = 2, default = 1, label = "Panel text size", labels = { [0] = "Small", "Standard", "Large" } },
            { key = "style_glass", fact = "style_glass", type = "enum", min = 0, max = 2, default = 2, label = "Glass strength", labels = { [0] = "Minimal", "Soft", "Full" } },
            { key = "hour12", fact = "hour12", type = "bool", default = true, label = "12-hour clock", labels = ONOFF },
        },
    },
    prefs = {
        file = "beskar/prefs.json",
        fields = {
            { key = "appearance", fact = "appearance", type = "enum", min = 0, max = 2, default = 1, label = "Appearance", labels = MODE_LABELS },
            { key = "reduce_motion", fact = "reduce_motion", type = "bool", default = false, label = "Reduce motion", labels = ONOFF },
            { key = "bar_style", fact = "bar_style", type = "enum", min = 0, max = 1, default = 0, label = "Menu bar style" },
            { key = "seconds", fact = "pref_seconds", type = "bool", default = false },
            { key = "weather", fact = "pref_weather", type = "bool", default = true },
            { key = "tray", fact = "pref_tray", type = "bool", default = true },
            { key = "workspaces", fact = "pref_workspaces", type = "bool", default = true },
            { key = "bar_apps", fact = "pref_bar_apps", type = "bool", default = true },
            { key = "updates", fact = "pref_updates", type = "bool", default = true },
            { key = "dock_size", fact = "dock_size_i", type = "enum", min = 0, max = 2, default = 1 },
            { key = "wallpaper_fx", fact = "wallpaper_fx", type = "enum", min = 0, max = 2, default = 0 },
            { key = "bar_left_order", fact = "bar_left_order", type = "enum", min = 0, max = 1, default = 0 },
            { key = "bar_right_order", fact = "bar_right_order", type = "enum", min = 0, max = 1, default = 0 },
            { key = "module_output_policy", fact = "module_output_policy", type = "enum", min = 0, max = 2, default = 0 },
            { key = "dock_output_policy", fact = "dock_output_policy", type = "enum", min = 0, max = 2, default = 0 },
            { key = "frame_output_name", fact = "frame_output_name", type = "output", default = "" },
            { key = "dock_show_delay", fact = "dock_show_delay", type = "enum", min = 0, max = 2, default = 0 },
            { key = "dock_delay", fact = "dock_delay_i", type = "enum", min = 0, max = 2, default = 1 },
            { key = "dock_auto", fact = "pref_dock_auto", type = "bool", default = true },
            { key = "widgets", fact = "pref_widgets", type = "bool", default = true },
            { key = "apps", fact = "pref_apps", type = "bool", default = true },
            { key = "night", fact = "nl_mode_i", type = "enum", min = 0, max = 2, default = 0 },
            { key = "night_t", fact = "nl_temp_i", type = "enum", min = 0, max = 2, default = 1 },
            { key = "banners", fact = "banners", type = "bool", default = true },
            { key = "banner_i", fact = "banner_i", type = "enum", min = 0, max = 3, default = 1 },
            { key = "group", fact = "group_apps", type = "bool", default = false },
            { key = "quiet_enabled", fact = "quiet_enabled", type = "bool", default = false },
            { key = "quiet_start", fact = "quiet_start", type = "enum", min = 0, max = 1439, default = 1320 },
            { key = "quiet_end", fact = "quiet_end", type = "enum", min = 0, max = 1439, default = 420 },
            -- minutes on disk, an index into `choices` in the fact (lock_i)
            { key = "lock_min", fact = "lock_i", type = "choice", choices = LOCK_MINUTES, default = 0, fact_index = true },
        },
    },
    palette = {
        file = "beskar/palette.json",
        fields = {
            { key = "style", fact = "pal_style", type = "enum", min = 0, max = 3, default = 0, label = "Palette style", labels = STYLE_LABELS },
        },
        -- plus: src (#rrggbb | nil), dark / light = { a, b, s } (#rrggbb each); handled by normalize_palette
    },
}
M.KINDS = { "theme", "prefs", "palette" }

-- ── helpers ──────────────────────────────────────────────────────

local MAX_DEPTH = 12

local function spec_of(kind)
    local s = SPECS[kind]
    if not s then error("preferences: unknown document kind " .. tostring(kind), 3) end
    return s
end

function M.spec(kind) return spec_of(kind) end

local function to_int(v)
    if type(v) == "string" and v:match("^%s*-?%d+%s*$") then v = tonumber(v) end
    if type(v) ~= "number" or v ~= v or v == math.huge or v == -math.huge then return nil end
    if v ~= math.floor(v) or math.abs(v) > 2 ^ 31 then return nil end
    return math.floor(v)
end

local function to_bool(v)
    if v == true or v == false then return v end
    if v == 1 or v == "true" then return true end
    if v == 0 or v == "false" then return false end
    return nil
end

-- JSON-safe deep copy (strings, finite numbers, booleans, tables of those); nil when it cannot be kept
local function clean(v, depth)
    local t = type(v)
    if t == "string" or t == "boolean" then return v end
    if t == "number" then
        if v ~= v or v == math.huge or v == -math.huge then return nil end
        return v
    end
    if t ~= "table" or depth > MAX_DEPTH then return nil end
    local out = {}
    for k, x in pairs(v) do
        if type(k) == "string" or type(k) == "number" then
            local c = clean(x, depth + 1)
            if c ~= nil then out[k] = c end
        end
    end
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

local function show(v)
    local s = type(v) == "table" and "<table>" or tostring(v)
    if #s > 40 then s = s:sub(1, 37) .. "..." end
    return s
end

-- the one value of a field, coerced; nil + problem when it does not fit
local function coerce(f, raw)
    if f.type == "output" then
        if type(raw) ~= "string" then return nil, "type" end
        if raw == "" or (#raw <= 64 and raw:match("^[%w_.:+%-]+$")) then return raw end
        return nil, "range"
    end
    if f.type == "bool" then
        local b = to_bool(raw)
        if b == nil then return nil, "type" end
        return b
    end
    local n = to_int(raw)
    if n == nil then return nil, "type" end
    if f.type == "enum" then
        if n < f.min or n > f.max then return nil, "range" end
        return n
    end
    for _, c in ipairs(f.choices) do
        if c == n then return n end
    end
    return nil, "range"
end

local function is_hex(s)
    return type(s) == "string" and s:match("^#%x%x%x%x%x%x$") ~= nil
end

-- a { a, b, s } colour set, or nil when any member is not #rrggbb
local function colour_set(raw)
    if type(raw) ~= "table" then return nil end
    if not (is_hex(raw.a) and is_hex(raw.b) and is_hex(raw.s)) then return nil end
    return { a = raw.a:lower(), b = raw.b:lower(), s = raw.s:lower() }
end

local function normalize_palette(doc, out, issues)
    if doc.src ~= nil then
        if is_hex(doc.src) then
            out.src = doc.src:lower()
        else
            issues[#issues + 1] = { key = "src", problem = "type", got = show(doc.src), used = "none" }
        end
    end
    for _, mode in ipairs({ "dark", "light" }) do
        if doc[mode] ~= nil then
            local set = colour_set(doc[mode])
            if set then
                out[mode] = set
            else
                issues[#issues + 1] = { key = mode, problem = "type", got = show(doc[mode]), used = "none" }
            end
        end
    end
end

-- ── normalisation ────────────────────────────────────────────────

function M.defaults(kind)
    local spec = spec_of(kind)
    local out = { version = M.VERSION }
    for _, f in ipairs(spec.fields) do out[f.key] = f.default end
    return out
end

local function known_keys(kind)
    local known = { version = true }
    for _, f in ipairs(spec_of(kind).fields) do known[f.key] = true end
    if kind == "palette" then known.src, known.dark, known.light = true, true, true end
    return known
end

function M.normalize(kind, doc)
    local spec = spec_of(kind)
    if type(doc) ~= "table" then doc = {} end
    local out, issues = {}, {}
    local info = { legacy = false, newer = false, unknown = {} }

    local ver = nil
    if doc.version == nil then
        info.legacy = true
    else
        ver = to_int(doc.version)
        if ver == nil or ver < 1 then
            issues[#issues + 1] = { key = "version", problem = ver == nil and "type" or "range", got = show(doc.version), used = M.VERSION }
            info.legacy = true
            ver = nil
        end
    end
    if ver and ver > M.VERSION then
        info.newer = true
        out.version = ver
    else
        out.version = M.VERSION
    end

    for _, f in ipairs(spec.fields) do
        local raw = doc[f.key]
        if raw == nil then
            out[f.key] = f.default
        else
            local v, problem = coerce(f, raw)
            if v == nil then
                issues[#issues + 1] = { key = f.key, problem = problem, got = show(raw), used = f.default }
                v = f.default
            end
            out[f.key] = v
        end
    end
    if kind == "palette" then normalize_palette(doc, out, issues) end

    local known = known_keys(kind)
    for k, raw in pairs(doc) do
        if type(k) == "string" and not known[k] then
            local c = clean(raw, 1)
            if c ~= nil then
                out[k] = c
                info.unknown[#info.unknown + 1] = k
            else
                issues[#issues + 1] = { key = k, problem = "unsupported", got = show(raw), used = "dropped" }
            end
        end
    end
    table.sort(info.unknown)
    return out, issues, info
end

function M.palette_usable(value)
    return type(value) == "table" and value.dark ~= nil and value.light ~= nil
        and colour_set(value.dark) ~= nil and colour_set(value.light) ~= nil
end

function M.read(kind, text, decode)
    local res = { kind = kind, issues = {}, legacy = false, unknown = {}, writable = false }
    local function fallback(status, detail)
        res.status, res.detail = status, detail
        res.value = M.defaults(kind)
        return res
    end
    if type(text) ~= "string" then return fallback("unreadable", "no text") end
    text = text:gsub("^\239\187\191", "")
    if not text:find("%S") then
        res.writable = true
        return fallback("missing")
    end
    if text:match("^%s*%[") then return fallback("corrupt", "not a JSON object") end
    if type(decode) ~= "function" then error("preferences.read: decode function required", 2) end
    local ok, doc = pcall(decode, text)
    if not ok then return fallback("corrupt", tostring(doc)) end
    if type(doc) ~= "table" or #doc > 0 then return fallback("corrupt", "not a JSON object") end

    local value, issues, info = M.normalize(kind, doc)
    res.value, res.issues, res.legacy, res.unknown = value, issues, info.legacy, info.unknown
    res.status = info.newer and "newer" or "ok"
    res.writable = not info.newer
    if info.newer then res.detail = "written by a newer version (" .. tostring(value.version) .. ")" end
    return res
end

-- ── encoding ─────────────────────────────────────────────────────

local ESC = { ['"'] = '\\"', ["\\"] = "\\\\", ["'"] = "\\u0027", ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t" }

local function enc_string(s)
    return '"' .. s:gsub("[%c\"\\']", function(c) return ESC[c] or string.format("\\u%04x", c:byte()) end) .. '"'
end

local function enc_number(n)
    if n == math.floor(n) and math.abs(n) < 2 ^ 53 then return string.format("%d", n) end
    return string.format("%.17g", n)
end

local function enc(v, depth)
    local t = type(v)
    if t == "boolean" then return tostring(v) end
    if t == "string" then return enc_string(v) end
    if t == "number" then return enc_number(v) end
    if t ~= "table" or depth > MAX_DEPTH then return nil end
    local n = #v
    local count = 0
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
        if e ~= nil then parts[#parts + 1] = enc_string(k) .. ": " .. e end
    end
    return "{" .. table.concat(parts, ", ") .. "}"
end

function M.encode(kind, value)
    local spec = spec_of(kind)
    local v, issues = M.normalize(kind, value)
    local known = known_keys(kind)
    local parts = { '"version": ' .. enc_number(v.version) }
    for _, f in ipairs(spec.fields) do
        parts[#parts + 1] = enc_string(f.key) .. ": " .. enc(v[f.key], 1)
    end
    if kind == "palette" then
        if v.src then parts[#parts + 1] = '"src": ' .. enc_string(v.src) end
        for _, mode in ipairs({ "dark", "light" }) do
            local s = v[mode]
            if s then
                parts[#parts + 1] = string.format('"%s": {"a": %s, "b": %s, "s": %s}', mode, enc_string(s.a), enc_string(s.b), enc_string(s.s))
            end
        end
    end
    local extra = {}
    for k in pairs(v) do
        if not known[k] then extra[#extra + 1] = k end
    end
    table.sort(extra)
    for _, k in ipairs(extra) do
        local e = enc(v[k], 1)
        if e ~= nil then parts[#parts + 1] = enc_string(k) .. ": " .. e end
    end
    return "{" .. table.concat(parts, ", ") .. "}", issues
end

-- ── facts <-> documents ──────────────────────────────────────────

function M.to_facts(kind, value)
    local spec = spec_of(kind)
    local v = M.normalize(kind, value)
    local facts = {}
    for _, f in ipairs(spec.fields) do
        local x = v[f.key]
        if f.fact_index then
            for i, c in ipairs(f.choices) do
                if c == x then x = i - 1 end
            end
        end
        facts[f.fact] = x
    end
    return facts
end

function M.from_facts(kind, facts, base)
    local spec = spec_of(kind)
    local out = M.normalize(kind, base or {})
    local issues = {}
    facts = facts or {}
    for _, f in ipairs(spec.fields) do
        local raw = facts[f.fact]
        if raw ~= nil then
            if f.fact_index then
                local i = to_int(raw)
                raw = i and f.choices[i + 1]
            end
            local v, problem = coerce(f, raw)
            if v == nil then
                issues[#issues + 1] = { key = f.key, problem = problem or "range", got = show(facts[f.fact]), used = out[f.key] }
            else
                out[f.key] = v
            end
        end
    end
    return out, issues
end

-- ── notices ──────────────────────────────────────────────────────

function M.describe(result)
    local name = spec_of(result.kind).file:match("[^/]+$")
    if result.status == "corrupt" then
        return name .. " could not be read (" .. tostring(result.detail) .. "). It was left as it is; defaults are in use until it is repaired or moved aside."
    elseif result.status == "unreadable" then
        return name .. " could not be read. It was left as it is; defaults are in use."
    elseif result.status == "newer" then
        return name .. " was written by a newer Beskar. It is read but will not be overwritten."
    elseif #result.issues > 0 then
        local n = #result.issues
        return string.format("%d invalid value%s in %s fell back to the default.", n, n == 1 and "" or "s", name)
    end
    return nil
end

function M.recovery_name(kind, stamp)
    local name = spec_of(kind).file:match("[^/]+$")
    stamp = tostring(stamp or ""):gsub("[^%w%-]", "")
    if stamp == "" then stamp = "backup" end
    return name .. ".corrupt-" .. stamp
end

-- ── Appearance group ─────────────────────────────────────────────
-- Excluded on purpose: dark_mode (derived from `appearance` by Settings), hour12, apps (other apps' theming),
-- the wallpaper itself, and anything hardware or personal.

local function field_of(kind, key)
    for _, f in ipairs(SPECS[kind].fields) do
        if f.key == key then return f end
    end
end

M.APPEARANCE = {}
for _, a in ipairs({
    { id = "appearance.mode", kind = "prefs", key = "appearance" },
    { id = "appearance.skin", kind = "theme", key = "skin" },
    { id = "appearance.wallpaper-colours", kind = "theme", key = "accent_auto" },
    { id = "appearance.accent", kind = "theme", key = "accent" },
    { id = "appearance.palette", kind = "palette", key = "style" },
    { id = "appearance.custom-accent", kind = "theme", key = "custom_accent", optional = true },
    { id = "appearance.text", kind = "theme", key = "style_text", optional = true },
    { id = "appearance.glass-strength", kind = "theme", key = "style_glass", optional = true },
    { id = "appearance.motion", kind = "prefs", key = "reduce_motion", optional = true },
}) do
    local f = field_of(a.kind, a.key)
    a.fact, a.label, a.labels, a.field = f.fact, f.label, f.labels, f
    M.APPEARANCE[#M.APPEARANCE + 1] = a
end

local function norm_values(src)
    local values = {}
    src = type(src) == "table" and src or {}
    for _, a in ipairs(M.APPEARANCE) do
        local v = nil
        if src[a.fact] ~= nil then v = coerce(a.field, src[a.fact]) end
        if v == nil then v = a.field.default end
        values[a.fact] = v
    end
    return values
end

local function norm_palette(pal)
    if not M.palette_usable(pal) then return nil end
    local out = { style = to_int(pal.style) or 0, dark = colour_set(pal.dark), light = colour_set(pal.light) }
    if is_hex(pal.src) then out.src = pal.src:lower() end
    return out
end

function M.appearance_snapshot(facts, pal)
    return { values = norm_values(facts), palette = norm_palette(pal) }
end

function M.appearance_defaults()
    return { values = norm_values({}), palette = nil }
end

function M.snapshot_equal(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then return false end
    return deep_equal(norm_values(a.values), norm_values(b.values)) and deep_equal(norm_palette(a.palette), norm_palette(b.palette))
end

local function label_of(a, v)
    if a.field.format == "hex" then return v == -1 and "Preset colour" or string.format("#%06x", v) end
    return (a.labels and a.labels[v]) or tostring(v)
end

function M.appearance_plan(current, target)
    local cur = norm_values(type(current) == "table" and current.values or nil)
    local tgt = norm_values(type(target) == "table" and target.values or nil)
    local plan = { changes = {}, values = tgt }
    for _, a in ipairs(M.APPEARANCE) do
        if cur[a.fact] ~= tgt[a.fact] then
            plan.changes[#plan.changes + 1] = {
                id = a.id, fact = a.fact, label = a.label or a.id,
                from = cur[a.fact], to = tgt[a.fact],
                from_label = label_of(a, cur[a.fact]), to_label = label_of(a, tgt[a.fact]),
            }
        end
    end
    -- the colours to put back; nil = leave the palette cache as it is (a reset to defaults has none)
    local tp = type(target) == "table" and norm_palette(target.palette) or nil
    local cp = type(current) == "table" and norm_palette(current.palette) or nil
    if tp and not deep_equal(tp, cp) then plan.restore_palette = tp end
    plan.noop = #plan.changes == 0 and plan.restore_palette == nil
    return plan
end

return M
