-- Pure quiet-policy checks: no services, files or scene state.
package.path = "shell/?.luau;" .. package.path
local Q = require("quiet_policy")
local passed = 0
local function check(value, message) assert(value, message); passed = passed + 1 end
local function eq(a, b, message) assert(a == b, message .. " (got " .. tostring(a) .. ", want " .. tostring(b) .. ")"); passed = passed + 1 end

-- temporary policies
local p = Q.policies_new()
check(select(1, Q.policy_apply(p, "start", "focus")) == true and p.focus, "start enables a mode")
check(Q.policy_apply(p, "start", "focus") == false, "starting an active mode changes nothing")
Q.policy_apply(p, "start", "GAME")
eq(Q.policy_text(p), "Focus · Game", "active modes are listed in fixed order")
Q.policy_apply(p, "toggle", "focus")
check(not p.focus and p.game, "toggle flips one mode only")
local changed, err = Q.policy_apply(p, "start", "gaming")
check(changed == false and err, "an unknown mode is refused with a message")
changed, err = Q.policy_apply(p, "start", nil)
check(changed == false and err, "a missing mode name is refused")
check(Q.policy_apply(p, "stop_all") == true and not p.game and Q.policy_apply(p, "stop_all") == false, "stop_all clears and is idempotent")
check(select(2, Q.policy_apply(p, "explode", "focus")) ~= nil, "an unknown operation is refused")

-- quiet hours
local function hours(s, e) return Q.hours_from(true, s, e) end
check(Q.hours_active(hours(22 * 60, 7 * 60), 23 * 60), "an overnight window is active before midnight")
check(Q.hours_active(hours(22 * 60, 7 * 60), 6 * 60 + 59), "an overnight window is active after midnight")
check(not Q.hours_active(hours(22 * 60, 7 * 60), 7 * 60), "the end minute is exclusive")
check(Q.hours_active(hours(22 * 60, 7 * 60), 22 * 60), "the start minute is inclusive")
check(Q.hours_active(hours(9 * 60, 17 * 60), 12 * 60) and not Q.hours_active(hours(9 * 60, 17 * 60), 17 * 60), "a same-day window")
check(not Q.hours_active(hours(600, 600), 600), "equal start and end is an empty window")
check(not Q.hours_active(Q.hours_from(false, 0, 1000), 100), "disabled windows are never active")
for _, bad in ipairs({ -1, 1440, 1.5, "10", 0 / 0 }) do
    check(not Q.hours_active(Q.hours_from(true, bad, 700), 100), "an invalid start means no window")
    check(not Q.hours_active(Q.hours_from(true, 0, bad), 100), "an invalid end means no window")
end
check(not Q.hours_active(Q.hours_from(nil, 0, 700), 100), "missing Settings facts mean no window")
eq(Q.minute_of({ hour = 7, min = 5 }), 425, "minute_of")

-- effective state: manual choice and temporary policies are independent
local manual_on = { manual = true, policies = Q.policies_new(), hours = hours(0, 0), minute = 0 }
local e = Q.effective(manual_on)
check(e.quiet and e.label == "Do Not Disturb" and e.short == "DND", "manual DND alone is quiet")
local pol = Q.policies_new(); pol.focus = true
e = Q.effective({ manual = true, policies = pol, hours = hours(0, 0), minute = 0 })
eq(e.label, "Do Not Disturb · Focus", "reasons combine in fixed order")
eq(e.short, "DND +1", "short label names the first reason and counts the rest")
-- the user turns DND on during focus, then focus ends: still quiet. Turning it off during focus keeps focus quiet.
pol.focus = false
check(Q.effective({ manual = true, policies = pol, minute = 0 }).quiet, "ending a mode keeps an intervening manual DND")
pol.focus = true
check(Q.effective({ manual = false, policies = pol, minute = 0 }).quiet, "manual off does not end an active mode")
pol.focus = false
check(not Q.effective({ manual = false, policies = pol, minute = 0 }).quiet, "no reasons is not quiet")
eq(Q.effective({ manual = false, policies = Q.policies_new(), hours = hours(60, 120), minute = 90 }).label, "Quiet hours", "hours are a reason")
eq(Q.effective({}).quiet, false, "an empty input is not quiet")

