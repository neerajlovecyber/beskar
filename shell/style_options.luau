-- Pure style helpers (C2b/C2c): a validated custom accent with a contrast foreground, reduced motion, and the three bounded
-- visual-tuning enums (text size, density, glass strength). No `run`, no timers, no surfaces, no facts of its own: Settings
-- (and wallpaper.luau) call these and apply the results; `lua tests/style-options.lua` covers them without the shell.
--
-- THE CONTRACT with common/theme.plm, theme_facts.plm, theme_owner.plm and common/style.plm (keep numbers in sync: the test
-- reads those files and fails when a table here and a `pick(...)` there disagree).
--
--   Facts the look is made of (OWNED by Settings; broadcast to every themed process like dark_mode / skin / accent):
--     acc_custom      bool    a validated custom accent is chosen
--     acc_cr/cg/cb    0..1    that accent (already adjusted for contrast, for the CURRENT mode: recompute when dark_mode flips)
--     acc_fg_dark     bool    the ACTIVE accent (wallpaper palette, custom or preset) needs the dark foreground
--     style_text      0..2    text size step    (-1 pt / standard / +1 pt on the t_* roles)
--     style_density   0..2    density step      (compact / standard / spacious: common/style.plm roles, NOT yet read by ui.plm)
--     style_glass     0..2    glass strength    (minimal / soft / FULL = default 2: theme.plm glass_amt x 0.5 / 0.75 / 1)
--     reduce_motion   bool    (theme_facts.plm) read by the root logic of each process, see below
--   Saved as integer enums: custom accent -1 (none) or 0xRRGGBB (`Style.int_from_hex` / `hex_from_int`), style_text, style_glass.
--   `Style.facts(opts)` returns exactly this table (plus `accent` = a report for the UI). Priority of accent sources, as in
--   theme.plm: wallpaper palette (accent_auto with a palette) > validated custom > preset.
--
--   Reduced motion is NOT a theme fact. pleamar's own `motion.reduced` (language 0.5+, global to the PROCESS) makes every spring
--   in every scene settle at once and silences wave / spin / blink; the desktop portal overwrites it on every system change.
--   Proven on pleamar 0.8.0-exp.16 (tests/style-runtime.py, a composite built like desktop.plm):
--     * only the ROOT scene's logic may write it: a plugin of an imported scene (Settings inside `desktop`) is refused with
--       "plugin 'X' has no fact called 'motion.reduced'". So the preference is a Settings fact (`reduce_motion`, declared on
--       Settings through theme_facts.plm) and the root scene's logic applies it. For `desktop` that is a new `shell/desktop.luau`:
--           local Style = require("style_options")
--           local motion = Style.bind_motion({ fact = fact, on = on })
--           on("fact:Settings.reduce_motion", function(v) motion.set(v) end)
--           if fact["Settings.reduce_motion"] then motion.set(true) end
--       Standalone processes (wallpaper: done here; widgets, lock, capture: their own logic) bind the same way on their own
--       `reduce_motion` fact, which Settings says with the theme broadcast.
--     * one write settles the springs of ALL imported scenes (open and close), `follow` springs, layers, and silences `wave`.
--   Preference key in prefs.json: `"reduce_motion": true|false` (wallpaper.luau reads it at start).
local M = {}

-- ── colour maths (WCAG 2.x relative luminance, sRGB) ─────────────────────────────────────────────────────────────
local function lin(c)
    c = c / 255
    if c <= 0.04045 then
        return c / 12.92
    end
    return ((c + 0.055) / 1.055) ^ 2.4
end

-- 0..255 channels → relative luminance 0..1
function M.luminance(r, g, b)
    return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
end

-- two luminances → contrast ratio 1..21
function M.contrast_ratio(l1, l2)
    local hi, lo = math.max(l1, l2), math.min(l1, l2)
    return (hi + 0.05) / (lo + 0.05)
end

M.FG_LIGHT = { 255, 255, 255 }   -- theme.plm on_accent when acc_fg_dark is false (the historical colour)
M.FG_DARK = { 16, 17, 20 }       -- theme.plm on_accent when acc_fg_dark is true
M.MIN_FG = 4.5                   -- text on an accent fill (WCAG AA, normal text)
M.MIN_SURFACE = 3.0              -- the accent as a control / glyph against the mode's glass (WCAG 1.4.11)
-- The theme's flat surfaces per mode (theme.plm bg_color / bar_color per skin). An accent must separate from ALL of them.
-- Glass over a wallpaper is not a flat colour, so this is the reference, not a guarantee (see docs/CUSTOMIZATION_PLAN.md).
M.SURFACES = {
    dark = { { 20, 22, 29 }, { 24, 26, 32 }, { 30, 32, 38 }, { 22, 24, 32 } },
    light = { { 248, 249, 252 }, { 240, 242, 246 }, { 242, 243, 247 }, { 234, 236, 242 } },
}
-- theme.plm's preset accents, in order (`accent` fact 0..6)
M.PRESETS = { { 0, 122, 255 }, { 175, 82, 222 }, { 255, 45, 85 }, { 255, 59, 48 }, { 255, 149, 0 }, { 52, 199, 89 }, { 142, 142, 147 } }

