-- The Control Center scene (controlcenter.plm): its panel body is cc.luau, run through the panels' client (panelclient.luau).
local module = require("panelclient")({ control_center = 1 })
module("control_center", require("cc"))
