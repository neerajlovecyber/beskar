# Beskar Shell - Agent Notes

Beskar is a macOS / iNiR-style Wayland desktop shell for **niri**, built with **pleamar**: a Rust
runtime that draws a declarative scene language (`.plm`) and runs sandboxed Luau logic (`.luau`).
There is no Rust/GPUI code to write here. Everything lives in `shell/`.

Use the `pleamar` skill when touching any `.plm` / `.luau` file.

## Layout

| File | What it is |
| :--- | :--- |
| `shell/topbar.plm` + `topbar.luau` | The frame: one full-screen glass silhouette (ring round all four edges, three top islands, bottom dock island). Scene name `MacTopBar`. |
| `shell/{control_center,spotlight,notifications,dashboard,wallpapers,settings,lock,session,capture,appswitcher,clipboard}.plm` | One scene per panel, each with its own `.luau` where it needs logic. |
| `shell/common/palette.plm` | Shared colour library. |
| `shell/start.sh` | Starts / stops every scene (one pleamar process each). |
| `bin/pleamar` | The runtime. |

## Tools

```
./bin/pleamar --check shell/x.plm          # compile only; run after EVERY edit
./bin/pleamar --docs reference | logic     # the language and the Luau API
./bin/pleamar --say <scene-stem> describe  # what a running scene shows (zones, texts, positions)
./bin/pleamar --say <scene-stem> "press <zone> right"
grim -o HDMI-A-1 out.png                   # screenshot a monitor
```

Scene sockets are named after the file stem in `$XDG_RUNTIME_DIR/pleamar/`. Logs: `/tmp/pleamar_<name>.log`.
Restart one scene by killing its PID (never `pkill -f` / `pgrep -f` from the same shell line: the
pattern matches the invoking command) and relaunching `bin/pleamar --no-hud --scene shell/x.plm`.

## Rules learned the hard way

1. **Right-click quits.** pleamar quits a scene's process on a right-click unless *some* rule in it
   uses `on press right`. Every scene with zones needs one (an empty `on press right zone { }` is enough).
2. **`screens: each` and props.** Loose `prop`/`follow`/`fact` on a per-monitor surface are shared by
   all copies, so a `follow` reading a layout's `.width` gets 0. Put the drawing, props and follows
   inside a `component` and instantiate it once. Per-monitor data comes from a `model` indexed by
   `$screen` (`mon.$screen.active`).
3. **Content-sized shapes.** Name a layout (`row left_row {…}`) and read `left_row.width`; chase it
   with a `~calm` spring. Shapes in one `body` that use `blend:` melt into each other (smooth union).
4. **Layout vs. anchor.** `center` in a layout is horizontal only; use `anchor: center middle` to centre both ways.
5. **Input.** On a full-screen surface only zones catch the mouse; everything else is click-through.
6. **Glass over bright wallpaper** needs `smoke` (dark) / `milk` (light) and a higher `tint`.
7. **Luau sandbox.** No `io` / `os`. Use `run(cmd, args, cb, opts)`, `spawn(...)`, `json.decode`, and
   declare every command and service in the scene's `permissions { run: …, services: … }` (commands by
   their first words, e.g. `"niri msg"`). Never block the logic thread.
8. **Tray.** The backend has one listener: only the logic owns it (`sys.watch("tray", fn)` → `model.icons`).
   Do not also declare `service tray` in the scene.
9. **niri.** The `workspaces` service is Hyprland-only: use `niri msg -j workspaces|windows|outputs`
   and `niri msg -j event-stream`. The 6 px ring is kept clear of windows by `struts` in
   `~/.config/niri/config.kdl`.
   Nothing user- or machine-specific is hard-coded: the user name, home, monitors, weather location and
   time zone all come from the system (`location.luau`, `$HOME`, `niri msg`, `date`).
