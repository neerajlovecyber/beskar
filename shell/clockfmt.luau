-- The time as the shell shows it: "2:05 PM" (12 hour, the default) or "14:05" (24 hour).
-- `hour12` is a theme fact (shell/common/theme.plm) that Settings changes and broadcasts.
return function(hour12)
    if hour12 == false or hour12 == 0 then
        return os.date("%H:%M")
    end
    local s = os.date("%I:%M %p")
    return (s:gsub("^0", ""))
end
