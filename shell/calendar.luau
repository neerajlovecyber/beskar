-- Pure Monday-first month metadata. Views share MonthGrid instead of duplicating day state.
local M = {}
function M.month(shift, today)
    today = today or os.date("*t")
    local month = today.month + (shift or 0)
    local year = today.year + math.floor((month - 1) / 12)
    month = (month - 1) % 12 + 1
    local first = os.time({year=year, month=month, day=1, hour=12})
    local lead = (tonumber(os.date("%w", first)) + 6) % 7
    local days = tonumber(os.date("%d", os.time({year=year, month=month+1, day=0, hour=12})))
    local cells = {}
    for i = 1, 42 do
        local day = os.date("*t", os.time({year=year, month=month, day=i-lead, hour=12}))
        cells[i] = {d=tostring(day.day), kind=day.month ~= month and 1 or ((day.year==today.year and day.month==today.month and day.day==today.day) and 2 or 0)}
    end
    return {
        cells=cells,
        title=os.date("%B %Y", first), year=year, month=month, lead=lead, days=days,
        previous=tonumber(os.date("%d", os.time({year=year, month=month, day=0, hour=12}))),
        today=(year==today.year and month==today.month) and today.day or 0,
        rows=math.ceil((lead + days) / 7),
    }
end
return M
