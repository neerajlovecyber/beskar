-- Static panel metadata, copied into each scene's Lua state. Mutable open/selection state stays in Panels.
local panels = {
    control_center = { id = 1, island = "rp", w = 372, scene = "topbar" },
    notifications = { id = 2, island = "rp", w = 386, scene = "notifications" },
    dashboard = { id = 3, island = "cp", w = 360, scene = "topbar" },
    spotlight = { id = 4, island = "bp", w = 640, scene = "topbar", slot = 1 },
    wallpapers = { id = 5, island = "bp", w = 980, scene = "topbar", slot = 3 },
    clipboard = { id = 6, island = "bp", w = 560, scene = "topbar", slot = 2 },
    banner = { id = 7, island = "cp", w = 380, scene = "notifications", kind = 1 },
    music = { id = 9, island = "cp", w = 380, scene = "topbar" },
    widget_bar = { id = 10, island = "bp", w = 800, scene = "topbar", slot = 7 },
    session = { id = 11, island = "bp", w = 520, scene = "topbar", slot = 5 },
    polkit = { id = 12, island = "bp", w = 520, scene = "topbar", slot = 8 },
    weather = { id = 15, island = "cp", w = 420, scene = "topbar" },
    updates = { id = 16, island = "rp", w = 372, scene = "topbar" },
    appswitcher = { id = 21, island = "bp", w = 520, scene = "topbar", slot = 6 },
    overview = { id = 22, island = "bp", w = 1000, scene = "topbar", slot = 10 },
    timer = { id = 26, island = "cp", w = 420, scene = "topbar" },
    personal = { id = 25, island = "cp", w = 600, scene = "topbar" },
    welcome = { id = 24, island = "bp", w = 640, scene = "topbar", slot = 9 },
    -- the Settings window: no island (the frame draws its own glass, `st_*` facts), opened from the monitor with the focus like the dock panels
    settings = { id = 30, island = "st", w = 840, scene = "topbar", slot = 4, window = true },
}

local by_id, known, dock, merged = {}, {}, {}, {}
local focus = { [11] = "capture" }
local slots = { capture = 11 }
for name, panel in pairs(panels) do
    panel.name = name
    by_id[panel.id] = panel
    if not panel.kind then
        known[panel.id] = true
        if panel.island == "bp" or panel.window then dock[name] = panel.id else merged[name] = true end
    end
    if panel.slot then
        focus[panel.slot] = name
        slots[name] = panel.slot
    end
end

return { panels = panels, by_id = by_id, known = known, dock = dock, merged = merged, focus = focus, slots = slots }
