# Plan 04 — Dashboard, Music/Cava, ScreenCapture

> **Depends on:** Plan 00 + Plan 01 (**Animator** center island morph + **concave** + `visible_bounds`) + Plan 02 (**Satellite/Layout** + MPRIS/Cava lifecycle).
> Panel placement respects Plan 00 slot exclusivity; Satellite OSDs may sit beside Dashboard.
> **Rev 2 — Capsule-Native:** Dashboard card grid world + sine-wave media progress + slider `DimensionTracker` copied from `references/capsule`, not Minflair QML.

## 0. Goal

Port the productivity + media slice: **Dashboard** as a 560×574 card world (Left + Right columns, `CONTROLS`/`CONTENT`/`SLIDER`/`NOTIFICATIONS`/`FOOTER`), **Music/Cava** as a sine-wave seek bar (`position` + `wave_phase 3.0` + `PathBuilder::stroke`), and **ScreenCapture/Recorder** — by copying Capsule's `module/dashboard.rs` + `widgets/dashboard/*` Rust, not Minflair `Dashboard.qml`/`MprisService.qml`.

## 1. References Inspected

| Area | Upstream | Files (with line ranges) |
|------|----------|--------------------------|
| **Dashboard — module** | **`references/capsule`** | **`crates/app/src/capsule/module/dashboard.rs:1-384`** (`Snapshot{network,audio,battery,players,notifications,tray,dnd,date,month,duration,current_wallpaper}::read(cx)` from `AppState`, `DashboardModule{ navigation:Navigation, satellites,satellite_heights,wave_phase,snapshot_at:Instant, container_size, player_bus, pending, volume_bounds/brightness_bounds/seek_bounds: DimensionTracker, dragging_*, focus, _refresh poll 250ms, action_task }`, `new(cx)` `player_bus retain_player(None,players)` + `observe_global<Theme>`, `set_active(active,size,cx)` 250ms snapshot poll loop + media animation `compositor.get_frame_duration.max(16ms) wave_phase = epoch*3.0`, `refresh_snapshot` size_changed when `tray.empty` flip → `SizeChanged`, `set_satellites/measure_satellite` retains measured heights, `retain_player(current,players)` prefers current else playing else first, `slider_fraction(x,left,width)->Option<f32>` clamp, `Render` `track_focus on_key_down on_mouse_move/up volume_at/brightness_at/seek_at`, tests `361-383`) |
| **Dashboard — widget layout** | **`references/capsule`** | **`crates/app/src/capsule/widgets/dashboard/mod.rs:1-206`** (`WIDTH 560 HEIGHT 574 PADDING 12 GAP 8 HEADER 28 LEFT 268 RIGHT = WIDTH-PADDING*2-LEFT-GAP CONTROLS 68 CONTENT=68*3+GAP*2 MEDIA_HEIGHT=CONTENT SLIDER 80 NOTIFICATIONS 150 FOOTER 40 BOTTOM_PADDING 12 BODY = HEIGHT-PADDING-BOTTOM-HEADER-GAP`, `module_size(has_tray)` `574 vs 574-FOOTER-GAP`, `card(theme,cx)->Div rounded cards_round.min(22) bg surface`, `DashboardAction enum { Satellite, Close, Wifi, Bluetooth, Dnd, Mute, Brightness(u32), Sink(String), ScanWifi/ScanBluetooth, SelectWifi, ConnectWifi, BluetoothDevice, Month(i8), Settings, ClearNotifications, RemoveNotification, Notification, Media(i8), Seek(f64), TrayActivate/Menu, TrayActivate }`, `button(id,label,icon,action,active,theme,cx)->AnyElement` `min_h 44 rounded 18 bg selected|surface hover`, `icon_action` `32 rounded 8`, tests `192-205` dimension invariants) |
| **Dashboard — media wave** | **`references/capsule`** | **`crates/app/src/capsule/widgets/dashboard/media.rs:1-265`** (`position(track,elapsed)->i64` `position_micros + elapsed if playing else 0, min length`, `render(module,theme,cx)` `card rounded cards_round surface`, `radius = cards_round.min(22)`, `wave_phase` `amplitude 3.0 if playing else 0`, `active accent, inactive foreground_muted 0.3`, `canvas track_bounds Seek` `width*fraction` split: rest `PathBuilder::stroke 2` `move_to(played,center)->line_to(width,center)` inactive, wave `PathBuilder::stroke 2` `steps ceil(played)` `x min(played)` `envelope (x/8).min1 * ((played-x)/8).clamp0,1` `y = center + sin(x/22*TAU - phase)*amp*envelope` `move_to/line_to`, art `img local_art_path cover aspect RIGHT/MEDIA_HEIGHT backdrop_blur 18 bg 0.62`, title `17 SEMIBOLD` artist `11 muted` play `36 accent` prev/next `skip-back/forward` 18 disabled `0.35`, `Seek` click `start_seek`, tests `244-264`) |
| **Dashboard — details/satellites** | **`references/capsule`** | **`crates/app/src/capsule/widgets/dashboard/{home,header}.rs`**, **`crates/app/src/capsule/widgets/dashboard/details/{mod,audio,connectivity,tray}.rs`** (home card grid, audio sink+slider, wifi/bt scan, tray `SniItem` activation) |
| **Dashboard — navigation** | **`references/capsule`** | **`crates/app/src/capsule/module/dashboard/navigation.rs`** (`Navigation{selected_ssid,password_input}`), **`crates/app/src/capsule/module/dashboard/input.rs`** (`volume_at/brightness_at/seek_at` via `DimensionTracker` + `slider_fraction`, `dispatch(Action)`) |
| **ScreenCapture/Record** | **`references/capsule`** | **`crates/app/src/capsule/module/record.rs`**, **`crates/app/src/capsule/widgets/record.rs`**, **`crates/app/src/capsule/module/record/worker.rs`** (record `Worker` `spawn_blocking wf-recorder/grim/slurp`, `RecordStatus{Stopped,Recording,Paused}`, `RecordModule` size) |
| **Satellite surfaces reuse** | **`references/capsule`** | **`crates/app/src/capsule/widgets/satellite/surface.rs`**, **`crates/app/src/capsule/widgets/satellite/calendar.rs`** (`WIDTH/HEIGHT` reused as satellite sizes in Plan 02) |
| **Hardware audio** | `references/wayle` | `crates/wayle-widgets/src/audio` (PipeWire) — kept for service layer; `Dashboard Snapshot.audio: SystemStatus` already wired |
| **GPU/Shaders** | `references/pleamar` | `src/gpu.rs`, `src/render.rs`, `src/shape.wgsl` (wgpu pipeline — not required for Dashboard; keep for wallpaper backdrop blur if needed) |
| **Cava config** | `references/minflair` | `config/cava/config` (4-band config Mirrored in `crates/beskar-services/src/cava.rs:82-92` — keep if Beskar wants Cava `MiniCavaBars`; Capsule media wave is separate) |

