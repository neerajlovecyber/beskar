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
    notify(title, "Saved to Pictures/Screenshots and copied to the clipboard")
end

on("capture", function()
    fact.open = false
    local m = fact.target_mode or 0
    -- let the HUD fade out before the picture is taken
    after(350, function()
        if m == 1 then
            -- the focused window, by niri itself (saved and copied)
            run("niri", { "msg", "action", "screenshot-window" }, nil, { output = false })
            return
        end
        dir_of("Pictures/Screenshots", function(dir)
            local file = string.format("%s/Screen_Shot_%s.png", dir, stamp())
            if m == 0 then
                focused_output(function(name)
                    local args = name ~= "" and { "-o", name, file } or { file }
                    run("grim", args, function(_, code)
                        if code == 0 then
                            finish_still(file, "Screenshot taken")
                        else
                            notify("Screenshot failed", "grim could not capture the screen", "dialog-error")
                        end
                    end)
                end)
            else
                -- a region: slurp asks for it, then grim takes it (cancelled with Esc: nothing happens)
                run("slurp", {}, function(region, code)
                    region = (region or ""):gsub("%s+$", "")
                    if code ~= 0 or region == "" then
                        return
                    end
                    run("grim", { "-g", region, file }, function(_, c2)
                        if c2 == 0 then
                            finish_still(file, "Portion captured")
                        end
                    end)
                end)
            end
        end)
    end)
end)

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

on("toggle_record", function()
    if rec_running then
        stop_recording()
        return
    end
    fact.open = false
    after(350, function()
        dir_of("Videos/Captures", function(dir)
            focused_output(function(name)
                local file = string.format("%s/Screen_Recording_%s.mp4", dir, stamp())
                local args = name ~= "" and { "-o", name, "-f", file } or { "-f", file }
                rec_file = file
                rec_running = true
                secs = 0
                fact.recording = true
                fact.record_secs = 0
                to_topbar("text rec_time 0:00")
                to_topbar("fact rec_on true")
                spawn("wf-recorder", args, function() end, function(_, code)
                    -- it ended (we stopped it, or it died): put everything back
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
        end)
    end)
end)
