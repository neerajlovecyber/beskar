# Plan 02 — Multi-Page Control Center & Hardware D-Bus Bus

> **Depends on:** Plan 00 (Lifecycle, blocking audit, OverlayHost). Parallel with Plan 01/03 after 00.
> Uses bar right-slot island (`IslandRightPill`) as anchor, but does not block on bar style completion.

## 0. Goal

Port Minflair's multi-page `controlCenter` as the premium hardware control hub: real, non-blocking NetworkManager/BlueZ/UPower/Audio/Backlight/PowerProfiles, with GPUI Kit primitives (never hand-rolled sliders).

## 1. References Inspected

| Area | Upstream source | Files |
|------|----------------|-------|
| ControlCenter UI | `references/minflair` | `Modules/ControlCenter/ControlCenter.qml`, `ControlCenterContent.qml`, `Widgets/*` (QuickSettings, sliders, toggles) |
| Hardware widgets (Pure Rust) | `references/wayle` | `crates/wayle-widgets/src/{audio,network,bluetooth,battery,backlight,power}` — PipeWire/WirePlumber, NetworkManager, BlueZ, UPower patterns |
| D-Bus streams | `references/icebar` | `src/modules/tray.rs`, `src/subscription.rs` (StatusNotifierWatcher, menu streaming, zbus) |
| System tray | `references/minflair` | `Modules/Bar/Widgets/SystemTray/{SystemTray,TrayItem,TrayMenu,TrayMenuItemDelegate}.qml`, `Modules/Bar/Components/SystemTrayGroup.qml` |
| Power/secrets | `references/pleamar` | `src/platform/audio.rs` (Pulse/PipeWire), `src/platform/backlight.rs` |

## 2. Architecture

```
crates/beskar-services/src/
  lifecycle.rs          (from 00)
  audio.rs              (PipeWire/Pulse — already exists, harden to wayle pattern)
  networkmanager.rs     (zbus NetworkManager — scan/connect, non-blocking)
  bluez.rs              (zbus BlueZ — list/pair/connect)
  battery.rs            (UPower — read_state + streaming)
  backlight.rs          (brightnessctl via spawn_blocking, clamp 5-100)
  power_profiles.rs     (powerprofilesctl via spawn_blocking)
  hardware_bus.rs       (facade: subscribe() → HardwareSnapshot for view)

crates/beskar-shell/src/modules/control_center/
  mod.rs                (PanelModule Slot::Right, OverlayHost scrim, Tab state)
  sliders.rs            (gpui_kit::component::Slider — volume + brightness + mic)
  quick_toggles.rs      (gpui_kit::component::Switch — WiFi/BT/DND/Caffeine/Game)
  wifi_list.rs          (Scrollable + List, connect with passphrase Dialog)
  bt_list.rs            (Scrollable + List, pair/connect)
  header.rs             (user avatar + power buttons row)
  footer.rs             (media + vitals footer)
  power_profiles.rs     (profile picker: balanced/performance/power-saver)
```

Panel geometry: fullscreen scrim (Plan 00) + sized inner card `360-420px` wide, bounded `Scrollable` inside, never fixed screen-filling modal.

## 3. Tasks (copy upstream mechanics)

### 3.1 Hardware Bus (deep module)

- Each helper (`NetworkHelper`, `BluetoothHelper`, `AudioService`, `BacklightService`, `BatteryService`) must be `ManagedService` with `Lifecycle` + `RunToken::alive()` loops; D-Bus listeners via `zbus` async, CLI fallbacks via `spawn_blocking` only.
- Provide a single `HardwareSnapshot { wifi, bt, audio, backlight, battery, powerProfile }` signal aggregated by `hardware_bus::SystemHub` or `ControlCenter` entity subscription — no polling in `render`.
- Extract `references/wayle/crates/wayle-widgets/src/*` error handling (Unavailable vs Error, retry backoff) verbatim.

### 3.2 ControlCenter Pages (consume GPUI Kit)

- Use `gpui_kit::component::slider::Slider` for volume/brightness/mic — never `div().on_mouse_drag` progress bars.
- Use `gpui_kit::component::switch::Switch` for WiFi/BT/DND/Caffeine/Game toggles.
- Use `gpui_kit::component::scroll::Scrollable` for wifi/bt lists + `gpui_kit::component::badge::Badge` for status (connected/secured).
- Use `gpui_kit::component::input::Input` + `Dialog` for WiFi passphrase.
- Page navigation via `Tabs` or `Sidebar` + `PageTransitionView` analog (copy `references/minflair/Core/Components/PageTransitionView.qml` spring).

### 3.3 System Tray (if not already complete)

- `SystemTrayGroup.qml` → `crates/beskar-services/src/tray.rs` already streams via `zbus`; ensure `PanelHost` slot `Right` hosts its `TrayMenu.qml` popover with correct D-Bus menu unpacking from `references/icebar`.

## 4. Acceptance

- [ ] Volume/brightness sliders use `gpui_kit::Slider`, toggles use `Switch`, lists use `Scrollable` — no hand-rolled primitives.
- [ ] WiFi scan/connect and BT pair/connect work without blocking UI (60 FPS while scanning); UPower battery updates stream.
- [ ] ControlCenter opens as scrim + card from right island, mutual-exclusive with NotificationsCenter (same `Slot::Right`), `Escape` + backdrop closes.
- [ ] No `Command::new("nmcli"|"bluetoothctl"|...)` outside `spawn_blocking`/`zbus`.
- [ ] `cargo check && cargo test` green.

## 5. Non-goals

- Notifications toasts/center, clipboard, wallpaper — Plan 03. Dashboard/music/capture — Plan 04.
