-- Music panel logic: the `media` service (MPRIS) → the card. The frame draws the glass (panel.luau reports the height).
local panel = require("panel")("music")
panel.height(196)

local playing, pos, len, rate = false, 0, 0, 1

local function clock(sec)
    sec = math.max(0, math.floor(sec or 0))
    return string.format("%d:%02d", sec // 60, sec % 60)
end

local function paint_time()
    text.time_pos = clock(pos)
    text.time_len = clock(len)
    fact.track_pos = pos
end

sys.watch("media", function(m)
    m = m or {}
    local title = m.title or ""
    playing = m.playing == true
    pos, len, rate = m.position or 0, m.length or 0, m.rate or 1
    fact.has_player = (m.player or "") ~= "" or title ~= ""
    fact.is_playing = playing
    fact.track_len = len
    fact.has_art = (m.art or "") ~= ""
    text.track_title = title ~= "" and title or "Unknown title"
    text.track_artist = m.artist or ""
    text.cover_art = m.art or ""
    paint_time()
end)

-- The player reports the position once; carry it on between reports.
every(1000, function()
    if playing and len > 0 then
        pos = math.min(pos + rate, len)
        paint_time()
    end
end)

on("play_pause", function() pcall(sys.call, "media.toggle") end)
on("previous", function() pcall(sys.call, "media.previous") end)
on("next", function() pcall(sys.call, "media.next") end)
on("seek", function(frac)
    if len > 0 then
        pcall(sys.call, "media.seek", math.floor((tonumber(frac) or 0) * len))
    end
end)

-- one panel at a time
require("exclusive")("music")
