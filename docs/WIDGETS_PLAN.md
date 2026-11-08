# Beskar desktop widgets: architecture and implementation plan

Goal: widgets on the desktop like iNiR 3.0 (iRiS): a set of small glass cards that sit on the wallpaper, an **edit mode** to arrange them, **sizes**, **stacks**, **saved layouts**, and a way to **add your own**. Built the pleamar way: `.plm` scenes + Luau, no Rust, no QML.

---

## 1. What iNiR does (the part we copy)

Read from `cloned_repos/inir` (v3.0.0): `services/DesktopWidgetLayout.qml`, `DesktopWidgetStacks.qml`, `CustomWidgets.qml`, `modules/shared/background/widgets/*`, `edit/WidgetShelf.qml`.

| iNiR piece | What it is | Beskar equivalent |
| :--- | :--- | :--- |
| `DesktopWidgetRegistry` + `widgets.list` + `<key>/widget.json` | One manifest per widget: name, icon, tint, category, `sizes`, `defaultOn`, `defaultConfig`, `options`, `lock`. Shelf, Settings and IPC all read it. | `shell/widgets/registry.luau`: one Lua table, same fields. |
| `AbstractBackgroundWidget` | Base class: position, scale, opacity, plate (background + border), lock, resize axes, edit popover. | `component WidgetFrame` in `widgets/frame.plm`. |
| Size classes | `small` 176x176, `medium` 368x176, `large` 368x368 on a 176 px unit with 16 px gap. | Same grid, same names. |
| `DesktopWidgetLayout` | Positions saved **per output and per resolution** (`layouts["1920x1080"]`), `placementStrategy` free / anchored, grid snap 16/32/48/64, "remembered sizes". | `layout.luau`: `widgets.json` keyed by output name. |
| Edit mode (`WidgetShelf`) | Desktop recedes into a card; shelf of every widget by category; magnet snapping + guides; Undo for any move. | `widgets.plm` edit state + `shelf` surface (Phase 4). |
| `DesktopWidgetStacks` | Several widgets share one place; one page shown, auto-rotate (paused on hover), shared place/size/material. | Phase 6. |
| Saved desktops | Presets: Glance, Dashboard, Focus, Listening, Bare. | Phase 5. |
| Custom widgets (`~/.config/inir/widgets/<id>/`) | A folder with a manifest + a QML file. | Phase 7: `~/.config/beskar/widgets/<id>/widget.json` + a `.plm` fragment. |
| Lock-screen widgets | A widget flagged `lock: true` can also show on the lock screen, with its own layout scope `lock:<output>`. | Phase 8, optional. |
| Faces per family | Same widget, different drawing per design. | We already have `skin`/`accent` in `theme.plm`; one face per widget, restyled by tokens. |

iNiR's 25 built-in widgets, grouped by its shelf categories: **today** (clock, worldClock, dayProgress, weather, dateBadge, monthCalendar, calendarUpcoming), **media** (mediaControls, lyrics, visualizer), **system** (systemMonitor, battery, uptime, screenTime, controls), **notes** (notes, todo, timers, newsTicker), **decor** (userCard, customImage, shape, mascot, palette, editorial, japaneseTypography, imageConverter).

---

## 2. What pleamar gives us (and what it does not)

Verified in `bin/pleamar --docs reference|logic`:

- **A surface at `level: background`** sits above the wallpaper and under every window. With `size: full, full` and `screens: each` it covers each monitor; **only zones catch the mouse, everything else is click-through** (rule 5 in AGENTS.md). So the whole desktop can be one surface and the wallpaper stays clickable. This is exactly how the frame already works.
- **`drag` zones** with `drag.dx` / `drag.dy`, `local.x/y`, `pointer.x/y`, `wheel`, `on press right`. Enough for move, resize handles and snapping.
- **Springs and layouts** (`prop ... ~calm`, `row`/`column` with `grow`, `size`, `view`) for the grid, size changes and magnet feel.
- **Glass** (`body`, `smoke`, `milk`, `blur`) already used in every panel; widgets reuse `theme.plm` tokens.
- **Services**: `media`, `battery`, `network`, `audio`, `brightness`, `notifications`, `apps`, `workspaces/window`, `clock`. Everything else through `run`/`spawn` (`/proc`, `curl`, `date`, `niri msg`).
- **Persistence**: `run("sh", {"-c", ...})` writing JSON under `~/.config/beskar/` (the Settings pattern: `prefs.json`).
- **`say` between scenes**: how Settings pushes options and how widgets get data from the frame.

