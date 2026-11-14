-- Pure frame / dock customization helpers (C3). No `run`, no timers, no facts: topbar.luau calls these and
-- applies the results, and `lua tests/frame-options.lua` covers them without the shell.
--
-- Contract with topbar.plm (keep the numbers in sync with the `pick(...)` / layer claims there):
--   Settings.dock_size_i   0 small 32 px icon · 1 standard 38 (default, the old size) · 2 large 46
--   Settings.dock_delay_i  0 quick 1.2 s · 1 standard 2.5 s (default, the old delay) · 2 relaxed 4.5 s
--   Settings.pref_workspaces / pref_bar_apps / pref_updates   booleans, default true
local M = {}

M.DOCK_ICON = { 32, 38, 46 }
M.PEEK_MS = { 1200, 2500, 4500 }
M.MAX_PINS = 12           -- the dock shows at most this many items (model dock_items max 12)
M.MAX_ID = 512            -- longest pin string accepted from an event

-- An enum fact from Settings, whatever arrives: an integer 0..max, else `default`.
function M.index(v, default, max)
    v = tonumber(v)
    if not v or v ~= math.floor(v) or v < 0 or v > max then
        return default
    end
    return v
end

function M.dock_icon(i)
    return M.DOCK_ICON[M.index(i, 1, 2) + 1]
end

function M.peek_ms(i)
    return M.PEEK_MS[M.index(i, 1, 2) + 1]
end

function M.flag(v, default)
    if v == nil then
        return default
    end
    return v == true or v == 1
end

-- The payload of `dock_move_pin(id, direction)`. `p` is a table ({ id = , direction = } or { id, direction }).
-- id: a whole number >= 0 (the dock's current item index, as `dock_click` uses) or a pin string (one line, bounded).
-- direction: negative / "left" / "up" = towards the start, positive / "right" / "down" = towards the end.
-- Returns id, dir (-1 or 1) or nil.
function M.parse_move(p)
    if type(p) ~= "table" then
        return nil
    end
    local id, dir = p.id, p.direction
    if id == nil then id = p[1] end
    if dir == nil then dir = p[2] end
    if type(id) == "string" then
        if id == "" or #id > M.MAX_ID or id:find("[%c]") then
            return nil
        end
    else
        id = tonumber(id)
        if not id or id ~= math.floor(id) or id < 0 or id >= M.MAX_PINS then
            return nil
        end
    end
    if type(dir) == "string" then
        local d = dir:lower()
        if d == "left" or d == "up" or d == "before" then
            dir = -1
        elseif d == "right" or d == "down" or d == "after" then
            dir = 1
        else
            dir = tonumber(d)
        end
    end
    dir = tonumber(dir)
    if not dir or dir == 0 or dir ~= dir then
        return nil
    end
    return id, (dir < 0) and -1 or 1
end

-- `items`: what the dock shows, in order. Each has `pinned` and, when pinned, `pin_pos` (its position in the saved
-- list) and `pinstr` (that list entry). Returns, per item, whether a pinned item can go left / right: the move is
-- among the VISIBLE pins only (a pin with no desktop entry stays where it is in the file).
function M.move_flags(items)
    local last, first_pos, n = nil, nil, 0
    for i, it in ipairs(items) do
        if it.pinned and it.pin_pos then
            n = n + 1
            first_pos = first_pos or i
            last = i
        end
    end
    local out = {}
    for i, it in ipairs(items) do
        local ok = it.pinned and it.pin_pos and n > 1
        out[i] = { left = ok and i ~= first_pos or false, right = ok and i ~= last or false }
    end
    return out
end

M.MAX_NAME = 64
M.MAX_LABEL = 128

-- A name for display: no control characters, trimmed, bounded (by characters when it is valid UTF-8).
function M.clean_name(s)
    s = tostring(s or ""):gsub("[%c]", " "):gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "")
    if not utf8.len(s) then
        s = s:gsub("[\128-\255]", "?")
    end
    if utf8.len(s) > M.MAX_NAME then
        s = s:sub(1, utf8.offset(s, M.MAX_NAME) - 1) .. "…"
    end
    return s
