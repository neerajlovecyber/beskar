-- Notification centre logic. The scene is the notification server; this only carries out the buttons.

on("dismiss_notice", function(id)
    if id then
        pcall(sys.call, "notifications.dismiss", id)
    end
end)

on("clear_notices", function()
    pcall(sys.call, "notifications.clear")
end)

-- A notification centre keeps what arrived until somebody dismisses it. Without this, anything that
-- asks to expire (most apps ask for ~5 s) leaves the list on its own and the centre is empty by the time
-- you open it.
sys.watch("notifications", function() end)   -- the service has to be running for `keep`
local ok, err = pcall(sys.call, "notifications.keep", true)
log("notifications.keep", ok, err)
