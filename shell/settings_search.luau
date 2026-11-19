-- Settings-local search navigation. The search index is data, never a second settings owner.
local text = require("keys_text")        -- the text fields are the Keys scene's
return function(actions, choose_tab)
    local catalogue, search = require("settings_catalog"), require("spotlight_search")
    local matches, highlight_job = {}, nil
    local function paint()
        local rows = {}
        for i, row in ipairs(matches) do rows[#rows + 1] = { name = row.name, sub = row.sub, idx = i - 1 } end
        model.setting_matches = rows
    end
    local function clear()
        text.side_q = ""
        fact.settings_search = false
        matches = {}
        model.setting_matches = {}
    end
    local function reveal(id)
        local control = catalogue.find(id)
        if not control then return false end
        clear()
        choose_tab(control.tab)
        if highlight_job then cancel(highlight_job) end
        fact.setting_target = control.reveal
        fact.setting_y, fact.setting_h = control.y, control.h
        -- A serial makes choosing the same result scroll into view again.
        fact.setting_reveal = (tonumber(fact.setting_reveal) or 0) + 1
        highlight_job = after(5000, function() fact.setting_target = 0; highlight_job = nil end)
        return true
    end
    local function update()
        local q = (text.side_q or ""):match("^%s*(.-)%s*$")
        fact.settings_search = q ~= ""
        fact.settings_search_sel = 0
        matches = q ~= "" and search.results("? " .. q, { settings = actions.settings_results }, search.history(), 8) or {}
        paint()
    end
    local function pick(index)
        local row = matches[(tonumber(index) or fact.settings_search_sel or 0) + 1]
        if not row then return end
        if row.setting_id then reveal(row.setting_id)
        else clear(); choose_tab(row.tab); fact.setting_target = 0 end
    end
    on("text:Keys.side_q", update)
    on("settings_search_step", function(delta)
        local step = tonumber(delta) or 1
        if step ~= step or step == math.huge or step == -math.huge then return end
        if #matches > 0 then fact.settings_search_sel = ((tonumber(fact.settings_search_sel) or 0) + math.floor(step)) % #matches end
    end)
    on("settings_search_pick", pick)
    on("settings_search_submit", function() pick(fact.settings_search_sel) end)
    on("settings_search_clear", clear)
    on("reveal_setting", reveal)
    return { reveal = reveal, clear = clear }
end
