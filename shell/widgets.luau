-- macOS Notification Center & Widgets Companion Logic

local stats_cmd = [[sh -c "awk '{print int($1*15)}' /proc/loadavg; free | grep Mem | awk '{print int($3/$2*100)}'; df / | tail -1 | tr -d '%' | awk '{print $5}'; date +'%B:%d:%A'"]]

local function update_stats()
    pcall(run, "sh", {"-c", stats_cmd}, function(output, code)
        if code == 0 and output and #output > 0 then
            local lines = {}
            for line in output:gmatch("[^\r\n]+") do
                lines[#lines + 1] = line
            end
            if #lines >= 3 then
                local cpu = tonumber(lines[1]) or 15
                local mem = tonumber(lines[2]) or 42
                local disk = tonumber(lines[3]) or 55
                fact.cpu_pct = math.min(100, math.max(0, cpu))
                fact.mem_pct = math.min(100, math.max(0, mem))
                fact.disk_pct = math.min(100, math.max(0, disk))
            end
            if #lines >= 4 then
                local parts = {}
                for p in lines[4]:gmatch("[^:]+") do
                    parts[#parts + 1] = p
                end
                if #parts >= 3 then
                    text.cal_month = parts[1]:upper()
                    text.cal_day = parts[2]
                    text.cal_dow = parts[3]
                end
            end
        end
    end)
end

-- Update stats immediately and periodically every 5s while daemon runs
update_stats()
every(5000, function()
    if fact.open then
        update_stats()
    end
end)

on("fact:open", function(open)
    if open then
        update_stats()
    end
end)

on("refresh_stats", function()
    update_stats()
end)

on("clear_notices", function()
    model.notices = {}
end)
