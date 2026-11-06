-- macOS Screen Capture & Recording Companion Logic

local rec_pid = nil
local timer_id = nil

local function get_pictures_dir()
    local home = os.getenv("HOME") or "~"
    local dir = home .. "/Pictures/Screenshots"
    os.execute("mkdir -p " .. dir)
    return dir
end

local function get_videos_dir()
    local home = os.getenv("HOME") or "~"
    local dir = home .. "/Videos/Captures"
    os.execute("mkdir -p " .. dir)
    return dir
end

on("capture", function()
    fact.open = false
    local m = fact.target_mode or 0
    local dir = get_pictures_dir()
    local filename = string.format("%s/Screen_Shot_%s.png", dir, os.date("%Y-%m-%d_%H-%M-%S"))

    after(250, function()
        if m == 0 then
            log("Capture: Capturing entire screen to", filename)
            os.execute(string.format("grim '%s' && wl-copy < '%s' &", filename, filename))
            os.execute("notify-send -a 'Screen Capture' 'Screenshot Taken' 'Saved to Screenshots and copied to clipboard' -i camera-photo &")
        elseif m == 1 then
            log("Capture: Capturing window...")
            os.execute(string.format("grim -g \"$(slurp)\" '%s' && wl-copy < '%s' &", filename, filename))
            os.execute("notify-send -a 'Screen Capture' 'Window Captured' 'Saved to Screenshots and copied to clipboard' -i camera-photo &")
        else
            log("Capture: Capturing selection area...")
            os.execute(string.format("grim -g \"$(slurp)\" '%s' && wl-copy < '%s' &", filename, filename))
            os.execute("notify-send -a 'Screen Capture' 'Portion Captured' 'Saved to Screenshots and copied to clipboard' -i camera-photo &")
        end
    end)
end)

on("toggle_record", function()
    if fact.recording == true then
        -- Stop recording
        fact.recording = false
        if timer_id then
            cancel_timer(timer_id)
            timer_id = nil
        end
        log("Capture: Stopping screen recording...")
        os.execute("pkill -INT -f wf-recorder")
        os.execute("notify-send -a 'Screen Capture' 'Screen Recording Saved' 'Video file saved in Videos/Captures' -i video-x-generic &")
        fact.open = false
    else
        -- Start recording
        fact.open = false
        after(300, function()
            local dir = get_videos_dir()
            local filename = string.format("%s/Screen_Recording_%s.mp4", dir, os.date("%Y-%m-%d_%H-%M-%S"))
            log("Capture: Starting screen recording to", filename)
            fact.recording = true
            fact.record_secs = 0
            
            -- Launch wf-recorder
            os.execute(string.format("wf-recorder -f '%s' 2>/dev/null &", filename))
            os.execute("notify-send -a 'Screen Capture' 'Recording Started' 'Press Cmd+Shift+5 to stop recording' &")

            local function tick()
                if fact.recording == true then
                    fact.record_secs = fact.record_secs + 1
                    timer_id = after(1000, tick)
                end
            end
            timer_id = after(1000, tick)
        end)
    end
end)
