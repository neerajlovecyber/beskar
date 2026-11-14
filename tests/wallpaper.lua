-- Run: lua tests/wallpaper.lua   (the script checks need ImageMagick; without it they are skipped)
-- Optional: WALLPAPER_TEST_SH=dash lua tests/wallpaper.lua  (which `sh` runs the script)
package.path = "shell/?.luau;" .. package.path
local S = require("wallpaper_store")
local passed = 0
local function check(v, why) assert(v, why); passed = passed + 1 end
local function eq(a, b, why) assert(a == b, (why or "") .. " expected " .. tostring(b) .. " got " .. tostring(a)); passed = passed + 1 end

-- ── paths ────────────────────────────────────────────────────────────
check(S.valid_path("/home/u/Pictures/a.jpg"), "plain jpg")
check(S.valid_path("/x/A.JPEG"), "upper-case extension")
check(S.valid_path("/x/a b 'q' $HOME [1].png"), "spaces, quotes, brackets are legal")
check(S.valid_path("/x/ünï.webp"), "unicode")
for _, bad in ipairs({ "", "rel/a.jpg", "a.jpg", "/x/a.gif", "/x/a.svg", "/x/a", "/x/a.jpg\n/y", "/x/\ta.jpg",
    "/x/../a.jpg", "/x/..", "/x/a.jpg?3", "data:image/png;base64,AAAA", "firefox" }) do
    check(not S.valid_path(bad), "rejects " .. bad:gsub("%c", "?"))
end
check(not S.valid_path("/" .. string.rep("a", 5000) .. ".jpg"), "too long")
check(not S.valid_path(nil) and not S.valid_path(5), "non strings")
local _, code = S.valid_path("/x/a.gif"); eq(code, "unsupported", "gif code")
eq(S.clean_path("  /x/a.jpg \r\n"), "/x/a.jpg", "clean path")
eq(S.clean_path(nil), "", "clean nil")
eq(S.pretty("/x/my_wall-paper.jpg"), "my wall paper", "pretty")

-- ── transition ───────────────────────────────────────────────────────
eq(S.clamp_fx(2), 2); eq(S.clamp_fx(1), 1); eq(S.clamp_fx(0), 0)
eq(S.clamp_fx(3), 0); eq(S.clamp_fx(-1), 0); eq(S.clamp_fx(1.5), 0); eq(S.clamp_fx(nil), 0); eq(S.clamp_fx("2"), 2)
eq(S.parse_fx('{"a": 1, "wallpaper_fx": 2, "b": 3}'), 2, "parse fx")
eq(S.parse_fx('"wallpaper_fx":1'), 1, "parse fx tight")
eq(S.parse_fx('{"wallpaper_fx": 7}'), nil, "fx out of range ignored")
eq(S.parse_fx('{"wallpaper_fx": -1}'), nil, "negative fx ignored")
eq(S.parse_fx(""), nil, "no prefs")
eq(S.parse_fx(nil), nil, "nil prefs")

-- ── parsing the script's answers ─────────────────────────────────────
local r = S.parse_result("ok\t/x/a.jpg\t1920x1080\n")
check(r.ok and r.path == "/x/a.jpg" and r.size == "1920x1080" and r.source == nil, "parse ok")
r = S.parse_result("ok\t/x/a.jpg\t?\tprevious\n"); check(r.ok and r.size == "?" and r.source == "previous", "parse boot")
r = S.parse_result("err\tmissing\tGone\n"); check(not r.ok and r.code == "missing" and r.message == "Gone", "parse err")
r = S.parse_result(""); check(not r.ok and r.code == "unknown", "parse empty")
r = S.parse_result(nil); check(not r.ok and r.code == "unknown", "parse nil")
r = S.parse_result("garbage"); check(not r.ok and r.code == "unknown", "parse garbage")
local m = S.parse_status("ok\t/a.jpg\nmissing\t/b.jpg\n\nunsupported\t/c.png\n")
check(m["/a.jpg"] == "ok" and m["/b.jpg"] == "missing" and m["/c.png"] == "unsupported", "parse status")

