-- The wallpaper scene's logic: show the saved wallpaper at start, and reveal each new one the picker sends.
--
-- The renderer never trusts a path. pleamar does not say whether an `image` loaded and a failed one draws nothing, so
-- every picture is proved (readable, JPEG / PNG / WebP, one frame, sane size, decodes) by wallpaper_store.luau's
-- script BEFORE its path reaches wp_b_path. The picture on screen (wp_a) is only replaced after the new one has been
-- shown over it, so a rejected path leaves the current wallpaper exactly as it was. Favourites and the choice of what
-- to show belong to the picker; this file only paints, and (for "restore previous") swaps the two files through the
-- same script the picker uses.
local Store = require("wallpaper_store")
local Style = require("style_options")

-- Reduced motion (C2b): this process has no Settings facts of its own, so it learns the preference the way it learns the
-- transition: the saved prefs.json at start, and Settings' `fact reduce_motion` live. pleamar's `motion.reduced` then makes the
-- rv spring settle at once (the reveal ends in the same state: wp_a_path = the new picture, wp_go back to false) and only the
-- hold below is shortened. The portal's own value is kept as the fallback when the preference goes off.
local motion = Style.bind_motion({ fact = fact, on = on })
local told = false     -- Settings said it: the start-up read must not replace it

local shown = ""           -- wp_a: what is on screen
local busy = false         -- a reveal is running
local queued = nil         -- the newest validated path that arrived during a reveal
local seq = 0              -- the newest request; an older one still validating is dropped when it answers
local touched = false      -- a request arrived: the start-up read must not replace it

local function reveal(path)
    if busy then queued = path return end
    if path == "" or path == shown then return end
    busy = true
    local wait = Style.wallpaper_timing(motion.reduced())
    text.wp_b_path = path
    after(wait.load, function()        -- let the new picture load before it grows over the old one
        fact.wp_go = true
        after(wait.reveal, function()
            text.wp_a_path = path
            shown = path
            after(wait.settle, function()
                fact.wp_go = false
                busy = false
                if queued then
                    local nxt = queued
                    queued = nil
                    reveal(nxt)
                end
            end)
        end)
    end)
end

-- `text wp_new PATH` (the picker, `--say wallpaper "text wp_new /x.jpg"`): validate, then reveal. A bad one is only
-- logged: the wallpaper stays.
on("text:wp_new", function(raw)
    local path = Store.clean_path(raw)
    if path == "" then return end
    text.wp_new = ""                   -- so saying the same path again later is a change, not a repeat
    touched = true
    if path == shown and not busy and not queued then return end
    local ok, _, why = Store.valid_path(path)
    if not ok then
        log("wallpaper: ignored a request:", why, path)
        return
    end
    seq = seq + 1
    local mine = seq
    Store.check(nil, path, function(r)
        if mine ~= seq then return end -- a newer request is on its way
        if not r.ok then
            log("wallpaper: kept the current picture, " .. tostring(r.code) .. ": " .. tostring(r.message), path)
            return
        end
        reveal(r.path)
    end)
end)

-- `--say wallpaper "emit restore_previous"`: back to the previous wallpaper (the files swap: again goes forward).
-- The picker normally runs Store.restore itself (it must also refresh the colours); this is the same thing for the CLI.
on("restore_previous", function()
    touched = true
    seq = seq + 1
    local mine = seq
    Store.restore(nil, function(r)
        if mine ~= seq then return end
        if not r.ok then
            log("wallpaper: nothing to restore, " .. tostring(r.code) .. ": " .. tostring(r.message))
            return
        end
        reveal(r.path)
    end)
end)

-- At start: the saved wallpaper if it is still a good picture, else the previous one, else a bundled one. Nothing is
-- rewritten; with none usable the dark base box stays (nothing else to show).
Store.boot(nil, function(r)
    if touched or shown ~= "" then return end
    if not r.ok then
        log("wallpaper: no usable picture at start, " .. tostring(r.code))
        return
    end
    if r.source ~= "current" then
        log("wallpaper: the saved wallpaper is unusable, showing the " .. tostring(r.source) .. " one", r.path)
    end
    shown = r.path
    text.wp_a_path = r.path
end)

-- The transition Settings chose lives in prefs.json (`wallpaper_fx`); Settings also says `fact wp_fx N` live. Read it
-- once so a restarted wallpaper process does not fall back to the circle (anything told meanwhile wins).
Store.read_fx(nil, function(n)
    if n ~= nil and fact.wp_fx == 0 then fact.wp_fx = n end
end)

-- Reduced motion: `fact reduce_motion` from Settings, else the saved `"reduce_motion"` preference.
on("fact:reduce_motion", function(v)
    told = true
    motion.set(v)
end)
run("sh", Store.argv("prefs"), function(out)
    if told or fact.reduce_motion then return end
    if Style.parse_reduce_motion(out) then motion.set(true) end
end)
