-- Run from the repository root: lua tests/spotlight.lua
package.path = "shell/?.luau;" .. package.path
local search = require("spotlight_search")
local actions = require("actions")
local panels = require("panels_data")
local passed = 0
local function check(condition, message)
    assert(condition, message)
    passed = passed + 1
end
local function contains(rows, predicate)
    for _, row in ipairs(rows) do if predicate(row) then return row end end
end

local apps = {
    { id = "alpha", name = "Alpha", exec = "alpha", icon = "alpha", keywords = "writing editor" },
    { id = "beta", name = "Beta", exec = "beta", icon = "beta" },
    { id = "org.example.Browser", name = "Browser", exec = "browser", wmclass = "browser", icon = "browser", generic_name = "Web browser" },
}
local sources = { apps = apps, settings = actions.settings, commands = actions.commands, windows = {
    { id = 10, title = "Research document", app_id = "browser", focus_timestamp = { secs = 100 } },
    { id = 11, title = "Code review", app_id = "browser", focus_timestamp = { secs = 200 } },
} }
local history = search.history()
check(search.results("writing editor", sources, history)[1].app_key == "alpha", "Match desktop-file keywords")
check(search.results("? volume", sources, history)[1].tab == 2, "Route a Settings keyword to Sound")
check(search.results("research", sources, history)[1].window_id == 10, "Search windows without a prefix")
check(search.results("@", sources, history)[1].window_id == 11, "Order windows by recent focus")
check(search.results("@ browser", sources, history)[1].icon == "browser", "Map a window's WM class to its app icon")
check(#search.results("? nonexistent", sources, history) == 0, "Do not leak other providers into Settings mode")
check(#search.results("> nonexistent", sources, history) == 0, "Do not leak other providers into command mode")
check(#search.results("", sources, history) == 3, "Empty search lists apps, without unrelated commands")
check(#search.results("", sources, history, 2) == 2, "Bound result count")
check(#search.results("", sources, history, 0) == 0, "Respect exhausted capacity after a special result")
for _ = 1, 60 do search.record(history, "beta") end
check(search.results("", sources, history)[1].app_key == "beta", "Promote frequently launched apps")
check(search.results("Alpha", sources, history)[1].app_key == "alpha", "History must not outrank an exact match")
search.record(history, "alpha")
check(search.results("", sources, search.history(history))[1].app_key == "alpha", "Restore recent ranking from saved data")
for i = 1, 140 do search.record(history, "app-" .. i) end
local count = 0
for _ in pairs(history.items) do count = count + 1 end
check(count == 100 and history.items["app-140"] ~= nil and history.items.beta == nil, "Bound persisted history and evict the oldest")
local restored = search.history({ version = 1, serial = "bad", items = { broken = false, valid = { count = 2, last = 7 }, nan = { count = 0/0 } } })
check(restored.serial == 7 and restored.items.valid ~= nil and restored.items.nan == nil, "Recover valid entries from malformed history")
check(next(search.history({ version = 2, items = {} }).items) == nil, "Reject unknown history versions")

local ids = {}
for name, panel in pairs(panels.panels) do
    check(not ids[panel.id], "Unique panel ID: " .. name)
    ids[panel.id] = true
    if panel.slot then check(panels.focus[panel.slot] == name, "Stable CLI route: " .. name) end
end
check(not panels.known[7] and panels.known[4], "Banners must not become regular panels")
for _, command in ipairs(actions.commands) do
    if command.event == "Topbar.open_panel" then check(panels.focus[command.value] ~= nil, "Action opens a registered panel") end
end

-- Exercise the actual Spotlight controller with isolated service/command adapters.
-- Nothing launches, focuses a real window, writes a user file, or changes the clipboard.
local function controller(disk)
    local state = { visible = false, handlers = {}, watchers = {}, jobs = {}, requests = {}, file_requests = {}, commands = {}, events = {}, disk = disk or {}, timers = {} }
    fact, text, model = { sp_sel = 0, sc_t = 0 }, { query = "" }, {}
    function on(name, fn) state.handlers[name] = fn end
    function after(_, fn)
        local job = { fn = fn }
        state.jobs[#state.jobs + 1] = job
        return job
    end
    function cancel(job) job.canceled = true end
    function every(_, fn) state.timers[#state.timers + 1] = fn end
    function emit(name, value) state.events[#state.events + 1] = { name, value } end
    function log() end
    function run(command, args, callback)
        state.commands[#state.commands + 1] = { command = command, args = args }
        if command == "niri" and args[3] == "windows" then
            state.requests[#state.requests + 1] = callback
        elseif command == "timeout" then
            state.file_requests[#state.file_requests + 1] = { args = args, reply = callback }
        elseif callback then
            local code = command == "xdg-open" and (state.open_error or 0) or (state.focus_error and 1 or 0)
            callback("", code)
        end
    end
    json = { decode = function(value) return value end }
    sys = {
        ask = function(what, name)
            if what == "env" then return "/home/test" end
            return state.disk[name]
        end,
        call = function(name, arg, value)
            if name == "files.write" then state.disk[arg] = search.history(value)
            elseif name == "apps.launch" then
                if state.launch_error then error("Launch refused") end
                state.launched = arg
            end
        end,
        watch = function(name, fn) state.watchers[name] = fn; fn(apps); return true end,
    }
    package.loaded.topbar_hooks = { emit = function(name, value) emit(name, value) end, call = function() end, handlers = {} }
    -- dock_panels.luau returns a function taking the frame's panel client
    dofile("shell/dock_panels.luau")(function(name, init)
        if name ~= "spotlight" then return end
        init({ height = function(h) state.height = h end },
            function(fn) state.open_hook = fn end,
            function() return state.visible end,
            function(fn) state.close_hook = fn end)
    end)
    function state.open() state.visible = true; state.open_hook() end
    function state.close() state.visible = false; state.close_hook() end
    function state.query(value) text.query = value; state.handlers["text:query"]() end
    function state.flush()
        local jobs = state.jobs
        state.jobs = {}
        for _, job in ipairs(jobs) do if not job.canceled then job.fn() end end
    end
    function state.reply(index, windows) state.requests[index](windows, 0) end
    return state
end

local c = controller()
for _, tick in ipairs(c.timers) do tick() end
check(#c.requests == 0, "Do not poll windows while closed")
c.open()
c.query("@ research")
c.reply(1, sources.windows)
check(model.hits[1].name == "Research document", "Refresh windows against the current query")
c.query("@ code")
check(model.hits[1].name == "Code review", "Typing searches the refreshed window snapshot")
c.handlers.launch(0)
c.close()
c.flush()
local focused = c.commands[#c.commands]
check(focused.command == "niri" and focused.args[5] == "11", "Enter focuses the chosen window ID")

c.open()
c.close()
c.open()
c.query("@")
c.reply(2, sources.windows)
check(model.hits[1].name == "No matching windows", "Ignore a late reply from a previous opening")
c.reply(3, { sources.windows[1] })
check(model.hits[1].name == "Research document", "A new opening can query before an old reply arrives")
c.query("? volume")
c.handlers.launch(0)
c.close()
c.flush()
check(c.events[#c.events - 1][1] == "Settings.set_tab" and c.events[#c.events - 1][2] == 2, "Select the Settings tab through its owner")
check(c.events[#c.events][1] == "Topbar.open_panel" and c.events[#c.events][2] == panels.slots.settings, "Open Settings through the frame")

c.open()
c.query("Beta")
c.handlers.launch(0)
c.close()
c.flush()
check(c.launched == "beta" and c.disk["spotlight-history.json"].items.beta.count == 1, "Save accepted app launches")
local disk = c.disk
c = controller(disk)
check(model.hits[1].name == "Beta", "Restore app ranking after controller restart")
c.open()
c.query("Alpha")
c.launch_error = true
c.handlers.launch(0)
c.close()
c.flush()
check(disk["spotlight-history.json"].items.alpha == nil, "Do not record rejected launches")

c.open()
c.query("12*(3+4)")
check(model.hits[1].name == "= 84", "Preserve calculator precedence")
c.query("yt lo fi")
check(model.hits[1].site == 2 and model.hits[1].kind == 2, "Preserve web prefixes")
c.query("timer 25m")
c.handlers.launch(0)
c.close()
c.flush()
check(c.events[#c.events][1] == "Activities.start" and c.events[#c.events][2] == 1500, "Preserve custom countdowns")
for query, event in pairs({ ["> timer"] = "Topbar.open_timer", ["> pause timer"] = "Activities.pause", ["> resume timer"] = "Activities.resume", ["> cancel timer"] = "Activities.cancel" }) do
    c.open()
    c.query(query)
    c.handlers.launch(0)
    c.close()
    c.flush()
    check(c.events[#c.events][1] == event, "Timer command routing: " .. query)
end
c.open()
c.query("> logout")
c.handlers.launch(0)
c.close()
c.flush()
check(c.events[#c.events - 1][1] == "Topbar.set_kind" and c.events[#c.events - 1][2] == 2, "Keep logout as a confirmation dialog")
c.open()
c.query("> session")
c.handlers.launch(0)
c.close()
c.flush()
check(c.events[#c.events][1] == "Topbar.open_session", "Session command opens the shared keyboard chooser")
c.open()
c.query("a query with no matches")
check(model.hits[1].kind == 2, "Preserve web fallback in ordinary search")
c.query("? no matching settings")
local event_count = #c.events
c.handlers.launch(0)
check(#c.events == event_count and not model.hits[1].actionable, "An empty explicit mode must not execute anything")

c = controller()
c.open()
c.query("/")
c.flush()
check(#c.file_requests == 0 and not model.hits[1].actionable, "Bare file mode must not scan the home directory")
c.query("/r")
c.flush()
check(#c.file_requests == 0, "Require a useful filename before searching")
c.query("/report")
check(#c.file_requests == 0 and not model.hits[1].actionable, "Debounce a file query and clear stale actions")
c.query("/report final")
c.flush()
check(#c.file_requests == 1, "Run only the latest query after a burst of typing")
local request = c.file_requests[1]
local args = request.args
local separator
for i, value in ipairs(args) do if value == "--" then separator = i end end
check(args[4] == "fd" and args[separator + 1] == "report final" and args[separator + 2] == "/home/test", "Pass the query and home as literal arguments")
check(contains(args, function(value) return value == "--fixed-strings" end) and contains(args, function(value) return value == "--print0" end), "Use literal matching with NUL-separated paths")
request.reply("/home/test/Documents/report final.txt\0/home/test/Work/report final.txt\0/home/test/report final folder/\0", 0)
check(#model.hits == 3 and model.hits[1].kind == 6, "Show file and directory results in the existing list")
check(model.hits[2].sub == "~/Documents" and model.hits[3].sub == "~/Work", "Distinguish equal filenames with their parent folder")

c.query("/older")
c.flush()
c.query("/newer")
c.flush()
check(#c.file_requests == 2, "Keep at most one file search process in flight")
c.file_requests[2].reply("/home/test/older.txt\0", 0)
check(#c.file_requests == 3 and model.hits[1].name ~= "older.txt", "Discard stale paths and run the latest debounced query next")
c.file_requests[3].reply("/home/test/newer.txt\0", 0)
check(model.hits[1].name == "newer.txt", "Publish the newest file query")

c.query("/late")
c.flush()
c.query("? volume")
c.file_requests[4].reply("/home/test/late.txt\0", 0)
check(model.hits[1].name == "Sound", "A late file reply must not overwrite another mode")
c.query("/closed")
c.flush()
c.close()
c.open()
c.query("/reopened")
c.flush()
c.file_requests[5].reply("/home/test/closed.txt\0", 0)
check(#c.file_requests == 6 and model.hits[1].name ~= "closed.txt", "Ignore file replies across close/reopen")
c.file_requests[6].reply("/home/test/reopened.txt\0", 0)
check(model.hits[1].name == "reopened.txt", "Resume file search after reopening")

c.query("/literal")
c.flush()
local literal = "/home/test/Documents/literal ' $() [x]\nsecond line.txt"
c.file_requests[7].reply(literal .. "\0", 0)
check(#model.hits == 1 and not model.hits[1].name:find("\n", 1, true), "Display control characters safely without splitting a filename")
c.handlers.launch(0)
c.close()
c.flush()
check(c.commands[#c.commands].command == "xdg-open" and c.commands[#c.commands].args[1] == literal, "Open the exact filename as one argument, preserving spaces and shell characters")
check(c.disk["spotlight-history.json"] == nil, "Never put file queries or paths into app history")

c.open()
c.query("/none")
c.flush()
c.file_requests[8].reply("", 0)
check(model.hits[1].name == "No matching files or folders" and not model.hits[1].actionable, "An empty file search never becomes a web search")
c.query("/slow")
c.flush()
c.file_requests[9].reply("", 124)
check(model.hits[1].name == "Search took too long", "Explain a timed-out search")
c.query("/partial")
c.flush()
c.file_requests[10].reply("/home/test/partial.txt\0/unfinished-path", 124)
check(#model.hits == 2 and model.hits[1].name == "partial.txt" and not model.hits[2].actionable, "Keep complete partial results and discard a truncated path")
c.query("/missing")
c.flush()
c.file_requests[11].reply("", 127)
check(model.hits[1].name == "File search is unavailable", "Explain a missing fd command")

c = controller({ ["spotlight-files.json"] = { roots = { "~/Documents", "/mnt/photos" } } })
c.open()
c.query("/--hidden")
c.flush()
args = c.file_requests[1].args
for i, value in ipairs(args) do if value == "--" then separator = i end end
check(args[separator + 1] == "--hidden" and args[separator + 2] == "/home/test/Documents" and args[separator + 3] == "/mnt/photos", "Expand configured folders and prevent query text from becoming flags")
c.file_requests[1].reply("/mnt/photos/--hidden.txt\0", 0)
check(model.hits[1].sub == "/mnt/photos", "Show folders outside home without a misleading home abbreviation")
c = controller({ ["spotlight-files.json"] = { roots = { "relative/folder" } } })
c.open()
c.query("/name")
c.flush()
check(#c.file_requests == 0 and model.hits[1].name == "Could not search these folders", "Invalid configured roots must not silently widen search to home")

c = controller()
c.open()
c.query("/removed")
c.flush()
c.file_requests[1].reply("/home/test/removed.txt\0", 0)
c.open_error = 2
c.handlers.launch(0)
c.close()
c.flush()
local notice = c.commands[#c.commands]
check(notice.command == "notify-send" and notice.args[2] == "That file or folder no longer exists", "Explain a file removed between search and opening")

print("Spotlight: " .. passed .. " checks passed")
