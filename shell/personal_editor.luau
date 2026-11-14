-- View state only. All content mutations are typed events to Personal.
local Hooks = require("topbar_hooks")        -- the frame cannot emit to itself: its own events are called directly
return function(module)
    local Store = require("personal_store")
    local data = { notes = {}, tasks = {} }
    local selected, reload, creating = 0, false, false
    local function rebuild()
        local notes, tasks, today, current = {}, {}, {}, nil
        for _, n in ipairs(data.notes) do if n.id == selected then current = n end end
        if creating or not current then
            current = data.notes[1]; selected = current and current.id or 0
            reload, creating = true, false
        end
        for _, n in ipairs(data.notes) do notes[#notes + 1] = { id = n.id, title = Store.title(n.text), selected = n.id == selected } end
        for _, t in ipairs(data.tasks) do
            if not t.done and #today < 2 then today[#today + 1] = { id = t.id, title = t.text } end
            if t.done == (fact.pe_completed == true) then tasks[#tasks + 1] = { id = t.id, title = t.text, done = t.done } end
        end
        model.pe_notes, model.pe_tasks, model.pe_today_tasks = notes, tasks, today
        fact.pe_selected = selected
        text.pe_modified = current and ("Edited " .. current.modified) or ""
        if reload then reload = false; text.pe_draft = current and current.text or "" end
    end
    local function sync()
        local ok, decoded = pcall(json.decode, text["Personal.snapshot"] or "")
        if ok and type(decoded) == "table" then data = decoded; rebuild() end
    end
    on("text:Personal.snapshot", sync)
    on("pe_pick", function(id) selected, reload = tonumber(id) or 0, true; rebuild() end)
    on("pe_new_note", function() creating = #data.notes < Store.MAX_NOTES; emit("Personal.add_note") end)
    on("pe_delete_note", function() emit("Personal.remove_note", selected) end)
    on("pe_undo", function() reload = true; emit("Personal.undo") end)
    on("text:pe_draft", function()
        if selected > 0 then
            local value = text.pe_draft or ""
            for _, n in ipairs(data.notes) do
                if n.id == selected and n.text ~= value then emit("Personal.edit_note", { id = selected, text = value }); break end
            end
        end
    end)
    on("pe_add_task", function()
        local value = text.pe_new_task or ""
        if value:match("%S") and #value <= Store.TASK_BYTES and #data.tasks < Store.MAX_TASKS then
            emit("Personal.add_task", { text = value }); text.pe_new_task = ""
        else emit("Personal.add_task", { text = value }) end
    end)
    on("pe_filter", function(n) fact.pe_completed = tonumber(n) == 1; rebuild() end)
    on("pe_up", function(id) emit("Personal.move_task", { id = id, delta = -1 }) end)
    on("pe_down", function(id) emit("Personal.move_task", { id = id, delta = 1 }) end)
    on("pe_open", function(n)
        n = tonumber(n) or 0
        local screen, output
        if n >= 1000 then
            output = math.floor((n - 1000) / 100)
            n = (n - 1000) % 100
        elseif fact["Panels.open"] == true and tonumber(fact["Panels.cur"]) == 3 then
            screen = tonumber(fact["Panels.open_screen"])
        end
        fact.pe_tab = n == 1 and 1 or 0
        if output then
            Hooks.emit("Topbar.open_personal_output", output)
        elseif screen then
            Hooks.emit("Topbar.open_personal_on", screen)
        elseif fact["Panels.open"] ~= true or tonumber(fact["Panels.cur"]) ~= 25 then Hooks.emit("Topbar.open_personal") end
    end)
    module("personal", function(panel, opened, shown, closed)
        panel.height(536)
        opened(sync)
        closed(function() emit("Personal.flush") end)
    end)
    after(100, sync)
end
