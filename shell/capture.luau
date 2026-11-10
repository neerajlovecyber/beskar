-- Screen capture and recording. The sandbox has no `os.execute`: everything goes through `run` / `spawn`.
--   still    grim (whole screen of the focused monitor, or a region from slurp) → file + clipboard
--   window   niri's own screenshot of the focused window (it saves and copies it itself)
--   record   wf-recorder on the focused monitor; the top bar shows a red dot and the time while it runs
--            (topbar.plm `rec_on`, `rec_time`), and a click there stops it

local rec_running = false
local rec_file = nil
local timer_id = nil
local secs = 0

local function to_topbar(words)
    pcall(sys.call, "say", "topbar", words)
end

local function notify(title, body, icon)
    run("notify-send", { "-a", "Screen Capture", "-i", icon or "camera-photo", title, body }, nil, { output = false })
end

local function stamp()
    return os.date("%Y-%m-%d_%H-%M-%S")
end

-- the monitor with the focus, as grim / wf-recorder name it ("" if niri does not say)
local function focused_output(cb)
    run("niri", { "msg", "-j", "focused-output" }, function(out)
        local ok, o = pcall(json.decode, out or "")
        cb((ok and type(o) == "table" and o.name) or "")
    end)
end

-- a directory under $HOME made on demand; the callback gets the full path
local function dir_of(sub, cb)
    run("sh", { "-c", 'd="$HOME/$1"; mkdir -p "$d" && printf %s "$d"', "x", sub }, function(out, code)
        if code == 0 and out and out ~= "" then
            cb(out)
        else
            notify("Capture failed", "Could not create " .. sub, "dialog-error")
        end
    end)
end

local function finish_still(file, title)
    run("sh", { "-c", 'wl-copy --type image/png < "$1"', "x", file }, nil, { output = false })
    to_topbar("text shot_path " .. file)
end

-- the monitor with the focus: name and where it sits in the global layout
local function focused_info(cb)
    run("niri", { "msg", "-j", "focused-output" }, function(out)
        local ok, o = pcall(json.decode, out or "")
        if ok and type(o) == "table" then
            local l = o.logical or {}
            cb(o.name or "", l.x or 0, l.y or 0, l.width or 0)
        else
            cb("", 0, 0, 0)
        end
    end)
end

local frozen = nil      -- the picture shown behind the picker
local frozen_out = nil  -- its monitor, and where that monitor sits (for recording a region)
local frozen_x, frozen_y, frozen_w = 0, 0, 0

local function drop_frozen()
    if frozen then
        run("rm", { "-f", frozen }, nil, { output = false })
        frozen = nil
    end
end

local function still_name(cb)
    dir_of("Pictures/Screenshots", function(dir)
        cb(string.format("%s/Screen_Shot_%s.png", dir, stamp()))
    end)
end

local do_screen_fn, do_window_fn, do_region_fn

local function stop_recording()
    if timer_id then
        cancel(timer_id)
        timer_id = nil
    end
    rec_running = false
    fact.recording = false
    to_topbar("fact rec_on false")
    run("pkill", { "-INT", "-x", "wf-recorder" }, nil, { output = false })
end

