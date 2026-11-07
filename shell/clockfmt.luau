-- The time as the shell shows it: "2:05 PM" (12 hour, the default) or "14:05" (24 hour), with seconds if asked.
-- `hour12` is a theme fact (shell/common/theme.plm); Settings changes and broadcasts it.
return function(hour12, seconds)
    local sec = (seconds == true or seconds == 1)
    if hour12 == false or hour12 == 0 then
        return os.date(sec and "%H:%M:%S" or "%H:%M")
    end
    local s = os.date(sec and "%I:%M:%S %p" or "%I:%M %p")
    return (s:gsub("^0", ""))
end
