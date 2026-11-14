-- Run only this suite for the style options (C2b/c): lua tests/style-options.lua
package.path = "shell/?.luau;" .. package.path
local S = require("style_options")
local passed = 0
local function check(v, why) assert(v, why); passed = passed + 1 end
local function eq(a, b, why) assert(a == b, (why or "") .. " expected " .. tostring(b) .. " got " .. tostring(a)); passed = passed + 1 end
local function near(a, b, tol, why) assert(math.abs(a - b) <= tol, (why or "") .. " expected ~" .. tostring(b) .. " got " .. tostring(a)); passed = passed + 1 end
local function read(path)
    local f = assert(io.open(path, "r"))
    local s = f:read("*a")
    f:close()
    return s
end

-- ── hex parsing ──────────────────────────────────────────────────────
local r, g, b = S.parse_hex("#0A84ff")
check(r == 10 and g == 132 and b == 255, "mixed case")
r, g, b = S.parse_hex("  0a84ff \n")
check(r == 10 and g == 132 and b == 255, "no hash, whitespace trimmed")
r, g, b = S.parse_hex("#fa0")
check(r == 255 and g == 170 and b == 0, "short form doubles each digit")
for bad, why in pairs({ [""] = "empty", ["   "] = "empty", ["#12345"] = "length", ["#1234567"] = "length", ["#gg0000"] = "not_hex",
    ["red"] = "not_hex", ["#"] = "not_hex", ["#ff000080"] = "alpha", ["#f008"] = "alpha", ["rgb(1,2,3)"] = "not_hex" }) do
    local a, reason = S.parse_hex(bad)
    check(a == nil and reason == why, "rejects '" .. bad .. "' as " .. why .. ", got " .. tostring(reason))
end
check(select(2, S.parse_hex(string.rep("a", 40))) == "too_long", "pasted prose is too long")
check(select(2, S.parse_hex(nil)) == "type" and select(2, S.parse_hex(12)) == "type" and select(2, S.parse_hex({})) == "type", "non strings")
eq(S.format_hex(10, 132, 255), "#0a84ff", "format")

-- ── luminance / contrast: the WCAG reference points ──────────────────
near(S.luminance(255, 255, 255), 1, 1e-9, "white")
near(S.luminance(0, 0, 0), 0, 1e-9, "black")
near(S.contrast_ratio(1, 0), 21, 1e-9, "white on black is 21:1")
near(S.contrast_ratio(S.luminance(119, 119, 119), 1), 4.48, 0.02, "#777 on white (the textbook 4.48)")
near(S.contrast_ratio(S.luminance(118, 118, 118), 1), 4.54, 0.02, "#767676 on white (the textbook 4.54)")

-- ── the foreground on an accent ──────────────────────────────────────
local dark = S.foreground(0, 0, 0)
check(dark == false, "white on black accent")
dark = S.foreground(255, 255, 255)
check(dark == true, "dark ink on a white accent")
local d2, ratio = S.foreground(255, 214, 10)   -- yellow
check(d2 == true and ratio > 10, "yellow takes the dark ink")
d2 = S.foreground(0, 122, 255)                 -- #007aff measures ~4.0 with white, ~5.2 with the dark ink
check(d2 == true, "the system blue is under 4.5 with white: the policy picks the better ink")
-- the policy never returns less than ~4.3:1, whatever the colour (sampled over the whole cube)
local worst = 99
for rr = 0, 255, 17 do for gg = 0, 255, 17 do for bb = 0, 255, 17 do
    local _, q = S.foreground(rr, gg, bb)
    worst = math.min(worst, q)
end end end
check(worst > 4.25, "best-of ink is at least 4.25:1 for 4096 sampled colours (worst " .. worst .. ")")
local u = S.foreground_unit(1, 1, 0.04)
check(u == true, "0..1 channels")

