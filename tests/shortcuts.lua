-- Run from the repository root: lua tests/shortcuts.lua
--
-- Tests shell/shortcuts.luau (pure core) and shell/shortcuts_adapter.py (filesystem / niri effects).
-- Nothing here touches the live session: every file lives in a throw-away HOME, the niri that `apply` talks to is a
-- FAKE (BESKAR_NIRI), NIRI_SOCKET is cleared so no reload can reach the running compositor, and only `niri validate -c`
-- (a pure check of files in the temp HOME) is ever run with the real binary, in section 9.
--
-- Assumptions (explicit):
--   A1. niri applies `include` in place and the later definition of a key replaces the earlier (docs/CUSTOMIZATION_PLAN C5).
--   A2. The fake niri is a small validator (include following, brace balance, duplicate keys per file, a reject marker);
--       the real one is only used to prove generated files and the static route table are accepted (section 9).
package.path = "shell/?.luau;" .. package.path
local S = require("shortcuts")

local passed = 0
local function check(cond, msg)
    if not cond then error("FAIL: " .. msg, 2) end
    passed = passed + 1
end
local function eq(a, b, msg)
    if a ~= b then error(("FAIL: %s\n  got:      %s\n  expected: %s"):format(msg, tostring(a), tostring(b)), 2) end
    passed = passed + 1
end
local function has(s, part, msg) check(s ~= nil and s:find(part, 1, true) ~= nil, msg .. " (missing " .. part .. ")") end
local function section(name) print("-- " .. name) end

local function q(s) return "'" .. tostring(s):gsub("'", "'\\''") .. "'" end
local function sh(cmd)
    local p = assert(io.popen(cmd .. " 2>&1", "r"))
    local out = p:read("*a")
    local ok = p:close()
    return out, ok
