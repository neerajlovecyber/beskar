-- Clipboard history logic (cliphist + wl-copy). Everything goes through `run` (the sandbox has no io / os), and the
-- frame draws the glass: this tells it how tall the list is.
--
--   history  `cliphist list`: up to 100 entries, stored by cliphist across restarts (start.sh keeps the watcher
--            `wl-paste --watch cliphist -max-items 100 store` running)
--   pins     text you pinned: stored by us (files.write) and never removed: not by Clear All, not by the 100 limit
--   shown    pinned entries first, then the recent ones, filtered by the search; 8 rows at a time (wheel / arrows)

local panel = require("panel")("clipboard")

local MAX_SHOWN = 8
local MAX_HISTORY = 100

local history = {}      -- { raw = the line cliphist printed, preview = text }
local pins = {}         -- { text = full text }
local view = {}         -- what the list can show now: { kind = "pin"|"hist", idx = n, preview = text }
local off = 0           -- first row on screen (0-based)
local CACHE = nil       -- ~/.cache/beskar/clipboard, where image thumbnails live
local thumb_state = {}  -- cliphist id -> "making" | "ready"

-- ── pins, on disk ────────────────────────────────────────────────
do
    local ok, loaded = pcall(sys.ask, "files.read", "pins.json", "json")
    if ok and type(loaded) == "table" and type(loaded.items) == "table" then
        pins = loaded.items
    end
end

local saving = false
local function save_pins()
    if saving then
        return
    end
    saving = true
    after(500, function()
        saving = false
        pcall(sys.call, "files.write", "pins.json", { items = pins })
    end)
end

-- ── what is shown ────────────────────────────────────────────────
local function flat(s)
    return ((s or ""):gsub("[\r\n\t]+", " "):gsub("%s+", " "))
end

-- cliphist lists an image as "[[ binary data 40 KiB png 468x111 ]]": turn that into a readable label, and keep
-- the id so a thumbnail can be made.
local function image_label(preview)
    local size, fmt, w, h = preview:match("^%[%[ binary data (%S+ %S+) (%a+) (%d+)x(%d+) %]%]")
    if size then
        return string.format("Image · %s × %s · %s", w, h, size), fmt
    end
end

local function thumb_path(id)
    return CACHE and (CACHE .. "/" .. id .. ".png") or ""
end

local repaint

local function make_thumb(id)
    if not CACHE or thumb_state[id] then
        return
    end
    thumb_state[id] = "making"
    local script = 'mkdir -p "$1" && { [ -f "$2" ] || cliphist decode "$3" | magick - -thumbnail 112x68 "$2"; }'
    run("sh", { "-c", script, "x", CACHE, thumb_path(id), tostring(id) }, function(_, code)
        if code == 0 then
            thumb_state[id] = "ready"
            repaint()
        else
            thumb_state[id] = nil
        end
    end)
end

