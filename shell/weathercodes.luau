-- WMO weather codes (Open-Meteo) → a glyph and words. Shared by the weather panel, the top bar, the dashboard and widgets.
local M = {}

function M.icon(code, is_day)
    code = code or 0
    local day = is_day ~= false and is_day ~= 0
    if code == 0 then
        return day and "󰖙" or "󰖔"
    elseif code <= 2 then
        return day and "󰖕" or "󰼱"
    elseif code == 3 then
        return "󰖐"
    elseif code == 45 or code == 48 then
        return "󰖑"
    elseif (code >= 51 and code <= 67) or (code >= 80 and code <= 82) then
        return "󰖗"
    elseif (code >= 71 and code <= 77) or code == 85 or code == 86 then
        return "󰖘"
    elseif code >= 95 then
        return "󰙾"
    end
    return "󰖐"
end

function M.words(code)
    code = code or 0
    if code == 0 then return "Clear sky"
    elseif code == 1 then return "Mostly clear"
    elseif code == 2 then return "Partly cloudy"
    elseif code == 3 then return "Overcast"
    elseif code == 45 or code == 48 then return "Fog"
    elseif code >= 51 and code <= 57 then return "Drizzle"
    elseif (code >= 61 and code <= 67) or (code >= 80 and code <= 82) then return "Rain"
    elseif (code >= 71 and code <= 77) or code == 85 or code == 86 then return "Snow"
    elseif code >= 95 then return "Thunderstorm" end
    return "Cloudy"
end

return M
