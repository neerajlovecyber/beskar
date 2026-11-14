-- Pure personal-content store. Only Personal persists it; placement never owns content.
local M = { MAX_NOTES = 16, MAX_TASKS = 48, NOTE_BYTES = 4096, TASK_BYTES = 240 }
local function copy(v)
    if type(v) ~= "table" then return v end
    local t = {}; for k, x in pairs(v) do t[k] = copy(x) end; return t
end
local function integer(n) return type(n) == "number" and n >= 0 and n < 1e12 and n == math.floor(n) end
local function valid_text(s, limit) return type(s) == "string" and #s <= limit and not s:find("%z") end
local function find(rows, id)
    for i, r in ipairs(rows) do if r.id == id then return r, i end end
end
local function sequence(t)
    if type(t) ~= "table" then return false end
    local n = #t
    for k in pairs(t) do if not integer(k) or k < 1 or k > n then return false end end
    return true
end
function M.featured(d) return find(d.notes, d.featured_id) or d.notes[1] end
function M.title(s) return (s:match("[^\r\n]+") or "Untitled note"):gsub("[%c]", " ") end
function M.new(saved)
    local data = saved
    if data == nil then data = { version = 1, revision = 0, next_id = 1, notes = {}, tasks = {} } end
    if type(data) ~= "table" or data.version ~= 1 or not integer(data.revision) or not integer(data.next_id)
        or not sequence(data.notes) or not sequence(data.tasks)
        or #data.notes > M.MAX_NOTES or #data.tasks > M.MAX_TASKS then return nil, "Personal content could not be loaded. The saved file has been kept." end
    local ids, max_id = {}, 0
    for _, name in ipairs({ "notes", "tasks" }) do
        for _, r in ipairs(data[name]) do
            if type(r) ~= "table" or not integer(r.id) or r.id < 1 or ids[r.id]
                or not valid_text(r.text, name == "notes" and M.NOTE_BYTES or M.TASK_BYTES)
                or type(r.modified) ~= "string" or #r.modified > 40
                or (name == "tasks" and type(r.done) ~= "boolean") then return nil, "Personal content is invalid. The saved file has been kept." end
            ids[r.id], max_id = true, math.max(max_id, r.id)
        end
    end
    if data.next_id <= max_id then return nil, "Personal content has invalid IDs. The saved file has been kept." end
    if data.featured_id ~= nil and (not integer(data.featured_id) or (data.featured_id ~= 0 and not find(data.notes, data.featured_id))) then
        return nil, "Personal content has an invalid note reference. The saved file has been kept."
    end
    local self = { data = copy(data), history = {}, edit_id = nil }
    function self:snapshot() return copy(self.data) end
    function self:apply(op, p, stamp)
        p = type(p) == "table" and p or { id = tonumber(p) }
        local d = self.data
        local before, changed = self:snapshot(), false
        local r, i
        if op == "add_note" then
            if #d.notes >= M.MAX_NOTES then return false, "You can keep up to 16 notes." end
            r = { id = d.next_id, text = "", modified = stamp }; d.next_id = d.next_id + 1
            table.insert(d.notes, 1, r); d.featured_id = r.id; changed = true
        elseif op == "edit_note" then
            r = find(d.notes, p.id)
            if not r then return false, "This note no longer exists." end
            if not valid_text(p.text, M.NOTE_BYTES) then return false, "A note can contain up to 4096 bytes of text." end
            if r.text ~= p.text then r.text, r.modified, changed, d.featured_id = p.text, stamp, true, r.id end
        elseif op == "remove_note" then
            r, i = find(d.notes, p.id)
            if i then
                table.remove(d.notes, i)
                if d.featured_id == p.id then d.featured_id = d.notes[1] and d.notes[1].id or 0 end
                changed = true
            end
        elseif op == "add_task" then
            local s = type(p.text) == "string" and p.text:match("^%s*(.-)%s*$") or ""
            if not valid_text(s, M.TASK_BYTES) or s == "" or s:find("[\r\n]") then return false, "Enter a to-do on one line (up to 240 bytes)." end
            if #d.tasks >= M.MAX_TASKS then return false, "You can keep up to 48 to-dos." end
            d.tasks[#d.tasks + 1] = { id = d.next_id, text = s, done = false, modified = stamp }
            d.next_id = d.next_id + 1; changed = true
        elseif op == "toggle_task" then
            r = find(d.tasks, p.id); if r then r.done, r.modified, changed = not r.done, stamp, true end
        elseif op == "remove_task" then
            r, i = find(d.tasks, p.id); if i then table.remove(d.tasks, i); changed = true end
        elseif op == "move_task" then
            r, i = find(d.tasks, p.id)
            if i and (p.delta == -1 or p.delta == 1) then
                -- Move among peers in the active/completed view; don't jump a hidden row.
                local j = i + p.delta
                while d.tasks[j] and d.tasks[j].done ~= r.done do j = j + p.delta end
                if d.tasks[j] then d.tasks[i], d.tasks[j], changed = d.tasks[j], r, true end
            end
        elseif op == "undo" then
            local old = table.remove(self.history)
            if old then
                old.next_id, old.revision = d.next_id, d.revision + 1
                self.data, self.edit_id = old, nil
                return true
            end
            return false
        end
        if not changed then return false end
        if not (op == "edit_note" and self.edit_id == p.id) then
            self.history[#self.history + 1] = before
            if #self.history > 20 then table.remove(self.history, 1) end
        end
        self.edit_id = op == "edit_note" and p.id or nil
        d.revision = d.revision + 1
        return true
    end
    return self
end
return M