local FG_DARK_L = M.luminance(M.FG_DARK[1], M.FG_DARK[2], M.FG_DARK[3])

-- ── hex colours ──────────────────────────────────────────────────────────────────────────────────────────────────
-- "#0a84ff", "0A84FF", "#fa0" (short form) → r, g, b (0..255). Otherwise nil, reason:
--   "type" · "empty" · "too_long" (more than 16 characters: pasted prose) · "alpha" (8 digits: no transparent accents) ·
--   "length" (not 3 or 6 digits) · "not_hex"
function M.parse_hex(s)
    if type(s) ~= "string" then
        return nil, "type"
    end
    s = s:gsub("^%s+", ""):gsub("%s+$", "")
    if s == "" then
        return nil, "empty"
    end
    if #s > 16 then
        return nil, "too_long"
    end
    s = s:gsub("^#", "")
    if s:find("[^%x]") or s == "" then
        return nil, "not_hex"
    end
    if #s == 8 or #s == 4 then
        return nil, "alpha"
    end
    if #s == 3 then
        s = s:gsub(".", "%0%0")
    end
    if #s ~= 6 then
        return nil, "length"
    end
    return tonumber(s:sub(1, 2), 16), tonumber(s:sub(3, 4), 16), tonumber(s:sub(5, 6), 16)
end

function M.format_hex(r, g, b)
    return string.format("#%02x%02x%02x", r, g, b)
end

-- The custom accent as a saved ENUM: -1 = none (use the preset), else 0 .. 16777215 (0xRRGGBB). Integer facts only, no text.
M.CUSTOM_NONE = -1
function M.int_from_hex(text)
    local r, g, b = M.parse_hex(text)
    if not r then
        return nil
    end
    return r * 65536 + g * 256 + b
end
-- n → "#rrggbb", or nil for -1 / anything that is not an integer in range
function M.hex_from_int(n)
    n = tonumber(n)
    if not n or n ~= math.floor(n) or n < 0 or n > 16777215 then
        return nil
    end
    return M.format_hex(math.floor(n / 65536), math.floor(n / 256) % 256, n % 256)
end

-- ── the foreground on an accent ──────────────────────────────────────────────────────────────────────────────────
-- White unless white misses 4.5:1 and the dark ink does better (so every colour the theme already ships in white stays white
-- when white is readable). Returns dark (bool), ratio (of the colour chosen). For ANY colour the result is at least ~4.3:1;
-- `accent()` below nudges a custom colour out of the narrow band where it is under 4.5:1.
function M.foreground(r, g, b)
    local l = M.luminance(r, g, b)
    local cw = M.contrast_ratio(l, 1)
    if cw >= M.MIN_FG then
        return false, cw
    end
    local cd = M.contrast_ratio(l, FG_DARK_L)
    if cd > cw then
        return true, cd
    end
    return false, cw
end

-- the same for 0..1 channels (the palette engine's facts)
function M.foreground_unit(r, g, b)
    return M.foreground(math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5))
end

local function mixed(r, g, b, target, t)
    local function m(c) return math.floor(c + (target - c) * t + 0.5) end
    return m(r), m(g), m(b)
end

local function surface_ratio(r, g, b, dark)
    local l = M.luminance(r, g, b)
    local worst = math.huge
    for _, s in ipairs(M.SURFACES[dark and "dark" or "light"]) do
        worst = math.min(worst, M.contrast_ratio(l, M.luminance(s[1], s[2], s[3])))
    end
    return worst
end

-- A custom accent as typed. `dark` is the current mode. The colour is kept as typed when it already separates from the mode's
-- surfaces (≥ 3:1) and carries a readable foreground (≥ 4.5:1); otherwise it moves in 5 % steps towards white (dark mode) or
-- black (light mode) until both hold, which always happens at the latest at the end of the line.
-- Returns { ok = true, hex, r, g, b (0..1), r255, g255, b255, fg_dark, fg_ratio, surface_ratio, adjusted, mix } or
-- { ok = false, reason } with parse_hex's reasons.
function M.accent(text, dark)
    local r, g, b = M.parse_hex(text)
    if not r then
        local _, why = M.parse_hex(text)
        return { ok = false, reason = why }
    end
    dark = dark and true or false
    local target = dark and 255 or 0
    for k = 0, 20 do
        local t = k / 20
        local cr, cg, cb = mixed(r, g, b, target, t)
        local fg_dark, fg_ratio = M.foreground(cr, cg, cb)
        local sr = surface_ratio(cr, cg, cb, dark)
        if sr >= M.MIN_SURFACE and fg_ratio >= M.MIN_FG then
            return {
                ok = true, hex = M.format_hex(cr, cg, cb), r255 = cr, g255 = cg, b255 = cb,
                r = cr / 255, g = cg / 255, b = cb / 255,
                fg_dark = fg_dark, fg_ratio = fg_ratio, surface_ratio = sr, adjusted = k > 0, mix = t,
            }
        end
    end
    return { ok = false, reason = "unreachable" }   -- cannot happen: white / black satisfy both
