-- Pure descriptions for individual Settings controls. IDs stay stable across layout changes.
-- reveal is a numeric view target, not an action that changes a preference.
-- y/h describe the existing row in its page's native viewport. Keep these offsets
-- with row height/gap changes in settings.plm; search never creates another page.
local M = {}
M.controls = {
    { id = "appearance.mode", reveal = 1, tab = 0, name = "Appearance mode", section = "Appearance", keywords = "light dark auto schedule", icon = "󰏘" },
    { id = "appearance.skin", reveal = 2, tab = 0, name = "Window glass", section = "Appearance", keywords = "skin liquid acrylic solid opacity blur", icon = "󰏘" },
    { id = "appearance.wallpaper-colours", reveal = 3, tab = 0, name = "Colours from the wallpaper", section = "Appearance", keywords = "colors automatic accent palette matugen", icon = "󰏘" },
    { id = "appearance.app-themes", reveal = 4, tab = 0, name = "Theme other apps", section = "Appearance", keywords = "terminal gtk qt application colours colors", icon = "󰏘" },
    { id = "appearance.accent", reveal = 5, tab = 0, name = "Accent colour", section = "Appearance", keywords = "color blue purple pink red orange green graphite", icon = "󰏘" },
    { id = "appearance.palette", reveal = 6, tab = 0, name = "Wallpaper palette style", section = "Appearance", keywords = "tonal vibrant neutral soft matugen scheme", icon = "󰏘" },
}
local appearance_rows = { {68, 138}, {218, 72}, {302, 56}, {370, 56}, {438, 72}, {522, 72} }
for i, row in ipairs(appearance_rows) do M.controls[i].y, M.controls[i].h = row[1], row[2] end
local function control(id, tab, name, keywords, y, h)
    M.controls[#M.controls + 1] = {
        id = id, reveal = #M.controls + 1, tab = tab, name = name,
        section = tab == 0 and "Appearance" or (tab == 3 and "Notifications" or "Menu Bar & Dock"),
        icon = tab == 3 and "󰒎" or "󰍜", keywords = keywords, y = y, h = h,
    }
end
control("notifications.quiet", 3, "Quiet modes & app delivery", "focus presentation game quiet hours schedule per-app delivery", 0, 56)
control("notifications.dnd", 3, "Do Not Disturb", "manual dnd quiet silent notifications", 68, 56)
control("notifications.group", 3, "Group by app", "notification grouping stack", 136, 56)
control("notifications.banners", 3, "Show banners", "notification popup clock pill", 204, 56)
control("notifications.duration", 3, "Banner duration", "banner stays timeout seconds notification", 272, 64)
control("frame.style", 4, "Top bar style", "notch strip menubar", 0, 54)
control("frame.clock", 4, "24-hour clock", "time format 12 hour am pm", 66, 56)
control("frame.seconds", 4, "Show seconds", "clock time", 134, 56)
control("frame.weather", 4, "Show weather", "bar temperature forecast", 202, 56)
control("frame.tray", 4, "Show system tray", "bar application icons", 270, 56)
control("frame.workspaces", 4, "Show workspaces", "bar workspace indicators", 338, 56)
control("frame.app", 4, "Show app indicator", "bar focused application", 406, 56)
control("frame.updates", 4, "Show update status", "bar software packages", 474, 56)
control("dock.autohide", 4, "Hide the dock automatically", "dock auto hide reveal", 980, 56)
control("dock.size", 4, "Dock icons", "dock icon size small medium large", 1048, 42)
control("dock.delay", 4, "Dock hide delay", "dock timing short normal long", 1102, 42)
control("dock.order", 4, "Dock order", "dock pin ordering arrange reorder", 1156, 56)
control("widgets.visible", 4, "Desktop widgets", "show hide widget visibility", 1224, 56)
control("widgets.arrange", 4, "Arrange widgets", "widget edit reset layout desktop", 1292, 64)
control("frame.left-order", 4, "Left indicators", "workspace app module order", 542, 42)
control("frame.right-order", 4, "Right indicators", "tray update module order", 596, 42)
control("frame.outputs", 4, "Optional modules on", "bar output monitor all focused named", 650, 42)
control("dock.outputs", 4, "Dock on", "dock output monitor all focused named", 704, 42)
control("dock.reveal", 4, "Dock reveal delay", "dock show timing immediate", 758, 42)
control("frame.output-name", 4, "Named output", "monitor connector HDMI output name", 812, 88)
control("appearance.custom-accent", 0, "Custom accent", "hex rgb colour color contrast", 578, 112)
control("appearance.text", 0, "Panel text size", "font typography small standard large", 702, 72)
control("appearance.glass-strength", 0, "Glass strength", "opacity transparency legibility minimal soft full", 786, 72)
control("appearance.motion", 0, "Reduce motion", "animation accessibility transitions system", 870, 56)
-- Validation metadata comes from the preference schema, so search and reset describe
-- the same defaults and bounds without maintaining a second preference definition.
local P = require("preferences")
local fields = {
    ["appearance.app-themes"] = { "prefs", "apps" },
    ["notifications.group"] = { "prefs", "group" }, ["notifications.banners"] = { "prefs", "banners" },
    ["notifications.duration"] = { "prefs", "banner_i" },
    ["frame.style"] = { "prefs", "bar_style" }, ["frame.clock"] = { "theme", "hour12" },
    ["frame.seconds"] = { "prefs", "seconds" }, ["frame.weather"] = { "prefs", "weather" },
    ["frame.tray"] = { "prefs", "tray" }, ["frame.workspaces"] = { "prefs", "workspaces" },
    ["frame.app"] = { "prefs", "bar_apps" }, ["frame.updates"] = { "prefs", "updates" },
    ["dock.autohide"] = { "prefs", "dock_auto" }, ["dock.size"] = { "prefs", "dock_size" },
    ["dock.delay"] = { "prefs", "dock_delay" }, ["widgets.visible"] = { "prefs", "widgets" },
    ["frame.left-order"] = { "prefs", "bar_left_order" }, ["frame.right-order"] = { "prefs", "bar_right_order" },
    ["frame.outputs"] = { "prefs", "module_output_policy" }, ["dock.outputs"] = { "prefs", "dock_output_policy" },
    ["dock.reveal"] = { "prefs", "dock_show_delay" }, ["frame.output-name"] = { "prefs", "frame_output_name" },
}
for _, control in ipairs(M.controls) do
    local field
    for _, entry in ipairs(P.APPEARANCE) do
        if control.id == entry.id then field = entry.field end
    end
    local source = fields[control.id]
    if source then
        for _, entry in ipairs(P.spec(source[1]).fields) do if entry.key == source[2] then field = entry end end
    end
    if field then
        control.fact, control.type, control.default = field.fact, field.type, field.default
        control.allowed, control.min, control.max = field.labels or field.choices, field.min, field.max
    end
end
local by_id, by_reveal = {}, {}
for _, control in ipairs(M.controls) do by_id[control.id], by_reveal[control.reveal] = control, control end
function M.find(id) return type(id) == "string" and by_id[id] or nil end
function M.target(n) return type(n) == "number" and by_reveal[n] or nil end
function M.results(pages)
    local rows = {}
    for _, page in ipairs(pages) do rows[#rows + 1] = page end
    for _, control in ipairs(M.controls) do rows[#rows + 1] = control end
    return rows
end
return M