**Archived Minflair rows superseded:** `Modules/Dashboard/*`, `GithubContributionsWidget.qml`, `QuoteWidget.qml`, `UpdatesCard.qml`, `Modules/Music/*`, `Core/Services/{GithubService,QuoteService,UpdateService,MprisService,CavaService}.qml`, `Core/Components/{Card,InfoRow,TypewriterText,Divider}.qml` — replaced by Capsule rows. `Modules/ScreenCapture/*` partially superseded by `capsule/module/record`.

## 2. Architecture

```
crates/beskar-services/src/
  mpris.rs / mpris_pleamar.rs  (zbus MPRIS2 — already exists; ensure Snapshot.players: Vec<MediaTrack{bus_name,title,artist,album,length_micros,position_micros,is_playing,can_go_next/previous,local_art_path}> matches Capsule's MediaTrack)
  cava.rs                       (spawn_blocking "cava" pipe, 4-band, 60ms when playing — keep; Capsule wave_phase is separate sine, not Cava bars)
  updates.rs                    (checkupdates/paru/yay via spawn_blocking, intervals — keep)
  github.rs                     (reqwest contributions graph — optional, keep; Capsule Dashboard does not use it)
  vitals.rs                     (sysinfo CPU/RAM — already streaming; maps to Dashboard SystemStatus)

crates/beskar-ui/src/
  widgets/dashboard/
    layout.rs                   <- copy capsule/widgets/dashboard/mod.rs constants + module_size/card/ tests
    media.rs                    <- copy capsule/widgets/dashboard/media.rs position + render (wave canvas)
    details/                    <- re-export Capsule details if Beskar also uses Satellite connectivity/audio panels
  widgets/
    dynamic_center.rs           (bar center: clock ↔ media+wave vs Cava 4-bars — keep; now reads wave_phase or Cava bands from DashboardModule snapshot)

crates/beskar-shell/src/modules/
  dashboard/
    mod.rs                      <- DashboardModule (Capsule IDs -> Beskar Slot::Left or Center expansion)
                                  owns Satellite visuals if using overlay beside Dashboard; else standalone Dashboard card grid
    navigation.rs               <- copy capsule/module/dashboard/navigation.rs + input.rs volume/brightness/seek handlers
    satellite_host.rs           <- if Dashboard owns Satellite visuals: mirrors DashboardModule.satellites + measure flow
    heatmap.rs / profile.rs / view.rs (existing) — replace or adapt to Capsule home.rs card grid; keep if Beskar wants Github heatmap extra
  music_player/
    mod.rs + view.rs            <- PanelModule Slot::Center — expands center island (Animator), reuses media.rs wave + MPRIS controls
                                  Alternatively: merge into Dashboard media card; Beskar today has separate music_player — keep but render same media.rs
  screen_capture/
    mod.rs + view.rs            <- copy capsule/module/record pattern: RecordModule + worker::start + RecordStatus
                                  PanelModule Slot::Focus (Focus-exclusive)
                                  wf-recorder/grim/slurp via spawn_blocking, pidof poll via lifecycle interval
```

