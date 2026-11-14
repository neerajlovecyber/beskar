-- Explicit temporary quiet modes (focus / presentation / game): in memory only, so a restart never leaves the shell silent.
-- Registered before the timer so an unreadable timer file cannot disable them. Notifications reads the facts.
local Quiet = require("quiet_policy")
local policies = Quiet.policies_new()
local function paint_quiet()
    local n = 0
    for _, p in ipairs(Quiet.POLICIES) do if policies[p] then n = n + 1 end end
    fact.quiet_focus, fact.quiet_presentation, fact.quiet_game = policies.focus, policies.presentation, policies.game
    fact.quiet_n = n
    text.quiet_text = Quiet.policy_text(policies)
end
for _, op in ipairs({ "start", "stop", "toggle", "stop_all" }) do
    on("quiet_" .. op, function(name)
        local changed, err = Quiet.policy_apply(policies, op, name)
        text.quiet_error = err or ""
        if changed then paint_quiet() end
    end)
end
paint_quiet()

-- Activities alone writes timer.json. Save transitions, never every displayed second.
local Timer = require("timer_state")
local ok, saved = pcall(sys.ask, "files.read", "timer.json", "json")
local state, problem
if ok then state, problem = Timer.new(saved) else problem = "Could not read the saved timer. Its file has been kept." end
if not state then text.storage_status = problem; return end
local tick, retry, dirty, completion = nil, nil, false, false
local STATES = { idle = 0, running = 1, paused = 2, done = 3 }
local LABELS = { idle = "Ready", running = "Running · sleep counts toward the timer", paused = "Paused", done = "Time’s up" }
local function paint()
    local remaining = Timer.remaining(state, os.time())
    fact.ready = true
    fact.timer_state, fact.timer_remaining = STATES[state.status], remaining
    fact.timer_duration = state.duration
    fact.timer_progress = state.status == "idle" and 0 or 1 - remaining / state.duration
    text.timer_text, text.timer_status = Timer.format(remaining), LABELS[state.status]
end
local function notify() pcall(sys.call, "say", "widgets", "emit timer_changed " .. state.revision) end
local function flush()
    if retry then cancel(retry); retry = nil end
    if not dirty then return end
    local success = pcall(sys.call, "files.write", "timer.json", state)
    if success then
        dirty = false; text.storage_status = ""; notify()
        -- Publish completion only after its terminal state has been persisted.
        if completion and state.status == "done" then completion = false; emit("Topbar.timer_finished") end
    else
        text.storage_status = "Could not save the timer. Retrying…"
        retry = after(2000, flush)
    end
end
local function update(op, value)
    if tick then cancel(tick); tick = nil end
    local changed, finished, err = Timer.apply(state, op, value, os.time())
    if changed then dirty = true; completion = finished; flush() end
    paint()
    if err then text.storage_status = err end
    if state.status == "running" then tick = after(1000, function() tick = nil; update("tick") end) end
end
for _, op in ipairs({ "start", "pause", "resume", "cancel", "dismiss" }) do on(op, function(value) update(op, value) end) end
on("resync", function(revision)
    if dirty then flush() elseif tonumber(revision) ~= state.revision then notify() end
end)
dirty = saved == nil
update("tick")
if dirty then flush() else notify() end
