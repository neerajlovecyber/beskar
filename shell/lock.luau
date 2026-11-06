-- macOS Wayland Lock Screen Companion Logic (PAM Authentication)

on("fact:locked", function()
    text.password = ""
    fact.checking = false
end)

on("unlock", function()
    if fact.locked ~= true or fact.checking == true then return end
    local pwd = text.password
    if pwd == nil or pwd == "" then return end

    fact.checking = true
    log("Lockscreen: Verifying password with PAM auth...")

    -- Asynchronous check or PAM verification
    local ok, valid = pcall(sys.ask, "auth.check", pwd)
    text.password = ""
    fact.checking = false

    if ok and valid == true then
        log("Lockscreen: Password correct! Unlocking session.")
        fact.locked = false
    else
        log("Lockscreen: Authentication failed.")
        emit("wrong_password")
    end
end)

-- ── who is logged in: the full name if the account has one, else the login name ──
local function load_user_name()
    run("sh", { "-c", 'n=$(getent passwd "$(id -un)" | cut -d: -f5 | cut -d, -f1); [ -n "$n" ] && echo "$n" || id -un' }, function(out)
        local n = (out or ""):match("([^\n]+)")
        if n and n ~= "" then
            text.user_name = n
        end
    end)
end
load_user_name()
