-- Settings' three existing files: asynchronous reads, coalesced serialized atomic writes.
-- No process/service/timer is created. All filesystem work uses the owner's run adapter.
return function(P, adapter)
    local states, dirty, busy = {}, {}, false
    local notify = adapter.notify or function() end
    local value = adapter.value
    local M = {}
    local flush_waiters = {}
    local function settle_flush()
        if busy then return end
        for _, pending in pairs(dirty) do if pending then return end end
        local problem
        for _, kind in ipairs(P.KINDS) do
            local state = states[kind]
            if not state or not state.writable then problem = "Preferences are unavailable"; break end
            if state.failed then problem = state.error or "Could not save preferences"; break end
        end
        local waiting = flush_waiters
        flush_waiters = {}
        for _, callback in ipairs(waiting) do callback(problem == nil, problem) end
    end
    local read_script = [=[
p="$HOME/.config/$1"
if [ ! -e "$p" ] && [ ! -L "$p" ]; then exit 3; fi
[ -f "$p" ] && [ -r "$p" ] || exit 4
n=$(wc -c < "$p") || exit 4
[ "$n" -le 1048576 ] || exit 4
cat "$p"
]=]
    local write_script = [=[
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
    local function status()
        local errors, pending = {}, busy
        for _, kind in ipairs(P.KINDS) do
            local s = states[kind]
            if s and s.error then errors[#errors + 1] = s.error end
            if dirty[kind] then pending = true end
        end
        notify(#errors > 0 and table.concat(errors, " · ") or (pending and "Saving preferences…" or ""))
    end
    local pump
    pump = function()
        if busy then return end
        local kind
        for _, k in ipairs(P.KINDS) do
            if dirty[k] and states[k] then
                if states[k].writable then kind = k; break else dirty[k] = nil end
            end
        end
        if not kind then status(); settle_flush(); return end
        local s = states[kind]
        local current = value(kind, s.value)
        local encoded = P.encode(kind, current)
        if not encoded then
            s.error, s.failed, dirty[kind] = "Could not encode " .. P.spec(kind).file, true, nil
            status(); pump(); return
        end
        dirty[kind], busy, s.failed = nil, true, false
        status()
        adapter.run(write_script, { P.spec(kind).file, encoded }, function(_, code)
            busy = false
            if code == 0 then s.value, s.error = current, nil
            else s.error = "Could not save " .. P.spec(kind).file .. "; previous file kept" end
            -- Failed saves wait for Retry; no tight retry loop on a full/read-only disk.
            if code ~= 0 then s.failed = true else s.failed = false end
            pump()
        end)
    end
    function M.load(kind, apply)
        adapter.run(read_script, { P.spec(kind).file }, function(out, code)
            local s = P.read(kind, code == 3 and "" or (code == 0 and out or nil), adapter.decode)
            -- An existing empty file is damaged, not a fresh missing preference file.
            if code == 0 and type(out) == "string" and not out:find("%S") then
                s.status, s.writable, s.detail = "corrupt", false, "file is empty"
            end
            s.error = P.describe(s)
            states[kind] = s
            apply(s)
            pump()
        end)
    end
    function M.save(kind)
        local s = states[kind]
        if s and not s.writable then status(); return false end
        dirty[kind] = true
        pump()
        return true
    end
    function M.retry()
        for kind, s in pairs(states) do if s.failed and s.writable then dirty[kind] = true end end
        pump()
    end
    -- A setup owner acknowledgement must mean its writes committed. Wait for the
    -- existing serialized queue without adding a timer or starting another writer.
    function M.flush(callback)
        flush_waiters[#flush_waiters + 1] = callback
        settle_flush()
    end
    function M.ready()
        for _, kind in ipairs(P.KINDS) do if not states[kind] or not states[kind].writable then return false end end
        return true
    end
    function M.state(kind) return states[kind] end
    return M
end
