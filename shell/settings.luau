-- System Settings logic. Every control in settings.plm lands here.
--   look      mode (light / dark / auto), glass, accent  → broadcast to every scene and saved (pleamar_shell.json)
--   prefs     bar / dock / notification options          → saved in ~/.config/beskar/prefs.json, pushed to the scenes
--   system    sound, brightness, displays (niri msg), Wi-Fi, Bluetooth, updates, shortcuts (read from niri's config)

-- the scenes of their OWN process that do not read Settings' facts by name (everything in `desktop` does): they are told by `say`
local THEMED = { "settings", "capture", "lock", "widgets" }

local function say(scene, words)
    pcall(sys.call, "say", scene, words)
end

local function sh(script, cb, ...)
    run("sh", { "-c", script, "x", ... }, cb, cb == nil and { output = false } or nil)
end

local preferences = require("preferences")
local Style = require("style_options")
local PAL = nil
local finish_preferences
local refresh_style
local palette_generation = 0
local preference_store = require("settings_store")(preferences, {
    run = function(script, args, cb) run("sh", { "-c", script, "settings-store", unpack(args) }, cb) end,
    decode = json.decode,
    notify = function(message) text.preference_status = message; fact.preference_problem = message ~= "" and message ~= "Saving preferences…" end,
    value = function(kind, base)
        local document = preferences.from_facts(kind, fact, base)
        if kind == "prefs" then document.frame_output_name = text.frame_output_name or "" end
        if kind == "palette" and PAL then
            document.src, document.dark, document.light = PAL.src, PAL.dark, PAL.light
        end
        return document
    end,
})
on("preference_retry", preference_store.retry)

-- ── the sidebar ──────────────────────────────────────────────────
local actions = require("actions")
local CATS = actions.settings
-- Nerd-font glyphs are not drawn symmetrically in their box: how far each one sits right of the middle (measured)
local GLYPH_DX = {}   -- no nudging any more: icons use the Mono Nerd Font (common/icons.plm), centred by design
local TITLES = {}
for _, c in ipairs(CATS) do
    TITLES[c.tab] = c.name
end

local function paint_cats()
    local rows = {}
    for _, c in ipairs(CATS) do
        rows[#rows + 1] = { idx = c.tab, icon = c.icon, tint = c.tint, name = c.name, dx = GLYPH_DX[c.tab] or 0 }
    end
    model.cats = rows
end
paint_cats()


-- ── the palette engine ───────────────────────────────────────────
-- "Colours from the wallpaper": matugen (Material You, Rust) reads the wallpaper once and gives a whole palette for
-- light and for dark; we keep an accent (primary tone 60 dark / 50 light), a second colour (tertiary) and the
-- surface, and send the ones for the current mode to every scene as pal_* facts (theme.plm turns them into
-- accent_c, focus_c and bg_color). Saved in ~/.config/beskar/palette.json so a restart needs no extraction.
local apply_apps          -- defined below (other apps' colours)
-- 0 Tonal · 1 Vibrant · 2 Neutral are matugen's own schemes; 3 Soft (pastel) is Tonal with lighter tones, a little
-- of the colour taken out and the surface kept quiet. (matugen has no chroma setting of its own: the schemes and
-- `--contrast` are all it offers.)
local PAL_STYLES = { [0] = "scheme-tonal-spot", [1] = "scheme-vibrant", [2] = "scheme-neutral", [3] = "scheme-tonal-spot" }

local function soften(hex, amount)
    local r, g, b = hex:match("#(%x%x)(%x%x)(%x%x)")
    if not r then return hex end
    r, g, b = tonumber(r, 16), tonumber(g, 16), tonumber(b, 16)
    local grey = 0.299 * r + 0.587 * g + 0.114 * b
    local function mix(c) return math.floor(c + (grey - c) * amount + 0.5) end
    return string.format("#%02x%02x%02x", mix(r), mix(g), mix(b))
end

local function rgb01(hex)
    local r, g, b = tostring(hex or ""):match("#(%x%x)(%x%x)(%x%x)")
    if not r then return 0, 0, 0 end
    return tonumber(r, 16) / 255, tonumber(g, 16) / 255, tonumber(b, 16) / 255
end

local function palette_words()
    if not PAL then return nil end
    local dm = (fact.dark_mode == true or fact.dark_mode == 1)
    local set = dm and PAL.dark or PAL.light
    if not set then return nil end
    local words = {}
    for _, k in ipairs({ { "a", "pal_a" }, { "b", "pal_b" }, { "s", "pal_s" } }) do
        local r, g, b = rgb01(set[k[1]])
        words[#words + 1] = string.format("fact %sr %.4f", k[2], r)
        words[#words + 1] = string.format("fact %sg %.4f", k[2], g)
        words[#words + 1] = string.format("fact %sb %.4f", k[2], b)
    end
    return words
end

local function push_palette()
    local words = palette_words()
    if not words then if refresh_style then refresh_style() end; return end
    for _, s in ipairs(THEMED) do
        for _, w in ipairs(words) do
            if s == "settings" then
                local name, val = w:match("fact (%S+) (%S+)")
                fact[name] = tonumber(val)
            else
                say(s, w)
            end
        end
    end
    if refresh_style then refresh_style() end
end

local function save_palette()
    preference_store.save("palette")
end

-- Which colour of the picture the palette is built from. matugen's own pick ("--prefer saturation") takes the most
-- saturated pixels even when they are a speck, so a grey-blue wallpaper came out yellow. Instead: 12 colours of the
-- picture (ImageMagick), each scored by how much of the picture it covers, a little by how colourful it is, and not
-- at all when it is nearly black or white; the best one is the source (a grey wallpaper gives a grey-blue palette).
local function pick_source(hist)
    local best, best_score = nil, -1
    for line in (hist or ""):gmatch("[^\n]+") do
        local count, hex = line:match("(%d+):.-#(%x%x%x%x%x%x)")
        if count then
            local r, g, b = tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255
            local mx, mn = math.max(r, g, b), math.min(r, g, b)
            local sat = mx > 0 and (mx - mn) / mx or 0
            local lively = (mx > 0.22 and mx < 0.97) and 1 or 0.2
            local score = tonumber(count) * (0.2 + sat) * lively
            if score > best_score then best, best_score = "#" .. hex, score end
        end
    end
    return best
end

local function extract_palette(path)
    if not path or path == "" then return end
    palette_generation = palette_generation + 1
    local generation = palette_generation
    local style = PAL_STYLES[tonumber(fact.pal_style) or 0] or PAL_STYLES[0]
    run("magick", { path, "-resize", "120x120", "-colors", "12", "-format", "%c", "histogram:info:-" }, function(hist, hcode)
        local source = hcode == 0 and pick_source(hist) or nil
        if not source then return end
        run("matugen", { "color", "hex", source, "--json", "hex", "--dry-run", "-m", "dark", "-t", style }, function(out, code)
            if code ~= 0 or not out or generation ~= palette_generation then return end
            local at = out:find("{", 1, true)
            local ok, d = pcall(json.decode, at and out:sub(at) or "")
            if not ok or type(d) ~= "table" or type(d.palettes) ~= "table" or type(d.colors) ~= "table" then return end
            local function tone(name, t)
                local p = d.palettes[name]
                return p and p[tostring(t)] and p[tostring(t)].color
            end
            local function surface(mode)
                local c = d.colors.surface
                return c and c[mode] and c[mode].color
            end
            local src = source
            if (tonumber(fact.pal_style) or 0) == 3 then
                -- Soft: lighter tones, 22 % of the colour taken out
                PAL = {
                    dark = { a = soften(tone("primary", 70), 0.22), b = soften(tone("tertiary", 70), 0.22), s = surface("dark") },
                    light = { a = soften(tone("primary", 60), 0.22), b = soften(tone("tertiary", 60), 0.22), s = surface("light") },
                }
            else
                PAL = {
                    dark = { a = tone("primary", 60), b = tone("tertiary", 60), s = surface("dark") },
                    light = { a = tone("primary", 50), b = tone("tertiary", 50), s = surface("light") },
                }
            end
            PAL.src = src
            save_palette()
            push_palette()
            apply_apps()
        end)
    end)
end

local function extract_current()
    sh('cat "$HOME/.config/beskar/wallpaper" 2>/dev/null | head -1', function(out)
        extract_palette((out or ""):gsub("%s+$", ""))
    end)
end

on("set_screen", function(i) fact.open_screen = tonumber(i) or 0 end)
on("set_pal_src", function(path)
    text.pal_src = path or ""
    if fact.accent_auto == true then extract_palette(path) end
end)
on("text:pal_src", function(path)
    if fact.accent_auto == true then
        extract_palette(path)
    end
end)

on("pal_style_pick", function(n)
    fact.pal_style = math.max(0, math.min(3, math.floor(tonumber(n) or 0)))
    save_palette()
    extract_current()
end)

local function load_palette()
    preference_store.load("palette", function(result)
        local d = result.value
        fact.pal_style = d.style
        if preferences.palette_usable(d) then
            PAL = { dark = d.dark, light = d.light, src = d.src }
            push_palette()
            after(3000, push_palette)
            after(8000, push_palette)
        end
        finish_preferences()
        after(2500, function() if fact.accent_auto == true then extract_current() end end)
    end)
end

-- ── other apps: terminals, GTK / libadwaita (Nautilus), Qt ───────
-- shell/appthemes.sh renders matugen templates (assets/matugen) from one source colour and the mode, and adds one
-- include line to each app's own config. The source is the wallpaper's colour when "Colours from the wallpaper" is on,
-- else the chosen accent. Debounced: a theme change fires several broadcasts.
local ACCENT_HEX = { [0] = "#007aff", "#af52de", "#ff2d55", "#ff3b30", "#ff9500", "#34c759", "#8e8e93" }
local apps_timer = nil

refresh_style = function()
    local values, report = Style.facts({ dark = fact.dark_mode == true, custom = fact.custom_accent,
        accent = fact.accent, accent_auto = fact.accent_auto == true,
        pal = { tonumber(fact.pal_ar) or -1, tonumber(fact.pal_ag) or 0, tonumber(fact.pal_ab) or 0 },
        text = fact.style_text, glass = fact.style_glass, presets_contrast = true })
    for name, value in pairs(values) do
        fact[name] = value
        for _, scene in ipairs(THEMED) do if scene ~= "settings" then say(scene, "fact " .. name .. " " .. tostring(value)) end end
    end
    local hex = Style.hex_from_int(fact.custom_accent)
    text.custom_accent_current = hex or "Preset colour"
    text.custom_accent_status = report.ok and ((report.adjusted and "Adjusted for contrast: " or "Applied colour: ") .. report.hex) or "Use #RRGGBB or #RGB"
end

function apply_apps()
    if apps_timer then cancel(apps_timer) end
    apps_timer = after(900, function()
        apps_timer = nil
        if fact.pref_apps ~= true then return end
        local dm = (fact.dark_mode == true or fact.dark_mode == 1)
        local src = ACCENT_HEX[tonumber(fact.accent) or 0] or ACCENT_HEX[0]
        if fact.acc_custom == true then src = string.format("#%02x%02x%02x", math.floor(fact.acc_cr * 255 + .5), math.floor(fact.acc_cg * 255 + .5), math.floor(fact.acc_cb * 255 + .5)) end
        if fact.accent_auto == true and PAL and PAL.src then src = PAL.src end
        local scheme = (PAL_STYLES[tonumber(fact.pal_style) or 0]) or "scheme-tonal-spot"
        if fact.accent_auto ~= true then scheme = "scheme-tonal-spot" end
        sh('D=$(cat "$HOME/.config/beskar/shell-dir" 2>/dev/null) || exit 0; sh "$D/shell/appthemes.sh" setup; sh "$D/shell/appthemes.sh" apply "$1" "$2" "$3"',
            nil, dm and "dark" or "light", src, scheme)
    end)
end

-- ── theme: mode, glass, accent, clock format ─────────────────────
local function save_theme()
    preference_store.save("theme")
end

local function broadcast_theme(persist)
    local dm = (fact.dark_mode == true or fact.dark_mode == 1)
    local dm_str = tostring(dm)
    local skin_str = tostring(fact.skin or 0)
    local accent_str = tostring(fact.accent or 0)
    local auto_str = tostring(fact.accent_auto == true)
    local h12_str = tostring(fact.hour12 ~= false)
    for _, s in ipairs(THEMED) do
        if s ~= "settings" then
            say(s, "fact dark_mode " .. dm_str)
            say(s, "fact skin " .. skin_str)
            say(s, "fact accent " .. accent_str)
            say(s, "fact accent_auto " .. auto_str)
            say(s, "fact hour12 " .. h12_str)
        end
    end
    if persist ~= false then save_theme() end
    push_palette()
    apply_apps()
    -- GTK / libadwaita apps follow too
    pcall(run, "gsettings", { "set", "org.gnome.desktop.interface", "color-scheme", dm and "prefer-dark" or "prefer-light" }, nil, { output = false })
end

-- ── prefs (bar, dock, notifications) ─────────────────────────────
local BANNER_MS = { [0] = 3000, [1] = 5500, [2] = 8000, [3] = 12000 }
local prefs_pending = false

local function b(v)
    return v == true or v == 1
end

local LOCK_MINUTES = { [0] = 0, 3, 5, 10, 15 }

local function save_prefs()
    preference_store.save("prefs")
end

local function push_prefs()
    -- the bar's and the notifications' preferences are Settings' own facts, read by name by the scenes in `desktop`;
    -- only what is NOT: the widgets (own process) and values computed here
    say("widgets", "fact widgets_on " .. tostring(b(fact.pref_widgets)))
    say("widgets", "fact clock_seconds " .. tostring(b(fact.pref_seconds)))
    say("wallpaper", "fact wp_fx " .. tostring(fact.wallpaper_fx))
    for _, scene in ipairs({ "widgets", "lock", "capture", "wallpaper" }) do
        say(scene, "fact reduce_motion " .. tostring(fact.reduce_motion == true))
    end
    emit("Notifications.set_banner_ms", BANNER_MS[tonumber(fact.banner_i) or 1] or 5500)
end

local function changed_pref()
    save_prefs()
    push_prefs()
end
on("toggle_reduce_motion", function()
    if not preference_store.ready() then return end
    fact.reduce_motion = not (fact.reduce_motion == true)
    changed_pref()
end)

require("settings_quiet")(changed_pref, preference_store.ready)

local function load_prefs()
    preference_store.load("prefs", function(result)
        for name, v in pairs(preferences.to_facts("prefs", result.value)) do if name == "frame_output_name" then text.frame_output_name = v; text.frame_output_edit = v else fact[name] = v end end
        push_prefs()
        finish_preferences()
        after(3000, push_prefs)
        after(8000, push_prefs)
    end)
end
preference_store.load("theme", function(result)
    for name, v in pairs(preferences.to_facts("theme", result.value)) do fact[name] = v end
    load_prefs()
    finish_preferences()
end)

-- ── Appearance ───────────────────────────────────────────────────
local function auto_dark()
    local h = tonumber(os.date("%H")) or 12
    return h >= 19 or h < 7
end

local function apply_mode(announce)
    local m = tonumber(fact.appearance) or 1
    local dark = (m == 1) or (m == 2 and auto_dark())
    local was = b(fact.dark_mode)
    fact.dark_mode = dark
    if announce or dark ~= was then
        broadcast_theme()
    end
end

on("set_mode", function(n)
    fact.appearance = math.max(0, math.min(2, math.floor(tonumber(n) or 1)))
    apply_mode(true)
    save_prefs()
end)

-- the Control Center's dark-mode tile
on("set_dark_mode", function(v)
    fact.appearance = (tonumber(v) or 1) == 1 and 1 or 0
    apply_mode(true)
    save_prefs()
end)

every(60000, function()
    if tonumber(fact.appearance) == 2 then
        apply_mode(false)
    end
end)

on("choose_skin", function(val)
    fact.skin = math.max(0, math.min(2, math.floor(tonumber(val) or 0)))
    broadcast_theme()
end)

-- Picked by hand: that ends "match the wallpaper".
on("choose_accent", function(val)
    fact.accent = math.max(0, math.min(6, math.floor(tonumber(val) or 0)))
    fact.custom_accent = -1
    fact.accent_auto = false
    broadcast_theme()
end)

on("custom_accent_apply", function()
    if not preference_store.ready() then return end
    local r, g, b = Style.parse_hex(text.custom_accent_edit or "")
    if not r then text.custom_accent_status = "Enter a solid colour as #RRGGBB or #RGB"; return end
    fact.custom_accent, fact.accent_auto = r * 65536 + g * 256 + b, false
    broadcast_theme()
end)
on("custom_accent_clear", function()
    if not preference_store.ready() then return end
    fact.custom_accent = -1
    broadcast_theme()
end)
for _, option in ipairs({ { "style_text_pick", "style_text" }, { "style_glass_pick", "style_glass" } }) do
    on(option[1], function(value)
        value = tonumber(value)
        if not preference_store.ready() or not value or value ~= math.floor(value) or value < 0 or value > 2 then return end
        fact[option[2]] = value
        broadcast_theme()
    end)
end

-- Picked by wallpapers.luau from the wallpaper (only while "match the wallpaper" is on).
on("auto_accent", function(val)
    if fact.accent_auto == true then
        fact.accent = math.max(0, math.min(6, math.floor(tonumber(val) or 0)))
        broadcast_theme()
    end
end)

on("toggle_accent_auto", function()
    fact.accent_auto = not (fact.accent_auto == true)
    broadcast_theme()
    if fact.accent_auto == true then extract_current() end        -- always from the wallpaper that is on now
end)

local appearance_undo = nil
local function apply_appearance(target)
    palette_generation = palette_generation + 1
    local plan = preferences.appearance_plan(preferences.appearance_snapshot(fact, PAL), target)
    for _, entry in ipairs(preferences.APPEARANCE) do fact[entry.fact] = plan.values[entry.fact] end
    if plan.restore_palette then PAL = plan.restore_palette end
    local mode = tonumber(fact.appearance) or 1
    fact.dark_mode = mode == 1 or (mode == 2 and auto_dark())
    broadcast_theme()
    save_prefs()
    save_palette()
    if fact.accent_auto == true and not plan.restore_palette then extract_current() end
end
on("reset_appearance_review", function()
    if not preference_store.ready() then
        text.preference_status = "Preferences are unavailable; restore is disabled"
        return
    end
    fact.reset_review, fact.reset_sel = true, 0
end)
on("reset_appearance_cancel", function() fact.reset_review = false end)
local function reset_appearance()
    if not fact.reset_review or not preference_store.ready() then return end
    appearance_undo = preferences.appearance_snapshot(fact, PAL)
    fact.reset_review, fact.reset_undo = false, true
    apply_appearance(preferences.appearance_defaults())
end
on("reset_appearance_apply", reset_appearance)
on("reset_appearance_activate", function()
    if fact.reset_sel == 1 then reset_appearance() else fact.reset_review = false end
end)
on("reset_appearance_undo", function()
    if not appearance_undo or not preference_store.ready() then return end
    apply_appearance(appearance_undo)
    appearance_undo, fact.reset_undo = nil, false
end)

require("settings_looks")(preferences, {
    current = function() return preferences.appearance_snapshot(fact, PAL) end,
    facts = function() return fact end,
    palette = function() return PAL end,
    ready = preference_store.ready,
    apply = function(previous, target)
        appearance_undo, fact.reset_undo = previous, true
        apply_appearance(target)
    end,
})

for _, setting in ipairs({ {"bar_left_order_pick", "bar_left_order", 1}, {"bar_right_order_pick", "bar_right_order", 1}, {"module_output_pick", "module_output_policy", 2}, {"dock_output_pick", "dock_output_policy", 2}, {"dock_show_delay_pick", "dock_show_delay", 2} }) do
    on(setting[1], function(n)
        n = tonumber(n)
        if not preference_store.ready() or not n or n ~= math.floor(n) or n < 0 or n > setting[3] then return end
        fact[setting[2]] = n; changed_pref()
    end)
end
on("frame_output_save", function()
    if not preference_store.ready() then return end
    local name = tostring(text.frame_output_edit or ""):match("^%s*(.-)%s*$")
    if #name > 64 or (name ~= "" and not name:match("^[%w_.:+%-]+$")) then
        text.frame_output_status = "Use an output name, for example HDMI-A-1"; return
    end
    text.frame_output_name = name
    save_prefs()
    text.frame_output_status = name == "" and "Named policy will follow the focused output" or "Saved · a disconnected output falls back to the focused output"
end)

-- ── Menu bar & dock ──────────────────────────────────────────────
on("toggle_hour12", function()
    fact.hour12 = not (fact.hour12 ~= false)
    broadcast_theme()
end)
on("toggle_seconds", function() fact.pref_seconds = not b(fact.pref_seconds); changed_pref() end)
on("toggle_weather", function() fact.pref_weather = not b(fact.pref_weather); changed_pref() end)
on("toggle_apps", function()
    fact.pref_apps = not b(fact.pref_apps)
    changed_pref()
    if fact.pref_apps == true then
        apply_apps()
    else
        sh('D=$(cat "$HOME/.config/beskar/shell-dir" 2>/dev/null) || exit 0; sh "$D/shell/appthemes.sh" remove')
    end
end)
on("toggle_widgets", function() fact.pref_widgets = not b(fact.pref_widgets); changed_pref() end)
on("widgets_edit", function() fact.open = false; say("widgets", "emit edit_toggle") end)
on("widgets_reset", function() say("widgets", "emit w_reset") end)
on("toggle_tray", function() fact.pref_tray = not b(fact.pref_tray); changed_pref() end)
on("toggle_dock_auto", function() fact.pref_dock_auto = not b(fact.pref_dock_auto); changed_pref() end)
local function enum_option(value, maximum)
    local n = tonumber(value)
    if not n or n ~= n or n < 0 or n > maximum or n ~= math.floor(n) then return nil end
    return n
end
for _, option in ipairs({ {"toggle_workspaces", "pref_workspaces"}, {"toggle_bar_apps", "pref_bar_apps"}, {"toggle_updates", "pref_updates"} }) do
    local event, key = option[1], option[2]
    on(event, function() fact[key] = not b(fact[key]); changed_pref() end)
end
for _, option in ipairs({ {"dock_size_pick", "dock_size_i"}, {"dock_delay_pick", "dock_delay_i"}, {"wallpaper_fx_pick", "wallpaper_fx"} }) do
    local event, key = option[1], option[2]
    on(event, function(value)
        local n = enum_option(value, 2)
        if n then fact[key] = n; changed_pref() end
    end)
end
on("bar_style_pick", function(n) fact.bar_style = tonumber(n) or 0; changed_pref() end)

-- Topbar owns pin IDs/order and writes the file; Settings only presents its snapshot.
local dock_pins, selected_pin = {}, nil
on("set_dock_pins", function(rows)
    if type(rows) ~= "table" then return end
    local view, next_rows = {}, {}
    local selection = math.max(0, tonumber(fact.pin_sel) or 0)
    for _, row in ipairs(rows) do
        if #next_rows >= 12 then break end
        if type(row) == "table" and type(row.pin) == "string" and type(row.index) == "number" then
            local idx = #next_rows
            next_rows[#next_rows + 1] = row
            view[#view + 1] = { name = tostring(row.name or row.pin), idx = idx, mvl = row.mvl == true, mvr = row.mvr == true }
            if row.pin == selected_pin then selection = idx end
        end
    end
    dock_pins, model.dock_pins = next_rows, view
    fact.pin_sel = math.max(0, math.min(selection, #next_rows - 1))
end)
on("pin_open", function() fact.pin_edit = true; emit("Topbar.request_dock_pins") end)
on("pin_close", function() fact.pin_edit = false end)
on("pin_step", function(delta)
    if #dock_pins > 0 then fact.pin_sel = ((tonumber(fact.pin_sel) or 0) + (tonumber(delta) == -1 and -1 or 1)) % #dock_pins end
end)
local function move_pin(index, direction)
    index = tonumber(index)
    if not index or index < 0 then index = tonumber(fact.pin_sel) or 0 end
    local row = dock_pins[index + 1]
    if not row or (direction < 0 and not row.mvl) or (direction > 0 and not row.mvr) then return end
    selected_pin = row.pin
    fact.pin_sel = index
    emit("Topbar.dock_move_pin", { id = row.index, direction = direction })
end
on("pin_left", function(index) move_pin(index, -1) end)
on("pin_right", function(index) move_pin(index, 1) end)

-- ── Notifications ────────────────────────────────────────────────
on("toggle_dnd", function() emit("Notifications.set_dnd", not (fact["Notifications.dnd"] == true)) end)
on("lock_pick", function(n)
    fact.lock_i = tonumber(n) or 0
    save_prefs()
    -- idle.sh lives next to start.sh: find the shell's folder from where the scene runs
    sh('d=$(cat "$HOME/.config/beskar/shell-dir" 2>/dev/null); [ -x "$d/shell/idle.sh" ] && "$d/shell/idle.sh" "$1"', nil, tostring(LOCK_MINUTES[fact.lock_i] or 0))
end)
on("toggle_group", function() fact.group_apps = not b(fact.group_apps); changed_pref() end)
on("toggle_banners", function() fact.banners = not b(fact.banners); changed_pref() end)
on("banner_secs_pick", function(n) fact.banner_i = tonumber(n) or 1; changed_pref() end)
on("clear_notif_history", function() emit("Notifications.clear_past") end)

-- ── Sound ────────────────────────────────────────────────────────
local out_ids = {}
sys.watch("audio", function(a)
    a = a or {}
    fact.in_level = a.input or 0
    local rows = {}
    out_ids = {}
    for _, o in ipairs(a.outputs or {}) do
        if #rows < 4 then
            out_ids[#rows + 1] = o.id
            rows[#rows + 1] = { name = o.name or "Output", def = o.default == true }
        end
    end
    model.outs = rows
end)

on("volume_set", function(val) pcall(sys.call, "audio.volume", tonumber(val) or 0) end)
on("input_set", function(val) pcall(sys.call, "audio.input", tonumber(val) or 0) end)
on("toggle_mute", function() pcall(sys.call, "audio.mute") end)
on("pick_out", function(i)
    local id = out_ids[(tonumber(i) or 0) + 1]
    if id ~= nil then
        pcall(sys.call, "audio.default", id)
    end
end)
on("brightness_set", function(val) pcall(sys.call, "brightness.level", math.max(0.05, tonumber(val) or 1)) end)

-- ── Displays (niri) ──────────────────────────────────────────────
local outputs, disp_names, disp_sel = {}, {}, 0
local SCALES = { 1, 1.25, 1.5, 2 }
local res_opts, hz_opts = {}, {}

local function paint_displays()
    local rows = {}
    for i, name in ipairs(disp_names) do
        local d = outputs[name]
        local make = ((d.model and d.model ~= "") and d.model or (d.make or "")):gsub("^%s+", ""):gsub("%s+$", "")
        local mode = d.modes and d.current_mode and d.modes[d.current_mode + 1]
        rows[#rows + 1] = {
            name = name, title = make ~= "" and make or "Display", sel = (i - 1) == disp_sel,
            mode = mode and string.format("%d × %d @ %d Hz", mode.width, mode.height, math.floor(mode.refresh_rate / 1000 + 0.5)) or "",
        }
        if #rows >= 4 then break end
    end
    model.disps = rows

    local name = disp_names[disp_sel + 1]
    local d = name and outputs[name]
    res_opts, hz_opts = {}, {}
    local resl, hzl = {}, {}
    if d and d.modes then
        local cur = d.modes[(d.current_mode or 0) + 1]
        local seen_res, seen_hz = {}, {}
        local mods = {}
        for _, m in ipairs(d.modes) do mods[#mods + 1] = m end
        table.sort(mods, function(a, c)
            if a.width * a.height ~= c.width * c.height then return a.width * a.height > c.width * c.height end
            return a.refresh_rate > c.refresh_rate
        end)
        for _, m in ipairs(mods) do
            local key = m.width .. "x" .. m.height
            if not seen_res[key] and #res_opts < 4 then
                seen_res[key] = true
                res_opts[#res_opts + 1] = m
                resl[#resl + 1] = { label = m.width .. " × " .. m.height, cur = cur and cur.width == m.width and cur.height == m.height }
            end
            if cur and m.width == cur.width and m.height == cur.height then
                local hz = math.floor(m.refresh_rate / 1000 + 0.5)
                if not seen_hz[hz] and #hz_opts < 5 then
                    seen_hz[hz] = true
                    hz_opts[#hz_opts + 1] = m
                    hzl[#hzl + 1] = { label = hz .. " Hz", cur = cur.refresh_rate == m.refresh_rate }
                end
            end
        end
        local sc = d.logical and d.logical.scale or 1
        local si = 0
        for i, v in ipairs(SCALES) do
            if math.abs(v - sc) < 0.01 then si = i - 1 end
        end
        fact.disp_scale_i = si
    end
    model.reslist = resl
    model.hzlist = hzl
end

local function refresh_displays()
    run("niri", { "msg", "-j", "outputs" }, function(out, code)
        local ok, o = pcall(json.decode, out or "")
        if code ~= 0 or not ok or type(o) ~= "table" then
            return
        end
        outputs, disp_names = o, {}
        for name in pairs(o) do
            disp_names[#disp_names + 1] = name
        end
        table.sort(disp_names)
        if disp_sel >= #disp_names then disp_sel = 0 end
        paint_displays()
    end)
end

local preview_display = require("settings_display")(refresh_displays)
local function niri_output(args)
    local name = disp_names[disp_sel + 1]
    if name then preview_display(name, args[1], args[2]) end
end

on("disp_pick", function(i) disp_sel = tonumber(i) or 0; paint_displays() end)
on("disp_scale", function(i)
    local v = SCALES[(tonumber(i) or 0) + 1]
    if v then niri_output({ "scale", tostring(v) }) end
end)
local function mode_arg(m)
    return string.format("%dx%d@%.3f", m.width, m.height, m.refresh_rate / 1000)
end
on("disp_res", function(i)
    local m = res_opts[(tonumber(i) or 0) + 1]
    if m then niri_output({ "mode", mode_arg(m) }) end
end)
on("disp_hz", function(i)
    local m = hz_opts[(tonumber(i) or 0) + 1]
    if m then niri_output({ "mode", mode_arg(m) }) end
end)

-- ── Shortcuts: read from niri's own config ───────────────────────
local all_binds, bind_view, boff = {}, {}, 0
local MAX_BINDS = 9

local function paint_binds(reset)
    bind_view = require("shortcuts").search(all_binds, text.bind_q or "")
    if reset then boff = 0 end
    boff = math.max(0, math.min(boff, math.max(0, #bind_view - MAX_BINDS)))
    local rows = {}
    for i = boff + 1, math.min(#bind_view, boff + MAX_BINDS) do
        rows[#rows + 1] = bind_view[i]
    end
    model.binds = rows
    text.bind_count = (#bind_view) .. " shortcuts"
end

local shortcut_controller = require("settings_shortcuts")(actions, function(rows)
    for _, row in ipairs(rows) do
        row.origin = (row.path or ""):match("([^/]+)$") or "niri"
        row.origin = row.origin .. ":" .. tostring(row.line or 0) .. (row.editable and " · Beskar-owned" or " · Read-only")
    end
    all_binds = rows
    paint_binds(true)
end)
local function load_binds() shortcut_controller.load() end
on("text:bind_q", function() paint_binds(true) end)
on("bind_scroll", function(wheel)
    boff = boff + ((tonumber(wheel) or 0) > 0 and -1 or 1)
    paint_binds(false)
end)

-- ── navigation ───────────────────────────────────────────────────
local function tab_changed(v)
    local t = tonumber(v) or 0
    text.pane_title = TITLES[t] or "Settings"
    if t == 1 then refresh_displays()
    elseif t == 5 then load_binds()
    end
end
local function choose_tab(v)
    fact.shortcut_open = false
    fact.quiet_edit = false
    fact.look_open = false
    fact.pin_edit = false
    fact.reset_review = false
    fact.tab = tonumber(v) or 0
    -- A logic's own fact writes do not call its fact-change listener.
    tab_changed(fact.tab)
end
on("set_tab", choose_tab)
on("pick_cat", function(v) fact.setting_target = 0; fact.reset_review = false; choose_tab(v) end)
local settings_search = require("settings_search")(actions, choose_tab)
on("fact:tab", tab_changed)
on("fact:open", function(v)
    if v == true or v == 1 then
        local t = tonumber(fact.tab) or 0
        text.side_q = ""
        text.pane_title = TITLES[t] or "Settings"
        if t == 1 then refresh_displays() elseif t == 5 then load_binds() end
        apply_mode(false)
    end
end)

-- ── About This PC: read the machine, once ────────────────────────
run("sh", { "-c", [=[
. /etc/os-release 2>/dev/null
echo "${PRETTY_NAME:-Linux}"
grep -m1 'model name' /proc/cpuinfo | cut -d: -f2 | sed 's/^ *//' | sed "s/\$/ ($(nproc) threads)/"
(lspci 2>/dev/null | grep -E 'VGA|3D|Display' | sed -E 's/^[^ ]+ [^:]+: *//; s/ \(rev.*//; s/.*\[([^]]*)\].*/\1/' | cut -c1-40 | paste -sd'+' | sed 's/+/ + /g') || true
awk '/MemTotal/ {printf "%.1f GB\n", $2/1048576}' /proc/meminfo
uname -r
df -h / --output=size,avail | tail -1 | awk '{print $1 " (" $2 " available)"}'
]=] }, function(out, code)
    if code ~= 0 or not out then
        return
    end
    local lines = {}
    for l in string.gmatch(out, "([^\n]*)\n?") do
        lines[#lines + 1] = l
    end
    text.about_os = lines[1] ~= "" and lines[1] or "Linux"
    text.about_cpu = lines[2] or ""
    text.about_gpu = (lines[3] and lines[3] ~= "") and lines[3] or "—"
    text.about_mem = lines[4] or ""
    text.about_kernel = lines[5] or ""
    text.about_disk = lines[6] or ""
end)

sh('hostname 2>/dev/null; uptime -p 2>/dev/null | sed "s/^up //"', function(out)
    local h, u = (out or ""):match("([^\n]*)\n([^\n]*)")
    text.about_host = (h and h ~= "") and h or "—"
    text.about_up = (u and u ~= "") and u or "—"
end)
every(60000, function()
    sh('uptime -p 2>/dev/null | sed "s/^up //"', function(out)
        local u = (out or ""):match("([^\n]+)")
        if u then text.about_up = u end
    end)
end)

local function session(kind)
    fact.open = false
    after(250, function()
        emit("Topbar.set_kind", tonumber(kind) or 0)
        emit("Topbar.open_panel", 5)
    end)
end
on("session_restart", function() session(1) end)
on("session_off", function() session(0) end)
on("session_lock", function()
    fact.open = false
    after(250, function() say("lock", "fact locked true") end)
end)

-- one panel at a time
-- a scene that starts later (the capture picker, on demand) asks for the look it missed
on("theme_sync", function()
    broadcast_theme(false)
    push_prefs()
end)

require("exclusive")("settings")

-- ── who is logged in: the full name if the account has one, else the login name ──
local function load_user_name()
    run("sh", { "-c", 'n=$(getent passwd "$(id -un)" | cut -d: -f5 | cut -d, -f1); [ -n "$n" ] && echo "$n" || id -un' }, function(out)
        local n = (out or ""):match("([^\n]+)")
        if n and n ~= "" then
            text.user_name = n
            text.avatar_initial = (n:sub(1, 1) or ""):upper()
        end
    end)
    -- a picture: ~/.face, ~/.face.icon or the account's icon
    run("sh", { "-c", 'for f in "$HOME/.face" "$HOME/.face.icon" "/var/lib/AccountsService/icons/$(id -un)"; do [ -f "$f" ] && echo "$f" && break; done' }, function(out)
        local path = (out or ""):match("([^\n]+)")
        if path and path ~= "" then
            text.avatar_path = path
            fact.has_avatar = true
        end
    end)
end
finish_preferences = function()
    for _, kind in ipairs(preferences.KINDS) do if not preference_store.state(kind) then return end end
    if fact.preferences_loaded then return end
    fact.preferences_loaded = true
    fact.preference_can_restore = preference_store.ready()
    local m = tonumber(fact.appearance) or 1
    fact.dark_mode = m == 1 or (m == 2 and auto_dark())
    broadcast_theme(false)
end
load_user_name()
load_palette()

after(5000, apply_apps)

-- ── Night light and power profile ────────────────────────────────
-- shell/nightlight.sh runs wlsunset (start.sh brings the saved choice back at login); the power profile is
-- power-profiles-daemon's, through powerprofilesctl.
local NL_MODES = { [0] = "off", "on", "auto" }
local NL_TEMPS = { [0] = 4500, 3800, 3200 }
local PROFILES = { [0] = "power-saver", "balanced", "performance" }

local function apply_night()
    local mode = NL_MODES[tonumber(fact.nl_mode_i) or 0] or "off"
    local k = NL_TEMPS[tonumber(fact.nl_temp_i) or 1] or 3800
    sh('D=$(cat "$HOME/.config/beskar/shell-dir" 2>/dev/null) || exit 0; sh "$D/shell/nightlight.sh" "$1" "$2"', nil, mode, tostring(k))
end

on("nl_mode_pick", function(n)
    fact.nl_mode_i = tonumber(n) or 0
    apply_night()
    changed_pref()
end)
on("nl_temp_pick", function(n)
    fact.nl_temp_i = tonumber(n) or 1
    if (tonumber(fact.nl_mode_i) or 0) > 0 then apply_night() end
    changed_pref()
end)

local function read_profile()
    sh("powerprofilesctl get 2>/dev/null", function(out)
        local cur = (out or ""):gsub("%s+", "")
        if cur == "" then
            fact.pp_ok = false
            return
        end
        fact.pp_ok = true
        for i = 0, 2 do
            if PROFILES[i] == cur then fact.pp_i = i end
        end
    end)
end
on("pp_pick", function(n)
    local i = tonumber(n) or 1
    sh("powerprofilesctl set " .. PROFILES[i] .. " 2>&1", function(out, code)
        if code ~= 0 then
            text.pp_note = "That mode is not available on this computer."
        else
            text.pp_note = ""
        end
        read_profile()
    end)
end)
read_profile()
