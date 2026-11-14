-- Settings presents the preview; display-preview.py owns its journal and detached rollback.
-- The timer exists only while a preview is pending. Closing Settings asks to revert immediately.
return function(refresh)
    local token, busy, generation = nil, false, 0
    local function invoke(args, cb)
        run("sh", { "-c", 'd=$(cat "$HOME/.config/beskar/shell-dir" 2>/dev/null) || exit 1; [ -n "$d" ] || exit 1; exec python3 "$d/shell/display-preview.py" "$@"', "display-preview", unpack(args) }, function(out)
            local ok, result = pcall(json.decode, out or "")
            cb(ok and type(result) == "table" and result or { ok = false, message = "Display recovery helper is unavailable" })
        end)
    end
    local function message(result)
        return result.message or result.detail or result.reason or result.state or "Display change failed"
    end
    local function finish(result)
        busy, fact.display_busy = false, false
        local pending = result.ok and result.state == "pending"
        fact.display_pending = pending
        if pending then
            text.display_status = "Keep this display setting? Reverts in " .. math.max(0, math.ceil((result.remaining_ms or 0) / 1000)) .. " seconds"
        else
            text.display_status = not result.ok and message(result) or (result.state == "kept" and "Display setting kept" or (result.state == "reverted" and "Previous display setting restored" or message(result)))
            if result.state ~= "restore-failed" then token = nil end
            refresh()
        end
    end
    local function watch(serial)
        after(1000, function()
            if serial ~= generation or not token or not fact.display_pending then return end
            if busy then watch(serial); return end
            invoke({ "status" }, function(result)
                if serial ~= generation then return end
                finish(result)
                if fact.display_pending then watch(serial) end
            end)
        end)
    end
    local function settle(keep)
        if not token or busy then return end
        generation = generation + 1 -- invalidate an in-flight status answer before settling
        busy, fact.display_busy = true, true
        invoke({ keep and "keep" or "revert", token }, finish)
    end
    on("display_keep", function() settle(true) end)
    on("display_revert", function() settle(false) end)
    on("display_activate", function() settle(fact.display_sel == 1) end)
    on("fact:open", function(value) if value == false and token then settle(false) end end)
    return function(name, kind, requested)
        if busy or token then return end
        busy, fact.display_busy = true, true
        text.display_status = "Starting protected display preview…"
        generation = generation + 1
        local serial = generation
        invoke({ "begin", name, kind, requested, "-" }, function(result)
            if result.ok and result.state == "pending" and type(result.token) == "string" then
                token = result.token
                fact.display_sel = 0
            end
            finish(result)
            if token and fact.open == false then settle(false)
            elseif fact.display_pending then watch(serial) end
        end)
    end
end
