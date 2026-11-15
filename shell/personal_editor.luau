-- View state only. All content mutations are typed events to Personal.
local text = require("keys_text")     -- the text fields are the Keys scene's (keys_text.luau)
local Hooks = require("topbar_hooks")        -- the frame cannot emit to itself: its own events are called directly
return function(module)
    local Store = require("personal_store")
    local data = { notes = {}, tasks = {} }
    local selected, reload, creating = 0, false, false
    local shown_tasks = {}                 -- ids of the to-dos listed now, in order (the keyboard walks them)
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
        shown_tasks = {}
        for i, t in ipairs(tasks) do shown_tasks[i] = t.id end
        for i, n in ipairs(notes) do if n.selected then fact.pe_note_i = i - 1 end end
        fact.pe_task_i = math.max(0, math.min(tonumber(fact.pe_task_i) or 0, #tasks - 1))
        fact.pe_selected = selected
        text.pe_modified = current and ("Edited " .. current.modified) or ""
        if reload then reload = false; text.pe_draft = current and current.text or "" end
    end
    local function sync()
        local ok, decoded = pcall(json.decode, text["Personal.snapshot"] or "")
        if ok and type(decoded) == "table" then data = decoded; rebuild() end
    end
    on("text:Personal.snapshot", sync)
    local function pick(id) selected, reload = tonumber(id) or 0, true; fact.pe_focus = fact.pe_focus == 2 and 1 or fact.pe_focus; rebuild() end
    on("pe_pick", pick)
    on("pe_new_note", function() creating = #data.notes < Store.MAX_NOTES; emit("Personal.add_note") end)
    on("pe_delete_note", function() emit("Personal.remove_note", selected) end)
    on("pe_undo", function() reload = true; emit("Personal.undo") end)
    on("text:Keys.pe_draft", function()
        if selected > 0 then
            local value = text.pe_draft or ""
            for _, n in ipairs(data.notes) do
                if n.id == selected and n.text ~= value then
                    emit("Personal.edit_note", { id = selected, text = value })
                    fact.pe_focus = 2                   -- typing (even after a click into the field): the keys belong to the editor
                    break
                end
            end
        end
    end)
    on("text:Keys.pe_new_task", function() if (text.pe_new_task or "") ~= "" then fact.pe_focus = 2 end end)
    on("pe_add_task", function()
        local value = text.pe_new_task or ""
        if value:match("%S") and #value <= Store.TASK_BYTES and #data.tasks < Store.MAX_TASKS then
            emit("Personal.add_task", { text = value }); text.pe_new_task = ""
        else emit("Personal.add_task", { text = value }) end
    end)
    local function filter(n) fact.pe_completed = tonumber(n) == 1; fact.pe_task_i = 0; rebuild() end
    on("pe_filter", filter)
    on("pe_up", function(id) emit("Personal.move_task", { id = id, delta = -1 }) end)
    on("pe_down", function(id) emit("Personal.move_task", { id = id, delta = 1 }) end)
    local function pe_open(n)
        n = tonumber(n) or 0
        local screen, output
        if n >= 1000 then
            output = math.floor((n - 1000) / 100)
            n = (n - 1000) % 100
        elseif fact["Panels.open"] == true and tonumber(fact["Panels.cur"]) == 3 then
            screen = tonumber(fact["Panels.open_screen"])
        end
        fact.pe_tab = n == 1 and 1 or 0
        fact.pe_head = fact.pe_tab
        if output then
            Hooks.emit("Topbar.open_personal_output", output)
        elseif screen then
            Hooks.emit("Topbar.open_personal_on", screen)
        elseif fact["Panels.open"] ~= true or tonumber(fact["Panels.cur"]) ~= 25 then Hooks.emit("Topbar.open_personal") end
    end
    on("pe_open", pe_open)
    Hooks.handlers.pe_open = pe_open         -- Today's keyboard (info_panels.luau) cannot emit to its own plugin

    -- ── keyboard (rules in common/personal_editor.plm send pe_nav(code)); zones: 0 header · 1 list · 2 editor or the to-do field ──
    local function zone_focus(z)
        fact.pe_focus = z
        if z ~= 2 then require("topbar_hooks").focus()
        elseif (tonumber(fact.pe_tab) or 0) == 0 then require("topbar_hooks").focus("pe_draft")
        else require("topbar_hooks").focus("pe_new_task") end
    end
    local function has_zone2()
        if not fact["Personal.ready"] then return false end
        return (tonumber(fact.pe_tab) or 0) == 1 or (tonumber(fact.pe_selected) or 0) > 0
    end
    local function step_note(delta)
        local at = (tonumber(fact.pe_note_i) or 0) + 1 + delta
        local n = data.notes[at]
        if n then pick(n.id) end
    end
    local function step_task(delta)
        fact.pe_task_i = math.max(0, math.min((tonumber(fact.pe_task_i) or 0) + delta, #shown_tasks - 1))
    end
    local armed = false                    -- the release of the Enter that opened the panel is not a key for it
    local function activate_header()
        local h = tonumber(fact.pe_head) or 0
        if h <= 1 then pe_open(h)
        elseif h == 2 then if fact["Personal.can_undo"] then reload = true; emit("Personal.undo") end
        else emit("Panels.close") end
    end
    on("pe_nav", function(code)
        if not (fact["Panels.open"] == true and tonumber(fact["Panels.cur"]) == 25) then return end
        code = tonumber(code) or 0
        local z, tab = tonumber(fact.pe_focus) or 1, tonumber(fact.pe_tab) or 0
        if code == 8 then                                                   -- Esc: leave the editor first, then close
            if z == 2 then zone_focus(1) else emit("Panels.close") end
        elseif code == 5 or code == 6 then                                  -- Tab / Shift+Tab
            local nz = (z + (code == 5 and 1 or -1)) % 3
            if nz == 2 and not has_zone2() then nz = (nz + (code == 5 and 1 or -1)) % 3 end
            if nz == 0 then fact.pe_head = tab end
            zone_focus(nz)
        elseif z == 2 then                                                  -- in the editor: the field has the keys
            if tab == 1 and code == 1 then zone_focus(1) end                 -- the to-do field is one line: Up goes back to the list
        elseif z == 0 then                                                  -- header
            local h = tonumber(fact.pe_head) or 0
            if code == 3 then fact.pe_head = math.max(0, h - 1)
            elseif code == 4 then fact.pe_head = math.min(3, h + 1)
            elseif code == 2 then zone_focus(1)
            elseif code == 7 and armed then activate_header() end
        elseif code == 1 then                                               -- list: Up
            local i = tab == 0 and (tonumber(fact.pe_note_i) or 0) or (tonumber(fact.pe_task_i) or 0)
            if i <= 0 then fact.pe_head = tab; zone_focus(0)
            elseif tab == 0 then step_note(-1) else step_task(-1) end
        elseif code == 2 then                                               -- list: Down
            if tab == 0 then step_note(1)
            elseif (tonumber(fact.pe_task_i) or 0) >= #shown_tasks - 1 then zone_focus(2)   -- past the last to-do: the field
            else step_task(1) end
        elseif code == 3 and tab == 1 then filter(0)
        elseif code == 4 and tab == 1 then filter(1)
        elseif code == 4 and tab == 0 then if has_zone2() then zone_focus(2) end
        elseif code == 7 then
            if not armed then return end
            if tab == 1 then
                local id = shown_tasks[(tonumber(fact.pe_task_i) or 0) + 1]
                if id then emit("Personal.toggle_task", id) end
            elseif has_zone2() then zone_focus(2) end
        elseif code == 9 then
            if tab == 0 then if selected > 0 then emit("Personal.remove_note", selected) end
            else
                local id = shown_tasks[(tonumber(fact.pe_task_i) or 0) + 1]
                if id then emit("Personal.remove_task", id) end
            end
        elseif code == 10 and tab == 0 then creating = #data.notes < Store.MAX_NOTES; emit("Personal.add_note")
        elseif code == 11 or code == 12 then
            local id = shown_tasks[(tonumber(fact.pe_task_i) or 0) + 1]
            if tab == 1 and id and not fact.pe_completed then
                local delta = code == 11 and -1 or 1
                emit("Personal.move_task", { id = id, delta = delta })
                step_task(delta)
            end
        end
    end)
    module("personal", function(panel, opened, shown, closed)
        panel.height(536)
        opened(function()
            fact.pe_head = fact.pe_tab; fact.pe_focus = 1; fact.pe_task_i = 0
            armed = false; after(350, function() armed = true end)
            require("topbar_hooks").focus()
            sync()
        end)
        closed(function() emit("Personal.flush") end)
    end)
    after(100, sync)
end