**Slot mapping:**

- Capsule Dashboard is a single `CapsuleModuleId::Dashboard` module sized `560×574` (or `560×(574-FOOTER-GAP)` when tray empty) centered in the capsule window; satellites sit beside it (`Left`/`Right` at `gap` from capsule). In Beskar, Dashboard maps to **`Slot::Left` scrim card** (`crates/beskar-shell/src/panel_host.rs`) **or** **`Slot::Center` island expansion** (`Animator` sized card) — choose one and keep consistent. The recommended Beskar mapping: **Dashboard = `Slot::Left` scrim card** `560×574` (largest overlay), **Music = `Slot::Center` island expansion** (shares media wave but not card grid).

## 3. Tasks

### 3.1 Dashboard (Left slot — copy Capsule card world)

- **Constants + layout copy:**
  ```rust
  // From references/capsule/crates/app/src/capsule/widgets/dashboard/mod.rs:14-38
  pub const WIDTH: f32 = 560.0; pub const HEIGHT: f32 = 574.0; pub const PADDING: f32 = 12.0; pub const GAP: f32 = 8.0;
  pub const HEADER: f32 = 28.0; pub const LEFT: f32 = 268.0; pub const RIGHT: f32 = WIDTH - PADDING*2.0 - LEFT - GAP;
  pub const CONTROLS: f32 = 68.0; pub const CONTENT: f32 = CONTROLS*3.0 + GAP*2.0; pub const MEDIA_HEIGHT: f32 = CONTENT;
  pub const SLIDER: f32 = 80.0; pub const NOTIFICATIONS: f32 = 150.0; pub const FOOTER: f32 = 40.0; pub const BOTTOM_PADDING: f32 = PADDING;
  pub const BODY: f32 = HEIGHT - PADDING - BOTTOM_PADDING - HEADER - GAP; // cfg(test)
  pub fn module_size(has_tray: bool) -> Size<Pixels> { size(px(WIDTH), px(if has_tray {HEIGHT} else {HEIGHT-FOOTER-GAP})) }
  pub fn card(theme: &Theme, cx: &App) -> Div { style::card(theme, cx.global::<AppState>().config.get().ui.cards_round.min(22.0)) }
  // Invariants: PADDING*2 + LEFT + GAP + RIGHT == WIDTH; PADDING+BOTTOM+HEADER+GAP+BODY == HEIGHT; CONTENT+SLIDER+NOTIFICATIONS+FOOTER+GAP*3 == BODY
  ```
  Copy `mod.rs:87-191` `DashboardAction` enum + `button` (`44 rounded 18 selected|surface hover ease_in_out`) + `icon_action` (`32 rounded 8 opacity disabled 0.35`). Tests `192-205` verify invariants.