-- ── favourites ───────────────────────────────────────────────────────
local f, st = S.fav_add({}, "/a/1.jpg"); eq(st, "added"); eq(#f, 1)
f, st = S.fav_add(f, "/a/2.png"); eq(f[1], "/a/2.png", "newest first")
f, st = S.fav_add(f, "/a/1.jpg"); eq(st, "exists"); eq(#f, 2, "no duplicate")
f, st = S.fav_add(f, "/a/bad.gif"); eq(st, "invalid"); eq(#f, 2)
f, st = S.fav_toggle(f, "/a/1.jpg"); eq(st, "removed"); eq(#f, 1)
f, st = S.fav_toggle(f, "/a/1.jpg"); eq(st, "added"); eq(#f, 2)
f, st = S.fav_remove(f, "/nope.jpg"); eq(st, "missing"); eq(#f, 2)
f, st = S.fav_remove(f, "/a/1.jpg"); eq(st, "removed"); eq(#f, 1)
local full = {}
for i = 1, S.MAX_FAVOURITES do full[i] = "/w/" .. i .. ".jpg" end
local g; g, st = S.fav_add(full, "/w/extra.jpg"); eq(st, "full"); eq(#g, S.MAX_FAVOURITES, "bounded, no eviction"); eq(g[1], "/w/1.jpg")
local big = {}
for i = 1, 200 do big[i] = "/w/" .. i .. ".jpg" end
eq(#S.fav_normalize(big), S.MAX_FAVOURITES, "a long file is cut")
local dirty = S.fav_decode({ favourites = { "/a/1.jpg", "/a/1.jpg", "rel.jpg", 5, { path = "/a/2.png" }, "/a/x.gif", "/a/n\n.jpg" } })
eq(#dirty, 2, "decode drops duplicates and invalid"); eq(dirty[2], "/a/2.png")
eq(#S.fav_decode({ "/a/1.jpg", "/a/2.jpg" }), 2, "plain array accepted")
eq(#S.fav_decode(nil), 0); eq(#S.fav_decode("x"), 0); eq(#S.fav_decode({ favourites = "x" }), 0, "garbage decodes to empty")
local enc = S.fav_encode({ "/a/1.jpg", "bad" }); check(enc.version == 1 and #enc.favourites == 1, "encode")
local rows = S.fav_rows({ "/a/1.jpg", "/a/2.png" }, { ["/a/1.jpg"] = "ok", ["/a/2.png"] = "missing" })
check(rows[1].available and not rows[2].available and rows[2].state == "missing" and rows[1].name == "1", "rows")

-- ── the script (needs a shell and ImageMagick) ───────────────────────
local function sh(cmd)
    local p = assert(io.popen(cmd .. " 2>&1"))
    local out = p:read("a"); p:close()
    return out
end
if sh("command -v magick"):match("^%s*$") then
    print(("wallpaper: %d checks passed, script tests skipped (no ImageMagick)"):format(passed))
    os.exit(0)
end
local SHELL = os.getenv("WALLPAPER_TEST_SH") or "sh"
local root = sh("mktemp -d"):gsub("%s+$", "")
check(root:match("^/"), "temp dir")
local home = root .. "/home"
local pics = root .. "/pics dir 'q' $x [1]"
local function q(s) return "'" .. tostring(s):gsub("'", "'\\''") .. "'" end
sh(("mkdir -p %s %s %s"):format(q(home .. "/.config/beskar"), q(pics), q(home .. "/.local/share/beskar/wallpapers")))
-- a `run` like the sandbox's: sh script with positional arguments, HOME replaced
local function runner(cmd, args, cb)
    local parts = { "HOME=" .. q(home), SHELL == "sh" and "sh" or SHELL }
    assert(cmd == "sh", "only sh is allowed")
    for _, a in ipairs(args) do parts[#parts + 1] = q(a) end
    local p = assert(io.popen(table.concat(parts, " ") .. " 2>/dev/null"))
    local out = p:read("a"); p:close()
    cb(out)
end
local function call(fn, ...)           -- fn(runner, args…, cb)
    local args, res = { ... }, nil
    args[#args + 1] = function(x) res = x end
    fn(runner, table.unpack(args))
    return res
end
local function read(path) local fh = io.open(path); if not fh then return nil end local t = fh:read("a"); fh:close(); return t end
local function make(name, args) sh(("magick %s %s"):format(args, q(pics .. "/" .. name))); return pics .. "/" .. name end

local jpg = make("a.jpg", "-size 300x200 plasma:fractal")
local png = make("b b.PNG", "-size 32x32 xc:green")
local webp = make("c.webp", "-size 40x30 xc:blue")
local weird = make("it's [x] $HOME `id`.jpg", "-size 8x8 xc:red")
local dashdir = pics .. "/-rf"
sh("mkdir -p " .. q(dashdir)); sh(("magick -size 8x8 xc:red %s"):format(q(dashdir .. "/-n.png")))
local wide = make("wide.png", "-size 17000x1 xc:red")
local trunc = pics .. "/trunc.jpg"
sh(("head -c 12000 %s > %s"):format(q(jpg), q(trunc)))
local truncpng = make("tp.png", "-size 300x200 plasma:fractal"); sh(("head -c 20000 %s > %s.cut && mv %s.cut %s"):format(q(truncpng), q(truncpng), q(truncpng), q(truncpng)))
local mism = pics .. "/actually-png.jpg"; sh(("cp %s %s"):format(q(png), q(mism)))
local notimg = pics .. "/text.png"; sh(("printf 'hello' > %s"):format(q(notimg)))
local empty = pics .. "/empty.jpg"; sh(("printf '' > %s"):format(q(empty)))
local gif = make("d.gif", "-size 8x8 xc:red")
local svg = pics .. "/e.svg"; sh(("printf '<svg/>' > %s"):format(q(svg)))
local anim = pics .. "/anim.webp"
sh(("magick -size 8x8 xc:red -size 8x8 xc:blue -loop 0 -delay 10 %s"):format(q(anim)))
local dirpic = pics .. "/folder.jpg"; sh("mkdir -p " .. q(dirpic))
local noread = pics .. "/noread.jpg"; sh(("cp %s %s && chmod 000 %s"):format(q(jpg), q(noread), q(noread)))
local cannot_read = sh(("test -r %s && echo yes"):format(q(noread))):match("yes") == nil -- root can read anything

local function code_of(path) local x = call(S.check, path); assert(not x.ok, path .. " should fail"); return x.code end
-- good ones
for _, p in ipairs({ jpg, png, webp, weird, dashdir .. "/-n.png" }) do
    local x = call(S.check, p); check(x.ok and x.path == p and x.size:match("^%d+x%d+$"), "good picture " .. p)
end
eq(call(S.check, jpg).size, "300x200", "size reported")
-- bad ones
eq(code_of(pics .. "/nope.jpg"), "missing")
eq(code_of(dirpic), "not_file", "directory named .jpg")
eq(code_of(empty), "corrupt", "empty file")
eq(code_of(notimg), "unsupported", "text named .png")
eq(code_of(mism), "unsupported", "png content with .jpg name")
eq(code_of(trunc), "corrupt", "truncated jpeg")
eq(code_of(truncpng), "corrupt", "truncated png")
eq(code_of(wide), "too_big", "17000 px wide")
eq(code_of(anim), "unsupported", "animated webp")
eq(code_of(gif), "unsupported", "gif")
eq(code_of(svg), "unsupported", "svg")
eq(code_of("relative.jpg"), "bad_path"); eq(code_of(""), "bad_path"); eq(code_of(jpg .. "\n" .. png), "bad_path")
if cannot_read then eq(code_of(noread), "unreadable", "unreadable file") end
-- the script itself also rejects what Lua would (called by something else)
local direct = S.parse_result(sh(("HOME=%s %s -c %s x check %s"):format(q(home), SHELL, q(S.SCRIPT), q("rel.jpg"))))
eq(direct.code, "bad_path", "script alone rejects relative")
direct = S.parse_result(sh(("HOME=%s %s -c %s x check %s"):format(q(home), SHELL, q(S.SCRIPT), q("/x/a\tb.jpg"))))
eq(direct.code, "bad_path", "script alone rejects control characters")
direct = S.parse_result(sh(("HOME=%s %s -c %s x check"):format(q(home), SHELL, q(S.SCRIPT))))
eq(direct.code, "bad_path", "script alone: no argument")
direct = S.parse_result(sh(("HOME=%s %s -c %s x frobnicate"):format(q(home), SHELL, q(S.SCRIPT))))
eq(direct.code, "unknown", "unknown mode")

-- check writes nothing
eq(read(home .. "/.config/beskar/wallpaper"), nil, "check does not write")

-- commit: validates, atomic, previous kept; failure changes nothing
local cur = home .. "/.config/beskar/wallpaper"
local prev = home .. "/.config/beskar/wallpaper.previous"
local x = call(S.commit, jpg); check(x.ok, "commit jpg")
eq(read(cur), jpg .. "\n", "current written, one line"); eq(read(prev), nil, "no previous yet")
x = call(S.commit, jpg); check(x.ok, "commit the same again")
eq(read(prev), nil, "re-committing the current one does not clobber previous")
x = call(S.commit, png); check(x.ok, "commit png")
eq(read(cur), png .. "\n"); eq(read(prev), jpg .. "\n", "previous = old current")
x = call(S.commit, trunc); check(not x.ok and x.code == "corrupt", "commit of a bad file refused")
eq(read(cur), png .. "\n", "a refused commit leaves current alone"); eq(read(prev), jpg .. "\n", "and previous")
x = call(S.commit, weird); check(x.ok, "weird name committed"); eq(read(cur), weird .. "\n", "weird name round-trips exactly")
eq((sh("ls -A " .. q(home .. "/.config/beskar")):gsub("%s+", " ")), "wallpaper wallpaper.previous ", "no temp files left")

-- restore swaps; twice goes forward; a bad previous refuses without changing anything
x = call(S.restore); check(x.ok and x.path == png, "restore -> png")
eq(read(cur), png .. "\n"); eq(read(prev), weird .. "\n", "swapped")
x = call(S.restore); check(x.ok and x.path == weird, "restore again toggles")
sh(("rm -f %s"):format(q(png)))
x = call(S.commit, jpg); check(x.ok, "commit jpg (previous becomes weird)")
sh(("rm -f %s"):format(q(weird)))
x = call(S.restore); check(not x.ok and x.code == "missing", "previous gone: refused")
eq(read(cur), jpg .. "\n", "refused restore leaves current"); eq(read(prev), weird .. "\n", "and previous")
sh(("rm -f %s"):format(q(prev)))
x = call(S.restore); check(not x.ok and x.code == "no_previous", "no previous file")

-- symlinked current file keeps its link (dotfiles users)
local real = root .. "/dotfiles-wallpaper"
sh(("printf '%%s\\n' %s > %s && rm -f %s && ln -s %s %s"):format(q(jpg), q(real), q(cur), q(real), q(cur)))
x = call(S.commit, webp); check(x.ok, "commit through a symlink")
check(sh("test -L " .. q(cur) .. " && echo link"):match("link"), "still a symlink")
eq(read(real), webp .. "\n", "written to the target")
sh("rm -f " .. q(cur) .. " " .. q(real))

-- boot: current, else previous, else bundled, else error; never writes
sh(("printf '%%s\\n' %s > %s"):format(q(jpg), q(cur)))
x = call(S.boot); check(x.ok and x.path == jpg and x.source == "current", "boot current")
sh(("printf '%%s\\n' %s > %s"):format(q(pics .. "/gone.jpg"), q(cur)))
sh(("printf '%%s\\n' %s > %s"):format(q(png), q(prev)))
-- png was removed above: recreate
sh(("magick -size 32x32 xc:green %s"):format(q(png)))
x = call(S.boot); check(x.ok and x.path == png and x.source == "previous", "boot falls back to previous")
sh(("rm -f %s"):format(q(prev)))
x = call(S.boot); check(not x.ok and x.code == "none", "boot with nothing")
sh(("magick -size 16x16 xc:red %s"):format(q(home .. "/.local/share/beskar/wallpapers/z.jpg")))
sh(("magick -size 16x16 xc:blue %s"):format(q(home .. "/.local/share/beskar/wallpapers/a.jpg")))
x = call(S.boot); check(x.ok and x.source == "bundled" and x.path:match("/a%.jpg$"), "boot bundled, first by name")
eq(read(cur), pics .. "/gone.jpg\n", "boot never rewrites the file")

-- status: cheap, one line each, bounded
local st2 = call(S.status, { jpg, pics .. "/nope.jpg", notimg, "rel.jpg", dirpic, weird })
eq(st2[jpg], "ok"); eq(st2[pics .. "/nope.jpg"], "missing"); eq(st2[notimg], "unsupported")
eq(st2["rel.jpg"], "bad_path"); eq(st2[dirpic], "not_file")
eq(st2[weird], "missing", "weird name was removed above")
local many = {}
for i = 1, 60 do many[i] = pics .. "/m" .. i .. ".jpg" end
local st3 = call(S.status, many)
local n = 0; for _ in pairs(st3) do n = n + 1 end
eq(n, S.MAX_FAVOURITES, "status asks at most 48")
local st4 = call(S.status, {}); check(next(st4) == nil, "status of nothing")

-- prefs
sh(("printf '%%s' '{\"night\": 0, \"wallpaper_fx\": 2}' > %s"):format(q(home .. "/.config/beskar/prefs.json")))
local fx; S.read_fx(runner, function(v) fx = v end); eq(fx, 2, "wallpaper_fx read from prefs.json")
sh(("rm -f %s"):format(q(home .. "/.config/beskar/prefs.json")))
fx = "unset"; S.read_fx(runner, function(v) fx = v end); eq(fx, nil, "no prefs file")

-- a runner that fails / answers nothing never leaves the callback uncalled or truthy
local dead = function(_, _, cb) cb(nil) end
x = nil; S.check(dead, jpg, function(v) x = v end); check(x and not x.ok and x.code == "unknown", "dead runner")
-- invalid syntax is refused WITHOUT running anything
local ran = false
S.commit(function() ran = true end, "/x/a.gif", function(v) x = v end)
check(not ran and not x.ok and x.code == "unsupported", "syntax refused without a process")

-- ── the renderer's logic (shell/wallpaper.luau) with a fake sandbox: virtual timers, deferred real `run`s ──────────
local function sandbox()
    local env = { text = { wp_a_path = "", wp_b_path = "", wp_new = "" }, fact = { wp_go = false, wp_fx = 0 } }
    local handlers, timers, pending, logs, now = {}, {}, {}, {}, 0
    env.on = function(name, fn) handlers[name] = fn end
    env.after = function(ms, fn) timers[#timers + 1] = { at = now + ms, fn = fn } end
    env.log = function(...) logs[#logs + 1] = table.concat({ ... }, " ") end
    env.require = require
    local saved_run = rawget(_G, "run")
    _G.run = function(cmd, args, cb) pending[#pending + 1] = { args = args, cb = cb } end
    local chunk = assert(loadfile("shell/wallpaper.luau", "t", setmetatable(env, { __index = _G })))
    chunk()
    local sb = { env = env, logs = logs }
    function sb.flush()                       -- answer every pending process with what the real script says
        while #pending > 0 do
            local job = table.remove(pending, 1)
            runner("sh", job.args, job.cb)
        end
    end
    function sb.advance(ms)
        local target = now + ms
        while true do
            local best
            for i, t in ipairs(timers) do if t.at <= target and (not best or t.at < timers[best].at) then best = i end end
            if not best then break end
            local t = table.remove(timers, best)
            now = t.at; t.fn()
        end
        now = target
    end
    function sb.say(path) env.text.wp_new = path; handlers["text:wp_new"](path) end
    function sb.emit(name) handlers[name]() end
    function sb.pending() return #pending end
    function sb.done() _G.run = saved_run end
    return sb
end
local function files(cur_path, prev_path)
    sh(("rm -f %s %s"):format(q(cur), q(prev)))
    if cur_path then sh(("printf '%%s\n' %s > %s"):format(q(cur_path), q(cur))) end
    if prev_path then sh(("printf '%%s\n' %s > %s"):format(q(prev_path), q(prev))) end
end
local function settle(sb) sb.flush(); sb.advance(2300); sb.flush() end
sh(("magick -size 20x20 xc:red %s"):format(q(pics .. "/r1.jpg")))
local r1, r2 = pics .. "/r1.jpg", pics .. "/r2.png"
sh(("magick -size 20x20 xc:green %s"):format(q(r2)))

-- start: a good saved wallpaper is shown without a transition
files(r1)
local sb = sandbox(); sb.flush()
eq(sb.env.text.wp_a_path, r1, "start shows the saved wallpaper"); eq(sb.env.text.wp_b_path, "", "no transition at start"); sb.done()
-- start: bad saved wallpaper falls back to the previous one, files untouched
files(pics .. "/gone.jpg", r2)
sb = sandbox(); sb.flush()
eq(sb.env.text.wp_a_path, r2, "start falls back to previous"); eq(read(cur), pics .. "/gone.jpg\n", "start rewrites nothing"); sb.done()
-- start: nothing usable (and no bundled): nothing shown, no crash
files(nil, nil); sh(("rm -f %s/*"):format(q(home .. "/.local/share/beskar/wallpapers")))
sb = sandbox(); sb.flush(); eq(sb.env.text.wp_a_path, "", "nothing usable: base box only"); sb.done()
-- start: Settings' transition comes back from prefs.json, but a live `fact wp_fx` told earlier wins
sh(("printf '%%s' '{\"wallpaper_fx\": 2}' > %s"):format(q(home .. "/.config/beskar/prefs.json")))
sb = sandbox(); sb.flush(); eq(sb.env.fact.wp_fx, 2, "wp_fx restored from prefs"); sb.done()
sb = sandbox(); sb.env.fact.wp_fx = 1; sb.flush(); eq(sb.env.fact.wp_fx, 1, "live wp_fx is not overridden"); sb.done()
sh(("rm -f %s"):format(q(home .. "/.config/beskar/prefs.json")))

-- a rejected request keeps everything; the same path can be said again after it is fixed
files(r1)
sb = sandbox(); sb.flush()
sb.say(pics .. "/d.gif"); eq(sb.pending(), 0, "bad syntax never spawns")
sb.say(pics .. "/ghost.jpg"); sb.flush(); sb.advance(5000)
eq(sb.env.text.wp_b_path, "", "rejected: wp_b untouched"); eq(sb.env.text.wp_a_path, r1, "rejected: wp_a untouched"); eq(sb.env.fact.wp_go, false, "rejected: no reveal")
check(#sb.logs >= 2, "rejections are logged"); eq(sb.env.text.wp_new, "", "request text reset so it can repeat")
sh(("magick -size 20x20 xc:blue %s"):format(q(pics .. "/ghost.jpg")))
sb.say(pics .. "/ghost.jpg"); sb.flush()
eq(sb.env.text.wp_b_path, pics .. "/ghost.jpg", "same path accepted once it exists"); sb.advance(450); eq(sb.env.fact.wp_go, true, "reveal starts after the load delay")
sb.advance(1500); eq(sb.env.text.wp_a_path, pics .. "/ghost.jpg", "swapped after the reveal"); sb.advance(250); eq(sb.env.fact.wp_go, false, "reveal ends")
-- saying what is already shown does nothing
sb.say(pics .. "/ghost.jpg"); eq(sb.pending(), 0, "already shown: no process")
-- a newer request supersedes an older one still being validated
sb.say(r1); sb.say(r2); sb.flush()
eq(sb.env.text.wp_b_path, r2, "only the newest request is revealed"); settle(sb); eq(sb.env.text.wp_a_path, r2)
-- during a reveal, the newest is queued and runs next; picking the shown one again comes back to it
sb.say(r1); sb.flush(); sb.advance(500)
sb.say(r2); sb.flush()                       -- r2 is on screen: but r1 is mid-reveal, so r2 must come after it
settle(sb); sb.advance(2500); sb.flush()
eq(sb.env.text.wp_a_path, r2, "back to the one picked last, after the running reveal")
-- out-of-range transition: the logic does not need to fix it (the scene shows the circle), and never errors
sb.env.fact.wp_fx = 9; sb.say(r1); settle(sb); eq(sb.env.text.wp_a_path, r1, "any wp_fx still ends on the new picture")
-- restore_previous through the same script
files(r1, r2)
sb.done(); sb = sandbox(); sb.flush(); sb.emit("restore_previous"); sb.flush()
eq(sb.env.text.wp_b_path, r2, "restore reveals the previous"); settle(sb); eq(read(cur), r2 .. "\n", "restore swapped the file"); eq(read(prev), r1 .. "\n")
sb.emit("restore_previous"); sh(("rm -f %s"):format(q(prev))); sb.flush()
check(sb.env.text.wp_a_path == r2, "failed restore keeps the picture"); sb.done()

sh("rm -rf " .. q(root))
print(("wallpaper: %d checks passed (shell: %s)"):format(passed, SHELL))
