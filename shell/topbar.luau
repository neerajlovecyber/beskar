-- macOS Top Bar Companion Logic
on("open_control_center", function()
    spawn("pleamar", { "--say", "MacControlCenter", "emit toggle" })
end)