end
local function slurp(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local t = f:read("*a")
    f:close()
    return t
end
local function spit(path, text)
    sh("mkdir -p " .. q(path:match("^(.*)/[^/]*$")))
    local f = assert(io.open(path, "wb"))
    f:write(text)
    f:close()
end

-- ═══ 1. KDL reader ═════════════════════════════════════════════════════════════════════════════════════════════
section("1. KDL reader")
do
    local src = [[
// line comment
/* block /* nested */ still a comment */
binds {
    Mod+T { spawn "a}b" "c{d"; }   // trailing comment with { brace
    /-Mod+Y { quit; }
    Mod+R { spawn r#"x"y"#; }
    Mod+U \
        repeat=false hotkey-overlay-title="Two words" { fullscreen-window; }
    Mod+I { spawn """
        one
        two
        """; }
}
/-include "ignored.kdl"
include optional=true "x.kdl"; other 1 2.5 #true null
(type)typed (u8)7 key=(u8)8 { child; }
]]
    local doc = assert(S.parse_kdl(src))
    local names = {}
    for _, n in ipairs(doc.nodes) do names[#names + 1] = n.name .. (n.disabled and "(off)" or "") end
    eq(table.concat(names, ","), "binds,include(off),include,other,typed", "top-level nodes")
    local binds = doc.nodes[1].children
    eq(#binds, 5, "five children")
    eq(binds[1].children[1].args[1], "a}b", "braces inside a string are data")
    eq(binds[1].children[1].args[2], "c{d", "second string")
    check(binds[2].disabled, "slashdash disables a node")
    eq(binds[3].children[1].args[1], 'x"y', "raw string")
    eq(binds[4].props["repeat"], false, "line continuation + boolean prop")
    eq(binds[4].props["hotkey-overlay-title"], "Two words", "string prop")
    eq(binds[5].children[1].args[1], "one\ntwo", "multi-line string is dedented")
    eq(doc.nodes[3].props.optional, true, "include optional")
    local other = doc.nodes[4]
    eq(other.args[1], 1, "number") eq(other.args[2], 2.5, "float") eq(other.args[3], true, "#true") eq(other.args[4], S.NULL, "null")
    eq(doc.nodes[5].args[1], 7, "typed arg") eq(doc.nodes[5].props.key, 8, "typed prop")
    eq(src:sub(binds[1].s, binds[1].e - 1), 'Mod+T { spawn "a}b" "c{d"; }', "node span covers the whole node")
    eq(doc.nodes[1].line, 3, "line numbers") eq(binds[3].line, 6, "line of a child")

    local bad = {
        { 'binds {\n  Mod+T { quit; }\n', "unterminated block" },
        { 'foo "abc\nbar', "newline in string" },
        { 'foo "abc', "unterminated string" },
        { '}\n', "unexpected" },
        { 'foo /* never closed', "unterminated comment" },
        { 'foo "\\q"', "bad escape" },
        { 'foo {} bar', "expected a newline" },
    }
    for _, case in ipairs(bad) do
        local d, e = S.parse_kdl(case[1])
        check(d == nil and e.line >= 1 and e.message:find(case[2], 1, true), "rejects: " .. case[2] .. " (" .. tostring(e and e.message) .. ")")
    end
    local d, e = S.parse_kdl(("a {"):rep(40) .. ("}"):rep(40))
    check(d == nil and e.message:find("deep"), "nesting is bounded")
    check(S.parse_kdl(("x"):rep(S.MAX_BYTES + 1)) == nil, "size is bounded")
    check(S.parse_kdl("a\0b") == nil, "NUL is refused")
end

-- ═══ 2. keys ═══════════════════════════════════════════════════════════════════════════════════════════════════
section("2. keys")
do
    local k = S.parse_key("Shift+Mod+q")
    eq(k.key, "Mod+Shift+q", "canonical order") eq(k.ident, "super+shift+q", "ident")
    eq(S.parse_key("Super+Shift+Q").ident, k.ident, "Mod and Super are one key for conflicts")
    check(S.parse_key("Super+Shift+Q").strict ~= S.parse_key("Mod+Shift+Q").strict, "but niri's duplicate check keeps them apart")
    eq(S.parse_key("Mod+t").ident, S.parse_key("Mod+T").ident, "case-insensitive key")
    eq(S.parse_key("XF86AudioMute").ident, "xf86audiomute", "bare key")
    eq(S.parse_key("Control+Win+1").key, "Super+Ctrl+1", "aliases fold")
    for _, bad in ipairs({ "", "Mod+", "+x", "Hyper+x", 'Mod+x" { quit; }', "Mod+x y", "Mod+Mod+x", "Mod+Super+x", ("a"):rep(60), "Mod+x\n", 5 }) do
        check(S.parse_key(bad) == nil, "refused key: " .. tostring(bad):sub(1, 20))
    end
    eq(S.pretty_key("Mod+Shift+XF86AudioMute"), "Super + Shift + Mute", "pretty")
    eq(S.pretty_key("Mod+Comma"), "Super + ,", "pretty punctuation")
end

-- ═══ 3. include tree (in memory) ═══════════════════════════════════════════════════════════════════════════════
section("3. include tree")
local function memfs(files, real)
    local fs = { reads = {} }
    function fs.read(p)
        fs.reads[#fs.reads + 1] = p
        local v = files[p]
        if v == nil then return nil, "missing" end
        if type(v) == "table" then return nil, v.err end
        return v
    end
    function fs.real(p) return real and real[p] or p end
    return fs
end
local function ctx_for(home) return S.context({ home = home, start_sh = "/opt/beskar/shell/start.sh" }) end

do
    local H = "/h"
    local N = H .. "/.config/niri"
    local files = {
        [N .. "/config.kdl"] = [[
binds { Mod+A { close-window; } }
include "sub/one.kdl"
include "/abs/two.kdl"
include "~/three.kdl"
include optional=true "none.kdl"
/-include "ignored.kdl"
// include "commented.kdl"
note "include \"quoted.kdl\" binds { Mod+Z { quit; } }"
// binds { Mod+Y { quit; } }
]],
        [N .. "/sub/one.kdl"] = 'include "../shared.kdl"\ninclude "deep/d.kdl"\nbinds { Mod+B { fullscreen-window; }; }\n',
        [N .. "/shared.kdl"] = 'binds {\n    Mod+S { center-column; }\n}\n',
        [N .. "/sub/deep/d.kdl"] = 'binds {\n    Mod+D { center-column; }\n}\n',
        ["/abs/two.kdl"] = 'binds {\n    Mod+Two { center-column; }\n}\n',
        [H .. "/three.kdl"] = 'binds {\n    Mod+Three { center-column; }\n}\n',
    }
    local tree = S.resolve(memfs(files), ctx_for(H))
    local order = {}
    for _, f in ipairs(tree.files) do order[#order + 1] = f.path:gsub("^" .. N, "N"):gsub("^" .. H, "H") end
    eq(table.concat(order, " "), "N/config.kdl N/sub/one.kdl N/shared.kdl N/sub/deep/d.kdl /abs/two.kdl H/three.kdl N/none.kdl",
        "relative, nested-relative, absolute and ~ includes in file order")
    local keys = {}
    for _, b in ipairs(tree.binds) do keys[#keys + 1] = b.key end
    eq(table.concat(keys, " "), "Mod+A Mod+S Mod+D Mod+B Mod+Two Mod+Three", "bindings in niri's processing order")
    check(tree.complete, "complete tree")
    eq(#tree.issues, 1, "only the optional-missing note") eq(tree.issues[1].kind, "optional_missing", "optional include absent is info")
    eq(tree.binds[2].path, N .. "/shared.kdl", "source path") eq(tree.binds[2].line, 2, "source line")
    check(not tree.owned_included, "owned file not included")

    -- missing, non-optional
    files[N .. "/shared.kdl"] = nil
    local t2 = S.resolve(memfs(files), ctx_for(H))
    check(not t2.complete and t2.issues[1].kind == "missing", "non-optional missing include makes the tree incomplete")
    files[N .. "/shared.kdl"] = 'binds { Mod+S { center-column; } }\n'

    -- cycles: a -> b -> a, self, and through a symlink
    local cyc = { [N .. "/config.kdl"] = 'include "a.kdl"\n', [N .. "/a.kdl"] = 'include "b.kdl"\n', [N .. "/b.kdl"] = 'include "a.kdl"\n' }
    local t3 = S.resolve(memfs(cyc), ctx_for(H))
    check(not t3.complete and t3.issues[1].kind == "cycle", "a -> b -> a is a cycle")
    local self = { [N .. "/config.kdl"] = 'include "config.kdl"\n' }
    check(S.resolve(memfs(self), ctx_for(H)).issues[1].kind == "cycle", "self include")
    local link = { [N .. "/config.kdl"] = 'include "a.kdl"\n', [N .. "/a.kdl"] = 'include "link.kdl"\n', [N .. "/link.kdl"] = 'include "a.kdl"\n' }
    local t4 = S.resolve(memfs(link, { [N .. "/link.kdl"] = N .. "/a.kdl" }), ctx_for(H))
    check(t4.issues[1] and t4.issues[1].kind == "cycle", "a symlink back to an ancestor is a cycle")
    -- the same file twice (not a cycle) is allowed
    local twice = { [N .. "/config.kdl"] = 'include "a.kdl"\ninclude "a.kdl"\n', [N .. "/a.kdl"] = 'binds { Mod+A { close-window; } }\n' }
    local t5 = S.resolve(memfs(twice), ctx_for(H))
    check(t5.complete and #t5.binds == 2 and #t5.conflicts == 1, "re-including a file is not a cycle (and shows as a conflict)")

    -- depth and file limits
    local deep = { [N .. "/config.kdl"] = 'include "f1.kdl"\n' }
    for n = 1, 12 do deep[N .. "/f" .. n .. ".kdl"] = 'include "f' .. (n + 1) .. '.kdl"\n' end
    local t6 = S.resolve(memfs(deep), ctx_for(H))
    check(not t6.complete and t6.issues[1].kind == "depth_limit", "depth is bounded")
    local wide = { [N .. "/config.kdl"] = ('include "a.kdl"\n'):rep(60), [N .. "/a.kdl"] = "\n" }
    local t7 = S.resolve(memfs(wide), ctx_for(H))
    check(not t7.complete and t7.issues[1].kind == "file_limit" and #t7.files == 48, "file count is bounded")
    local big = { [N .. "/config.kdl"] = 'include "a.kdl"\ninclude "a.kdl"\ninclude "a.kdl"\ninclude "a.kdl"\ninclude "a.kdl"\n',
        [N .. "/a.kdl"] = "// " .. ("x"):rep(S.MAX_BYTES - 10) .. "\n" }
    check(S.resolve(memfs(big), ctx_for(H)).issues[1].kind == "size_limit", "total bytes are bounded")

    -- read errors and bad KDL
    local errs = { [N .. "/config.kdl"] = 'include "a.kdl"\ninclude "b.kdl"\ninclude "c.kdl"\ninclude\n',
        [N .. "/a.kdl"] = { err = "unreadable" }, [N .. "/b.kdl"] = { err = "too_large" }, [N .. "/c.kdl"] = 'binds {\n' }
    local t8 = S.resolve(memfs(errs), ctx_for(H))
    local kinds = {}
    for _, i in ipairs(t8.issues) do kinds[#kinds + 1] = i.kind end
    eq(table.concat(kinds, ","), "unreadable,too_large,invalid_kdl,bad_include", "read errors are reported, not hidden")
    check(not t8.complete, "incomplete")
    eq(t8.issues[3].line, 2, "KDL error carries a line")
    local t9 = S.resolve(memfs({}), ctx_for(H))
    check(not t9.complete and t9.issues[1].kind == "missing", "no config at all")

    -- effective order and conflicts
    local ov = { [N .. "/config.kdl"] = 'binds {\n Mod+Q { close-window; }\n Mod+X { center-column; }\n}\ninclude "o.kdl"\n',
        [N .. "/o.kdl"] = 'binds {\n Super+q { fullscreen-window; }\n}\n' }
    local t10 = S.resolve(memfs(ov), ctx_for(H))
    eq(#t10.effective, 2, "later definition replaces the earlier") eq(t10.effective[2].id, "fullscreen-window", "winner")
    eq(t10.binds[1].shadowed_by, t10.binds[3], "shadowed_by")
    eq(#t10.conflicts, 1, "one conflict") eq(t10.conflicts[1].kind, "shadowed", "across files") eq(t10.conflicts[1].winner.path, N .. "/o.kdl", "winner path")
    local dup = S.resolve(memfs({ [N .. "/config.kdl"] = 'binds {\n Mod+Q { quit; }\n Mod+q { close-window; }\n}\n' }), ctx_for(H))
    eq(dup.conflicts[1].kind, "duplicate_in_file", "duplicates in one file are what niri rejects")

    -- sources: owned / beskar / user
    local own = { [N .. "/config.kdl"] = 'include "beskar.kdl"\ninclude optional=true "beskar-shortcuts.kdl"\nbinds { Mod+U { center-column; } }\n',
        [N .. "/beskar.kdl"] = 'binds { Mod+Space { spawn "/x/shell/start.sh" "spotlight"; } }\n',
        [N .. "/beskar-shortcuts.kdl"] = 'binds { Mod+O { close-window; } }\n' }
    local t11 = S.resolve(memfs(own), ctx_for(H))
    eq(t11.binds[1].source, "beskar", "beskar default") eq(t11.binds[2].source, "owned", "owned") eq(t11.binds[3].source, "user", "user")
    check(t11.owned_included and t11.beskar_file ~= nil, "owned + beskar found")
end

-- ═══ 4. classification, rows, search ═══════════════════════════════════════════════════════════════════════════
section("4. rows and search")
do
    local H, N = "/h", "/h/.config/niri"
    local files = { [N .. "/config.kdl"] = [[
binds {
    Mod+Space hotkey-overlay-title="Spotlight" { spawn "/x/shell/start.sh" "spotlight"; }
    Mod+Shift+Q { spawn "/x/shell/start.sh" "power-menu"; }
    Mod+Return { spawn "kitty"; }
    Mod+F { fullscreen-window; }
    Mod+Alt+E { spawn "dms" "ipc" "x"; }
    Mod+Left { focus-column-left; }
    Mod+Odd { frobnicate-everything; }
    XF86AudioMute allow-when-locked=true { spawn "/x/shell/start.sh" "mute"; }
    Mod+Nothing
}
]] }
    local tree = S.resolve(memfs(files), ctx_for(H))
    local by = {}
    for _, b in ipairs(tree.binds) do by[b.key] = b end
    eq(by["Mod+Space"].what, "Spotlight", "title wins") eq(by["Mod+Space"].kind, "shell", "shell route") check(by["Mod+Space"].route, "known route")
    eq(by["Mod+Shift+Q"].what, "Session Menu", "label from actions.luau cli_labels")
    eq(by["Mod+Return"].kind, "spawn", "plain spawn") eq(by["Mod+Return"].what, "Open kitty", "spawn label")
    eq(by["Mod+F"].what, "Fullscreen window", "niri action label") check(by["Mod+F"].route, "static niri route")
    check(by["Mod+Alt+E"].inert, "dms binds are inert")
    eq(by["Mod+Odd"].what, "Frobnicate everything", "unknown action is humanised") check(not by["Mod+Odd"].route, "and not editable")
    eq(by["XF86AudioMute"].what, "Mute", "mute label")
    check(by["Mod+Nothing"] == nil and tree.issues[1].kind == "no_action", "a bind without an action is reported")
    local rows = S.rows(tree)
    for _, r in ipairs(rows) do check(not r.keys:find("Alt + E", 1, true), "inert binds are not listed") end
    eq(#rows, 7, "rows") eq(rows[1].what, "Focus column left", "sorted by label")
    eq(#S.rows(tree, { include_inert = true }), 8, "inert on request")
    eq(#S.search(rows, "super spot"), 1, "search: super finds Mod, words are ANDed")
    eq(#S.search(rows, "kitty"), 1, "search by action text") eq(#S.search(rows, "xf86"), 1, "search by key")
    eq(#S.search(rows, "config.kdl"), 7, "search by file") eq(#S.search(rows, ""), #rows, "empty query lists all")
    eq(#S.search(rows, "zzz"), 0, "no match")
end

-- ═══ 5. planning and splicing (pure) ═══════════════════════════════════════════════════════════════════════════
section("5. plan")
local function planner(files, owned_text, beskar_text)
    local ctx = ctx_for("/h")
    if owned_text ~= nil and files[ctx.owned] == nil then
        local copy = {}
        for k, v in pairs(files) do copy[k] = v end
        copy[ctx.owned] = owned_text
        files = copy
    end
    local tree = S.resolve(memfs(files), ctx)
    return function(request) return S.plan(tree, ctx, request, { owned_text = owned_text, beskar_text = beskar_text }), tree end
end
do
    local N = "/h/.config/niri"
    local base = { [N .. "/config.kdl"] = 'binds { Mod+Q { close-window; } }\ninclude "beskar.kdl"\ninclude optional=true "beskar-shortcuts.kdl"\n',
        [N .. "/beskar.kdl"] = 'binds { Mod+Space { spawn "/x/shell/start.sh" "spotlight"; } }\n' }
    local plan = planner(base, nil, '// installer\nspawn-at-startup "/x/shell/start.sh"')
    local p = plan({ ops = { { op = "set", key = "shift+mod+K", route = { kind = "shell", id = "clipboard" } } } })
    eq(p.status, "ok", "new binding on a new file") eq(#p.changes, 1, "one change: the owned file")
    local text = p.changes[1].text
    has(text, "// Beskar shortcuts. Managed by Beskar Settings", "header")
    has(text, 'Mod+Shift+K hotkey-overlay-title="Clipboard History" { spawn "/opt/beskar/shell/start.sh" "clipboard"; }', "binding line (canonical key, static title)")
    eq(p.changes[1].expect, nil, "expects an absent file")
    check(S.parse_kdl(text) ~= nil, "the result parses")

    -- options
    local p2 = plan({ ops = { { op = "set", key = "Mod+Alt+M", route = { kind = "shell", id = "mute" }, ["repeat"] = false, allow_when_locked = true } } })
    has(p2.changes[1].text, 'Mod+Alt+M repeat=false allow-when-locked=true hotkey-overlay-title="Mute" { spawn "/opt/beskar/shell/start.sh" "mute"; }', "options")

    -- conflicts
    local c = plan({ ops = { { op = "set", key = "Super+q", route = { kind = "niri", id = "fullscreen-window" } } } })
    eq(c.status, "conflict", "conflict with the user's binding") eq(#c.changes, 0, "nothing planned")
    eq(c.conflicts[1].kind, "user_binding", "kind") eq(c.conflicts[1].wins, "owned", "owned file comes later so it would win")
    eq(c.conflicts[1].with.path, N .. "/config.kdl", "reported with the file") eq(c.conflicts[1].with.line, 1, "and the line")
    eq(c.conflicts[1].with.action, "close-window", "and the action")
    local acc = plan({ ops = { { op = "set", key = "Super+q", route = { kind = "niri", id = "fullscreen-window" } } }, accept = { "Mod+Q" } })
    eq(acc.status, "ok", "accepted by key (alias spelling does not matter)") eq(#acc.changes, 1, "planned after acceptance")
    local other = plan({ ops = { { op = "set", key = "Super+q", route = { kind = "niri", id = "fullscreen-window" } } }, accept = { "Mod+W" } })
    eq(other.status, "conflict", "accepting another key does not help")
    local d = plan({ ops = { { op = "set", key = "Mod+Space", route = { kind = "shell", id = "clipboard" } } } })
    eq(d.status, "conflict", "rebinding a Beskar default is explicit too") eq(d.conflicts[1].kind, "beskar_default", "kind")
    local same = plan({ ops = { { op = "set", key = "Mod+Space", route = { kind = "shell", id = "spotlight" } } } })
    eq(same.status, "ok", "an identical action loses nothing")  check(same.conflicts[1].identical, "marked identical")

    -- shadowed: a later user file wins and acceptance cannot fix it
    local late = { [N .. "/config.kdl"] = 'include "beskar-shortcuts.kdl"\nbinds {\n Mod+Q { close-window; }\n}\n', [N .. "/beskar-shortcuts.kdl"] = "// empty\n" }
    local sp = planner(late, "// empty\n", nil)({ ops = { { op = "set", key = "Mod+Q", route = { kind = "niri", id = "fullscreen-window" } } }, accept = { "Mod+Q" } })
    eq(sp.status, "shadowed", "a later binding of the same key wins: refuse") eq(sp.conflicts[1].wins, "user", "reported")

    -- not included
    local noinc = planner({ [N .. "/config.kdl"] = 'binds { Mod+Q { close-window; } }\n' }, nil, nil)
    eq(noinc({ ops = { { op = "set", key = "Mod+K", route = { kind = "niri", id = "close-window" } } } }).status, "include_required", "owned file is inert without an include")
    eq(noinc({ ops = { { op = "set", key = "Mod+K", route = { kind = "niri", id = "close-window" } } }, ensure_include = true }).status, "needs_installer",
        "no beskar.kdl in the tree: the user's own config is never edited")
    eq(noinc({ ops = {} }).status, "unchanged", "nothing asked")
    local noown = planner({ [N .. "/config.kdl"] = 'binds { Mod+Q { close-window; } }\ninclude "beskar.kdl"\n', [N .. "/beskar.kdl"] = base[N .. "/beskar.kdl"] },
        nil, '// installer\nspawn-at-startup "/x/shell/start.sh"')
    -- an override that is already in the owned file does not ask again
    local stand = planner({ [N .. "/config.kdl"] = base[N .. "/config.kdl"], [N .. "/beskar.kdl"] = base[N .. "/beskar.kdl"] },
        'binds {\n    Mod+Q { fullscreen-window; }\n}\n', nil)
    local sr = stand({ ops = { { op = "set", key = "Mod+Q", route = { kind = "niri", id = "center-column" } } } })
    eq(sr.status, "ok", "changing an override that was already accepted") check(sr.conflicts[1].standing, "marked standing")
    local ens = noown({ ops = { { op = "set", key = "Mod+K", route = { kind = "niri", id = "close-window" } } }, ensure_include = true })
    eq(ens.status, "ok", "ensure_include with beskar.kdl in the tree")
    eq(ens.changes[1].path, N .. "/beskar.kdl", "the include goes into beskar.kdl, first") eq(ens.changes[2].path, N .. "/beskar-shortcuts.kdl", "then the owned file")
    has(ens.changes[1].text, 'include optional=true "beskar-shortcuts.kdl"', "optional include, relative")
    has(ens.changes[1].text, '// installer\nspawn-at-startup "/x/shell/start.sh"\n\n// Beskar shortcuts', "beskar.kdl keeps its content")

    eq(plan({ ops = {}, ensure_include = true }).status, "unchanged", "included already (config.kdl names it): no include change")

    -- already included: ensure_include adds nothing
    local inc = planner({ [N .. "/config.kdl"] = 'include optional=true "beskar-shortcuts.kdl"\n' }, nil, nil)
    eq(inc({ ops = {}, ensure_include = true }).status, "unchanged", "already included")

    -- invalid requests: nothing reaches the file
    local bads = {
        { { op = "set", key = 'Mod+x" { quit; }', route = { kind = "niri", id = "close-window" } }, "bad_key" },
        { { op = "set", key = "Mod+x", route = { kind = "niri", id = 'close-window; quit' } }, "bad_route" },
        { { op = "set", key = "Mod+x", route = { kind = "niri", id = "quit" } }, "bad_route" },
        { { op = "set", key = "Mod+x", route = { kind = "niri", id = "spawn" } }, "bad_route" },
        { { op = "set", key = "Mod+x", route = { kind = "shell", id = "../../evil" } }, "bad_route" },
        { { op = "set", key = "Mod+x", route = { kind = "spawn", id = "rm" } }, "bad_route" },
        { { op = "set", key = "Mod+x", route = "close-window" }, "bad_route" },
        { { op = "set", key = "Mod+x", command = "rm -rf ~", route = { kind = "niri", id = "close-window" }, ["repeat"] = "no" }, "bad_option" },
        { { op = "set", key = "Mod+x", route = { kind = "niri", id = "close-window" }, allow_when_locked = true }, "bad_option" },
        { { op = "frob", key = "Mod+x" }, "bad_op" },
        { { op = "remove" }, "bad_key" },
    }
    for _, case in ipairs(bads) do
        local r = plan({ ops = { case[1] } })
        check(r.status == "invalid_request" and r.errors[1].kind == case[2], "refused: " .. case[2] .. " " .. tostring(r.status))
    end
    local dupop = plan({ ops = { { op = "remove", key = "Mod+x" }, { op = "set", key = "Super+X", route = { kind = "niri", id = "close-window" } } } })
    eq(dupop.errors[1].kind, "duplicate_op", "the same key twice in a request")
    -- a command field is never copied
    local cmd = plan({ ops = { { op = "set", key = "Mod+x", command = "rm -rf ~", route = { kind = "niri", id = "close-window" } } } })
    check(not cmd.changes[1].text:find("rm", 1, true), "unknown fields are ignored, never written")
    -- start.sh must be a plain absolute path
    local ctx = ctx_for("/h")
    ctx.start_sh = '/x/";quit;"/start.sh'
    local tree = S.resolve(memfs(base), ctx)
    eq(S.plan(tree, ctx, { ops = { { op = "set", key = "Mod+k", route = { kind = "shell", id = "clipboard" } } } }, {}).errors[1].kind, "bad_start_sh", "hostile start.sh")
    ctx.start_sh = nil
    eq(S.plan(tree, ctx, { ops = { { op = "set", key = "Mod+k", route = { kind = "niri", id = "close-window" } } } }, {}).status, "ok", "niri routes need no start.sh")

    -- editing an existing owned file keeps everything else byte for byte
    local owned = table.concat({
        "// my notes about shortcuts",
        "binds {",
        "    // keep me",
        "      Mod+A   { spawn \"/usr/bin/foot\"; }   // my terminal",
        "    Mod+B hotkey-overlay-title=\"Old\" { close-window; }",
        "    Mod+C { spawn \"/usr/bin/true\"; }",
        "    /-Mod+D { quit; }",
        "}",
        "window-rule { match app-id=\"x\"; }",
        "" }, "\n")
    local pl = planner({ [N .. "/config.kdl"] = 'include "beskar-shortcuts.kdl"\n' }, owned, nil)
    local e = pl({ ops = {
        { op = "set", key = "Mod+b", route = { kind = "niri", id = "fullscreen-window" } },
        { op = "remove", key = "Mod+C" },
        { op = "set", key = "Mod+N", route = { kind = "niri", id = "center-column" } },
        { op = "remove", key = "Mod+Nothing" },
    } })
    eq(e.status, "ok", "edit existing")
    eq(e.changes[1].text, table.concat({
        "// my notes about shortcuts",
        "binds {",
        "    // keep me",
        "      Mod+A   { spawn \"/usr/bin/foot\"; }   // my terminal",
        "    Mod+b hotkey-overlay-title=\"Fullscreen window\" { fullscreen-window; }",
        "    /-Mod+D { quit; }",
        "    Mod+N hotkey-overlay-title=\"Centre column\" { center-column; }",
        "}",
        "window-rule { match app-id=\"x\"; }",
        "" }, "\n"), "only the touched lines change (hand-written binds, comments, other nodes survive)")
    eq(e.changes[1].expect, owned, "compare-and-swap token is the text that was read")
    -- removing the last line of a one-liner block, and an empty file
    local one = planner({ [N .. "/config.kdl"] = 'include "beskar-shortcuts.kdl"\n' }, 'binds { Mod+A { quit; } }', nil)
    local o1 = one({ ops = { { op = "set", key = "Mod+B", route = { kind = "niri", id = "close-window" } } } })
    check(S.parse_kdl(o1.changes[1].text) and o1.changes[1].text:find("Mod%+A { quit; }"), "one-line block stays valid: " .. o1.changes[1].text)
    local o2 = one({ ops = { { op = "remove", key = "Mod+A" } } })
    check(S.parse_kdl(o2.changes[1].text), "removing from a one-line block stays valid")
    local emp = planner({ [N .. "/config.kdl"] = 'include "beskar-shortcuts.kdl"\n' }, "", nil)
    has(emp({ ops = { { op = "set", key = "Mod+B", route = { kind = "niri", id = "close-window" } } } }).changes[1].text, "binds {", "empty file gets a block")
    eq(emp({ ops = { { op = "remove", key = "Mod+B" } } }).status, "unchanged", "removing what is not there changes nothing")
    local nofile = planner({ [N .. "/config.kdl"] = 'include optional=true "beskar-shortcuts.kdl"\n' }, nil, nil)
    eq(nofile({ ops = { { op = "remove", key = "Mod+B" } } }).status, "unchanged", "remove on a missing file does not create one")
    -- a broken or duplicated owned file is never rewritten
    local broken = planner({ [N .. "/config.kdl"] = 'include "beskar-shortcuts.kdl"\n' }, 'binds {\n', nil)
    -- (the tree itself reports the invalid file first)
    eq(broken({ ops = { { op = "set", key = "Mod+B", route = { kind = "niri", id = "close-window" } } } }).status, "tree_incomplete", "invalid KDL in an included file blocks edits")
    local dupo = planner({ [N .. "/config.kdl"] = 'include "beskar-shortcuts.kdl"\n' }, 'binds {\n Mod+A { quit; }\n Mod+a { quit; }\n}\n', nil)
    eq(dupo({ ops = { { op = "set", key = "Mod+B", route = { kind = "niri", id = "close-window" } } } }).errors[1].kind, "owned_duplicate", "duplicate in the owned file")
    -- spelled differently inside the owned file: the set replaces that line instead of adding a niri-rejected duplicate
    local alias = planner({ [N .. "/config.kdl"] = 'include "beskar-shortcuts.kdl"\n' }, 'binds {\n Super+A { quit; }\n}\n', nil)
    local ar = alias({ ops = { { op = "set", key = "Mod+a", route = { kind = "niri", id = "close-window" } } } })
    eq(ar.status, "ok", "alias in the owned file") check(not ar.changes[1].text:find("Super+A", 1, true) and ar.changes[1].text:find("Mod+a", 1, true), "replaced, not duplicated")
end

-- ═══ real adapter + fake niri in a throw-away HOME ═════════════════════════════════════════════════════════════
local TMP = sh("mktemp -d"):gsub("%s+$", "")
local FAKE = TMP .. "/fake-niri"
local LOG = TMP .. "/niri.log"
spit(FAKE, [=[#!/usr/bin/env python3
import os, re, sys
log = os.environ.get("FAKE_NIRI_LOG")
def note(text):
    if log:
        with open(log, "a") as f: f.write(text + "\n")
args = sys.argv[1:]
home = os.environ.get("HOME", "")
def check(path, stack):
    real = os.path.realpath(path)
    if real in stack: print("recursive include " + path); return False
    try: text = open(path).read()
    except OSError as e: print("failed to read " + path); return False
    rej = os.environ.get("FAKE_NIRI_REJECT")
    if "!!BAD!!" in text or (rej and rej in text): print("error parsing " + path); return False
    if text.count("{") != text.count("}"): print("unbalanced braces in " + path); return False
    seen = set(); depth = 0; inb = False
    for line in text.splitlines():
        s = line.strip()
        if re.match(r"^binds\s*\{", s): inb = True; depth = 0
        if inb and depth == 1 and not s.startswith("//") and not s.startswith("binds"):
            m = re.match(r"^([A-Za-z0-9_+]+)", s)
            if m:
                k = m.group(1).lower()
                if k in seen: print("duplicate keybind " + k); return False
                seen.add(k)
        depth += line.count("{") - line.count("}")
        if inb and depth == 0 and not re.match(r"^binds\s*\{", s): inb = False
    for m in re.finditer(r'^include\s+(optional=true\s+)?"([^"]*)"', text, re.M):
        p = m.group(2)
        if p.startswith("~/"): p = home + p[1:]
        elif not p.startswith("/"): p = os.path.join(os.path.dirname(path), p)
        if not os.path.exists(p):
            if m.group(1): continue
            print("failed to read included config " + p); return False
        if not check(p, stack | {real}): return False
    return True
if args[:1] == ["validate"]:
    cfg = args[args.index("-c") + 1]
    note("validate " + cfg)
    if os.environ.get("FAKE_NIRI_SLEEP"):
        import time; time.sleep(float(os.environ["FAKE_NIRI_SLEEP"]))
    if check(cfg, set()): print("config is valid"); sys.exit(0)
    sys.exit(1)
if args[:3] == ["msg", "action", "load-config-file"]:
    note("reload")
    if os.environ.get("FAKE_NIRI_RELOAD_FAIL"): print("no niri session"); sys.exit(1)
    sys.exit(0)
sys.exit(2)
]=])
sh("chmod +x " .. q(FAKE))
local ADAPTER = "shell/shortcuts_adapter.py"
local live_before = sh("stat -c '%n %Y' ~/.config/niri/*.kdl")

local function runner_for(home, env)
    env = env or {}
    return function(argv)
        local parts = { "env", "HOME=" .. q(home), "BESKAR_NIRI=" .. q(FAKE), "FAKE_NIRI_LOG=" .. q(LOG), "NIRI_SOCKET=", "NIRI_CONFIG=" }
        for k, v in pairs(env) do parts[#parts + 1] = k .. "=" .. q(v) end
        parts[#parts + 1] = "python3 -I " .. q(ADAPTER)
        for _, a in ipairs(argv) do parts[#parts + 1] = q(a) end
        local p = assert(io.popen(table.concat(parts, " ") .. " 2>/dev/null", "r"))
        local out = p:read("*a")
        local ok, how, code = p:close()
        return out, code or (ok and 0 or 1)
    end
end

local home_n = 0
local function new_home(files)
    home_n = home_n + 1
    local H = TMP .. "/home" .. home_n
    local N = H .. "/.config/niri"
    spit(N .. "/config.kdl", files.config or [[
// the user's own config
input { keyboard { xkb { layout "us" } } }
binds {
    Mod+T { spawn "kitty"; }
    Mod+Q { close-window; }
}
include "beskar.kdl"
]])
    if files.beskar ~= false then
        spit(N .. "/beskar.kdl", files.beskar or [[
// Beskar shell (written by ./beskar install)
spawn-at-startup "/opt/beskar/shell/start.sh"
binds {
    Mod+Space hotkey-overlay-title="Spotlight" { spawn "/opt/beskar/shell/start.sh" "spotlight"; }
    Mod+V hotkey-overlay-title="Clipboard" { spawn "/opt/beskar/shell/start.sh" "clipboard"; }
}
]])
    end
    for name, text in pairs(files.extra or {}) do spit(N .. "/" .. name, text) end
    local ctx = S.context({ home = H, start_sh = "/opt/beskar/shell/start.sh" })
    return H, N, ctx
end
local function log_lines()
    local t = slurp(LOG) or ""
    local out = {}
    for l in t:gmatch("[^\n]+") do out[#out + 1] = l end
    return out
end
local function reset_log() spit(LOG, "") end
local function count(prefix)
    local n = 0
    for _, l in ipairs(log_lines()) do if l:sub(1, #prefix) == prefix then n = n + 1 end end
    return n
end
local SET_LOCK = { op = "set", key = "Mod+Alt+L", route = { kind = "shell", id = "lock" } }

-- ═══ 6. adapter ════════════════════════════════════════════════════════════════════════════════════════════════
section("6. adapter")
do
    local H, N = new_home({})
    local run = runner_for(H)
    local fs = S.adapter_fs(run)
    local text, why = fs.read(N .. "/config.kdl")
    check(text and text:find("the user's own config", 1, true), "read")
    local cut = S.adapter_fs(function(argv) local o, c = run(argv); return o:sub(1, -3), c end)
    eq(select(2, cut.read(N .. "/config.kdl")), "unreadable", "output that lost its end marker is never trusted")
    eq(select(2, fs.read(N .. "/nope.kdl")), "missing", "missing")
    eq(select(2, fs.read(N)), "unreadable", "a directory is unreadable")
    spit(N .. "/locked.kdl", "x"); sh("chmod 000 " .. q(N .. "/locked.kdl"))
    eq(select(2, fs.read(N .. "/locked.kdl")), "unreadable", "permission denied")
    spit(N .. "/binary.kdl", "a\0b")
    eq(select(2, fs.read(N .. "/binary.kdl")), "unreadable", "binary data")
    sh("head -c 1100000 /dev/zero | tr '\\0' 'a' > " .. q(N .. "/huge.kdl"))
    eq(select(2, fs.read(N .. "/huge.kdl")), "too_large", "over 1 MiB")
    spit(N .. "/latin.kdl", "caf\xe9"); eq(select(2, fs.read(N .. "/latin.kdl")), "unreadable", "not UTF-8")
    eq(fs.real(N .. "/../niri/config.kdl"), N .. "/config.kdl", "real path")
    sh("ln -s " .. q(N .. "/config.kdl") .. " " .. q(N .. "/linked.kdl"))
    eq(fs.real(N .. "/linked.kdl"), N .. "/config.kdl", "real follows symlinks")

    -- write: only Beskar-owned names, compare-and-swap, backup, atomic
    local owned = N .. "/beskar-shortcuts.kdl"
    check(fs.write(owned, "one\n", nil), "create")
    eq(slurp(owned), "one\n", "created")
    eq(select(2, fs.write(owned, "two\n", nil)), "changed", "--absent on an existing file is refused")
    eq(select(2, fs.write(owned, "two\n", "stale\n")), "changed", "stale expect is refused")
    eq(slurp(owned), "one\n", "refused writes change nothing")
    check(fs.write(owned, "two\n", "one\n"), "update with the right expect")
    eq(slurp(owned .. ".beskar-bak"), "one\n", "backup holds the previous text")
    eq(sh("ls " .. q(N) .. " | grep -c 'tmp'"):gsub("%s", ""), "0", "no temp file left behind")
    local before = slurp(N .. "/config.kdl")
    eq(select(2, fs.write(N .. "/config.kdl", "x", before)), "refused", "the user's config is never writable")
    eq(select(2, fs.write(N .. "/other.kdl", "x", nil)), "refused", "nor any other name")
    eq(select(2, fs.write("relative/beskar.kdl", "x", nil)), "refused", "nor relative paths")
    eq(slurp(N .. "/config.kdl"), before, "config untouched")
    eq(select(2, fs.write(owned, ("x"):rep(S.MAX_WRITE + 1), "two\n")), "too_large", "write size is bounded")
    -- symlinked owned file stays a symlink
    sh("rm " .. q(owned) .. "; mkdir -p " .. q(H .. "/dotfiles") .. "; printf 'dot\\n' > " .. q(H .. "/dotfiles/beskar-shortcuts.kdl") .. "; ln -s " .. q(H .. "/dotfiles/beskar-shortcuts.kdl") .. " " .. q(owned))
    check(fs.write(owned, "new\n", "dot\n"), "write through a symlink")
    eq(slurp(H .. "/dotfiles/beskar-shortcuts.kdl"), "new\n", "target updated")
    check(sh("test -L " .. q(owned) .. " && echo link"):find("link"), "still a symlink")
    -- remove
    spit(N .. "/beskar.kdl", "keep")
    eq(select(2, fs.remove(N .. "/beskar.kdl", "other")), "changed", "remove is compare-and-swap")
    check(fs.remove(N .. "/beskar.kdl", "keep"), "remove")
    eq(slurp(N .. "/beskar.kdl"), nil, "gone")
    eq(select(2, fs.remove(N .. "/config.kdl", before)), "refused", "config cannot be removed")
    -- niri calls
    spit(N .. "/beskar.kdl", "// restored\n")
    reset_log()
    local ok, msg = fs.validate(N .. "/config.kdl")
    check(ok, "fake niri validates: " .. msg)
    local okr = fs.reload()
    check(okr, "reload")
    eq(table.concat(log_lines(), "|"), "validate " .. N .. "/config.kdl|reload", "niri was asked to validate -c <config>, then reload")
    local bad = S.adapter_fs(runner_for(H, { FAKE_NIRI_RELOAD_FAIL = "1" }))
    check(not bad.reload(), "reload failure is reported")
    local missing = S.adapter_fs(function(argv)
        local f = runner_for(H, { BESKAR_NIRI = "/nonexistent/niri" })
        return f(argv)
    end)
    local okm, mm = missing.validate(N .. "/config.kdl")
    check(not okm, "validate fails when the binary is missing")
    sh("chmod 600 " .. q(N .. "/locked.kdl"))
end

-- ═══ 7. apply (transaction) ════════════════════════════════════════════════════════════════════════════════════
section("7. apply")
do
    -- happy path: the owned file is created, the include is installed first, then validate, then reload
    local H, N, ctx = new_home({})
    local fs = S.adapter_fs(runner_for(H))
    local cfg0, bes0 = slurp(N .. "/config.kdl"), slurp(N .. "/beskar.kdl")
    local loaded = S.load(fs, ctx)
    check(loaded.complete and not loaded.owned.included and loaded.can_install_include, "load: include can be installed")
    eq(#loaded.rows, 4, "load rows: user + beskar defaults")
    reset_log()
    local r = S.apply(fs, ctx, { ops = { SET_LOCK }, ensure_include = true })
    eq(r.status, "applied", "applied: " .. tostring(r.message))
    check(r.ok, "ok")
    eq(slurp(N .. "/config.kdl"), cfg0, "the user's config.kdl is byte-identical")
    has(slurp(N .. "/beskar.kdl"), 'include optional=true "beskar-shortcuts.kdl"', "include added to beskar.kdl")
    eq(slurp(N .. "/beskar.kdl.beskar-bak"), bes0, "beskar.kdl backed up")
    has(slurp(N .. "/beskar-shortcuts.kdl"), 'Mod+Alt+L hotkey-overlay-title="Lock Screen" { spawn "/opt/beskar/shell/start.sh" "lock"; }', "binding written")
    eq(count("validate"), 2, "validated before (preflight) and after the write")
    local lines = log_lines()
    eq(lines[#lines], "reload", "reload is last")
    local result_tree = S.resolve(fs, ctx)
    check(result_tree.owned_included and result_tree.effective[#result_tree.effective].key == "Mod+Alt+L", "the new binding is in the effective set, with its source file")
    eq(result_tree.effective[#result_tree.effective].path, N .. "/beskar-shortcuts.kdl", "source path of the new binding")

    -- idempotent
    reset_log()
    local again = S.apply(fs, ctx, { ops = { SET_LOCK }, ensure_include = true })
    eq(again.status, "unchanged", "same request again changes nothing") eq(count("reload"), 0, "and does not reload")

    -- a second edit: change, add, conflict, accept
    local cfg1 = slurp(N .. "/beskar-shortcuts.kdl")
    local c = S.apply(fs, ctx, { ops = { { op = "set", key = "Mod+Q", route = { kind = "niri", id = "fullscreen-window" } } } })
    eq(c.status, "conflict", "conflict is reported before anything is written")
    eq(c.conflicts[1].with.path, N .. "/config.kdl", "with the user's file") eq(slurp(N .. "/beskar-shortcuts.kdl"), cfg1, "no write")
    reset_log()
    check(count("reload") == 0, "no reload on conflict")
    local a = S.apply(fs, ctx, { ops = { { op = "set", key = "Mod+Q", route = { kind = "niri", id = "fullscreen-window" } } }, accept = { "Mod+Q" } })
    eq(a.status, "applied", "applied once accepted")
    eq(slurp(N .. "/config.kdl"), cfg0, "the user's own Mod+Q line is still in config.kdl, untouched")
    local t = S.resolve(fs, ctx)
    local mq
    for _, b in ipairs(t.effective) do if b.ident == "super+q" then mq = b end end
    eq(mq.source, "owned", "the owned binding takes effect") eq(#t.conflicts, 1, "and the shadowed user binding is listed as a conflict")
    eq(t.conflicts[1].entries[1].path, N .. "/config.kdl", "conflict knows both sides")
    -- remove restores the user's binding
    local rm = S.apply(fs, ctx, { ops = { { op = "remove", key = "Mod+Q" } } })
    eq(rm.status, "applied", "remove")
    has(slurp(N .. "/beskar-shortcuts.kdl"), "Mod+Alt+L", "other owned binding kept") check(not slurp(N .. "/beskar-shortcuts.kdl"):find("Mod%+Q"), "Mod+Q gone")
    eq(#S.resolve(fs, ctx).conflicts, 0, "no conflicts left")
end

do
    -- validation fails after the write: restored byte for byte, no reload
    local H, N, ctx = new_home({})
    local cfg0, bes0 = slurp(N .. "/config.kdl"), slurp(N .. "/beskar.kdl")
    local bad = S.adapter_fs(runner_for(H, { FAKE_NIRI_REJECT = "Lock Screen" }))
    reset_log()
    local r = S.apply(bad, ctx, { ops = { SET_LOCK }, ensure_include = true })
    eq(r.status, "rolled_back", "validation failure rolls back")
    has(r.message, "error parsing", "niri's message is passed on")
    eq(slurp(N .. "/config.kdl"), cfg0, "config.kdl untouched") eq(slurp(N .. "/beskar.kdl"), bes0, "beskar.kdl restored byte for byte")
    eq(slurp(N .. "/beskar-shortcuts.kdl"), nil, "the file that did not exist is gone again")
    eq(count("reload"), 0, "never reloaded")
    check(r.after_rollback_valid, "the restored config validates")
    check(not r.ok, "not ok")
    -- with an existing owned file, restored to the previous text
    spit(N .. "/beskar-shortcuts.kdl", 'binds {\n    Mod+A { close-window; }\n}\n')
    local prev = slurp(N .. "/beskar-shortcuts.kdl")
    local fsx = S.adapter_fs(runner_for(H))
    check(S.apply(fsx, ctx, { ops = {}, ensure_include = true }).ok, "include installed with the file already there")
    reset_log()
    local r2 = S.apply(bad, ctx, { ops = { SET_LOCK } })
    eq(r2.status, "rolled_back", "second rollback") eq(slurp(N .. "/beskar-shortcuts.kdl"), prev, "owned file restored to the previous text")
    eq(count("reload"), 0, "no reload")

    -- the config is already broken before we start: nothing is touched
    spit(N .. "/config.kdl", cfg0 .. "\n!!BAD!!\n")
    local broken = slurp(N .. "/config.kdl")
    local good = S.adapter_fs(runner_for(H))
    local r3 = S.apply(good, ctx, { ops = { SET_LOCK } })
    eq(r3.status, "config_invalid", "pre-existing invalid config: refuse") eq(slurp(N .. "/config.kdl"), broken, "untouched")
    eq(slurp(N .. "/beskar-shortcuts.kdl"), prev, "owned file untouched")

    -- the reload fails (no niri session): the valid change stays, the status says so
    spit(N .. "/config.kdl", cfg0)
    local noreload = S.adapter_fs(runner_for(H, { FAKE_NIRI_RELOAD_FAIL = "1" }))
    local r4 = S.apply(noreload, ctx, { ops = { SET_LOCK } })
    eq(r4.status, "applied_reload_failed", "reload failure") check(r4.ok, "the file is saved and valid") has(slurp(N .. "/beskar-shortcuts.kdl"), "Lock Screen", "saved")
end

do
    -- not included and no beskar.kdl: the user's config is never touched, a clear status explains
    local H, N, ctx = new_home({ beskar = false })
    local cfg0 = slurp(N .. "/config.kdl")
    -- config.kdl includes a missing beskar.kdl (non-optional): the tree is incomplete
    local fs = S.adapter_fs(runner_for(H))
    eq(S.apply(fs, ctx, { ops = { SET_LOCK }, ensure_include = true }).status, "tree_incomplete", "a missing non-optional include blocks edits")
    spit(N .. "/config.kdl", 'binds { Mod+T { spawn "kitty"; } }\n')
    cfg0 = slurp(N .. "/config.kdl")
    local r = S.apply(fs, ctx, { ops = { SET_LOCK }, ensure_include = true })
    eq(r.status, "needs_installer", "beskar.kdl absent: ask the installer") eq(slurp(N .. "/config.kdl"), cfg0, "config untouched") eq(slurp(N .. "/beskar-shortcuts.kdl"), nil, "nothing written")
    eq(S.apply(fs, ctx, { ops = { SET_LOCK } }).status, "include_required", "without ensure_include: include_required")

    -- beskar.kdl exists but nothing includes it: it is not proof of anything
    spit(N .. "/beskar.kdl", "// orphan\n")
    eq(S.apply(fs, ctx, { ops = { SET_LOCK }, ensure_include = true }).status, "needs_installer", "beskar.kdl outside the include tree is not edited")
    eq(slurp(N .. "/beskar.kdl"), "// orphan\n", "orphan untouched")
end

do
    -- incomplete trees block edits (unreadable file, bad KDL, cycle)
    local cases = {
        { 'include "bad.kdl"\ninclude "beskar.kdl"\n', { ["bad.kdl"] = "binds {\n" }, "invalid_kdl" },
        { 'include "a.kdl"\ninclude "beskar.kdl"\n', { ["a.kdl"] = 'include "a.kdl"\n' }, "cycle" },
        { 'include "dir.kdl"\ninclude "beskar.kdl"\n', {}, "unreadable" },
    }
    for _, case in ipairs(cases) do
        local H, N, ctx = new_home({ config = case[1], extra = case[2] })
        if case[3] == "unreadable" then sh("mkdir " .. q(N .. "/dir.kdl")) end
        local fs = S.adapter_fs(runner_for(H))
        local cfg0 = slurp(N .. "/config.kdl")
        reset_log()
        local r = S.apply(fs, ctx, { ops = { SET_LOCK }, ensure_include = true })
        eq(r.status, "tree_incomplete", "blocked by " .. case[3])
        eq(r.errors[1].kind, case[3], "reported as " .. case[3])
        eq(slurp(N .. "/config.kdl"), cfg0, "nothing changed") eq(count("validate") + count("reload"), 0, "no niri calls")
        local loaded = S.load(fs, ctx)
        check(not loaded.complete and #loaded.issues >= 1, "load reports the same problem")
    end
end

do
    -- another writer changes the owned file between our read and our write
    local H, N, ctx = new_home({ extra = { ["beskar-shortcuts.kdl"] = 'binds {\n    Mod+A { close-window; }\n}\n' } })
    local real = S.adapter_fs(runner_for(H))
    check(S.apply(real, ctx, { ops = {}, ensure_include = true }).ok, "include installed")
    local racing = setmetatable({}, { __index = real })
    local first = true
    function racing.write(path, text, expect)
        if first then first = false; spit(N .. "/beskar-shortcuts.kdl", "binds {\n    Mod+Z { quit; }\n}\n") end
        return real.write(path, text, expect)
    end
    local r = S.apply(racing, ctx, { ops = { SET_LOCK } })
    eq(r.status, "write_failed", "a concurrent edit is detected, never overwritten")
    eq(slurp(N .. "/beskar-shortcuts.kdl"), "binds {\n    Mod+Z { quit; }\n}\n", "the other writer's text is intact")
    has(r.message, "changed", "message says why")
end

do
    -- rollback itself fails: reported loudly with the backup location
    local H, N, ctx = new_home({ extra = { ["beskar-shortcuts.kdl"] = 'binds {\n    Mod+A { close-window; }\n}\n' } })
    local real = S.adapter_fs(runner_for(H))
    check(S.apply(real, ctx, { ops = {}, ensure_include = true }).ok, "include installed")
    local flaky = setmetatable({}, { __index = S.adapter_fs(runner_for(H, { FAKE_NIRI_REJECT = "Lock Screen" })) })
    local writes = 0
    local base = S.adapter_fs(runner_for(H, { FAKE_NIRI_REJECT = "Lock Screen" }))
    function flaky.write(path, text, expect)
        writes = writes + 1
        if writes >= 2 then return nil, "io" end
        return base.write(path, text, expect)
    end
    local before = slurp(N .. "/beskar-shortcuts.kdl")
    local r = S.apply(flaky, ctx, { ops = { SET_LOCK } })
    eq(r.status, "rollback_failed", "failed rollback is its own status") eq(r.stuck[1], N .. "/beskar-shortcuts.kdl", "names the stuck file")
    eq(slurp(N .. "/beskar-shortcuts.kdl.beskar-bak"), before, "and the backup holds the previous text")
end

do
    -- a user's hand-written owned-file content and a second owned file edit survive
    local H, N, ctx = new_home({ extra = { ["beskar-shortcuts.kdl"] = '// mine\nbinds {\n    Mod+Home { spawn "/usr/bin/foot"; }  // my terminal\n}\n' } })
    local fs = S.adapter_fs(runner_for(H))
    local r = S.apply(fs, ctx, { ops = { SET_LOCK }, ensure_include = true })
    eq(r.status, "applied", "edit with an existing owned file")
    local text = slurp(N .. "/beskar-shortcuts.kdl")
    has(text, '// mine\nbinds {\n    Mod+Home { spawn "/usr/bin/foot"; }  // my terminal\n', "the user's own binding and comments are preserved")
    local t = S.resolve(fs, ctx)
    local found
    for _, b in ipairs(t.effective) do if b.written == "Mod+Home" then found = b end end
    check(found and found.source == "owned" and found.kind == "spawn" and not found.route, "listed, but not an editable route")
end

-- ═══ 8. async driver ═══════════════════════════════════════════════════════════════════════════════════════════
section("8. async driver")
do
    local H, N, ctx = new_home({})
    local queue, calls = {}, {}
    local run_env = runner_for(H)
    local cfg = {
        adapter = "ADAPTER", python = "python3",
        run = function(cmd, args, cb)
            calls[#calls + 1] = cmd .. " " .. args[2]
            queue[#queue + 1] = function()
                local argv = {}
                for i = 2, #args do argv[#argv + 1] = args[i] end
                local out, code = run_env(argv)
                cb(out, code)
                cb("again", 99) -- a second callback must be ignored
            end
        end,
    }
    local got, err
    S.apply_async(cfg, ctx, { ops = { SET_LOCK }, ensure_include = true }, function(r, e) got, err = r, e end)
    local steps = 0
    while #queue > 0 do
        check(got == nil, "result is not delivered before the last step")
        local job = table.remove(queue, 1)
        job()
        steps = steps + 1
        check(steps < 200, "bounded number of adapter calls")
    end
    check(got and got.status == "applied" and err == nil, "async apply finished: " .. tostring(got and got.status or err))
    check(calls[1]:find("^python3 real"), "first call goes through the adapter by argv, not a shell")
    has(slurp(N .. "/beskar-shortcuts.kdl"), "Lock Screen", "written through the async path")

    local loaded
    S.load_async(cfg, ctx, function(r) loaded = r end)
    while #queue > 0 do table.remove(queue, 1)() end
    check(loaded and loaded.complete and loaded.owned.included, "async load")

    -- synchronous callbacks work too
    local sync_cfg = { adapter = "A", run = function(cmd, args, cb)
        local argv = {}
        for i = 2, #args do argv[#argv + 1] = args[i] end
        cb(run_env(argv))
    end }
    local viasync
    S.load_async(sync_cfg, ctx, function(r) viasync = r end)
    check(viasync and #viasync.rows >= 5, "async load with synchronous callbacks")

    -- an error inside the work is delivered, not thrown
    local e2
    S.async(cfg, function() error("boom") end, function(r, e) e2 = e end)
    has(e2, "boom", "errors reach done()")
end

-- ═══ 9. the real niri agrees ═══════════════════════════════════════════════════════════════════════════════════
section("9. real niri (validate only)")
do
    local exists = sh("command -v niri"):find("niri", 1, true)
    if not exists then
        print("   (niri not installed: skipped)")
    else
        local H, N, ctx = new_home({ config = 'include "beskar.kdl"\ninclude optional=true "beskar-shortcuts.kdl"\n', beskar = 'binds {\n    Mod+Space { close-window; }\n}\n' })
        local real_env = function(argv)
            local parts = { "env", "HOME=" .. q(H), "BESKAR_NIRI=niri", "NIRI_SOCKET=", "python3 -I " .. q(ADAPTER) }
            for _, a in ipairs(argv) do parts[#parts + 1] = q(a) end
            local p = assert(io.popen(table.concat(parts, " ") .. " 2>/dev/null", "r"))
            local out = p:read("*a")
            local ok, _, code = p:close()
            return out, code or (ok and 0 or 1)
        end
        local fs = S.adapter_fs(real_env)
        -- every static route, every option, written by our own renderer, accepted by niri
        local ops, n = {}, 0
        local letters = "abcdefghijklmnopqrstuvwxyz"
        for _, r in ipairs(S.routes()) do
            n = n + 1
            local letter = letters:sub((n - 1) % 26 + 1, (n - 1) % 26 + 1)
            ops[#ops + 1] = { op = "set", key = (n > 26 and "Mod+Ctrl+Shift+" or "Mod+Ctrl+Alt+") .. letter,
                route = { kind = r.kind, id = r.id }, ["repeat"] = n % 2 == 0 and false or nil, allow_when_locked = (n % 3 == 0 and r.kind == "shell") and true or nil }
        end
        local plan = S.plan(S.resolve(fs, ctx), ctx, { ops = ops }, { owned_text = nil })
        eq(plan.status, "ok", "plan for every route")
        spit(N .. "/beskar-shortcuts.kdl", plan.changes[1].text)
        local ok, msg = fs.validate(N .. "/config.kdl")
        check(ok, "niri accepts every static route as written: " .. msg)
        check(select(1, S.parse_kdl(plan.changes[1].text)) ~= nil, "and our reader parses it")
        local back = S.resolve(fs, ctx)
        eq(#back.effective - 1, #ops, "round trip: every binding reads back (plus the beskar default)")
        -- niri rejects a key repeated in one file; our reader sees the same
        spit(N .. "/beskar-shortcuts.kdl", 'binds {\n    Mod+T { close-window; }\n    Mod+t { close-window; }\n}\n')
        check(not (fs.validate(N .. "/config.kdl")), "niri rejects duplicate keys in one file")
        eq(S.resolve(fs, ctx).conflicts[1].kind, "duplicate_in_file", "and the resolver reports the same")
        -- shadowing across files is allowed by niri (the later one wins)
        spit(N .. "/beskar-shortcuts.kdl", 'binds {\n    Mod+Space { fullscreen-window; }\n}\n')
        check(fs.validate(N .. "/config.kdl"), "niri accepts a later file redefining a key")
        -- what niri says about includes matches the resolver
        spit(N .. "/config.kdl", 'include "beskar.kdl"\ninclude "~/home-rel.kdl"\n')
        spit(H .. "/home-rel.kdl", 'binds {\n    Mod+H { close-window; }\n}\n')
        check(fs.validate(N .. "/config.kdl"), "niri expands ~/")
        local t = S.resolve(fs, ctx)
        local seen
        for _, b in ipairs(t.binds) do if b.key == "Mod+H" then seen = b end end
        check(seen and seen.path == H .. "/home-rel.kdl", "and so does the resolver")
        spit(N .. "/config.kdl", 'include "beskar.kdl"\ninclude "missing.kdl"\n')
        check(not (fs.validate(N .. "/config.kdl")) and not S.resolve(fs, ctx).complete, "missing non-optional include: both reject it")
    end
end

-- ═══ 10. static tables ═════════════════════════════════════════════════════════════════════════════════════════
section("10. static routes")
do
    local start = slurp("shell/start.sh")
    for _, r in ipairs(S.SHELL_ROUTES) do
        local id = r.id:gsub("%-", "%%-")
        check(start:find("\n    " .. id .. "[%)|]") or start:find("|" .. id .. "[%)|]"), "start.sh handles `" .. r.id .. "`")
    end
    local seen = {}
    for _, r in ipairs(S.routes()) do
        check(not seen[r.kind .. r.id], "unique route " .. r.id)
        seen[r.kind .. r.id] = true
        check(r.label ~= "" and r.id:match("^[a-z0-9%-]+$"), "route data is plain: " .. r.id)
    end
    for _, forbidden in ipairs({ "quit", "spawn", "spawn-sh", "do-screen-transition" }) do
        check(not seen["niri" .. forbidden], forbidden .. " is not an editable route")
    end
    local actions = require("actions")
    local labels = {}
    for _, r in ipairs(S.routes({ actions = actions })) do labels[r.id] = r.label end
    eq(labels["control-center"], actions.cli_labels["control-center"], "labels follow actions.luau")
end

-- ═══ 11. the live session was never touched ════════════════════════════════════════════════════════════════════
section("11. live config")
do
    eq(sh("stat -c '%n %Y' ~/.config/niri/*.kdl"), live_before, "the live niri config files are unchanged")
    check(not (slurp(os.getenv("HOME") .. "/.config/niri/beskar-shortcuts.kdl")), "no live owned file was created")
end

sh("chmod -R u+rwx " .. q(TMP) .. "; rm -rf " .. q(TMP))
print(("shortcuts: %d checks passed"):format(passed))
