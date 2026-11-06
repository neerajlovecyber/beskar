-- Notification centre logic. The scene is the notification server; this only carries out the buttons.

on("dismiss_notice", function(id)
    if id then
        pcall(sys.call, "notifications.dismiss", id)
    end
end)

on("clear_notices", function()
    pcall(sys.call, "notifications.clear")
end)
