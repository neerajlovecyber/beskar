-- Lock screen logic. The password is checked by PAM (`auth.check`); there is no other way in.
-- The screen is held by the compositor (ext-session-lock): if this process dies the session stays locked, and
--     XDG_RUNTIME_DIR=/run/user/$UID WAYLAND_DISPLAY=wayland-1 bin/pleamar --say lock "fact locked false"
-- from a text console gets you back.

local function say(scene, words)
    pcall(sys.call, "say", scene, words)
end

-- ── the clock: big time (no AM / PM, no leading zero) and the date ──
local function paint_clock()
    local h12 = fact.hour12 ~= false
    local t = h12 and os.date("%I:%M") or os.date("%H:%M")
    if h12 then t = t:gsub("^0", "") end
    local d = os.date("%A, %d %B"):gsub(", 0", ", ")
    if text.big_time ~= t then text.big_time = t end
    if text.date_line ~= d then text.date_line = d end
end
paint_clock()
every(1000, paint_clock)

-- ── who you are ──
local function load_user()
    run("sh", { "-c", 'n=$(getent passwd "$(id -un)" | cut -d: -f5 | cut -d, -f1); [ -n "$n" ] && echo "$n" || id -un' }, function(out)
        local n = (out or ""):match("([^\n]+)")
        if n and n ~= "" then
            text.user_name = n
            text.avatar_initial = n:sub(1, 1):upper()
        end
    end)
    run("sh", { "-c", 'for f in "$HOME/.face" "$HOME/.face.icon" "/var/lib/AccountsService/icons/$(id -un)"; do [ -f "$f" ] && echo "$f" && break; done' }, function(out)
        local path = (out or ""):match("([^\n]+)")
        if path and path ~= "" then
            text.avatar_path = path
            fact.has_avatar = true
        end
    end)
end
load_user()

local function load_wallpaper()
    run("sh", { "-c", 'cat "$HOME/.config/beskar/wallpaper" 2>/dev/null' }, function(out)
        local path = (out or ""):match("([^\n]+)")
        if path and path ~= "" then
            text.lock_wall = path
            fact.has_wall = true
        end
    end)
end
load_wallpaper()

-- ── locking and unlocking ──
local wrong_timer = nil

on("fact:locked", function()
    text.password = ""
    fact.checking = false
    fact.wrong = false
    text.lbl_restart = "Restart"
    text.lbl_off = "Shut Down"
    if fact.locked == true then
        load_wallpaper()
        paint_clock()
    end
end)

on("unlock", function()
    if fact.locked ~= true or fact.checking == true then return end
    local pwd = text.password
    if pwd == nil or pwd == "" then return end

    fact.checking = true
    fact.wrong = false
    local ok, valid = pcall(sys.ask, "auth.check", pwd)      -- a wrong one takes a couple of seconds, on purpose
    text.password = ""
    fact.checking = false

    if ok and valid == true then
        fact.locked = false
    else
        fact.wrong = true
        emit("wrong_password")
        if wrong_timer then cancel(wrong_timer) end
        wrong_timer = after(3000, function() fact.wrong = false; wrong_timer = nil end)
    end
end)

-- typing again clears the "incorrect" message
on("text:password", function()
    if fact.wrong == true and (text.password or "") ~= "" then
        fact.wrong = false
    end
end)

-- ── sleep / restart / shut down: the last two ask for a second tap, so a stray click does nothing ──
local armed = nil
local arm_timer = nil
local function two_taps(name, label_key, original, go)
    if armed == name then
        armed = nil
        go()
        return
    end
    armed = name
    text.lbl_restart = "Restart"
    text.lbl_off = "Shut Down"
    text[label_key] = "Tap again"
    if arm_timer then cancel(arm_timer) end
    arm_timer = after(3000, function()
        armed = nil
        text[label_key] = original
    end)
end

on("do_sleep", function()
    run("systemctl", { "suspend" }, nil, { output = false })
end)
on("do_restart", function()
    two_taps("restart", "lbl_restart", "Restart", function() run("systemctl", { "reboot" }, nil, { output = false }) end)
end)
on("do_off", function()
    two_taps("off", "lbl_off", "Shut Down", function() run("systemctl", { "poweroff" }, nil, { output = false }) end)
end)