-- ── a validated custom accent ────────────────────────────────────────
for _, isdark in ipairs({ true, false }) do
    local a = S.accent("#0a84ff", isdark)
    check(a.ok, "accepts a hex")
    check(a.fg_ratio >= S.MIN_FG and a.surface_ratio >= S.MIN_SURFACE, "blue meets both limits in both modes")
end
-- over the whole sampled cube, in both modes: the result ALWAYS meets 4.5:1 for its foreground and 3:1 for every surface
local adjusted, kept = 0, 0
for _, isdark in ipairs({ true, false }) do
    for rr = 0, 255, 15 do for gg = 0, 255, 15 do for bb = 0, 255, 15 do
        local a = S.accent(S.format_hex(rr, gg, bb), isdark)
        check(a.ok, "every colour resolves")
        check(a.fg_ratio >= S.MIN_FG - 1e-9, "foreground ≥ 4.5:1")
        check(a.surface_ratio >= S.MIN_SURFACE - 1e-9, "surface ≥ 3:1 for " .. a.hex)
        -- recompute independently from the returned colour
        local l = S.luminance(a.r255, a.g255, a.b255)
        local ink = a.fg_dark and S.FG_DARK or S.FG_LIGHT
        check(S.contrast_ratio(l, S.luminance(ink[1], ink[2], ink[3])) >= S.MIN_FG - 1e-9, "independent foreground check")
        for _, sf in ipairs(S.SURFACES[isdark and "dark" or "light"]) do
            check(S.contrast_ratio(l, S.luminance(sf[1], sf[2], sf[3])) >= S.MIN_SURFACE - 1e-9, "independent surface check")
        end
        if a.adjusted then adjusted = adjusted + 1 else kept = kept + 1 end
    end end end
end
check(adjusted > 0 and kept > 0, "some colours move, some stay: " .. adjusted .. " / " .. kept)
-- a colour that already works is returned exactly as typed
local k = S.accent("#0a84ff", true)
check(k.ok and not k.adjusted and k.hex == "#0a84ff" and k.mix == 0, "unchanged when it already works")
local lg = S.accent("#34c759", false)   -- the system green is 2.2:1 on a light surface: it moves, and says so
check(lg.ok and lg.adjusted and lg.surface_ratio >= 3, "a light-mode green is darkened to 3:1")
-- near black in dark mode moves up, near white in light mode moves down, and says so
local nb = S.accent("#101010", true)
check(nb.ok and nb.adjusted and nb.r255 > 16, "near-black accent is lifted in dark mode")
local nw = S.accent("#f8f8f8", false)
check(nw.ok and nw.adjusted and nw.r255 < 248, "near-white accent is lowered in light mode")
-- the narrow band where neither white nor the dark ink reaches 4.5 is nudged out of it
local band = S.accent("#7c7c7c", false)   -- L ≈ 0.20: white 4.2 / dark 4.4 before the nudge
check(band.ok and band.fg_ratio >= 4.5, "mid-grey band reaches 4.5:1")
-- typed with a short form / no hash
check(S.accent("fa0", false).ok and S.accent("#FA0", true).ok, "short and hash-less forms")
-- bad input reports why, no table of numbers
for bad, why in pairs({ ["nope"] = "not_hex", [""] = "empty", ["#12"] = "length" }) do
    local a = S.accent(bad, true)
    check(a.ok == false and a.reason == why and a.r == nil, "reject " .. bad)
end

