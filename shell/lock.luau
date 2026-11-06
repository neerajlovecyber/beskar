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
