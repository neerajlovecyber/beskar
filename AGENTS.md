# Beskar Shell - Agent Notes

Beskar is a Wayland desktop shell for **niri**, built with **pleamar**: a Rust runtime that draws a declarative scene
language (`.plm`) and runs sandboxed Luau logic (`.luau`). There is no Rust code to write here. Everything lives in
`shell/`. Use the `pleamar` skill when touching any `.plm` / `.luau` file; `./bin/exp/pleamar --docs reference | logic`
prints the language and the Luau API of the installed runtime (the upstream docs are no longer copied into `docs/`).

Older design notes and finished plans are in `docs/archive/`. Current references: `docs/UI_STANDARDS.md`,
`COMPONENT_LIBRARY.md`, `RENDERING_NOTES.md`, `SESSION_MENU.md`, `TIMERS.md`, `WEATHER.md`, `PERSONAL_CONTENT.md`.

## Processes

The shell is **two pleamar processes** under one supervisor (`shell/supervise.sh`, started by `shell/start.sh`):

| Process | What it is |
| :--- | :--- |
| `shell/desktop.plm` | `import scene` of everything below, in ONE process: the frame, the panels, Settings, the owners, the wallpaper and the widgets. |
| `shell/lock.plm` | The lock screen, its OWN process on purpose: if the desktop crashes while the session is locked there must still be a locker. Never test it against the live session (use a nested niri). |

On demand: `shell/capture.plm` (the capture picker; `start.sh capture-ensure` starts it, it quits itself when idle).
Four processes became two in 2026-11 (about 620 MB RSS became 370 MB); the price is a few more slow frames while a panel
morphs, because the wallpaper and widgets are repainted with it. To go back, revert that commit.

| Scene | Role |
| :--- | :--- |
| `topbar.plm` + `topbar.luau` | **The frame**: one full-screen surface per monitor (`screens: each`) that draws the glass (ring, three top islands, dock island) AND the content of every panel. Panels are parts it includes (`common/cc_panel.plm`, `updates_panel.plm`, `info_panels.plm`, `timer_panel.plm`, `personal_editor.plm`, `dock_panels.plm`, `dialog_panels.plm`, `window_panels.plm`, `notice_view.plm`); their logic is loaded by `topbar.luau` through ONE panel client (`cc.luau`, `updates_panel.luau`, `info_panels.luau`, `dock_panels.luau`, `dialog_panels.luau`, `window_panels.luau`, `session_menu.luau`). |
| `keys.plm` + `keys.luau` | The keyboard and the panels' text fields (see **Keyboard**). Imported AFTER the frame. |
| `panels.plm` + `panels.luau` | Owner of which panel is open (`open`, `cur`, `panel_h`, `panel_mon`, `open_screen`, `fresh`). Everyone else asks with typed events (`Panels.show`, `close`, `height`…). |
| `system.plm` + `system.luau` | The system services held ONCE (battery, network, audio volume/muted, brightness, media with the player controls). Others read `System.bat.percent`, `System.net.online`, `System.sound.volume`, `System.is_playing`… and never declare those services themselves. |
| `weather`, `activities` (the timer), `personal` (notes / to-dos) | Headless owners, the only writers of their data (see **Data owners**). |
| `notifications.plm` + `notif.luau` | The notification server and owner (history in `~/.local/share/pleamar/notifications/`, DND, quiet rules). It has NO surface of its own: the frame draws the centre and the banner by reading its models by name. |
| `settings.plm` + `settings.luau` | The Settings window (a single surface that follows `Panels.panel_mon`). |
| `wallpaper.plm`, `widgets.plm` | Per-monitor surfaces (`level: background` / `bottom`) inside the desktop process. |
| `common/` | Shared: `theme.plm` (part), `geometry.plm`, `icons.plm`, `ui.plm`, `buttons.plm`, `calendar.plm`, `scroll.plm` (libraries), the panel parts above, `morph_core.plm`, `palette.plm`. |
| `shell/*.sh` | `start.sh`, `supervise.sh`, `migrate.sh`, `smoke.sh`, `rig.sh`, `verify.sh`, `release.sh`, `runtime.sh`, `appthemes.sh`, `nightlight.sh`, `idle.sh`. |
| `beskar`, `install.sh` | The user-facing command (doctor / install / uninstall / update) and the `curl | sh` entry. |
| `bin/exp/pleamar` | The runtime: pleamar 0.8.0-exp.24 (pinned and built by `shell/runtime.sh`; `bin/` is git-ignored). |

