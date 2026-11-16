# Unified surface plan

Branch: `feat/unified-surface` (from `master` 98fb690).

## Goal

Today every panel is its own overlay surface, and the frame (`topbar.plm`) draws the glass for them from
facts. That bridge is most of the complexity in `AGENTS.md` (rules 13, 14, 15, 34, 35, 52, 53, 55).
The goal is for **panels to be drawn inside the same scene as the frame**, so a panel growing out of the
bar or dock is one shape in one surface: no `cp_* / rp_* / bp_*` facts crossing scenes, no
`panel_open / panel_close / panel_height` reporting, no `say`-based opening, and far fewer surfaces
(now ~23 declared, ~40-50 live on 2 monitors).

Also: the app switcher, window overview and welcome stop being centred floating windows (rules 22, 35, 51)
and become **dock panels that grow out of the bottom island**, like Spotlight, clipboard and the
wallpaper strip. Rule 22's "centred on purpose" is retired.

## Current surfaces (starting point)

| Scene | Surfaces | Becomes |
| :--- | :--- | :--- |
| `topbar` | 1 (frame, full screen) | the one `shell` surface |
| `overlays` | 13: weather, music, today, updates (top); session, auth, spotlight, clipboard, wallpapers, widget_bar (dock); switcher, overview, welcome (centred) | panels inside `shell`; switcher / overview / welcome move to the dock |
| `control_center` | 1 | panel inside `shell` |
| `notifications` | 2 (centre, banner) | panels inside `shell` |
| `settings` | 1 (sheet window) | stays its own scene for now (Phase 5) |
| `capture` | 1 (on demand) | unchanged |
| `lock` | 1 | unchanged |
| `wallpaper` | 1 (background) | unchanged |
| `widgets` | 1 (bottom level) | unchanged |
| `border` | 1 | unchanged |

Target: wallpaper + widgets + `shell` (+ settings, + on-demand capture, + lock) = 4 always-on processes
(from 8), roughly 1 surface per monitor for the shell instead of up to 12.

## Phase 0 - Baseline and spikes (do first, decide go / no-go)

Nothing in the live shell changes.

1. **Baseline numbers** (save in `docs/UNIFIED_SURFACE_BASELINE.md`): for each pleamar process,
   `drm-memory-gtt` + `drm-memory-vram` from `/proc/<pid>/fdinfo`; PSS; `./bin/pleamar --report <scene>
   --seconds 10` (paint rate, "barely animated"); surface count from the startup log.
