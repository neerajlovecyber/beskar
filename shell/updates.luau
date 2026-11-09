-- Updates panel logic: `checkupdates` (official repos) → the list, and "Update all" = one terminal with the update (see below).
-- Tells the top bar the count (the arrow only shows when > 0).
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

-- Update all: ONE terminal with one `sudo` session for everything (like iNiR): the AUR helper's -Syu does the official
-- packages and the AUR ones (paru, else yay); without a helper, sudo pacman -Syu. The list is checked again when the
-- terminal closes. (A polkit popup cannot do this with one password: pkexec asks again for every command.)
local TERMINAL = [[
run_in() {
    case "$1" in
        wezterm) wezterm start -- sh -c "$2" ;;
        foot|kitty|alacritty|ghostty|konsole|xterm|gnome-terminal|xfce4-terminal) "$1" -e sh -c "$2" ;;
    esac
}
CMD="$1"
for t in "$TERMINAL" kitty foot alacritty ghostty wezterm konsole gnome-terminal xfce4-terminal xterm; do
    [ -n "$t" ] && command -v "$t" >/dev/null 2>&1 && { run_in "$t" "$CMD"; exit $?; }
done
exit 127
]]

local function update()
    if fact.running then return end
    local cmd = helper and (helper .. " -Syu") or "sudo pacman -Syu"
    cmd = cmd .. "; echo; read -r -p 'Done. Press Enter to close.' _"
    fact.running = true
    text.status = "Updating in the terminal…"
    spawn("sh", { "-c", TERMINAL, "x", cmd }, function() end, function(_, code)
        fact.running = false
        if code == 127 then
            fact.failed = true
            text.status = "No terminal found (kitty, foot, alacritty…)"
        else
            fact.checking = false
            fresh = false
            check()
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
