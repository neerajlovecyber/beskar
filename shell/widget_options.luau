-- Per-card widget options (C4b). Pure logic: no globals, no scene access, so tests/widget-options.lua runs it as is.
-- Used by widgets.luau (the ONLY writer of ~/.config/beskar/widgets.json) and widget_layouts.luau (saved desktops).
--
-- A card keeps only what differs from the default, so the record stays clean for later features (stacks):
--     card = { id, out, kind, sz, x, y, opts = { lock = true, date = "off", seconds = "on", format = "24" } }
-- The supported options, their order, stored values and labels are DATA in widgets_data.luau (OPTIONS). Every value
-- travels as its 1-based index into the option's `keys` (1 = default); one UI event code is `option id * 10 + index`.
--
-- widgets.json (version 2): { version, snap, next, cards = [ { id, out, kind, sz, x, y, opts? } ] }
--   version 3 only when some card is stacked (C4c): such a card also has `stack = { id, i, on? }` (shell/widget_stacks.luau:
--   stack id, page order, `on` on the shown member). A desktop without stacks is still written as version 2.
--   version 1 (no `version` at all counts as 1) is the legacy file: same cards, no options. It is read as it is and
--   rewritten as version 2 on the next save. A file of a NEWER version is still read (what this build understands),
--   and `decode_file` says so, so the caller can keep a copy before it overwrites it.
local Data = require("widgets_data")
local Stacks = require("widget_stacks")

local O = {}

O.FILE_VERSION = 3           -- the newest file this build understands (3 = stacks, C4c)
O.BASE_VERSION = 2           -- what a file WITHOUT stacks is still written as, so an older Beskar keeps reading it
O.SNAPSHOT_VERSION = 1       -- the compact snapshot the widget bar reads (text wb_card_options)
O.MAX_UNKNOWN_KEYS = 8       -- plain values kept for a widget kind this build does not know

local function is_finite(v) return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge end

-- ── the schema ──
function O.def(key) return Data.OPTIONS[key] end

function O.by_id(id)
    for _, key in ipairs(Data.OPTION_ORDER) do
        if Data.OPTIONS[key].id == id then return Data.OPTIONS[key] end
    end
end

function O.applies(def, kind)
    if not def.kinds then return true end
    for _, k in ipairs(def.kinds) do
        if k == kind then return true end
    end
    return false
end

