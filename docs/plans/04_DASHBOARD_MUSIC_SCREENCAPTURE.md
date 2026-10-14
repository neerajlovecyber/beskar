# Plan 04 — Dashboard, Music/Cava, ScreenCapture

> **Depends on:** Plan 00 + Plan 01 (center island morph) + Plan 02 (MPRIS/Cava lifecycle).
> Panel placement respects Plan 00 slot exclusivity.

## 0. Goal

Port the productivity + media slice: Dashboard (aggregated cards), Music/Cava (MPRIS + spectrum visualizer in the bar center), and ScreenCapture/Recorder.

## 1. References Inspected

| Area | Upstream | Files |
|------|----------|-------|
| Dashboard | `references/minflair` | `Modules/Dashboard/Dashboard.qml`, `DashboardContent.qml`, `Components/*`, `GithubContributionsWidget.qml`, `GithubWidget.qml`, `QuoteWidget.qml`, `UpdatesCard.qml` |
| Dashboard services | `references/minflair` | `Core/Services/{GithubService,QuoteService,UpdateService,SystemInfoService,SystemStats}.qml`, `Core/Components/{Card,InfoRow,TypewriterText,Divider,AppHeader}.qml` |
| Music | `references/minflair` | `Modules/Music/*` (MPRIS player, Cava bars), `Core/Services/{MprisService,CavaService,AudioService}.qml`, `Modules/Bar/Components/{MediaButton,MiniCavaBars}.qml` |
| ScreenCapture | `references/minflair` | `Modules/ScreenCapture/*`, `Core/Services/RecorderService.qml`, `Core/Components/SvgIcon.qml` |
| GPU/Shaders | `references/pleamar` | `src/gpu.rs`, `src/render.rs`, `src/shape.wgsl`, `src/platform/` (wgpu, wgsl pipeline, layer-shell chrome) |
| Hardware audio | `references/wayle` | `crates/wayle-widgets/src/audio` (PipeWire) |
| Cava spectrum | `references/minflair` | `config/cava/config` (4-band config Mirrored in `crates/beskar-services/src/cava.rs:82-92`) |

## 2. Architecture

```
crates/beskar-services/src/
  mpris.rs / mpris_pleamar.rs  (zbus MPRIS2 — already exists, harden to ManagedService)
  cava.rs                       (spawn_blocking "cava" pipe, 4-band, 60ms when playing)
  updates.rs                    (checkupdates/paru/yay via spawn_blocking, intervals)
  github.rs                     (reqwest contributions graph — already exists)
  vitals.rs                     (sysinfo CPU/RAM — already streaming)

crates/beskar-shell/src/modules/
  dashboard/mod.rs              (PanelModule Slot::Left — aggregated card grid)
    heatmap.rs / profile.rs / view.rs (already exist, polish to Minflair cards)
  music_player/mod.rs + view.rs (PanelModule Slot::Center — expands center island, NOT detached; controls + art)
  screen_capture/view.rs        (PanelModule Slot::Focus — region/window/full + recorder indicator)

crates/beskar-ui/src/widgets/
  dynamic_center.rs             (bar center: clock ↔ media+4-band Cava ↔ notification toast — spring width already in bar/view.rs:82)
```

Dashboard is `Left` slot (competes with nothing else today; later holds its own page). Music is `Center` slot (competes with clock detail, not focus overlays). ScreenCapture is `Focus` slot (closes launcher/clipboard/etc).

## 3. Tasks

### 3.1 Dashboard (Left slot)

- Cards: keep `crates/beskar-shell/src/modules/dashboard/{profile,heatmap,view}.rs` but skin to `Card.qml` (obsidian glass `16px` radius, `8px` padding, top specular border) + `InfoRow` + `Divider`.
- Widgets: `GithubWidget` (contributions heatmap `heatmap.rs`), `QuoteWidget` (`TypewriterText` animation via `SpringValue` or `gpui::Animation` — 1:1 `references/minflair/Core/Components/TypewriterText.qml`), `UpdatesCard` (`PackageManagerChecksEnabled` toggle from SettingsService), `SystemStats` CPU/RAM mini bars.
- Data: services use `Lifecycle`; `UpdateService` polls on interval (`packageManagerCheckInterval`), never on render.

### 3.2 Music / Cava (Center island)

- Service: `MprisService` (zbus) + `CavaService` (already `crates/beskar-services/src/cava.rs:92` `Command::new("cava")` in `spawn_blocking`, 4 bands). Respect `SettingsService.musicPlayer` preference (`"none"` hides media slot).
- Bar center: `crates/beskar-ui/src/widgets/dynamic_center.rs` already morphs center pill width via `SpringValue`; wire real Cava bands from `bar/view.rs:167-201` loop (already 60ms when playing) into `MiniCavaBars.qml` 4-bar visualizer.
- Panel: `music_player/view.rs` full player (art, title/artist, seek `Slider`, play/pause/next via `playerctl` in `spawn_blocking` — already `music_player/mod.rs:145` but ensure non-blocking). Panel expands center island in-place (Plan 01), not a detached overlay — `AppState.qml:73-78` `barIslandWidth/Height` contract.

### 3.3 ScreenCapture / RecordingIndicator

- Capture: `screen_capture/view.rs:57-83` fronts `wf-recorder`/`grim`/`slurp` via `sh -c` — all inside `spawn_blocking`; honor `PanelModule Slot::Focus` scrim. Recordings list + `RecordingIndicator` pill in bar Right slot when active (`references/minflair/Modules/Bar/Components/RecordingIndicator.qml`).
- Indicator: tiny red dot + timer in bar Right slot when `pidof wf-recorder` succeeds (already `screen_capture/mod.rs:45` but ensure non-blocking poll interval, not render loop).

## 4. Acceptance

- [ ] Dashboard opens as scrim+card Left slot, cards match Minflair `Card`/`InfoRow` styling, Github heatmap + Quote typewriter + Updates visible when enabled.
- [ ] Music: bar center shows clock by default, expands to media+art+4-band Cava when playing (60ms bands), contracts when paused; full Music panel is center-slot morph, controls non-blocking.
- [ ] ScreenCapture: Focus-exclusive, capture commands non-blocking, RecordingIndicator red pill appears during recording and hides after.
- [ ] No render-thread blocking; Cava/MPRIS listeners respect `RunToken::alive()`.
- [ ] `cargo check && cargo test` green.

## 5. Non-goals

- LockScreen/settings/packageManager — Plan 05.