`--say <file stem>` still reaches every scene (`--say topbar …`, `--say settings …`, `--say widgets …`). Facts inside the
desktop are `Topbar.x`, `Settings.x`… and a scene writes only its OWN facts; owners declare typed events for the others.
Old scene names (`controlcenter`, `infopanels`, `dockpanels`, `dialogs`, `windows`, `overlays`, `music`, `dashboard`,
`updates`, `polkit`, `welcome`) no longer exist: their panels are parts of the frame.

## Tools

```
./bin/exp/pleamar --check shell/desktop.plm   # compile; run after EVERY edit. Check desktop.plm, not a scene alone
                                              # (a `uses` scene's names are not resolved alone)
./bin/exp/pleamar --say <stem> describe       # what a running scene shows (zones, texts, positions)
./bin/exp/pleamar --say <stem> "emit open_panel 4"
grim -o HDMI-A-1 out.png                      # screenshot a monitor
shell/rig.sh start|say|key|shot|log|stop      # this tree's desktop in a nested niri (see below)
shell/verify.sh [--no-rig]                    # THE GATE before every commit
```

**Rig and gate (use these, not the live desktop).** `rig.sh` runs this tree's desktop in a nested niri with its own session
D-Bus, pleamar sockets, HOME and data folder, stubbed system commands and no polkit agent (`BESKAR_RIG=1`). `verify.sh`
compiles every process, runs every `tests/*.lua`, the UI guard (`shell/check-ui.py`) and the full smoke INSIDE the rig.
The rig has ONE output: multi-monitor behaviour must be checked on real monitors. For screenshots make the nested window
fullscreen (`niri msg action fullscreen-window --id`) and restart the rig's scenes so surfaces are 1920x1080. Its nested
niri config must be multi-line KDL (`{ a; }` on one line is rejected and niri falls back to defaults).

Scene sockets are in `$XDG_RUNTIME_DIR/pleamar/`, logs in `/tmp/pleamar_<name>.log`. Restart the desktop by killing its
pleamar pid (the supervisor brings it back; never `pkill -f` from the same shell line: it matches your own command).

**The live shell runs from the working tree and hot-reloads every edited `.plm` / `.luau`.** Do structural work in a
`git worktree` (`bin/` is ignored, so symlink it: `ln -s ../beskar/bin bin`), run `verify.sh` there, then merge. A half-applied
edit once put both bars on the second monitor. **Never start the shell from an agent session directly**: it dies with the
session's cgroup. Use `systemd-run --user --unit=beskar-shell --remain-after-exit --collect shell/start.sh restart` and run
the new unit by its absolute path. Never run `start.sh stop` / `./beskar uninstall` in a test (they kill the live shell).

## Keyboard

- **The keyboard belongs to the `Keys` scene.** pleamar delivers keys and typing only to the FIRST copy of a `screens: each`
  surface (upstream k4ditano/pleamar#156, fixed on pleamar 0.7.31 but not yet in an exp release), so the frame never got a key
  on the second monitor. `Keys` has ONE surface that follows the open panel's monitor (`screens: Panels.panel_mon`), takes the
  keyboard while a panel is open and is click-through except its fields. It forwards every key the panels use to the frame as
  an event (`on key Down` -> `Topbar.k_down`, `on keyup Return` -> `Topbar.ku_return`, focus loss -> `Topbar.k_blur`); the
  frame's rules are `on k_down while Panels.cur == N and screen.index == 0`. It owns the text fields (`query`, `clip_q`,
  `wb_name`, `password`, `wq`, `pe_draft`, `pe_new_task`, `tm_duration`, `wifi_pw`), drawn where the frame draws the panels;
  a field's Enter is `Topbar.sub_<field>`. The frame's logic reads and writes them with `require("keys_text")` (reads
  `Keys.<field>`, writes `Keys.set_text`, watch `on("text:Keys.<field>")`). Focus a field with `fld_req = N; fld_seq = fld_seq + 1`
  in a rule or `require("topbar_hooks").focus("name")` in Luau. A new key in a panel: its forwarder in `keys.plm` plus the
  `event k_… ->` in `topbar.plm`. `keys.plm` is imported AFTER `topbar.plm`. **Never add a second surface to the Topbar scene**
  (pleamar then moves surface 0 and drops the frame copy on the second monitor). Remove the whole scene when upstream ships #156
  in an exp release (revert the Keys commit and watch the issue).
