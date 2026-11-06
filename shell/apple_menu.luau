-- macOS Apple Menu Companion Logic
on("action_settings", function()
    pcall(sys.call, "say", "settings", "fact tab 0")
    pcall(sys.call, "say", "settings", "fact open true")
end)

on("action_lock", function()
    run("loginctl", { "lock-session" })
end)

on("action_restart", function()
    run("systemctl", { "reboot" })
end)

on("action_power", function()
    run("systemctl", { "poweroff" })
end)

on("action_about", function()
    pcall(sys.call, "say", "settings", "fact tab 7")
    pcall(sys.call, "say", "settings", "fact open true")
end)