end

-- ── bounded enums ────────────────────────────────────────────────────────────────────────────────────────────────
-- An enum fact from Settings, whatever arrives: an integer 0..max, else `default`.
function M.index(v, default, max)
    v = tonumber(v)
    if not v or v ~= math.floor(v) or v < 0 or v > max then
        return default
    end
    return v
end

M.LABELS = {
    text = { "Compact", "Standard", "Large" },
    density = { "Compact", "Standard", "Spacious" },
    glass = { "Minimal", "Soft", "Full" },   -- the glass amount: Minimal is the most opaque
}

-- Text: points added to the five t_* roles (theme.plm `t_title = pick(style_text, font_title - 1, font_title, font_title + 1)`…).
-- Only ONE point either way on purpose: row, button and field heights and every measured label width stay constant (geometry.plm
-- is constants only) and the callers size buttons from their label, so a bigger step would clip. Roles: title 15, body 13,
-- secondary 12, caption 11, micro 10.5 (geometry.plm) → compact 14 / 12 / 11 / 10 / 9.5, large 16 / 14 / 13 / 12 / 11.5.
M.TEXT_DELTA = { -1, 0, 1 }
M.TEXT_DEFAULT = 1
function M.text_delta(i)
    return M.TEXT_DELTA[M.index(i, M.TEXT_DEFAULT, 2) + 1]
end

-- Density (common/style.plm): the row and control heights and the gaps a dense or roomy layout would use, as whole pixels
-- relative to the geometry roles. STANDARD IS THE GEOMETRY ITSELF. Nothing in ui.plm reads these yet: do not expose the choice.
M.DENSITY = {
    --        row_h  row_detail_h  row_slider_h  control_h  gap_controls  gap_sections
    { row = 36, detail = 50, slider = 58, control = 24, gap = 6, section = 12 },
    { row = 42, detail = 56, slider = 64, control = 28, gap = 8, section = 16 },
    { row = 48, detail = 62, slider = 70, control = 32, gap = 10, section = 20 },
}
M.DENSITY_DEFAULT = 1
function M.density(i)
    return M.DENSITY[M.index(i, M.DENSITY_DEFAULT, 2) + 1]
end

