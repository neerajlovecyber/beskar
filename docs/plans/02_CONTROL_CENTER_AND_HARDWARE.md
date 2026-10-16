# Plan 02 — Multi-Page Control Center & Hardware D-Bus Bus

> **Depends on:** Plan 00 (Lifecycle, **Animator**, **LayerShell dynamic sizing**, blocking audit, OverlayHost). Parallel with Plan 01/03 after 00.
> Uses bar right-slot island (`IslandRightPill`) as anchor, but does not block on bar style completion.
> **Rev 2 — Capsule-Native:** QML `ControlCenter.qml` → Rust `Satellite` OSD overlay engine. Copy `references/capsule`, don't translate QML widgets.

## 0. Goal

Port Minflair's multi-page `controlCenter` as the premium hardware control hub: **non-intrusive floating Satellite OSDs** for Wifi/Bluetooth/Audio/Tray/Calendar that sit beside the bar (not as fullscreen scrims), plus real non-blocking NetworkManager/BlueZ/UPower/Audio/Backlight/PowerProfiles, with GPUI Kit primitives.

Capsule's `Satellite` is the proven pattern: at most **2 panels** (Left + Right), newest evicts oldest on same side, `SatelliteLayout::new` auto-falls back to `Below`, measured content height centers vertically on the capsule, `SatelliteAnimator` easeOutCubic `16*(1-progress)` slide. Beskar adapts this verbatim but keeps its `PanelHost Slot::Right` mutual-exclusion as fallback for narrow viewports.

## 1. References Inspected

| Area | Upstream source | Files (with line ranges) |
|------|----------------|--------------------------|
| **Satellite overlay engine** | **`references/capsule`** | **`crates/app/src/capsule/satellite/mod.rs:1-270`** (`SatelliteId{Calendar,Wifi,Bluetooth,Audio,Tray}`, `Satellite{panels: Vec<Panel{id,side,animator}>}`, `next_side`, `transition(id,open,duration,side)` retain-same-side / newest-eviction, `advance`, `layout(viewport,capsule,gap,measured) -> SatelliteVisual{layout:SatelliteLayout,progress,open}`, `Capsule::toggle_satellite/set_satellite_open/close_satellite/transition_satellite` with `SatelliteLayout::new` destination + `AppState.network rescan_wifi/start_bluetooth_scan` + `compositor.get_frame_duration` loop), **`crates/app/src/capsule/satellite/animator.rs:1-58`** (`SatelliteAnimator{progress,start,target,started_at,duration}`, `transition(open,duration,now)` `duration.mul_f32(|target-start|)`, `advance` ease `1-(1-t)^3`, `open/progress`), **`crates/app/src/capsule/satellite/layout.rs:1-77`** (`SatelliteLayout::new(viewport,capsule,desired,gap,preferred,progress) -> {bounds,content_size,side}`, `Side{Left,Right,Below}`, `centered_y`) |
| **Satellite widget surfaces** | **`references/capsule`** | **`crates/app/src/capsule/widgets/satellite/mod.rs`**, **`crates/app/src/capsule/widgets/satellite/surface.rs`**, **`crates/app/src/capsule/widgets/satellite/calendar.rs:WIDTH/HEIGHT`** (`Calendar WIDTH/HEIGHT`, `Audio 320×300`, default `320×400`), **`crates/app/src/capsule/widgets/dashboard/details/{mod,audio,connectivity,tray}.rs`** (Audio output card, Wifi networks, BT devices, Tray menu — reused inside Dashboard satellite panels) |
| **Dashboard satellite wiring** | **`references/capsule`** | **`crates/app/src/capsule/module/dashboard.rs:195-226`** (`set_satellites`, `measure_satellite`, `satellite_heights`, `SatelliteVisual`), **`crates/app/src/capsule/widgets/dashboard/details/mod.rs`** |
| Hardware widgets (Pure Rust) | `references/wayle` | `crates/wayle-widgets/src/{audio,network,bluetooth,battery,backlight,power}` — PipeWire/WirePlumber, NetworkManager, BlueZ, UPower, brightnessctl patterns (kept for Beskar service layer) |
| System tray D-Bus | `references/icebar`, `references/capsule` | `src/modules/tray.rs`, `crates/app/src/capsule/widgets/dashboard/details/tray.rs`, `services::SniItem` |
| Power/secrets | `references/pleamar` | `src/platform/audio.rs`, `src/platform/backlight.rs` |

