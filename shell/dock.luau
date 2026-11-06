-- macOS Dock Companion Logic
local apps = {
    [1] = "nautilus",
    [2] = "firefox",
    [3] = "kitty",
    [4] = "code",
    [5] = "flatpak run org.gnome.Music",
    [6] = "gnome-control-center",
    [7] = "nautilus trash://"
}

on("launch", function(index)
    if index == 6 then
        pcall(sys.call, "say", "settings", "emit toggle")
        return
    end
    local cmd = apps[index]
    if cmd then
        log("Dock: launching", cmd)
        spawn(cmd)
    end
end)
