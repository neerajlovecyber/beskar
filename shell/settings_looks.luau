-- Settings owns applying appearance. This adapter keeps the named-look store and staged import UI together.
return function(P, host)
    local ctl, selected, top, preview, armed = nil, 0, 0, nil, nil
    local rows = {}
    local function current() return host.current() end
    local function status(message) text.look_status = message or "" end
    local function paint()
        if not ctl then return end
        rows = ctl.list()
        local present = false
        for _, r in ipairs(rows) do if r.id == selected then present = true end end
        if not present then selected = rows[1] and rows[1].id or 0 end
        local index = 1
        for i, r in ipairs(rows) do if r.id == selected then index = i end end
        top = math.max(0, math.min(top, math.max(0, #rows - 5)))
        if index <= top then top = index - 1 elseif index > top + 5 then top = index - 5 end
        local visible, matching = {}, ctl.matching(current())
        for i = top + 1, math.min(#rows, top + 5) do
            local r = rows[i]
            visible[#visible + 1] = { id = i, name = r.name, sub = r.summary, sel = r.id == selected, tag = r.pending and "Saving…" or (matching == r.id and "Current" or "") }
        end
        model.look_rows = visible
        fact.look_selected = #rows > 0 and index or 0
        local st = ctl.status()
        fact.look_writable = st.writable == true and st.state ~= "loading"
        fact.look_ready = host.ready()
        fact.look_preview = preview ~= nil
        text.look_range = #rows == 0 and "No saved looks" or ((top + 1) .. "–" .. math.min(top + 5, #rows) .. " of " .. #rows)
    end
    ctl = require("appearance_profiles").new(P, {
        run = function(script, args, cb) run("sh", { "-c", script, "looks-store", unpack(args) }, cb) end,
        decode = json.decode,
        notify = function(st) status(st.message); paint() end,
    })
    local function clear_preview()
        preview = nil; ctl.cancel_import(); fact.look_preview = false
    end
    local function result(r)
        status(r.message or (r.ok and "Saved" or "Could not save")); paint()
    end
    local function mutate(op)
        clear_preview()
        local name = text.look_name or ""
        if op == "delete" or op == "update" then
            local key = op .. ":" .. selected
            if armed ~= key then
                armed = key; status("Press " .. (op == "delete" and "Delete" or "Update") .. " again to confirm")
                after(4000, function() if armed == key then armed = nil; status("") end end)
                return
            end
        end
        armed = nil
        local r
        if op == "save" then r = ctl.save(name, host.facts(), host.palette(), { palette = true })
        elseif op == "rename" then r = ctl.rename(selected, name)
        elseif op == "update" then r = ctl.update(selected, host.facts(), host.palette(), { palette = true })
        else r = ctl.delete(selected) end
        if r.ok and r.id then selected = r.id end
        result(r)
    end
    on("look_open", function()
        fact.look_open = true; clear_preview(); armed = nil
        ctl.open(function() paint() end); paint()
    end)
    on("look_close", function() clear_preview(); fact.look_open = false end)
    on("look_pick", function(id) selected = rows[tonumber(id) or 0] and rows[tonumber(id)].id or 0; armed = nil; paint() end)
    on("look_step", function(delta)
        local index = 1
        for i, r in ipairs(rows) do if r.id == selected then index = i end end
        local d = tonumber(delta) or 0
        if d ~= d then return end
        index = math.max(1, math.min(#rows, index + math.floor(d)))
        selected = rows[index] and rows[index].id or 0; armed = nil; paint()
    end)
    for _, op in ipairs({ "save", "update", "rename", "delete" }) do on("look_" .. op, function() mutate(op) end) end
    local function apply(r)
        if not host.ready() then status("Preferences are unavailable"); return end
        if not r.ok then status(r.message); return end
        if r.noop then status("This appearance is already applied"); return end
        host.apply(r.undo_snapshot, r.snapshot or r.target or { values = r.plan.values, palette = r.plan.restore_palette })
        clear_preview(); status("Appearance applied · Undo is available"); paint()
    end
    on("look_load", function() if host.ready() then apply(ctl.apply_look(selected, current())) end end)
    on("look_preview", function()
        if not host.ready() then status("Preferences are unavailable"); return end
        local r = ctl.preview_import(text.look_document or "", current())
        preview = r.ok and not r.noop and r or nil
        status(r.ok and (r.noop and "This appearance is already applied" or r.message or "Review the changes, then Apply import") or r.message)
        if preview then
            local lines = {}
            for _, change in ipairs(r.plan.changes or {}) do
                lines[#lines + 1] = (change.label or change.id or "Appearance") .. ": " .. tostring(change.from_label or change.from or "") .. " → " .. tostring(change.to_label or change.to or "")
            end
            text.look_changes = table.concat(lines, " · ")
        end
        paint()
    end)
    on("text:look_document", function() clear_preview(); status("") end)
    on("look_apply", function()
        if not preview then return end
        local token = preview.token
        local r = ctl.apply_import(token, current())
        apply(r)
    end)
    on("look_export", function()
        local body = ctl.export(current())
        if not body then status("Could not export appearance"); return end
        text.look_document = body; clear_preview()
        run("sh", { "-c", 'printf "%s" "$1" | wl-copy', "appearance-export", body }, function(_, code)
            status(code == 0 and "Appearance copied · paste into a file to share" or "Select the document field and copy it to share")
        end)
    end)
    on("look_retry", function() ctl.retry(); paint() end)
    return ctl
end
