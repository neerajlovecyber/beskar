-- System Settings logic. Every control in settings.plm lands here.
--   look      mode (light / dark / auto), glass, accent  → broadcast to every scene and saved (pleamar_shell.json)
--   prefs     bar / dock / notification options          → saved in ~/.config/beskar/prefs.json, pushed to the scenes
--   system    sound, brightness, displays (niri msg), Wi-Fi, Bluetooth, updates, shortcuts (read from niri's config)

local THEMED = { "topbar", "control_center", "notifications", "dashboard", "settings", "wallpapers",
                "spotlight", "clipboard", "session", "capture", "appswitcher", "lock", "music", "widgets",
                "overview", "widget_bar", "polkit", "welcome" }

local function say(scene, words)
    pcall(sys.call, "say", scene, words)
end

local function sh(script, cb, ...)
    run("sh", { "-c", script, "x", ... }, cb, cb == nil and { output = false } or nil)
end

-- ── the sidebar ──────────────────────────────────────────────────
local CATS = {
    { 0, "󰏘", 0, "Appearance" }, { 1, "󰍹", 1, "Displays" }, { 2, "󰕾", 2, "Sound" },
    { 3, "󰒎", 3, "Notifications" }, { 4, "󰍜", 4, "Menu Bar & Dock" },
    { 5, "󰌌", 5, "Shortcuts" }, { 6, "󰋚", 6, "General" }, { 7, "󰚰", 7, "Software Update" },
    { 8, "󰌵", 8, "Night Light & Power" },
}
-- Nerd-font glyphs are not drawn symmetrically in their box: how far each one sits right of the middle (measured)
local GLYPH_DX = { [0] = 1, 1.5, 0.5, 1.5, 1, 1.5, 2, 2, 1 }
local TITLES = {}
for _, c in ipairs(CATS) do
    TITLES[c[1]] = c[4]
end

local function paint_cats()
    local q = (text.side_q or ""):lower()
    local rows = {}
    for _, c in ipairs(CATS) do
        if q == "" or c[4]:lower():find(q, 1, true) then
            rows[#rows + 1] = { idx = c[1], icon = c[2], tint = c[3], name = c[4], dx = GLYPH_DX[c[1]] or 0 }
        end
    end
    model.cats = rows
end
paint_cats()
on("text:side_q", paint_cats)


-- ── the palette engine ───────────────────────────────────────────
-- "Colours from the wallpaper": matugen (Material You, Rust) reads the wallpaper once and gives a whole palette for
-- light and for dark; we keep an accent (primary tone 60 dark / 50 light), a second colour (tertiary) and the
-- surface, and send the ones for the current mode to every scene as pal_* facts (theme.plm turns them into
-- accent_c, focus_c and bg_color). Saved in ~/.config/beskar/palette.json so a restart needs no extraction.
local PAL = nil
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
    if not words then return end
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
end

local function save_palette()
    if not PAL then return end
    local j = json.encode({ style = tonumber(fact.pal_style) or 0, src = PAL.src, dark = PAL.dark, light = PAL.light })
    sh('mkdir -p "$HOME/.config/beskar" && printf "%s\\n" "$1" > "$HOME/.config/beskar/palette.json"', nil, j)
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
    local style = PAL_STYLES[tonumber(fact.pal_style) or 0] or PAL_STYLES[0]
    run("magick", { path, "-resize", "120x120", "-colors", "12", "-format", "%c", "histogram:info:-" }, function(hist, hcode)
        local source = hcode == 0 and pick_source(hist) or nil
        if not source then return end
        run("matugen", { "color", "hex", source, "--json", "hex", "--dry-run", "-m", "dark", "-t", style }, function(out, code)
            if code ~= 0 or not out then return end
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

on("text:pal_src", function(path)
    if fact.accent_auto == true then
        extract_palette(path)
    end
end)

on("pal_style_pick", function(n)
    fact.pal_style = tonumber(n) or 0
    extract_current()
end)

local function load_palette()
    sh('cat "$HOME/.config/beskar/palette.json" 2>/dev/null', function(out)
        local ok, d = pcall(json.decode, out or "")
        if ok and type(d) == "table" and type(d.dark) == "table" and type(d.light) == "table" then
            PAL = { dark = d.dark, light = d.light, src = d.src }
            fact.pal_style = tonumber(d.style) or 0
            -- the other scenes may still be starting: send now and again a little later
            push_palette()
            after(3000, push_palette)
            after(8000, push_palette)
        end
        -- a palette left from another wallpaper must not outlive a restart: look at the one on now
        after(2500, function() if fact.accent_auto == true then extract_current() end end)
    end)
end

-- ── other apps: terminals, GTK / libadwaita (Nautilus), Qt ───────
-- shell/appthemes.sh renders matugen templates (assets/matugen) from one source colour and the mode, and adds one
-- include line to each app's own config. The source is the wallpaper's colour when "Colours from the wallpaper" is on,
-- else the chosen accent. Debounced: a theme change fires several broadcasts.
local ACCENT_HEX = { [0] = "#007aff", "#af52de", "#ff2d55", "#ff3b30", "#ff9500", "#34c759", "#8e8e93" }
local apps_timer = nil

function apply_apps()
    if apps_timer then cancel(apps_timer) end
    apps_timer = after(900, function()
        apps_timer = nil
        if fact.pref_apps ~= true then return end
        local dm = (fact.dark_mode == true or fact.dark_mode == 1)
        local src = ACCENT_HEX[tonumber(fact.accent) or 0] or ACCENT_HEX[0]
        if fact.accent_auto == true and PAL and PAL.src then src = PAL.src end
        local scheme = (PAL_STYLES[tonumber(fact.pal_style) or 0]) or "scheme-tonal-spot"
        if fact.accent_auto ~= true then scheme = "scheme-tonal-spot" end
        sh('D=$(cat "$HOME/.config/beskar/shell-dir" 2>/dev/null) || exit 0; sh "$D/shell/appthemes.sh" setup; sh "$D/shell/appthemes.sh" apply "$1" "$2" "$3"',
            nil, dm and "dark" or "light", src, scheme)
    end)
end

-- ── theme: mode, glass, accent, clock format ─────────────────────
local function save_theme(dm_str, skin_str, accent_str, auto_str, h12_str)
    -- ~/.config/pleamar_shell.json is read by start.sh to restore the look after a restart.
    local json_text = string.format('{"dark_mode": %s, "skin": %s, "accent": %s, "accent_auto": %s, "hour12": %s}', dm_str, skin_str, accent_str, auto_str, h12_str)
    sh("mkdir -p \"$HOME/.config\" && printf '%s\\n' '" .. json_text .. "' > \"$HOME/.config/pleamar_shell.json\"")
end

local function broadcast_theme()
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
    save_theme(dm_str, skin_str, accent_str, auto_str, h12_str)
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
    local j = string.format(
        '{"appearance": %d, "bar_style": %d, "seconds": %s, "weather": %s, "tray": %s, "dock_auto": %s, "widgets": %s, "apps": %s, "night": %d, "night_t": %d, "banners": %s, "banner_i": %d, "group": %s, "lock_min": %d}',
        tonumber(fact.appearance) or 1, tonumber(fact.bar_style) or 0, tostring(b(fact.pref_seconds)), tostring(b(fact.pref_weather)), tostring(b(fact.pref_tray)),
        tostring(b(fact.pref_dock_auto)), tostring(b(fact.pref_widgets)), tostring(b(fact.pref_apps)), tonumber(fact.nl_mode_i) or 0, tonumber(fact.nl_temp_i) or 1, tostring(b(fact.banners)), tonumber(fact.banner_i) or 1, tostring(b(fact.group_apps)), LOCK_MINUTES[tonumber(fact.lock_i) or 0] or 0)
    sh('mkdir -p "$HOME/.config/beskar" && printf "%s\\n" "$1" > "$HOME/.config/beskar/prefs.json"', nil, j)
end

local function push_prefs()
    say("topbar", "fact bar_style " .. tostring(tonumber(fact.bar_style) or 0))
    say("topbar", "fact pref_seconds " .. tostring(b(fact.pref_seconds)))
    say("topbar", "fact pref_weather " .. tostring(b(fact.pref_weather)))
    say("topbar", "fact pref_tray " .. tostring(b(fact.pref_tray)))
    say("topbar", "fact pref_dock_auto " .. tostring(b(fact.pref_dock_auto)))
    say("widgets", "fact widgets_on " .. tostring(b(fact.pref_widgets)))
    say("notifications", "fact banners " .. tostring(b(fact.banners)))
    say("notifications", "fact banner_ms " .. tostring(BANNER_MS[tonumber(fact.banner_i) or 1] or 5500))
    say("notifications", "fact group_apps " .. tostring(b(fact.group_apps)))
    say("notifications", "fact dnd " .. tostring(b(fact.dnd)))
end

local function changed_pref()
    save_prefs()
    push_prefs()
end

local function load_prefs()
    sh('cat "$HOME/.config/beskar/prefs.json" 2>/dev/null', function(out)
        local ok, p = pcall(json.decode, out or "")
        if ok and type(p) == "table" then
            if p.appearance ~= nil then fact.appearance = tonumber(p.appearance) or 1 end
            if p.bar_style ~= nil then fact.bar_style = tonumber(p.bar_style) or 0 end
            if p.seconds ~= nil then fact.pref_seconds = p.seconds == true end
            if p.weather ~= nil then fact.pref_weather = p.weather == true end
            if p.tray ~= nil then fact.pref_tray = p.tray == true end
            if p.dock_auto ~= nil then fact.pref_dock_auto = p.dock_auto == true end
            if p.widgets ~= nil then fact.pref_widgets = p.widgets == true end
            if p.apps ~= nil then fact.pref_apps = p.apps == true end
            if p.night ~= nil then fact.nl_mode_i = tonumber(p.night) or 0 end
            if p.night_t ~= nil then fact.nl_temp_i = tonumber(p.night_t) or 1 end
            if p.banners ~= nil then fact.banners = p.banners == true end
            if p.group ~= nil then fact.group_apps = p.group == true end
            if p.lock_min ~= nil then
                for i = 0, 4 do if LOCK_MINUTES[i] == tonumber(p.lock_min) then fact.lock_i = i end end
            end
            if p.banner_i ~= nil then fact.banner_i = tonumber(p.banner_i) or 1 end
        end
        -- the other scenes may still be starting: push now and once more a little later
        push_prefs()
        after(3000, push_prefs)
        after(8000, push_prefs)
    end)
end
-- the theme file start.sh restores: pick the clock format up from it too
sh('cat "$HOME/.config/pleamar_shell.json" 2>/dev/null', function(out)
    local ok, t = pcall(json.decode, out or "")
    if ok and type(t) == "table" and t.hour12 ~= nil then
        fact.hour12 = t.hour12 == true
    end
    load_prefs()
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
    fact.appearance = tonumber(n) or 1
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
    fact.skin = tonumber(val) or 0
    broadcast_theme()
end)

-- Picked by hand: that ends "match the wallpaper".
on("choose_accent", function(val)
    fact.accent = tonumber(val) or 0
    fact.accent_auto = false
    broadcast_theme()
end)

-- Picked by wallpapers.luau from the wallpaper (only while "match the wallpaper" is on).
on("auto_accent", function(val)
    if fact.accent_auto == true then
        fact.accent = tonumber(val) or 0
        broadcast_theme()
    end
end)

on("toggle_accent_auto", function()
    fact.accent_auto = not (fact.accent_auto == true)
    broadcast_theme()
    if fact.accent_auto == true then extract_current() end        -- always from the wallpaper that is on now
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
on("bar_style_pick", function(n) fact.bar_style = tonumber(n) or 0; changed_pref() end)

-- ── Notifications ────────────────────────────────────────────────
on("toggle_dnd", function() fact.dnd = not b(fact.dnd); changed_pref() end)
on("lock_pick", function(n)
    fact.lock_i = tonumber(n) or 0
    save_prefs()
    -- idle.sh lives next to start.sh: find the shell's folder from where the scene runs
    sh('d=$(cat "$HOME/.config/beskar/shell-dir" 2>/dev/null); [ -x "$d/shell/idle.sh" ] && "$d/shell/idle.sh" "$1"', nil, tostring(LOCK_MINUTES[fact.lock_i] or 0))
end)
on("toggle_group", function() fact.group_apps = not b(fact.group_apps); changed_pref() end)
on("toggle_banners", function() fact.banners = not b(fact.banners); changed_pref() end)
on("banner_secs_pick", function(n) fact.banner_i = tonumber(n) or 1; changed_pref() end)
on("clear_notif_history", function() say("notifications", "emit clear_past") end)

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

local function niri_output(args)
    local name = disp_names[disp_sel + 1]
    if not name then return end
    local full = { "msg", "output", name }
    for _, a in ipairs(args) do full[#full + 1] = a end
    run("niri", full, function() after(1500, refresh_displays) end)
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

local KEY_NAMES = {
    XF86AudioRaiseVolume = "Volume +", XF86AudioLowerVolume = "Volume −", XF86AudioMute = "Mute", XF86AudioMicMute = "Mic mute",
    XF86MonBrightnessUp = "Brightness +", XF86MonBrightnessDown = "Brightness −",
    XF86AudioPlay = "Play / Pause", XF86AudioNext = "Next track", XF86AudioPrev = "Previous track", XF86AudioStop = "Stop",
}

local function pretty_keys(k)
    local parts = {}
    for part in k:gmatch("[^%+]+") do
        part = KEY_NAMES[part] or part
        part = part:gsub("^Mod$", "Super"):gsub("^Comma$", ","):gsub("^Period$", "."):gsub("^Slash$", "/")
        part = part:gsub("^Return$", "Enter"):gsub("^BracketLeft$", "["):gsub("^BracketRight$", "]"):gsub("^Print$", "PrtSc")
        part = part:gsub("^Minus$", "−"):gsub("^Equal$", "="):gsub("^Next$", "Page Down"):gsub("^Prior$", "Page Up")
        parts[#parts + 1] = part
    end
    return table.concat(parts, " + ")
end

-- friendly words for niri actions and for the shell's own `start.sh <command>` binds
local ACTIONS = {
    ["consume-or-expel-window-left"] = "Move window into the left column",
    ["consume-or-expel-window-right"] = "Move window into the right column",
    ["consume-window-into-column"] = "Stack window into the column",
    ["expel-window-from-column"] = "Pull window out of the column",
    ["toggle-window-floating"] = "Float / tile window",
    ["fullscreen-window"] = "Fullscreen window",
    ["maximize-column"] = "Maximize column",
    ["center-column"] = "Centre column",
    ["center-visible-columns"] = "Centre visible columns",
    ["switch-preset-column-width"] = "Cycle column width",
    ["screenshot"] = "Screenshot (choose area)",
    ["screenshot-screen"] = "Screenshot the screen",
    ["screenshot-window"] = "Screenshot the window",
    ["close-window"] = "Close window",
    ["quit"] = "Quit niri",
    ["power-off-monitors"] = "Turn monitors off",
}
local SHELL_CMDS = {
    spotlight = "Spotlight", clipboard = "Clipboard history", notifications = "Notification centre", wallpapers = "Wallpapers",
    settings = "Settings", shortcuts = "Keyboard shortcuts", appswitcher = "App switcher", ["control-center"] = "Control Center",
    dashboard = "Dashboard", capture = "Screen capture", lock = "Lock screen",
    ["vol-up"] = "Volume up", ["vol-down"] = "Volume down", mute = "Mute", ["bright-up"] = "Brightness up", ["bright-down"] = "Brightness down",
}

local function humanize(action)
    local w = action:match("^([%w%-]+)") or action
    if ACTIONS[w] then return ACTIONS[w] end
    return (w:gsub("%-", " "):gsub("^%l", string.upper))
end

local function parse_binds(src)
    local map, order = {}, {}
    local inside = false
    for line in (src or ""):gmatch("[^\n]+") do
        local t = line:gsub("^%s+", "")
        if t:match("^binds%s*{") then
            inside = true
        elseif inside and t:match("^}%s*$") then
            inside = false
        elseif inside and not t:match("^//") then
            local key, attrs, body = t:match("^([%w_%+]+)%s*(.-)%s*{%s*(.-)%s*}%s*$")
            -- dms is not part of this shell: its binds ("dms ipc …") do nothing here
            if key and not body:match('^spawn%s+"dms"') then
                local title = attrs:match('hotkey%-overlay%-title="([^"]*)"')
                local what = title
                if not what then
                    local act = body:gsub(";%s*$", "")
                    local cmd, arg = act:match('^spawn%s+"([^"]*)"%s+"([^"]*)"')
                    if cmd and cmd:find("start%.sh$") and SHELL_CMDS[arg] then
                        what = SHELL_CMDS[arg]
                    elseif cmd then
                        what = humanize(arg or cmd:match("([^/]+)$") or cmd)
                    else
                        local one = act:match('^spawn%s+"([^"]*)"')
                        what = one and ("Open " .. (one:match("([^/]+)$") or one)) or humanize(act)
                    end
                end
                if not map[key] then order[#order + 1] = key end
                map[key] = what
            end
        end
    end
    local list = {}
    for _, k in ipairs(order) do
        list[#list + 1] = { keys = pretty_keys(k), what = map[k] }
    end
    table.sort(list, function(a, c) return a.what:lower() < c.what:lower() end)
    return list
end

local function paint_binds(reset)
    local q = (text.bind_q or ""):lower()
    bind_view = {}
    for _, e in ipairs(all_binds) do
        if q == "" or e.what:lower():find(q, 1, true) or e.keys:lower():find(q, 1, true) then
            bind_view[#bind_view + 1] = e
        end
    end
    if reset then boff = 0 end
    boff = math.max(0, math.min(boff, math.max(0, #bind_view - MAX_BINDS)))
    local rows = {}
    for i = boff + 1, math.min(#bind_view, boff + MAX_BINDS) do
        rows[#rows + 1] = bind_view[i]
    end
    model.binds = rows
    text.bind_count = (#bind_view) .. " shortcuts"
end

local function load_binds()
    sh('cat "$HOME/.config/niri/dms/binds.kdl" "$HOME/.config/niri/config.kdl" 2>/dev/null', function(out)
        all_binds = parse_binds(out)
        paint_binds(true)
    end)
end
on("text:bind_q", function() paint_binds(true) end)
on("bind_scroll", function(wheel)
    boff = boff + ((tonumber(wheel) or 0) > 0 and -1 or 1)
    paint_binds(false)
end)

-- ── Software update (pacman) ─────────────────────────────────────
local function check_updates()
    fact.up_checking = true
    text.up_title = "Checking…"
    text.up_sub = "Asking the package servers"
    sh('timeout 40 checkupdates 2>/dev/null', function(out, code)
        fact.up_checking = false
        local rows, n = {}, 0
        for line in (out or ""):gmatch("[^\n]+") do
            local name, old, new = line:match("^(%S+)%s+(%S+)%s+%->%s+(%S+)")
            if name then
                n = n + 1
                if #rows < 6 then
                    rows[#rows + 1] = { name = name, ver = old .. " → " .. new }
                end
            end
        end
        model.ups = rows
        fact.up_n = n
        if n == 0 then
            text.up_title = "Your system is up to date"
            text.up_sub = (code ~= 0 and code ~= 2) and "Could not reach the package servers" or "Nothing to install"
        else
            text.up_title = n .. (n == 1 and " update available" or " updates available")
            text.up_sub = (n > #rows) and ("Showing the first " .. #rows .. ". Update all installs everything.") or "Ready to install"
        end
    end)
end
on("check_updates", check_updates)
on("run_update", function()
    pcall(run, "kitty", { "-e", "sh", "-c", "paru -Syu || yay -Syu || sudo pacman -Syu; echo; read -p 'Done. Press Enter.' _" }, nil, { output = false })
end)
on("open_updates_tab", function() fact.tab = 7 end)

-- ── navigation ───────────────────────────────────────────────────
on("pick_cat", function(i) fact.tab = tonumber(i) or 0 end)
on("fact:tab", function(v)
    local t = tonumber(v) or 0
    text.pane_title = TITLES[t] or "Settings"
    if t == 1 then refresh_displays()
    elseif t == 5 then load_binds()
    elseif t == 7 and (fact.up_n or 0) == 0 then check_updates()
    end
end)
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
        say("session", "fact kind " .. kind)
        say("topbar", "emit open_panel 5")
    end)
end
on("session_restart", function() session(1) end)
on("session_off", function() session(0) end)
on("session_lock", function()
    fact.open = false
    after(250, function() say("lock", "fact locked true") end)
end)

-- one panel at a time
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
load_user_name()
load_palette()

-- A Settings that was restarted on its own starts with the defaults; it must take the saved look first, or the next
-- change would save (and broadcast) those defaults over the user's theme.
sh('cat "$HOME/.config/pleamar_shell.json" 2>/dev/null', function(out)
    local ok, t = pcall(json.decode, out or "")
    if ok and type(t) == "table" then
        if t.dark_mode ~= nil then fact.dark_mode = t.dark_mode == true end
        if t.skin ~= nil then fact.skin = tonumber(t.skin) or 0 end
        if t.accent ~= nil then fact.accent = tonumber(t.accent) or 0 end
        if t.accent_auto ~= nil then fact.accent_auto = t.accent_auto == true end
        if t.hour12 ~= nil then fact.hour12 = t.hour12 ~= false end
    end
end)
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
