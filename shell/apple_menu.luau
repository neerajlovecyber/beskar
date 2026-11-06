-- macOS Apple Menu Companion Logic
on("action_settings", function()
    pcall(sys.call, "say", "settings", "fact tab 0")
    pcall(sys.call, "say", "settings", "fact open true")
end)

on("action_lock", function()
    log("Apple Menu: Triggering macOS Lock Screen...")
    pcall(sys.call, "say", "lock", "fact locked true")
end)

on("action_restart", function()
    log("Apple Menu: Opening Restart Confirmation...")
    pcall(sys.call, "say", "session", "fact kind 1")
    pcall(sys.call, "say", "session", "fact open true")
end)

on("action_power", function()
    log("Apple Menu: Opening Shut Down Confirmation...")
    pcall(sys.call, "say", "session", "fact kind 0")
    pcall(sys.call, "say", "session", "fact open true")
end)

on("action_about", function()
    pcall(sys.call, "say", "settings", "fact tab 7")
    pcall(sys.call, "say", "settings", "fact open true")
end)
