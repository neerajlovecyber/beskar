# Plan 05 — LockScreen, Settings GUI, PackageManager & Final QA

> **Depends on:** Plans 00-04 complete. This plan owns the standalone windows and the final acceptance matrix.

## 0. Goal

Close Minflair parity: lock screen, full Settings GUI (8 sub-pages), keybinds/package-manager launchers, and a verifiable QA/perf sweep that guarantees no hanging/ugly regressions.

## 1. References Inspected

| Area | Upstream | Files |
|------|----------|-------|
| LockScreen | `references/minflair` | `Modules/LockScreen/*`, `Core/Services/DisplayProfileService.qml` (caffeine/gameMode) |
| Settings GUI | `references/minflair` | `Modules/Settings/Settings.qml`, `Settings/BarSettings/*`, `Settings/{Personalization,Wallpaper,Effects,InputAndClipboard,Mouse,Window,SystemInfo,Integrations}/*`, `Core/Components/{AppSidebar,SidebarNavRow,SettingRowTemplate,ThemedSelect,ThemedSlider,ThemedSearchBar,ThemedTooltip,PageTransitionView}.qml` |
| Settings prefs | `references/minflair` | `Core/Services/SettingsService.qml` (40 fields, debounced JSON to `~/.cache/quickshell/settings_prefs.json`, cursor/font apply) |
| Wayle settings pattern | `references/wayle` | `crates/wayle-settings/*`, `crates/wayle-ipc/*` (macOS/GTK style prefs app layout, IPC between settings app and shell) |
| PackageManager | `references/minflair` | `Modules/PackageManager/*`, `Core/Services/{UpdateService,SystemInfoService}.qml` |
| Keybinds | `references/minflair` | `Modules/KeybindsCheatSheet/*` (standalone window `minflair_keybinds`) |
| Design system | `.agents/skills/gpui-kit-design-guides` | spacing, hierarchy, interaction states, overlay motion |

## 2. Architecture

```
crates/beskar-shell/src/modules/
  lock_screen/mod.rs + view.rs        (Layer::Overlay, KeyboardInteractivity::Exclusive,
                                        TOP|BOTTOM|LEFT|RIGHT scrim — entire display, clock + auth)
  settings/mod.rs                     (STANDALONE window: NOT PanelHost scrim — AppState.standaloneWindows)
    + subpages: bar, personalization, wallpaper, effects, input_clipboard, mouse, window, systeminfo
  — keybinds are a standalone popover/dialog (gpui_kit Dialog), not a panel overlay
  — package manager is a standalone window/panel per Minflair PackageManager

crates/beskar-core/src/config.rs      (extend ShellConfig to cover SettingsService fields if missing:
                                        fontFamily/fontScale, cursorTheme/cursorSize, clock24h/seconds/showDate,
                                        clipboardMaxItems, enabledKbLayouts, githubUsername — behind feature flags)

crates/beskar-services/src/
  auth.rs    (logind PAM / unlock — already exists)
  logind.rs  (session lock listener — already in bar/view.rs:204-212 toggle_lockscreen)

Standalone-window routing (from references/minflair/Core/Services/AppState.qml:29,53-54):
  isStandaloneWindow(id) ∈ {"minflair_settings","minflair_keybinds","packagemanager"}
  → WindowKind::LayerShell or normal window, NOT OverlayHost scrim. Settings GUI has its own app_id.
```

## 3. Tasks

### 3.1 LockScreen (exclusive focus)

- Fullscreen LayerShell window: `Layer::Overlay`, `Anchor::TOP|BOTTOM|LEFT|RIGHT`, `KeyboardInteractivity::Exclusive`, covers all displays with blurred/dimmed wallpaper + centered clock + unlock input (`gpui_kit::Input` + `Button`).
- Trigger: `listen_logind_lock` (`bar/view.rs:204`) + `ControlCenter` lock button + idle timeout (reuse `DisplayProfileService` caffeine flag to suppress idle).
- Render via `lock_screen/view.rs` (already exists) — polish to Minflair `LockScreen` styling (obsidian card, lavender accent, `ThemedShadow`).