- **Conventions.** Up/Down (and Tab / Shift+Tab) move a focus ring through items, Left/Right through strips, sliders (5 % steps)
  and pages, Home/End and PageUp/PageDown where a list scrolls, Enter / Space activate, Esc goes back a level and then closes.
  Focus starts fresh each time a panel opens. Enter / Space act on key RELEASE and only if the press was seen while the panel was
  up (the Enter that opened a panel from Spotlight must not fire the item under the ring). A focused text field swallows Home,
  End, Delete, Enter and modifier arrows: panels with a search field use Ctrl+Up / Ctrl+Down for first / last and `on submit`
  for Enter.
- **Sectors.** A panel with several rows of controls moves by sector: Up/Down change sector, Left/Right move inside it, one focus
  ring, Enter presses. The wallpaper strip is the model (`wall_sec` 0 tabs, 1 strip, 2 transition, 3 actions; `wall_item`;
  handlers `wall_sec_step`, `wall_item_step`, `wall_activate` in `dock_panels.luau`). A ring that belongs to a sector is hidden
  while another sector has the focus.
- **One focus ring**: `stroke: focus_stroke; color: ring_c` at 100 % everywhere (`ring_c` in `theme.plm`, `focus_stroke` in
  `geometry.plm`), never `focus_c` (a palette colour), `accent_c` or a literal width. `SelectCard` takes `ui_ring_c`. A selection
  that is not keyboard focus is `RowFrame`.
- **Settings keyboard**: Up/Down walk the sidebar tabs (`emit pick_cat(tab ± 1)`) while no sub-flow (look, shortcut editor, quiet
  apps, display Keep/Revert, pin editor, reset review) or the search field has the keys; Esc closes. The controls INSIDE a tab are
  still pointer-only (idea: build on `settings_catalog.luau` + `setting_reveal`).
- The frame's logic cannot emit an event to ITSELF (not even unqualified): use `require("topbar_hooks").call(name, v)` /
  `.emit("Topbar.x", v)`, and register direct-call handlers with `Hooks.handlers[name] = fn` (`topbar.luau` records every handler
  it registers there; a module-scoped `on` is not recorded).

## Panels

- `Panels` owns ONE `cur` / `open`: opening a panel replaces the one shown, and `panels.luau` ends with
  `require("exclusive")("panels")` (`shell/exclusive.luau`, its list is `settings`, `panels`, `topbar`) which closes the OTHER
  windows (Settings, the power menu). A scene that says to another needs `say:<scene>` in its `permissions`.
- A panel opens ONLY through the frame (it picks the monitor): `--say topbar "emit open_panel N"` or `open_island_panel(name)`.
  `cur` ids: 1 Control Center, 2 notifications, 3 today, 4 spotlight, 5 wallpapers, 6 clipboard, 9 music, 10 widget bar,
  11 session dialog, 12 polkit, 15 weather, 16 updates, 21 app switcher, 22 window overview, 24 welcome, 25 personal, 26 timer.
