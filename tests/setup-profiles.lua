-- Run only this suite for portable setup profiles: lua tests/setup-profiles.lua
package.path = "shell/?.luau;" .. package.path
local P = require("preferences")
local SP = require("setup_profiles")
local passed = 0
local function check(v, why) if not v then error("FAILED: " .. tostring(why), 2) end passed = passed + 1 end

-- a small strict JSON decoder (the scene passes pleamar's json.decode; this one only feeds the tests)
local function decode(s)
    local i = 1
    local function ws() i = s:find("%S", i) or #s + 1 end
    local value
    local function str()
        local out = {}
        i = i + 1
        while true do
            local c = s:sub(i, i)
            if c == "" then error("unterminated string") end
            if c == '"' then i = i + 1; return table.concat(out) end
            if c == "\\" then
                local e = s:sub(i + 1, i + 1)
                if e == "u" then out[#out + 1] = string.char(tonumber(s:sub(i + 2, i + 5), 16)); i = i + 6
                else out[#out + 1] = ({ n = "\n", r = "\r", t = "\t" })[e] or e; i = i + 2 end
            else out[#out + 1] = c; i = i + 1 end
        end
    end
    function value()
        ws()
        local c = s:sub(i, i)
        if c == "{" then
            local t = {}
            i = i + 1; ws()
            if s:sub(i, i) == "}" then i = i + 1; return t end
            while true do
                ws(); local k = str(); ws()
                if s:sub(i, i) ~= ":" then error("colon expected at " .. i) end
                i = i + 1; t[k] = value(); ws()
                local d = s:sub(i, i); i = i + 1
                if d == "}" then return t end
                if d ~= "," then error("comma expected at " .. i) end
            end
        elseif c == "[" then
            local t = {}
            i = i + 1; ws()
            if s:sub(i, i) == "]" then i = i + 1; return t end
            while true do
                t[#t + 1] = value(); ws()
                local d = s:sub(i, i); i = i + 1
                if d == "]" then return t end
                if d ~= "," then error("comma expected at " .. i) end
            end
        elseif c == '"' then return str()
        elseif s:find("^true", i) then i = i + 4; return true
        elseif s:find("^false", i) then i = i + 5; return false
        elseif s:find("^null", i) then i = i + 4; return nil
        end
        local num = s:match("^-?%d+%.?%d*[eE]?[+-]?%d*", i)
        if not num or num == "" then error("unexpected '" .. c .. "' at " .. i) end
        i = i + #num
        return tonumber(num)
    end
    local v = value(); ws()
    if i <= #s then error("trailing text at " .. i) end
    return v
end


local function copy(v)
    if type(v) ~= "table" then return v end
    local t = {}
    for k, x in pairs(v) do t[k] = copy(x) end
    return t
end

-- ── a fake world of owners ───────────────────────────────────────
local function new_world()
    return {
        app = { appearance = 1, skin = 0, accent = 0, accent_auto = false, pal_style = 0 },
        palette = { style = 0, src = "#336699", dark = { a = "#112233", b = "#223344", s = "#334455" }, light = { a = "#aabbcc", b = "#bbccdd", s = "#ccddee" } },
        frame = { bar_style = 0, pref_seconds = false, pref_weather = true, pref_tray = true, pref_workspaces = true, pref_bar_apps = true,
            pref_updates = true, dock_size_i = 1, dock_delay_i = 1, pref_dock_auto = true, bar_left_order = 0, bar_right_order = 0,
            module_output_policy = 0, dock_output_policy = 0, dock_show_delay = 0, frame_output_name = "" },
        pins = { "org.gnome.Nautilus", "kitty", "app:zed|/usr/bin/zed --new" },
        apps = { ["org.gnome.Nautilus"] = true, kitty = true, firefox = true },
        widgets = { snap = true, cards = {
            { id = 1, out = "DP-1", kind = 1, sz = 1, x = 48, y = 72, opts = { date = "off" } },
            { id = 2, out = "DP-1", kind = 3, sz = 0, x = 48, y = 248, stack = { id = 1, i = 1, on = true } },
            { id = 3, out = "DP-1", kind = 4, sz = 0, x = 48, y = 248, stack = { id = 1, i = 2 } },
            { id = 4, out = "HDMI-A-1", kind = 5, sz = 1, x = 48, y = 72 },
        } },
        outputs = { ["DP-1"] = true, ["HDMI-A-1"] = true },
    }
end

-- differs from the exported setup (text0) in all four sections
local function diff_world()
    local w = new_world()
    w.app.skin = 2
    w.frame.bar_style = 1
    w.pins = { "firefox" }
    w.widgets = { snap = true, cards = { { id = 1, out = "DP-1", kind = 2, sz = 0, x = 400, y = 72 } } }
    return w
end

local function live_of(w)
    return {
        appearance = { values = copy(w.app), palette = copy(w.palette) },
        frame = { facts = copy(w.frame) },
        pins = { list = w.pins and copy(w.pins) or nil, apps = w.apps },
        widgets = { ready = true, snap = w.widgets.snap, cards = copy(w.widgets.cards) },
        outputs = { connected = w.outputs },
    }
end

-- one owner's current section, as the owner would snapshot it
local function owner_fp(w, section)
    local live = live_of(w)
    return SP.fingerprint(section, assert(SP.snapshot(section, live[section], { preferences = P })))
end

-- applies a request to the fake world; returns the ack info
local function owner_apply(w, act, mode)
    local section = act.section
    if not act.force and act.expect and owner_fp(w, section) ~= act.expect then
        return { ok = false, untouched = true, code = "stale" }
    end
    local data, errs = SP.validate_section(section, act.data, { preferences = P, local_pins = true })
    if not data then return { ok = false, untouched = true, code = "invalid", message = errs[1].message } end
    if mode == "nack" then return { ok = false, untouched = false, code = "io", message = "disk full" } end
    if section == "appearance" then
        for fact, v in pairs(SP.to_facts("appearance", data, { preferences = P })) do w.app[fact] = v end
        if act.data.palette then w.palette = copy(act.data.palette) end
    elseif section == "frame" then
        for fact, v in pairs(SP.to_facts("frame", data)) do w.frame[fact] = v end
    elseif section == "pins" then
        w.pins = data.default and nil or copy(data.list)
    else
        w.widgets = { snap = data.snap, cards = copy(data.cards) }
    end
    return { ok = true, fp = owner_fp(w, section) }
end

-- the host pump. hooks.persist(seq, text, n) -> ok ; hooks.owner(act, n) -> "timeout" | info | nil (apply for real)
local function pump(ctl, w, hooks)
    hooks = hooks or {}
    local log, journal, npersist, nowner = {}, nil, 0, 0
    for _ = 1, 200 do
        local act = ctl.next(hooks.live_each_step and live_of(w) or nil)
        if act.kind == "persist" then
            npersist = npersist + 1
            local ok = true
            if hooks.persist then ok = hooks.persist(act.seq, act.text, npersist) end
            if ok then journal = act.text end
            log[#log + 1] = "persist"
            ctl.persisted(act.seq, ok, ok and nil or "EIO")
        elseif act.kind == "apply" then
            nowner = nowner + 1
            log[#log + 1] = act.op .. ":" .. act.section
            local verdict = hooks.owner and hooks.owner(act, nowner)
            if verdict == "crash" then
                return { kind = "crashed" }, log, journal
            elseif verdict == "timeout" then
                if hooks.late_apply then owner_apply(w, act) end
                ctl.timeout(act.request)
            else
                ctl.ack(act.request, verdict or owner_apply(w, act))
            end
        elseif act.kind == "wait" then
            log[#log + 1] = "wait:" .. act.reason
            return act, log, journal
        elseif act.kind == "finish" then
            return act, log, journal
        elseif act.kind == "idle" then
            return act, log, journal
        end
    end
    error("pump did not settle")
end

local function new_ctl(extra)
    local a = { decode = decode, preferences = P, now = function() return 1000 end }
    for k, v in pairs(extra or {}) do a[k] = v end
    return SP.new(a)
end

-- ── 1. mirrored bounds agree with the owners ─────────────────────
do
    local ok, L = pcall(require, "widget_layouts")
    if ok then
        check(SP.MAX_CARDS == L.MAX_CARDS and SP.MAX_COORD == L.MAX_COORD and SP.MAX_OUT == L.MAX_OUT, "card bounds mirror widget_layouts")
    end
    local okf, F = pcall(require, "frame_options")
    check(not okf or SP.MAX_PINS == F.MAX_PINS, "pin limit mirrors frame_options")
    local oks, S = pcall(require, "widget_stacks")
    check(not oks or SP.MAX_STACK_MEMBERS == S.MAX_MEMBERS and SP.MAX_STACK_ID == S.MAX_ID, "stack bounds mirror widget_stacks")
    check(#SP.SECTIONS == 4 and SP.OWNER.pins == "topbar" and SP.OWNER.widgets == "widgets" and SP.OWNER.appearance == "settings", "owners")
end

-- ── 2. export ────────────────────────────────────────────────────
local w0 = new_world()
local ctl0 = new_ctl()
local text0, doc0, report0 = ctl0.export(live_of(w0))
check(text0 and doc0 and report0, "export works")
check(#report0.included == 4 and #report0.skipped == 0, "all four sections exported")
check(#report0.excluded == 1 and report0.excluded[1].section == "pins" and report0.excluded[1].message:find("command"), "window pin reported as left out")
check(not text0:find("zed") and not text0:find("app:") and not text0:find("/usr"), "no command or path leaves in the export")
check(doc0.sections.pins.list[1] == "org.gnome.Nautilus" and #doc0.sections.pins.list == 2, "portable pins exported in order")
check(doc0.sections.appearance.values["appearance.mode"] == 1 and doc0.sections.frame.values["frame.output-name"] == "", "values by stable ids")
check(doc0.sections.widgets.cards[2].stack.id == 1 and doc0.sections.widgets.cards[2].stack.on == true and doc0.sections.widgets.cards[3].stack.i == 2, "stack metadata exported, not stripped")
check(doc0.sections.widgets.cards[1].opts.date == "off", "card options exported")
check(not text0:find("#336699") and not text0:find("\"dark\""), "derived palette colours are never exported")
check(#text0 < 8192, "a real setup is small")
do
    local a = ctl0.export(live_of(w0), { "frame" })
    local d = decode(a)
    check(d.sections.frame and not d.sections.widgets and not d.sections.pins, "selective export")
    local t, f = ctl0.export(live_of(w0), { "bogus" })
    check(t == nil and f.code == "section", "unknown section refused")
    local t2, f2, r2 = ctl0.export({ frame = { facts = {} } }, { "pins" })
    check(t2 == nil and f2.code == "empty" and r2.skipped[1].section == "pins", "unavailable sections are reported, nothing to export")
    local w = new_world(); w.pins = nil
    local d3 = decode((ctl0.export(live_of(w), { "pins" })))
    check(d3.sections.pins.default == true, "automatic pins export as default")
end
-- a broken live stack refuses the widgets section instead of exporting something altered
do
    local w = new_world(); w.widgets.cards[3].stack.on = true      -- two active members
    local t, f, r = ctl0.export(live_of(w), { "widgets" })
    check(t == nil and r.skipped[1].reason:find("active"), "inconsistent live stack is not exported silently")
    local w2 = new_world(); w2.widgets.cards[4].id = 1             -- duplicate id: card not representable
    local _, _, r2 = ctl0.export(live_of(w2), { "widgets" })
    check(r2.excluded[1] and r2.excluded[1].message:find("left out"), "skipped cards are counted")
end

-- ── 3. round trip ────────────────────────────────────────────────
do
    local fresh = new_world()
    fresh.app = { appearance = 0, skin = 2, accent = 4, accent_auto = false, pal_style = 1 }
    fresh.frame.bar_style = 1; fresh.frame.dock_size_i = 2; fresh.frame.frame_output_name = "DP-2"
    fresh.pins = { "firefox" }; fresh.widgets = { snap = false, cards = {} }
    local ctl = new_ctl()
    local p = ctl.preview_import(text0, live_of(fresh))
    check(p.ok and not p.noop and p.token, "preview of a different machine has changes")
    local act, _, _ = nil, nil, nil
    check(ctl.begin(p.token, live_of(fresh)).ok, "begin")
    act = pump(ctl, fresh)
    check(act.kind == "finish" and act.ok and act.code == "applied" and #act.applied == 4, "applied everywhere")
    -- local window pin handling: fresh had none; the imported list wins
    local ex = ctl.export(live_of(fresh))
    local d1, d2 = decode(text0), decode(ex)
    check(SP.fingerprint("widgets", d1.sections.widgets and { snap = d1.sections.widgets.snap, cards = d1.sections.widgets.cards })
        == SP.fingerprint("widgets", { snap = d2.sections.widgets.snap, cards = d2.sections.widgets.cards }), "widgets round trip (stacks included)")
    check(d1.sections.frame.values["frame.output-name"] == d2.sections.frame.values["frame.output-name"]
        and d1.sections.appearance.values["appearance.skin"] == d2.sections.appearance.values["appearance.skin"]
        and #d2.sections.pins.list == 2, "supported choices round trip")
    local again = ctl.preview_import(text0, live_of(fresh))
    check(again.ok and again.noop and again.token == nil and again.message:find("No changes"), "applying the same file again is a no-op")
end

-- ── 4. strict import: invalid files change nothing ───────────────
do
    local ctl = new_ctl()
    local function bad(t, code, why)
        local r = ctl.parse_import(t)
        check(not r.ok, why .. " (rejected)")
        local found = code == nil
        for _, e in ipairs(r.errors) do if e.code == code then found = true end end
        check(found, why .. " (code " .. tostring(code) .. ", got " .. (r.errors[1] and r.errors[1].code or "?") .. ")")
        local pv = ctl.preview_import(t, live_of(new_world()))
        check(not pv.ok and not pv.token and ctl.status().state ~= "preview", why .. " (nothing staged)")
    end
    local function wrap(sections) return '{"kind":"beskar.setup","version":1,"sections":' .. sections .. '}' end
    bad(nil, "empty", "nil")
    bad("   ", "empty", "blank")
    bad("[1]", "format", "array")
    bad("{not json", "format", "malformed")
    bad(string.rep(" ", SP.MAX_IMPORT_BYTES + 1), "size", "oversize")
    bad('{"kind":"beskar.appearance","version":1,"values":{}}', "kind", "other kind")
    bad('{"kind":"x","version":1,"sections":{}}', "kind", "wrong kind")
    bad('{"kind":"beskar.setup","version":2,"sections":{"frame":{"values":{"frame.tray":true}}}}', "version", "newer version")
    bad('{"kind":"beskar.setup","version":"1","sections":{}}', "version", "version type")
    bad(wrap('{}'), "empty", "no sections")
    bad(wrap('{"commands":{"list":["rm -rf /"]}}'), "unsupported", "commands section")
    bad(wrap('{"personal":{}}'), "unsupported", "personal content")
    bad(wrap('{"timers":{}}'), "unsupported", "timers")
    bad(wrap('{"display":{"mode":"2560x1440"}}'), "unsupported", "display modes")
    bad(wrap('{"frame":{"values":{"frame.tray":true},"command":"x"}}'), "unsupported", "extra key in a section")
    bad(wrap('{"frame":{"values":{"frame.tray":1}}}'), "value", "bool as number")
    bad(wrap('{"frame":{"values":{"frame.bar-style":2}}}'), "value", "enum out of range")
    bad(wrap('{"frame":{"values":{"frame.bar-style":0.5}}}'), "value", "fractional enum")
    bad(wrap('{"frame":{"values":{"frame.nope":1}}}'), "unsupported", "unknown id")
    bad(wrap('{"frame":{"values":{"frame.output-name":"a b"}}}'), "value", "output name with space")
    bad(wrap('{"frame":{"values":{"frame.output-name":"' .. string.rep("a", 65) .. '"}}}'), "value", "output name too long")
    bad(wrap('{"frame":{"values":{"frame.output-name":"../x"}}}'), "value", "output name with a path")
    bad(wrap('{"frame":{"values":{"frame.output-name":7}}}'), "value", "output name not text")
    bad(wrap('{"frame":{"values":{}}}'), "empty", "empty values")
    bad(wrap('{"appearance":{"values":{"appearance.mode":5}}}'), "value", "appearance out of range")
    bad(wrap('{"appearance":{"values":{"appearance.palette":0},"palette":{}}}'), "unsupported", "palette in a section")
    bad(wrap('{"pins":{"list":["app:zed|/bin/zed"]}}'), "value", "command pin")
    bad(wrap('{"pins":{"list":["/usr/bin/zed"]}}'), "value", "path pin")
    bad(wrap('{"pins":{"list":["a","a"]}}'), "duplicate", "duplicate pin")
    bad(wrap('{"pins":{"list":["a b"]}}'), "value", "pin with space")
    bad(wrap('{"pins":{"list":[1]}}'), "value", "pin not text")
    bad(wrap('{"pins":{"list":["a"],"default":true}}'), "type", "pins both modes")
    bad(wrap('{"pins":{"list":["1","2","3","4","5","6","7","8","9","10","11","12","13"]}}'), "size", "too many pins")
    bad(wrap('{"pins":{"cmd":"x"}}'), "unsupported", "pins extra key")
    local card = '{"id":1,"out":"DP-1","kind":1,"sz":1,"x":0,"y":0}'
    bad(wrap('{"widgets":{"snap":true,"cards":[' .. card:gsub('"x":0', '"x":1.5') .. ']}}'), "value", "fractional position")
    bad(wrap('{"widgets":{"cards":[' .. card:gsub('"kind":1', '"kind":0') .. ']}}'), "value", "kind 0")
    bad(wrap('{"widgets":{"cards":[' .. card:gsub('"sz":1', '"sz":3') .. ']}}'), "value", "size 3")
    bad(wrap('{"widgets":{"cards":[' .. card:gsub('"x":0', '"x":100001') .. ']}}'), "value", "coordinate beyond the limit")
    bad(wrap('{"widgets":{"cards":[' .. card:gsub('"out":"DP%-1"', '"out":""') .. ']}}'), "value", "empty output")
    bad(wrap('{"widgets":{"cards":[' .. card .. ',' .. card .. ']}}'), "duplicate", "duplicate card ids")
    bad(wrap('{"widgets":{"cards":[' .. card:gsub('}$', ',"cmd":"x"}') .. ']}}'), "unsupported", "unknown card field")
    bad(wrap('{"widgets":{"cards":[' .. card:gsub('}$', ',"opts":{"date":"maybe"}}') .. ']}}'), "value", "known option with a bad value")
    bad(wrap('{"widgets":{"cards":[' .. card:gsub('}$', ',"opts":{"seconds":{"x":1}}}') .. ']}}'), "value", "option with a table value")
    bad(wrap('{"widgets":{"areas":{"DP-1":{"w":1,"h":1}},"cards":[]}}'), "unsupported", "areas are not portable")
    do
        local many = {}
        for i = 1, 17 do many[i] = card:gsub('"id":1', '"id":' .. i) end
        bad(wrap('{"widgets":{"cards":[' .. table.concat(many, ",") .. ']}}'), "size", "17 cards")
    end
    -- stacks
    local function sc(id, i, on, extra)
        return string.format('{"id":%d,"out":"DP-1","kind":3,"sz":0,"x":0,"y":0,"stack":{"id":1,"i":%d%s%s}}', id, i, on and ',"on":true' or '', extra or "")
    end
    bad(wrap('{"widgets":{"cards":[' .. sc(1, 1, true) .. ']}}'), "stack", "single-member stack")
    bad(wrap('{"widgets":{"cards":[' .. sc(1, 1, false) .. ',' .. sc(2, 2, false) .. ']}}'), "stack", "stack without an active member")
    bad(wrap('{"widgets":{"cards":[' .. sc(1, 1, true) .. ',' .. sc(2, 2, true) .. ']}}'), "stack", "two active members")
    bad(wrap('{"widgets":{"cards":[' .. sc(1, 1, true) .. ',' .. sc(2, 1, false) .. ']}}'), "stack", "repeated page position")
    do
        local gap = ctl.parse_import(wrap('{"widgets":{"cards":[' .. sc(1, 1, true) .. ',' .. sc(2, 3, false) .. ']}}'))
        check(gap.ok and gap.warnings[1].code == "stack_renumbered" and gap.sections.widgets.cards[2].stack.i == 3, "a gap in page order is accepted with a visible warning, not rewritten")
    end
    bad(wrap('{"widgets":{"cards":[' .. sc(1, 1, true) .. ',' .. sc(2, 2, false):gsub('"x":0', '"x":9') .. ']}}'), "stack", "different footprint")
    bad(wrap('{"widgets":{"cards":[' .. sc(1, 1, true, ',"zz":1') .. ',' .. sc(2, 2, false) .. ']}}'), "unsupported", "unknown stack field")
    bad(wrap('{"widgets":{"cards":[' .. sc(1, 1, true):gsub('"i":1', '"i":0') .. ',' .. sc(2, 2, false) .. ']}}'), "value", "stack position 0")
    bad(wrap('{"widgets":{"cards":[' .. sc(1, 1, true) .. ',' .. sc(2, 2, false):gsub('"stack":{', '"stack":{"on":"yes",'):gsub(',"on":true', '') .. ']}}'), nil, "active flag type")
    bad(wrap('{"widgets":{"cards":[' .. sc(1, 1, true):gsub('"opts"', '"o"') .. ',' .. sc(2, 2, false):gsub('}$', ',"opts":{"lock":true}}') .. ']}}'), "stack", "lock on part of a stack")
    -- a valid stack passes
    local good = ctl.parse_import(wrap('{"widgets":{"cards":[' .. sc(1, 1, true) .. ',' .. sc(2, 2, false) .. ']}}'))
    check(good.ok and good.sections.widgets.cards[2].stack.i == 2 and good.sections.widgets.cards[1].stack.on == true, "valid stack kept intact")
    check(good.sections.widgets.cards[2].stack.on == nil, "inactive member stays inactive")
end

-- ── 5. preview: reports, merge, local pins ───────────────────────
do
    local w = new_world()
    local ctl = new_ctl()
    local function wrap(sections) return '{"kind":"beskar.setup","version":1,"sections":' .. sections .. '}' end
    -- partial: only one value; the others keep their live values
    w.frame.bar_style = 1
    local p = ctl.preview_import(wrap('{"frame":{"values":{"frame.tray":false}}}'), live_of(w))
    check(p.ok and #p.sections.frame.changes == 1 and p.sections.frame.changes[1].id == "frame.tray", "only the named value changes")
    check(p.sections.frame.changes[1].from_label == "On" and p.sections.frame.changes[1].to_label == "Off", "labels in the review")
    check(p.order[1] == "frame" and #p.order == 1 and p.sections.appearance == nil, "only mentioned sections are reviewed")
    -- named monitor missing: reported, name kept
    w.outputs = { ["DP-1"] = true }
    local pm = ctl.preview_import(wrap('{"frame":{"values":{"frame.output-name":"HDMI-A-9"}}}'), live_of(w))
    local found
    for _, x in ipairs(pm.warnings) do if x.code == "missing_output" and x.message:find("HDMI%-A%-9") and x.message:find("name is kept") then found = true end end
    check(pm.ok and found, "missing named output is reported")
    check(ctl.begin(pm.token, live_of(w)).ok, "a missing monitor does not block the import")
    local act = pump(ctl, w)
    check(act.ok and w.frame.frame_output_name == "HDMI-A-9", "the name is kept even though the monitor is absent")
    -- empty string clears it explicitly (and only when asked)
    local pe = ctl.preview_import(wrap('{"frame":{"values":{"frame.output-name":""}}}'), live_of(w))
    check(pe.ok and pe.sections.frame.changes[1].to_label == "Follow the focused monitor", "explicit empty name = follow focus")
    local pn = ctl.preview_import(wrap('{"frame":{"values":{"frame.tray":true}}}'), live_of(w))
    check(pn.ok and pn.noop, "a file that does not mention the name never erases it")
    -- widgets warnings
    local cards = '[{"id":1,"out":"GONE-1","kind":1,"sz":1,"x":0,"y":0},{"id":2,"out":"DP-1","kind":99,"sz":1,"x":0,"y":0,"opts":{"mystery":5,"lock":true}},'
        .. '{"id":3,"out":"DP-1","kind":2,"sz":2,"x":300,"y":0},{"id":4,"out":"DP-1","kind":1,"sz":1,"x":0,"y":300,"opts":{"future":"yes"}}]'
    local pw = ctl.preview_import(wrap('{"widgets":{"cards":' .. cards .. '}}'), live_of(w))
    local codes = {}
    for _, x in ipairs(pw.warnings or {}) do codes[x.code] = true end
    check(pw.ok and codes.missing_output and codes.unknown_kind and codes.size_adjusted and codes.unknown_option, "widget reports: monitor, kind, size, options")
    check(pw.sections.widgets.changes[1].added == 4, "widget summary counts")
    -- unknown kind and its options are preserved verbatim in the target
    ctl.begin(pw.token, live_of(w))
    local _, _, journal = pump(ctl, w)
    local kept
    for _, c in ipairs(w.widgets.cards) do if c.kind == 99 then kept = c end end
    check(kept and kept.opts.mystery == 5 and kept.opts.lock == true, "unknown kind and options preserved")
    check(w.widgets.cards[4].opts.future == "yes", "unknown option on a known kind preserved")
    -- local pins
    local w2 = new_world()
    local p2 = ctl.preview_import(wrap('{"pins":{"list":["firefox","kitty","ghostty"]}}'), live_of(w2))
    local c2 = {}
    for _, x in ipairs(p2.warnings) do c2[x.code] = x.message end
    check(c2.local_pins_kept and c2.missing_app and c2.missing_app:find("ghostty"), "window pin kept, missing app reported")
    ctl.begin(p2.token, live_of(w2))
    pump(ctl, w2)
    check(#w2.pins == 4 and w2.pins[4] == "app:zed|/usr/bin/zed --new" and w2.pins[1] == "firefox", "imported pins first, local window pin appended")
    local w3 = new_world(); w3.pins = { "a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "app:z|/z" }
    local p3 = ctl.preview_import(wrap('{"pins":{"list":["1","2","3","4","5","6","7","8","9","10","11"]}}'), live_of(w3))
    check(p3.ok, "preview with overflow")
    local drop
    for _, x in ipairs(p3.warnings) do if x.code == "local_pins_kept" or x.code == "local_pins_dropped" then drop = x.code end end
    check(drop == "local_pins_kept", "one local pin fits the 12th place")
    local w4 = new_world(); w4.pins = { "a", "app:y|/y", "app:z|/z" }
    local p4 = ctl.preview_import(wrap('{"pins":{"default":true}}'), live_of(w4))
    local dropped4
    for _, x in ipairs(p4.warnings) do if x.code == "local_pins_dropped" then dropped4 = true end end
    check(dropped4, "returning to automatic pins warns about window pins")
end

-- ── 6. begin: stale, not ready, selection, journal size ──────────
do
    local ctl = new_ctl()
    local w = new_world()
    w.app.skin = 2; w.frame.bar_style = 1; w.pins = { "firefox" }; w.widgets = { snap = true, cards = {} }
    local p = ctl.preview_import(text0, live_of(w))
    check(p.ok and p.sections.appearance and p.sections.widgets and #p.order == 4, "reviews every section")
    local w_changed = new_world(); w_changed.app.skin = 2; w_changed.app.accent = 3; w_changed.frame.bar_style = 1; w_changed.pins = { "firefox" }; w_changed.widgets = { snap = true, cards = {} }
    local r = ctl.begin(p.token, live_of(w_changed))
    check(not r.ok and r.code == "stale" and r.message:find("Appearance"), "stale review is refused, naming the section")
    check(ctl.begin(p.token, live_of(w)).code == "no_preview", "a refused review is gone")
    local p2 = ctl.preview_import(text0, live_of(w))
    local live2 = live_of(w); live2.widgets = nil
    local r2 = ctl.begin(p2.token, live2)
    check(not r2.ok and r2.code == "not_ready" and r2.message:find("Nothing was changed"), "an owner that cannot answer blocks the apply")
    local wc = new_world(); wc.widgets.cards[1].x = 99
    local p2b = ctl.preview_import(text0, live_of(wc))
    local lossy = live_of(wc); lossy.widgets.cards[4].id = lossy.widgets.cards[1].id
    local rl = ctl.begin(p2b.token, lossy)
    check(not rl.ok and rl.code == "not_ready" and rl.message:find("widgets"), "an unrepresentable current desktop is refused (the previous snapshot must be lossless)")
    local p3 = ctl.preview_import(text0, live_of(w))
    local r3 = ctl.begin(p3.token, live_of(w), { sections = { "frame", "pins" } })
    check(r3.ok and #r3.sections == 2 and r3.sections[1] == "frame" and r3.sections[2] == "pins", "selective apply of two sections")
    local act = pump(ctl, w)
    check(act.ok and #act.applied == 2 and w.app.skin == 2 and #w.widgets.cards == 0, "unselected sections are untouched")
    check(ctl.begin(9999, live_of(w)).code == "no_preview", "unknown token")
    -- journal size is checked before anything happens
    local old = SP.MAX_JOURNAL_BYTES
    SP.MAX_JOURNAL_BYTES = 300
    local wbig = new_world(); wbig.app.skin = 2
    local p4 = ctl.preview_import(text0, live_of(wbig))
    local r4 = ctl.begin(p4.token, live_of(wbig))
    check(not r4.ok and r4.code == "too_large" and ctl.next().kind == "idle", "a journal over the limit refuses before any mutation")
    SP.MAX_JOURNAL_BYTES = old
    -- only one run at a time
    local pw = new_ctl()
    local w5 = diff_world()
    local pp = pw.preview_import(text0, live_of(w5))
    check(pw.begin(pp.token, live_of(w5)).ok, "first begin")
    local pq = pw.preview_import(text0, live_of(w5))
    check(pw.begin(pq.token, live_of(w5)).code == "busy", "a second begin during a run is refused")
end

-- ── 7. the pipeline: journal before mutation, acknowledgements, undo ──
do
    local w = new_world()
    w.app.skin = 2; w.frame.pref_tray = false; w.pins = { "firefox" }; w.widgets = { snap = true, cards = {} }
    local before = new_world()
    before.app.skin = 2; before.frame.pref_tray = false; before.pins = { "firefox" }; before.widgets = { snap = true, cards = {} }
    local ctl = new_ctl()
    local p = ctl.preview_import(text0, live_of(w))
    ctl.begin(p.token, live_of(w))
    local sequence, texts = {}, {}
    local first = ctl.next()
    check(first.kind == "persist" and first.journal_id, "the first action is the journal")
    local j1 = decode(first.text)
    check(j1.state == "prepared" and #j1.steps == 4 and j1.steps[1].state == "pending", "journal is prepared with every step pending")
    for i, st in ipairs(j1.steps) do
        check(st.before and st.target and st.before_fp and st.target_fp, "previous snapshot and target of step " .. i .. " are in the first journal")
    end
    check(j1.steps[1].before.palette and j1.steps[1].before.palette.style == 0, "the appearance snapshot carries the colour cache for restoring")
    check(ctl.next().kind == "wait" and ctl.next().reason == "persist", "nothing proceeds before the journal is on disk")
    ctl.persisted(first.seq, true)
    local a1 = ctl.next()
    check(a1.kind == "persist", "step 'sent' is persisted BEFORE the owner is asked")
    check(decode(a1.text).steps[1].state == "sent" and decode(a1.text).state == "running", "journal says sent")
    ctl.persisted(a1.seq, true)
    local req = ctl.next()
    check(req.kind == "apply" and req.section == "appearance" and req.owner == "settings" and req.op == "apply" and req.expect == j1.steps[1].before_fp, "apply request carries compare-and-swap")
    check(req.data.values["appearance.mode"] == 1 and req.text:find("appearance.mode"), "request carries data and its JSON text")
    check(ctl.next().kind == "wait" and ctl.next().reason == "owner", "waits for the owner")
    check(not ctl.ack("bogus", { ok = true }).ok, "an answer for another request is ignored")
    -- complete the rest through the pump with a recording journal
    ctl.ack(req.request, owner_apply(w, req))
    local act, log, journal = pump(ctl, w)
    check(act.kind == "finish" and act.ok, "finished")
    check(decode(journal).state == "done" and decode(journal).steps[4].state == "applied", "final journal is done")
    local order = {}
    for _, e in ipairs(log) do if e:find("^apply:") then order[#order + 1] = e end end
    check(table.concat(order, ",") == "apply:frame,apply:pins,apply:widgets", "sections applied in order")
    check(w.widgets.cards[2].stack.id == 1 and w.widgets.cards[2].stack.on, "stack metadata reached the owner")
    check(act.undo_available and ctl.status().undo_available, "undo is available")
    -- undo
    local u = ctl.undo(live_of(w))
    check(u.ok and u.sections[1] == "widgets" and u.sections[4] == "appearance", "undo runs in reverse order")
    local uact = pump(ctl, w)
    check(uact.ok and uact.code == "undone", "undone")
    check(SP.fingerprint("widgets", SP.snapshot("widgets", live_of(w).widgets)) == SP.fingerprint("widgets", SP.snapshot("widgets", live_of(before).widgets)), "widgets restored")
    check(w.pins[1] == "firefox" and #w.pins == 1 and w.app.skin == 2 and w.frame.pref_tray == false, "everything restored")
    check(not ctl.status().undo_available and ctl.undo(live_of(w)).code == "none", "undo is one-shot")
end

-- ── 8. failures: rollback ────────────────────────────────────────
do
    -- nack in the middle: earlier sections are put back, the failed one is rolled back too
    local w = new_world()
    w.app.skin = 2; w.frame.pref_tray = false; w.pins = { "firefox" }
    local snap = new_world(); snap.app.skin = 2; snap.frame.pref_tray = false; snap.pins = { "firefox" }
    local ctl = new_ctl()
    local p = ctl.preview_import(text0, live_of(w))
    ctl.begin(p.token, live_of(w))
    local act, log = pump(ctl, w, { owner = function(a) if a.section == "pins" and a.op == "apply" then return { ok = false, untouched = false, code = "io", message = "disk full" } end end })
    check(act.kind == "finish" and not act.ok and act.code == "io" and act.rolled_back_all, "failed apply reports and rolls back")
    local rb = {}
    for _, e in ipairs(log) do if e:find("^rollback:") then rb[#rb + 1] = e end end
    check(table.concat(rb, ",") == "rollback:pins,rollback:frame,rollback:appearance", "failed + applied steps rolled back in reverse order")
    check(w.app.skin == 2 and w.app.appearance == 1 and w.frame.pref_tray == false and w.pins[1] == "firefox" and #w.widgets.cards == 4, "world restored")
    check(w.palette.src == "#336699", "colour cache restored")
    check(table.concat(act.rolled_back, ",") == "appearance,frame,pins", "finish lists what was rolled back")
    check(not ctl.status().undo_available, "a failed apply leaves no undo")

    -- an owner that refuses untouched (stale) is not rolled back; the others are
    local w2 = diff_world()
    local c2 = new_ctl()
    local p2 = c2.preview_import(text0, live_of(w2))
    c2.begin(p2.token, live_of(w2))
    local act2, log2 = pump(c2, w2, { owner = function(a) if a.section == "pins" then return { ok = false, untouched = true, code = "stale" } end end })
    check(not act2.ok and act2.code == "stale" and act2.message:find("changed while"), "stale owner answer surfaces")
    local pins_rb = false
    for _, e in ipairs(log2) do if e == "rollback:pins" then pins_rb = true end end
    check(not pins_rb and w2.pins[1] == "firefox", "an untouched section is not rolled back")

    -- timeout: the step state is unknown, so it IS rolled back; a late apply cannot undo the rollback
    local w3 = diff_world()
    local c3 = new_ctl()
    local p3 = c3.preview_import(text0, live_of(w3))
    c3.begin(p3.token, live_of(w3))
    local act3, log3 = pump(c3, w3, { late_apply = true, owner = function(a) if a.section == "frame" and a.op == "apply" then return "timeout" end end })
    local sawfr = false
    for _, e in ipairs(log3) do if e == "rollback:frame" then sawfr = true end end
    check(not act3.ok and act3.code == "timeout" and sawfr, "a timed-out step is rolled back")
    check(w3.frame.bar_style == 1 and w3.app.skin == 2 and w3.pins[1] == "firefox", "a timed-out apply that did land is undone by the forced rollback")
    check(not c3.ack("x", { ok = true }).ok, "late answers after a timeout are ignored")

    -- coordinator-side compare-and-swap between steps
    local w4 = diff_world()
    local c4 = new_ctl()
    local p4 = c4.preview_import(text0, live_of(w4))
    c4.begin(p4.token, live_of(w4))
    local n = 0
    local act4 = pump(c4, w4, { live_each_step = true, owner = function(a)
        n = n + 1
        if n == 1 then
            local res = owner_apply(w4, a)
            w4.pins = { "someone-else" }          -- the user changes pins while the setup runs
            return res
        end
    end })
    check(not act4.ok and act4.code == "stale" and w4.pins[1] == "someone-else" and w4.app.skin == 2 and w4.app.appearance == 1, "a change during the run stops it and rolls back what had been applied; the concurrent change survives")
end

-- ── 9. rollback failure surfaced, retry, abandon ─────────────────
do
    local function scene()
        local w = diff_world()
        local ctl = new_ctl()
        local p = ctl.preview_import(text0, live_of(w))
        ctl.begin(p.token, live_of(w))
        return w, ctl
    end
    local w, ctl = scene()
    local broken = true
    local act = pump(ctl, w, { owner = function(a)
        if a.section == "pins" and a.op == "apply" then return { ok = false, code = "io" } end
        if a.section == "frame" and a.op == "rollback" and broken then return { ok = false, code = "io", message = "read-only" } end
    end })
    check(act.kind == "finish" and not act.ok and act.code == "rollback_failed", "rollback failure is surfaced")
    check(#act.needs_attention == 1 and act.needs_attention[1].section == "frame" and act.needs_attention[1].owner == "settings" and act.needs_attention[1].message:find("read%-only"), "names the section that needs attention")
    check(w.app.appearance == 1 and w.app.skin == 2, "the other sections were still restored (best effort)")
    check(ctl.status().state == "rollback_failed" and ctl.begin(1, live_of(w)).code == "busy", "the run stays until resolved")
    broken = false
    check(ctl.retry_rollback().ok, "retry")
    local act2 = pump(ctl, w, { owner = function(a) if a.op == "apply" then return { ok = false } end end })
    check(act2.kind == "finish" and act2.ok == false and act2.code ~= "rollback_failed" and w.frame.pref_tray == true, "retry restores the failed section")
    check(ctl.status().state == "rolled_back", "journal ends rolled_back")
    -- abandon
    local w2, c2 = scene()
    pump(c2, w2, { owner = function(a)
        if a.section == "pins" and a.op == "apply" then return { ok = false, code = "io" } end
        if a.op == "rollback" and a.section == "frame" then return { ok = false, code = "io" } end
    end })
    check(c2.abandon().ok, "abandon")
    local fin, _, journal = pump(c2, w2)
    check(fin.kind == "finish" and fin.code == "abandoned" and decode(journal).state == "abandoned", "abandoned is journalled")
    check(c2.abandon().code == "none", "nothing more to accept")
end

-- ── 10. journal write failures ───────────────────────────────────
do
    local w = diff_world()
    local ctl = new_ctl()
    local p = ctl.preview_import(text0, live_of(w))
    ctl.begin(p.token, live_of(w))
    local act, log = pump(ctl, w, { persist = function() return false end })
    check(act.kind == "idle" and #log == 1, "first journal write fails: the run is dropped")
    check(w.app.skin == 2 and #w.widgets.cards == 1 and w.frame.bar_style == 1 and ctl.status().message:find("journal"), "nothing was touched")
    check(ctl.begin(ctl.preview_import(text0, live_of(w)).token, live_of(w)).ok, "a new run can start after the dropped one")
    -- a later failure blocks: no owner is asked, retry continues
    local w2 = diff_world()
    local c2 = new_ctl()
    local p2 = c2.preview_import(text0, live_of(w2))
    c2.begin(p2.token, live_of(w2))
    local asked = 0
    local act2 = pump(c2, w2, { persist = function(_, _, n) return n ~= 2 end, owner = function() asked = asked + 1 end })
    check(act2.kind == "wait" and act2.reason == "blocked" and asked == 0, "journal write failure blocks before the first owner is asked")
    check(c2.status().state == "blocked" and c2.status().blocked.code == "journal_write", "status says blocked")
    check(c2.retry(), "retry")
    local act3 = pump(c2, w2)
    check(act3.kind == "finish" and act3.ok, "continues after the journal is writable again")
    -- failure to persist an acknowledgement: blocks; the journal on disk still says 'sent'
    local w3 = diff_world()
    local c3 = new_ctl()
    local p3 = c3.preview_import(text0, live_of(w3))
    c3.begin(p3.token, live_of(w3))
    local disk
    local act4 = pump(c3, w3, { persist = function(_, text, n) if n == 3 then return false end disk = text return true end })
    check(act4.reason == "blocked" and decode(disk).steps[1].state == "sent", "the journal on disk still names the step as in flight")
end

-- ── 11. restart reconciliation ───────────────────────────────────
local function crashed_run(apply_before_crash, partial)
    local w = diff_world()
    local before = copy(w)
    local ctl = new_ctl()
    local p = ctl.preview_import(text0, live_of(w))
    ctl.begin(p.token, live_of(w))
    local n = 0
    local act, _, disk = pump(ctl, w, { owner = function(a)
        n = n + 1
        if n == 2 then
            if apply_before_crash then owner_apply(w, a) end
            if partial then w.frame.pref_tray = false; w.frame.frame_output_name = "ZZ-9" end   -- only part of it landed
            return "crash"
        end
    end })
    check(act.kind == "crashed" and decode(disk).steps[2].state == "sent", "the journal on disk names the step in flight")
    return w, before, disk
end

do
    -- (a) the owner never executed the step
    local w, _, disk = crashed_run(false)
    local ctl = new_ctl()                       -- a restarted controller
    local r = ctl.reconcile(disk, live_of(w))
    check(r.ok and r.status == "needs_recovery" and not r.nothing_changed, "needs recovery")
    local actual = {}
    for _, s in ipairs(r.steps) do actual[s.section] = s.actual end
    check(actual.appearance == "applied" and actual.frame == "untouched" and actual.pins == "untouched" and actual.widgets == "untouched", "per-section reality")
    check(ctl.status().state == "needs_recovery", "status")
    check(ctl.recover("rollback", live_of(w)).ok, "recover")
    local act, log = pump(ctl, w)
    local rb = {}
    for _, e in ipairs(log) do if e:find("^rollback") then rb[#rb + 1] = e end end
    check(act.ok and act.code == "recovered" and table.concat(rb, ",") == "rollback:appearance", "only what reached an owner is rolled back")
    check(w.app.appearance == 1 and w.app.skin == 2 and w.palette.src == "#336699", "restored")
end
do
    -- (b) executed, ack lost
    local w, _, disk = crashed_run(true)
    local ctl = new_ctl()
    local r = ctl.reconcile(disk, live_of(w))
    local actual = {}
    for _, s in ipairs(r.steps) do actual[s.section] = s.actual end
    check(actual.appearance == "applied" and actual.frame == "untouched" or actual.frame == "applied", "executed step is recognised")
    ctl.recover("rollback", live_of(w))
    local act = pump(ctl, w)
    check(act.ok and w.frame.bar_style == 1 and w.app.skin == 2 and w.pins[1] == "firefox", "recovered to the previous snapshot")
end
do
    -- (c) diverged: neither before nor target
    local w, _, disk = crashed_run(false, true)
    local ctl = new_ctl()
    local r = ctl.reconcile(disk, live_of(w))
    local actual = {}
    for _, s in ipairs(r.steps) do actual[s.section] = s.actual end
    check(actual.frame == "diverged", "a half-applied section is reported as diverged")
    ctl.recover("rollback", live_of(w))
    local act = pump(ctl, w)
    check(act.ok and w.frame.bar_style == 1 and w.frame.pref_tray == true and w.frame.frame_output_name == "", "diverged section restored to its previous snapshot")
end
do
    -- keep
    local w, _, disk = crashed_run(true)
    local ctl = new_ctl()
    ctl.reconcile(disk, live_of(w))
    check(ctl.recover("keep", live_of(w)).ok, "keep")
    local act, _, journal = pump(ctl, w)
    check(act.kind == "finish" and act.code == "kept" and decode(journal).state == "abandoned", "kept and journalled as abandoned")
    check(w.app.skin == 0 and w.pins[1] == "firefox", "keep leaves the current state exactly as it is")
    check(ctl.status().state ~= "needs_recovery", "recovery closed")
    local again = new_ctl().reconcile(journal, live_of(w))
    check(again.status == "complete", "an abandoned journal is not offered again")
end
do
    -- waiting for an owner that has not started yet
    local w, _, disk = crashed_run(true)
    local ctl = new_ctl()
    local live = live_of(w); live.frame = nil
    local r = ctl.reconcile(disk, live)
    check(r.status == "needs_live" and r.waiting_for[1] == "frame", "asks again when the owner answers")
    local live_pending = live_of(w); live_pending.widgets = nil
    check(new_ctl().reconcile(disk, live_pending).status == "needs_recovery", "a step that was never sent does not need its owner")
    check(ctl.recover("rollback", live).code == "none", "no decision before the journal can be checked")
    check(ctl.reconcile(disk, live_of(w)).status == "needs_recovery", "then it can be checked")
end
do
    -- nothing reached an owner (crash while only the first persist happened)
    local w = diff_world()
    local ctl = new_ctl()
    local p = ctl.preview_import(text0, live_of(w))
    ctl.begin(p.token, live_of(w))
    local first = ctl.next()
    local r = new_ctl().reconcile(first.text, live_of(w))
    check(r.status == "needs_recovery" and r.nothing_changed, "a prepared journal changed nothing")
    local c = new_ctl()
    c.reconcile(first.text, live_of(w))
    check(c.recover("rollback", live_of(w)).ok, "it only closes")
    local fin = pump(c, w)
    check(fin.kind == "finish" and fin.code == "kept", "closed without touching owners")
end
do
    -- unreadable / hostile journals
    local ctl = new_ctl()
    for _, text in ipairs({ "", "nonsense", "[]", '{"kind":"x"}', '{"kind":"beskar.setup-journal","version":9}',
        '{"kind":"beskar.setup-journal","version":1,"id":"a b","op":"apply","state":"running","steps":[]}',
        '{"kind":"beskar.setup-journal","version":1,"id":"a","op":"apply","state":"running","steps":[{"section":"pins","state":"sent","before":{"list":["a\\nb"]},"target":{"default":true}}]}' }) do
        local r = ctl.reconcile(text, live_of(new_world()))
        check(not r.ok and r.status == "unreadable", "rejects " .. text:sub(1, 30))
    end
end
do
    -- a finished apply offers undo after a restart; a changed section blocks it unless skip_stale
    local w = diff_world()
    local ctl = new_ctl()
    local p = ctl.preview_import(text0, live_of(w))
    ctl.begin(p.token, live_of(w))
    local _, _, disk = pump(ctl, w)
    check(decode(disk).state == "done", "done journal")
    local restarted = new_ctl()
    local r = restarted.reconcile(disk, live_of(w))
    check(r.status == "complete" and r.undo_available and restarted.status().undo_available, "undo survives a restart")
    w.pins = { "changed-afterwards" }
    local u = restarted.undo(live_of(w))
    check(not u.ok and u.code == "stale" and u.message:find("Pinned apps") and u.stale[1] == "Pinned apps", "undo refuses to overwrite later changes")
    local u2 = restarted.undo(live_of(w), { skip_stale = true })
    check(u2.ok and #u2.sections == 3 and u2.skipped[1] == "Pinned apps", "skip_stale undoes the rest")
    local fin = pump(restarted, w)
    check(fin.ok and w.pins[1] == "changed-afterwards" and w.app.appearance == 1 and w.app.skin == 2 and #w.widgets.cards == 1 and w.frame.bar_style == 1, "pins left alone, others restored")
    check(fin.message:find("Pinned apps"), "says what was left")
end

-- ── 12. helpers owners use ───────────────────────────────────────
do
    local a = SP.snapshot("widgets", { ready = true, snap = true, cards = { { id = 1, out = "A", kind = 1, sz = 1, x = 1, y = 2 }, { id = 2, out = "A", kind = 5, sz = 1, x = 9, y = 2 } } })
    local b = SP.snapshot("widgets", { ready = true, snap = true, cards = { { id = 77, out = "A", kind = 5, sz = 1, x = 9, y = 2 }, { id = 3, out = "A", kind = 1, sz = 1, x = 1, y = 2 } } })
    check(SP.fingerprint("widgets", a) == SP.fingerprint("widgets", b), "fingerprints ignore card ids and order")
    b.cards[1].x = 10
    check(SP.fingerprint("widgets", a) ~= SP.fingerprint("widgets", b), "and see a moved card")
    check(SP.fingerprint("widgets", a):match("^%x+:%d+$"), "fingerprint format")
    check(SP.snapshot("widgets", { ready = false }) == nil, "not ready widgets have no snapshot")
    local d, errs = SP.validate_section("pins", { list = { "app:x|y" } })
    check(d == nil and errs[1].code == "value", "owners re-validate strictly")
    check(SP.validate_section("pins", { list = { "app:x|y" } }, { local_pins = true }), "local pins are allowed in local mode")
    local f = SP.to_facts("frame", { values = { ["frame.output-name"] = "DP-1", ["frame.dock-show-delay"] = 2 } })
    check(f.frame_output_name == "DP-1" and f.dock_show_delay == 2, "facts for Settings")
    check(SP.validate_section("frame", { values = { ["frame.output-name"] = "x y" } }) == nil, "text field validated")
end

-- ── 13. purity ───────────────────────────────────────────────────
do
    local f = assert(io.open("shell/setup_profiles.luau"))
    local src = f:read("a"); f:close()
    local code = src:gsub("%-%-[^\n]*", ""):gsub("%[=%[.-%]=%]", "")
    for _, banned in ipairs({ "io%.", "os%.", "spawn", "sys%.", "timer%.", "%.after%(", "%.every%(", "loadstring", "surface%s*[:=({]",
        "[^%.%w_]run%(", "[^%w_]emit%(", "goto%s", "//", "<<", ">>", "%f[%w_]band%f[^%w_]", "%f[%w_]bxor%f[^%w_]", "debug%." }) do
        check(not code:find(banned), "module does not use " .. banned)
    end
    check(src:find("adapter%.decode"), "decoding goes through the host adapter")
    local sources = io.open("shell/setup_profiles.luau"):read("a")
    check(#sources > 0, "readable")
end

print(string.format("setup-profiles: %d checks passed", passed))