### 3.2 Settings GUI (standalone window, 8 pages)

- Window: `AppState.qml:29` `standaloneWindows` — not an overlay scrim. Use `gpui_kit::component::sidebar::Sidebar` + `Tabs` / `SidebarNavRow` for left nav (`BarSettings`, `Personalization`, `Wallpaper`, `Effects`, `Input&Clipboard`, `Mouse`, `Window`, `SystemInfo`, `Integrations`) mirroring `Settings.qml` hierarchy. Each row uses `SettingRowTemplate.qml` → `gpui_kit` `Label` + `Switch`/`Select`/`Slider`.
- Persist: reuse `ShellConfig::{load,save}` + `notify_config_changed` already wired to bar; extend config file to cover missing SettingsService fields or keep a second `settings_prefs.json` compat file if needed — writes debounced 100ms (already `SettingsService.qml:207-263` saveTimer pattern).
- Components to use (never hand-roll): `Select`/`Combobox` for dropdowns, `Slider` for scales, `Input` for text, `ColorPicker` for accent, `Dialog/Sheet` for confirmations, `Tooltip` for hints, `Badge/Breadcrumb` for status.
- IPC: `wayle-ipc` pattern if settings app is a separate binary; otherwise in-process `subscribe_config()`.

### 3.3 PackageManager & Keybinds (standalone)

- `Modules/PackageManager/*` → standalone window or card reachable from Dashboard `UpdatesCard` button; real `checkupdates`/`paru -Qua`/`yay -Qua` via `spawn_blocking` (`crates/beskar-services/src/updates.rs:82-102` already wrapped).
- `Modules/KeybindsCheatSheet/*` → `Dialog` or Help panel populated from compositor keybinds (`beskar-compositor` if Niri/Hyprland exposes).

### 3.4 Final QA & Perf Matrix (every plan's invariants verified together)

| Area | Criterion |
|------|-----------|
| Workspaces | Click + wheel switch active capsule `24×8` lavender immediately; `WindowsChanged` dot opacity `0.65/0.22` reflects window open/close without lag |
| Convex Bézier | Seamless flares at 1.0/1.25/1.5/2.0 fractional scale, border `rgba(255,255,255,0.08)` + ThemedShadow, no boxy artifacts |
| Island morphing | Center pill `180→320→360` spring-animated on media/notification; expansions in-place, not detached windows; 60 FPS during motion, 300ms idle settle |
| ControlCenter | `Slider`/`Switch`/`Scrollable` only; NetworkManager/BlueZ/UPower non-blocking while scanning |
| Overlays | Focus slot mutual-exclusion, Right slot (ControlCenter↔NotificationsCenter) mutual, backdrop+Escape close only owning slot, scrim fullscreen |
| Blocking | 0 `Command::new` outside `spawn_blocking`/async across `crates/beskar-shell` + `crates/beskar-services` (grep audit) |
| Config | Changing `bar_style`/`theme_preset`/bar slots hot-swaps without restart; `ThemeEngine::set_preset` follows signal |
| Build | `cargo check` + `cargo test` green on all workspace crates |

## 4. Acceptance

- [ ] LockScreen fullscreen exclusive grabs focus, shows clock, unlocks via correct auth (already `auth.rs`), `logind` lock triggers it.
- [ ] Settings standalone window with sidebar nav (8 pages), each row using GPUI Kit `Switch/Select/Slider/Input`; persist round-trips and hot-swaps bar/theme.
- [ ] PackageManager standalone window lists updates via non-blocking checks; Keybinds cheat sheet accurate.
- [ ] QA matrix above passes on a niri session with fractional-scale display.
- [ ] `cargo check && cargo test` green; no regressions in Plans 00-04.

## 5. Non-goals

- New modules beyond Minflair parity. This plan is the parity gate — subsequent work is polish/perf, not scope expansion.
