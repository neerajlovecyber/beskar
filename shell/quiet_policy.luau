-- Pure quiet-delivery policy. No services, files, timers or scene state: callers pass facts in and apply the result.
--
--   effective quiet = manual Do Not Disturb  OR  an explicit temporary policy (focus / presentation / game)
--                     OR  quiet hours (a saved daily window)
--
-- Nothing here writes the manual choice, so a policy ending can never undo a change the user made meanwhile.
-- Per-app rules are keyed by the notification's `app` string (the D-Bus app_name: the only identity the service gives).
local M = { MAX_RULES = 24, MAX_APPS = 32, MAX_APP_LEN = 120, VERSION = 1 }

M.POLICIES = { "focus", "presentation", "game" }
local POLICY_LABEL = { focus = "Focus", presentation = "Presentation", game = "Game" }
local REASON_LABEL = { manual = "Do Not Disturb", focus = "Focus", presentation = "Presentation", game = "Game", hours = "Quiet hours" }
local REASON_SHORT = { manual = "DND", focus = "Focus", presentation = "Presenting", game = "Game", hours = "Quiet hours" }
local REASON_ORDER = { "manual", "focus", "presentation", "game", "hours" }

-- ── temporary policies (owned by Activities) ─────────────────────

function M.policies_new()
    return { focus = false, presentation = false, game = false }
end

-- op: "start" | "stop" | "toggle" | "stop_all" (name ignored). Returns changed, err.
function M.policy_apply(state, op, name)
    if op == "stop_all" then
        local changed = false
        for _, p in ipairs(M.POLICIES) do
            if state[p] then state[p] = false; changed = true end
        end
        return changed
    end
    if op ~= "start" and op ~= "stop" and op ~= "toggle" then return false, "Unknown quiet operation." end
    if type(name) ~= "string" or POLICY_LABEL[name:lower()] == nil then
        return false, "Unknown quiet mode. Use focus, presentation or game."
    end
    name = name:lower()
    local want
    if op == "toggle" then want = not state[name] else want = (op == "start") end
    if state[name] == want then return false end
    state[name] = want
    return true
end

