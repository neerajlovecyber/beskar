# Beskar Shell - Agent Notes

Beskar is a macOS / iNiR-style Wayland desktop shell for **niri**, built with **pleamar**: a Rust
runtime that draws a declarative scene language (`.plm`) and runs sandboxed Luau logic (`.luau`).
There is no Rust/GPUI code to write here. Everything lives in `shell/`.

Use the `pleamar` skill when touching any `.plm` / `.luau` file.

## Layout

| File | What it is |
| :--- | :--- |
| `shell/topbar.plm` + `topbar.luau` | The frame: one full-screen glass silhouette (ring round all four edges, three top islands, bottom dock island). Scene name `MacTopBar`. |
| `shell/{control_center,spotlight,widgets,apple_menu,osd,settings,lock,session,capture,appswitcher,clipboard}.plm` | One scene per panel, each with its own `.luau` where it needs logic. |
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

Scene sockets are named after the file stem in `/run/user/1000/pleamar/`. Logs: `/tmp/pleamar_<name>.log`.
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
10. **One panel at a time.** A panel's logic ends with `require("exclusive")("<scene>")` (`shell/exclusive.luau`), which closes the other panels when it opens. A new panel must be added to `PANELS` there and get `say:<scene>` permissions both ways.
11. **Names.** Component-scoped names are mangled (`hit#Shell7#DockItem36`); `--say` can see them via `describe`.

## Working style

- Reuse before writing: the reference repos in `references/` (inir, minflair, capsule, pleamar, …) show
  island geometry, morphing and tray handling worth adapting, but port the *idea* into `.plm`, not their code.
- Verify visually: restart the scene, `grim` both monitors, look at the result. `--check` passing does not mean it looks right.
- Do not commit unless asked.
