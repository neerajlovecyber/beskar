-- What the widgets scene and the widget bar both need to know: the kinds of widget and the layout presets.
local KINDS = {
    { id = 1, name = "Clock",    icon = "󰥔", sizes = { 0, 1, 2 }, def = 1 },
    { id = 2, name = "Date",     icon = "󰃭", sizes = { 0, 1 },    def = 0 },
    { id = 3, name = "Weather",  icon = "󰖙", sizes = { 0, 1, 2 }, def = 0 },
    { id = 4, name = "Battery",  icon = "󰁹", sizes = { 0, 1 },    def = 0 },
    { id = 5, name = "System",   icon = "󰍹", sizes = { 0, 1, 2 }, def = 1 },
    { id = 6, name = "Music",    icon = "󰎆", sizes = { 1 },       def = 1 },
    { id = 7, name = "Calendar", icon = "󰸗", sizes = { 2 },       def = 2 },
    { id = 8, name = "Day",      icon = "󰔟", sizes = { 0, 1 },    def = 0 },
    { id = 9, name = "Controls", icon = "󰕾", sizes = { 1 },       def = 1 },
}
local PRESETS = {
    { name = "Glance",    cards = { { 1, 1, 48, 72 }, { 3, 0, 48, 248 }, { 4, 0, 224, 248 } } },
    { name = "Dashboard", cards = { { 1, 1, 48, 72 }, { 2, 0, 400, 72 }, { 3, 0, 576, 72 }, { 5, 2, 48, 248 }, { 7, 2, 400, 248 } } },
    { name = "Focus",     cards = { { 1, 2, 48, 72 }, { 2, 0, 400, 72 } } },
    { name = "Listening", cards = { { 6, 1, 48, 72 }, { 1, 0, 400, 72 }, { 3, 0, 576, 72 } } },
    { name = "Bare",      cards = {} },
}
return { KINDS = KINDS, PRESETS = PRESETS }