10. **One panel at a time.** A panel's logic ends with `require("exclusive")("<scene>")` (`shell/exclusive.luau`), which closes the other panels when it opens. A new panel must be added to `PANELS` there and get `say:<scene>` permissions both ways.
11. **Colours come from `shell/common/theme.plm`.** It is a `part`: put `include "common/theme.plm"` as the first line of a scene and use its tokens (`accent_c`, `ok_c`, `danger_c`, `focus_c`, `ink_c`, `ink_sub`, `card_fill`, `item_solid`, `bg_color`, …) instead of hex values. It declares the `dark_mode`, `skin` and `accent` facts; Settings broadcasts them to every scene and saves them to `~/.config/pleamar_shell.json`.
12. **Which screen is which monitor.** With `screens: each` the compositor decides which copy is on which output, and it changes between runs. Never assume `screen.index` follows sorted output names: `topbar.luau` reads pleamar's startup log (`surface N on NAME`) to learn it and builds every per-monitor model (`mon`, `ws_list`) from that.
13. **Panels that grow out of an island: one reusable mechanism.** The frame (`topbar.plm`) draws all their glass: one shape per island (`power_m` left, `center_m`, `right_m`) driven by facts (`cp_*`, `rp_*`: on / screen / w / h) through springs, so each island stretches down into its panel as one piece of glass. A panel scene draws ONLY content: it is `screens: each`, includes `common/morph.plm` (declares `open`, `open_screen`, `panel_h`, the fade, the dismiss zone; the scene sets `mp_sw`/`mp_sh` first and wraps its content in `group { show: mp_here; move: X, -2; opacity: mp_fade }`) and its logic does `local panel = require("panel")("<name>")` then `panel.height(h)`. `panel.luau` reports open/close/height to `topbar.luau`, which arbitrates islands shared by two panels (Control Center and notifications share the right one). To add a panel: give it an id in `PANELS` (topbar.luau) and `IDS` (panel.luau), emit an event from its button that calls `open_island_panel(name)`, add it to `exclusive.luau`. Always open panels through the frame: it picks the monitor.
14. **The bottom island too.** Spotlight and the wallpaper strip grow out of the DOCK island (`bp_*` facts, `bv`/`bpw`/`bph` springs and the `dock_island` shape in `topbar.plm`: it grows up, the dock icons fade, a dock hidden by auto-hide is forced up while one is open). They are `screens: each`, anchored `bottom`, include `common/morph.plm`, and place their content with `move: X, <surface height> - ph` so it stays attached to the bottom.
15. **Separate panels open on ONE monitor, with a keyboard.** A non-`each` surface appears on every monitor, and a `keyboard: … while` condition cannot tell the copies apart (the panel then never got keys). So a panel that is its own window (Spotlight, clipboard, wallpapers, Settings, session dialog, app switcher) uses ONE NAMED surface with `screens: each` and a per-copy `open:` (`open: (open or seen > 0.02) and open_screen == screen.index`), `keyboard: exclusive while open`, and carries its dismiss zone and main group (and the dismiss rules) INSIDE the surface block. A closed copy is not mapped, so only the target monitor takes the keyboard. Do NOT use `screen.index` (or a `let` built on it) inside such a surface's content: it reads 0 there; the `open:` expression is the only place it works. Never toggle these panels directly: send `--say topbar "emit open_panel N"` (numbers in `topbar.luau`'s `FOCUS_PANELS`), which sets `open_screen` to the monitor with the focus and toggles. Test keys for real with `wtype -k Right` (a `--say … emit` bypasses the keyboard). Not done yet this way: osd, capture, lock.
16. **Volume / brightness feedback is in the centre pill too** (`kind = 2`, owner id 8 in `topbar.luau`; the old floating `osd` scene is gone): `sys.watch` on `audio` and `brightness` shows it for any change, whoever made it; keys go through `start.sh vol-up|vol-down|mute|bright-up|bright-down` → `emit osd_*`. A dashboard open keeps it away; it takes the island from a banner.
17. **A notification appears INSIDE the centre pill.** The banner is a `kind = 1` panel (id 7) of the centre island in `topbar.luau`'s arbiter: the frame grows the island and fades the clock (`cp_kind`, `bnv`); `notifications.plm`'s `banner` surface (negative top margin so it starts above the bar's strip) draws only the card; `notifications.luau` shows it for a few seconds on a fresh notification, keeps it while hovered, opens the centre on a click, and stays away when Do Not Disturb is on, the centre is open or a real panel (the dashboard) owns the island. Other transient things (volume / brightness, music, recording) should use the same pattern.
19. **Music lives in the centre pill.** `topbar.luau` watches `media`: while a player has a title, the clock pill gets a circular cover and three `wave` bars (flat when paused); a click opens `music.plm`, a morph panel (id 9, island `cp`) with cover, title, seekable progress and prev / play / next, driven by `music.luau` (`media.*` calls, position carried on every second). Declare every event the logic receives with `->` in `topbar.plm`, or it never arrives.
20. **The centre groups by app.** `notifications.luau` builds `model rows` (kind 0 card, 1 stack, 2 header of an open group; `h` is each row's height, `live_h` their sum): an app with several waiting shows one stack (the newest, two edges behind it, `+N`), a click opens it, "Show less" closes it, × dismisses the whole app. The banner still reads `notices`.
21. **Capture and recording** (`capture.luau`) only use `run` / `spawn` (no `os.execute`; `spawn` needs an `on_line` function, not nil). While `wf-recorder` runs, the clock pill shows a red dot and the time (`rec_on` / `rec_time` facts in `topbar.plm`, set through `say`); a click there sends `emit toggle_record` to the capture scene.
18. **Names.** Component-scoped names are mangled (`hit#Shell7#DockItem36`); `--say` can see them via `describe`.

## Working style

- Reuse before writing: the reference repos in `references/` (inir, minflair, capsule, pleamar, …) show
  island geometry, morphing and tray handling worth adapting, but port the *idea* into `.plm`, not their code.
- Verify visually: restart the scene, `grim` both monitors, look at the result. `--check` passing does not mean it looks right.
- Do not commit unless asked.