**Do not translate `references/minflair/Modules/ControlCenter/*Widgets/*` QML into Rust.** Those files are superseded by `capsule/satellite` + `capsule/widgets/dashboard/details`.

## 2. Architecture

```
crates/beskar-services/src/
  lifecycle.rs          (from 00)
  audio.rs              (PipeWire/Pulse — harden to wayle pattern, expose via SystemStatus)
  networkmanager.rs     (zbus NetworkManager — scan/connect, non-blocking, rescan_wifi/start_bluetooth_scan hooks)
  bluez.rs              (zbus BlueZ — list/pair/connect)
  battery.rs            (UPower — read_state + streaming)
  backlight.rs          (brightnessctl via spawn_blocking, clamp 5-100)
  power_profiles.rs     (powerprofilesctl via spawn_blocking)
  hardware_bus.rs       (facade: subscribe() → HardwareSnapshot for view; mirrors capsule AppState.network/system/power)

crates/beskar-shell/src/
  satellite.rs          <- NEW: port of capsule/satellite/{mod,animator,layout}
                          SatelliteId, SatelliteAnimator, SatelliteLayout, Satellite
                          + SatelliteVisual, Side — copy verbatim (see §3.1)
  modules/control_center/
    mod.rs              <- Dashboard-embedded control hub (Capsule pattern) OR standalone Satellite host
                          Owns Satellite entity, toggles via toggle_satellite(Bluetooth/Wifi/Audio/Calendar)
                          Only active when Dashboard module is current (like capsule/mod.rs:175 guard)
    satellite_host.rs   <- Satellite overlay container: layout(viewport,capsule,gap,measured) → visuals,
                           SatelliteLayout::new per visual, measured content heights, vertical centering
    details/
      audio.rs          <- copy capsule/widgets/dashboard/details/audio.rs (sink picker, volume slider)
      connectivity.rs   <- copy capsule/widgets/dashboard/details/connectivity.rs (wifi list + passphrase, bt list)
      tray.rs           <- copy capsule/widgets/dashboard/details/tray.rs (SNI tray Activate/Menu)
      calendar.rs       <- copy capsule/widgets/satellite/calendar.rs (month grid)
    sliders.rs          <- gpui_kit::Slider for volume/brightness/mic (if not covered by details/audio)
    quick_toggles.rs    <- gpui_kit::Switch for WiFi/BT/DND/Caffeine/Game (or Dashboard quick toggles)
    header.rs           <- user avatar + power buttons row (if keeping ControlCenter header)
    footer.rs           <- media + vitals footer (if keeping)

  // Alternative mapping if Beskar keeps ControlCenter as standalone Right-slot overlay:
  // satellite.rs still required — PanelHost Slot::Right switches to Satellite layout when viewport wide,
  // falls back to fullscreen scrim card (360-420px, Scrollable) when narrow (Side::Below branch).

crates/beskar-ui/src/widgets/
  satellite.rs          <- re-export or thin wrapper over beskar-shell::satellite::SatelliteLayout math
                          for reuse in bar/orbit if needed
```

**Geometry contract (from 02 perspective):**

- Viewport = `window.viewport_size()`; capsule/bar bounds = `window_state::visible_bounds(viewport, animator.size(), margin, location)` (Plan 00).
- Gap = `Orbit::satellite_gap(px(config.ui.gap))` or `px(config.ui.gap).max(12)*2 + ORB_SIZE*2 + …` analogue — copy `orbit/state.rs:206-208`.
- Each `SatelliteId` declares `size(): Size<Pixels>` — `Calendar  WIDTH×HEIGHT`, `Audio 320×300`, others `320×400` (`capsule/satellite/mod.rs:30-39`).
- `SatelliteLayout::new(viewport, capsule, id.size(), gap, preferred_side, progress)` returns `{bounds, content_size, side}` with `Left`/`Right`/`Below` fallback; `progress` drives `offset 16*(1-progress)` slide.
- Panels vertically centered: `centered_y(capsule, measured_height.min(maximum), viewport.height)` where `measured` is actual content height tracked via `DimensionTracker` or `measure_satellite` (`capsule/module/dashboard.rs:209-226`).
- Max 2 panels: `[Left, Right]` — `next_side(id)` reuses closed side else evicts oldest on preferred side (`capsule/satellite/mod.rs:74-93`).

