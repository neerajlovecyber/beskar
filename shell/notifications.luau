-- The notification centre and banner scene (notifications.plm): the body is notif.luau, run through the panels' client.
local module = require("panelclient")({ notifications = 2 })
module("notifications", require("notif"))