- **Snapshot + DashboardModule copy:**
  ```rust
  // From references/capsule/crates/app/src/capsule/module/dashboard.rs:23-384
  // Snapshot::read(cx) -> { network get_status(), audio get_status(), battery get_battery(), players get_all_players, notifications global, tray get_items(), dnd is_dnd, date format_date(config clock_format + language months/days), month calendar get_view_date(), duration animation_duration_ms, wallpaper get_current() }
  // DashboardModule::new(cx) { satellites vec, wave_phase 0, snapshot_at now, container_size module_size(!tray.empty), player_bus retain_player(None,players), observe_global Theme }
  // set_active(active,size,cx) { 250ms refresh_snapshot poll loop; media animation loop wave_phase = epoch.elapsed as_secs_f32 * 3.0 when playing }
  // refresh_snapshot { if snapshot != self.snapshot { retain_player, clear selected_ssid when wifi_ssid matches, SizeChanged when tray.empty flip } }
  // retain_player(current,players) { find current else playing else first }
  // slider_fraction(x,left,width) { width>0 then ((x-left)/width).clamp 0..1 else None }
  // Render { track_focus on_key_down, on_mouse_move volume_at/brightness_at, on_mouse_up finish_brightness + seek_at, w/h container_size rounded capsule_round bg background, child home::render }
  // + satellite loop: for visual in satellites { div id satellite-? child details::render_satellite(..., radius satellite_round) }
  ```