- The frame grows the island's glass from facts (`cp_*`, `rp_*`, `bp_*`: on / screen / w / h) through springs and in the same
  `Shell` component places the panel's `…Content()` component over it: `show: Panels.cur == N and <spring> > 0.01 and
  <island>_screen == screen.index`, `move:` to the panel's origin, opacity from the spring and the glass having arrived, a `clip box`
  following the glass. Content is laid out at its FINAL place and never moved while the glass grows (bottom panels use
  `Panels.panel_h`, not the animated height). Write `Panels.open`, `Panels.cur`, `Panels.fresh` (`open` / `cur` / `fresh` alone
  in the frame mean the POWER MENU's).
- A new panel: metadata in `panels_data.luau`, a part with its facts and `…Content()` included by `topbar.plm`, a placement group in
  `Shell`, its id in the panel client in `topbar.luau`, its `.luau` returning `function(module)` / the module body
  (`module("name", function(panel, opened, shown, closed) … end)`; `panel.height(h)`, `panel.width(w)`, `panel.keep()`), its text
  field in `keys.plm`, its id in the frame's `keyboard:` condition if it takes keys, and `shell/smoke.sh` + `shell/verify.sh`.
- Click outside closes a panel (the frame's `outside_zone`, declared before every button zone, emits `outside_click` ->
  `Panels.outside_close`, except `panel.keep()` ones: welcome, widget bar, polkit). Every modal / dock panel closes with Esc, a
  click outside or losing focus.
- A merged panel brings its PERMISSIONS with it: every `run:` command and `services:` entry the old scene declared must be in
  `topbar.plm`'s `permissions` (a missing one fails only at run time).
- Saved files are stored per scene folder (`~/.local/share/pleamar/<file stem>/`). Merging a scene moves them: `shell/migrate.sh`
  (idempotent, run by `supervise.sh`) copies them. Notifications stays separate for that reason.
- A text `input` inside a component is scoped to it (logic cannot read it) and `on change` cannot watch a text: fields are
  declared loose at scene level (now in `keys.plm`).
- One panel's design language (dock panels): HEADER at the top (`PanelHeader`), content in the middle, the SEARCH FIELD always at the
  BOTTOM (`PanelSearch`); never a search field at the top of a dock panel.
- Settings opened FROM a panel goes through `topbar.luau`'s `open_it`, which closes the panel and starts Settings 260 ms later.
- Closing is quick, opening calm: the island springs `cv` / `bv` / `rv` are `layer`s (`up` ~calm, `down` ~quick).
- The dock island's glass width while a bottom panel opens uses the VISIBLE dock width (`dw_shown`), or an auto-hidden dock made
  a narrow tower and a jump.

## Look and UI conventions

- **Colours come from `shell/common/theme.plm` and the LOOK is owned by Settings.** The facts (`dark_mode`, `skin`, `accent`,
  `accent_auto`, `hour12`, `pal_*`) belong to the Settings scene (saved in `~/.config/pleamar_shell.json`; preferences in
  `~/.config/beskar/prefs.json`). A scene in the desktop says `uses scene "settings.plm" as Settings`, includes
  `common/theme_owner.plm` then `common/theme.plm` and uses the tokens (`accent_c`, `ok_c`, `danger_c`, `focus_c`, `ink_c`,
  `ink_sub`, `card_fill`, `item_solid`, `bg_color`, `on_accent`, `scrim_c`, `btn_fill`, `switch_off`, `field_bg`, `sel_bg`,
  `bar_color`…), never a hex value. The lock and capture scenes (own processes) include `common/theme_facts.plm` and Settings tells
  them by `say` (`THEMED` in `settings.luau`). To change the look, ask Settings (`say settings "emit set_dark_mode 1|0"`,
  `"emit choose_skin N"`): never write its facts. Never test a preference (`bar_style_pick`…) on the live shell without putting
  the value back: they SAVE.
- **Shared parts**: `common/ui.plm` (Plate, Switch, ToggleRow, Btn, Pill, Seg, Chip, Slider, RowFrame, EmptyState, PanelHeader,
  PanelSearch, SectionLabel, KeyHint, Divider, ScrollBar, SelectCard, CardBg), `buttons.plm` (IconButton / IconTextButton),
  `calendar.plm` (MonthGrid), `scroll.plm` (ScrollFade, ScrollChrome). Use them instead of drawing a toggle, button, chip, slider or
  header by hand; pass the scene's theme tokens through their named `ui_*` colour arguments. Library defaults must not reference
  aliases (pass `ink_c` explicitly). The libraries are `import`ed ONCE (not `include`d: two scenes in one process cannot both
  declare `Sym`, `Plate`…). New rendering libraries are `library … strict` with explicit inputs and declare no surface, service,
  model or timer.
- **Geometry** is standardised: read `docs/UI_STANDARDS.md`; `common/geometry.plm` is the source (radii `r_s` 8 · `r_m` 12 · `r_l`
  16 · `r_xl` 24, text sizes `t_title` 15 · `t_body` 13 · `t_sub` 12 · `t_cap` 11.5 · `t_micro` 10.5, `focus_stroke` 2). Run
  `python3 shell/check-ui.py`.
- **Icons**: ONE font and ONE component (`common/icons.plm`): `Sym(g, x, y, size, color)` / `SymTile(...)`; a glyph that changes with a
  fact or sits in a model is a `text` with `family: "JetBrainsMono Nerd Font Mono"`. Never a bare glyph `text`.
- **Anything longer than its room scrolls, with a bar**: a layout with `view: w, h` (and `step:`), named so `.scroll` / `.content` feed
  `ScrollBar`. A layout declared inside a component's `children` cannot have its `scroll` set from a scene-level rule; when keys must
  move a list (Spotlight) scroll it yourself (a `fact` target + `prop` spring + `column { at: x, y - sc }` in a `clip box`).
- Glass over a bright wallpaper needs `smoke` (dark) / `milk` (light) and a higher `tint`.
- Hover = a spring that adds 8-22 % of the accent or `item_bg`; selection = `RowFrame`.
- **Never leave a `wave`, `spin` or `blink` running in a scene that is always up** (they keep the scene painting at the monitor's
  rate for ever). Advance a phase from Luau only while something plays (`m_ph`, `wave_kick`). Measure with
  `./bin/exp/pleamar --report <scene> --seconds 10` (it writes a report file into `$HOME`: delete it).

## pleamar and Luau pitfalls

1. **Right-click quits** a scene's process unless SOME rule in it uses `on press right`. Every scene with zones needs one
   (an empty `on press right zone { }` is enough).
2. **`screens: each` compiles up to FOUR copies** of a surface (one per possible monitor, even with two). Loose `prop` / `follow` /
   `fact` on it are shared by all copies, so put drawing, props and follows inside a `component` instantiated once; per-monitor
   data comes from a `model` indexed by `$screen`. Which copy is on which output changes between runs: never assume
   `screen.index` follows sorted output names; `topbar.luau` reads the startup log (`surface N on NAME … Topbar copy 1`, in
   `$BESKAR_DESKTOP_LOG` or `/tmp/pleamar_desktop.log`) and builds `mon` / `ws_list` from it; `widgets.luau` does the same for
   its cards. `screen.N.name` texts do not exist when a scene is imported.
3. **Imported-scene rules.** A surface imported BEFORE the frame renumbers the frame's per-monitor copies (import order in
   `desktop.plm`: frame, then Keys, Wallpaper, Widgets). Two components cannot share a name across scenes (`Card` is `WCard` in
   widgets). `service … { outputs: outs }` lines that map a list into a model fail when imported (use plain watchers and fill the
   model yourself). `screens:` does not find a scene's OWN `text` once several scenes are imported, so the monitor texts are owned
   by `Panels` (`Panels.panel_mon`, `Panels.toast_mon`) and others read them by full name. Declare every event the logic receives
   with `->`. A plugin cannot emit to itself. A fact changed by Luau does not come back through `on("fact:…")` in the same plugin.
   A numeric `emit` payload travels as an f32 (ids stay below 2^24); event payloads are numbers only; a rule can `emit` with at
   most ONE argument (put the rest in facts first).
4. **Content-sized shapes**: name a layout (`row left_row {…}`), read `left_row.width`, chase it with a `~calm` spring. Shapes in one
   `body` that use `blend:` melt into each other. `center` in a layout is horizontal only; use `anchor: center middle`.
5. **Input**: on a full-screen surface only zones catch the mouse; everything else is click-through. Component-scoped names are
   mangled (`hit#Shell7#DockItem36`): `--say … describe` shows them.