function M.policy_list(state)
    local out = {}
    for _, p in ipairs(M.POLICIES) do
        if state[p] then out[#out + 1] = POLICY_LABEL[p] end
    end
    return out
end

function M.policy_text(state)
    return table.concat(M.policy_list(state), " · ")
end

-- ── quiet hours (saved by Settings, evaluated here) ──────────────

function M.valid_minute(v)
    return type(v) == "number" and v == v and v >= 0 and v <= 1439 and v == math.floor(v)
end

-- Normalise Settings' three values. Anything invalid means "no window".
function M.hours_from(enabled, start, stop)
    if enabled ~= true or not M.valid_minute(start) or not M.valid_minute(stop) then
        return { enabled = false, start = 0, stop = 0 }
    end
    return { enabled = true, start = start, stop = stop }
end

-- [start, stop): a window that ends earlier than it starts crosses midnight; equal times are an empty window.
function M.hours_active(h, minute)
    if type(h) ~= "table" or h.enabled ~= true or not M.valid_minute(minute) then return false end
    if h.start == h.stop then return false end
    if h.start < h.stop then return minute >= h.start and minute < h.stop end
    return minute >= h.start or minute < h.stop
end

function M.minute_of(t)
    return t.hour * 60 + t.min
end

-- ── effective state ───────────────────────────────────────────────

-- input = { manual = bool, policies = {focus,presentation,game}, hours = {enabled,start,stop}, minute = 0..1439 }
function M.effective(input)
    local active = {
        manual = input.manual == true,
        focus = input.policies and input.policies.focus == true,
        presentation = input.policies and input.policies.presentation == true,
        game = input.policies and input.policies.game == true,
        hours = M.hours_active(input.hours, input.minute),
    }
    local reasons, long, short = {}, {}, {}
    for _, r in ipairs(REASON_ORDER) do
        if active[r] then
            reasons[#reasons + 1] = r
            long[#long + 1] = REASON_LABEL[r]
            short[#short + 1] = REASON_SHORT[r]
        end
    end
    local quiet = #reasons > 0
    local compact = quiet and (short[1] .. (#short > 1 and (" +" .. (#short - 1)) or "")) or ""
    return { quiet = quiet, reasons = reasons, label = table.concat(long, " · "), short = compact }
end

-- ── per-app rules (saved by Notifications) ────────────────────────
-- Modes: "normal" (default, no rule), "no_banner" (never a banner, still counted and listed), "muted" (no banner and not
-- counted on the bell: held quietly in the centre and history).

M.MODE_CODE = { normal = 0, no_banner = 1, muted = 2 }
local MODE_NAME = { [0] = "normal", [1] = "no_banner", [2] = "muted" }

function M.mode_from(v)
    if type(v) == "string" and M.MODE_CODE[v] ~= nil then return v end
    if type(v) == "number" and MODE_NAME[v] ~= nil then return MODE_NAME[v] end
    return nil
end

-- A name is kept exactly (after trimming); an over-long or control-character name is rejected, never truncated.
function M.normalize_app(name)
    if type(name) ~= "string" then return nil end
    name = name:gsub("^%s+", ""):gsub("%s+$", "")
    if name == "" or #name > M.MAX_APP_LEN or name:find("%c") then return nil end
    return name
end

local BAD_SAVED = "Could not read the saved quiet rules. The file has been kept."

-- saved == nil is a first run. Anything malformed is refused whole: nil, message.
function M.rules_new(saved)
    if saved == nil then return { version = M.VERSION, apps = {} } end
    if type(saved) ~= "table" or saved.version ~= M.VERSION or type(saved.apps) ~= "table" then return nil, BAD_SAVED end
    local rules, seen, n = { version = M.VERSION, apps = {} }, {}, 0
    for _, e in ipairs(saved.apps) do
        n = n + 1
        local app = type(e) == "table" and M.normalize_app(e.app) or nil
        local mode = type(e) == "table" and M.mode_from(e.mode) or nil
        if n > M.MAX_RULES or app == nil or app ~= e.app or mode == nil or mode == "normal" or seen[app] then return nil, BAD_SAVED end
        seen[app] = true
        rules.apps[n] = { app = app, mode = mode }
    end
    return rules
end

-- Returns changed, err. mode "normal" removes the rule.
function M.rule_set(rules, app, mode)
    local name = M.normalize_app(app)
    if not name then return false, "That application name cannot be used for a quiet rule." end
    local m = M.mode_from(mode)
    if not m then return false, "Unknown quiet rule. Use normal, no_banner or muted." end
    for i, e in ipairs(rules.apps) do
        if e.app == name then
            if m == "normal" then table.remove(rules.apps, i); return true end
            if e.mode == m then return false end
            e.mode = m
            return true
        end
    end
    if m == "normal" then return false end
    if #rules.apps >= M.MAX_RULES then return false, "Too many quiet rules. Remove one first." end
    rules.apps[#rules.apps + 1] = { app = name, mode = m }
    return true
end

-- normal → no_banner → muted → normal
function M.rule_cycle(rules, app)
    local current = M.rule_mode(M.rule_map(rules), M.normalize_app(app) or "")
    local nextmode = ({ normal = "no_banner", no_banner = "muted", muted = "normal" })[current]
    return M.rule_set(rules, app, nextmode)
end

function M.rules_clear(rules)
    local changed = #rules.apps > 0
    rules.apps = {}
    return changed
end

function M.rule_map(rules)
    local map = {}
    for _, e in ipairs(rules.apps) do map[e.app] = e.mode end
    return map
end

function M.rule_mode(map, app)
    return map[app] or "normal"
end

-- A copy safe to hand to the files service.
function M.snapshot(rules)
    local out = { version = M.VERSION, apps = {} }
    for i, e in ipairs(rules.apps) do out.apps[i] = { app = e.app, mode = e.mode } end
    return out
end

-- What one arriving notification gets: a banner? does it count on the bell?
function M.treatment(quiet, mode)
    return { banner = (not quiet) and mode == "normal", counted = mode ~= "muted" }
end

-- The list Settings shows: rules first (A–Z), then recent senders with no rule (given newest first), at most `cap`.
function M.app_list(rules, recent, cap)
    cap = cap or M.MAX_APPS
    local out, have = {}, {}
    local sorted = {}
    for i, e in ipairs(rules.apps) do sorted[i] = e end
    table.sort(sorted, function(a, b)
        local x, y = a.app:lower(), b.app:lower()
        if x ~= y then return x < y end
        return a.app < b.app
    end)
    for _, e in ipairs(sorted) do
        if #out < cap then out[#out + 1] = { app = e.app, mode = M.MODE_CODE[e.mode], rule = true }; have[e.app] = true end
    end
    for _, name in ipairs(recent or {}) do
        local app = M.normalize_app(name)
        if app and not have[app] and #out < cap then
            out[#out + 1] = { app = app, mode = 0, rule = false }
            have[app] = true
        end
    end
    return out
end

return M