local function clock(sec)
    return string.format("%d:%02d", sec // 60, sec % 60)
end

local function tick()
    if not rec_running then
        return
    end
    secs = secs + 1
    fact.record_secs = secs
    to_topbar("text rec_time " .. clock(secs))
    timer_id = after(1000, tick)
end


local function start_recording(geom)
    dir_of("Videos/Captures", function(dir)
        local file = string.format("%s/Screen_Recording_%s.mp4", dir, stamp())
        local args = {}
        if geom then
            args = { "-g", geom, "-f", file }
        elseif frozen_out and frozen_out ~= "" then
            args = { "-o", frozen_out, "-f", file }
        else
            args = { "-f", file }
        end
        rec_file = file
        rec_running = true
        secs = 0
        fact.recording = true
        fact.record_secs = 0
        to_topbar("text rec_time 0:00")
        to_topbar("fact rec_on true")
        spawn("wf-recorder", args, function() end, function(_, code)
            local was = rec_running
            if timer_id then
                cancel(timer_id)
                timer_id = nil
            end
            rec_running = false
            fact.recording = false
            to_topbar("fact rec_on false")
            if was then
                notify("Recording failed", "wf-recorder stopped unexpectedly", "dialog-error")
            else
                notify("Recording saved", "Videos/Captures", "video-x-generic")
            end
        end)
        timer_id = after(1000, tick)
    end)
end

-- open the picker: the screen is frozen first, so what you select is what you saw
on("toggle", function()
    if fact.open then
        fact.open = false
        return
    end
    if rec_running then
        stop_recording()
        return
    end
    focused_info(function(name, lx, ly, lw)
        local file = string.format("/tmp/beskar-cap-%d.png", os.time())
        local args = name ~= "" and { "-o", name, file } or { file }
        run("grim", args, function(_, code)
            if code ~= 0 then
                notify("Screenshot failed", "grim could not capture the screen", "dialog-error")
                return
            end
            drop_frozen()
            frozen, frozen_out, frozen_x, frozen_y, frozen_w = file, name, lx, ly, lw
            text.shot_path = file
            fact.has_sel = false
            fact.sel_w = 0
            fact.sel_h = 0
            after(120, function() fact.open = true end)
        end)
    end)
end)

do_screen_fn = function()
    fact.open = false
    local k = fact.kind or 0
    after(350, function()
        if k == 1 then
            start_recording(nil)
        elseif frozen then
            still_name(function(dest)
                run("cp", { frozen, dest }, function(_, code)
                    if code == 0 then finish_still(dest, "Screenshot taken") end
                end)
            end)
        end
    end)
end
on("do_screen", do_screen_fn)

-- A screenshot of the whole monitor WITH the shell (grim sees every layer; niri's own screenshot-window draws the
-- window alone, without the bar, ring and dock). No picker: Ctrl+Print / Alt+Print and the picker's Window mode.
local function shot_now()
    focused_info(function(name)
        still_name(function(dest)
            local args = name ~= "" and { "-o", name, dest } or { dest }
            run("grim", args, function(_, code)
                if code == 0 then
                    finish_still(dest, "Screenshot taken")
                else
                    notify("Screenshot failed", "grim could not capture the screen", "dialog-error")
                end
            end)
        end)
    end)
end
on("shot_now", shot_now)

do_window_fn = function()
    fact.open = false
    local k = fact.kind or 0
    after(350, function()
        if k == 1 then
            start_recording(nil)
        else
            shot_now()
        end
    end)
end
on("do_window", do_window_fn)

local region_busy = false
do_region_fn = function()
    local x, y = math.floor(fact.sel_x or 0), math.floor(fact.sel_y or 0)
    local w, h = math.floor(fact.sel_w or 0), math.floor(fact.sel_h or 0)
    -- the monitor's logical width, known from niri (a key press cannot read `screen.width` in the scene: it is 0 there)
    local sw = frozen_w > 0 and frozen_w or math.floor(fact.scr_w or 0)
    if sw <= 0 then sw = 1920 end
    if region_busy then return end            -- one press can arrive from every copy of the surface
    region_busy = true
    after(1500, function() region_busy = false end)
    local k = fact.kind or 0
    fact.open = false
    if w < 4 or h < 4 then return end
    if k == 1 then
        local geom = string.format("%d,%d %dx%d", x + frozen_x, y + frozen_y, w, h)
        after(350, function() start_recording(geom) end)
        return
    end
    if not frozen then return end
    still_name(function(dest)
        local script = 'f="$1"; out="$2"; iw=$(magick identify -format %w "$f"); '
            .. 'magick "$f" -crop "$(($5*iw/$7))x$(($6*iw/$7))+$(($3*iw/$7))+$(($4*iw/$7))" +repage "$out"'
        run("sh", { "-c", script, "x", frozen, dest, tostring(x), tostring(y), tostring(w), tostring(h), tostring(sw) },
            function(_, code)
                if code == 0 then
                    finish_still(dest, "Screenshot taken")
                else
                    notify("Screenshot failed", "could not crop the picture", "dialog-error")
                end
            end)
    end)
end
on("do_region", do_region_fn)

-- Enter: take what the picker is set up for (a selected region, the focused window, or the whole screen)
on("confirm", function()
    local mode = fact.mode or 0
    if mode == 1 then
        do_window_fn()
    elseif mode == 2 then
        do_screen_fn()
    elseif fact.has_sel == true then
        do_region_fn()
    end
end)

on("toggle_record", function()
    if rec_running then
        stop_recording()
    end
end)

-- ── on demand: this scene is started by start.sh when you press Print (or shoot / record from Spotlight) and ends
-- itself when it has nothing to do, so an idle shell holds none of its (full-screen, two monitors) GPU memory.
-- It stays while a recording runs (the bar's red dot stops it through `toggle_record`).
local age = 0
every(2000, function()
    age = age + 2
    if age > 10 and fact.open ~= true and not rec_running then
        pcall(sys.call, "say", "capture", "quit")
    end
end)
