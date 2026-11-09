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
            cb(o.name or "", l.x or 0, l.y or 0)
        else
            cb("", 0, 0)
        end
    end)
end

local frozen = nil      -- the picture shown behind the picker
local frozen_out = nil  -- its monitor, and where that monitor sits (for recording a region)
local frozen_x, frozen_y = 0, 0

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
    focused_info(function(name, lx, ly)
        local file = string.format("/tmp/beskar-cap-%d.png", os.time())
        local args = name ~= "" and { "-o", name, file } or { file }
        run("grim", args, function(_, code)
            if code ~= 0 then
                notify("Screenshot failed", "grim could not capture the screen", "dialog-error")
                return
            end
            drop_frozen()
            frozen, frozen_out, frozen_x, frozen_y = file, name, lx, ly
            text.shot_path = file
            fact.has_sel = false
            fact.sel_w = 0
            fact.sel_h = 0
            after(120, function() fact.open = true end)
        end)
    end)
end)

on("do_screen", function()
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
end)

on("do_window", function()
    fact.open = false
    local k = fact.kind or 0
    after(350, function()
        if k == 1 then
            start_recording(nil)
        else
            run("niri", { "msg", "action", "screenshot-window" }, nil, { output = false })
        end
    end)
end)

on("do_region", function()
    local x, y = math.floor(fact.sel_x or 0), math.floor(fact.sel_y or 0)
    local w, h = math.floor(fact.sel_w or 0), math.floor(fact.sel_h or 0)
    local sw = math.floor(fact.scr_w or 1920)
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
end)

on("toggle_record", function()
    if rec_running then
        stop_recording()
    end
end)
