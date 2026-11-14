-- Settings' portable-setup adapter end to end: export, review, apply across the four owners, undo, owner
-- failures and a recovery after an interrupted run. Owners are in-memory stand-ins; the adapter's own sh scripts run
-- for real against a throwaway HOME. Run: lua tests/settings-setup.lua
package.path = 'shell/?.luau;tests/?.lua;' .. package.path
local SP, P = require('setup_profiles'), require('preferences')
local json = require('jsonlite')

local passed = 0
local function check(v, m) if not v then error(m, 2) end; passed = passed + 1 end
local function q(v) return "'" .. tostring(v):gsub("'", "'\\''") .. "'" end

local temp = os.tmpname(); os.remove(temp)
assert(os.execute('mkdir -m 700 ' .. q(temp) .. ' && mkdir -p ' .. q(temp .. '/.config/beskar')))

local function runner(script, args, cb, opts)
    local words = { 'HOME=' .. q(temp), 'sh', '-c', q(script), 'setup' }
    for _, a in ipairs(args) do words[#words + 1] = q(a) end
    local cmd = table.concat(words, ' ')
    if opts and opts.input then
        local f = assert(io.open(temp .. '/input', 'wb')); f:write(opts.input); f:close()
        cmd = cmd .. ' < ' .. q(temp .. '/input')
    end
    local ok, _, code = os.execute(cmd .. ' > ' .. q(temp .. '/out') .. ' 2>/dev/null')
    local f = assert(io.open(temp .. '/out', 'rb')); local body = f:read('*a'); f:close()
    cb(body, ok and 0 or code or 1)
end

-- ── the world: what each owner holds ───────────────────────────────────────────────────────────────────
local function frame_defaults()
    local t = {}
    for _, f in ipairs(SP.FRAME_FIELDS) do t[f.fact] = f.default end
    t.frame_output_name = ''
    return t
end
local world = {
    appearance = { appearance = 1, skin = 0, accent = 0, accent_auto = false, pal_style = 0 },
    frame = frame_defaults(),
    pins = { 'kitty' },
    cards = {},
    fail_settings = false,
}
local function live_settings()
    return { appearance = { values = world.appearance, palette = nil }, frame = { facts = world.frame } }
end
local function section_fp(section)
    return SP.fingerprint(section, SP.snapshot(section, live_settings()[section], { preferences = P }))
end

local settings_calls, pins_calls = 0, 0
local host_fact, host_text, host_model, handlers, queue = {}, {}, {}, {}, {}
local clipboard

local function apply_settings(act, cb)
    settings_calls = settings_calls + 1
    if world.fail_settings and act.op == 'apply' then cb({ ok = false, untouched = false, code = 'write_failed' }); return end
    if not act.force and section_fp(act.section) ~= act.expect then cb({ ok = false, untouched = true, code = 'stale' }); return end
    local data = SP.validate_section(act.section, act.data, { preferences = P })
    if not data then cb({ ok = false, untouched = true, code = 'invalid' }); return end
    for name, value in pairs(SP.to_facts(act.section, data, { preferences = P })) do world[act.section][name] = value end
    cb({ ok = true, fp = section_fp(act.section) })
end
local function pins_fp() return SP.fingerprint('pins', SP.snapshot('pins', { list = world.pins })) end
local function apply_pins(act, cb)
    pins_calls = pins_calls + 1
    if not act.force and pins_fp() ~= act.expect then cb({ ok = false, untouched = true, code = 'stale' }); return end
    local data = SP.validate_section('pins', act.data, { local_pins = true })
    if not data then cb({ ok = false, untouched = true, code = 'invalid' }); return end
    world.pins = data.default and nil or data.list
    cb({ ok = true, fp = pins_fp() })
end
local function cards_snapshot() return { ready = true, snap = true, cards = world.cards } end

local function say(scene, words)
    local id = tonumber(words:match('^emit setup_request (%d+)$'))
    if scene ~= 'widgets' or not id then return end
    local f = assert(io.open(temp .. '/.config/beskar/setup-widget-request.json', 'rb')); local body = f:read('*a'); f:close()
    local req = assert(json.decode(body))
    local resp = { id = req.id, ok = true }
    if req.kind == 'snapshot' then resp.data = cards_snapshot()
    else
        local data = SP.validate_section('widgets', req.data, {})
        world.cards = data and data.cards or world.cards
        resp.fp = SP.fingerprint('widgets', SP.snapshot('widgets', cards_snapshot()))
    end
    local out = assert(io.open(temp .. '/.config/beskar/setup-widget-response.json', 'wb')); out:write(json.encode(resp)); out:close()
    handlers.setup_widgets_reply(req.id)
end

local A = require('settings_setup')(P, {
    live_settings = live_settings,
    apply_settings = apply_settings,
    read_pins = function(cb) cb({ list = world.pins }) end,
    apply_pins = apply_pins,
    ready = function() return true end,
    run = runner,
    say = say,
    clipboard = function(body, cb) clipboard = body; cb(true) end,
    now = function() return 1700000000 end,
    decode = json.decode, encode = json.encode,
    after = function(_, fn) local h = { fn = fn }; queue[#queue + 1] = h; return h end,
    cancel = function(h) if h then h.fn = nil end end,
    on = function(name, fn) handlers[name] = fn end,
    fact = host_fact, text = host_text, model = host_model,
})

check(host_fact.setup_export_count == 4, 'All four sections are offered for export')
check(host_fact.setup_open == nil or host_fact.setup_open == false, 'The page starts closed')
handlers.setup_show(); check(host_fact.setup_open == true, 'Opening the page sets its fact')

-- state A: export it
handlers.setup_export()
check(type(clipboard) == 'string' and clipboard:find('%S'), 'Export puts the document on the clipboard')
check(host_text.setup_document == clipboard, 'Export fills the document field')
check(not clipboard:find('commandpin') and not clipboard:find('app:'), 'The document carries no window pins')
local doc_a = clipboard

-- state B: change everything the profile covers
world.appearance.appearance = 0
world.frame.bar_style = 1
world.pins = { 'foot' }
local before_b = { app = section_fp('appearance'), frame = section_fp('frame'), pins = pins_fp() }

handlers.setup_review_import()
check(host_fact.setup_reviewing == true, 'A document with changes is staged for review')
check(host_fact.setup_review_count >= 3, 'Appearance, frame and pins are chosen by default')
check(settings_calls == 0 and pins_calls == 0, 'Review changes nothing')
check(#host_model.setup_lines > 0, 'The review lists what would change')

handlers.setup_apply()
check(host_fact.setup_running == false, 'The run finished')
check(world.appearance.appearance == 1 and world.frame.bar_style == 0, 'Settings sections were applied')
check(world.pins and world.pins[1] == 'kitty', 'The dock pins were applied through Topbar')
check(host_fact.setup_can_undo == true, 'Undo is offered after a completed apply')

handlers.setup_undo()
check(world.appearance.appearance == 0 and world.frame.bar_style == 1 and world.pins[1] == 'foot', 'Undo puts state B back')
check(section_fp('appearance') == before_b.app and section_fp('frame') == before_b.frame and pins_fp() == before_b.pins, 'Undo restores exact fingerprints')

-- a failing owner rolls the others back
world.fail_settings = true
handlers.setup_review_import()
check(host_fact.setup_reviewing == true, 'Second review staged')
handlers.setup_apply()
check(world.pins[1] == 'foot' and world.appearance.appearance == 0, 'A refused section leaves everything as it was')
check(host_fact.setup_running == false and host_fact.setup_attention == false, 'A clean rollback needs no attention')
world.fail_settings = false

-- a malformed document is refused without touching anything
local calls = settings_calls + pins_calls
host_text.setup_document = '{"not":"a setup"}'
handlers.setup_review_import()
check(host_fact.setup_reviewing == false and settings_calls + pins_calls == calls, 'A foreign document is refused')

-- the journal survives: a fresh adapter reads it and offers nothing to recover after a finished run
local B = require('settings_setup')(P, {
    live_settings = live_settings, apply_settings = apply_settings,
    read_pins = function(cb) cb({ list = world.pins }) end, apply_pins = apply_pins,
    ready = function() return true end, run = runner, say = say, now = function() return 1700000100 end,
    decode = json.decode, encode = json.encode,
    after = function(_, fn) return { fn = fn } end, cancel = function() end,
    on = function() end, fact = {}, text = {}, model = {},
})
check(B.state.phase ~= 'recovery', 'A completed or rolled-back journal needs no recovery')

-- a clipboard helper that never answers cannot leave the page busy
do
    local f2, t2, h2, q2 = {}, {}, {}, {}
    local C = require('settings_setup')(P, {
        live_settings = live_settings, apply_settings = apply_settings,
        read_pins = function(cb) cb({ list = world.pins }) end, apply_pins = apply_pins,
        ready = function() return true end, run = runner, say = say, now = function() return 1700000200 end,
        decode = json.decode, encode = json.encode, clipboard = function() end,
        after = function(_, fn) local h = { fn = fn }; q2[#q2 + 1] = h; return h end,
        cancel = function(h) if h then h.fn = nil end end,
        on = function(name, fn) h2[name] = fn end, fact = f2, text = t2, model = {},
    })
    h2.setup_export()
    check(f2.setup_busy == true, 'Export waits for the clipboard')
    for _, h in ipairs(q2) do if h.fn then local fn = h.fn; h.fn = nil; fn() end end
    check(f2.setup_busy == false and t2.setup_status:find('clipboard'), 'A silent clipboard times out and frees the page')
end

os.execute('rm -rf ' .. q(temp))
print('settings-setup: ' .. passed .. ' checks passed')
