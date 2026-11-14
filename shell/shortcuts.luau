-- C5 shortcut backend: resolve niri's include tree, list the bindings, and edit ONLY a Beskar-owned include.
--
-- Pure logic. Every filesystem / niri effect goes through an injected `fs` table, so tests can fake it and Settings
-- reaches the real one through shortcuts_adapter.py (see M.adapter_fs / M.async). Nothing here spawns a process,
-- starts a timer or imports command strings: the only editable actions are the static tables below.
--
-- fs contract (every function is synchronous from this module's point of view; M.async makes them yield):
--   fs.read(path)                -> text | nil, "missing" | "unreadable" | "too_large"
--   fs.real(path)                -> canonical path | nil              (optional: symlink-aware cycle detection)
--   fs.write(path, text, expect) -> true | nil, "changed" | "refused" | "too_large" | "io"
--                                   atomic + backup (path .. ".beskar-bak"); `expect` = the text read earlier, nil = the
--                                   file must not exist (compare-and-swap: another writer is never overwritten)
--   fs.remove(path, expect)      -> true | nil, reason                (only used to undo a file this module created)
--   fs.validate(config)          -> ok, message                       (niri validate -c <config>: the FULL config)
--   fs.reload()                  -> ok, message                       (niri msg action load-config-file)
--
-- niri semantics this relies on (checked against niri 26.04, see tests/shortcuts.lua):
--   * `include "p"` / `include optional=true "p"` at the top level, processed IN PLACE; relative paths are relative to
--     the including file, `~/` is the home folder, a missing non-optional file or a file including itself is an error.
--   * the same key twice in ONE file is an error (keys compare case-insensitively); across files the later definition
--     replaces the earlier one. That last point is the assumption behind every "wins" below.
--   * `Mod` is Super on a TTY session: Mod+X and Super+X are the same key here (reported as an alias conflict).
--
-- PUBLIC API (stable; everything else is internal)
--   S.context{ home, start_sh, config?, owned?, beskar?, xdg_config?, actions? } -> ctx   absolute paths; defaults under ~/.config/niri
--   S.load(fs, ctx[, opts])      -> { tree, rows, conflicts, issues, complete, owned = {path, included, present}, can_install_include }
--   S.apply(fs, ctx, request)    -> { ok, status, conflicts, errors, issues, message, stuck, tree }
--        request = { ops = { {op="set", key="Mod+Shift+K", route={kind="shell"|"niri", id=...}, repeat?, allow_when_locked?},
--                            {op="remove", key=...} },
--                    accept = { "Mod+Q", ... },        -- conflicts the UI showed and the user confirmed, by key
--                    ensure_include = bool }           -- add `include optional=true` to beskar.kdl when the file is not in the tree
--        status: applied | applied_reload_failed | unchanged                      (ok)
--                conflict | shadowed | include_required | needs_installer | invalid_request | tree_incomplete |
--                config_invalid (already broken before) | write_failed | rolled_back (niri rejected it; files restored) |
--                rollback_failed (files NOT restored: `stuck` names them, <file>.beskar-bak holds the old text)
--   S.resolve(fs, ctx[, opts])   -> tree { files, binds, effective, conflicts, issues, complete, owned_included, ... }
--   S.plan(tree, ctx, request, { owned_text, beskar_text }) -> { status, changes = {{path, text, expect, role}}, conflicts, errors }
--   S.rows(tree[, {all, include_inert}]) -> { keys, what, key, ident, source = "user"|"beskar"|"owned", path, line, editable, shadowed, conflict }
--   S.search(rows, query)        every word must match label, key, action or file name
--   S.routes([ctx])              the picker: { kind, id, label } for every route that may be written
--   S.parse_kdl(text), S.parse_key(spec), S.pretty_key(spec), S.normalize(path)
--   S.adapter_fs(runner)         fs over shortcuts_adapter.py; runner(argv) -> out, code
--   S.async(cfg, fn, done), S.load_async(cfg, ctx, done[, opts]), S.apply_async(cfg, ctx, request, done)
--        cfg = { run = run, adapter = "shortcuts_adapter.py", python = "python3" }; the scene's permissions need
--        run: "python3 shortcuts_adapter.py" (programs run in the scene's folder). done(result, err) fires once.
--
-- Safety rules this module keeps (tests/shortcuts.lua checks each):
--   * only <niri dir>/beskar-shortcuts.kdl and beskar.kdl are ever written (the adapter refuses every other name);
--     the user's config.kdl and its other includes are only read;
--   * a request carries data only: a key and a route id from the tables above; no command or title text is accepted;
--   * edits splice the touched lines; everything else in the file stays byte for byte;
--   * any conflict with a binding outside the owned file stops the edit until the caller accepts that key, and a
--     binding that a LATER file would silently override is refused outright;
--   * order: resolve (incomplete tree = stop) -> plan -> validate the current config -> compare-and-swap write with backup
--     -> validate the FULL config -> prove the binding is in the new tree -> reload; any failure restores the old text.
local M = {}
M.version = 1
M.OWNED_NAME = "beskar-shortcuts.kdl"
M.BESKAR_NAME = "beskar.kdl"
M.MAX_BYTES = 1048576
M.MAX_WRITE = 100000

-- ── static tables: the only actions this backend will write ───────────────────────────────────────────────────
-- `start.sh <cli>` routes (checked against shell/start.sh by tests/shortcuts.lua). Labels come from actions.luau
-- (`cli_labels`) when it knows the route; these are the fallback and the picker's ordering.
local SHELL_ROUTES = {
    { id = "spotlight", label = "Spotlight" },
    { id = "clipboard", label = "Clipboard" },
    { id = "notifications", label = "Notifications" },
    { id = "wallpapers", label = "Wallpapers" },
    { id = "control-center", label = "Control Center" },
    { id = "appswitcher", label = "App Switcher" },
    { id = "overview", label = "Window Overview" },
    { id = "settings", label = "Settings" },
    { id = "widgets", label = "Edit Widgets" },
    { id = "shortcuts", label = "Keyboard Shortcuts" },
    { id = "power-menu", label = "Session Menu" },
    { id = "lock", label = "Lock Screen" },
    { id = "capture", label = "Screenshot / Record" },
    { id = "shot", label = "Screenshot: Screen (with the shell)" },
    { id = "timer", label = "Timer" },
    { id = "dashboard", label = "Today" },
    { id = "vol-up", label = "Volume up" },
    { id = "vol-down", label = "Volume down" },
    { id = "mute", label = "Mute" },
    { id = "bright-up", label = "Brightness up" },
    { id = "bright-down", label = "Brightness down" },
}
-- niri actions that take no argument. `quit`, `spawn` and anything with an argument are NOT here on purpose.
local NIRI_ROUTES = {
    { id = "close-window", label = "Close window" },
    { id = "fullscreen-window", label = "Fullscreen window" },
    { id = "toggle-window-floating", label = "Float / tile window" },
    { id = "switch-focus-between-floating-and-tiling", label = "Switch floating / tiling focus" },
    { id = "maximize-column", label = "Maximize column" },
    { id = "maximize-window-to-edges", label = "Maximize window to the edges" },
    { id = "center-column", label = "Centre column" },
    { id = "center-visible-columns", label = "Centre visible columns" },
    { id = "switch-preset-column-width", label = "Cycle column width" },
    { id = "toggle-column-tabbed-display", label = "Tabbed column" },
    { id = "consume-window-into-column", label = "Stack window into the column" },
    { id = "expel-window-from-column", label = "Pull window out of the column" },
    { id = "consume-or-expel-window-left", label = "Move window into the left column" },
    { id = "consume-or-expel-window-right", label = "Move window into the right column" },
    { id = "focus-column-left", label = "Focus column left" },
    { id = "focus-column-right", label = "Focus column right" },
    { id = "focus-window-up", label = "Focus window above" },
    { id = "focus-window-down", label = "Focus window below" },
    { id = "move-column-left", label = "Move column left" },
    { id = "move-column-right", label = "Move column right" },
    { id = "focus-workspace-up", label = "Workspace up" },
    { id = "focus-workspace-down", label = "Workspace down" },
    { id = "toggle-overview", label = "niri overview" },
    { id = "screenshot", label = "Screenshot (choose area)" },
    { id = "screenshot-screen", label = "Screenshot the screen" },
    { id = "screenshot-window", label = "Screenshot the window" },
    { id = "power-off-monitors", label = "Turn monitors off" },
}
local shell_by_id, niri_by_id = {}, {}
for _, r in ipairs(SHELL_ROUTES) do shell_by_id[r.id] = r end
for _, r in ipairs(NIRI_ROUTES) do niri_by_id[r.id] = r end
M.SHELL_ROUTES, M.NIRI_ROUTES = SHELL_ROUTES, NIRI_ROUTES

local function load_actions(ctx)
    if ctx and ctx.actions then return ctx.actions end
    local ok, a = pcall(require, "actions")
    return ok and type(a) == "table" and a or { cli_labels = {} }
end

local function humanize(action)
    local w = tostring(action):match("^([%w%-]+)") or tostring(action)
    return (w:gsub("%-", " "):gsub("^%l", string.upper))
end

-- Route picker data for the UI: { kind, id, label }, shell routes first.
function M.routes(ctx)
    local labels = load_actions(ctx).cli_labels or {}
    local out = {}
    for _, r in ipairs(SHELL_ROUTES) do out[#out + 1] = { kind = "shell", id = r.id, label = labels[r.id] or r.label } end
    for _, r in ipairs(NIRI_ROUTES) do out[#out + 1] = { kind = "niri", id = r.id, label = r.label } end
    return out
end

local function route_label(route, ctx)
    if route.kind == "shell" then
        local labels = load_actions(ctx).cli_labels or {}
        return labels[route.id] or shell_by_id[route.id].label
    end
    return niri_by_id[route.id].label
end

-- ── paths ──────────────────────────────────────────────────────────────────────────────────────────────────────
local function dirname(p)
    local d = p:match("^(.*)/[^/]*$")
    if d == nil then return "." end
    return d == "" and "/" or d
end
local function basename(p) return p:match("([^/]*)$") end

local function normalize(path)
    local abs = path:sub(1, 1) == "/"
    local out = {}
    for part in path:gmatch("[^/]+") do
        if part == ".." then
            if #out > 0 and out[#out] ~= ".." then out[#out] = nil elseif not abs then out[#out + 1] = ".." end
        elseif part ~= "." then
            out[#out + 1] = part
        end
    end
    return (abs and "/" or "") .. table.concat(out, "/")
end
M.normalize = normalize

local function expand(path, home, base)
    if path == "~" then path = home
    elseif path:sub(1, 2) == "~/" then path = home .. "/" .. path:sub(3) end
    if path:sub(1, 1) ~= "/" then path = base .. "/" .. path end
    return normalize(path)
end

-- ── KDL reader (v1 + v2 subset, tolerant; niri's own validator is the final judge) ─────────────────────────────
-- Node: { name, args, props, children, disabled, line, s, e, cs, ce }   s/e = byte span of the node (e exclusive),
-- cs/ce = the `{` and the matching `}` of its children block (children == nil when it has none).
local NULL = setmetatable({}, { __tostring = function() return "null" end })
M.NULL = NULL
local MAX_DEPTH, MAX_NODES = 24, 50000

local ESC = { n = "\n", r = "\r", t = "\t", ["\\"] = "\\", ['"'] = '"', b = "\b", f = "\f", s = " ", ["/"] = "/" }

function M.parse_kdl(text)
    if type(text) ~= "string" then return nil, { line = 1, message = "not text" } end
    if #text > M.MAX_BYTES then return nil, { line = 1, message = "file too large" } end
    if text:find("\0", 1, true) then return nil, { line = 1, message = "binary data" } end
    local s, n, i = text, #text, 1
    local nl = {}
    for p in s:gmatch("()\n") do nl[#nl + 1] = p end
    local function line_at(pos)
        local lo, hi = 1, #nl
        local count = 0
        while lo <= hi do
            local mid = math.floor((lo + hi) / 2)
            if nl[mid] < pos then count = mid; lo = mid + 1 else hi = mid - 1 end
        end
        return count + 1
    end
    local function fail(msg, pos) error({ kdl = true, line = line_at(pos or i), message = msg }, 0) end
    local count = 0

    local function skip_block_comment()
        local depth = 0
        while i <= n do
            local two = s:sub(i, i + 1)
            if two == "/*" then depth = depth + 1; i = i + 2
            elseif two == "*/" then depth = depth - 1; i = i + 2; if depth == 0 then return end
            else i = i + 1 end
        end
        fail("unterminated comment")
    end
    -- whitespace, comments and line continuations that do NOT end a node
    local function skip_inline()
        while i <= n do
            local c = s:sub(i, i)
            if c == " " or c == "\t" or c == "\r" or c == "\f" or c == "\v" then i = i + 1
            elseif c == "\\" then
                local j = i + 1
                while s:sub(j, j):match("^[ \t\r]$") do j = j + 1 end
                if s:sub(j, j + 1) == "//" then while j <= n and s:sub(j, j) ~= "\n" do j = j + 1 end end
                if s:sub(j, j) == "\n" then i = j + 1 elseif j > n then i = j else return end
            elseif s:sub(i, i + 1) == "/*" then skip_block_comment()
            elseif s:sub(i, i + 1) == "//" then
                while i <= n and s:sub(i, i) ~= "\n" do i = i + 1 end
            else return end
        end
    end
    local function dedent(body)
        body = body:gsub("^[ \t]*\r?\n", "", 1)
        local last = body:match("\n([ \t]*)$") or body:match("^([ \t]*)$")
        if last then
            body = body:gsub("\n[ \t]*$", "", 1)
            if #last > 0 then
                body = ("\n" .. body):gsub("\n" .. last:gsub("%p", "%%%0"), "\n"):sub(2)
            end
        end
        return body
    end
    local function quoted()
        local multi = s:sub(i, i + 2) == '"""'
        local start = i
        i = i + (multi and 3 or 1)
        local out = {}
        while true do
            if i > n then fail("unterminated string", start) end
            local c = s:sub(i, i)
            if multi and s:sub(i, i + 2) == '"""' then i = i + 3; break end
            if not multi and c == '"' then i = i + 1; break end
            if not multi and c == "\n" then fail("newline in string", start) end
            if c == "\\" then
                local e = s:sub(i + 1, i + 1)
                if e == "u" then
                    local hex = s:match("^{(%x+)}", i + 2)
                    if not hex or #hex > 6 then fail("bad unicode escape") end
                    local cp = tonumber(hex, 16)
                    if cp > 0x10FFFF or (cp >= 0xD800 and cp <= 0xDFFF) then fail("bad unicode escape") end
                    out[#out + 1] = utf8.char(cp)
                    i = i + 4 + #hex
                elseif ESC[e] then out[#out + 1] = ESC[e]; i = i + 2
                elseif e:match("^%s$") then
                    i = i + 1
                    while i <= n and s:sub(i, i):match("^%s$") do i = i + 1 end
                else fail("bad escape \\" .. e) end
            else out[#out + 1] = c; i = i + 1 end
        end
        local v = table.concat(out)
        return multi and dedent(v) or v
    end
    local function raw()
        local start = i
        if s:sub(i, i) == "r" then i = i + 1 end
        local hashes = s:match("^#*", i)
        i = i + #hashes
        if s:sub(i, i) ~= '"' then fail("bad raw string", start) end
        i = i + 1
        local close = '"' .. hashes
        local e = s:find(close, i, true)
        if not e then fail("unterminated raw string", start) end
        local v = s:sub(i, e - 1)
        i = e + #close
        return v
    end
    local function bare()
        local start = i
        while i <= n do
            local c = s:sub(i, i)
            if c:match("[%s{}();=\"\\]") then break end
            if c == "/" and (s:sub(i + 1, i + 1) == "/" or s:sub(i + 1, i + 1) == "*") then break end
            i = i + 1
        end
        if i == start then fail("unexpected `" .. s:sub(i, i) .. "`") end
        return s:sub(start, i - 1)
    end
    local function skip_type()
        if s:sub(i, i) == "(" then
            local e = s:find(")", i, true)
            if not e then fail("unterminated type annotation") end
            i = e + 1
            skip_inline()
        end
    end
    -- returns value, kind ("string" | "word" | "number" | "boolean" | "null")
    local function token()
        skip_type()
        local c = s:sub(i, i)
        if c == '"' then return quoted(), "string" end
        if c == "#" then
            if s:match('^#+"', i) then return raw(), "string" end
            i = i + 1
            local w = bare()
            if w == "true" then return true, "boolean" elseif w == "false" then return false, "boolean"
            elseif w == "null" then return NULL, "null" end
            return "#" .. w, "word"
        end
        if c == "r" and s:match('^r#*"', i) then return raw(), "string" end
        local w = bare()
        if w == "true" then return true, "boolean" elseif w == "false" then return false, "boolean"
        elseif w == "null" then return NULL, "null" end
        local num = w:gsub("_", "")
        if num:match("^[+-]?%d+%.?%d*[eE]?[+-]?%d*$") or num:match("^[+-]?0x%x+$") then
            return tonumber(num) or w, "number"
        end
        return w, "word"
    end

    local parse_nodes
    local function parse_node(depth, disabled, ns)
        count = count + 1
        if count > MAX_NODES then fail("too many nodes") end
        skip_type()
        local line = line_at(ns)
        local name = token()
        if type(name) ~= "string" then fail("bad node name", ns) end
        local node = { name = name, args = {}, props = {}, disabled = disabled, line = line, s = ns }
        local last = i
        while true do
            skip_inline()
            local c = s:sub(i, i)
            if i > n or c == "\n" or c == ";" or c == "}" then break end
            if s:sub(i, i + 1) == "/-" then
                i = i + 2
                skip_inline()
                if s:sub(i, i) == "{" then
                    i = i + 1
                    parse_nodes(depth + 1)
                    i = i + 1
                else
                    local v = token()
                    skip_inline()
                    if s:sub(i, i) == "=" then i = i + 1; skip_inline(); token() end
                end
                last = i
            elseif node.children then
                fail("expected a newline or `;` after the children block")
            elseif c == "{" then
                node.cs = i
                i = i + 1
                node.children = parse_nodes(depth + 1)
                node.ce = i
                i = i + 1
                last = i
            else
                local v, kind = token()
                if s:sub(i, i) == "=" and (kind == "string" or kind == "word") then
                    i = i + 1
                    skip_inline()
                    local val = token()
                    node.props[v] = val
                else
                    node.args[#node.args + 1] = v
                end
                last = i
            end
        end
        node.e = last
        return node
    end
    parse_nodes = function(depth)
        if depth > MAX_DEPTH then fail("nesting too deep") end
        local out = {}
        while true do
            while i <= n do
                local c = s:sub(i, i)
                if c:match("^%s$") or c == ";" then i = i + 1
                elseif s:sub(i, i + 1) == "//" then while i <= n and s:sub(i, i) ~= "\n" do i = i + 1 end
                elseif s:sub(i, i + 1) == "/*" then skip_block_comment()
                else break end
            end
            if i > n then
                if depth > 0 then fail("unterminated block") end
                return out
            end
            local c = s:sub(i, i)
            if c == "}" then
                if depth == 0 then fail("unexpected `}`") end
                return out
            end
            local disabled, ns = false, i
            if s:sub(i, i + 1) == "/-" then
                disabled = true
                i = i + 2
                while i <= n and s:sub(i, i):match("^%s$") do i = i + 1 end
                ns = i
            end
            local node = parse_node(depth, disabled, ns)
            out[#out + 1] = node
            -- a node ends at a newline, `;`, `}` or the end of the text; anything else is a syntax error
            local c2 = s:sub(i, i)
            if i <= n and c2 ~= "\n" and c2 ~= ";" and c2 ~= "}" then fail("expected a newline or `;`") end
        end
    end
    local ok, result = pcall(parse_nodes, 0)
    if ok then return { nodes = result, text = text } end
    if type(result) == "table" and result.kdl then return nil, { line = result.line, message = result.message } end
    return nil, { line = 1, message = tostring(result) }
end

-- ── keys ───────────────────────────────────────────────────────────────────────────────────────────────────────
local MODS = {
    mod = { "super", "Mod" }, super = { "super", "Super" }, win = { "super", "Super" },
    ctrl = { "ctrl", "Ctrl" }, control = { "ctrl", "Ctrl" },
    shift = { "shift", "Shift" }, alt = { "alt", "Alt" },
    iso_level3_shift = { "iso_level3_shift", "ISO_Level3_Shift" }, mod5 = { "iso_level3_shift", "ISO_Level3_Shift" },
    iso_level5_shift = { "iso_level5_shift", "ISO_Level5_Shift" }, mod3 = { "iso_level5_shift", "ISO_Level5_Shift" },
}
local MOD_ORDER = { "super", "ctrl", "shift", "alt", "iso_level3_shift", "iso_level5_shift" }

-- "Mod+Shift+q" -> { ident, strict, key, name, mods }
--   key    canonical spelling, modifiers in a fixed order ("Mod+Shift+q"); what gets written to the file
--   ident  what conflicts compare: modifier set with Mod = Super (a TTY session) + lower-cased key name
--   strict like ident but Mod and Super differ: what niri's own duplicate check compares inside one file
function M.parse_key(spec)
    if type(spec) ~= "string" or spec == "" or #spec > 80 then return nil, "empty or too long" end
    local parts = {}
    for p in (spec .. "+"):gmatch("([^+]*)%+") do parts[#parts + 1] = p end
    local name = parts[#parts]
    if not name:match("^[%w_]+$") or #name > 40 then return nil, "bad key name" end
    local shown, canon = {}, {}
    for k = 1, #parts - 1 do
        local def = MODS[parts[k]:lower()]
        if not def then return nil, "unknown modifier `" .. parts[k] .. "`" end
        if canon[def[1]] then return nil, "modifier repeated" end
        canon[def[1]] = def[2]
    end
    local mods = {}
    for _, id in ipairs(MOD_ORDER) do
        if canon[id] then mods[#mods + 1] = id; shown[#shown + 1] = canon[id] end
    end
    shown[#shown + 1] = name
    local key = table.concat(shown, "+")
    return {
        ident = (#mods > 0 and (table.concat(mods, "+") .. "+") or "") .. name:lower(),
        strict = key:lower(), key = key, name = name, mods = mods,
    }
end

local KEY_NAMES = {
    xf86audioraisevolume = "Volume +", xf86audiolowervolume = "Volume −", xf86audiomute = "Mute", xf86audiomicmute = "Mic mute",
    xf86monbrightnessup = "Brightness +", xf86monbrightnessdown = "Brightness −",
    xf86audioplay = "Play / Pause", xf86audionext = "Next track", xf86audioprev = "Previous track", xf86audiostop = "Stop",
    comma = ",", period = ".", slash = "/", ["return"] = "Enter", bracketleft = "[", bracketright = "]", print = "PrtSc",
    minus = "−", equal = "=", next = "Page Down", prior = "Page Up",
}
-- "Mod+Shift+Q" -> "Super + Shift + Q" (same wording Settings shows today)
function M.pretty_key(spec)
    local out = {}
    for word in tostring(spec):gmatch("[^%+]+") do
        local low = word:lower()
        out[#out + 1] = low == "mod" and "Super" or KEY_NAMES[low] or word
    end
    return table.concat(out, " + ")
end

-- ── bindings ───────────────────────────────────────────────────────────────────────────────────────────────────
local function is_shell_script(p) return type(p) == "string" and (p == "start.sh" or p:sub(-9) == "/start.sh") end

local function action_text(node)
    local first = node.children and node.children[1]
    if not first then return "" end
    local parts = { first.name }
    for _, a in ipairs(first.args) do parts[#parts + 1] = type(a) == "string" and ('"' .. a .. '"') or tostring(a) end
    return table.concat(parts, " ")
end

-- what a binding does, in the shell's terms: { kind = "shell" | "niri" | "spawn", id, label, route, inert }
local function classify(node, ctx)
    local act = node.children and node.children[1]
    local title = type(node.props["hotkey-overlay-title"]) == "string" and node.props["hotkey-overlay-title"] or nil
    local info = { kind = "niri", id = "", label = title, route = false, inert = false }
    if not act then info.kind = "none"; info.label = title or "(no action)"; return info end
    info.id = act.name
    if act.name == "spawn" then
        local cmd, arg = act.args[1], act.args[2]
        if cmd == "dms" then info.inert = true end
        if is_shell_script(cmd) and type(arg) == "string" and #act.args == 2 then
            info.kind, info.id = "shell", arg
            info.route = shell_by_id[arg] ~= nil
            info.label = title or (load_actions(ctx).cli_labels or {})[arg] or (shell_by_id[arg] and shell_by_id[arg].label) or humanize(arg)
        else
            info.kind = "spawn"
            info.label = title or ("Open " .. (type(cmd) == "string" and basename(cmd) or "program"))
        end
    else
        info.route = niri_by_id[act.name] ~= nil and #act.args == 0
        info.label = title or (niri_by_id[act.name] and niri_by_id[act.name].label) or humanize(act.name)
    end
    return info
end

-- ── include tree ───────────────────────────────────────────────────────────────────────────────────────────────
-- ctx = { home, config, owned?, beskar?, start_sh?, actions? }; paths are absolute.
function M.context(env)
    local home = (env.home or ""):gsub("/+$", "")
    local config_dir = env.config_dir or ((env.xdg_config or (home .. "/.config")) .. "/niri")
    return {
        home = home, config = env.config or (config_dir .. "/config.kdl"),
        owned = env.owned or (config_dir .. "/" .. M.OWNED_NAME),
        beskar = env.beskar or (config_dir .. "/" .. M.BESKAR_NAME),
        start_sh = env.start_sh, actions = env.actions,
    }
end

local function add_issue(tree, severity, kind, path, line, message)
    tree.issues[#tree.issues + 1] = { severity = severity, kind = kind, path = path, line = line, message = message }
    if severity == "error" then tree.complete = false end
end

function M.resolve(fs, ctx, opts)
    opts = opts or {}
    local max_depth, max_files, max_bytes = opts.max_depth or 8, opts.max_files or 48, opts.max_bytes or 4 * M.MAX_BYTES
    local tree = { root = ctx.config, files = {}, binds = {}, issues = {}, complete = true, owned_path = ctx.owned }
    local function key_of(path) return (fs.real and fs.real(path)) or path end
    local owned_key = key_of(ctx.owned)
    local beskar_key = key_of(ctx.beskar or "")
    local stack, seq, total = {}, 0, 0
    tree.owned_key = owned_key

    local visit
    local function binds_of(file, node)
        for _, child in ipairs(node.children or {}) do
            if not child.disabled then
                local key, err = M.parse_key(child.name)
                if not key then
                    add_issue(tree, "warning", "bad_key", file.path, child.line, "`" .. child.name .. "`: " .. err)
                elseif not child.children or not child.children[1] then
                    add_issue(tree, "warning", "no_action", file.path, child.line, "`" .. child.name .. "` has no action")
                else
                    seq = seq + 1
                    local info = classify(child, ctx)
                    local owned = file.key == owned_key
                    tree.binds[#tree.binds + 1] = {
                        seq = seq, ident = key.ident, key = key.key, written = child.name, pretty = M.pretty_key(child.name),
                        what = info.label, kind = info.kind, id = info.id, route = info.route, inert = info.inert,
                        action = action_text(child), props = child.props, title = child.props["hotkey-overlay-title"],
                        path = file.path, file = file.index, line = child.line,
                        owned = owned, source = owned and "owned" or (file.key == beskar_key and "beskar" or "user"),
                        node = child,
                    }
                end
            end
        end
    end
    visit = function(path, depth, parent, line, optional)
        if #tree.files >= max_files then add_issue(tree, "error", "file_limit", path, line, "more than " .. max_files .. " files"); return end
        if depth > max_depth then add_issue(tree, "error", "depth_limit", path, line, "includes nested deeper than " .. max_depth); return end
        local key = key_of(path)
        if stack[key] then add_issue(tree, "error", "cycle", path, line, "include cycle through " .. path); return end
        local file = { path = path, key = key, depth = depth, parent = parent, line = line, optional = optional, index = #tree.files + 1 }
        tree.files[#tree.files + 1] = file
        seq = seq + 1 -- entry tick: positions in niri's processing order never tie, even for files without bindings
        file.first_seq, file.last_seq = seq, seq
        local text, why = fs.read(path)
        if not text then
            file.status = why or "unreadable"
            if why == "missing" and optional then
                add_issue(tree, "info", "optional_missing", path, line, "optional include is absent")
            else
                add_issue(tree, "error", why == "missing" and "missing" or (why or "unreadable"), path, line,
                    (why == "missing" and "included file is missing: " or "cannot read ") .. path)
            end
            return
        end
        total = total + #text
        if total > max_bytes then file.status = "too_large"; add_issue(tree, "error", "size_limit", path, line, "include tree is too large"); return end
        local doc, err = M.parse_kdl(text)
        if not doc then
            file.status = "invalid_kdl"
            add_issue(tree, "error", "invalid_kdl", path, err.line, path .. ":" .. err.line .. ": " .. err.message)
            return
        end
        file.status, file.text, file.doc = "ok", text, doc
        stack[key] = true
        for _, node in ipairs(doc.nodes) do
            if not node.disabled then
                if node.name == "include" then
                    local target = node.args[1]
                    if type(target) ~= "string" or target == "" then
                        add_issue(tree, "error", "bad_include", path, node.line, "include needs a path")
                    else
                        visit(expand(target, ctx.home, dirname(path)), depth + 1, file.index, node.line, node.props.optional == true)
                    end
                elseif node.name == "binds" then
                    binds_of(file, node)
                end
            end
        end
        stack[key] = nil
        seq = seq + 1
        file.last_seq = seq
    end
    visit(ctx.config, 0, nil, nil, false)

    -- effective bindings: the later definition replaces the earlier one
    local last = {}
    for _, b in ipairs(tree.binds) do last[b.ident] = b end
    tree.effective, tree.conflicts = {}, {}
    local groups, order = {}, {}
    for _, b in ipairs(tree.binds) do
        if last[b.ident] ~= b then b.shadowed_by = last[b.ident] else tree.effective[#tree.effective + 1] = b end
        if not groups[b.ident] then groups[b.ident] = {}; order[#order + 1] = b.ident end
        local g = groups[b.ident]
        g[#g + 1] = b
    end
    for _, ident in ipairs(order) do
        local g = groups[ident]
        if #g > 1 then
            local same_file = false
            for a = 1, #g do for c = a + 1, #g do if g[a].file == g[c].file then same_file = true end end end
            tree.conflicts[#tree.conflicts + 1] = {
                ident = ident, key = g[#g].key, entries = g, winner = g[#g],
                kind = same_file and "duplicate_in_file" or "shadowed",
            }
        end
    end
    for _, f in ipairs(tree.files) do
        if f.key == owned_key and f.status == "ok" then tree.owned_file = f; break end
    end
    tree.owned_included = false
    for _, f in ipairs(tree.files) do
        if f.key == owned_key then tree.owned_included = true; tree.owned_visit = tree.owned_visit or f end
    end
    for _, f in ipairs(tree.files) do
        if ctx.beskar and f.key == beskar_key and f.status == "ok" then tree.beskar_file = f; break end
    end
    return tree
end

-- ── Settings-facing list and search ────────────────────────────────────────────────────────────────────────────
-- Rows replace parse_binds' { keys, what }: effective bindings only, with provenance for the UI.
function M.rows(tree, opts)
    opts = opts or {}
    local rows = {}
    for _, b in ipairs(opts.all and tree.binds or tree.effective) do
        if opts.include_inert or not b.inert then
            rows[#rows + 1] = {
                keys = b.pretty, what = b.what, key = b.key, ident = b.ident, source = b.source, path = b.path, line = b.line,
                editable = b.owned and b.route and true or false, action = b.action, kind = b.kind, id = b.id,
                shadowed = b.shadowed_by ~= nil, conflict = false,
            }
        end
    end
    local bad = {}
    for _, c in ipairs(tree.conflicts) do bad[c.ident] = true end
    for _, r in ipairs(rows) do r.conflict = bad[r.ident] == true end
    table.sort(rows, function(a, c)
        local x, y = a.what:lower(), c.what:lower()
        if x ~= y then return x < y end
        return a.keys < c.keys
    end)
    return rows
end

-- every word of the query must appear in the label, the key, the action text or the file name ("super" finds Mod)
function M.search(rows, query)
    local words = {}
    for w in tostring(query or ""):lower():gmatch("%S+") do words[#words + 1] = w end
    if #words == 0 then return rows end
    local out = {}
    for _, r in ipairs(rows) do
        local hay = (r.what .. " " .. r.keys .. " " .. r.key .. " " .. (r.action or "") .. " " .. basename(r.path or "")):lower()
        hay = hay .. " " .. hay:gsub("mod%+", "super+"):gsub("%+", " ")
        local all = true
        for _, w in ipairs(words) do if not hay:find(w, 1, true) then all = false; break end end
        if all then out[#out + 1] = r end
    end
    return out
end

-- ── owned-file editing ─────────────────────────────────────────────────────────────────────────────────────────
local function kdl_string(v)
    return '"' .. v:gsub('[%c"\\]', function(c)
        if c == '"' then return '\\"' elseif c == "\\" then return "\\\\" elseif c == "\n" then return "\\n"
        elseif c == "\r" then return "\\r" elseif c == "\t" then return "\\t" end
        return string.format("\\u{%x}", c:byte())
    end) .. '"'
end

local function safe_path(p)
    return type(p) == "string" and p:sub(1, 1) == "/" and #p < 500 and not p:find("[%c\"\\]") and is_shell_script(p)
end

-- one bind node, written entirely from static data: nothing the caller typed reaches the file except the checked key
local function render_bind(op, ctx)
    local key = M.parse_key(op.key)
    local route = op.route
    local props = {}
    if op["repeat"] == false then props[#props + 1] = "repeat=false" end
    if op.allow_when_locked == true then props[#props + 1] = "allow-when-locked=true" end
    props[#props + 1] = "hotkey-overlay-title=" .. kdl_string(route_label(route, ctx))
    local body
    if route.kind == "shell" then body = "spawn " .. kdl_string(ctx.start_sh) .. " " .. kdl_string(route.id) .. ";"
    else body = route.id .. ";" end
    return key.key .. " " .. table.concat(props, " ") .. " { " .. body .. " }"
end

local HEADER = "// Beskar shortcuts. Managed by Beskar Settings: bindings here can be changed there.\n"
    .. "// Other lines in this file are kept as they are. niri applies this file after the files above it.\n"

-- delete a node's whole line(s) when it is alone on them
local function line_span(text, node)
    local a, b = node.s, node.e
    local ls = a
    while ls > 1 and text:sub(ls - 1, ls - 1):match("^[ \t]$") do ls = ls - 1 end
    local lead_ok = ls == 1 or text:sub(ls - 1, ls - 1) == "\n"
    local tail = text:match("^[ \t]*;?[ \t]*//[^\n]*()", b) or text:match("^[ \t]*;?[ \t]*()", b)
    local tail_end = tail
    local nl_ok = text:sub(tail_end, tail_end) == "\n" or tail_end > #text
    if lead_ok and nl_ok then
        return ls, (text:sub(tail_end, tail_end) == "\n") and tail_end + 1 or tail_end
    end
    return a, b
end

local function dup_in_file(doc)
    local seen, dups = {}, {}
    for _, node in ipairs(doc.nodes) do
        if node.name == "binds" and not node.disabled then
            for _, c in ipairs(node.children or {}) do
                local k = not c.disabled and M.parse_key(c.name)
                if k then
                    if seen[k.strict] then dups[#dups + 1] = c.name end
                    seen[k.strict] = true
                end
            end
        end
    end
    return dups
end

-- Splice the operations into the owned file's text. Returns new_text | nil, errors.
-- Everything outside the touched lines is kept byte for byte.
local function splice_owned(text, ops, ctx)
    local doc, err = M.parse_kdl(text)
    if not doc then return nil, { { kind = "owned_invalid", message = "the shortcuts file has a syntax error at line " .. err.line .. ": " .. err.message } } end
    local d = dup_in_file(doc)
    if #d > 0 then return nil, { { kind = "owned_duplicate", message = "the shortcuts file binds " .. d[1] .. " twice; fix it first" } } end
    local binds
    local existing = {}
    for _, node in ipairs(doc.nodes) do
        if node.name == "binds" and not node.disabled and node.children then
            binds = binds or node
            for _, c in ipairs(node.children) do
                local k = not c.disabled and M.parse_key(c.name)
                if k then existing[k.ident] = c end
            end
        end
    end
    local splices, inserts, errors = {}, {}, {}
    for _, op in ipairs(ops) do
        local k = M.parse_key(op.key)
        local cur = existing[k.ident]
        if op.op == "remove" then
            if cur then
                local a, b = line_span(text, cur)
                splices[#splices + 1] = { a, b, "" }
            end
        else
            local line = render_bind(op, ctx)
            if cur then
                splices[#splices + 1] = { cur.s, cur.e, line }
            else
                inserts[#inserts + 1] = "    " .. line
            end
        end
    end
    -- apply back to front so offsets stay valid
    local function apply(list)
        table.sort(list, function(x, y) return x[1] > y[1] end)
        for idx = 1, #list - 1 do
            if list[idx][1] < list[idx + 1][2] then return false end
        end
        for _, sp in ipairs(list) do text = text:sub(1, sp[1] - 1) .. sp[3] .. text:sub(sp[2]) end
        return true
    end
    if #inserts > 0 then
        if binds then
            local ce = binds.ce
            local ls = ce
            while ls > 1 and text:sub(ls - 1, ls - 1):match("^[ \t]$") do ls = ls - 1 end
            if ls == 1 or text:sub(ls - 1, ls - 1) == "\n" then
                splices[#splices + 1] = { ls, ls, table.concat(inserts, "\n") .. "\n" }
            else
                splices[#splices + 1] = { ce, ce, "\n" .. table.concat(inserts, "\n") .. "\n" }
            end
        else
            local block = "binds {\n" .. table.concat(inserts, "\n") .. "\n}\n"
            local at = #text + 1
            if text == "" then block = HEADER .. block
            elseif text:sub(-1) ~= "\n" then block = "\n" .. block end
            splices[#splices + 1] = { at, at, block }
        end
    end
    if not apply(splices) then return nil, { { kind = "internal", message = "overlapping edits" } } end
    return text
end

local function copy_set(t) local c = {}; for k, v in pairs(t or {}) do c[k] = v end; return c end

-- Validate and normalise a request's operations. Returns ops | nil, errors.
local function check_ops(request, ctx)
    local ops, errors, seen = {}, {}, {}
    for idx, op in ipairs(request.ops or {}) do
        local bad
        local key = type(op) == "table" and M.parse_key(op.key)
        if type(op) ~= "table" or (op.op ~= "set" and op.op ~= "remove") then bad = { "bad_op", "operation " .. idx .. " must be set or remove" }
        elseif not key then bad = { "bad_key", "operation " .. idx .. ": `" .. tostring(op.key) .. "` is not a valid key" }
        elseif seen[key.ident] then bad = { "duplicate_op", "`" .. op.key .. "` appears twice in one request" }
        elseif op.op == "set" then
            local r = op.route
            local known = type(r) == "table" and ((r.kind == "shell" and shell_by_id[r.id]) or (r.kind == "niri" and niri_by_id[r.id]))
            if not known then bad = { "bad_route", "operation " .. idx .. ": that action is not a known route" }
            elseif r.kind == "shell" and not safe_path(ctx.start_sh) then bad = { "bad_start_sh", "start.sh path must be absolute and plain" }
            elseif (op["repeat"] ~= nil and type(op["repeat"]) ~= "boolean") or (op.allow_when_locked ~= nil and type(op.allow_when_locked) ~= "boolean") then
                bad = { "bad_option", "repeat / allow_when_locked must be true or false" }
            elseif op.allow_when_locked ~= nil and r.kind ~= "shell" then
                bad = { "bad_option", "niri accepts allow-when-locked only on spawn bindings" }
            end
        end
        if bad then errors[#errors + 1] = { kind = bad[1], message = bad[2] }
        else seen[key.ident] = true; ops[#ops + 1] = copy_set(op) end
    end
    return ops, errors
end

-- Conflicts the request would create against bindings that are NOT in the owned file.
local function find_conflicts(tree, ops, ctx)
    local out = {}
    -- where the owned file's bindings land in niri's order
    local pos
    if tree.owned_visit then pos = tree.owned_visit.last_seq
    elseif tree.beskar_file then pos = tree.beskar_file.last_seq + 0.5
    else pos = math.huge end
    for _, op in ipairs(ops) do
        if op.op == "set" then
            local k = M.parse_key(op.key)
            local want = op.route
            for _, b in ipairs(tree.binds) do
                if b.ident == k.ident and not b.owned then
                    local identical = want.kind == b.kind and want.id == b.id and b.kind ~= "spawn"
                    -- an owned binding for this very key already exists: the override was accepted when it was made
                    local standing = false
                    for _, o in ipairs(tree.binds) do if o.owned and o.ident == k.ident then standing = true end end
                    out[#out + 1] = {
                        standing = standing,
                        ident = k.ident, key = k.key, kind = b.source == "beskar" and "beskar_default" or "user_binding",
                        with = { path = b.path, line = b.line, key = b.written, label = b.what, action = b.action, source = b.source },
                        wins = b.seq > pos and "user" or "owned", identical = identical,
                    }
                end
            end
        end
    end
    return out
end

-- plan: pure. Returns { status, changes, conflicts, errors, ops }.
--   status: "ok" | "unchanged" | "invalid_request" | "tree_incomplete" | "conflict" | "shadowed" | "include_required" | "needs_installer"
function M.plan(tree, ctx, request, state)
    request = request or {}
    state = state or {}
    local plan = { status = "ok", changes = {}, conflicts = {}, errors = {}, issues = tree.issues }
    local ops, errors = check_ops(request, ctx)
    if #errors > 0 then plan.status, plan.errors = "invalid_request", errors; return plan end
    plan.ops = ops
    if not tree.complete then plan.status = "tree_incomplete"; return plan end

    local accepted = {}
    for _, id in ipairs(request.accept or {}) do
        local k = M.parse_key(id)
        if k then accepted[k.ident] = true end
    end
    plan.conflicts = find_conflicts(tree, ops, ctx)
    local blocked = false
    for _, c in ipairs(plan.conflicts) do
        if c.wins == "user" and not c.identical then plan.status = "shadowed"; blocked = true
        elseif c.wins == "user" then -- the later user binding does the same thing: nothing is lost
        elseif not c.identical and not c.standing and not accepted[c.ident] then blocked = true; if plan.status == "ok" then plan.status = "conflict" end end
    end
    if blocked then return plan end

    local owned_text = state.owned_text
    local owned_changed = false
    local new_owned = owned_text
    if #ops > 0 then
        local ok, errs = splice_owned(owned_text or "", ops, ctx)
        if not ok then plan.status, plan.errors = "invalid_request", errs; return plan end
        new_owned = ok
        -- round trip: the result parses, has no duplicate key, and holds what was asked for
        local doc = M.parse_kdl(new_owned)
        if not doc or #dup_in_file(doc) > 0 then plan.status = "invalid_request"; plan.errors = { { kind = "internal", message = "edit would produce an invalid file" } }; return plan end
        if #new_owned > M.MAX_WRITE then plan.status = "invalid_request"; plan.errors = { { kind = "too_large", message = "shortcuts file would be too large" } }; return plan end
        owned_changed = new_owned ~= (owned_text or "")
    end

    local include_change
    if not tree.owned_included then
        if request.ensure_include then
            local f = tree.beskar_file
            if not f or not state.beskar_text then
                plan.status = "needs_installer"
                plan.errors = { { kind = "needs_installer", message = "beskar.kdl is not part of your niri config; run ./beskar install or add  include \"" .. M.OWNED_NAME .. "\"  yourself" } }
                return plan
            end
            local rel = dirname(ctx.beskar) == dirname(ctx.owned) and M.OWNED_NAME or ctx.owned
            local text = state.beskar_text
            if text ~= "" and text:sub(-1) ~= "\n" then text = text .. "\n" end
            text = text .. "\n// Beskar shortcuts (managed by Settings; the file is optional)\ninclude optional=true " .. kdl_string(rel) .. "\n"
            if not M.parse_kdl(text) then plan.status = "needs_installer"; plan.errors = { { kind = "beskar_invalid", message = "beskar.kdl cannot be edited safely" } }; return plan end
            include_change = { path = ctx.beskar, text = text, expect = state.beskar_text, role = "include" }
        elseif #ops > 0 then
            plan.status = "include_required"
            plan.errors = { { kind = "include_required", message = "beskar-shortcuts.kdl is not included by your niri config yet" } }
            return plan
        end
    end
    -- the include goes in first: until it exists the owned file would be inert
    if owned_changed then plan.changes[#plan.changes + 1] = { path = ctx.owned, text = new_owned, expect = owned_text, role = "owned" } end
    if include_change then table.insert(plan.changes, 1, include_change) end
    if #plan.changes == 0 then plan.status = "unchanged" end
    return plan
end

-- ── transaction ────────────────────────────────────────────────────────────────────────────────────────────────
local function result(status, extra)
    extra = extra or {}
    extra.status = status
    extra.ok = status == "applied" or status == "applied_reload_failed" or status == "unchanged"
    return extra
end

local function undo(fs, done)
    local failed = {}
    for idx = #done, 1, -1 do
        local c = done[idx]
        local ok
        if c.expect == nil then ok = fs.remove(c.path, c.text) else ok = fs.write(c.path, c.expect, c.text) end
        if not ok then failed[#failed + 1] = c.path end
    end
    return failed
end

-- Load everything Settings needs: the tree, the rows, the conflicts and the state of the owned include.
function M.load(fs, ctx, opts)
    local tree = M.resolve(fs, ctx, opts)
    return {
        tree = tree, rows = M.rows(tree, opts), conflicts = tree.conflicts, issues = tree.issues, complete = tree.complete,
        owned = { path = ctx.owned, included = tree.owned_included, present = tree.owned_file ~= nil },
        can_install_include = (not tree.owned_included) and tree.beskar_file ~= nil,
    }
end

-- apply: request = { ops = { {op="set"|"remove", key, route, repeat?, allow_when_locked?} }, accept = { keys }, ensure_include = bool }
-- Order: resolve -> preflight validate -> plan -> backup+write -> validate the FULL config -> (rollback) -> reload.
-- Returns { ok, status, ... }. A non-ok status never leaves a changed file behind except "rollback_failed".
function M.apply(fs, ctx, request)
    request = request or {}
    local tree = M.resolve(fs, ctx)
    local owned_text = fs.read(ctx.owned)
    local beskar_text = fs.read(ctx.beskar)
    local plan = M.plan(tree, ctx, request, { owned_text = owned_text, beskar_text = beskar_text })
    local base = { conflicts = plan.conflicts, errors = plan.errors, issues = tree.issues, tree = tree }
    if plan.status ~= "ok" then
        if plan.status == "tree_incomplete" then
            base.errors = {}
            for _, i in ipairs(tree.issues) do if i.severity == "error" then base.errors[#base.errors + 1] = { kind = i.kind, message = i.message } end end
        end
        return result(plan.status, base)
    end
    local ok, message = fs.validate(ctx.config)
    if not ok then base.message = message; return result("config_invalid", base) end

    local done = {}
    for _, c in ipairs(plan.changes) do
        local wrote, why = fs.write(c.path, c.text, c.expect)
        if not wrote then
            local bad = undo(fs, done)
            base.message = "could not write " .. c.path .. " (" .. tostring(why) .. ")"
            base.stuck = bad
            return result(#bad > 0 and "rollback_failed" or "write_failed", base)
        end
        done[#done + 1] = c
    end

    local function roll_back(reason, msg)
        local bad = undo(fs, done)
        base.message = msg
        base.stuck = bad
        if #bad > 0 then
            base.backup = ctx.owned .. ".beskar-bak"
            return result("rollback_failed", base)
        end
        local ok2, m2 = fs.validate(ctx.config)
        base.after_rollback_valid = ok2
        return result(reason, base)
    end

    local valid, vmsg = fs.validate(ctx.config)
    if not valid then return roll_back("rolled_back", vmsg) end

    -- proof that the change is live: the new tree must be complete, include the owned file and hold every set key
    local after = M.resolve(fs, ctx)
    local proven = after.complete and after.owned_included
    if proven then
        local effective = {}
        for _, b in ipairs(after.effective) do effective[b.ident] = b end
        for _, op in ipairs(plan.ops) do
            local k = M.parse_key(op.key)
            local b = effective[k.ident]
            if op.op == "set" and not (b and b.kind == op.route.kind and b.id == op.route.id) then proven = false end
            if op.op == "remove" and b and b.owned then proven = false end
        end
    end
    if not proven then return roll_back("rolled_back", "the new configuration did not take effect as planned") end
    base.tree = after

    local reloaded, rmsg = fs.reload()
    if not reloaded then base.message = rmsg; return result("applied_reload_failed", base) end
    return result("applied", base)
end

-- ── adapter (shortcuts_adapter.py) ─────────────────────────────────────────────────────────────────────────────
-- runner(argv) -> out, code. In Settings the runner yields (see M.async); tests may pass a blocking one.
function M.adapter_fs(runner)
    local fs = {}
    function fs.read(path)
        local out, code = runner({ "read", path })
        if code == 0 then
            -- the adapter ends the text with "\n\30": without it the output was cut or changed on the way, and a
            -- compare-and-swap against it could never be trusted
            if type(out) == "string" and out:sub(-2) == "\n\30" then return out:sub(1, -3) end
            return nil, "unreadable"
        end
        return nil, code == 3 and "missing" or code == 5 and "too_large" or "unreadable"
    end
    function fs.real(path)
        local out, code = runner({ "real", path })
        if code == 0 and type(out) == "string" and out ~= "" then return (out:gsub("\n$", "")) end
        return nil
    end
    function fs.write(path, text, expect)
        local argv = { "write", path, text }
        if expect == nil then argv[#argv + 1] = "--absent" else argv[#argv + 1] = "--expect"; argv[#argv + 1] = expect end
        local _, code = runner(argv)
        if code == 0 then return true end
        return nil, code == 6 and "changed" or code == 7 and "refused" or code == 5 and "too_large" or "io"
    end
    function fs.remove(path, expect)
        local _, code = runner({ "remove", path, "--expect", expect or "" })
        if code == 0 then return true end
        return nil, code == 6 and "changed" or code == 7 and "refused" or "io"
    end
    function fs.validate(config)
        local out, code = runner({ "validate", config })
        return code == 0, out or ""
    end
    function fs.reload()
        local out, code = runner({ "reload" })
        return code == 0, out or ""
    end
    return fs
end

-- Run fn(fs) in a coroutine whose fs calls go through cfg.run (Settings' sandboxed `run`):
--   cfg = { run = run, adapter = "/abs/shell/shortcuts_adapter.py", python = "python3" }
-- Declare "python3" in the scene's permissions. done(result, err) fires once, from a run callback.
function M.async(cfg, fn, done)
    local co = coroutine.create(function()
        return fn(M.adapter_fs(function(argv) return coroutine.yield(argv) end))
    end)
    local finished = false
    local function step(...)
        if finished then return end
        local ok, a = coroutine.resume(co, ...)
        if not ok then finished = true; done(nil, tostring(a)); return end
        if coroutine.status(co) == "dead" then finished = true; done(a); return end
        local argv = { cfg.adapter }
        for _, v in ipairs(a) do argv[#argv + 1] = v end
        local replied = false
        cfg.run(cfg.python or "python3", argv, function(out, code)
            if replied then return end
            replied = true
            step(out, code)
        end)
    end
    step()
end

function M.load_async(cfg, ctx, done, opts)
    M.async(cfg, function(fs) return M.load(fs, ctx, opts) end, done)
end
function M.apply_async(cfg, ctx, request, done)
    M.async(cfg, function(fs) return M.apply(fs, ctx, request) end, done)
end

return M
