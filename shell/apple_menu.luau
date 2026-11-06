-- macOS Apple Menu Companion Logic
on("action_settings", function()
    run("gnome-control-center", {})
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
    run("gnome-control-center", { "info-overview" })
end)
