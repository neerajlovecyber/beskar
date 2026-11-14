-- Bounded, asynchronous filename search. The controller receives rows; only this module schedules fd.
-- Optional scene-local spotlight-files.json: { "roots": ["~/Documents", "~/Downloads"] }.
local M = {}
local LIMIT, DEBOUNCE_MS = 24, 300
local function message(title, detail)
    return { name = title, sub = detail or "", kind = 3, glyph = "󰍉" }
end
local function display(value) return (value:gsub("[%c]", " ")) end

local function roots()
    local home_ok, home = pcall(sys.ask, "env", "HOME")
    if not home_ok or type(home) ~= "string" or home:sub(1, 1) ~= "/" or home:find("%z") then
        return nil, nil, "Your home folder is unavailable"
    end
    home = home:gsub("/+$", "")
    if home == "" then home = "/" end
    local ok, saved = pcall(sys.ask, "files.read", "spotlight-files.json", "json")
    if not ok or (saved ~= nil and type(saved) ~= "table") then return nil, home, "Check spotlight-files.json" end
    local chosen = saved and saved.roots
    if chosen == nil then return { home }, home end
    if type(chosen) ~= "table" or #chosen == 0 or #chosen > 8 then return nil, home, "Choose between one and eight search folders" end
    local result, seen = {}, {}
    for _, path in ipairs(chosen) do
        if type(path) ~= "string" then return nil, home, "Use absolute paths or ~/folder" end
        if path == "~" then path = home
        elseif path:sub(1, 2) == "~/" then path = home:gsub("/$", "") .. path:sub(2) end
        if path:sub(1, 1) ~= "/" or path:find("%z") then return nil, home, "Use absolute paths or ~/folder" end
        path = path:gsub("/+$", "")
        if path == "" then path = "/" end
        if not seen[path] then result[#result + 1], seen[path] = path, true end
    end
    return result, home
end

local function rows_from(output, home)
    local rows, seen = {}, {}
    -- run() preserves NULs: filenames containing spaces or line breaks remain one path.
    for path in (output or ""):gmatch("([^%z]+)%z") do
        local directory = path:sub(-1) == "/"
        local full = path:gsub("/+$", "")
        if full:sub(1, 1) == "/" and full ~= "" and not seen[full] then
            local name, parent = full:match("([^/]+)$"), full:match("^(.*)/[^/]+$")
            if name then
                if parent == "" then parent = "/" end
                if parent == home then parent = "~"
                elseif home ~= "/" and parent:sub(1, #home + 1) == home .. "/" then parent = "~" .. parent:sub(#home + 1) end
                rows[#rows + 1] = { key = "file:" .. full, name = display(name), sub = display(parent),
                    path = full, kind = 6, glyph = directory and "󰉋" or "󰈙" }
                seen[full] = true
            end
        end
        if #rows == LIMIT then break end
    end
    table.sort(rows, function(a, b)
        if a.name:lower() ~= b.name:lower() then return a.name:lower() < b.name:lower() end
        return a.path < b.path
    end)
    return rows
end

function M.new(changed)
    local generation, timer, pending, busy = 0, nil, nil, false
    local current, visible = nil, false
    local start
    start = function()
        if busy or not pending then return end
        local request = pending
        pending = nil
        local selected, home, err = roots()
        if not selected then changed({ message("Could not search these folders", err) }); return end
        local args = { "--signal=TERM", "--kill-after=0.2s", "2s", "fd",
            "--color", "never", "--absolute-path", "--print0", "--fixed-strings", "--ignore-case",
            "--threads", "1", "--max-depth", "8", "--max-results", tostring(LIMIT),
            "--one-file-system", "--type", "file", "--type", "directory" }
        for _, excluded in ipairs({ "node_modules", "target", "build", "__pycache__", ".venv", "venv" }) do
            args[#args + 1], args[#args + 2] = "--exclude", excluded
        end
        if request.term:find("/", 1, true) then args[#args + 1] = "--full-path" end
        args[#args + 1], args[#args + 2] = "--", request.term
        for _, path in ipairs(selected) do args[#args + 1] = path end
        busy = true
        local function finished(output, code)
            busy = false
            if visible and request.generation == generation then
                local rows = rows_from(output, home)
                if code == 0 then
                    if #rows == 0 then rows[1] = message("No matching files or folders", "Try another name") end
                elseif code == 124 or code == 137 then
                    if #rows == LIMIT then table.remove(rows) end
                    rows[#rows + 1] = message(#rows > 0 and "Showing partial results" or "Search took too long", "Try a more specific name")
                elseif code == 126 or code == 127 or code == -1 then
                    rows = { message("File search is unavailable", "Check that fd and timeout are installed") }
                else rows = { message("Could not search these folders", "Check your search folders and fd version") } end
                changed(rows)
            end
            -- At most one fd process runs. A newer debounced query gets the next turn.
            start()
        end
        local launched = pcall(run, "timeout", args, finished)
        if not launched then finished("", -1) end
    end

    return {
        update = function(raw, active)
            local text = (raw or ""):match("^%s*(.-)%s*$")
            local term = text:sub(1, 1) == "/" and text:sub(2):match("^%s*(.-)%s*$") or nil
            if current == term and visible == active then return end
            generation, current, visible = generation + 1, term, active
            pending = nil
            if timer then cancel(timer); timer = nil end
            if not active or term == nil then return end
            if #term < 2 then changed({ message("Find files and folders", "Type at least two characters after /") }); return end
            if #term > 256 or term:find("%z") then changed({ message("Use a shorter filename", "Search names can contain up to 256 bytes") }); return end
            changed({ message("Searching files and folders…", "Hidden files and ignored folders are skipped") })
            local ticket = generation
            timer = after(DEBOUNCE_MS, function()
                timer = nil
                if ticket ~= generation or not visible then return end
                pending = { generation = ticket, term = term }
                start()
            end)
        end,
    }
end

return M
