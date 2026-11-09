-- Updates panel logic: `checkupdates` (official repos) → the list, and "Update all" = pkexec pacman -Syu in the
-- background (the polkit popup asks for the password). Tells the top bar the count (the arrow only shows when > 0).
local panel = require("panel")("updates")

local function sh(script, cb, ...)
    run("sh", { "-c", script, "x", ... }, cb, cb == nil and { output = false } or nil)
end

local function resize()
    local n = tonumber(fact.n) or 0
    local rows = fact.show_log and 8 or math.min(math.max(n, 1), 8)
    panel.height(70 + rows * 34 + 24 + ((n < 1 and not fact.show_log) and 70 or 0) + 36 + 20)
end

local function tell_bar(n)
    pcall(sys.call, "say", "topbar", "fact upd_n " .. n)
end

local fresh = false          -- checked within the last 5 minutes
local helper = nil            -- the AUR helper found on this machine: paru, else yay (nil: no AUR part)
sh("command -v paru >/dev/null && echo paru || { command -v yay >/dev/null && echo yay; }", function(out)
    local h = (out or ""):match("%a+")
    if h == "paru" or h == "yay" then helper = h end
end)

local function parse(out, aur, rows)
    local n = 0
    for line in (out or ""):gmatch("[^\n]+") do
        local name, old, new = line:match("^(%S+)%s+(%S+)%s+%->%s+(%S+)")
        if name then
            n = n + 1
            if #rows < 60 then rows[#rows + 1] = { name = name, ver = old .. " → " .. new, aur = aur } end
        end
    end
    return n
end

local function check()
    if fact.checking then return end
    fact.checking = true
    fact.failed = false
    if not fact.running then fact.show_log = false end
    sh("timeout 60 checkupdates 2>/dev/null", function(out, code)
        local rows = {}
        local n = parse(out, false, rows)
        local official_ok = code == 0 or code == 2
        local function finish(aur_n)
            fact.checking = false
            if official_ok then
                model.pkgs = rows
                fact.n = n + aur_n
                fact.known = true
                tell_bar(n + aur_n)
                fresh = true
                after(300000, function() fresh = false end)
                if not fact.running then
                    local t = n + aur_n
                    text.status = t == 0 and "Up to date" or (t .. (t == 1 and " update available" or " updates available")
                        .. (aur_n > 0 and (" · " .. aur_n .. " from the AUR") or ""))
                end
            elseif not fact.running then
                text.status = "Could not reach the package servers"
            end
            resize()
        end
        if helper and official_ok then
            sh("timeout 60 " .. helper .. " -Qua 2>/dev/null", function(aout)
                finish(parse(aout, true, rows))
            end)
        else
            finish(0)
        end
    end)
end

-- Update all: pacman -Syu (official), then the AUR helper (-Sua). Both run as root through pkexec (our popup asks):
-- the helper builds as you and calls `--sudo pkexec` for its installs, so no terminal and no sudo are involved.
local LOG = {}
local function log_line(l)
    LOG[#LOG + 1] = { t = l:sub(1, 70) }
    while #LOG > 14 do table.remove(LOG, 1) end
    model.logl = LOG
end

local function run_step(cmd, args, label, on_done)
    local last_error = nil
    text.status = "Waiting for your password…"
    spawn(cmd, args, function(line)
        line = (line or ""):gsub("%c%[[%d;]*%a", ""):gsub("^.*\r", ""):gsub("^%s+", ""):gsub("%s+$", "")
        if line:match("^error") then last_error = line end
        if line ~= "" then
            log_line(line)
            text.status = (label .. line):sub(1, 60)
        end
    end, function(_, code)
        on_done(code, last_error)
    end, { env = { LC_ALL = "C" }, errors = true })
end

local function finish_update(code, err)
    fact.running = false
    if code == 0 then
        text.status = "System updated"
        fact.show_log = false
        check()
    else
        fact.failed = true
        text.status = (code == 126 or code == 127) and "The password was not given" or (err and err:sub(1, 70)) or ("The update stopped (code " .. tostring(code) .. ")")
    end
end

local function update()
    if fact.running then return end
    fact.running = true
    fact.failed = false
    LOG = {}
    model.logl = LOG
    fact.show_log = true
    resize()
    run_step("pkexec", { "pacman", "-Syu", "--noconfirm" }, "", function(code, err)
        if code == 0 and helper then
            local args = { "-Sua", "--noconfirm", "--batchinstall", "--sudo", "pkexec" }
            if helper == "paru" then args[#args + 1] = "--skipreview" end
            run_step(helper, args, "AUR: ", finish_update)
        else
            finish_update(code, err)
        end
    end)
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
