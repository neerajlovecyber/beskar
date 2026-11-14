-- Topbar's portable-pin owner adapter. Requests are FIFO, so a timed-out write
-- cannot execute after its forced rollback. Acknowledgement means committed storage.
local M = {}
function M.new(host)
    local SP = host.profiles or require("setup_profiles")
    local queue, active, last, cache = {}, nil, {}, {}
    local function pins()
        local raw = host.current()
        return SP.snapshot("pins", { list = raw }, { local_pins = true })
    end
    local function reply(request, info)
        info.request, info.owner, info.section = request, "topbar", "pins"
        host.reply(info)
    end
    local pump
    pump = function()
        if active or #queue == 0 then return end
        local r = table.remove(queue, 1)
        active = r.request
        local function done(info)
            active = nil
            cache[r.request] = info
            last[#last + 1] = r.request
            if #last > 32 then cache[table.remove(last, 1)] = nil end
            reply(r.request, info)
            pump()
        end
        if not host.ready() or host.busy() then done({ok=false,untouched=true,code="busy",message="The dock is still loading or saving"}); return end
        local current = pins()
        if not current then done({ok=false,untouched=true,code="unrepresentable",message="The current pins cannot be captured losslessly"}); return end
        local fp = SP.fingerprint("pins", current)
        if not r.force and fp ~= r.expect then done({ok=false,untouched=true,code="stale",fp=fp}); return end
        local data, errors = SP.validate_section("pins", r.data, { local_pins = true })
        if not data then done({ok=false,untouched=true,code="invalid",message=errors and errors[1] and errors[1].message}); return end
        -- Portable imports cannot add an executable window pin. Existing local pins
        -- may survive import; forced rollback may restore a trusted local journal.
        local known = {}
        for _, id in ipairs(current.list or {}) do known[id] = true end
        if not r.force then
            for _, id in ipairs(data.list or {}) do
                if id:find("|", 1, true) and not known[id] then done({ok=false,untouched=true,code="not_portable"}); return end
            end
        end
        host.commit(data, function(ok, code, message)
            if not ok then done({ok=false,untouched=true,code=code or "io",message=message}); return end
            host.set(data.default and nil or data.list)
            done({ok=true,fp=SP.fingerprint("pins", data)})
        end)
    end
    local c = {}
    function c.apply(r)
        if type(r) ~= "table" or type(r.request) ~= "string" or #r.request > 160 or r.request == "" then return false end
        if r.force ~= nil and type(r.force) ~= "boolean" then return false end
        if active == r.request then return true end
        if cache[r.request] then reply(r.request, cache[r.request]); return true end
        for _, item in ipairs(queue) do if item.request == r.request then return true end end
        if #queue >= 16 then reply(r.request,{ok=false,untouched=true,code="busy"}); return false end
        queue[#queue + 1] = r
        pump()
        return true
    end
    function c.snapshot(request)
        local data = host.ready() and not host.busy() and pins() or nil
        host.snapshot({request=request,owner="topbar",section="pins",ready=data~=nil,data=data,fp=data and SP.fingerprint("pins",data) or nil})
    end
    return c
end
return M
