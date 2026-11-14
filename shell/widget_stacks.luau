-- Manual widget stacks (C4c). Pure logic: no globals, no scene access, so tests/widget-stacks.lua runs it as is.
-- Used by widgets.luau (the owner and ONLY writer of widgets.json), widget_options.luau (file encode / decode) and
-- widget_layouts.luau (saved desktops).
--
-- A stack is cards that share ONE footprint (same output, position and size); only the ACTIVE member is drawn,
-- interactive and fed. Membership lives on the cards themselves, so every copy of a card (undo, saved layouts) keeps it:
--     card.stack = { id = <stack id>, i = <1-based page order>, on = true on the active member only }
-- Invariants (what `normalize` restores, and every function below keeps):
--   · a stack has 2 to MAX_MEMBERS members, orders 1..n without gaps, exactly one active member
--   · members agree on out / x / y / sz (the footprint of the ACTIVE member) and every member's kind supports that size
--   · position lock is stack-wide: all members locked or none (a locked stack never moves, stacks or resizes
--     out of place; the lock follows whichever member the user changed)
-- Stack ids are per desktop / per layout (`next_id`); nothing else refers to them.
local S = {}

S.MAX_MEMBERS = 8
S.MAX_ID = 2147483646

local function is_int(v, lo, hi)
    return type(v) == "number" and v == v and v == math.floor(v) and v >= lo and v <= hi
end

local function locked(card) return card.opts ~= nil and card.opts.lock == true end

local function supports(kind_of, kind, sz)
    if not kind_of then return true end
    local k = kind_of(kind)
    if not k then return false end
    for _, s in ipairs(k.sizes) do
        if s == sz then return true end
    end
    return false
end

-- ── the record ──
-- A stored value → { id, i, on } or nil when it is not a usable membership.
function S.clean(raw)
    if type(raw) ~= "table" then return nil end
    if not is_int(raw.id, 1, S.MAX_ID) or not is_int(raw.i, 1, 1000) then return nil end
    return { id = raw.id, i = raw.i, on = raw.on == true or nil }
end

function S.copy(st)
    if type(st) ~= "table" then return nil end
    return { id = st.id, i = st.i, on = st.on }
end

function S.hidden(card) return card.stack ~= nil and card.stack.on ~= true end
function S.stacked(card) return card.stack ~= nil end
function S.same(a, b) return a.stack ~= nil and b.stack ~= nil and a.stack.id == b.stack.id end