6. **Luau sandbox**: no `io` / `os`; use `run(cmd, args, cb, opts)`, `spawn(...)` (needs an `on_line` function), `json.decode`, and
   declare every command and service in the scene's `permissions { run: …, services: … }` (commands by their first words, `date` is
   not `sh`; a refused command throws and stops the rest of the file). Never block the logic thread. `wl-copy` must be redirected to
   `/dev/null` or `run` never returns.
7. **Tray**: one listener; only the logic owns it (`sys.watch("tray", fn)`); never also declare `service tray`.
8. **niri**: the `workspaces` service is Hyprland-only: use `niri msg -j workspaces|windows|outputs|casts` and `niri msg -j event-stream`.
   The 6 px ring is kept clear of windows by `struts` in `~/.config/niri/config.kdl`. Nothing user- or machine-specific is
   hard-coded (name, home, monitors, weather location and time zone come from the system).
9. **Closed-panel ghosts on niri/AMD**: pleamar's own partial-damage buffers retained faded content; `supervise.sh` sets
   `PLEAMAR_SWAPCHAIN=1` for the desktop process (`BESKAR_DESKTOP_SWAPCHAIN=0` opts out). Keep it in startup. Details:
   `docs/RENDERING_NOTES.md`. Do not keep closed panels permanently mapped to mask it.
10. **Smoothness**: absolute slow-frame counts depend on GPU load (the same commit gave 0 and 240 an hour apart): compare versions
    back to back, with `PLEAMAR_TIMING=1` (`painted, of 300 rounds` per surface). Measure GPU memory from `/proc/<pid>/fdinfo`
    (`drm-memory-gtt` + `drm-memory-vram`), not from `pleamar --report`.
