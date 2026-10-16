# Mega Plan Index — Minflair 100% Parity in Pure Rust (Capsule-Accelerated)

> Single entry point. No plan executes out of order. Plan 00 is a hard gate.
> **Revision 2 — Capsule-Native:** QML-to-Rust translation is **eliminated**. Every UI/geometry/physics task now ports battle-tested **Rust + GPUI** code from `references/capsule` directly into Beskar's modular crates. Estimated total effort drops **~55-65%** (from ~16-21 days to ~7-10 days).

## Why this exists

`docs/MINFLAIR_PORTING_PLAN.md` (204 lines, 6 phases) covers ~40% of Minflair (186 QML + 18 services). It has no cross-cutting architecture contract, so naive execution reproduces the current `ugly / thin / hanging` shell. This index splits the work into a DAG of 6 sequenced sub-plans that are each independently verifiable.

**Revision 2 delta:** Upstream `references/capsule` (`https://github.com/moiCR/Capsule`) is an all-in-one Wayland shell already written in **pure Rust + GPUI**. Per `AGENTS.md §2` and the Mandatory Architecture Decision, every task that previously said "translate Minflair QML `ConvexShape.qml:27-69` / `IslandCenterPill.qml` / `ControlCenter.qml` into Rust" now says **"cherry-pick `references/capsule/crates/app/src/...` verbatim, adapt the `Theme`/`AppState` seam, and connect to `beskar-services::HardwareBus` / `CompositorBackend`"**. No QML interpretation, no Bézier re-derivation, no spring re-tuning.

Measured speedup:

| Work type | QML→Rust (old) | Rust→Rust via Capsule (new) | Speedup |
|-----------|----------------|------------------------------|---------|
| Convex Bézier notch (7-segment path) | 1.5 days (re-derive control points, test seams) | 0.25 days (copy `concave_background` + `concave_radii`) | ~6× |
| Island morph spring + outgoing cross-fade | 1.5 days (tune From/To, re-impl `SpringValue`) | 0.25 days (copy `Animator` + `apple_island_morph`) | ~6× |
| Satellite OSDs (Wifi/BT/Audio/Tray) | 2 days (design layout, animate, wire D-Bus) | 0.5 days (copy `satellite/` + `layout.rs`) | ~4× |
| Notifications + Clipboard | 1.5 days (design list, measure text, manage history) | 0.5 days (copy `module/notification.rs` + `widgets/clipboard.rs`) | ~3× |
| Dashboard + Media wave | 1.5 days (card layout, wave PathBuilder, slider trackers) | 0.5 days (copy `widgets/dashboard/media.rs` + `module/dashboard.rs`) | ~3× |
| Lockscreen PAM + Settings 8-page | 2 days (SessionLock, PAM, prefs IPC) | 0.75 days (copy `lockscreen/` + `settings/` + `module/polkit.rs`, fix blocking) | ~2.5× |

## Execution DAG

```
             ┌─ Plan 00 ─┐  Architecture Overhauls (HARD GATE — nothing else starts)
             └───────────┘       OverlayHost deep module · Service Lifecycle/RunToken
                                 Animator spring contract · LayerShell dynamic sizing
                                 BarHost unified interface · Theme/Config signal
                                      │
               ┌──────────────────────┼──────────────────────┐
               ▼                      ▼                      ▼
           Plan 01                 Plan 02                Plan 03
        Bar Styles              Control Center         Notification Stack
      Convex/Island            Satellite OSDs         Clipboard · Wallpaper
       + Orbit                 (capsule/satellite)    (capsule modules)
               │                      │                      │
               └──────────────────────┼──────────────────────┘
                                     ▼
                                 Plan 04
                          Dashboard · Music/Cava
                            ScreenCapture
                                     ▼
                                 Plan 05
                         LockScreen · Settings (8 pages) · Polkit
                         PackageManager · Final QA
```

## Ordering rules (do not violate)

1. **Plan 00 is a hard gate.** Plans 01-05 must not start until `docs/plans/00_ARCHITECTURE_OVERHAULS.md` is implemented and `cargo check + cargo test` passes with no main-thread `Command::new` outside `spawn_blocking`/`spawn_tokio`.
2. Plans 01, 02, 03 are parallelizable after 00, but share the contracts from 00 — any deviation reblocks the downstream plan.
3. Plan 04 depends on 01 (bar center island morphing / `Animator`) and 02 (MPRIS/Cava service lifecycle).
4. Plan 05 depends on 00+01+02+03 (settings writes `barStyle`, screen capture needs `OverlayHost`, lockscreen needs `SessionLock` contract).
5. Every plan must preserve `references/` read-only and pass `cargo check` before closing.
6. **Capsule blocking rule (new):** Capsule calls `sh -c grim …`, `magick/convert`, `std::thread::spawn` for PAM, and raw `Command::new` for audio. Every extracted component must be patched to Beskar's non-blocking rule before merge: `tokio::task::spawn_blocking` for CLI, `services::spawn_tokio`/`zbus` for D-Bus, never in `render`/`View::new`/`cx.update`.