## 3. Tasks (copy upstream mechanics)

### 3.1 Satellite Engine (deep module — copy Capsule verbatim)

- **Create `crates/beskar-shell/src/satellite.rs`** (or `crates/beskar-ui/src/satellite.rs` + re-export):
  Copy exactly (adapt `services::AppState` → `beskar-services::HardwareBus` / `beskar-core::config` only where touching `AppState`):

  1. `crates/app/src/capsule/satellite/layout.rs:1-77` → `SatelliteLayout`, `Side`, `centered_y`:
     ```rust
     pub enum Side { Left, Right, Below }
     pub struct SatelliteLayout { pub bounds: Bounds<Pixels>, pub content_size: Size<Pixels>, pub side: Side }
     impl SatelliteLayout { pub fn new(viewport: Size<Pixels>, capsule: Bounds<Pixels>, desired: Size<Pixels>, gap: Pixels, preferred: Side, progress: f32) -> Self { /* gap max(0), width min(viewport.width) max(1), left_space/right_space vs width, pick side, target_y Below vs capsule.origin.y, height min(viewport.height-target_y), progress offset 16*(1-progress) with Left=-, Right=+, Below center-clamped */ } }
     pub fn centered_y(capsule: Bounds<Pixels>, height: Pixels, viewport_height: Pixels) -> Pixels { (capsule.origin.y + (capsule.size.height - height)/2).clamp(px(0),(viewport_height-height).max(px(0))) }
     ```
  2. `crates/app/src/capsule/satellite/animator.rs:1-58` → `SatelliteAnimator`:
     ```rust
     pub struct SatelliteAnimator { progress: f32, start: f32, target: f32, started_at: Option<Instant>, duration: Duration }
     impl SatelliteAnimator { pub fn new() -> Self; pub fn progress(&self)->f32; pub fn open(&self)->bool; pub fn transition(&mut self, open: bool, duration: Duration, now: Instant) { /* advance, target 1/0, duration.mul_f32(|target-start|), started_at Some(now), advance */ } pub fn advance(&mut self, now: Instant)->bool { /* eased 1-(1-t)^3, progress = start+(target-start)*eased */ } }
     ```
  3. `crates/app/src/capsule/satellite/mod.rs:11-171` → `SatelliteId`, `SatelliteVisual`, `Satellite`:
     ```rust
     pub enum SatelliteId { Calendar, Wifi, Bluetooth, Audio, Tray{bus:String,path:String} }
     impl SatelliteId { pub fn title_key(&self)->&'static str; fn size(&self)->Size<Pixels> { Calendar WIDTH×HEIGHT, Audio 320×300, _ 320×400 } }
     pub struct SatelliteVisual { pub id: SatelliteId, pub layout: SatelliteLayout, pub progress: f32, pub open: bool }
     pub struct Satellite { panels: Vec<Panel{id: SatelliteId, side: Side, animator: SatelliteAnimator}> }
     impl Satellite {
         pub fn new() -> Self;
         pub fn open(&self)->bool;
         pub fn contains(&self, id: &SatelliteId)->bool;
         pub fn maximum_size()->Size<Pixels> { size(px(320),px(400)) }
         fn next_side(&self, id: &SatelliteId)->Side { /* same id → same side; find first free Left/Right; else oldest open side; else Left */ }
         fn transition(&mut self, id: SatelliteId, open: bool, duration: Duration, side: Side) { /* if open retain same side's other, move existing to end (newest), push new Panel if missing, set side + animator.transition */ }
         fn advance(&mut self, now: Instant)->bool { /* for panel in panels running|=animator.advance, retain open||progress>0 */ }
         pub fn layout(&self, viewport: Size<Pixels>, capsule: Bounds<Pixels>, gap: Pixels, measured: &[(SatelliteId,Bounds<Pixels>)])->Vec<SatelliteVisual> { /* filter progress>0, SatelliteLayout::new per panel, clamp height to min(viewport.height, id.size.height), center y via measured height or 72, max progress side Below skip */ }
     }
     // + Capsule/BeskarBar integration fns: toggle_satellite, set_satellite_open, close_satellite, transition_satellite
     //   with SatelliteLayout::new destination recompute + AppState.network rescan_wifi/start_bluetooth_scan + duration 180 open /130 close + compositor.get_frame_duration loop
     ```