2. **Build pleamar `exp2` (0.8.0-exp.1) in a separate directory**, not over `bin/pleamar`. Run
   `--check` on every `shell/*.plm`; list breakages. Features we want from it: `screens:` from a text
   (move a surface to a chosen monitor while it runs, #136), `z:` groups taking presses where drawn,
   `#rrggbbaa` colours, `border:`, popups from a window, more than 65 536 properties.
3. **Spike A - keyboard.** One surface that moves to the monitor with the focus (`screens:` from text)
   with `keyboard: exclusive while open`. Must give keys on the right monitor, and keys back to windows
   on close. This is what rule 15 could not do with `each` (the condition cannot tell copies apart).
   **If this fails, stop: the plan needs another approach** (see Risks).
4. **Spike B - cost of one full-screen surface per monitor** with glass and a morphing panel: paint
   percentage with `PLEAMAR_TIMING=1`, hover and open / close cost, GPU memory vs baseline.
5. **Spike C - stacking.** The frame is a full-screen surface: confirm its `level` keeps windows
   below it, a fullscreen window / game still covers it, and click-through still works (rule 5) with the
   panel zones added.

Exit criteria: A works, B is not worse than baseline, C works. Write the result at the top of this file.

## Phase 1 - Dock modals become dock panels (smallest visible win, low risk) - DONE, uncommitted

Implemented and tested on the live shell: switcher, overview and welcome open from the dock with the frame's glass; the glass width follows the content (`panel.width`); Esc / arrows / outside click work; `modal` layer removed. `--check` passes on `overlays.plm` and `topbar.plm`.

Done inside the existing `overlays` scene, before the big merge, so it ships on its own.

- `switcher` (cur 21), `overview` (22), `welcome` (24) lose their `anchor: center` surfaces and the
  `modal` layer (`mseen`, `mscale`, `mp_*`). Each becomes a panel of the dock island like Spotlight
  (`PanelBody(x, y, 1)`, `cur` ids kept, `PANELS` / `DOCK` entries in `topbar.luau`, glass from the
  `dock_island` shape).
- Sizes: switcher 1160x220 (a wide strip, fits the dock), overview 1280x860 (large: grows up from the
  dock, scrolls if the screen is small), welcome 720x520.
- Keep behaviour: Super+Tab hold / release logic, Tab / arrows / Enter / Esc, thumbnails `want` / `live`
  released on close (rule 35), welcome's 7 s first-run open.
- Delete: the `modal` layer code, `mseen`/`mscale`, the centred-window rules in `AGENTS.md`.
- Check: every panel closes the same way (rule 42): Esc, click outside, blur.

## Phase 2 - Fold `control_center` and `notifications` into `overlays` - DONE, committed with this note

Implemented as `shell/parts/*.plm` + `cc.luau` / `notif.luau`; 8 always-on processes became 6. Tested on the real shell: Control Center (pages, media card), notification centre, banner in the centre pill.

The "planned next" from rule 55. Their panels (right island) and the banner / centre cards join the
overlays scene as more `cur` ids. Removes two processes and the `say` between them and `exclusive.luau`.
`notifications.luau` keeps owning the notification daemon / history; the banner stays a card in the
centre pill (rule 17). Settings pushes (`THEMED`, theme broadcast) lose two targets.

## Phase 3 - The merge: frame + overlays = scene `shell`

The real change.

1. New scene `shell.plm / shell.luau` = `topbar` + `overlays`. One surface `frame` per monitor
   (full screen, `screens: each` as now, or one moved surface if Phase 0 A says so), containing: the
   frame silhouette, all islands, **every panel as a body inside it**, the outside-click zone.
2. Panels use one `Panel(id, island, w, h)` wrapper replacing `PanelBody`, `TopBody`, the `morph*.plm`
   files and the `cp_* / rp_* / bp_*` facts: the glass shape and the content share the same spring.
3. One `cur` / `open_screen`, one `fresh`, one keyboard owner. `panelcore.luau`, `panel.luau`,
   `exclusive.luau` collapse into a single `panels.luau` (open, close, height, exclusivity, outside click).
4. Opening becomes a plain `emit open_panel ID` in the same scene; `OVERLAY`, `FOCUS_PANELS`, `MERGED`,
   `PANELS`, `DOCK` maps and every `say overlays` / `say topbar` between them go away. Other scenes
   (widgets, settings, capture, lock, start.sh) say `shell` instead.
5. Keyboard: `keyboard: exclusive while open` on the one surface for panels that need it
   (spotlight, clipboard, wallpapers, session, auth, switcher, overview, welcome, widget bar when it
   needs it), `on_demand` for weather search.
6. Port panel by panel, keeping the old scenes running until each one works in `shell`:
   today -> music -> updates -> weather -> control centre -> notifications -> spotlight -> clipboard ->
   wallpapers -> widget bar -> session -> auth -> switcher -> overview -> welcome. After each: `--check`,
   restart in its own unit (rule 47), `grim` both monitors, test keys with `wtype`.
7. Switch `start.sh`: supervised list = wallpaper, shell, widgets, settings (+ lock, capture as before).

Risks to watch: file size (`overlays.plm` 1593 + `topbar.plm` 867 lines: split into `part` files per
panel, `include`d), `each max` copies compiled per monitor (set `max 2`), full-screen repaint cost
(Phase 0 B), and one scene crash taking the bar and every panel down (the supervisor restarts it in 1 s).

## Phase 4 - Clean up and document

- Delete the old scenes and files: `topbar.*`, `overlays.*`, `control_center.*`, `notifications.*`,
  `panelcore.luau`, `panel.luau`, `exclusive.luau`, `common/morph*.plm`.
- Rewrite `AGENTS.md`: replace rules 13-15, 17, 22, 34, 35, 36 (where it names scenes), 50-55 with one
  short "how panels work" rule. Update the layout table.
- Re-measure against the Phase 0 baseline and record it.

## Phase 5 - Optional

- Settings as a dock panel (it has 8 tabs and a sidebar: probably stays a window).
- Widgets and wallpaper into `shell` (rule 27 / 29 reasons: level bottom / background; probably stay).
- Planned in `AGENTS.md`: a `desktop` scene = wallpaper + topbar + widgets.

## Acceptance criteria

- All current features work: every panel, keyboard flows, notifications, OSD cards, lock, capture,
  recording dot, multi-monitor (panel opens on the focused monitor).
- Processes always on: 8 -> 4 or fewer. GPU memory and PSS no worse than baseline, ideally lower.
- Idle `--report shell` says "barely animated" (rule 54).
- `AGENTS.md` lost more rules than it gained.

## Risks and fallbacks

| Risk | Fallback |
| :--- | :--- |
| Spike A fails (keyboard per monitor) | Keep one separate `keyboard: exclusive` surface per monitor only for key-taking panels (current model), still merge everything else. |
| `exp2` is an experimental pre-release | Phases 1 and 2 need nothing from it. Phase 3 can use `each` + `open_screen` as today and adopt `screens:`-from-text later. |
| Full-screen surface costs more paint | Pleamar repaints only changed boxes (P14); verify in Spike B. If bad, stop at Phase 2. |
| Large diff, long-running branch | Each phase merges to `master` on its own once green; Phase 3 per panel. |

## Notes

- The branch was created with uncommitted changes carried over (`docs/ROADMAP.md`, `shell/topbar.luau`);
  commit or stash them before starting.
- Never start the shell from a tool call directly (rule 47): use
  `systemd-run --user --unit=beskar-shell --remain-after-exit --collect shell/start.sh restart`.


## Status after phases 3 and 4 (done with `import scene` of pleamar 0.8-exp.3, not by rewriting into one surface)

The approach changed: pleamar 0.8 lets a scene bring whole scenes into one process (`import scene`) and draw a panel once on a
surface that follows a monitor (`screens: <text>`). So: processes 6 -> 3 (desktop, widgets, lock; capture on demand) and
overlay surfaces from ~26 to 13 (one per panel, mapped only while open). See AGENTS.md rule 57 for what it took and the
measured numbers. Not done: widgets and lock inside the desktop (pleamar issues above), the frame itself is still a
`screens: each` surface, and settings is still a window of its own inside the desktop. When 0.8.0 is released, move
`bin/exp/pleamar` to the stable build.