-- Glass strength (theme.plm `glass_k`): a multiplier on the skin's glass_amt, the see-through amount of every panel / card body
-- (0 % = a solid panel in the theme colour; 70 % = the standard liquid glass). MEASURED (film, flat backdrop under a panel,
-- dark mode, ink #f5f7f5 against the pixel the panel shows): over pure white the panel is 3.5:1 at x1.0, 4.4 at x0.85, 6.6 at x0.6,
-- 10.9 at x0.3; ABOVE 1 it only gets worse (2.9 at x1.15, 2.5 at x1.25), so no step goes above standard. The steps are therefore
-- 0.5 / 0.75 / 1.0, standard LAST: a lower step is a more opaque, more legible panel. `tint:` was also measured and does not
-- change the pixels at all on these bodies (x0.8 .. x2.0 identical), so it is not scaled. Classic solid (skin 2) has 0 %, so the
-- step changes nothing there (Settings should disable the control). The frame (topbar.plm bar_glass) has its own numbers.
M.GLASS = { 0.5, 0.75, 1.0 }
M.GLASS_DEFAULT = 2
function M.glass(i)
    return M.GLASS[M.index(i, M.GLASS_DEFAULT, 2) + 1]
end

-- ── the facts for the look ───────────────────────────────────────────────────────────────────────────────────────
-- opts = {
--   dark        bool   current mode (the resolved one: for appearance "auto" the mode in force now)
--   custom      integer the saved custom accent enum (-1 none, else 0xRRGGBB), or
--   custom_hex  string  the accent as typed (either one; `custom` wins; nil / "" / -1 = none)
--   accent_auto bool   colours from the wallpaper are on
--   pal         { r, g, b } 0..1 palette accent when there is one (pal_ar..), else nil
--   accent      0..6   preset index
--   presets_contrast bool  also give presets / the palette the best foreground (default: only the palette and custom do; the
--                      presets keep the historical white: orange and green measure 2.2:1 with it, see tests)
--   text, density, glass   enum indices (bounded here)
-- }
-- Returns the table of facts to set / broadcast, and `accent` (the report for the UI: ok, reason, hex, adjusted, ratios).
function M.facts(o)
    o = o or {}
    local f = {
        acc_custom = false, acc_cr = 0, acc_cg = 0, acc_cb = 0, acc_fg_dark = false,
        style_text = M.index(o.text, M.TEXT_DEFAULT, 2),
        style_density = M.index(o.density, M.DENSITY_DEFAULT, 2),
        style_glass = M.index(o.glass, M.GLASS_DEFAULT, 2),
    }
    local report = { ok = false, reason = "none" }
    local typed = M.hex_from_int(o.custom)
    if not typed and type(o.custom_hex) == "string" and o.custom_hex ~= "" then
        typed = o.custom_hex
    end
    if typed then
        report = M.accent(typed, o.dark)
        if report.ok then
            f.acc_custom = true
            f.acc_cr, f.acc_cg, f.acc_cb = report.r, report.g, report.b
        end
    end
    local pal = o.pal
    local pal_on = o.accent_auto and type(pal) == "table" and (tonumber(pal[1]) or -1) >= 0
    if pal_on then
        f.acc_fg_dark = (M.foreground_unit(pal[1], pal[2], pal[3]))
    elseif f.acc_custom then
        f.acc_fg_dark = report.fg_dark
    elseif o.presets_contrast then
        local p = M.PRESETS[M.index(o.accent, 0, 6) + 1]
        f.acc_fg_dark = (M.foreground(p[1], p[2], p[3]))
    end
    return f, report
end

-- ── reduced motion ───────────────────────────────────────────────────────────────────────────────────────────────
-- prefs.json text (the first 64 KiB, as wallpaper_store reads it) → true / false / nil for `"reduce_motion"`.
function M.parse_reduce_motion(text)
    if type(text) ~= "string" then
        return nil
    end
    local v = text:match('"reduce_motion"%s*:%s*([%w]+)')
    if v == "true" or v == "1" then
        return true
    elseif v == "false" or v == "0" then
        return false
    end
    return nil
end

-- The wallpaper reveal's waits in ms: `load` lets the new picture decode before it grows over the old one, `reveal` is the
-- growth (the renderer's rv spring is 1300 ms; reduced motion settles it in a frame, so only a short hold is kept so the
-- swap never races the last painted frame), `settle` lets the swapped-in picture load before the cover goes. The final state
-- (wp_a_path = the new picture, wp_go back to false) is the same.
M.WALLPAPER_FULL = { load = 450, reveal = 1500, settle = 250 }
M.WALLPAPER_REDUCED = { load = 450, reveal = 120, settle = 250 }
function M.wallpaper_timing(reduced)
    return reduced and M.WALLPAPER_REDUCED or M.WALLPAPER_FULL
end

-- Binds pleamar's `motion.reduced` to a preference. `env` = { fact = <logic's fact table>, on = <logic's on()> } (injected so a
-- test can fake them). Returns a controller:
--   set(bool)   true: force reduced motion on and keep it on (the portal's later changes are re-asserted, and remembered);
--               false: let go, giving back the last value the system reported
--   reduced()   whether motion is reduced right now (forced or the system's)
--   system()    the system's last known value (0 / 1)
-- MUST run in the ROOT scene's logic of a process (see the header). Evidence (pleamar 0.8.0-exp.16, film fixture): a logic write to
-- fact["motion.reduced"] takes effect in the whole process and does NOT call that logic's own on("fact:motion.reduced") handler; an outside write (`--say … fact motion.reduced 0`,
-- standing in for the portal) DOES, so the re-assert cannot loop.
function M.bind_motion(env)
    local fact, on = env.fact, env.on
    local system = tonumber(fact["motion.reduced"]) or 0
    local forced = false
    local ctl = {}
    on("fact:motion.reduced", function(v)
        v = tonumber(v) or 0
        system = v
        if forced and v ~= 1 then
            fact["motion.reduced"] = 1
        end
    end)
    function ctl.set(on_)
        on_ = (on_ == true or on_ == 1) and true or false
        if on_ == forced then
            return
        end
        forced = on_
        fact["motion.reduced"] = forced and 1 or system
    end
    function ctl.reduced()
        return forced or system == 1
    end
    function ctl.system()
        return system
    end
    return ctl
end

function M.follow_motion(env, key)
    key = key or "reduce_motion"
    local motion = M.bind_motion(env)
    env.on("fact:" .. key, motion.set)
    motion.set(env.fact[key])
    return motion
end

return M