- **Adaptation seams:**
  - `services::AppState` → `beskar-services::HardwareBus` + `beskar-core::config` + `beskar-services::notifications::NotificationStore` + `beskar-services::tray` + `beskar-services::mpris`.
  - `ui::theme::Theme` → `beskar-theme::ThemeEngine` (or `ui` alias if Beskar keeps Capsule's `ui` crate).
  - `ui::tracker::DimensionTracker` → `beskar-ui::tracker` or keep `ui` alias; `DimensionTracker::new/track_bounds` used for volume/brightness/seek sliders.
  - `language.get("...")` → Beskar i18n stub or keep English strings; not blocking.
  - `calendar.get_view_date() / language.get_list("datetime.months")` → keep if Beskar has calendar; else stub `Local::now()`.

- **Home/widgets:** copy `capsule/widgets/dashboard/home.rs` card grid (home.rs composes header + media + controls + notifications + footer + tray). Each card uses `style::card` with `cards_round.min(22)`. Input handlers `volume_at(x,cx)` / `brightness_at` / `seek_at` via `DimensionTracker` bounds + `slider_fraction` → `DashboardAction::Brightness/Sink/Seek` dispatch through `actions.rs` `spawn_tokio` (same as Capsule).

### 3.2 Music / Cava — sine-wave seek bar (copy Capsule media wave)

- **Service:** `MprisService` (zbus) + `CavaService` (already `crates/beskar-services/src/cava.rs:92` `Command::new("cava")` in `spawn_blocking`, 4 bands — keep). Respect `SettingsService.musicPlayer` preference (`"none"` hides media slot). No Capsule Cava analog; keep Beskar Cava for `MiniCavaBars` in bar center if desired.

- **Bar center wave vs Cava bars:**
  Option A — **Capsule wave** (sine `x/22*TAU - phase`): `crates/beskar-ui/src/widgets/dynamic_center.rs` already morphs center pill width via `Animator` (Plan 01); wire `DashboardModule.wave_phase` + `position(track, snapshot_at.elapsed())` + `fraction position/length` into the seek bar wave canvas when media card is visible.
  Option B — **Minflair Cava bars** (`MiniCavaBars.qml` 4-band, 60ms when playing) fed from `bar/view.rs:167-201` loop — keep if Beskar wants spectrum, but don't wire both waves to same pill (visual clash).

- **Panel:** `music_player/view.rs` full player (art, title/artist, seek, play/pause/next) — **reuse `capsule/widgets/dashboard/media.rs:26-241` verbatim** (art `backdrop_blur 18`, `position` in micros, `fraction`, wave canvas `16 offset 8 envelope`, `inactive 0.3`, `play 36 accent`, `skip-back/forward` 18). Controls via `DashboardAction::Media(i8)` dispatch (`-1 prev, 0 play/pause, 1 next`) + `Seek(f64)` via `seek_bounds` `DimensionTracker`. All `playerctl` calls via `spawn_blocking` (already `music_player/mod.rs:145` but ensure non-blocking). Panel expands center island in-place (Plan 01 `Animator`), not detached overlay.

- **Pure fn `position`:** `position(track, elapsed) = (position_micros.max(0) + (elapsed if is_playing else 0)).min(length_micros if >0 else next)` — copy `media.rs:12-24`, tests `244-264` (`paused never exceeds track, -20 clamped 0`).

### 3.3 ScreenCapture / RecordingIndicator (copy Capsule record module)

- **Record module copy:**
  ```rust
  // From references/capsule/crates/app/src/capsule/module/record.rs + worker.rs
  // RecordModule { status: RecordStatus::Stopped|Recording|Paused, worker: start(), ... }
  // Worker { spawn_blocking wf-recorder/grim/slurp, sh -c handling via spawn_blocking, pidof wf-recorder poll via lifecycle interval }
  // Capsule widgets/record.rs renders card with controls + file list
  ```

- **Beskar mapping:** `screen_capture/view.rs:57-83` already fronts `wf-recorder`/`grim`/`slurp` via `sh -c` — **all inside `spawn_blocking`** (Plan 00 audit). Honor `PanelModule Slot::Focus` scrim. `RecordingIndicator` red pill in bar Right slot when `RecordStatus != Stopped` (`references/minflair/Modules/Bar/Components/RecordingIndicator.qml` — or Capsule `Orbit::Recording` orb when `record_status != Stopped`).

- **Indicator:** tiny red dot + timer in bar Right slot when `pidof wf-recorder` succeeds — ensure poll interval via `Lifecycle` timer, not render loop. If adopting Capsule `Orbit::Recording` pattern, consider orb beside bar instead of bar pill (Beskar today: bar pill — keep).

## 4. Acceptance

- [ ] Dashboard overlay opens as `Left` (or `Center`) slot card `560×574` (`has_tray` vs `no-tray` height `574-FOOTER-GAP`), gap `12`, left column `268` + right `RIGHT = WIDTH-PADDING*2-LEFT-GAP`, `CONTENT=212` `SLIDER 80` `NOTIFICATIONS 150`; dimension invariants pass.
- [ ] Snapshot polls at `250ms` when `active`, `SizeChanged` only when `tray.empty` flips; `retain_player` prefers `current` else `playing` else `first`; `slider_fraction` clamps `0..1` returns `None` when `width==0`.
- [ ] Wave animation runs at `compositor.get_frame_duration().max(16ms)` while `is_playing`, `wave_phase = epoch*3.0`; progress wave `amplitude 3.0` else `0`, envelope `min(x/8,1)*clamp((played-x)/8,0,1)`, `inactive 0.3` rest line, `active accent` wave stroke `2`; `position(track,elapsed)` clamped `max 0` and never exceeds `length`.
- [ ] Media card: `backdrop_blur 18 bg 0.62` art cover `aspect RIGHT/MEDIA_HEIGHT`, title `17 SEMIBOLD` artist `11 muted`, `play 36 accent` + prev/next `18 disabled 0.35`, seek `canvas 12×` with `start_seek` `on_mouse_down`, `Seek(f64)` dispatch via `DimensionTracker` + `slider_fraction`; non-blocking `playerctl`/`mpris` `spawn_tokio`.
- [ ] Volume/brightness/seek `DimensionTracker` bounds `track_bounds` + `on_mouse_move` `volume_at/brightness_at/seek_at` + `on_mouse_up` `finish_brightness` — no polling in `render`.
- [ ] ScreenCapture: `Focus`-exclusive, `wf-recorder`/`grim`/`slurp` via `spawn_blocking`, `RecordingIndicator` red pill/orb when `Recording`, hides after `Stopped`; `RunToken::alive()` respected.
- [ ] Cava 4-band `60ms` loop (if kept) respects `RunToken::alive()`; not conflated with Capsule wave (docs note which pill shows which).
- [ ] `cargo check && cargo test` green; `capsule/widgets/dashboard` trace matches Beskar `widgets/dashboard` diff.

## 5. Non-goals

- LockScreen/settings/polkit — Plan 05. Github/Quotes/Updates cards beyond Capsule's home grid — keep as Beskar extras if existing, not required for gate.