-- ── reading ──
-- Members of a stack id, in page order (a copy of the list, not of the cards).
function S.members_of(cards, id)
    local list = {}
    for n, c in ipairs(cards) do
        if c.stack and c.stack.id == id then list[#list + 1] = { c = c, n = n } end
    end
    table.sort(list, function(a, b)
        if a.c.stack.i ~= b.c.stack.i then return a.c.stack.i < b.c.stack.i end
        return a.n < b.n
    end)
    local out = {}
    for i, e in ipairs(list) do out[i] = e.c end
    return out
end

-- The members of `card`'s stack, or nil when it is not stacked.
function S.members(cards, card)
    if not card.stack then return nil end
    return S.members_of(cards, card.stack.id)
end

-- The card that is shown for `card`'s stack (the card itself when it is not stacked).
function S.active(cards, card)
    if not card.stack or card.stack.on then return card end
    for _, m in ipairs(S.members_of(cards, card.stack.id)) do
        if m.stack.on then return m end
    end
    return card
end

function S.next_id(cards)
    local top = 0
    for _, c in ipairs(cards) do
        if c.stack and c.stack.id > top then top = c.stack.id end
    end
    return top + 1
end

-- card id → { n = members, i = position of that card } for every stacked card, in one pass.
function S.index_map(cards)
    local by, out = {}, {}
    for _, c in ipairs(cards) do
        if c.stack then by[c.stack.id] = (by[c.stack.id] or 0) + 1 end
    end
    for _, c in ipairs(cards) do
        if c.stack then out[c.id] = { n = by[c.stack.id], i = c.stack.i } end
    end
    return out
end

-- ── keeping the invariants ──
local function renumber(members, active)
    for i, m in ipairs(members) do
        m.stack.i = i
        m.stack.on = (m == active) or nil
    end
end

-- Take every member out of its stack (positions untouched).
local function dissolve(members)
    for _, m in ipairs(members) do m.stack = nil end
end

-- Repair every stack in `cards` (a hand-edited or newer file, a layout whose kinds changed): members that no longer
-- fit the footprint of the active one leave the stack, a stack left with fewer than two members dissolves, orders and
-- the active member are made valid, the lock is made stack-wide. `kind_of` (optional) also checks sizes. → changed.
function S.normalize(cards, kind_of)
    local changed = false
    local ids, order = {}, {}
    for _, c in ipairs(cards) do
        if c.stack then
            local st = S.clean(c.stack)
            if not st then c.stack = nil; changed = true
            else
                if st.id ~= c.stack.id or st.i ~= c.stack.i or st.on ~= c.stack.on then changed = true end
                c.stack = st
                if not ids[st.id] then ids[st.id] = true; order[#order + 1] = st.id end
            end
        end
    end
    for _, id in ipairs(order) do
        local members = S.members_of(cards, id)
        local active
        for _, m in ipairs(members) do
            if m.stack.on then active = m; break end
        end
        active = active or members[1]
        local keep, any_lock = {}, false
        for _, m in ipairs(members) do
            local fits = m == active or (m.out == active.out and m.x == active.x and m.y == active.y and m.sz == active.sz
                and supports(kind_of, m.kind, active.sz))
            if fits and #keep < S.MAX_MEMBERS then
                keep[#keep + 1] = m
                if locked(m) then any_lock = true end
            else
                m.stack = nil
                changed = true
            end
        end
        if not supports(kind_of, active.kind, active.sz) then
            -- the footprint's own size is not one its kind draws: nothing to repair it with
            dissolve(keep)
            changed = true
        elseif #keep < 2 then
            dissolve(keep)
            if #keep == 1 then changed = true end
        else
            if any_lock then
                for _, m in ipairs(keep) do
                    if not locked(m) then m.opts = m.opts or {}; m.opts.lock = true; changed = true end
                end
            end
            renumber(keep, active)
            for i, m in ipairs(keep) do
                if m.stack.i ~= i then changed = true end
            end
        end
    end
    return changed
end

-- Copy the footprint of `card` (out, position, size) to the rest of its stack.
function S.sync(cards, card)
    if not card.stack then return end
    for _, m in ipairs(S.members_of(cards, card.stack.id)) do
        if m ~= card then m.out, m.x, m.y, m.sz = card.out, card.x, card.y, card.sz end
    end
end

-- Position lock is stack-wide: make every member of `card`'s stack lock like `card` (its own value wins).
function S.set_lock(cards, card, on)
    if not card.stack then return end
    for _, m in ipairs(S.members_of(cards, card.stack.id)) do
        if m ~= card then
            if on then
                m.opts = m.opts or {}
                m.opts.lock = true
            elseif m.opts then
                m.opts.lock = nil
                if next(m.opts) == nil then m.opts = nil end
            end
        end
    end
end

-- Sizes (in the kind's own order) every member of the stack can draw; the card's own kind's sizes when not stacked.
function S.sizes(cards, card, kind_of)
    local k = kind_of(card.kind)
    if not k then return {} end
    local members = S.members(cards, card)
    if not members then return k.sizes end
    local out = {}
    for _, sz in ipairs(k.sizes) do
        local all = true
        for _, m in ipairs(members) do
            if not supports(kind_of, m.kind, sz) then all = false; break end
        end
        if all then out[#out + 1] = sz end
    end
    return out
end

-- ── changing ──
-- Why `source` cannot be stacked onto `target` (nil when it can): a code the caller turns into words.
function S.join_refusal(cards, source, target, kind_of)
    if not source or not target then return "missing" end
    if source == target or S.same(source, target) then return "same" end
    if source.out ~= target.out then return "output" end
    if locked(source) then return "locked" end
    if not supports(kind_of, source.kind, target.sz) then return "size" end
    local members = S.members(cards, target)
    if members and #members >= S.MAX_MEMBERS then return "full" end
    return nil
end

-- Stack `source` onto `target`'s footprint: it joins at the end of the target's stack (a new one when the target was
-- alone) and becomes the active face. If it was in a stack of its own it only leaves that one. → ok | false, code
function S.join(cards, source, target, kind_of)
    local why = S.join_refusal(cards, source, target, kind_of)
    if why then return false, why end
    S.leave(cards, source)
    local members = S.members(cards, target)
    local id
    if members then
        id = target.stack.id
    else
        id = S.next_id(cards)
        target.stack = { id = id, i = 1 }
        members = { target }
    end
    local was_locked = locked(target)
    for _, m in ipairs(members) do m.stack.on = nil end
    source.stack = { id = id, i = #members + 1, on = true }
    source.out, source.x, source.y, source.sz = target.out, target.x, target.y, target.sz
    if was_locked then
        source.opts = source.opts or {}
        source.opts.lock = true
    end
    return true
end

-- `card` leaves its stack (position untouched; the caller places it): the rest closes up, a neighbour becomes active
-- when it was, and a stack left with one member dissolves. → ok (false when it was not stacked)
function S.leave(cards, card)
    if not card.stack then return false end
    local id = card.stack.id
    local members = S.members_of(cards, id)
    local rest, at, active = {}, 0, nil
    for _, m in ipairs(members) do
        if m == card then at = #rest + 1
        else
            rest[#rest + 1] = m
            if m.stack.on then active = m end
        end
    end
    card.stack = nil
    if #rest < 2 then
        dissolve(rest)
        return true
    end
    active = active or rest[math.min(at, #rest)]
    renumber(rest, active)
    return true
end

-- Make `card` the face of its stack. → ok
function S.show(cards, card)
    if not card.stack then return false end
    local members = S.members_of(cards, card.stack.id)
    renumber(members, card)
    return true
end

-- Page the stack of `card` by `delta` (+1 next, -1 previous, wraps). → the member now shown, or nil when not stacked
function S.page(cards, card, delta)
    local members = S.members(cards, card)
    if not members or #members < 2 then return nil end
    local at = 1
    for i, m in ipairs(members) do
        if m.stack.on then at = i end
    end
    local picked = members[(at - 1 + delta) % #members + 1]
    renumber(members, picked)
    return picked
end

-- ── what the widget bar reads (inside the card-options snapshot) ──
-- → { id = stack id (0 alone), n = members, i = this card's page, m = { {card id, kind}… in page order },
--     pick = { {card id, kind}… } the cards `card` could be stacked onto (one per stack: its shown face) }
-- Positional pairs keep it small (the bridge's command is limited to 4096 bytes; at most 16 + 16 pairs).
function S.info(cards, card, kind_of)
    local info = { id = 0, n = 1, i = 1, m = {}, pick = {} }
    local members = S.members(cards, card)
    if members then
        info.id, info.n, info.i = card.stack.id, #members, card.stack.i
        for _, m in ipairs(members) do info.m[#info.m + 1] = { m.id, m.kind } end
    end
    for _, c in ipairs(cards) do
        if (c.stack == nil or c.stack.on) and not S.same(c, card) and c ~= card
            and not S.join_refusal(cards, card, c, kind_of) then
            info.pick[#info.pick + 1] = { c.id, c.kind }
        end
    end
    return info
end

-- Stable text for a layout signature: the page order of a stacked card (nothing for a loose one). The active face is a
-- view state, not part of what a layout "is", so paging never makes a saved desktop look edited.
function S.sig(card)
    if not card.stack then return "" end
    return "s" .. card.stack.i
end

return S