end

-- A pin as it may be shown or sent back: a pin made from a running window is `app:<id>|<command line>`: the command
-- never leaves this module, only `app:<id>`. Desktop ids are shown as they are. Bounded, no control characters.
function M.pin_label(pinstr)
    local s = tostring(pinstr or "")
    local aid = s:match("^(app:[^|]+)|")
    s = (aid or s):gsub("[%c]", "")
    return s:sub(1, M.MAX_LABEL)
end

-- The rows the Settings list shows: the pinned items the dock shows, in dock order, each with its dock item index
-- (the `id` that `dock_move_pin` takes), a command-free label, a clean name and whether it can move either way.
function M.snapshot(items)
    local flags = M.move_flags(items)
    local rows = {}
    for i, it in ipairs(items) do
        if it.pinned and it.pin_pos and #rows < M.MAX_PINS then
            rows[#rows + 1] = { index = i - 1, pin = M.pin_label(it.pinstr), name = M.clean_name(it.name), mvl = flags[i].left, mvr = flags[i].right }
        end
    end
    return rows
end

-- Which item an id names: a 0-based index, or a pin string (exact, else case-insensitive). nil if none / not pinned.
function M.find_item(items, id)
    if type(id) == "number" then
        local it = items[id + 1]
        if it and it.pinned and it.pin_pos then
            return id + 1
        end
        return nil
    end
    local low = tostring(id):lower()
    local found
    for i, it in ipairs(items) do
        if it.pinned and it.pin_pos then
            if it.pinstr == id then
                return i
            end
            if not found and it.pinstr and (it.pinstr:lower() == low or M.pin_label(it.pinstr):lower() == low) then
                found = i
            end
        end
    end
    return found
end

-- Move one visible pin a step. Returns a NEW pin list (the same entries, two swapped), or nil, reason.
-- Entries are never added, removed or rewritten: nothing from the event reaches the file except an existing entry.
function M.plan_move(items, pins, id, dir)
    local k = M.find_item(items, id)
    if not k then
        return nil, "not a pinned item"
    end
    local flags = M.move_flags(items)[k]
    if (dir < 0 and not flags.left) or (dir > 0 and not flags.right) then
        return nil, "at the edge"
    end
    local j = k + dir
    while items[j] and not (items[j].pinned and items[j].pin_pos) do
        j = j + dir
    end
    if not items[j] then
        return nil, "no neighbour"
    end
    local a, b = items[k].pin_pos, items[j].pin_pos
    if pins[a] ~= items[k].pinstr or pins[b] ~= items[j].pinstr then
        return nil, "stale"                  -- the list changed under the dock: build again, ignore the event
    end
    local out = {}
    for i, v in ipairs(pins) do
        out[i] = v
    end
    out[a], out[b] = out[b], out[a]
    return out
end

-- Persist output names, never transient compositor indexes. A missing named/focused output
-- falls back to the focused connected output, then the first connected name.
function M.output_visible(policy, wanted, current, outputs, focused)
    policy = M.index(policy, 0, 2)
    if policy == 0 then return true end
    local connected = {}
    for _, name in ipairs(outputs or {}) do connected[name] = true end
    local fallback = connected[focused] and focused or (outputs or {})[1]
    local chosen = policy == 2 and connected[wanted] and wanted or fallback
    return current == chosen
end

function M.show_ms(v) return ({ 0, 150, 350 })[M.index(v, 0, 2) + 1] end

-- One pending edge reveal, cancelled when the pointer leaves. The host owns the timer
-- and emits the existing reveal event; no background tick is needed.
function M.edge_controller(host)
    local generation = 0
    return {
        enter = function()
            generation = generation + 1
            local serial = generation
            local delay = M.show_ms(host.delay())
            if delay == 0 then host.reveal(); return end
            host.after(delay, function() if generation == serial then host.reveal() end end)
        end,
        leave = function() generation = generation + 1 end,
    }
end

return M