-- rules
local r = Q.rules_new(nil)
check(#r.apps == 0, "first run has no rules")
check(Q.rule_set(r, " Mail ", "muted") == true, "a rule can be added (name trimmed)")
eq(Q.rule_mode(Q.rule_map(r), "Mail"), "muted", "lookup is by exact app name")
eq(Q.rule_mode(Q.rule_map(r), "mail"), "normal", "app names are case-sensitive")
check(Q.rule_set(r, "Mail", 1) == true and r.apps[1].mode == "no_banner", "numeric modes are accepted and replace")
check(Q.rule_set(r, "Mail", "no_banner") == false, "the same rule is not a change")
check(Q.rule_set(r, "Mail", "normal") == true and #r.apps == 0, "normal removes the rule")
check(Q.rule_set(r, "Ghost", "normal") == false, "removing an absent rule changes nothing")
for _, bad in ipairs({ "", "   ", 5, "a\nb", string.rep("x", 121) }) do
    local c, msg = Q.rule_set(r, bad, "muted")
    check(c == false and msg, "unusable app names are refused")
end
local c, msg = Q.rule_set(r, "A", "loud")
check(c == false and msg, "unknown modes are refused")
Q.rule_cycle(r, "Chat"); eq(r.apps[1].mode, "no_banner", "cycle: normal to no_banner")
Q.rule_cycle(r, "Chat"); eq(r.apps[1].mode, "muted", "cycle: no_banner to muted")
Q.rule_cycle(r, "Chat"); eq(#r.apps, 0, "cycle: muted back to normal")
for i = 1, Q.MAX_RULES do check(Q.rule_set(r, "app" .. i, "muted"), "fill rules") end
c, msg = Q.rule_set(r, "overflow", "muted")
check(c == false and msg, "the rule list is bounded")
check(Q.rule_set(r, "app1", "no_banner") == true, "an existing rule can change when full")
check(Q.rules_clear(r) and #r.apps == 0 and not Q.rules_clear(r), "clear removes everything once")

-- saved store validation
r = Q.rules_new(nil); Q.rule_set(r, "Mail", "muted"); Q.rule_set(r, "Chat", "no_banner")
local snap = Q.snapshot(r)
snap.apps[1].mode = "normal"
eq(r.apps[1].mode, "muted", "a snapshot is a copy")
local back = Q.rules_new(Q.snapshot(r))
check(back and #back.apps == 2 and back.apps[2].app == "Chat", "a saved store round-trips")
local function bad(saved) local v, m = Q.rules_new(saved); check(v == nil and m, "bad store refused") end
bad("x"); bad({ version = 2, apps = {} }); bad({ version = 1 }); bad({ version = 1, apps = { 7 } })
bad({ version = 1, apps = { { app = "A", mode = "loud" } } })
bad({ version = 1, apps = { { app = "A", mode = "normal" } } })
bad({ version = 1, apps = { { app = " A", mode = "muted" } } })
bad({ version = 1, apps = { { app = "A", mode = "muted" }, { app = "A", mode = "no_banner" } } })
local many = { version = 1, apps = {} }
for i = 1, Q.MAX_RULES + 1 do many.apps[i] = { app = "a" .. i, mode = "muted" } end
bad(many)

-- treatment and app list
local t = Q.treatment(false, "normal"); check(t.banner and t.counted, "normal apps banner and count")
t = Q.treatment(true, "normal"); check(not t.banner and t.counted, "quiet suppresses banners, still counts")
t = Q.treatment(false, "no_banner"); check(not t.banner and t.counted, "no_banner: counted, no banner")
t = Q.treatment(false, "muted"); check(not t.banner and not t.counted, "muted: neither")
r = Q.rules_new(nil); Q.rule_set(r, "zeta", "muted"); Q.rule_set(r, "Alpha", "no_banner")
local list = Q.app_list(r, { "Mail", "zeta", "Mail", "", "Chat" }, 4)
eq(#list, 4, "list respects the cap")
check(list[1].app == "Alpha" and list[1].mode == 1 and list[1].rule, "rules first, sorted ignoring case")
check(list[2].app == "zeta" and list[2].mode == 2, "second rule")
check(list[3].app == "Mail" and list[3].mode == 0 and not list[3].rule and list[4].app == "Chat", "recent senders follow, de-duplicated, in order")
print("Quiet policy: " .. passed .. " focused checks passed")
