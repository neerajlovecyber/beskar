-- Updates panel logic: `checkupdates` (official repos) → the list, and "Update all" = pkexec pacman -Syu in the
-- background (the polkit popup asks for the password). Tells the top bar the count (the arrow only shows when > 0).
local panel = require("panel")("updates")

local function sh(script, cb, ...)
    run("sh", { "-c", script, "x", ... }, cb, cb == nil and { output = false } or nil)
end

local function resize()
    local n = tonumber(fact.n) or 0
    panel.height(70 + math.min(math.max(n, 1), 8) * 34 + 24 + (n < 1 and 70 or 0) + 36 + 20)
end

local function tell_bar(n)
    pcall(sys.call, "say", "topbar", "fact upd_n " .. n)
end

local fresh = false          -- checked within the last 5 minutes
local function check()
    if fact.checking then return end
    fact.checking = true
    fact.failed = false
    sh("timeout 60 checkupdates 2>/dev/null", function(out, code)
        fact.checking = false
        local rows, n = {}, 0
        for line in (out or ""):gmatch("[^\n]+") do
            local name, old, new = line:match("^(%S+)%s+(%S+)%s+%->%s+(%S+)")
            if name then
                n = n + 1
                if #rows < 40 then rows[#rows + 1] = { name = name, ver = old .. " → " .. new } end
            end
        end
        if code == 0 or code == 2 then
            fact.known = true
            fresh = true
            after(300000, function() fresh = false end)
            model.pkgs = rows
            fact.n = n
            tell_bar(n)
            if not fact.running then
                text.status = n == 0 and "Up to date" or (n .. (n == 1 and " update available" or " updates available")
                    .. (n > 40 and " (first 40 shown)" or ""))
            end
        elseif not fact.running then
            text.status = "Could not reach the package servers"
        end
        resize()
    end)
end

local function update()
    if fact.running then return end
    fact.running = true
    fact.failed = false
    text.status = "Waiting for your password…"
    local last_error = nil
    spawn("pkexec", { "pacman", "-Syu", "--noconfirm" }, function(line)
        line = (line or ""):gsub("%c%[[%d;]*%a", ""):gsub("^%s+", ""):gsub("%s+$", "")
        if line:match("^error") then last_error = line end
        if line ~= "" then text.status = line:sub(1, 60) end
    end, function(_, code)
        fact.running = false
        if code == 0 then
            text.status = "System updated"
            check()
        else
            fact.failed = true
            text.status = (code == 126 or code == 127) and "The password was not given" or (last_error and last_error:sub(1, 70)) or ("pacman stopped (code " .. tostring(code) .. ")")
        end
    end, { env = { LC_ALL = "C" }, errors = true })
end

on("do_check", check)
on("do_update", update)
-- the list is kept between checks: opening the panel shows it at once and only looks again when it is old
on("fact:open", function(v)
    if (v == true or v == 1) and not fact.running and not fresh then check() end
end)

resize()
after(3000, check)
every(30 * 60 * 1000, check)

require("exclusive")("updates")