Limits that shape the design:

1. **No dynamic instancing.** A `component` is instantiated at load time; `repeat i in 0..N` unfolds at load (512 max). A model can drive `show:`, text and position, but it cannot create a new widget kind at run time. So: a **fixed pool of slots**, each slot a generic `WidgetFrame` that shows exactly one *face* chosen by `kind`.
2. **`screens: each` shares loose props** (rule 2). Per-monitor data lives in a `model` indexed by `$screen`, and the drawing sits inside a component.
3. **One process per scene.** We already run 13. Widgets must be **one** new scene (`widgets.plm`), not one per widget.
4. **No `loadstring`, no `io`/`os`.** Custom widgets are declarative (manifest + a `.plm` part), not arbitrary code. See Phase 7.
5. **Events need `->`** to reach Luau (the bug that broke the lock screen).
6. **Right-click quits a scene** unless some rule uses `on press right` (rule 1).

---

## 3. Architecture

```
shell/
  widgets.plm              scene "Widgets": ONE surface, level: background, screens: each
  widgets.luau             logic: registry, layout, edit state, persistence, data feeds
  widgets/
    registry.luau          manifest table (name, icon, tint, category, sizes, defaults, options)
    layout.luau            grid math, snapping, per-output positions, save/load widgets.json
    feeds.luau             shared data (weather, system stats, calendar, notes) → facts per kind
    frame.plm              part: WidgetFrame (plate, drag zone, resize handle, lock, edit chrome)
    faces/                 one part per widget kind: clock.plm, weather.plm, system.plm, ...
    presets.json           factory desktops (Glance, Dashboard, Focus, Listening, Bare)
  widget_shelf.plm/.luau   edit-mode shelf (a panel scene, Phase 4)
```

### 3.1 The slot pool

`widgets.plm` declares a `model slots max 24 { kind: number; x, y: number; size: number; opacity; locked: bool; stack: number; page: number; ... }`, **per monitor** (`$screen`). Logic fills it from `widgets.json`.

Inside the surface: `repeat i in 0..23 { WidgetFrame(i) }`. Each frame:

- positions itself at `slots.$i.x/y` through springs (`~calm`), size from the size class;
- draws the plate (glass, `smoke`/`milk` by `dark_mode`, border, shadow) unless the widget is `bare`;
- contains `include "widgets/faces/*.plm"` groups, each `show: kind == K`. Hidden groups are not drawn; the cost is measured in Phase 0 before we commit to this (§7, risk 1);
- owns the zones: body (drag in edit mode, click action otherwise), 4 resize handles / one corner, a lock toggle, a close/remove chip.

Unused slots are `show: kind > 0`-gated and cost nothing.

### 3.2 Faces

A face is a `part Clock { ... }` that reads **only** its own facts (`w_clock_time`, `w_weather_temp`, ...) and the frame's `fw`/`fh` (the size class box). Each face supports the widget's size classes by switching on `fw`/`fh` (small = glyph + one number; medium = row; large = detailed). Colours only from `theme.plm` tokens, so light/dark/skin/accent work for free.

### 3.3 Data feeds (`feeds.luau`)

One timer per *data source*, started only when at least one visible widget needs it (reference-counted by kind), stopped when none does:

| Source | How | Interval | Used by |
| :--- | :--- | :--- | :--- |
| time | `clock` service + `shell/clockfmt.luau` | 1 s (only if a seconds clock is shown) else 15 s | clock, dateBadge, dayProgress, worldClock |
| weather | `location.luau` + Open-Meteo `curl` (as the top bar) | 15 min | weather, forecast |
| system | `/proc/stat` twice (0.4 s), `/proc/meminfo`, `df` (the fixed dashboard command), `/sys/class/thermal` | 3 s | systemMonitor, uptime |
| media | `media` service | event | mediaControls, visualizer, lyrics |
| battery / network / audio | services | event | battery, controls |
| notifications | `notification_history` service | event | newsTicker-like "recent" |
| calendar | local `.ics` files or `khal list` if installed (§7 risk 3) | 5 min | monthCalendar, upcoming |
| notes / todo | `~/.config/beskar/widgets/notes.json` | on edit | notes, todo |
| timers | `after`/`every`, state in widgets.json | 1 s while running | timers |
| screen time | focus time per app from `niri msg -j event-stream` | event | screenTime (later) |

