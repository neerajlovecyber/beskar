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
    { id = 10, name = "Notes", icon = "󰎞", sizes = { 1, 2 }, def = 1 },
    { id = 11, name = "To-dos", icon = "󰄱", sizes = { 1, 2 }, def = 1 },
    { id = 12, name = "Timer", icon = "󰔛", sizes = { 1 }, def = 1 },
}
-- Shared catalogue metadata; content belongs to Personal, independently of card placement.
for _, k in ipairs(KINDS) do
    k.category = (k.id == 10 or k.id == 11) and "Personal" or "Desktop"
    k.options = (k.category == "Personal") and { content = "shared", editor = "personal" } or {}
    if k.id == 12 then k.category = "Activities"; k.options = { content = "shared", editor = "timer" } end
end
-- Per-card options (C4b). A card stores only what differs from the default: `card.opts = { lock = true, date = "off" }`.
-- `keys[1]` is always the default; an option's value travels as its 1-based index into `keys` (UI event code =
-- id * 10 + index). `kinds` lists the widget kinds an option applies to (nil = every kind). The kind-specific
-- options are explicit on purpose: a stack (C4c) adds its own keys here, never free-form data.
local OPTIONS = {
    lock    = { id = 1, label = "Lock position", keys = { false, true }, labels = { "Unlocked", "Locked" } },
    date    = { id = 2, label = "Date line", keys = { "inherit", "on", "off" }, labels = { "Automatic", "Show", "Hide" }, kinds = { 1 } },
    seconds = { id = 3, label = "Seconds", keys = { "inherit", "on", "off" }, labels = { "Automatic", "Show", "Hide" }, kinds = { 1 } },
    format  = { id = 4, label = "Time format", keys = { "inherit", "12", "24" }, labels = { "Automatic", "12-hour", "24-hour" }, kinds = { 1 } },
}
local OPTION_ORDER = { "lock", "date", "seconds", "format" }
for key, def in pairs(OPTIONS) do def.key = key end
local PRESETS = {
    { name = "Glance",    cards = { { 1, 1, 48, 72 }, { 3, 0, 48, 248 }, { 4, 0, 224, 248 } } },
    { name = "Dashboard", cards = { { 1, 1, 48, 72 }, { 2, 0, 400, 72 }, { 3, 0, 576, 72 }, { 5, 2, 48, 248 }, { 7, 2, 400, 248 } } },
    { name = "Focus",     cards = { { 1, 2, 48, 72 }, { 2, 0, 400, 72 } } },
    { name = "Listening", cards = { { 6, 1, 48, 72 }, { 1, 0, 400, 72 }, { 3, 0, 576, 72 } } },
    { name = "Bare",      cards = {} },
}
return { KINDS = KINDS, PRESETS = PRESETS, OPTIONS = OPTIONS, OPTION_ORDER = OPTION_ORDER }