## Sub-plans

| # | Doc | Scope | Primary upstream mirrors (Capsule-native) | Est. effort (old → new) |
|---|-----|-------|-------------------------------------------|-------------------------|
| 00 | [00_ARCHITECTURE_OVERHAULS.md](00_ARCHITECTURE_OVERHAULS.md) | OverlayHost deep module, Service Lifecycle/RunToken, **Capsule Animator spring contract**, **LayerShell dynamic sizing** (`maximum_window_size`, `visible_bounds`, `exclusive_zone`), BarHost unified interface, Theme/Config signal, main-thread blocking audit | `references/capsule/crates/app/src/capsule/animator.rs:15-44` (`spring_eval`, `apple_island_morph`), `references/capsule/crates/app/src/panel.rs:25-80` (`CapsulePanel::window_options`), `references/capsule/crates/app/src/capsule/window_state.rs`, `references/gpui-shell/crates/services/src/lifecycle.rs`, `references/wayle` | 2-3 days → **1-1.5 days** |
| 01 | [01_BAR_HOST_AND_STYLES.md](01_BAR_HOST_AND_STYLES.md) | Concave Bézier notch (cubic fillets), Island 3-pill morphing with outgoing cross-fade, Gaming telemetry, slot loader, Workspaces pill, fractional-scale snapping | `references/capsule/crates/app/src/capsule/widgets/style.rs:27-130` (`concave_radii`, `concave_background`, `concave_input_regions`), `references/capsule/crates/app/src/capsule/orbit/{animator,state,mod}.rs`, `references/capsule/crates/app/src/capsule/mod.rs:29-188` (outgoing `OutgoingContent`, `content_scale`/`content_progress`) | 3-4 days → **1.5-2 days** |
| 02 | [02_CONTROL_CENTER_AND_HARDWARE.md](02_CONTROL_CENTER_AND_HARDWARE.md) | Multi-page ControlCenter as **non-intrusive Satellite OSDs** (Wifi, Bluetooth, Audio, Calendar, Tray) + Hardware D-Bus bus (Audio/PipeWire, NetworkManager, BlueZ, UPower, Backlight, PowerProfiles) | `references/capsule/crates/app/src/capsule/satellite/{mod,animator,layout}.rs`, `references/capsule/crates/app/src/capsule/widgets/dashboard/details/{audio,connectivity,tray,mod}.rs`, `references/wayle/crates/wayle-widgets/src/*` (zbus adapters) | 3-4 days → **1.5-2 days** |
| 03 | [03_NOTIFICATIONS_CLIPBOARD_WALLPAPER.md](03_NOTIFICATIONS_CLIPBOARD_WALLPAPER.md) | Notifications toast layer + NotificationCenter (inline reply), Clipboard history + Snippets grid, Wallpaper selector + dynamic palette engine | `references/capsule/crates/app/src/capsule/module/notification.rs` (history vs popup, `popup_height`, inline reply), `references/capsule/crates/app/src/capsule/widgets/notification.rs:97-133` (`popup_height`, `actions_height`), `references/capsule/crates/app/src/capsule/module/clipboard.rs` + `widgets/clipboard.rs:13-25` (`WIDTH 480`, `COLUMNS 2`, `CARD_HEIGHT 144`) | 3 days → **1-1.5 days** |
| 04 | [04_DASHBOARD_MUSIC_SCREENCAPTURE.md](04_DASHBOARD_MUSIC_SCREENCAPTURE.md) | Dashboard (480-viewport card grid), Music/Cava sine-wave seek bar, ScreenCapture/Recorder | `references/capsule/crates/app/src/capsule/module/dashboard.rs` (`Snapshot`, `retain_player`, `slider_fraction`), `references/capsule/crates/app/src/capsule/widgets/dashboard/{mod,media,home,header}.rs` (`WIDTH 560`, `HEIGHT 574`, wave `PathBuilder::stroke`), `references/capsule/crates/app/src/capsule/widgets/satellite/surface.rs` | 2-3 days → **1-1.5 days** |
| 05 | [05_LOCKSCREEN_SETTINGS_QA.md](05_LOCKSCREEN_SETTINGS_QA.md) | LockScreen (SessionLock + PAM + blur snapshot), Settings GUI (6-view `Appearance/Apps/Media/LockScreen/System/Record` + sidebar), Polkit native agent, PackageManager, final QA/perf matrix | `references/capsule/crates/app/src/panel.rs:108-220` (`LockScreenPanel::window_options` `SessionLockOptions`, blur via `grim -g` + `magick`), `references/capsule/crates/app/src/lockscreen/view.rs` (PAM thread, `InputState` masked, `BlurredWallpaper` fallback), `references/capsule/crates/app/src/settings/mod.rs` (`WIDTH 1120`, `HEIGHT 780`, 6-view `Sidebar`/`SettingsTab`), `references/capsule/crates/app/src/capsule/module/polkit.rs` | 3-4 days → **1.5-2 days** |