-- ── bounded enums ────────────────────────────────────────────────────
eq(S.index(1, 1, 2), 1); eq(S.index(0, 1, 2), 0); eq(S.index(2, 1, 2), 2)
eq(S.index(3, 1, 2), 1, "past the end"); eq(S.index(-1, 1, 2), 1, "negative"); eq(S.index(1.5, 1, 2), 1, "fraction")
eq(S.index("x", 1, 2), 1, "text"); eq(S.index(nil, 1, 2), 1, "nil"); eq(S.index("2", 1, 2), 2, "numeric text")
eq(S.text_delta(0), -1); eq(S.text_delta(1), 0); eq(S.text_delta(2), 1); eq(S.text_delta(9), 0, "text out of range = standard")
eq(S.density(1).row, 42, "standard density is the geometry"); eq(S.density(7).row, 42, "density out of range = standard")
eq(S.glass(2), 1.0, "standard glass is the old look, and the default"); eq(S.glass(-3), 1.0, "glass out of range = standard")
check(S.glass(0) < S.glass(1) and S.glass(1) < S.glass(2) and S.glass(2) <= 1, "glass steps only go down from standard")
eq(S.GLASS_DEFAULT, 2)
for _, set in ipairs({ S.LABELS.text, S.LABELS.density, S.LABELS.glass }) do eq(#set, 3, "three labels") end

-- ── the custom accent as an integer enum ─────────────────────────────
eq(S.int_from_hex("#0a84ff"), 10 * 65536 + 132 * 256 + 255); eq(S.hex_from_int(S.int_from_hex("#0a84ff")), "#0a84ff")
eq(S.hex_from_int(0), "#000000"); eq(S.hex_from_int(16777215), "#ffffff")
check(S.hex_from_int(-1) == nil and S.hex_from_int(16777216) == nil and S.hex_from_int(1.5) == nil and S.hex_from_int(nil) == nil and S.hex_from_int("x") == nil, "no custom / out of range")
eq(S.int_from_hex("nope"), nil)
for _, n in ipairs({ 0, 1, 255, 256, 65535, 65536, 8421504, 16777215 }) do eq(S.int_from_hex(S.hex_from_int(n)), n, "round trip " .. n) end
local fi = S.facts({ dark = false, custom = S.int_from_hex("#ffd60a") })
check(fi.acc_custom and fi.acc_cr > 0, "facts take the enum")
check(S.facts({ custom = -1, custom_hex = "#ffd60a" }).acc_custom == true, "-1 falls back to a typed hex")
check(S.facts({ custom = -1 }).acc_custom == false and S.facts({ custom = 99999999 }).acc_custom == false, "-1 / out of range = none")

-- ── the facts ────────────────────────────────────────────────────────
local f, rep = S.facts({})
check(f.acc_custom == false and f.acc_fg_dark == false and f.style_text == 1 and f.style_density == 1 and f.style_glass == 2,
    "defaults are the old look")
check(rep.ok == false and rep.reason == "none", "no custom accent: report says none")
f, rep = S.facts({ dark = true, custom_hex = "#ffd60a", text = 2, density = 0, glass = 2 })
check(f.acc_custom and rep.ok and f.acc_fg_dark == true, "light custom accent: dark foreground")
near(f.acc_cr, rep.r, 1e-9); near(f.acc_cg, rep.g, 1e-9); near(f.acc_cb, rep.b, 1e-9, "channels are 0..1")
check(f.style_text == 2 and f.style_density == 0 and f.style_glass == 2, "steps pass through")
f = S.facts({ custom_hex = "garbage" })
check(f.acc_custom == false, "an invalid custom accent is not applied")
f = S.facts({ text = 9, density = -1, glass = "x" })
check(f.style_text == 1 and f.style_density == 1 and f.style_glass == 2, "bad steps fall back to standard")
-- priority: palette > custom > preset (theme.plm)
f = S.facts({ dark = true, custom_hex = "#ffd60a", accent_auto = true, pal = { 0.05, 0.05, 0.05 } })
check(f.acc_fg_dark == false, "palette wins the foreground over a custom accent")
f = S.facts({ dark = true, custom_hex = "#ffd60a", accent_auto = true, pal = { -1, 0, 0 } })
check(f.acc_fg_dark == true, "a palette that is not ready (-1) does not win")
-- presets keep white by default; `presets_contrast` opts into the measured best ink
for i = 0, 6 do check(S.facts({ accent = i }).acc_fg_dark == false, "preset " .. i .. " keeps the historical white") end
local flips = {}
for i = 0, 6 do
    if S.facts({ accent = i, presets_contrast = true }).acc_fg_dark then flips[#flips + 1] = i end
end
check(#flips >= 3, "the shipped orange / green / graphite do not reach 4.5:1 with white (" .. #flips .. " presets would flip)")
local pr = S.PRESETS[5]   -- #ff9500 orange: the number the report quotes
near(S.contrast_ratio(S.luminance(pr[1], pr[2], pr[3]), 1), 2.2, 0.1, "orange with white is ~2.2:1")

-- ── reduced motion ───────────────────────────────────────────────────
eq(S.parse_reduce_motion('{"reduce_motion": true, "a": 1}'), true)
eq(S.parse_reduce_motion('{"reduce_motion":false}'), false)
eq(S.parse_reduce_motion('"reduce_motion" : 1'), true)
eq(S.parse_reduce_motion('{"reduce_motion": "yes"}'), nil, "only booleans / 0 / 1")
eq(S.parse_reduce_motion('{"other": true}'), nil)
eq(S.parse_reduce_motion(nil), nil)
eq(S.wallpaper_timing(false).reveal, 1500); eq(S.wallpaper_timing(true).reveal, 120)
eq(S.wallpaper_timing(true).load, S.wallpaper_timing(false).load, "decode wait is not motion")
eq(S.wallpaper_timing(true).settle, S.wallpaper_timing(false).settle, "swap settle is not motion")

-- bind_motion with a fake logic environment: the portal changes the fact from outside (handlers fire), our own writes do not
local function env(initial)
    local e = { fact = { ["motion.reduced"] = initial }, handlers = {} }
    e.on = function(name, fn) e.handlers[name] = fn end
    e.portal = function(v)            -- an OUTSIDE write: the value changes, then the logic's handler hears it
        e.fact["motion.reduced"] = v
        e.handlers["fact:motion.reduced"](v)
    end
    return e
end
local e = env(0)
local m = S.bind_motion(e)
check(not m.reduced() and m.system() == 0, "starts as the system says")
m.set(true)
check(e.fact["motion.reduced"] == 1 and m.reduced(), "forced on")
e.portal(0)                            -- the desktop says "animations on" while we force reduced
check(e.fact["motion.reduced"] == 1 and m.reduced() and m.system() == 0, "the portal's change is re-asserted and remembered")
e.portal(1)
check(e.fact["motion.reduced"] == 1 and m.system() == 1, "the portal agrees")
e.portal(0)
m.set(false)
check(e.fact["motion.reduced"] == 0 and not m.reduced(), "off: the system's last value comes back")
local e2 = env(1)                       -- the system already asks for reduced motion
local m2 = S.bind_motion(e2)
check(m2.reduced() and m2.system() == 1, "system reduced is honoured without forcing")
m2.set(true); m2.set(false)
check(e2.fact["motion.reduced"] == 1, "turning the preference off never turns off what the system asks for")
m2.set(1)
check(e2.fact["motion.reduced"] == 1, "numeric truthy forces")
local before = e2.fact["motion.reduced"]
m2.set(true)
eq(e2.fact["motion.reduced"], before, "setting the same value again changes nothing")

-- ── the plm tables mirror these ones (a change on one side fails here) ───
local theme = read("shell/common/theme.plm")
local style = read("shell/common/style.plm")
local facts_plm = read("shell/common/theme_facts.plm")
local owner = read("shell/common/theme_owner.plm")
local function nums(list, f2) local o = {} for _, v in ipairs(list) do o[#o + 1] = f2 and f2(v) or tostring(v) end return table.concat(o, ", ") end
check(theme:find("pick(style_glass, " .. nums(S.GLASS, function(v) return v == 1 and "1" or tostring(v) end) .. ")", 1, true), "theme.plm glass_k = Style.GLASS")
check(theme:find("pick(style_text, font_title - 1, font_title, font_title + 1)", 1, true) and S.TEXT_DELTA[1] == -1 and S.TEXT_DELTA[3] == 1,
    "theme.plm ts_* moves each role one point: Style.TEXT_DELTA")
check(theme:find("let on_accent  = #ffffff", 1, true) and S.FG_LIGHT[1] == 255,
    "theme.plm on_accent is always white (the accents are mostly dark); Style.FG_DARK stays for the contrast report")
for i, p in ipairs(S.PRESETS) do
    check(theme:find(S.format_hex(p[1], p[2], p[3]), 1, true), "theme.plm preset accent " .. i .. " is Style.PRESETS")
end
-- geometry values the density table is relative to
local geo = read("shell/common/geometry.plm")
local function geom(name) return tonumber(geo:match("let " .. name .. " = (%d+)")) end
eq(S.DENSITY[2].row, geom("row_h")); eq(S.DENSITY[2].detail, geom("row_detail_h")); eq(S.DENSITY[2].slider, geom("row_slider_h"))
eq(S.DENSITY[1].control, geom("control_h_compact")); eq(S.DENSITY[2].control, geom("control_h")); eq(S.DENSITY[3].control, geom("control_h_large"))
eq(S.DENSITY[1].gap, geom("space_6")); eq(S.DENSITY[2].gap, geom("space_8")); eq(S.DENSITY[3].gap, geom("space_8") + geom("space_2"))
eq(S.DENSITY[1].section, geom("space_12")); eq(S.DENSITY[2].section, geom("space_16")); eq(S.DENSITY[3].section, geom("space_20"))
check(style:find("row_h - 6, row_h, row_h + 6", 1, true) and S.DENSITY[1].row == geom("row_h") - 6 and S.DENSITY[3].row == geom("row_h") + 6, "style.plm rows")
check(style:find("row_detail_h - 6, row_detail_h, row_detail_h + 6", 1, true) and S.DENSITY[1].detail == geom("row_detail_h") - 6, "style.plm detail rows")
check(style:find("row_slider_h - 6, row_slider_h, row_slider_h + 6", 1, true) and S.DENSITY[3].slider == geom("row_slider_h") + 6, "style.plm slider rows")
check(style:find("pick(style_density, control_h_compact, control_h, control_h_large)", 1, true), "style.plm control height")
check(style:find("pick(style_density, space_6, space_8, space_8 + space_2)", 1, true), "style.plm gap")
check(style:find("pick(style_density, space_12, space_16, space_20)", 1, true), "style.plm section gap")
-- facts the plm declares / reads
for _, name in ipairs({ "acc_custom", "acc_cr", "acc_cg", "acc_cb", "acc_fg_dark", "style_text", "style_density", "style_glass" }) do
    check(facts_plm:find("fact " .. name .. " =", 1, true), "theme_facts.plm declares " .. name)
    check(owner:find("let " .. name .. " = Settings." .. name, 1, true), "theme_owner.plm reads Settings." .. name)
    local ret = S.facts({})
    check(ret[name] ~= nil, "Style.facts returns " .. name)
end
check(facts_plm:find("fact reduce_motion = false", 1, true), "theme_facts.plm declares reduce_motion")
check(facts_plm:find("fact style_text = 1", 1, true) and facts_plm:find("fact style_density = 1", 1, true) and facts_plm:find("fact style_glass = 2", 1, true),
    "fact defaults are the standard steps")
-- the new part declares no surface, fact, model, service or timer
for _, banned in ipairs({ "surface", "fact ", "model ", "service ", "every ", "wave ", "spin ", "blink " }) do
    check(not style:gsub("//[^\n]*", ""):find(banned, 1, true), "style.plm has no '" .. banned .. "'")
end

print(string.format("style-options: %d checks passed", passed))
