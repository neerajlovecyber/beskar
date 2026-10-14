# Plan 03 — Notification Stack, Clipboard, Wallpaper

> **Depends on:** Plan 00 (OverlayHost, Lifecycle, Theme). Parallel with 01/02 after 00.

## 0. Goal

Port the 3 focused overlays that share the `Slot::Focus` mutual-exclusion: freedesktop Notifications (toast layer + center), Clipboard history, and Wallpaper selector with dynamic palette engine.

## 1. References Inspected

| Area | Upstream | Files |
|------|----------|-------|
| Notifications | `references/minflair` | `Modules/Notifications/*`, `Modules/NotificationCenter/*`, `Core/Services/NotificationService.qml`, `Core/Services/NotificationData.qml`, `Modules/Bar/Components/BaseNotifLayer.qml`, `Modules/Bar/Styles/{Convex/ConvexNotifLayer,Island/IslandNotifLayer}.qml` |
| Clipboard | `references/minflair` | `Modules/Clipboard/Clipboard.qml`, `ClipboardContent.qml`, `Components/ClipboardItemDelegate.qml`, `Core/Services/ClipboardService.qml` |
| Wallpaper | `references/minflair` | `Modules/WallpaperSelector/*`, `Core/Services/WallpaperManager.qml`, `Scripts/theme/generate_theme.py` (Wallpaper HSL engine), `Scripts/theme/apply_cursor.py` (reference for palette apply) |
| Aesthetics/Theme | `references/suzuha`, `references/amane` | `src/theme.rs`, `src/theme/hsl.rs`, `src/liquid.rs`, `shaders/` (HSL wallpaper palette, glass acrylic) |
| GPUI Kit lists | `references/gpui-kit` (crate `gpui_kit`) | `crates/component/src/{list,scroll,virtual_list,input,dialog}` |

## 2. Architecture

```
crates/beskar-services/src/
  notifications.rs   (freedesktop Notifications D-Bus: notify-send + zbus, toast stream + history)
  clipboard.rs       (wayland-data-control via arboard, maxItems cap like SettingsService.clipboardMaxItems)
  watcher.rs         (wallpaper file watcher via notify crate — already exists)
  palette.rs         (HSL palette extraction from wallpaper — extract suzuha/amane)

crates/beskar-shell/src/modules/
  notification_center/mod.rs  (PanelModule Slot::Right — center list, groups, clear/dismiss)
  clipboard/mod.rs            (PanelModule Slot::Focus — VirtualList 8-12 items, pin/favorite)
  wallpaper_selector/mod.rs   (PanelModule Slot::Focus — grid + preview + apply via swww/feh spawn_blocking)
  tray_menu/                  (reuse if notif tray integration needs it)

crates/beskar-ui/src/widgets/
  notification_row.rs (toast row + center row variant)
  clipboard_row.rs    (delegate with icon + text + category badge)
```

All 3 Focus panels use Plan 00 scrim + bounded `Scrollable`/`VirtualList`, never bare fixed windows. Notification toasts are the bar-adjacent inline layer (`ConvexNotifLayer`/`IslandNotifLayer`) — not a separate overlay window.

## 3. Tasks

### 3.1 Notifications (toast layer + NotificationCenter)

- D-Bus: `org.freedesktop.Notifications` via `zbus` (copy `references/icebar` patterns). Keep in-memory history (cap 100), expose `subscribe()` for bar toast + center.
- Bar toast: `crates/beskar-shell/src/bar/view.rs:118-121` already syncs `sync_notification_toasts`; ensure toast expands center pill width `180→360` via spring and auto-expires (Minflair `BaseNotifLayer` timed dismiss).
- Center: `Scrollable` list of grouped notifications, `Badge` for count, `Button` (ghost) for Clear All / Dismiss, `EmptyState` when none. Match `NotificationCenter` QML grouping.

### 3.2 Clipboard

- Service: `arboard` + `wayland-data-control` poll, capped at `SettingsService.clipboardMaxItems` (100 default), dedup by content hash, persist optional.
- UI: `VirtualList` (8-12 visible, windowed like `launcher` max 8), `Input` filter bar (`ThemedSearchBar` analog), `List` row with `14px` icon + text truncate, pin/favorite action. `Enter` pastes, `Delete` removes. All via `gpui_kit::component::list::List` / `VirtualList` + `Scrollable`.

### 3.3 Wallpaper Selector & Palette Engine

- Selector: `PanelModule Slot::Focus` grid of thumbnails (copy `WallpaperSelectorContent.qml` layout), search `Input`, preview, Apply. Execution via `spawn_blocking` (`swww` preferred, `feh` fallback — already `wallpaper_selector/mod.rs:51-54` but must be moved off render into service).
- Palette: extract dominant HSL from wallpaper (`references/suzuha/src/theme/hsl.rs` + `references/amane`), generate `bg/bg_secondary/fg/muted/border/accent/complementary` tokens for `beskar-theme`, expose via `ThemeEngine::set_palette`. Background `hsla(240,0.16,0.08,0.95)` obsidian glass + specular top border `hsla(0,0,1.0,0.14)` like PowerMenu spec.

## 4. Acceptance

- [ ] New notification briefly expands bar center pill + shows toast inline; NotificationCenter lists history grouped, Clear/Dismiss work, center is `Slot::Right` exclusive with ControlCenter.
- [ ] Clipboard `Focus` exclusive with Launcher/PowerMenu/Wallpaper; `VirtualList` filtered by typing, `Enter`/`Delete` correct, no render-thread blocking on `arboard`.
- [ ] Wallpaper grid previews, Apply changes wallpaper via non-blocking command and updates theme palette (HSL) without restart.
- [ ] All lists use `Scrollable`/`VirtualList`, inputs use `gpui_kit::Input` — no hand-rolled scroll.
- [ ] `cargo check && cargo test` green.

## 5. Non-goals

- Dashboard/music/capture — Plan 04. Lockscreen/settings — Plan 05.
