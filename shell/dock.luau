-- iNiR Floating Dock Companion Logic
local apps = {
    [1] = "kitty",
    [2] = "nautilus",
    [3] = "code",
    [4] = "steam",
    [5] = "obsidian",
    [6] = "firefox",
    [7] = "discord",
    [8] = "telegram-desktop"
}

on("launch", function(index)
    local cmd = apps[index]
    if cmd then
        pcall(run, cmd)
    end
end)
