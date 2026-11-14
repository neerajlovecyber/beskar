-- Run only this suite for the preference schema: lua tests/preferences.lua
package.path = "shell/?.luau;" .. package.path
local P = require("preferences")
local passed = 0
local function check(v, why) assert(v, why); passed = passed + 1 end

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

local function read(kind, text) return P.read(kind, text, decode) end
local function issue_keys(r)
    local k = {}
    for _, x in ipairs(r.issues) do k[#k + 1] = x.key end
    table.sort(k)
    return table.concat(k, ",")
end

-- ── defaults are what Settings starts with ──
local t, p, pal = P.defaults("theme"), P.defaults("prefs"), P.defaults("palette")
check(t.version == 1 and t.dark_mode == true and t.skin == 0 and t.accent == 0 and t.accent_auto == false and t.hour12 == true, "theme defaults")
check(p.appearance == 1 and p.bar_style == 0 and p.seconds == false and p.weather == true and p.tray == true and p.dock_auto == true
    and p.widgets == true and p.apps == true and p.night == 0 and p.night_t == 1 and p.banners == true and p.banner_i == 1
    and p.group == false and p.lock_min == 0, "prefs defaults")
check(pal.style == 0 and pal.src == nil and not P.palette_usable(pal), "palette defaults")
for _, k in ipairs(P.KINDS) do
    local v, issues, info = P.normalize(k, P.defaults(k))
    check(#issues == 0 and not info.legacy and #info.unknown == 0, k .. " defaults normalise cleanly")
end

-- ── missing / unreadable / corrupt are different from an invalid key ──
local r = read("prefs", "")
check(r.status == "missing" and r.writable and r.value.appearance == 1 and P.describe(r) == nil, "blank text is a missing file")
r = read("prefs", "  \n")
check(r.status == "missing", "whitespace is a missing file")
r = P.read("prefs", nil, decode)
check(r.status == "unreadable" and not r.writable and r.value.banner_i == 1 and P.describe(r):find("left as it is"), "nil text is unreadable and not writable")
for _, bad in ipairs({ "{", '{"appearance": 2', "not json", "[1,2]", '"text"', "42", "null", '{"a": }' }) do
    r = read("prefs", bad)
    check(r.status == "corrupt" and not r.writable and r.value.appearance == 1, "corrupt: " .. bad)
end
check(P.describe(read("theme", "{")):find("pleamar_shell.json") and P.describe(read("theme", "{")):find("repaired or moved aside"), "corrupt recovery message names the file")
r = P.read("prefs", "\239\187\191" .. '{"appearance": 0}', decode)
check(r.status == "ok" and r.value.appearance == 0, "UTF-8 BOM is tolerated")
check(not pcall(P.read, "prefs", "{}"), "a decode function is required")
check(not pcall(P.defaults, "nope"), "unknown kind is a programming error")

-- ── legacy, unversioned documents ──
r = read("theme", '{"dark_mode": false, "skin": 2}')   -- what start.sh itself writes
check(r.status == "ok" and r.legacy and r.writable and r.value.dark_mode == false and r.value.skin == 2 and r.value.accent == 0
    and r.value.hour12 == true and r.value.version == 1 and #r.issues == 0, "partial legacy theme keeps choices, defaults the rest")
r = read("theme", '{"dark_mode": true, "skin": 1, "accent": 5, "accent_auto": true, "hour12": false}')
check(r.value.accent == 5 and r.value.accent_auto == true and r.value.hour12 == false and r.value.skin == 1, "full legacy theme")
r = read("prefs", '{"appearance": 2, "bar_style": 1, "seconds": true, "weather": false, "tray": false, "dock_auto": false, "widgets": false, "apps": false, "night": 2, "night_t": 2, "banners": false, "banner_i": 3, "group": true, "lock_min": 15}')
check(r.legacy and #r.issues == 0 and r.value.appearance == 2 and r.value.bar_style == 1 and r.value.seconds == true and r.value.weather == false
    and r.value.tray == false and r.value.dock_auto == false and r.value.widgets == false and r.value.apps == false and r.value.night == 2
    and r.value.night_t == 2 and r.value.banners == false and r.value.banner_i == 3 and r.value.group == true and r.value.lock_min == 15, "full legacy prefs")
r = read("theme", "{}")
check(r.status == "ok" and r.legacy and r.value.skin == 0, "empty object is a legacy document of defaults")
-- numbers written by the old code as strings or floats still load
r = read("prefs", '{"appearance": "0", "banner_i": 2.0, "night": " 1 "}')
check(#r.issues == 0 and r.value.appearance == 0 and r.value.banner_i == 2 and r.value.night == 1, "numeric strings and integral floats are accepted")
-- the old booleans were `== true`; 1 / 0 and "true" / "false" are read as what they obviously mean
r = read("prefs", '{"seconds": 1, "weather": 0, "tray": "false"}')
check(r.value.seconds == true and r.value.weather == false and r.value.tray == false and #r.issues == 0, "boolean spellings")

-- ── invalid individual keys: defaults + issues, the rest survives ──
r = read("prefs", '{"appearance": 7, "bar_style": 1.5, "seconds": "yes", "banner_i": -1, "lock_min": 7, "night": [], "tray": false, "group": true}')
check(r.status == "ok" and r.writable, "invalid keys do not make the document corrupt")
check(r.value.appearance == 1 and r.value.bar_style == 0 and r.value.seconds == false and r.value.banner_i == 1 and r.value.lock_min == 0 and r.value.night == 0,
    "each invalid key falls back to its own default")
check(r.value.tray == false and r.value.group == true, "valid neighbours are kept")
check(issue_keys(r) == "appearance,banner_i,bar_style,lock_min,night,seconds", "issues name the keys: " .. issue_keys(r))
for _, x in ipairs(r.issues) do check(x.problem == "type" or x.problem == "range", "problem kind") end
check(P.describe(r):find("^6 invalid values") ~= nil, "notice counts invalid values")
r = read("theme", '{"skin": 3, "accent": 7, "dark_mode": "dark", "accent_auto": 2, "hour12": null}')
check(r.value.skin == 0 and r.value.accent == 0 and r.value.dark_mode == true and r.value.accent_auto == false and r.value.hour12 == true, "theme out-of-range / wrong types")
check(issue_keys(r) == "accent,accent_auto,dark_mode,skin", "null is simply absent: " .. issue_keys(r))
for _, big in ipairs({ "1e400", "1e30", "-3" }) do
    check(read("theme", '{"skin": ' .. big .. "}").value.skin == 0, "huge / negative enum " .. big)
end
r = read("prefs", '{"appearance": 1}')
check(P.describe(r) == nil, "no notice when nothing is wrong")

-- ── versions ──
r = read("theme", '{"version": 1, "skin": 1}')
check(not r.legacy and r.status == "ok" and r.value.skin == 1, "current version")
r = read("theme", '{"version": "x", "skin": 1}')
check(r.legacy and r.status == "ok" and issue_keys(r) == "version" and r.value.version == 1, "bad version reads as legacy")
r = read("theme", '{"version": 0}')
check(r.legacy and issue_keys(r) == "version", "version 0 is invalid")
r = read("theme", '{"version": 2, "skin": 1, "accent": 99, "newthing": {"x": 1}}')
check(r.status == "newer" and not r.writable and r.value.skin == 1 and r.value.accent == 0 and r.value.version == 2 and r.value.newthing.x == 1, "newer document: normalised, preserved, not writable")
check(P.describe(r):find("newer"), "newer notice")

-- ── unknown keys survive normalisation and encoding ──
r = read("prefs", '{"appearance": 0, "zz_future_size": 48, "future": {"list": [1, 2, {"deep": true}], "name": "it\'s \\"x\\""}, "tags": ["a", "b"]}')
check(r.value.zz_future_size == 48 and r.value.future.list[3].deep == true and r.value.tags[2] == "b", "unknown keys kept")
check(table.concat(r.unknown, ",") == "future,tags,zz_future_size", "unknown names sorted")
local text = P.encode("prefs", r.value)
check(not text:find("'") and text:find('"future": {"list": [1, 2, {"deep": true}]', 1, true), "encoded unknown keys, apostrophe escaped")
local back = read("prefs", text)
check(back.status == "ok" and not back.legacy and #back.issues == 0 and back.value.future.name == "it's \"x\"", "round trip")
check(back.value.future.list[3].deep == true and back.value.zz_future_size == 48 and back.value.appearance == 0, "round trip keeps values")
-- unknown values that cannot be JSON are dropped, and said so
r = P.normalize("prefs", { appearance = 1, weird = function() end, nan = 0 / 0, ok = "fine" })
local _, iss = P.normalize("prefs", { weird = function() end, nan = 0 / 0 })
check(#iss == 2 and r.ok == "fine" and r.weird == nil, "unsupported unknown values dropped with issues")

-- ── encoding shape: one line, legacy greps still work ──
text = P.encode("theme", { dark_mode = false, skin = 2, accent = 4, accent_auto = true, hour12 = false })
check(not text:find("\n") and text:find('"version": 1', 1, true), "single line, versioned")
check(text:match('"dark_mode": *(%a*)') == "false" and text:match('"skin": *(%d*)') == "2" and text:match('"accent": *(%d*)') == "4"
    and text:match('"accent_auto": *(%a*)') == "true" and text:match('"hour12": *(%a*)') == "false", "start.sh grep patterns still match")
text = P.encode("prefs", P.defaults("prefs"))
check(text:match('"night": *(%d*)') == "0" and text:match('"night_t": *(%d*)') == "1" and text:match('"lock_min": *(%d*)') == "0", "prefs greps still match")
local enc_text, enc_issues = P.encode("prefs", { appearance = 9, seconds = true })
check(#enc_issues == 1 and read("prefs", enc_text).value.appearance == 1 and read("prefs", enc_text).value.seconds == true, "encode never writes an invalid value")
for _, k in ipairs(P.KINDS) do
    local a = P.encode(k, P.defaults(k))
    check(a == P.encode(k, read(k, a).value), k .. " encoding is deterministic and stable")
end

-- ── palette ──
local good = '{"style": 2, "src": "#AABBCC", "dark": {"a": "#112233", "b": "#445566", "s": "#778899"}, "light": {"a": "#ffffff", "b": "#eeeeee", "s": "#dddddd"}}'
r = read("palette", good)
check(r.status == "ok" and r.legacy and r.value.style == 2 and r.value.src == "#aabbcc" and P.palette_usable(r.value) and r.value.dark.a == "#112233", "legacy palette")
r = read("palette", '{"style": 1, "dark": {"a": "#112233", "b": "red", "s": "#778899"}, "light": {"a": "#ffffff", "b": "#eeeeee", "s": "#dddddd"}, "src": 5}')
check(r.value.style == 1 and r.value.dark == nil and r.value.light ~= nil and r.value.src == nil and not P.palette_usable(r.value) and issue_keys(r) == "dark,src",
    "a bad colour set / source is dropped, not the whole palette: " .. issue_keys(r))
r = read("palette", '{"style": 3}')
check(r.value.style == 3 and not P.palette_usable(r.value), "a style-only palette is valid (the style fact has no other home)")
text = P.encode("palette", read("palette", good).value)
r = read("palette", text)
check(r.value.src == "#aabbcc" and r.value.light.s == "#dddddd" and r.value.style == 2 and not r.legacy, "palette round trip")
check(P.encode("palette", { style = 1 }):find("dark") == nil, "no colours invented for a style-only palette")

-- ── facts <-> documents ──
local facts = P.to_facts("prefs", P.normalize("prefs", { lock_min = 10, seconds = true, night = 2 }))
check(facts.lock_i == 3 and facts.pref_seconds == true and facts.nl_mode_i == 2 and facts.nl_temp_i == 1 and facts.group_apps == false and facts.pref_dock_auto == true, "prefs -> facts (lock index)")
check(P.to_facts("theme", P.defaults("theme")).dark_mode == true and P.to_facts("palette", { style = 3 }).pal_style == 3, "theme / palette -> facts")
local base = read("prefs", '{"seconds": true, "future": 1, "lock_min": 5}').value
local out, fissues = P.from_facts("prefs", { lock_i = 4, pref_tray = false, banner_i = 9 }, base)
check(out.lock_min == 15 and out.tray == false and out.seconds == true and out.future == 1 and out.banner_i == 1, "facts -> prefs keeps base, unknown keys and unnamed facts")
check(#fissues == 1 and fissues[1].key == "banner_i", "an invalid fact is reported, base value kept")
out = P.from_facts("prefs", { lock_i = 99 }, base)
check(out.lock_min == 5, "bad lock index leaves the base")
out = P.from_facts("palette", { pal_style = 1 }, read("palette", good).value)
check(out.style == 1 and P.palette_usable(out) and out.src == "#aabbcc", "style change keeps the cached colours")
out = P.from_facts("theme", {})
check(out.skin == 0 and out.version == 1, "no base, no facts: defaults")
check(P.from_facts("theme", { accent_auto = false, hour12 = false }, { accent_auto = true }).accent_auto == false, "false facts are applied")

-- ── Appearance snapshot / reset / undo ──
check(#P.APPEARANCE == 9 and P.APPEARANCE[1].fact == "appearance" and P.APPEARANCE[5].fact == "pal_style", "appearance preserves original members and adds validated style choices")
do
    local chosen = P.appearance_snapshot({custom_accent=16777215,style_text=2,style_glass=0,reduce_motion=true})
    local defaults = P.appearance_defaults()
    local plan = P.appearance_plan(chosen,defaults)
    check(#plan.changes==4 and plan.values.custom_accent==-1 and plan.values.style_glass==2,
        "Appearance restore includes the custom accent, text, glass and motion choices")
    local undo = P.appearance_plan(defaults,chosen)
    check(undo.values.custom_accent==16777215 and undo.values.style_text==2 and undo.values.reduce_motion==true,
        "Appearance undo restores supported style choices together")
    local valid = P.normalize("theme",{custom_accent=0,style_text=0,style_glass=2})
    check(valid.custom_accent==0 and valid.style_text==0,"black is a valid source colour; contrast adaptation stays derived")
    local invalid = P.normalize("theme",{custom_accent=16777216,style_text=1.5,style_glass=-1})
    check(invalid.custom_accent==-1 and invalid.style_text==1 and invalid.style_glass==2,"invalid style values fall back within bounds")
end
for _, a in ipairs(P.APPEARANCE) do check(a.id:find("^appearance%.") ~= nil, "stable id " .. a.id) end
local defaults = P.appearance_defaults()
check(defaults.values.appearance == 1 and defaults.values.skin == 0 and defaults.values.accent == 0 and defaults.values.accent_auto == false and defaults.values.pal_style == 0 and defaults.palette == nil, "appearance defaults")
local palette = read("palette", good).value
local mine = P.appearance_snapshot({ appearance = 2, skin = 1, accent = 3, accent_auto = true, pal_style = 2, hour12 = false, pref_apps = false }, palette)
check(mine.values.appearance == 2 and mine.values.accent_auto == true and mine.values.hour12 == nil and mine.values.pref_apps == nil, "snapshot holds only appearance values")
check(mine.palette and mine.palette.dark.a == "#112233" and mine.palette ~= palette and mine.palette.dark ~= palette.dark, "snapshot palette is a copy")
palette.dark.a = "#000000"
check(mine.palette.dark.a == "#112233", "later palette changes do not alter the snapshot")
check(P.appearance_snapshot({ skin = "x", accent = 50 }).values.skin == 0 and P.appearance_snapshot({ accent_auto = false }).values.accent_auto == false, "snapshot validates facts")
check(P.appearance_snapshot({}, { style = 1 }).palette == nil, "an unusable palette is not snapshotted")

local reset = P.appearance_plan(mine, defaults)
check(not reset.noop and #reset.changes == 5 and reset.restore_palette == nil, "reset plans every differing value and leaves the palette alone")
local c1 = reset.changes[1]
check(c1.id == "appearance.mode" and c1.fact == "appearance" and c1.from == 2 and c1.to == 1 and c1.from_label == "Auto" and c1.to_label == "Dark" and c1.label == "Appearance", "change entry for the review")
local by = {}
for _, c in ipairs(reset.changes) do by[c.fact] = c end
check(by.accent_auto.from_label == "On" and by.accent_auto.to_label == "Off" and by.accent.from_label == "Red" and by.skin.to_label == "Liquid Glass" and by.pal_style.from_label == "Neutral", "review labels")
check(reset.values.skin == 0 and reset.values.accent_auto == false, "reset values are the defaults")
check(P.appearance_plan(defaults, defaults).noop, "resetting defaults is a no-op")
local only = P.appearance_plan({ values = { appearance = 1, skin = 0, accent = 0, accent_auto = false, pal_style = 0 } }, { values = { accent = 4 } })
check(#only.changes == 1 and only.changes[1].fact == "accent" and only.values.accent == 4 and only.values.skin == 0, "only differing values are listed; missing target values default")

-- undo: the snapshot taken before the reset restores manual/auto choice, values and colours
local after_reset = P.appearance_snapshot(reset.values, nil)   -- accent_auto is off after the reset
local undo = P.appearance_plan(after_reset, mine)
check(#undo.changes == 5 and undo.values.accent_auto == true and undo.values.accent == 3 and undo.values.pal_style == 2 and undo.values.appearance == 2, "undo restores every value, auto accent included")
check(undo.restore_palette and undo.restore_palette.light.s == "#dddddd" and undo.restore_palette.src == "#aabbcc", "undo restores the displayed colours")
local re = P.appearance_plan(mine, mine)
check(re.noop and re.restore_palette == nil, "undo of an unchanged state is a no-op")
check(P.snapshot_equal(mine, P.appearance_snapshot(mine.values, mine.palette)) and not P.snapshot_equal(mine, defaults), "snapshot_equal")
check(not P.snapshot_equal(mine, nil), "snapshot_equal tolerates nil")
check(P.appearance_plan(nil, nil).noop, "plans tolerate nil")

-- recovery name
check(P.recovery_name("prefs", "20261114T1015") == "prefs.json.corrupt-20261114T1015", "recovery name")
check(P.recovery_name("palette", "a/b c") == "palette.json.corrupt-abc" and P.recovery_name("prefs"):find("corrupt%-backup$"), "recovery name is a safe basename")

print(string.format("preferences: %d checks passed", passed))