11. **Pinned runtime**: `shell/runtime.sh` (VERSION) builds the tag into `bin/exp/pleamar-<version>` and links `bin/exp/pleamar`.
    Run it with `bash`. Upstream status: exp.24 is the newest exp; the keys-per-copy (#156), lock-on-every-monitor and generic-font
    fixes are on pleamar's 0.7.x line only.

## Feature notes

- **Settings** (`settings.plm` + `.luau`): a sidebar with search and 8 tabs (Appearance, Displays, Sound, Notifications, Menu Bar &
  Dock, Shortcuts, General, Night Light & Power; Wi-Fi, Bluetooth and wallpaper choice live in the Control Center and the picker).
  Components (`Card`, `ToggleRow`, `SliderRow`, `Seg`, `Chip`, `Btn`, `ActionRow`…) keep tabs short. `settings_catalog.luau` lists
  searchable controls (tab, y, h). Settings OWNS the prefs: the bar's (`pref_seconds`, `pref_weather`, `pref_tray`, `pref_dock_auto`,
  `bar_style`) are read by the frame as `Settings.pref_x`; only what is not read by name is pushed by `say` (`push_prefs`).
  Looks (saved appearance profiles, `settings_looks.luau` + `appearance_profiles.luau`) stay; the "Portable setup" export/import
  (about 5,600 lines) was removed. A display scale / mode the user KEEPS is saved by `shell/displays.py` and restored at login.
- **Colour engine**: "Colours from the wallpaper" picks the picture's dominant colour with ImageMagick and runs matugen
  (`pal_style` 0-3 Tonal / Vibrant / Neutral / Soft), keeps accent / second colour / surface for both modes in
  `~/.config/beskar/palette.json` and sends the `pal_*` facts to every themed scene. New colours must use the theme tokens.
- **Other apps wear the theme** (`shell/appthemes.sh`, `assets/matugen/`): `pref_apps` runs `appthemes.sh setup` (one include line per
  app, containing `beskar/themes`, no inline comments) and `apply`, rendering kitty / alacritty / ghostty / foot / gtk.css / qt5ct
  schemes into `~/.config/beskar/themes/`. Test with a fake `$HOME`, never by editing the user's terminal configs.
- **Top bar styles**: `bar_style` 0 Notch, 1 Strip, morphing through `prop s_strip ~calm`. Notification banner, volume / brightness /
  microphone OSD, timer done, charging, screenshot, privacy alerts and music are CARDS in the centre pill, arbitrated by priority in
  `topbar.luau` (`card_open(id, ms, {glyph, title, sub, value, tone, thumb})`; banner > osd > timer done > charging > screenshot >
  privacy > ambient (timer ring, recording dot, music cover and wave bars) > clock). Panel 25 keeps priority 100.
- **Notifications**: the centre is capped at 720 px with a native `view:` list; keep all waiting rows in logic and render at most 16
  around the scroll position (`list_scrolled` is a scalar event). Group by app (`group_apps`) builds `rows` (kind 0 card, 1 stack, 2
  header). A notification's own buttons (`actions`, at most two) are drawn in the centre; a press sends
  `Notifications.invoke_action(id * 10 + n)`; declare the button zones AFTER the card's own zones.
- **Spotlight** (`spotlight.luau`, `spotlight_search.luau`, `spotlight_files.luau`, `actions.luau`): entries `{ name, sub, kind, icon, run }`
  (0 app, 1 calculator, 2 web search, 3 command), a small parser for sums (no `loadstring`), `g|ddg|yt|gh|w|maps <text>`, `> command`,
  `/` files, `@` windows, `?` Settings pages. History is bounded and holds no window titles or queries. Checks: `lua tests/spotlight.lua`.
- **Wallpaper** is painted by pleamar (`wallpaper.luau` + the picker in `dock_panels`): `~/.config/beskar/wallpaper`, `wp_a` shown, `wp_b`
  revealed over it (`wp_fx` 0 circle, 1 fade, 2 wipe), `reserve: -1` so it covers the bar's strip. Nothing may call `awww`. A wallpaper
  change adds GPU memory pleamar never frees; pre-shrinking does not help.