local function rebuild(keep_off)
    local q = (text.clip_q or ""):lower()
    view = {}
    local pinned_text = {}
    for i, p in ipairs(pins) do
        pinned_text[p.text] = true
        local pv = flat(p.text)
        if q == "" or pv:lower():find(q, 1, true) then
            view[#view + 1] = { kind = "pin", idx = i, preview = pv }
        end
    end
    for i, h in ipairs(history) do
        if not pinned_text[h.preview] and (q == "" or h.preview:lower():find(q, 1, true)) then
            view[#view + 1] = { kind = "hist", idx = i, preview = flat(h.preview), image = h.image, id = h.id }
        end
    end
    if not keep_off then
        off = 0
    end
    off = math.max(0, math.min(off, math.max(0, #view - MAX_SHOWN)))
    local rows = {}
    for k = off + 1, math.min(#view, off + MAX_SHOWN) do
        local v = view[k]
        local is_img = v.image == true
        if is_img then
            make_thumb(v.id)
        end
        rows[#rows + 1] = {
            src = k - 1,
            preview = v.preview,
            pinned = v.kind == "pin",
            pinnable = v.kind == "pin" or not is_img,
            is_img = is_img,
            ready = is_img and thumb_state[v.id] == "ready",
            thumb = is_img and thumb_path(v.id) or "",
        }
    end
    model.clips = rows
    local n = #view
    text.clip_count = (q ~= "" and (n .. " found")) or (#history .. " saved" .. (#pins > 0 and (" · " .. #pins .. " pinned") or ""))
    text.clip_empty = (q ~= "") and "Nothing matches" or "Nothing copied yet"
    if #rows > 0 and (fact.sel >= #rows or fact.sel < 0) then
        fact.sel = 0
    end
    panel.height(96 + math.max(#rows, 1) * 46 + 30)
end

repaint = function()
    rebuild(true)
end

local function refresh_history()
    run("sh", { "-c", "cliphist list 2>/dev/null | head -n " .. MAX_HISTORY }, function(out)
        local items = {}
        for line in (out or ""):gmatch("[^\n]+") do
            local id_s, preview = line:match("^(%d+)%s+(.*)$")
            if id_s and preview then
                local label = image_label(preview)
                items[#items + 1] = { raw = line, id = tonumber(id_s), preview = label or preview, image = label ~= nil }
            end
        end
        history = items
        rebuild(true)
    end)
end

on("fact:open", function(v)
    if v == true or v == 1 then
        text.clip_q = ""
        refresh_history()
        rebuild(false)
    end
end)

on("text:clip_q", function()
    rebuild(false)
end)

-- ── buttons ──────────────────────────────────────────────────────
local function entry_at(src)
    return view[off + (tonumber(src) or 0) + 1]
end

on("copy_clip", function(i)
    local v = entry_at(i)
    fact.open = false
    if not v then
        return
    end
    if v.kind == "pin" then
        -- a pinned entry is the text itself
        run("sh", { "-c", 'printf "%s" "$1" | wl-copy', "x", pins[v.idx].text }, nil, { output = false })
    else
        -- a history entry goes back through cliphist (it knows the id) into the clipboard
        run("sh", { "-c", 'printf "%s" "$1" | cliphist decode | wl-copy', "x", history[v.idx].raw }, nil, { output = false })
    end
    run("notify-send", { "-a", "Clipboard", "-i", "edit-paste", "Copied", "Ready to paste" }, nil, { output = false })
end)

on("pin_clip", function(i)
    local v = entry_at(i)
    if not v then
        return
    end
    if v.kind == "pin" then
        table.remove(pins, v.idx)
        save_pins()
        rebuild(true)
    else
        -- the full text, decoded, is what is kept (the list only has a one-line preview)
        run("sh", { "-c", 'printf "%s" "$1" | cliphist decode', "x", history[v.idx].raw }, function(out)
            if out and out ~= "" then
                table.insert(pins, 1, { text = out })
                save_pins()
                rebuild(true)
            end
        end)
    end
end)

on("clip_scroll", function(wheel)
    local step = (tonumber(wheel) or 0) > 0 and -1 or 1
    off = math.max(0, math.min(math.max(0, #view - MAX_SHOWN), off + step))
    rebuild(true)
end)

-- Keep the cursor in view when the arrows run past the ends of the 8 shown rows.
on("fact:sel", function()
    -- (the rows are the window; moving past it is handled by the wheel)
end)

on("clear_all", function()
    -- the history goes; pinned entries stay
    run("cliphist", { "wipe" }, nil, { output = false })
    history = {}
    rebuild(false)
    run("notify-send", { "-a", "Clipboard", "Clipboard cleared", "Pinned entries were kept" }, nil, { output = false })
end)

run("sh", { "-c", 'printf %s "$HOME"' }, function(out)
    if out and out ~= "" then
        CACHE = out .. "/.cache/beskar/clipboard"
        rebuild(true)
    end
end)
refresh_history()

-- one panel at a time
require("exclusive")("clipboard")
