-- Where you are, for the weather and the clocks. Nothing is hard-coded to a place:
--   1. ~/.config/beskar/location, one line "LAT LON City name", wins (write it yourself to pin a place)
--   2. otherwise the place is looked up once from your IP (ipwho.is) and saved there
-- `require("location")(function(place) … end)` calls back with { lat, lon, city } (nil if both fail).
-- The scene needs `run: "sh", "curl"`.
local cached = nil
local waiting = nil

return function(done)
    if cached then
        done(cached)
        return
    end
    if waiting then
        waiting[#waiting + 1] = done
        return
    end
    waiting = { done }
    local function finish(place)
        cached = place
        local list = waiting
        waiting = nil
        for _, cb in ipairs(list) do
            cb(place)
        end
    end
    run("sh", { "-c", 'cat "$HOME/.config/beskar/location" 2>/dev/null | head -1' }, function(out)
        local lat, lon, city = (out or ""):match("^%s*(-?[%d%.]+)%s+(-?[%d%.]+)%s*(.-)%s*$")
        if lat then
            finish({ lat = tonumber(lat), lon = tonumber(lon), city = city ~= "" and city or "Here" })
            return
        end
        run("curl", { "-fsS", "--max-time", "6", "https://ipwho.is/?fields=success,latitude,longitude,city" }, function(body, code)
            local ok, d = pcall(json.decode, body or "")
            if code == 0 and ok and type(d) == "table" and d.success ~= false and d.latitude and d.longitude then
                local place = { lat = d.latitude, lon = d.longitude, city = d.city or "Here" }
                run("sh", { "-c", 'mkdir -p "$HOME/.config/beskar" && printf "%s %s %s\\n" "$1" "$2" "$3" > "$HOME/.config/beskar/location"',
                    "x", tostring(place.lat), tostring(place.lon), place.city }, nil, { output = false })
                finish(place)
            else
                finish(nil)
            end
        end)
    end)
end