Facts are written once and all slots of that kind read them (no per-slot polling).

### 3.4 Persistence (`~/.config/beskar/widgets.json`)

```json
{
  "version": 1,
  "grid": { "snap": true, "size": 32 },
  "outputs": {
    "HDMI-A-1": {
      "1920x1080": [
        { "id": "w1", "kind": "clock",   "size": "medium", "x": 120, "y": 96,  "locked": false, "opacity": 100, "opts": { "seconds": false } },
        { "id": "w2", "kind": "weather", "size": "small",  "x": 120, "y": 288, "opts": {} },
        { "id": "s1", "stack": ["media", "lyrics"], "size": "medium", "x": 520, "y": 96 }
      ]
    }
  },
  "presets": { "mine": [ ... ] }
}
```

Keyed by **output name and resolution** (like iNiR), so a second monitor or a changed mode never scrambles positions. Written with `sh -c 'printf > tmp && mv tmp file'` (atomic), debounced 400 ms after the last change. Read at start with `cat`.

### 3.5 Input and edit mode

Normal mode: the surface is click-through except each widget's body zone (click → that widget's action: open music panel, open calendar, start a timer...). Right-click a widget → context menu (Edit desktop, Lock, Remove, Size ▸ S/M/L).

Edit mode (`widget_edit` fact, toggled by right-click on the desktop zone is **not** possible because the desktop is click-through, so by: Spotlight `> edit widgets`, the Apple menu item "Edit Widgets…", a keybind, or right-clicking a widget):

- the surface rises to `level: top` while editing, a dismiss zone covers the monitor, the wallpaper dims (`brightness 0.7`), widgets show their chrome (outline, resize handle, ✕, 🔒);
- drag with `drag.dx/dy`; position = start + drag, snapped to the grid in Luau (`round(x / g) * g`), with **magnet guides** (lines drawn when an edge or centre lines up with another widget within 8 px);
- **Undo** stack (last 20 layout snapshots, Ctrl+Z and a button), because iNiR ships "Undo takes back any move";
- the shelf (a second surface, or a `bottom` morph panel like the wallpaper strip) lists every widget by category with a live preview; click or drag adds it at the first free spot (`layout.freeSpot(size)` scans the grid).

---

## 4. Widget catalogue and phasing

Priority = useful on a laptop desktop and cheap to build with what we have.

| Tier | Widgets | Source | Notes |
| :--- | :--- | :--- | :--- |
| **A (Phase 2)** | Clock, Date badge, Weather, Battery, System monitor | clock, `location.luau`, battery, `/proc` | The dashboard's weather and resource code is reused. |
| **B (Phase 3)** | Media controls, Month calendar, Notes, To-do, Uptime, User card | media, `date`/`cal`, files | Media reuses `music.luau`. |
| **C (Phase 5+)** | World clock, Day progress, Timers, Quick controls, Recent notifications, Image / photo, Palette | mixed | Controls = the Control Center tiles. |
| **D (later)** | Visualizer (needs `cava`), Lyrics (lrclib via `curl`), Screen time, Upcoming events | external tools | Skip until a source exists. |
| **Skip** | Mascot, Chaos, Japanese typography, Editorial, Image converter | decor | Not worth the surface area. |

Each widget ships with: manifest entry, one face part, a feed (if any), 1–3 size classes, options (e.g. clock: 12/24h follows the shell, seconds, date; weather: units; system: which meters).

---

## 5. Implementation phases

Each phase ends with a commit + push, `--check` clean, screenshots on both monitors, and an AGENTS.md rule (27+).

### Phase 0: spike (½ day), **decide go/no-go**
- Throw-away `widgets.plm`: background-level surface, `screens: each`, 24 slots × 6 hidden faces. Measure frame time with `--hud` and `cycle` log lines (mean and p99) with 4 and with 20 visible slots; confirm click-through on the wallpaper, drag with `drag.dx`, and that the surface does not steal the top bar's reserve.
- Confirm `level: background` is under windows but above the wallpaper daemon (`awww`).
- Confirm a face can read per-kind facts without per-slot copies.
- **Exit**: frame time < 4 ms added at idle; if not, fall back to the multi-surface design (one named surface per widget, `open:` per kind) and update §3.1.

