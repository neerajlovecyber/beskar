-- macOS Top Bar Companion Logic
on("open_apple_menu", function()
    pcall(sys.call, "say", "apple_menu", "emit toggle")
end)

on("open_control_center", function()
    pcall(sys.call, "say", "control_center", "emit toggle")
end)

on("open_spotlight", function()
    pcall(sys.call, "say", "spotlight", "emit toggle")
end)

on("open_widgets", function()
    pcall(sys.call, "say", "widgets", "emit toggle")
end)

on("tray_activate", function(i)
    local it = model.icons and model.icons[i + 1]
    if it and it.key then
        pcall(sys.call, "tray.activate", it.key)
    end
end)
