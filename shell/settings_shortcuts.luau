-- Recursive include discovery and bounded editing of Beskar's own shortcut include.
local text = require("keys_text")        -- the text fields are the Keys scene's
return function(actions, publish)
    local S = require("shortcuts")
    local ctx, cfg, snapshot, busy = nil, nil, nil, false
    local post_save = nil
    local routes, route, accepted = S.routes({ actions = actions }), 1, nil
    local c = {}
    local function status(s) text.shortcut_status = s or "" end
    local function paint_route() text.shortcut_route = routes[route].label end
    local function loaded(result, err)
        busy, fact.shortcut_busy = false, false
        if not result then status(err or "Could not read niri shortcuts"); return end
        snapshot = result
        publish(result.rows or {})
        fact.shortcut_editable = result.complete == true and (result.owned.included or result.can_install_include == true)
        if not result.complete then status("Some included files could not be read. Shortcut editing is unavailable")
        elseif not fact.shortcut_editable then status("Your niri configuration has no reachable Beskar include. Existing bindings remain read-only")
        else status(post_save or "Only Beskar-owned shortcuts can be changed here") end
        post_save = nil
    end
    function c.load()
        if busy then return end
        busy, fact.shortcut_busy = true, true
        if ctx then S.load_async(cfg, ctx, loaded); return end
        run("sh", { "-c", 'printf "%s\\n" "$HOME"; cat "$HOME/.config/beskar/shell-dir" 2>/dev/null' }, function(out)
            local home, repo = tostring(out or ""):match("^([^\n]+)\n([^\n]+)")
            if not home or not repo then loaded(nil, "Beskar install location is unavailable"); return end
            ctx = S.context({ home = home, start_sh = repo .. "/shell/start.sh", actions = actions })
            cfg = {
                adapter = repo .. "/shell/shortcuts_adapter.py",
                run = function(_, args, cb)
                    run("sh", { "-c", 'exec python3 "$@"', "shortcuts", unpack(args) }, cb)
                end,
            }
            S.load_async(cfg, ctx, loaded)
        end)
    end
    on("shortcut_open", function() fact.shortcut_open = true; accepted = nil; c.load(); paint_route() end)
    on("shortcut_close", function() fact.shortcut_open = false; accepted = nil; fact.shortcut_conflict = false end)
    on("shortcut_route_next", function(d)
        route = ((route - 1 + ((tonumber(d) or 0) < 0 and -1 or 1)) % #routes) + 1
        accepted = nil; fact.shortcut_conflict = false; paint_route()
    end)
    on("text:Keys.shortcut_key", function() accepted = nil; fact.shortcut_conflict = false end)
    on("shortcut_save", function()
        if busy or not ctx or not fact.shortcut_editable then return end
        local key = text.shortcut_key or ""
        local r = routes[route]
        local request = { ops = { { op = "set", key = key, route = { kind = r.kind, id = r.id } } }, ensure_include = true }
        if accepted and accepted.key == key and accepted.route == route then request.accept = { key } end
        busy, fact.shortcut_busy = true, true
        S.apply_async(cfg, ctx, request, function(result, err)
            busy, fact.shortcut_busy = false, false
            if not result then status(err or "Shortcut change failed"); return end
            fact.shortcut_conflict = result.status == "conflict"
            if fact.shortcut_conflict then
                accepted = { key = key, route = route }
                local names = {}
                for _, conflict in ipairs(result.conflicts or {}) do
                    local at = conflict.with or {}
                    if #names < 3 then names[#names + 1] = tostring(at.label or "Binding") .. " (" .. tostring(at.path or "niri"):match("([^/]+)$") .. ":" .. tostring(at.line or 0) .. ")" end
                end
                status("Conflict: " .. key .. " already runs " .. table.concat(names, "; ") .. ". Press Override existing binding only to replace this action")
            else
                accepted = nil
                local first_error = result.errors and result.errors[1]
                status(result.message or (first_error and first_error.message) or result.status)
                if result.ok and result.status ~= "applied_reload_failed" then
                    post_save = result.status == "unchanged" and "Shortcut already matches" or "Shortcut saved and niri reloaded"
                    c.load()
                end
            end
        end)
    end)
    paint_route()
    return c
end
