-- Run only this suite: lua tests/settings-search.lua      (from the repository root)
--
-- Tests shell/settings_catalog.luau + shell/settings_search.luau (and the search ranking they ride on) against a
-- MOCKED Luau scene environment (text / fact / model / on / after / cancel). Nothing touches the live shell.
--
-- Assumptions (explicit):
--   B1. The scene runtime provides the globals `text`, `fact`, `model`, `on(event, fn)`, `after(ms, fn) -> job`,
--       `cancel(job)`. A logic's own writes to text/fact do NOT fire its own listeners (settings.luau says so), but
--       a variant of the harness below makes them fire, to prove the adapter does not depend on that.
--   B2. Timers are drained by hand with advance(ms); nothing real sleeps.
--   B3. Search is a VIEW over the catalogue: it may write only the search / reveal facts, never a preference fact.
--   B4. "Page rows" are the sidebar categories in actions.settings; they must stay in the result set next to the
--       per-control rows and stay routable (choose_tab(page.tab)) without a setting_id.
--   B5. IDs are an external contract (Spotlight emits Settings.reveal_setting(id)): renaming one breaks callers.

package.path = "shell/?.luau;" .. package.path

local passed, failures = 0, {}
local function check(v, why)
    if v then passed = passed + 1 else failures[#failures + 1] = why; print("  FAIL: " .. why) end
end
local function head(name) print("-- " .. name) end

local function deep_copy(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for k, x in pairs(v) do out[k] = deep_copy(x) end
    return out
end
local function deep_equal(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for k, v in pairs(a) do if not deep_equal(v, b[k]) then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
end

local catalogue = require("settings_catalog")
local actions = require("actions")

---------------------------------------------------------------------------------------------------------------
head("1. catalogue: stable control IDs")
do
    -- B5: the exact public ID list. A rename or deletion must be a deliberate edit of this table.
    local GOLDEN = {
        ["appearance.mode"] = 0, ["appearance.skin"] = 0, ["appearance.wallpaper-colours"] = 0,
        ["appearance.app-themes"] = 0, ["appearance.accent"] = 0, ["appearance.palette"] = 0,
        ["notifications.quiet"] = 3, ["notifications.dnd"] = 3, ["notifications.group"] = 3,
        ["notifications.banners"] = 3, ["notifications.duration"] = 3,
        ["frame.style"] = 4, ["frame.clock"] = 4, ["frame.seconds"] = 4, ["frame.weather"] = 4,
        ["frame.tray"] = 4, ["frame.workspaces"] = 4, ["frame.app"] = 4, ["frame.updates"] = 4,
        ["dock.autohide"] = 4, ["dock.size"] = 4, ["dock.delay"] = 4, ["dock.order"] = 4,
        ["widgets.visible"] = 4, ["widgets.arrange"] = 4,
        ["frame.left-order"] = 4, ["frame.right-order"] = 4, ["frame.outputs"] = 4,
        ["dock.outputs"] = 4, ["dock.reveal"] = 4, ["frame.output-name"] = 4,
        ["appearance.custom-accent"] = 0, ["appearance.text"] = 0,
        ["appearance.glass-strength"] = 0, ["appearance.motion"] = 0,
    }
    local seen, reveals, n = {}, {}, 0
    for _, c in ipairs(catalogue.controls) do
        n = n + 1
        check(type(c.id) == "string" and c.id:find("^[%l%d]+%.[%l%d%-]+$") ~= nil, "id has the namespaced lower-case shape: " .. tostring(c.id))
        check(not seen[c.id], "id is unique: " .. tostring(c.id)); seen[c.id] = true
        check(math.type and math.type(c.reveal) == "integer" or (type(c.reveal) == "number" and c.reveal == math.floor(c.reveal) and c.reveal > 0), "reveal target is a positive integer: " .. c.id)
        check(not reveals[c.reveal], "reveal target is unique (two controls would highlight together): " .. c.id); reveals[c.reveal] = true
        check(type(c.name) == "string" and c.name ~= "" and type(c.keywords) == "string" and type(c.section) == "string", "searchable fields present: " .. c.id)
        check(GOLDEN[c.id] == c.tab, "golden ID " .. c.id .. " is still on tab " .. tostring(GOLDEN[c.id]))
        -- the control's tab and section must be a real sidebar page
        local page
        for _, p in ipairs(actions.settings) do if p.tab == c.tab then page = p end end
        check(page ~= nil, "control tab exists in the sidebar: " .. c.id)
        check(page and page.name == c.section, "section label equals its page name: " .. c.id .. " (" .. tostring(c.section) .. ")")
    end
    for id in pairs(GOLDEN) do check(catalogue.find(id) ~= nil, "golden ID still resolves: " .. id) end
    check(n == 35, "no control silently added without updating the golden list (" .. n .. ")")
    local a, b = catalogue.find("appearance.accent"), catalogue.target(catalogue.find("appearance.accent").reveal)
    check(a == b, "find and target agree")

    -- unknown / hostile ids are inert
    for _, bad in ipairs({ "nope", "", "APPEARANCE.MODE", "appearance.mode ", "appearance", "__index", "constructor", "settings:0" }) do
        check(catalogue.find(bad) == nil, "unknown id resolves to nothing: '" .. bad .. "'")
    end
    check(catalogue.find(nil) == nil and catalogue.find(3) == nil and catalogue.find({}) == nil and catalogue.find(true) == nil, "non-string ids resolve to nothing")
    check(catalogue.target("1") == nil and catalogue.target(0) == nil and catalogue.target(99) == nil and catalogue.target(1.5) == nil and catalogue.target(nil) == nil, "target() only accepts a known number")
    check(catalogue.target(0 / 0) == nil, "target(NaN) is nothing")

    -- the IDs of the Appearance reset group (preferences.APPEARANCE) are a SECOND namespace for the same controls
    local P = require("preferences")
    local missing = {}
    for _, a in ipairs(P.APPEARANCE) do
        if not catalogue.find(a.id) then missing[#missing + 1] = a.id end
    end
    check(#missing == 0, "every preferences.APPEARANCE id is also a catalogue id (one stable ID per control); missing: " .. table.concat(missing, ", "))
    check(catalogue.find("appearance.app-themes").fact == "pref_apps" and catalogue.find("appearance.app-themes").default == true,
        "app integration describes the existing preference schema")
    check(catalogue.find("dock.delay").max == 2 and catalogue.find("dock.delay").default == 1,
        "new search rows use the saved preference bounds")
end

---------------------------------------------------------------------------------------------------------------
head("2. catalogue.results keeps the pages and does not alter its inputs")
do
    local pages_before = deep_copy(actions.settings)
    local controls_before = deep_copy(catalogue.controls)
    local rows = catalogue.results(actions.settings)
    check(#rows == #actions.settings + #catalogue.controls, "every page and every control is a row")
    for i, page in ipairs(actions.settings) do
        check(rows[i] == page, "page " .. page.name .. " is preserved, in order, before the controls")
        check(rows[i].id == nil, "a page row has no setting id (it only routes to its tab)")
    end
    for i, c in ipairs(catalogue.controls) do check(rows[#actions.settings + i] == c, "control row " .. c.id .. " follows the pages in catalogue order") end
    rows[#rows + 1] = { tab = 99 }
    check(#catalogue.results(actions.settings) == #rows - 1, "the returned list is a fresh array (appending to it does not grow the catalogue)")
    check(deep_equal(pages_before, actions.settings) and deep_equal(controls_before, catalogue.controls), "results() leaves pages and controls untouched")
    check(#catalogue.results({}) == #catalogue.controls, "no pages: controls only")
    -- tabs of the sidebar are not contiguous (7 is absent: Night Light is 8); every tab must survive
    local tabs = {}
    for _, p in ipairs(actions.settings) do tabs[p.tab] = true end
    check(tabs[8] and tabs[0] and not tabs[7], "sidebar tabs as expected (0..6 and 8)")
    -- ranking (pure) leaves the source rows alone too
    local search = require("spotlight_search")
    local before = deep_copy(actions.settings_results)
    local got = search.results("? accent", { settings = actions.settings_results }, search.history(), 8)
    check(deep_equal(before, actions.settings_results), "search.results never writes to the catalogue rows (score lives on the result row)")
    local ids = {}
    for _, r in ipairs(got) do ids[#ids + 1] = r.setting_id or ("page:" .. r.tab) end
    check(ids[1] == "appearance.accent", "'accent' ranks the exact control first (got " .. tostring(ids[1]) .. ")")
end

---------------------------------------------------------------------------------------------------------------
head("3. deterministic ranking in '?' mode")
do
    local search = require("spotlight_search")
    local function order(rows, q)
        local o = {}
        for _, r in ipairs(search.results("? " .. q, { settings = rows }, search.history(), 50)) do o[#o + 1] = r.setting_id or ("page" .. r.tab) end
        return table.concat(o, ",")
    end
    local base = actions.settings_results
    -- the same data in every rotation / reversal must rank the same: the order must not depend on input order
    local function permute(rows, how)
        local out = {}
        if how == "reverse" then for i = #rows, 1, -1 do out[#out + 1] = rows[i] end
        elseif how == "rotate" then for i = 1, #rows do out[i] = rows[(i + 4) % #rows + 1] end
        else for i = 1, #rows do out[i] = rows[i] end end
        return out
    end
    for _, q in ipairs({ "colour", "colors", "a", "e", "theme", "light", "accent", "app" }) do
        local ref = order(base, q)
        for _, how in ipairs({ "reverse", "rotate" }) do
            local got = order(permute(base, how), q)
            check(got == ref, "query '" .. q .. "': " .. how .. "d input gives the same order\n      " .. ref .. "\n      " .. got)
        end
    end
end

---------------------------------------------------------------------------------------------------------------
-- the mocked scene environment
local function environment(reactive)
    local env = { now = 0, jobs = {}, next_job = 0, handlers = {}, tab_calls = {}, cancelled = {}, writes = {} }
    local function make_store(name, initial)
        local data = initial or {}
        return setmetatable({}, {
            __index = function(_, k) return data[k] end,
            __newindex = function(_, k, v)
                env.writes[#env.writes + 1] = name .. "." .. tostring(k)
                data[k] = v
                if reactive and name == "text" then
                    local fn = env.handlers["text:" .. k]
                    if fn then fn(v) end
                end
            end,
            __pairs = function() return pairs(data) end,
        })
    end
    env.text = make_store("text", { side_q = "" })
    env.fact = make_store("fact", { tab = 0, setting_target = 0, setting_reveal = 0, settings_search = false, settings_search_sel = 0 })
    env.model = make_store("model", {})
    -- preference facts that search must never touch
    env.prefs = { appearance = 2, skin = 1, accent = 3, accent_auto = true, pal_style = 2, dark_mode = false, hour12 = false, pref_apps = false,
        pref_seconds = true, banner_i = 3, lock_i = 4, pref_tray = false }
    for k, v in pairs(env.prefs) do env.fact[k] = v end
    env.writes = {}
    env.on = function(event, fn) env.handlers[event] = fn end
    env.after = function(ms, fn)
        env.next_job = env.next_job + 1
        local job = { id = env.next_job, at = env.now + ms, fn = fn, live = true }
        env.jobs[#env.jobs + 1] = job
        return job
    end
    env.cancel = function(job) if job then job.live = false; env.cancelled[#env.cancelled + 1] = job end end
    function env.advance(ms)
        local target = env.now + ms
        while true do
            local nxt
            for _, j in ipairs(env.jobs) do if j.live and j.at <= target and (not nxt or j.at < nxt.at) then nxt = j end end
            if not nxt then break end
            env.now = nxt.at; nxt.live = false; nxt.fn()
        end
        env.now = target
    end
    function env.live_jobs() local n = 0; for _, j in ipairs(env.jobs) do if j.live then n = n + 1 end end; return n end
    function env.emit(event, ...) local fn = env.handlers[event]; assert(fn, "no handler for " .. event); return fn(...) end
    function env.type_query(q)
        env.text.side_q = q                                    -- the runtime fires text:Keys.side_q on a USER edit
        env.handlers["text:Keys.side_q"](q)
    end
    function env.rows() local out = {}; for i, r in ipairs(env.model.setting_matches or {}) do out[i] = r end; return out end
    function env.prefs_unchanged()
        for k, v in pairs(env.prefs) do if env.fact[k] ~= v then return false, k end end
        return true
    end
    return env
end

local function boot(reactive)
    local env = environment(reactive)
    -- install the globals the module expects
    _G.text, _G.fact, _G.model = env.text, env.fact, env.model
    package.loaded["keys_text"] = env.text        -- the search field is the Keys scene's: the module reads / writes it through keys_text
    _G.on, _G.after, _G.cancel = env.on, env.after, env.cancel
    local function choose_tab(v) env.tab_calls[#env.tab_calls + 1] = v; env.fact.tab = tonumber(v) or 0 end
    package.loaded["settings_search"] = nil
    env.api = dofile("shell/settings_search.luau")(actions, choose_tab)
    env.writes = {}
    return env
end

---------------------------------------------------------------------------------------------------------------
head("4. typing: query -> bounded rows, pages preserved, stable ids")
do
    local env = boot(false)
    env.type_query("appearance")
    local rows = env.rows()
    check(env.fact.settings_search == true and #rows >= 2, "a query shows the result list")
    check(env.fact.settings_search_sel == 0, "selection starts on the first row")
    for i, r in ipairs(rows) do check(r.idx == i - 1 and type(r.name) == "string" and type(r.sub) == "string", "row " .. i .. " has name, sub and a 0-based idx") end
    local page_row, ctrl_row
    for _, r in ipairs(rows) do
        if r.name == "Appearance" then page_row = r end
        if r.name == "Appearance mode" then ctrl_row = r end
    end
    check(page_row ~= nil and ctrl_row ~= nil, "the page 'Appearance' and its control 'Appearance mode' are both offered")
    check(page_row and page_row.sub == "Settings", "page rows keep the plain 'Settings' label")
    check(ctrl_row and ctrl_row.sub == "Settings · Appearance", "control rows say which page they live on")
    check(rows[1].name == "Appearance", "an exact page-name match ranks first")

    -- bounded: a one-letter query matches nearly everything, still at most 8 rows
    env.type_query("a")
    check(#env.rows() == 8, "matches are bounded to 8 (" .. #env.rows() .. ")")
    env.type_query("e")
    check(#env.rows() <= 8, "bounded for another broad query")
    local total = #actions.settings + #catalogue.controls
    check(total > 8, "the catalogue is larger than the bound (so the bound is really exercised)")

    -- whitespace-only / empty / nil queries show nothing and turn the list off
    for _, q in ipairs({ "", "   ", "\t\n " }) do
        env.type_query(q)
        check(env.fact.settings_search == false and #env.rows() == 0, "blank query '" .. q:gsub("%s", "·") .. "' hides results")
    end
    env.text.side_q = nil
    env.handlers["text:Keys.side_q"](nil)
    check(env.fact.settings_search == false, "nil text is a blank query, not an error")
    env.type_query("  accent  ")
    check(env.fact.settings_search == true and env.rows()[1].name == "Accent colour", "surrounding whitespace is ignored")
    env.type_query("zzzzzz")
    check(#env.rows() == 0 and env.fact.settings_search == true, "no match: empty list but the 'No matches' panel is on")
    env.type_query("volume")
    check(env.rows()[1].name == "Sound", "keyword reaches its page (volume -> Sound)")
    -- hostile text never raises
    for _, q in ipairs({ "%", "[", "(", "%1", "?", "> x", "@", string.rep("x", 5000), "\0", "a\nb" }) do
        local ok = pcall(env.type_query, q)
        check(ok, "query " .. string.format("%q", q:sub(1, 12)) .. " does not raise")
    end
end

---------------------------------------------------------------------------------------------------------------
head("5. wrap-around navigation")
do
    local env = boot(false)
    env.type_query("a")
    local n = #env.rows()
    check(n == 8, "precondition: 8 rows")
    local function step(d) env.emit("settings_search_step", d) end
    step(1); check(env.fact.settings_search_sel == 1, "Down moves to the second row")
    for _ = 1, n - 2 do step(1) end
    check(env.fact.settings_search_sel == n - 1, "Down reaches the last row")
    step(1); check(env.fact.settings_search_sel == 0, "Down on the last row wraps to the first")
    step(-1); check(env.fact.settings_search_sel == n - 1, "Up on the first row wraps to the last")
    step(-1); check(env.fact.settings_search_sel == n - 2, "Up moves back")
    step(n); check(env.fact.settings_search_sel == n - 2, "a full lap is a no-op")
    step(-3 * n - 1); check(env.fact.settings_search_sel == n - 3, "a large negative delta still lands in range")
    check(env.fact.settings_search_sel >= 0 and env.fact.settings_search_sel < n, "selection is always inside the list")
    step(nil); check(env.fact.settings_search_sel == (n - 3 + 1) % n, "no delta means one step down")
    step("-1"); check(env.fact.settings_search_sel == (n - 3) % n, "a numeric string delta is understood")
    local keep = env.fact.settings_search_sel
    step("sideways"); check(env.fact.settings_search_sel == (keep + 1) % n, "a non-numeric delta falls back to one step down")
    -- fractional / NaN deltas would leave a selection no row can match
    local before = env.fact.settings_search_sel
    step(0.5)
    local sel = env.fact.settings_search_sel
    check(sel == math.floor(sel), "a fractional delta never leaves a fractional selection (got " .. tostring(sel) .. ")")
    env.fact.settings_search_sel = before
    step(0 / 0)
    sel = env.fact.settings_search_sel
    check(sel == sel and sel == math.floor(sel) and sel >= 0 and sel < n, "a NaN delta never leaves NaN as the selection (got " .. tostring(sel) .. ")")

    -- single result: both directions stay on it; no result: inert
    env.type_query("zzzz")
    env.fact.settings_search_sel = 0
    step(1); step(-1); step(5)
    check(env.fact.settings_search_sel == 0, "no rows: stepping changes nothing")
    env.type_query("night light")
    local one = #env.rows()
    env.fact.settings_search_sel = 0
    step(1)
    check(env.fact.settings_search_sel == (1 % one), "small result lists wrap too (" .. one .. " rows)")
    -- typing again resets the selection to the top
    env.type_query("a"); step(3); check(env.fact.settings_search_sel == 3, "moved")
    env.type_query("ac"); check(env.fact.settings_search_sel == 0, "a new query resets the selection")
end

---------------------------------------------------------------------------------------------------------------
head("6. reveal: unknown ids are inert")
do
    local env = boot(false)
    env.type_query("accent")
    local rows_before = env.rows()
    env.fact.tab, env.tab_calls = 5, {}
    env.writes = {}
    for _, bad in ipairs({ "does.not-exist", "", "Appearance.Mode", 42, true, {}, "settings:0", "appearance.mode\0" }) do
        local ok, res = pcall(env.emit, "reveal_setting", bad)
        check(ok and res == false, "reveal(" .. tostring(type(bad) == "string" and bad or type(bad)) .. ") returns false without raising")
    end
    check(pcall(env.emit, "reveal_setting", nil), "reveal(nil) does not raise")
    check(#env.tab_calls == 0 and env.fact.tab == 5, "an unknown id never changes the tab")
    check(#env.writes == 0, "an unknown id writes no facts or texts at all (wrote: " .. table.concat(env.writes, ",") .. ")")
    check(env.fact.setting_reveal == 0 and env.fact.setting_target == 0, "no serial bump, no highlight")
    check(env.live_jobs() == 0, "no highlight timer was armed")
    check(env.fact.settings_search == true and deep_equal(env.rows(), rows_before) and env.text.side_q == "accent", "the search in progress is left exactly as it was")
    -- and an unknown id arriving while a valid highlight is running must not disturb it
    check(env.emit("reveal_setting", "appearance.skin") == true, "valid reveal")
    local job_count, target = env.live_jobs(), env.fact.setting_target
    env.emit("reveal_setting", "ghost")
    check(env.live_jobs() == job_count and env.fact.setting_target == target and #env.cancelled == 0, "an unknown id does not cancel or re-arm a running highlight")
    -- the module's public API is the same function
    check(env.api.reveal("ghost") == false and env.api.reveal("appearance.skin") == true, "returned API behaves like the event")
end

---------------------------------------------------------------------------------------------------------------
head("7. reveal: routing, serial, highlight timer")
for _, reactive in ipairs({ false, true }) do
    local label = reactive and " (text writes fire listeners)" or ""
    local env = boot(reactive)
    env.type_query("accent")
    check(env.emit("reveal_setting", "appearance.accent") == true, "reveal known id" .. label)
    local control = catalogue.find("appearance.accent")
    check(env.tab_calls[#env.tab_calls] == control.tab, "routes to the control's tab" .. label)
    check(env.fact.setting_target == control.reveal, "highlight target is the control's reveal number" .. label)
    check(env.fact.setting_reveal == 1, "serial starts at 1" .. label)
    check(env.fact.settings_search == false and #env.rows() == 0 and env.text.side_q == "", "search is closed and emptied after revealing" .. label)
    check(env.live_jobs() == 1, "exactly one highlight timer" .. label)

    -- the SAME result chosen again must scroll again: the serial changes even though the target does not
    local s1 = env.fact.setting_reveal
    env.emit("reveal_setting", "appearance.accent")
    check(env.fact.setting_reveal == s1 + 1 and env.fact.setting_target == control.reveal, "choosing the same result again bumps the serial" .. label)
    env.emit("reveal_setting", "appearance.accent")
    check(env.fact.setting_reveal == s1 + 2, "...every time" .. label)
    check(env.live_jobs() == 1, "still exactly one highlight timer after repeats (old ones cancelled)" .. label)
    check(#env.cancelled == 2, "each repeat cancelled the previous timer" .. label)

    -- timing: a second reveal at t=3000 owns the highlight until t=8000; the first timer must not clear it at 5000
    local t = boot(reactive)
    t.emit("reveal_setting", "appearance.skin")
    t.advance(3000)
    t.emit("reveal_setting", "appearance.palette")
    t.advance(2001)                                            -- t = 5001: the FIRST timer's deadline has passed
    check(t.fact.setting_target == catalogue.find("appearance.palette").reveal, "an older timer cannot clear a newer highlight" .. label)
    t.advance(2998)                                            -- t = 7999
    check(t.fact.setting_target ~= 0, "the newer highlight lasts its full 5 s" .. label)
    t.advance(2)                                               -- t = 8001
    check(t.fact.setting_target == 0, "and is cleared 5 s after the LAST reveal" .. label)
    check(t.live_jobs() == 0, "no timer left behind" .. label)
    -- after the highlight ended, revealing again works and a stale handle is not cancelled twice
    t.emit("reveal_setting", "appearance.mode")
    check(t.fact.setting_target == catalogue.find("appearance.mode").reveal and t.fact.setting_reveal == 3, "reveal after the highlight expired" .. label)
    local cancelled = #t.cancelled
    t.advance(5001)
    t.emit("reveal_setting", "appearance.mode")
    check(#t.cancelled == cancelled, "an expired timer is not cancelled again (handle was dropped)" .. label)

    -- the serial survives hostile starting values
    for _, start in ipairs({ "abc", false, -5 }) do
        local e = boot(reactive)
        e.fact.setting_reveal = start
        e.emit("reveal_setting", "appearance.mode")
        check(type(e.fact.setting_reveal) == "number" and e.fact.setting_reveal ~= start, "serial recovers from " .. tostring(start) .. label)
    end
end

---------------------------------------------------------------------------------------------------------------
head("8. picking a result: control vs page, submit, clear")
do
    local env = boot(false)
    env.type_query("appearance")
    local rows = env.rows()
    local ctrl_idx, page_idx
    for _, r in ipairs(rows) do
        if r.name == "Appearance mode" then ctrl_idx = r.idx end
        if r.name == "Appearance" then page_idx = r.idx end
    end
    -- a page row only switches tab and clears any highlight
    env.fact.setting_target = 4
    env.emit("settings_search_pick", page_idx)
    check(env.tab_calls[#env.tab_calls] == 0 and env.fact.setting_target == 0, "picking a page row opens the page and clears the highlight")
    check(env.fact.settings_search == false and #env.rows() == 0, "and closes the search")
    local serial = env.fact.setting_reveal
    check(serial == 0, "a page pick does not bump the reveal serial (nothing to scroll to)")

    env.type_query("appearance")
    env.emit("settings_search_pick", ctrl_idx)
    check(env.fact.setting_target == catalogue.find("appearance.mode").reveal and env.fact.setting_reveal == serial + 1, "picking a control row reveals it")

    -- Enter submits the highlighted row
    env.type_query("night")
    env.fact.settings_search_sel = 0
    local first = env.rows()[1]
    env.emit("settings_search_submit")
    check(env.tab_calls[#env.tab_calls] == 8 and first.name:find("Night"), "Enter opens the selected row (Night Light & Power is tab 8)")

    -- out-of-range / hostile picks are inert
    env.type_query("appearance")
    local calls, writes = #env.tab_calls, #env.writes
    for _, bad in ipairs({ -1, 99, 1.5, "x" }) do env.emit("settings_search_pick", bad) end
    -- tonumber("x") is nil -> falls back to the current selection (a valid row): only that one may act
    local acted = #env.tab_calls - calls
    check(acted <= 1, "bad pick indices do not open arbitrary rows (acted " .. acted .. ")")

    -- clear + submit with nothing listed does nothing
    local e2 = boot(false)
    e2.type_query("accent")
    e2.emit("settings_search_clear")
    check(e2.fact.settings_search == false and #e2.rows() == 0 and e2.text.side_q == "", "clear empties the search")
    e2.fact.settings_search_sel = 3
    e2.emit("settings_search_submit")
    e2.emit("settings_search_pick")
    check(#e2.tab_calls == 0, "Enter / pick with no results is inert")
    e2.emit("settings_search_step", 1)
    check(e2.fact.settings_search_sel == 3, "stepping with no results leaves the selection alone")
    check(e2.live_jobs() == 0, "clearing arms no timers")
end

---------------------------------------------------------------------------------------------------------------
head("9. search never mutates preference values or the catalogue")
for _, reactive in ipairs({ false, true }) do
    local label = reactive and " (reactive)" or ""
    local env = boot(reactive)
    local catalogue_before = deep_copy(catalogue.controls)
    local pages_before = deep_copy(actions.settings)
    local results_before = deep_copy(actions.settings_results)
    for _, q in ipairs({ "a", "accent", "appearance", "dark", "volume", "night", "colour", "zzz", "" }) do
        env.type_query(q)
        env.emit("settings_search_step", 1)
        env.emit("settings_search_step", -1)
        env.emit("settings_search_submit")
    end
    for _, c in ipairs(catalogue.controls) do env.emit("reveal_setting", c.id) end
    env.emit("reveal_setting", "unknown")
    env.emit("settings_search_pick", 0)
    env.emit("settings_search_clear")
    env.advance(10000)
    local same, which = env.prefs_unchanged()
    check(same, "no preference fact changed" .. label .. (which and (" (" .. which .. ")") or ""))
    -- and the only keys search wrote are the search / reveal ones
    local allowed = { ["fact.settings_search"] = true, ["fact.settings_search_sel"] = true, ["fact.setting_target"] = true, ["fact.setting_reveal"] = true,
        ["fact.setting_y"] = true, ["fact.setting_h"] = true,
        ["text.side_q"] = true, ["model.setting_matches"] = true, ["fact.tab"] = true }
    local stray = {}
    for _, w in ipairs(env.writes) do if not allowed[w] then stray[w] = true end end
    local names = {}
    for w in pairs(stray) do names[#names + 1] = w end
    check(#names == 0, "search writes only its own facts" .. label .. (#names > 0 and (": " .. table.concat(names, ",")) or ""))
    check(deep_equal(catalogue_before, catalogue.controls) and deep_equal(pages_before, actions.settings) and deep_equal(results_before, actions.settings_results), "catalogue and pages are unchanged after use" .. label)
    check(env.fact.setting_target == 0 and env.live_jobs() == 0, "after 10 s the highlight is off and no timer remains" .. label)
end

---------------------------------------------------------------------------------------------------------------
head("10. Spotlight shares the catalogue: ordinary queries reach the same stable ids")
do
    local search = require("spotlight_search")
    local rows = search.results("accent", { settings = actions.settings_results, apps = {}, windows = {}, commands = actions.commands }, search.history(), 24)
    local hit
    for _, r in ipairs(rows) do if r.setting_id == "appearance.accent" then hit = r end end
    check(hit ~= nil and hit.kind == 5 and hit.tab == 0, "an unprefixed query returns the control with its id, tab and kind 5")
    local keys = {}
    for _, r in ipairs(rows) do check(not keys[r.key], "result keys are unique: " .. r.key); keys[r.key] = true end
    local pages = search.results("? ", { settings = actions.settings_results }, search.history(), 50)
    local page_rows, control_rows = 0, 0
    for _, r in ipairs(pages) do if r.setting_id then control_rows = control_rows + 1 else page_rows = page_rows + 1 end end
    check(page_rows == #actions.settings and control_rows == #catalogue.controls, "the empty '?' list holds every page and every control (" .. page_rows .. "/" .. control_rows .. ")")
end

head("11. notification and frame targets reveal the row without applying it")
do
    local search = require("spotlight_search")
    for _, c in ipairs(catalogue.controls) do
        check(type(c.y) == "number" and c.y >= 0 and c.h > 0, "viewport geometry exists: " .. c.id)
        local env = boot(false)
        check(env.api.reveal(c.id), "target reveals: " .. c.id)
        check(env.fact.tab == c.tab and env.fact.setting_y == c.y and env.fact.setting_h == c.h,
            "reveal supplies the right page and row geometry: " .. c.id)
        check(env.prefs_unchanged(), "reveal leaves preferences alone: " .. c.id)
    end
    for query, id in pairs({ ["dock hide delay"] = "dock.delay", ["banner duration"] = "notifications.duration",
        ["quiet hours"] = "notifications.quiet", ["24-hour clock"] = "frame.clock", ["show workspaces"] = "frame.workspaces" }) do
        for _, prefix in ipairs({ "", "? " }) do
            local rows = search.results(prefix .. query, { settings = actions.settings_results }, search.history(), 8)
            check(rows[1] and rows[1].setting_id == id, "Settings/Spotlight query routes to " .. id .. ": " .. prefix .. query)
        end
    end
end

print(string.format("settings-search: %d checks passed, %d failed", passed, #failures))
if #failures > 0 then
    for _, f in ipairs(failures) do print("  - " .. f:gsub("\n.*", "")) end
    os.exit(1)
end
