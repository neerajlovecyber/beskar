-- Read-only bridge for the separate widgets process. Personal alone writes this file.
-- Numeric resync/revision events fit pleamar's socket protocol; content never passes through commands.
return function()
    local Store = require("personal_store")
    local revision, reading, pending = -1, false, false
    local home = sys.ask("env", "HOME") or ""
    local base = sys.ask("env", "XDG_DATA_HOME")
    if not base or base == "" then base = home .. "/.local/share" end
    local path = base .. "/pleamar/personal/content.json"
    local function read()
        if reading then pending = true; return end
        reading = true
        run("cat", { path }, function(out, code)
            reading = false
            if code == 0 then
                local ok, decoded = pcall(json.decode, out or "")
                local checked = ok and Store.new(decoded) or nil
                if checked and decoded.revision >= revision then
                    revision = decoded.revision
                    local note = Store.featured(decoded)
                    text.personal_note = note and note.text or "Click to write your first note."
                    local rows, count = {}, 0
                    for _, task in ipairs(decoded.tasks) do
                        if not task.done then
                            count = count + 1
                            if #rows < 4 then rows[#rows + 1] = { id = task.id, title = task.text } end
                        end
                    end
                    model.personal_tasks = rows
                    text.personal_count = count == 0 and "All caught up" or (count .. " remaining")
                end
            end
            if pending then pending = false; read() end
        end)
    end
    on("personal_changed", function(n) if tonumber(n) ~= revision then read() end end)
    local function resync() pcall(sys.call, "say", "personal", "emit resync " .. revision) end
    on("personal_toggle", function(id)
        if tonumber(id) then pcall(sys.call, "say", "personal", "emit toggle_task " .. math.floor(id)) end
    end)
    after(500, resync)
    every(15000, resync) -- recovers when either process starts after the other
end