- **Widgets** (`widgets.plm` + `.luau`, kinds and presets in `widgets_data.luau`, toolbar = the widget bar panel 10): `model ws` (id, scr,
  kind, sz, x, y), a `WCard` per record, NO slot pool, `max 16`. `widgets.luau` is the only writer of `~/.config/beskar/widgets.json`
  (cards per output NAME, one write queue, atomic, debounced). Edit mode: dim, drag (grid cells of 160 px with a 16 px gap), size
  cycle, remove, Undo (20 snapshots), presets. New kind: a face component + `group { show: w.kind == N }` in `WCard`, an entry in
  `KINDS`, its data. Do not create a per-day component in widgets (the `max 16` expansion multiplies it).
- **Data owners**: `weather` (one location in `~/.config/beskar/location`, Open-Meteo, 15 min freshness, cache, typed `Weather.ensure` /
  `refresh` / `choose_location` / `use_ip`; widgets read a snapshot file), `activities` (the timer: epoch deadlines in `timer.json`,
  typed `Activities.*`, `timer_state.luau`), `personal` (notes and to-dos, `content.json`, `Personal.*` events,
  `personal_client.luau` resyncs by revision). Never start a second poller in a view. Docs: `WEATHER.md`, `TIMERS.md`,
  `PERSONAL_CONTENT.md`; checks `lua tests/weather.lua|timer.lua|personal.lua`.
- **Session menu** (panel 11): opened via `Topbar.open_session` or `start.sh power-menu|session`; Super+Shift+Q / Super+X; arrows / Tab;
  Return / space on release; confirmation starts on Cancel. Tests capture every command; never trigger real lock / power actions.
  `docs/SESSION_MENU.md`.
- **Lock** (`lock.plm`): `kind: lock`, its `size` is a box centred on each monitor and `screen.width` is not usable; every event needs
  `->`. No bypass. Recovery from a text console: `XDG_RUNTIME_DIR=/run/user/$UID WAYLAND_DISPLAY=wayland-1 bin/exp/pleamar --say lock "fact locked false"`.
  Lock when away: `shell/idle.sh <minutes>` (hypridle).
- **Capture** (`capture.luau`): frozen `grim` picture, Region / Window / Screen, `magick` crop, `wf-recorder`; started on demand under a
  `flock`; the bar's red dot stops a recording.
- **Polkit agent** (panel 12): the logic's `sys.watch("polkit")` makes the process the session's agent (one per session: never start a
  second, nested test shells included); `faillock --user $USER --reset` after tests.
- **Updates** (panel 16): `checkupdates` + the AUR helper, "Update all" opens ONE terminal with one sudo prompt (never pkexec per package).
- **Night light / power / privacy**: `shell/nightlight.sh` (wlsunset), `powerprofilesctl`, privacy dots polled every 4 s (camera by `fuser`,
  mic by `pactl`, screen cast by `niri msg -j casts`).
- **Window panels** (app switcher 21, overview 22): windows from `niri msg -j windows` mapped to pleamar's `thumbnails` service
  (`thumbnails.want` / `live`, released when closed); a card falls back to the app icon when the compositor exports no frames.
- **Install, doctor, update, welcome**: `./beskar` (`doctor`, `install [--yes --dry-run --no-packages]`, `uninstall`, `update`). Packages in
  `REPO_PKGS` / `AUR_PKGS`; the Bibata cursor (`beskar-look.kdl`) and Papirus icons only when the user has none; it writes
  `~/.config/niri/beskar.kdl` and one `include` line with a `.beskar-bak` backup, and leaves a config that already mentions `start.sh`
  alone. Test with a throwaway `HOME` and a multi-line KDL config. First run: `welcome` opens 7 s after start while
  `~/.config/beskar/welcome-done` is missing.
- **Releases**: `shell/release.sh vX.Y.Z` runs `verify.sh`, tags, pushes and creates the GitHub release (versions below 1.0 are
  pre-releases). `install.sh` is the `curl | sh` entry. MIT licence; the wallpapers are iNiR's and keep their credit.

## Working style

- Reuse before writing; port the idea from `references/` (inir, minflair, capsule, pleamar), not their code.
- Verify visually: restart, `grim` both monitors, look. `--check` passing does not mean it looks right.
- Every change passes `shell/verify.sh`. Do not commit unless asked. A tool that is missing is named in the panel (`cliphist`,
  `checkupdates`), never a generic "nothing here".
- When adding to `git`, never `git add -A` in a worktree that has a `bin` symlink unless `.gitignore` covers it (it does now).
