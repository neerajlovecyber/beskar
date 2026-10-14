# Mega Plan Index — Minflair 100% Parity in Pure Rust

> Single entry point. No plan executes out of order. Plan 00 is a hard gate.

## Why this exists

`docs/MINFLAIR_PORTING_PLAN.md` (204 lines, 6 phases) covers ~40% of Minflair (186 QML + 18 services). It has no cross-cutting architecture contract, so naive execution reproduces the current `ugly / thin / hanging` shell. This index splits the work into a DAG of 6 sequenced sub-plans that are each independently verifiable.

## Execution DAG

```
             ┌─ Plan 00 ─┐  Architecture Overhauls (HARD GATE — nothing else starts)
             └───────────┘       OverlayHost deep module · Service Lifecycle/RunToken
                                 BarHost unified interface · Theme/Config signal
                                      │
               ┌──────────────────────┼──────────────────────┐
               ▼                      ▼                      ▼
           Plan 01                 Plan 02                Plan 03
        Bar Styles              Control Center         Notification Stack
      Convex/Island            + Hardware D-Bus       Clipboard · Wallpaper
       + Gaming           NetworkManager·BlueZ·UPower   Matugen · Palette
               │                      │                      │
               └──────────────────────┼──────────────────────┘
                                     ▼
                                 Plan 04
                          Dashboard · Music/Cava
                            ScreenCapture
                                     ▼
                                 Plan 05
                         LockScreen · Settings GUI (8 pages)
                         PackageManager · Final QA
```

## Ordering rules (do not violate)

1. **Plan 00 is a hard gate.** Plans 01-05 must not start until `docs/plans/00_ARCHITECTURE_OVERHAULS.md` is implemented and `cargo check + cargo test` passes with no main-thread `Command::new` outside `spawn_blocking`.
2. Plans 01, 02, 03 are parallelizable after 00, but share the contracts from 00 — any deviation reblocks the downstream plan.
3. Plan 04 depends on 01 (bar center island morphing) and 02 (MPRIS/Cava service lifecycle).
4. Plan 05 depends on 00+01+02+03 (settings writes barStyle, screen capture needs OverlayHost).
5. Every plan must preserve `references/` read-only and pass `cargo check` before closing.

## Sub-plans

| # | Doc | Scope | Primary upstream mirrors | Est. effort |
|---|-----|-------|--------------------------|-------------|
| 00 | [00_ARCHITECTURE_OVERHAULS.md](00_ARCHITECTURE_OVERHAULS.md) | OverlayHost deep module, Service Lifecycle/RunToken, BarHost unified interface, Theme/Config signal, main-thread blocking audit | `references/gpui-shell` (`bar/view.rs`, `services/lifecycle.rs`), `references/wayle`, `references/minflair/Core/Services/{AppState,SettingsService}.qml` | 2-3 days |
| 01 | [01_BAR_HOST_AND_STYLES.md](01_BAR_HOST_AND_STYLES.md) | Convex Bézier notch, Island 3-pill morphing, Gaming telemetry, slot loader, Workspaces pill, fractional-scale snapping | `references/minflair/Modules/Bar/{Bar,BarStyleConfig,Styles/Convex/ConvexShape,Styles/Island/*}.qml`, `references/gpui-shell/crates/ui/src/patterns/bar.rs`, `references/inir` | 3-4 days |
| 02 | [02_CONTROL_CENTER_AND_HARDWARE.md](02_CONTROL_CENTER_AND_HARDWARE.md) | Multi-page ControlCenter + Hardware D-Bus bus (Audio/PipeWire, NetworkManager, BlueZ, UPower, Backlight, PowerProfiles) | `references/wayle/crates/wayle-widgets/src/*`, `references/icebar/src/modules/tray.rs`, `references/minflair/Modules/ControlCenter/*` | 3-4 days |
| 03 | [03_NOTIFICATIONS_CLIPBOARD_WALLPAPER.md](03_NOTIFICATIONS_CLIPBOARD_WALLPAPER.md) | Notifications toast layer + NotificationCenter, Clipboard history, Wallpaper selector + dynamic palette engine | `references/minflair/Modules/{Notifications,NotificationCenter,Clipboard,WallpaperSelector}`, `references/gpui-kit` `List/VirtualList` | 3 days |
| 04 | [04_DASHBOARD_MUSIC_SCREENCAPTURE.md](04_DASHBOARD_MUSIC_SCREENCAPTURE.md) | Dashboard (Quote/Github/Updates/Heatmap), Music/Cava (MPRIS + spectrum), ScreenCapture/Recorder | `references/minflair/Modules/{Dashboard,Music,ScreenCapture}`, `references/pleamar/src/gpu.rs`, `references/wayle` audio | 2-3 days |
| 05 | [05_LOCKSCREEN_SETTINGS_QA.md](05_LOCKSCREEN_SETTINGS_QA.md) | LockScreen, Settings GUI (8 sub-pages), KeybindsCheatSheet, PackageManager, final QA/perf matrix | `references/minflair/Modules/{LockScreen,Settings,KeybindsCheatSheet,PackageManager}`, `references/wayle/crates/wayle-settings` | 3-4 days |

## Cross-cutting invariants (every sub-plan enforces)

- **Reference reuse:** each task lists exact `references/` files to cherry-pick (per `AGENTS.md §2`). No reimplementation from scratch.
- **Zero main-thread blocking:** every `Command::new("nmcli"|"wpctl"|"brightnessctl"|"bluetoothctl"|"playerctl"|"swww")` behind `tokio::task::spawn_blocking` or `zbus` async adapter.
- **LayerShell geometry:** overlays = fullscreen scrim (`Anchor::TOP|BOTTOM|LEFT|RIGHT`, `exclusive_zone=None`) + sized inner card + bounded `Scrollable`. Never fixed `640×460` sub-screen windows.
- **GPUI Kit primitives:** `Slider` for volume/brightness, `Switch` for toggles, `Scrollable` for lists, `List/VirtualList` for launchers/history, `Dialog/Sheet/Popover` for modals. No hand-rolled `div()` sliders.
- **60/120 FPS:** spring physics via `beskar-ui/src/spring.rs:SpringValue` + adaptive frame loop (16ms animating / 300ms idle).

## How to use this index

- Implementors: start at Plan 00, check off every `Input files`, `Output files`, and `Acceptance` line before moving on. Link PRs back to the plan file.
- Reviewers: verify the `References Inspected` list matches the diff; reject hand-rolled reimplementations that ignore `references/`.
- Conflicts: this index wins over `MINFLAIR_PORTING_PLAN.md` and `MINFLAIR_PARITY_MASTER_PLAN.md`. Those two are archived context, not execution specs.

## Legacy docs

- `docs/MINFLAIR_PORTING_PLAN.md` — original 6-phase outline (retained for history, not authoritative).
- `docs/MINFLAIR_PARITY_MASTER_PLAN.md` — overhaul plan for the bar (folded into Plan 00 + Plan 01).

Rules from `.agents/skills/gpui-kit/SKILL.md` and `.agents/skills/gpui-kit-design-guides/SKILL.md` remain normative for UI work.