- **Tests:** copy `capsule/satellite/mod.rs:271-443` (`panels_fill_both_sides_and_replace_the_oldest`, `reopening_a_closing_panel_makes_it_the_newest`, `a_closed_side_is_reused_without_evicting_the_other`, `opening_and_closing_panels_preserves_the_others`, `one_panel_per_side_is_centered_on_the_capsule`) + `layout.rs:80-151` (`preferred_side_falls_back_only_when_it_cannot_fit`, `panels_fit_and_reveal_from_the_nearest_edge`) + `animator.rs:60-91` (`reversing_preserves_position_and_finishes_without_idle_frames`, `zero_duration_opens_and_closes_immediately`). Gate on `cargo test satellite`.

- **Adaptation seams:**
  - `services::AppState` → `beskar-services::HardwareBus` + `beskar-core::config::ShellConfig`. `language.get(key)` title keys → keep or map to Beskar i18n; not blocking.
  - `compositor.get_frame_duration()` → `beskar-compositor::CompositorBackend::frame_duration()` or fallback `Duration::from_millis(16)`.
  - `state.calendar.reset_to_today()` / `state.network.rescan_wifi()` / `start_bluetooth_scan()` → wire to `HardwareBus` methods; if not yet available, stub with `spawn_blocking` + `zbus` in `beskar-services`.

### 3.2 Hardware Bus (deep module — same as before, now feeds Satellite)

- Each helper (`NetworkHelper`, `BluetoothHelper`, `AudioService`, `BacklightService`, `BatteryService`) must be `ManagedService` with `Lifecycle` + `RunToken::alive()` loops; D-Bus listeners via `zbus` async, CLI fallbacks via `spawn_blocking` only.
- Provide a single `HardwareSnapshot { wifi, bt, audio, backlight, battery, powerProfile }` signal aggregated by `hardware_bus::SystemHub` or `ControlCenter` entity subscription — **no polling in `render`**. Satellite `transition_satellite` triggers `rescan_wifi`/`start_bluetooth_scan` on open (Capsule pattern `capsule/satellite/mod.rs:232-236`), not on render.
- Extract `references/wayle/crates/wayle-widgets/src/*` error handling (Unavailable vs Error, retry backoff) verbatim.
- **Non-blocking fix:** ensure Audio `Sink` selection, Wifi `SelectWifi`/`ConnectWifi`/`ScanWifi`, Bluetooth `BluetoothDevice` dispatch via `DashboardModule::dispatch` pattern (`capsule/module/dashboard/actions.rs` + `capsule/widgets/dashboard/details`) uses `services::spawn_tokio` / `spawn_blocking`, never `Command::new` in `render`.

### 3.3 Satellite Panels (consume GPUI Kit + Capsule details)

- **Reuse Capsule detail widgets verbatim where possible:**
  - `crates/app/src/capsule/widgets/dashboard/details/audio.rs` → `beskar-shell/src/modules/control_center/details/audio.rs` (volume Slider, sink list via `HardwareSnapshot.audio`, mute toggle).
  - `crates/app/src/capsule/widgets/dashboard/details/connectivity.rs` → `details/connectivity.rs` (Wifi SSID list + signal, passphrase `Input` + `Dialog`, BT device list + pair/connect).
  - `crates/app/src/capsule/widgets/dashboard/details/tray.rs` → `details/tray.rs` (SNI `TrayActivate` / `TrayMenu`).
  - `crates/app/src/capsule/widgets/satellite/calendar.rs` → `details/calendar.rs` (month grid, `Month(i8)` nav).

