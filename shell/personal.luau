-- Personal is the only writer of personal/content.json (files service: atomic, mode 0600).
-- Widgets request resync with their last revision; after a successful save Personal emits
-- personal_changed(revision). Widgets read that atomic snapshot, never write it.
local Store = require("personal_store")
local ok, saved = pcall(sys.ask, "files.read", "content.json", "json")
local store, problem
if ok then store, problem = Store.new(saved) else problem = "Personal content could not be read. The saved file has been kept." end
if not store then text.status = problem; return end
local timer, dirty = nil, false
local function notify()
    pcall(sys.call, "say", "widgets", "emit personal_changed " .. store.data.revision)
end
local function publish()
    local d, active, completed = store.data, 0, 0
    for _, t in ipairs(d.tasks) do if t.done then completed = completed + 1 else active = active + 1 end end
    fact.ready, fact.can_undo = true, #store.history > 0
    fact.note_count, fact.task_count, fact.completed_count = #d.notes, active, completed
    local note = Store.featured(d)
    text.note_preview = note and Store.title(note.text) or "Keep a note here"
    local lines = {}
    for _, t in ipairs(d.tasks) do if not t.done and #lines < 2 then lines[#lines + 1] = "• " .. t.text end end
    text.task_preview = #lines > 0 and table.concat(lines, "\n") or "All caught up"
    text.snapshot = json.encode(store:snapshot())
end
local function flush()
    if timer then cancel(timer); timer = nil end
    if not dirty then return end
    local success = pcall(sys.call, "files.write", "content.json", store:snapshot())
    if success then dirty = false; text.status = "Saved on this device"; notify()
    else text.status = "Could not save. Your changes are still open; retrying…"; timer = after(2000, flush) end
end
for _, op in ipairs({ "add_note", "edit_note", "remove_note", "add_task", "toggle_task", "remove_task", "move_task", "undo" }) do
    on(op, function(p)
        local changed, err = store:apply(op, p, os.date("%Y-%m-%d %H:%M:%S"))
        if err then text.status = err; return end
        if changed then
            dirty = true; publish(); text.status = "Saving…"
            if timer then cancel(timer) end
            timer = after(300, flush)
        end
    end)
end
on("flush", flush)
on("resync", function(rev)
    if dirty then flush() elseif tonumber(rev) ~= store.data.revision then notify() end
end)
publish()
text.status = "Saved on this device"
-- Ensure a fresh store has a snapshot for readers, without changing revision.
if not saved then dirty = true; flush() else notify() end
