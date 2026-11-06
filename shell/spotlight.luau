-- macOS Spotlight Search Logic
local apps = {}

local function filter()
    local q = (text.query or ""):lower()
    local hits = {}
    for _, a in ipairs(apps) do
        if #hits < 7 and (q == "" or a.name:lower():find(q, 1, true)) then
            hits[#hits + 1] = a
        end
    end
    model.hits = hits
    fact.sel = 0
end

-- Watch the system apps database (.desktop files on Linux)
if not sys.watch("apps", function(list) apps = list; filter() end) then
    model.hits = { { name = "Loading applications..." } }
end

on("text:query", filter)

on("launch", function(i)
    local a = model.hits[i + 1]
    if a then
        log("Spotlight: launching", a.name, "→", a.exec)
        sys.call("apps.launch", a.exec)
    end
    fact.open = false
end)

-- Reset query when closed
on("fact:open", function(open)
    if not open then
        text.query = ""
        filter()
    end
end)