- **GPUI Kit mapping (replaces QML `QuickSettings`/`ThemedSlider`/`ThemedSearchBar`):**
  - `gpui_kit::component::slider::Slider` for volume/brightness/mic — never `div().on_mouse_drag` progress bars. Capsule's `DashboardAction::Brightness(u32)` + `Sink(String)` + `DimensionTracker` for slider bounds (`capsule/module/dashboard.rs:70-78`) maps to `Slider` + `DimensionTracker` if keeping Capsule slider; else `gpui_kit::Slider`.
  - `gpui_kit::component::switch::Switch` for WiFi/BT/DND toggles (or `DashboardAction::Wifi/Bluetooth/Dnd/Mute` chips).
  - `gpui_kit::component::scroll::Scrollable` for wifi/bt lists + `gpui_kit::component::badge::Badge` for status (connected/secured) — but Capsule's `Scrollable` inside satellite card already correct; keep.
  - `gpui_kit::component::input::Input` + `Dialog` for WiFi passphrase (Capsule uses `InputState` inline; adapt to `gpui_kit::Input`).

- **Panel chrome:** each satellite is a `div().rounded(px(radius)).bg(surface(theme)).border_1().border_color(border(theme))` card with `concave` caps if Beskar keeps concave bar — Capsule uses `style::surface/border` (`capsule/widgets/style.rs:132-155`). Copy `style::card` / `style::surface`.

### 3.4 Integration with Beskar Bar / Dashboard

- **If ControlCenter lives inside Dashboard** (Capsule pattern: Dashboard module owns `Satellite` visuals, renders them around the capsule — `capsule/module/dashboard.rs:338-355` root + `satellites` loop): `crates/beskar-shell/src/modules/dashboard/mod.rs` owns `Satellite` entity, `set_satellites` + `measure_satellite` update measured heights, `toggle_satellite(id,cx)` guarded by `current_id==Dashboard` (Capsule `mod.rs:175-177` guard).
- **If ControlCenter is standalone Right-slot overlay** (Beskar today: `PanelHost Slot::Right`): keep `PanelHost` but **replace inner card layout with `SatelliteLayout` when viewport wide** (`viewport.width >= capsule.width + 320*2 + gap*2`). When narrow or on `Side::Below`, fall back to fullscreen scrim + centered card `360-420px` (Plan 00 scrim pattern). This preserves Beskar's 3-region bar while getting Capsule's non-intrusive OSD layout.

### 3.5 System Tray (if not already complete)

- `SystemTrayGroup.qml` → `crates/beskar-services/src/tray.rs` already streams via `zbus`; `Tray {bus, path}` satellite already handles per-item popover with correct D-Bus menu unpacking from `references/icebar`. Ensure `TrayActivate` + `TrayMenu(String,String,i32)` dispatch preserved.

## 4. Acceptance

- [x] `Satellite` layout tests pass: both sides filled, oldest evicted, reopening closing panel makes it newest, closed side reused, centered on capsule, measured heights correct; `SatelliteAnimator` reversing preserves position, zero-duration opens immediately.
- [x] `SatelliteLayout::new` clamps: preferred side honored when fits, fallback to other side when not, `Below` when neither fits, `16*(1-progress)` offset direction correct, `Below` center-clamped, `centered_y` within viewport.
- [x] Satellite panels render beside the bar/dashboard (`Left`/`Right`) with easeOutCubic slide, at most 2 open, `progress` drives opacity/slide, `Below` fallback centers below bar. When narrow viewport, scrim card fallback works.
- [x] Wifi/Bluetooth scans trigger on satellite open (not on render), lists populate via `HardwareSnapshot` subscription, connect/pair via `zbus`/`spawn_blocking` non-blocking, passphrase via `Input` + `Dialog`.
- [x] Volume/brightness sliders use `gpui_kit::Slider` (or `DimensionTracker` slider if copying Capsule detail verbatim), toggles use `Switch`, lists use `Scrollable` — no hand-rolled primitives; wifi/bt lists scroll bounded.
- [x] ControlCenter/Satellite respects `Slot::Right` mutual-exclusion with NotificationsCenter when in scrim mode; `Escape` + backdrop closes owning side only (Satellite `close_satellite` per-id).
- [x] No `Command::new("nmcli"|"bluetoothctl"|...)` outside `spawn_blocking`/`zbus`; frame loop uses `compositor.get_frame_duration().max(2ms)`.
- [x] `cargo check && cargo test` green; `grep -R "Command::new"` review clean.

## 5. Non-goals

- Notifications toasts/center (Plan 03 — but Satellite `Tray` handles per-icon menus).
- Dashboard card grid world (Plan 04 — but `details/` widgets already shared).
- Lockscreen/settings — Plan 05.