### Phase 1: skeleton (1 day)
- `widgets.plm/.luau`, `registry.luau`, `layout.luau`, `widgets.json` load/save (debounced, atomic).
- `WidgetFrame` with plate, size classes, springs, position from the model. Two placeholder faces.
- `start.sh` launches the scene; `start.sh widgets edit|reset` commands; permissions (`run: sh`, `say:topbar`, `say:settings`).
- **Verify**: widgets survive a scene restart in the same place; two monitors have independent layouts.

### Phase 2: Tier A widgets (2 days)
- Clock (small/medium/large, uses `clockfmt`, follows `hour12`), date badge, weather (moves the Open-Meteo fetch into `feeds.luau` and the dashboard reads the same facts), battery (hidden on desktops: `present = false`), system monitor (the repaired `/proc` command, ring or bars).
- Feeds are reference-counted: close the last system widget and the poll stops (check with `ps`).
- **Verify**: values match `top`/`free`/`df`; light/dark/accent change repaints everything.

### Phase 3: edit mode (2–3 days)
- `widget_edit` state; surface level switch; dim; chrome; drag move; grid snap (16/32/48/64, cycles from the context menu); magnet guides; resize by size-class cycling (S→M→L via a corner handle: the handle's drag distance picks the class, then the spring animates); lock; remove; **Undo** (20 snapshots).
- Entry points: Apple menu "Edit Widgets…", Spotlight command `> edit widgets` (add to `COMMANDS`), widget right-click, `Super+Shift+W` niri bind. Exit: Esc, Done button, click on dim area.
- Keyboard: `keyboard: exclusive while widget_edit` on the top-level edit copy only (rule 15: one named surface, per-copy `open:`).
- **Verify**: real mouse drags with `wtype`/`ydotool` where available, else `--say ... press`; no widget can leave the screen or sit under the top bar / dock reserve.

### Phase 4: the shelf (2 days)
- `widget_shelf.plm` morph-from-dock panel (reuse the wallpaper strip mechanism, rule 14) listing widgets by category (today / media / system / notes), live thumbnails (same faces drawn at 0.4 scale), search, "added" check.
- Add → `layout.freeSpot`; drag-out-of-shelf is a stretch goal.
- Add the panel to `PANELS`, `IDS`, `exclusive.luau`, `FOCUS_PANELS`.

### Phase 5: Tier B widgets and presets (3 days)
- Media (cover, title, controls, tint from cover), month calendar (grid, today highlighted, click → week row?), notes and to-do (text input faces, saved to `widgets/notes.json`, `input` with `agent: no`), uptime, user card.
- Presets: Glance, Dashboard, Focus, Listening, Bare, plus "Save current as…" and delete. Settings gets a **Widgets** tab: master on/off, preset picker, grid snap, "Reset layout", per-widget options (the registry's `options` list rendered with existing `ToggleRow`/`Seg`/`Chip` components).
- `prefs.json` gains `widgets_on`; the dock/topbar do not change.

### Phase 6: stacks (2 days)
- A slot with `stack = [kinds...]` shows one page; dots at the bottom; wheel or click-dots switch; auto-rotate every N s (paused on hover); the stack owns position/size/lock, pages keep their own options (iNiR's `sharedKeys`).
- Merge: dropping a widget on another in edit mode asks "Stack?"; split from the context menu.
- Slot model gets `page`, `pages`; faces unchanged (the frame just maps `kind` to the current page's kind).

### Phase 7: custom widgets (2–3 days)
- Folder `~/.config/beskar/widgets/<id>/widget.json` + `face.plm` (a `part`). Because pleamar cannot compile a `part` at run time, **custom widgets are templates, not code**: the manifest picks a *template* (`text`, `value+label`, `list`, `image`, `shell-command output`) and gives data from either a command (`run`, interval) or a file. Templates are fixed faces with configurable text/colour/icon.
- Examples shipped in `assets/widget-examples/`: "Command output", "Countdown to date", "Quote of the day (file)".
- Leave "arbitrary code widgets" as a documented non-goal until pleamar supports run-time scene loading (check pleamar changelog; `cloned_repos/pleamar` is the source).

### Phase 8: polish and optional extras (open)
- Lock-screen widgets: a separate `lock:<output>` layout; the lock scene gets 1–3 slots (clock is already there; add media + weather). Needs the lock's `kind: lock` surface to host the same part (parts can be included in both scenes).
- Fullscreen / game pause: hide the scene when a window is fullscreen (`niri msg -j windows`), stop all feeds. Rate-limit with `rate: 30, 5 while idle`.
- Reduced motion (`motion.reduced`), accessibility labels (`describe` friendly names), `inir`-style IPC: `--say widgets "add weather"`, `"preset Focus"`, `"edit"`.
- Hot-reload of `widgets.json` edited by hand (watch with `sys.watch` or mtime poll).

---

## 6. Interfaces (so the pieces fit)

```
-- registry.luau
M.kinds = {
  weather = { id = 3, name = "Weather", icon = "󰖙", tint = "#ff9f0a", category = "today",
              sizes = { "small", "medium" }, default_on = false, feed = "weather",
              options = { { key = "units", type = "seg", values = {"°C","°F"}, default = 1 } } },
  ...
}
-- layout.luau
M.footprint(size)            --> w, h   (176 / 368 on a 16 gap)
M.snap(x, y, w, h, others)   --> x, y, guides   (grid + magnets)
M.free_spot(output, w, h)    --> x, y
M.load(output, w, h) / M.save(output, w, h, list)
M.undo() / M.push_snapshot()
-- feeds.luau
M.need(kind) / M.release(kind)   -- ref-counts a data source; starts/stops its timer
```

Messages (all declared with `->` in `widgets.plm`): `event add_widget -> `, `event remove_widget ->`, `event set_size ->`, `event edit_toggle ->`, `event apply_preset ->`, `event undo ->`.

---

## 7. Risks and mitigations

1. **A fixed slot pool with every face compiled in may be heavy** (24 slots × N faces of hidden geometry). Mitigation: Phase 0 measures it. Fallbacks: (a) fewer slots (12) and faces shared between kinds; (b) one named surface per *kind* with a per-copy `open:` (as rule 15), each kind owning its own slot count.
2. **Background layer vs. wallpaper daemon / window rules.** `awww` draws on its own layer; ours must sit above it. Verify in Phase 0; niri `layer-rule` may be needed for blur behind widgets (check `background-effect`).
3. **Calendar has no source** (already noted). Offer: local `.ics` folder, `khal`, or "no events"; do not ship a fake "Upcoming events".
4. **Edit mode needs the desktop to accept right-click**, but the desktop is click-through by design. Use explicit entry points (menu, Spotlight, keybind), not desktop right-click. Optional: a thin full-screen zone behind the widgets at `level: bottom` only while `widget_edit_hint` is true.
5. **Per-output keys** depend on rule 12 (screen index ↔ output name changes between runs); reuse `topbar.luau`'s `surface N on NAME` parsing, or ask `niri msg -j outputs` and pass the mapping via `say`.
6. **Writes to `widgets.json` from two scenes** (Settings and Widgets) could race. Only `widgets.luau` writes it; Settings sends commands by `say`.
7. **Scope creep.** The 25 iNiR widgets are the catalogue, not the target; ship Tier A+B (≈12) and stop.

---

## 8. Testing and verification checklist

- `./bin/pleamar --check shell/widgets.plm` after every edit; no logic errors in `/tmp/pleamar_widgets.log`.
- Screenshot both monitors (`grim -o NAME`), light and dark, each accent, each size class.
- `ps` shows exactly one `widgets.plm` process; feeds start/stop with their widgets.
- Restart the scene and the whole shell: layout restored; delete `widgets.json`: factory preset appears.
- Edit mode: drag, snap, magnet, resize, lock, remove, undo, shelf add, Esc exit, keyboard goes only to the active monitor.
- Frame cost: `cycle` lines with 0, 6 and 12 widgets (target mean < 6 ms and no p99 spikes on 165 Hz).
- Hide on fullscreen; no polling while hidden.
- Documentation: AGENTS.md rules 27+ (widgets scene, slot pool, feeds, edit mode), README feature list.

---

## 9. Order of work and estimates

| Phase | Output | Time |
| :--- | :--- | :--- |
| 0 | Spike + go/no-go | 0.5 d |
| 1 | Skeleton, persistence, frame | 1 d |
| 2 | Clock, date, weather, battery, system | 2 d |
| 3 | Edit mode (drag, snap, resize, undo) | 2–3 d |
| 4 | Shelf panel | 2 d |
| 5 | Media, calendar, notes, to-do, presets, Settings tab | 3 d |
| 6 | Stacks | 2 d |
| 7 | Template custom widgets | 2–3 d |
| 8 | Lock widgets, fullscreen pause, IPC | open |

First milestone you can see: end of Phase 2 (a clock, weather and system card on the desktop that survive restarts).
