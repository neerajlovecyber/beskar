-- Pure timer state and formatting. Epoch deadlines include sleep and survive process restarts.
local M = { MAX_SECONDS = 86400 }
local states = { idle = true, running = true, paused = true, done = true }
local function integer(v, lo, hi)
    return type(v) == "number" and v == v and v >= lo and v <= hi and v == math.floor(v)
end
function M.new(saved)
    if saved == nil then
        return { version = 1, revision = 0, status = "idle", duration = 1500, remaining = 1500, deadline = 0 }
    end
    if type(saved) ~= "table" or saved.version ~= 1 or not states[saved.status]
        or not integer(saved.revision, 0, 1e12) or not integer(saved.duration, 1, M.MAX_SECONDS)
        or not integer(saved.remaining, 0, saved.duration) or not integer(saved.deadline, 0, 1e12)
        or (saved.status == "running" and saved.deadline == 0)
        or (saved.status ~= "running" and saved.deadline ~= 0)
        or (saved.status == "paused" and saved.remaining == 0)
        or (saved.status == "done" and saved.remaining ~= 0) then
        return nil, "Could not read the saved timer. Its file has been kept."
    end
    local copy = {}
    for _, k in ipairs({ "version", "revision", "status", "duration", "remaining", "deadline" }) do copy[k] = saved[k] end
    return copy
end
function M.remaining(s, now)
    if s.status == "running" then return math.max(0, math.min(s.duration, math.ceil(s.deadline - now))) end
    return s.remaining
end
function M.format(seconds)
    seconds = math.max(0, math.ceil(seconds))
    if seconds >= 3600 then return string.format("%d:%02d:%02d", math.floor(seconds / 3600), math.floor(seconds / 60) % 60, seconds % 60) end
    return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end
-- Bare numbers mean minutes; explicit h/m/s and mm:ss are also accepted.
function M.parse(value)
    if type(value) ~= "string" or #value > 40 then return nil end
    local raw = value:lower():gsub("%s+", "")
    local seconds
    if raw:match("^%d+$") then seconds = tonumber(raw) * 60
    else
        local minutes, secs = raw:match("^(%d+):(%d%d)$")
        if minutes and tonumber(secs) < 60 then seconds = tonumber(minutes) * 60 + tonumber(secs) end
        if not seconds then
            local rest, total, previous = raw, 0, 4
            while rest ~= "" do
                local number, unit, tail = rest:match("^(%d+)([hms])(.*)$")
                local rank = unit and ({ h = 3, m = 2, s = 1 })[unit]
                if not number or rank >= previous then
                    -- Preserve Spotlight's existing 1h30 spelling.
                    if previous == 3 and rest:match("^%d+$") then total = total + tonumber(rest) * 60; rest = ""; break end
                    return nil
                end
                previous, rest = rank, tail
                total = total + tonumber(number) * ({ h = 3600, m = 60, s = 1 })[unit]
            end
            seconds = total
        end
    end
    if integer(seconds, 1, M.MAX_SECONDS) then return seconds, M.format(seconds) end
end
function M.apply(s, op, value, now)
    local finished = false
    -- A click after the deadline observes completion before it can pause the timer.
    if s.status == "running" and M.remaining(s, now) == 0 then
        s.status, s.remaining, s.deadline = "done", 0, 0
        finished = true
    end
    local changed = finished
    if op == "start" then
        local duration = tonumber(value)
        if not integer(duration, 1, M.MAX_SECONDS) then
            if changed then s.revision = s.revision + 1 end
            return changed, finished, "Choose a duration from 1 second to 24 hours."
        end
        s.duration, s.remaining, s.deadline, s.status = duration, duration, now + duration, "running"
        changed, finished = true, false
    elseif op == "pause" and s.status == "running" then
        s.remaining = M.remaining(s, now)
        s.status, s.deadline, changed = "paused", 0, true
    elseif op == "resume" and s.status == "paused" then
        s.deadline, s.status, changed = now + s.remaining, "running", true
    elseif op == "cancel" and s.status ~= "idle" then
        s.status, s.deadline, s.remaining, changed, finished = "idle", 0, s.duration, true, false
    elseif op == "dismiss" and s.status == "done" then
        s.status, s.remaining, changed, finished = "idle", s.duration, true, false
    end
    if changed then s.revision = s.revision + 1 end
    return changed, finished
end
return M
