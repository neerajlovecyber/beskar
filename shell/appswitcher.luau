-- App switcher logic: the windows come from `niri msg -j windows` (most recently used first), their icons from the
-- apps service. Opened by Super+Tab (start.sh appswitcher → the frame picks the monitor with the focus); Tab / arrows
-- move, Enter or a click focuses, Esc closes.

local window_list = {}
local by_key = {}

local function lower(s)
    return string.lower(s or "")
end

sys.watch("apps", function(list)
    by_key = {}
    for _, e in ipairs(list or {}) do
        local id = lower(e.id):gsub("%.desktop$", "")
        by_key[id] = e
        if e.wmclass and e.wmclass ~= "" then
            by_key[lower(e.wmclass)] = e
        end
        local last = id:match("([^%.]+)$")
        if last and not by_key[last] then
            by_key[last] = e
        end
    end
end)

local function icon_for(app_id)
    local k = lower(app_id)
    local e = by_key[k] or by_key[k:match("([^%.]+)$") or k]
    return (e and e.icon) or k
end

local function show_title(idx)
    local w = window_list[(tonumber(idx) or tonumber(fact.sel) or 0) + 1]
    text.sel_title = w and w.title or ""
end
on("fact:sel", function(v) show_title(v) end)

local function focus_secs(w)
    local t = w.focus_timestamp
    if type(t) == "table" then
        return (t.secs or 0) + (t.nanos or 0) / 1e9
    end
    return 0
end

local function refresh_windows()
    run("niri", { "msg", "-j", "windows" }, function(out)
        local ok, all = pcall(json.decode, out or "")
        if not ok or type(all) ~= "table" then
            return
        end
        local wins = {}
        for _, w in ipairs(all) do
            local app = w.app_id or ""
            if app ~= "" and app ~= "pleamar" then
                wins[#wins + 1] = { id = w.id, title = w.title or "", app_id = app, icon = icon_for(app), t = focus_secs(w) }
            end
        end
        table.sort(wins, function(a, b) return a.t > b.t end)      -- most recent first
        while #wins > 7 do
            table.remove(wins)
        end
        window_list = wins
        model.wins = wins
        -- the first press goes to the previous window (the current one is first)
        local first = (#wins > 1) and 1 or 0
        fact.sel = first
        show_title(first)
    end)
end

on("fact:open", function(v)
    if v == true or v == 1 then
        refresh_windows()
    end
end)

on("next_app", function()
    local count = #window_list
    if count > 0 then
        fact.sel = (fact.sel + 1) % count
    end
end)

on("prev_app", function()
    local count = #window_list
    if count > 0 then
        fact.sel = (fact.sel - 1 + count) % count
    end
end)

on("switch_to", function(idx)
    fact.open = false
    local i = tonumber(idx) or fact.sel or 0
    local target = window_list[i + 1]
    if target and target.id then
        run("niri", { "msg", "action", "focus-window", "--id", tostring(target.id) }, nil, { output = false })
    end
end)
