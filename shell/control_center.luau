-- macOS Control Center Logic
on("volume_set", function(val)
    sys.call("audio.volume", val)
end)

on("brightness_set", function(val)
    sys.call("brightness.level", val)
end)

on("play_pause", function()
    sys.call("media.toggle")
end)