**Total:** ~16-21 days → **~7-10 days** (Capsule-native, Rust-to-Rust).

## Cross-cutting invariants (every sub-plan enforces)

- **Reference reuse (Capsule-first):** each task lists exact `references/capsule/...` files to cherry-pick (per `AGENTS.md §2` + Mandatory Decision). No reimplementation from scratch, no QML interpretation. Copy data structures, `PathBuilder` math, `Duration`/`Instant` loops, and error handling verbatim; only adapt `Theme` (`ui::theme::Theme` → `beskar-theme`) and `AppState`/`AppState.config` seams.
- **Zero main-thread blocking:** every `Command::new("grim"|"magick"|"nmcli"|"wpctl"|"brightnessctl"|"bluetoothctl"|"playerctl"|"swww")` and every `std::thread::spawn(|| PamService::authenticate(...))` behind `tokio::task::spawn_blocking` or `services::spawn_tokio`/async `zbus` — never in `render`, `View::new`, or `cx.update` synchronously. Capsule violations (`panel.rs:165-166` `sh -c grim`, `lockscreen/view.rs:116` PAM thread, `orbit/mod.rs:277-285` `spawn_tokio` already ok) must be fixed on extraction.
- **LayerShell geometry (Capsule pattern):** bar = `Layer::Top`, `Anchor::TOP|LEFT|RIGHT` (or `BOTTOM`), `exclusive_zone = logical_height + margin`; overlays/satellites = fullscreen scrim (`Anchor::TOP|BOTTOM|LEFT|RIGHT`, `exclusive_zone=None`) + sized inner card + bounded `Scrollable`; lockscreen = `WindowKind::SessionLock(SessionLockOptions)` per-display. Never fixed `640×460` sub-screen windows. Use `Capsule::maximum_window_size` / `window_state::visible_bounds` / `SatelliteLayout::new` clamping verbatim.
- **GPUI Kit primitives:** `Slider` for volume/brightness/seek, `Switch` for toggles, `Scrollable` for lists, `List/VirtualList` for launchers/history, `Dialog/Sheet/Popover` for modals, `InputState`/`Input` for search & auth. Capsule's `ui::components::{InputState, Badge, Button, Chip, IconButton}` maps 1:1 to `gpui-kit`; never hand-rolled `div()` sliders.
- **60/120 FPS:** spring physics via `beskar-ui/src/spring.rs:Animator` (`spring_eval` zeta 0.73/0.77, `apple_island_morph` powf 0.92/1.04) + adaptive frame loop (16ms animating / 300ms idle). Capsule already drives `compositor.get_frame_duration().max(16ms)` — reuse.
- **Compositor agnostic:** `beskar-compositor::CompositorBackend` trait (Niri, Umbriel, Hyprland). Capsule's `AppState::compositor` calls (`logout`, `get_frame_duration`) stay behind the trait; never hard-code `niri msg`.
- **Isolate references:** `references/` is strictly read-only (git `skip-worktree`). Verify with `git status --ignored`.

## How to use this index

- Implementors: start at Plan 00, check off every `Input files`, `Output files`, and `Acceptance` line before moving on. Link PRs back to the plan file. For each cherry-pick, paste the source line range in the PR description (e.g., `capsule/animator.rs:15-44 → beskar-ui/src/spring.rs`).
- Reviewers: verify the `References Inspected` list matches the diff; reject any hand-rolled Bézier/spring/layout that ignores `references/capsule`.
- Conflicts: this index wins over `MINFLAIR_PORTING_PLAN.md` and `MINFLAIR_PARITY_MASTER_PLAN.md`. Those two are archived context, not execution specs. QML line references in them are superseded by Capsule paths.

## Legacy docs

- `docs/MINFLAIR_PORTING_PLAN.md` — original 6-phase outline (retained for history, not authoritative).
- `docs/MINFLAIR_PARITY_MASTER_PLAN.md` — overhaul plan for the bar (folded into Plan 00 + Plan 01).
- `references/capsule/` — upstream Rust/GPUI mirror (read-only). Do not modify; do not fork Beskar around it. Beskar retains `crates/{beskar-core,beskar-compositor,beskar-services,beskar-theme,beskar-ui,beskar-shell}` + 3-region bar topology.

Rules from `.agents/skills/gpui-kit/SKILL.md` and `.agents/skills/gpui-kit-design-guides/SKILL.md` remain normative for UI work.
