# Aligning Beskar with the pleamar way

Historical migration notes. The current shell already has owner scenes, typed events, split panel scenes and shared media.
For new work, see [Next features and unification](NEXT_FEATURES_PLAN.md). Later status sections supersede the early proposals below.

Branch `feat/pleamar-way`. Written 2026-11-12, after the unified-surface work (docs/UNIFIED_SURFACE_PLAN.md).

## What "the pleamar way" is (from pleamar 0.8's own docs and commits)

- A shell is **several scenes**, each one thing, able to be opened and restarted alone, composed with `import scene` into one
  process when wanted (G22). Not one giant scene, not one giant surface.
- A scene **owns** its facts and **writes only its own**; others **read** them by full name (`Core.open`) and ask for a change
  with an **event that says what it carries** (`event landed(id, x)`), checked by the compiler at both ends.
- A scene says which scenes it talks to (`uses scene "core.plm" as Core`) so it still opens alone.
- Each scene has **its own `permissions`** (least privilege), and its own Luau state/thread.
- A panel is drawn ONCE on a surface that follows its monitor (`screens: <text>`), not in every per-monitor copy.
- Feeds and helpers that are not UI are **plugins** (own thread, approved permissions, boundary of facts/events).
- Shared UI is **libraries** imported once.
- Coming upstream: a `shared fact` with an owner (issue 75 C), copies created at runtime (G12), fixes for #143 and #144.

## Where Beskar differs today

| Now | Pleamar way |
| :--- | :--- |
| `overlays` = ONE scene with 15 panels and ~2100 lines of logic, one `permissions` block with `sh`, `curl`, `rm`... for all | one scene per panel, each with only the permissions it needs |
| scenes talk with `say <scene> "fact x 1"` strings (unchecked) | events with declared payloads, `uses scene`, facts read by full name |
| shared panel state (`open`, `cur`, `panel_h`, `panel_mon`, `fresh`) lives inside overlays | an owner scene (`Panels`) holds it; panel scenes read it and send events |
| weather / system / updates feeds are modules inside overlays.luau | plugins (own thread, approved) |
| widgets, lock, wallpaper separate processes by workaround | brought into `desktop` once upstream fixes #143 / #144 |

## Spike (done, works on v0.8.0-exp.3)

`core.plm` (owns `text mon`, `fact open`, `fact cur`, `event close`), `p1.plm` and `p2.plm` (`uses scene "core.plm" as Core`,
`screens: Core.mon`, `open: Core.open and Core.cur == 1`, `on press z { emit Core.close }`), `main.plm` importing the three:
compiles and the panels are separate scenes. So the owner-scene pattern is possible today.

## Slices (each one ships on its own; the shell must work after every one)

1. **`Panels` owner scene. DONE.** New `shell/panels.plm` (+ `panels.luau` = what panelcore.luau does today): owns `open`, `cur`,
   `panel_h`, `panel_mon`, `fresh`, `open_screen`, the events `toggle(id)`, `show(id)`, `close(id)`, `outside_close`, and reports to
   the frame. `desktop.plm` imports it. Overlays still holds the panels but READS `Panels.*` and emits events.
2. **Typed contracts with the frame.** Replace the `say topbar "emit panel_open N"` / `say overlays "fact open_screen"` strings
   between topbar, panels and settings with declared events (`event panel_opened(id)`, `event panel_height(id, h)`,
   `event panel_width(id, w)`) and facts read by full name. Compile errors replace silent typos.
3. **Move the panels out of `overlays`, one scene each**, easiest first: Control Center (`cc.luau`), notifications (+ banner),
   today, music, weather, updates, then the dock panels (Spotlight, clipboard, wallpapers, widget bar, session, polkit, switcher,
   overview, welcome). Each scene: its own `.plm`, `.luau`, `permissions`, a surface `screens: Panels.mon`,
   `PanelBody` as a library component fed from `Panels.*`. Overlays shrinks until it is gone.
4. **Least-privilege permissions** per scene (only the Control Center gets network/bluetooth, only Spotlight gets `sh`...).
5. **Feeds as plugins**: weather forecast, system stats, update check, notification history; approved with `--approve`.
6. **Widgets, lock, wallpaper into `desktop`** when #143 / #144 are fixed (or earlier if a workaround holds). Frame with runtime
   per-monitor copies when pleamar has them.
7. **Shared facts with an owner** when pleamar ships them: drop the remaining event plumbing for plain values.

## Risks

- Every moved panel needs a live check (keys, close, monitor switch). A smoke script that opens every panel and reads the logs
  should come with slice 3.
- Panel scenes are `each`-free single surfaces; the scene-body `text` / `screens:` limits (#144) are avoided by reading the
  owner's text (`Core.mon`), which the spike proved.
- `import scene` shares one render: a slow panel scene slows the frame. Measured baseline: 0 slow frames on 8 panel opens.
- The runtime is an experimental pre-release (v0.8.0-exp.3, backed up in `~/.local/share/beskar/bin/`).

## Order of work

Slice 1, then 2, then 3 panel by panel (with the smoke script from the first moved panel), then 4, 5; 6 and 7 follow upstream.

## Status

- Slice 1 done and live: `shell/panels.plm` + `panels.luau` own the panel state; overlays (via `panelclient.luau`), the frame,
  widgets and Settings read it / talk to it. Settings now follows `Panels.panel_mon` (no more borrowing Overlays' text).
  Checked on the real shell: panel switching, heights/widths, keys, Esc, click outside, widget bar, Settings closing panels.
- Finding (pleamar 0.8-exp.3): an event emitted by a scene's LOGIC (`emit("Panels.height")`) reaches the other scene's `.plm`
  rules but not its logic; the logic side uses `say panels "emit ..."` meanwhile. Typed events from logic wait for upstream.
- Next: slice 2 (typed contracts where the runtime allows: `.plm` rules can already emit and read across scenes), then slice 3
  panel by panel.

## Final status (2026-11-12)

- Slice 1 done (owner scene `Panels`). Slice 3 done: `overlays` is gone; `controlcenter`, `notifications`, `infopanels`, `dockpanels`,
  `dialogs`, `windows` are scenes of their own in `desktop`, 9 scenes in one process, `PanelBody` a library, `shell/smoke.sh` checks all.
- Slice 4 done: each panel scene has only the permissions its own code uses.
- Slice 6: widgets and the wallpaper stay their own processes (measured: brought in beside the frame their drawing is repainted
  with every panel morph); the lock stays separate on purpose (a crash must not take the screen locker down).
- Slice 5 (plugins): not done on purpose. A plugin needs a per-user `--approve`, and our scenes already have their own Luau state,
  thread and permissions without it; feeds would better be a headless scene, which is not worth the rewiring now.
- Slice 2 (typed events): possible only from `.plm` rules; from logic an event does not reach the other scene's logic in
  0.8.0-exp.3 (reported: k4ditano/pleamar#145), so logic keeps `say`. Redo when it is fixed.
- Waiting on upstream: #143, #144 (widgets), #145 (typed events from logic), shared facts with an owner, runtime copies per monitor.

## Update: pleamar 0.8.0-exp.6 (2026-11-12)

#143, #144 and #145 are fixed upstream (exp.4 / exp.5). The shell runs on exp.6. Done with it: slice 2 (typed events between the scenes
of `desktop`: panels, frame, panel scenes, Settings; 35 `say` strings became `emit("Scene.event", payload)`, with `uses scene` declarations).
Still `say`: writes of another scene's facts, and every message to the separate processes. Widgets are still kept out of `desktop`
by the repaint measurement, not by the compile problem.
