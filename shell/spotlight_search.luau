-- Pure search and bounded launch history. No commands, scene globals or persistence here.
local M = {}
local MAX_HISTORY = 100
local function flat(value)
    return type(value) == "string" and value:gsub("[\r\n\t]+", " "):gsub("%s+", " ") or ""
end
local function trim(value) return flat(value):match("^%s*(.-)%s*$") end
local function number(value)
    return type(value) == "number" and value == value and value >= 0 and value < 1e12 and math.floor(value) or 0
end

function M.app_key(app)
    if type(app.id) == "string" and app.id ~= "" then return app.id end
    return type(app.exec) == "string" and app.exec or ""
end

function M.history(saved)
    local history = { version = 1, serial = 0, items = {} }
    if type(saved) ~= "table" or saved.version ~= 1 or type(saved.items) ~= "table" then return history end
    history.serial = number(saved.serial)
    local rows = {}
    for key, value in pairs(saved.items) do
        if type(key) == "string" and #key <= 512 and type(value) == "table" and number(value.count) > 0 then
            rows[#rows + 1] = { key = key, count = math.min(number(value.count), 100000), last = number(value.last) }
        end
    end
    table.sort(rows, function(a, b)
        if a.last ~= b.last then return a.last > b.last end
        return a.key < b.key
    end)
    for i = 1, math.min(#rows, MAX_HISTORY) do
        local row = rows[i]
        history.items[row.key] = { count = row.count, last = row.last }
        history.serial = math.max(history.serial, row.last)
    end
    return history
end

function M.record(history, key)
    if type(key) ~= "string" or key == "" or #key > 512 then return end
    history.serial = history.serial + 1
    local row = history.items[key] or { count = 0 }
    history.items[key] = { count = math.min(row.count + 1, 100000), last = history.serial }
    local count, oldest, oldest_at = 0, nil, math.huge
    for id, item in pairs(history.items) do
        count = count + 1
        if item.last < oldest_at or (item.last == oldest_at and (not oldest or id < oldest)) then
            oldest, oldest_at = id, item.last
        end
    end
    if count > MAX_HISTORY then history.items[oldest] = nil end
end

local function match(query, name, keywords)
    name, keywords = flat(name):lower(), flat(keywords):lower()
    if query == "" then return 100 end
    if name == query then return 1000 end
    if name:sub(1, #query) == query then return 800 end
    if name:find(query, 1, true) then return 600 end
    if keywords:find(query, 1, true) then return 400 end
    local text = name .. " " .. keywords
    for word in query:gmatch("%S+") do
        if not text:find(word, 1, true) then return nil end
    end
    return 300
end

function M.results(raw, sources, history, limit)
    local query = trim(raw):lower()
    local mode = query:sub(1, 1)
    if mode == "@" or mode == "?" or mode == ">" then query = trim(query:sub(2)) else mode = "" end
    local rows, seen, app_icons = {}, {}, {}
    local function add(row, score)
        if score and not seen[row.key] then
            row.score = score
            rows[#rows + 1], seen[row.key] = row, true
        end
    end
    for _, app in ipairs(sources.apps or {}) do
        local id = flat(app.id):lower():gsub("%.desktop$", "")
        if id ~= "" then app_icons[id] = app end
        if app.wmclass and app.wmclass ~= "" then app_icons[flat(app.wmclass):lower()] = app end
        local short = id:match("([^%.]+)$")
        if short and not app_icons[short] then app_icons[short] = app end
        if mode == "" then
            local key = M.app_key(app)
            local usage = history.items[key]
            local score = match(query, app.name, table.concat({ flat(app.local_name), flat(app.id), flat(app.generic_name), flat(app.keywords), flat(app.comment) }, " "))
            if usage and score then
                score = score + math.min(usage.count, 20) + 40 / (1 + math.max(0, history.serial - usage.last))
            end
            if key ~= "" then
                add({ key = "app:" .. key, app_key = key, name = flat(app.name), sub = usage and "Recent app" or "Application", kind = 0, icon = app.icon or "", app = app }, score)
            end
        end
    end
    if mode == "@" or (mode == "" and query ~= "") then
        for _, window in ipairs(sources.windows or {}) do
            local app_id = flat(window.app_id)
            local app = app_icons[app_id:lower()] or app_icons[app_id:lower():match("([^%.]+)$") or ""]
            local title = trim(window.title)
            if title == "" then title = app and app.name or app_id end
            local id = tonumber(window.id)
            if id and id >= 0 and id == math.floor(id) then
                local time = window.focus_timestamp
                local recency = type(time) == "table" and number(time.secs) or 0
                add({ key = "window:" .. id, name = title, sub = "Window · " .. (app and app.name or app_id), kind = 4,
                    icon = app and app.icon or "", glyph = "󰖯", window_id = id, recent = recency }, match(query, title, app_id .. " " .. (app and app.name or "")))
            end
        end
    end
    if mode == "?" or (mode == "" and query ~= "") then
        for _, setting in ipairs(sources.settings or {}) do
            local score = match(query, setting.name, "settings " .. setting.keywords)
            -- Prefer the actionable row when it and its category match equally well.
            if score and setting.id then score = score + 1 end
            add({ key = "settings:" .. (setting.id or setting.tab), name = setting.name, sub = setting.section and ("Settings · " .. setting.section) or "Settings", kind = 5, glyph = setting.icon, tab = setting.tab, setting_id = setting.id },
                score)
        end
    end
    if mode == ">" or (mode == "" and #query >= 3) then
        for i, action in ipairs(sources.commands or {}) do
            add({ key = "action:" .. action.id, name = action.name, sub = "Command", kind = 3, glyph = "󰆍", action = action, order = i },
                match(query, action.name, action.keywords))
        end
    end
    table.sort(rows, function(a, b)
        if a.score ~= b.score then return a.score > b.score end
        if mode == "@" and a.recent ~= b.recent then return a.recent > b.recent end
        if mode == ">" and a.order ~= b.order then return a.order < b.order end
        if mode == "?" and a.tab ~= b.tab then return a.tab < b.tab end
        local an, bn = a.name:lower(), b.name:lower()
        if an ~= bn then return an < bn end
        return a.key < b.key
    end)
    while #rows > (limit or 24) do table.remove(rows) end
    return rows
end

return M