-- the options a kind supports, in display order
function O.defs(kind)
    local list = {}
    for _, key in ipairs(Data.OPTION_ORDER) do
        local def = Data.OPTIONS[key]
        if O.applies(def, kind) then list[#list + 1] = def end
    end
    return list
end

local function index_of(def, value)
    for i, k in ipairs(def.keys) do
        if k == value then return i end
    end
end

-- value index of a stored value (e.g. "off" → 3), nil when it is not one of the option's values
function O.key_index(def, value) return index_of(def, value) end

-- A stored `opts` table → a clean one (only known keys with a valid, non-default value), or nil when nothing is left.
-- A kind this build does not know keeps its plain scalar values (bounded), so a layout or file written by a newer
-- Beskar loses nothing here; `lock` is validated everywhere.
function O.clean(kind, raw)
    if type(raw) ~= "table" then return nil end
    local out, n = {}, 0
    if Data.KINDS[kind] then
        for _, key in ipairs(Data.OPTION_ORDER) do
            local def = Data.OPTIONS[key]
            local v = raw[key]
            if v ~= nil and O.applies(def, kind) then
                local i = index_of(def, v)
                if i and i > 1 then out[key] = def.keys[i]; n = n + 1 end
            end
        end
    else
        local names = {}
        for key, v in pairs(raw) do
            if type(key) == "string" and #key <= 24 and key:match("^[%a_][%w_]*$") then
                if key == "lock" then
                    if v == true then names[#names + 1] = key end
                elseif type(v) == "boolean" or is_finite(v) or (type(v) == "string" and #v <= 32 and not v:find("%c")) then
                    names[#names + 1] = key
                end
            end
        end
        table.sort(names)
        for i = 1, math.min(#names, O.MAX_UNKNOWN_KEYS) do
            out[names[i]] = raw[names[i]]
            n = n + 1
        end
    end
    return n > 0 and out or nil
end

-- ── reading and changing one card ──
function O.locked(card) return card.opts ~= nil and card.opts.lock == true end

-- index of the card's value for `key` (1 = default)
function O.index(card, key)
    local def = Data.OPTIONS[key]
    if not def then return 1 end
    return index_of(def, card.opts and card.opts[key]) or 1
end

-- Set option `key` to value index `idx` (1 = default). → ok, changed | false, reason
function O.set(card, key, idx)
    local def = Data.OPTIONS[key]
    if not def then return false, "unknown" end
    if not O.applies(def, card.kind) then return false, "unsupported" end
    if type(idx) ~= "number" or idx ~= math.floor(idx) or idx < 1 or idx > #def.keys then return false, "value" end
    local was = O.index(card, key)
    if was == idx then return true, false end
    card.opts = card.opts or {}
    if idx == 1 then card.opts[key] = nil else card.opts[key] = def.keys[idx] end
    if next(card.opts) == nil then card.opts = nil end
    return true, true
end

-- Next value (wraps around). → ok, changed | false, reason
function O.cycle(card, key)
    local def = Data.OPTIONS[key]
    if not def then return false, "unknown" end
    return O.set(card, key, O.index(card, key) % #def.keys + 1)
end

-- Back to every default. Only the options this build knows are removed; plain values kept for an unknown kind go too.
function O.reset(card)
    if card.opts == nil then return true, false end
    card.opts = nil
    return true, true
end

-- A UI event code (option id * 10 + value index) → option definition, index. nil when it names nothing.
function O.parse_code(code)
    code = tonumber(code)
    if not code or code ~= math.floor(code) or code < 10 then return nil end
    local def = O.by_id(math.floor(code / 10))
    if not def then return nil end
    return def, code % 10
end

-- A stable text for a card's options (ordered), so a saved desktop knows when the live one differs.
function O.sig(opts)
    if not opts then return "" end
    local names = {}
    for key in pairs(opts) do names[#names + 1] = key end
    table.sort(names)
    local parts = {}
    for _, key in ipairs(names) do parts[#parts + 1] = key .. "=" .. tostring(opts[key]) end
    return table.concat(parts, ",")
end

local function copy(v)
    if type(v) ~= "table" then return v end
    local t = {}
    for k, x in pairs(v) do t[k] = copy(x) end
    return t
end
O.copy = copy

-- ── clock presentation ──
-- globals = { hour12 = bool|nil (the shell's choice), seconds = bool (the shell's default for widgets) }
-- → { hour12, seconds, date }: what ONE clock card shows. "inherit" follows the globals; the date line, when
-- inherited, appears from the medium size up (as before options existed).
function O.clock(card, globals)
    local o = card.opts or {}
    local g = globals or {}
    local h12
    if o.format == "12" then h12 = true
    elseif o.format == "24" then h12 = false
    else h12 = not (g.hour12 == false or g.hour12 == 0) end
    local sec = o.seconds == "on" or (o.seconds ~= "off" and (g.seconds == true or g.seconds == 1))
    local date = o.date == "on" or (o.date ~= "off" and (card.sz or 0) > 0)
    return { hour12 = h12, seconds = sec, date = date }
end

-- "2:05:09 PM" → "2:05:09", "PM" · "14:05" → "14:05", ""
function O.split_time(t)
    local time, ampm = tostring(t):match("^(%d+:%d+:?%d*)%s*(%a*)$")
    return time or tostring(t), ampm or ""
end

-- ── the compact snapshot for the widget bar ──
-- card: the selected card or nil. meta = { editing = bool, name = fn(kind) → name, sizes = fn(kind) → count }
-- Small on purpose (the IPC command is limited to 4096 bytes): no positions, no timestamps.
function O.snapshot(card, meta)
    meta = meta or {}
    local snap = { v = O.SNAPSHOT_VERSION, editing = meta.editing == true, sel = card and card.id or 0, options = {} }
    if not card then return snap end
    snap.kind = card.kind
    snap.name = meta.name and meta.name(card.kind) or ""
    snap.sz = card.sz
    snap.nsz = meta.sizes and meta.sizes(card.kind) or 1
    snap.out = card.out
    snap.lock = O.locked(card)
    if meta.stack then snap.stack = meta.stack(card) end
    for _, def in ipairs(O.defs(card.kind)) do
        snap.options[#snap.options + 1] = { id = def.id, key = def.key, label = def.label,
            value = O.index(card, def.key), n = #def.keys, labels = def.labels }
    end
    return snap
end

-- ── widgets.json ──
-- Decoded JSON → { cards, next, snap, version, newer, migrated } or nil when it is not a card file at all.
-- `kind_of(id)` says whether a kind exists (legacy behaviour: cards of an unknown kind are not loaded). Ids that are
-- missing, not positive integers or repeated get a fresh one, so selecting a card by id is never ambiguous.
function O.decode_file(d, kind_of)
    if type(d) ~= "table" or type(d.cards) ~= "table" then return nil end
    local version = tonumber(d.version)
    if not is_finite(version) or version < 1 then version = 1 end
    local cards, used, maxid, fresh = {}, {}, 0, {}
    for _, c in ipairs(d.cards) do
        if type(c) == "table" then
            local kind = tonumber(c.kind) or 0
            if kind_of(kind) then
                local id = tonumber(c.id)
                local card = { id = 0, out = type(c.out) == "string" and c.out or nil, kind = kind,
                    sz = tonumber(c.sz) or 0, x = tonumber(c.x) or 48, y = tonumber(c.y) or 72, opts = O.clean(kind, c.opts),
                    stack = Stacks.clean(c.stack) }
                if is_finite(id) and id == math.floor(id) and id >= 1 and id <= 2147483646 and not used[id] then
                    card.id = id
                    used[id] = true
                    if id > maxid then maxid = id end
                else
                    fresh[#fresh + 1] = card
                end
                cards[#cards + 1] = card
            end
        end
    end
    local nxt = tonumber(d.next)
    if not is_finite(nxt) or nxt <= maxid then nxt = maxid + 1 end
    for _, card in ipairs(fresh) do
        card.id = nxt
        nxt = nxt + 1
    end
    Stacks.normalize(cards, kind_of)
    return { cards = cards, next = nxt, snap = d.snap ~= false, version = version,
        newer = version > O.FILE_VERSION, migrated = version < O.BASE_VERSION }
end

-- Live cards → the table widgets.json stores.
function O.encode_file(cards, next_id, snap)
    local list, version = {}, O.BASE_VERSION
    for _, c in ipairs(cards) do
        list[#list + 1] = { id = c.id, out = c.out, kind = c.kind, sz = c.sz, x = c.x, y = c.y, opts = copy(c.opts),
            stack = Stacks.copy(c.stack) }
        if c.stack then version = O.FILE_VERSION end
    end
    return { version = version, snap = snap and true or false, next = next_id, cards = list }
end

return O
