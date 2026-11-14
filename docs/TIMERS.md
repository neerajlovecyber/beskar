# Shared timer

Beskar has one timer shared by Spotlight, the centre pill, the timer panel and a
medium desktop widget. Open **Timer** in Spotlight (or `> timer`), click its pill
indicator while a timer is present, click the timer widget's body, or run
`./beskar timer`.

The panel offers 5, 10 and 25 minute presets and a custom duration. Bare numbers
mean minutes; `1h30`, `1h30m`, `45s` and `0:30` also work. Durations are limited to
1 second through 24 hours. Selecting a preset changes the draft; Start begins it.
Starting another duration replaces the current timer.

While running, the panel and widget offer Pause, Resume and Cancel. Closing the
panel keeps the timer. Spotlight also offers Pause Timer, Resume Timer and Cancel
Timer; existing `timer 25m` input starts the same owner. The widget starts the
last duration, initially 25 minutes. Removing it never cancels the timer.

The duration field receives focus when the panel opens idle or completed. Tab
and Shift+Tab cycle between the field and two actions; Left/Right move between
actions. Enter/keypad Enter submits the field. Buttons activate on key release,
including Space, and the field's submit release is consumed so starting cannot
immediately pause. Escape and outside click close the panel.

## Ownership and recovery

`Activities` is a headless scene imported by the existing desktop process. It
alone mutates the timer and writes the atomic files-service snapshot:
`$XDG_DATA_HOME/pleamar/activities/timer.json` (the usual data-home fallback is
`~/.local/share`). `timer_state.luau` contains validation, parsing, formatting and
state transitions; `timer_panel.luau` owns only view focus and the duration draft.

Public events are `Activities.start(seconds)`, `pause`, `resume`, `cancel` and
`dismiss`. Other scenes read `timer_state` (idle 0, running 1, paused 2, done 3),
`timer_duration`, `timer_remaining`, `timer_progress`, `timer_text`, `timer_status`
and `ready`. Errors appear in `storage_status`. Existing `Topbar.timer_start` and
`timer_cancel` socket events forward to Activities for compatibility.

Remaining time is `deadline - os.time()`, bounded to the selected duration. The
runtime provides Luau's epoch clock; no `date` subprocess is spawned. Sleep and
time while the shell is stopped count toward a running timer. A paused timer
stays paused across both. System clock adjustments affect epoch deadlines: a
forward jump can finish early, a backward jump can extend the wait. This is a
wall-clock timer, not an alarm that wakes a sleeping computer.

Transitions save immediately; displayed seconds cause no disk writes. A timer
whose saved running deadline expired completes on startup. The terminal state is
saved before emitting `Topbar.timer_finished`; restarting with that saved done
state does not emit it again. If saving fails, completion waits for a successful
retry and the error stays visible. A crash between saving and delivering the
transient card can lose that card; the persistent done state remains visible.
Unreadable or malformed state is preserved and the owner stays unavailable.

## Presentation and cost

The frame retains its island priority rules. Completion offers a five-second
**Timer done** card when a higher-priority activity or panel does not own the
centre. Clicking it opens Timer. The pill retains a green done indicator until
Dismiss, Cancel or another start, including when the transient card was
suppressed. Paused timers show a pause glyph. Completion has no sound and keeps
the existing Timer notification/history entry; Notifications suppresses its
duplicate banner.

Panel 26 is one new, conditionally opened content surface in Infopanels; the
existing frame draws its glass through `PanelBody`. It adds no process or
full-screen effect. Timer widget kind 12 uses the existing widgets surface,
shared controls and catalogue. Widgets send monitor-name ordinals through
`Topbar.open_timer_output`, avoiding cross-process screen-index assumptions.

`timer_client.luau` reads Activities' snapshot on transition/revision events and
requests resync every 15 seconds only while a timer widget is visible (or in edit
mode). Its local display ticks once per second only while running with positive
time remaining. Removing/hiding the last timer widget stops both timers. The
owner's one-second deadline check exists only while running. There are no
per-second socket messages, file reads or file writes.

Compiled desktop: 2163 properties / 12327 instructions / 23 layers / 3140 rules /
1054 zones. Compiled widgets: 431 properties / 18512 instructions / 0 layers /
2308 rules / 900 zones. The extra widget controls expand over its max-16 model;
these are explicit source/compiled costs, not a frame-time benchmark.

## Focused verification

- `lua tests/timer.lua`: parser/state, delayed callbacks, suspend-equivalent clock
  jumps, recovery, persistence retries, completion delivery, keyboard controller
  and visibility-gated widget bridge.
- `lua tests/spotlight.lua`: existing launcher behaviour and timer routing.
- Compile `shell/desktop.plm` and `shell/widgets.plm`, run `shell/check-ui.py` and
  `shell/smoke.sh timer spotlight 'widget bar'`.
- An isolated nested niri checks native key event handling at 125% scale,
  including held Return, Pause/Resume, Tab/Cancel and Escape, alongside the widget.
  Dark/light visuals, widget-to-owner controls and a paused process restart were
  checked in that isolated session.
  The live check uses a short timer, verifies both monitor routes and restores an
  idle 25-minute duration.

Focus/DND policy and multiple concurrent timers remain separate future work.
