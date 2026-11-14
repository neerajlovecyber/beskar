-- Shared descriptions and routes. Callers dispatch through their own declared permissions/events.
local slots = require("panels_data").slots
local settings = {
    { tab = 0, name = "Appearance", icon = "󰏘", tint = 0, keywords = "theme colors colours accent palette glass dark light" },
    { tab = 1, name = "Displays", icon = "󰍹", tint = 1, keywords = "monitor screen resolution scale refresh brightness" },
    { tab = 2, name = "Sound", icon = "󰕾", tint = 2, keywords = "audio volume speakers output microphone" },
    { tab = 3, name = "Notifications", icon = "󰒎", tint = 3, keywords = "banners do not disturb dnd grouping quiet hours focus presentation game app delivery" },
    { tab = 4, name = "Menu Bar & Dock", icon = "󰍜", tint = 4, keywords = "topbar strip notch tray widgets auto hide" },
    { tab = 5, name = "Shortcuts", icon = "󰌌", tint = 5, keywords = "keyboard keys keybind bindings" },
    { tab = 6, name = "General", icon = "󰋚", tint = 6, keywords = "about computer system clock time idle lock" },
    { tab = 8, name = "Night Light & Power", icon = "󰌵", tint = 8, keywords = "warmth temperature sunset battery performance saver profile" },
}
local commands = {
    { id = "timer", name = "Timer", keywords = "timer countdown", cli = "timer", event = "Topbar.open_timer" },
    { id = "timer-pause", name = "Pause Timer", keywords = "timer pause", event = "Activities.pause" },
    { id = "timer-resume", name = "Resume Timer", keywords = "timer resume", event = "Activities.resume" },
    { id = "timer-cancel", name = "Cancel Timer", keywords = "timer cancel", event = "Activities.cancel" },
    { id = "timer-5", name = "Timer 5 min", keywords = "timer 5", event = "Activities.start", value = 300 },
    { id = "timer-10", name = "Timer 10 min", keywords = "timer 10", event = "Activities.start", value = 600 },
    { id = "timer-25", name = "Timer 25 min", keywords = "timer 25", event = "Activities.start", value = 1500 },
    { id = "session", name = "Session Menu", keywords = "power menu session", cli = "power-menu", event = "Topbar.open_session" },
    { id = "lock", name = "Lock Screen", keywords = "lock", cli = "lock", route = "lock" },
    { id = "sleep", name = "Sleep", keywords = "suspend", route = "sleep" },
    { id = "logout", name = "Log Out…", keywords = "logout", route = "session", value = 2 },
    { id = "restart", name = "Restart…", keywords = "reboot", route = "session", value = 1 },
    { id = "shutdown", name = "Shut Down…", keywords = "poweroff", route = "session", value = 0 },
    { id = "screenshot", name = "Take Screenshot", keywords = "screenshot", route = "capture", mode = 2, kind = 0 },
    { id = "capture-area", name = "Select Area Screenshot", keywords = "area", route = "capture", mode = 0, kind = 0 },
    { id = "record", name = "Record Screen", keywords = "record", route = "capture", mode = 0, kind = 1 },
    { id = "clipboard", name = "Clipboard History", keywords = "clipboard", cli = "clipboard", event = "Topbar.open_panel", value = slots.clipboard },
    { id = "wallpapers", name = "Wallpapers", keywords = "wallpapers", cli = "wallpapers", event = "Topbar.open_panel", value = slots.wallpapers },
    { id = "widgets", name = "Edit Widgets", keywords = "widgets", cli = "widgets", route = "widgets" },
    { id = "settings", name = "Settings", keywords = "settings", cli = "settings", event = "Topbar.open_panel", value = slots.settings },
    { id = "notifications", name = "Notifications", keywords = "notifications", cli = "notifications", event = "Topbar.open_notifications" },
    { id = "control-center", name = "Control Center", keywords = "control wifi bluetooth", cli = "control-center", event = "Topbar.open_control_center" },
    { id = "music", name = "Music", keywords = "music player", event = "Topbar.open_music" },
    { id = "personal", name = "Notes & To-dos", keywords = "notes todo checklist personal", event = "Topbar.open_personal" },
    { id = "overview", name = "Window Overview", keywords = "overview", cli = "overview", event = "Topbar.open_panel", value = slots.overview },
}
local cli_labels = {
    spotlight = "Spotlight", shortcuts = "Keyboard shortcuts", appswitcher = "App switcher",
    dashboard = "Dashboard", capture = "Screen capture",
    session = "Session menu", ["session-menu"] = "Session menu",
    ["vol-up"] = "Volume up", ["vol-down"] = "Volume down", mute = "Mute",
    ["bright-up"] = "Brightness up", ["bright-down"] = "Brightness down",
}
for _, action in ipairs(commands) do
    if action.cli then cli_labels[action.cli] = action.name end
end

return { commands = commands, settings = settings, settings_results = require("settings_catalog").results(settings), cli_labels = cli_labels }
