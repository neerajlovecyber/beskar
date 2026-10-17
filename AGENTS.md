# Beskar Shell - Agent Directives & Engineering Rules

## 1. Prime Directive: Maximize Reference Code Reuse
**Do not write boilerplate or reimplement complex desktop shell mechanics from scratch.**
Always copy, cherry-pick, and adapt battle-tested code directly from the local `references/` directory. This guarantees that protocols, edge cases (fractional scaling, Wayland layer-shell flags, D-Bus message unpacking, spring physics), and platform interactions work out of the box without guesswork or regressions.

---

## 2. Upstream Reference Bank Guide

When implementing or extending any module in Beskar, directly extract logic from these sources:

| Subsystem / Feature | Primary Upstream Source | Files to Copy / Adapt |
| :--- | :--- | :--- |
| **GPUI & Wayland LayerShell** | `references/gpui-shell` | `crates/app/src/bar/view.rs`, `crates/ui/src/patterns/bar.rs` (LayerShell options, screen bounds, fractional scale fix) |
| **Niri Compositor IPC** | `references/gpui-shell` & `references/inir` | `crates/services/src/compositor/niri.rs` (event stream handling, action dispatch, `EventStreamState`) |
| **Island Geometry & Convex Math** | `references/minflair` & `references/inir` | `Modules/Bar/Styles/Convex/ConvexShape.qml`, `modules/iris/bar/IrisIsland.qml`, `modules/iris/style/IrisStyle.qml` (Cubic Bézier fillets, spring physics) |
| **Aesthetics, Theme & Shaders** | `references/suzuha` & `references/amane` | `src/theme.rs`, `src/theme/hsl.rs`, `src/liquid.rs`, `shaders/` (Wallpaper HSL color engine, glass acrylic shaders) |
| **Hardware Modules (Pure Rust)** | `references/wayle` | `crates/wayle-widgets/src/` (PipeWire/WirePlumber audio, UPower battery, NetworkManager, BlueZ) |
| **System Tray & D-Bus Streams** | `references/icebar` | `src/modules/tray.rs`, `src/subscription.rs` (StatusNotifierWatcher, D-Bus menu streaming, zbus) |
| **Settings GUI & IPC** | `references/wayle` & `references/capsule` | `crates/wayle-settings/`, `crates/app/src/settings/` (macOS/GTK style preferences app layout, sidebar, tabs) |
| **GPUI Component Catalog (75+ Primitives)** | `references/gpui-kit` / crates.io `gpui-kit` | `crates/component/src/` (Button, Switch, Slider, Popover, Dialog, Tooltip, Input, Menu, Tabs, Calendar) |
| **Shell Runtime, WGPU Shaders & Protocols** | `references/pleamar` | `src/gpu.rs`, `src/render.rs`, `src/shape.wgsl`, `src/platform/` (Wayland layer-shell, Pure-Rust audio/PulseAudio, wgpu/wgsl rendering pipeline) |
| **Dynamic Island Morphing, Satellites & Settings (GPUI Shell)** | `references/capsule` | `crates/app/src/capsule/` (orbit, satellite, morphing state, modules), `crates/app/src/lockscreen/`, `crates/app/src/settings/` |
| **Unified Launcher & Dev Dashboard** | `references/minflair` | `config/quickshell/Modules/Launcher/`, `Modules/Dashboard/`, `Modules/ControlCenter/` |

---

## 3. Strict Coding & Architecture Rules

1. **Pure & Declarative `render()`**:
   - `render()` must be 100% pure and side-effect free.
   - **PROHIBITED inside `render()`**: `window.focus()`, `window.activate_window()`, `window.refresh()`, `cx.notify()`, and spawning tasks (`cx.spawn`).
   - Focus must ONLY be requested upon explicit window open or mode transition events, never during paint passes.
2. **Wayland Layer-Surface Commits**:
   - In GPUI's Wayland backend, setter methods (`set_keyboard_interactivity`, `set_input_region`, `set_exclusive_zone`) unconditionally commit the layer surface (`surface.commit()`), prompting the compositor to issue `configure` and triggering `request_redraw()`.
   - NEVER call surface setters inside `render()` without a strict cache diff:
     ```rust
     if self.cached_state != Some(desired_state) {
         self.cached_state = Some(desired_state);
         window.set_state(desired_state);
     }
     ```
3. **Element Reconciliation & Dynamic Loops**:
   - Any interactive element with `.hover(...)`, `.on_click(...)`, or event handlers created inside an iterator or loop MUST be given a unique, stable ID (e.g., `.id(("cal-day", day as u32))`). Failing to do so invalidates the hit-test tree every frame and causes severe frame drops.
4. **Zero-Panic Policy**:
   - Never use `unwrap()`, `expect()`, or manual panics in production shell code.
   - Propagate errors using `anyhow::Result`, `thiserror`, or handle defaults gracefully.
5. **Zero Main-Thread Blocking**:
   - NEVER invoke blocking CLI commands (`nmcli`, `bluetoothctl`, `wpctl`, `brightnessctl`) inside GPUI's UI thread.
   - All platform interactions must live behind Tokio async tasks (`beskar-services`), communicating with GPUI via channels (`tokio::sync::mpsc` or `broadcast`).

---

## 4. The 4-Agent Implementation & Review Protocol

When building, updating, or refactoring features in Beskar, work proceeds through four specialized roles:

1. **Role 1: Architect / Spec Agent**
   - Studies the reference repositories (`references/`).
   - Writes or updates the detailed sub-plan in `docs/plans/`.
   - Defines struct/enum contracts, Wayland layer-shell geometry, and component layout.
2. **Role 2: Implementation Agent**
   - Ports battle-tested logic from references into `crates/beskar-*`.
   - Composes views using `gpui-kit` primitives (`Button`, `Slider`, `Switch`, `Input`, `Calendar`).
   - Wires background Tokio services to GPUI entity channels.
3. **Role 3: Reviewer / UX & Security Agent**
   - Validates that `render()` is pure and side-effect free.
   - Checks that layer-surface setters are guarded by cache comparisons.
   - Verifies the zero-panic policy (no `unwrap()`).
   - Validates compliance with `.agents/skills/gpui-kit-design-guides/SKILL.md`.
4. **Role 4: QA & Integration Agent**
   - Runs `cargo check --workspace` and `cargo test --workspace`.
   - Verifies fractional scaling, multi-monitor safety, and keybinding interactions.

---

## 5. Mandatory GPUI Kit Component Usage

Always use `gpui_kit::component` primitives:
- **Sliders**: `gpui_kit::component::slider::Slider` (Volume, Brightness).
- **Toggles & Switches**: `gpui_kit::component::switch::Switch` (Wi-Fi, Bluetooth, DND, Night Light).
- **Calendar**: `gpui_kit::component::calendar::Calendar` (Date notch drop-down, agenda).
- **Buttons & Chips**: `gpui_kit::component::button::Button`, `Chip`, `Badge`.
- **Search Inputs**: `gpui_kit::component::input::Input` with debounce, clear triggers, and prefix icons.
- **Scrollable Containers**: `gpui_kit::component::scroll::Scrollable` with auto-managed scrollbars.
- **Tabs & Sidebars**: `gpui_kit::component::tabs::Tabs`, `Sidebar` for Standalone Settings.
- **Data Tables & Lists**: `gpui_kit::component::table::DataTable`, `VirtualList` for package management and app search.

---

## 6. Master Plans Directory

- Master Architecture Blueprint: [`docs/plans/MASTER_SHELL_BLUEPRINT.md`](file:///home/nsp/Documents/p/beskar/beskar/docs/plans/MASTER_SHELL_BLUEPRINT.md)
- Sub-Plan 01: Top Bar & Dynamic Notch: [`docs/plans/01_TOP_BAR_AND_DYNAMIC_NOTCH.md`](file:///home/nsp/Documents/p/beskar/beskar/docs/plans/01_TOP_BAR_AND_DYNAMIC_NOTCH.md)
- Sub-Plan 02: Middle Drawer Panels: [`docs/plans/02_MIDDLE_DRAWER_PANELS.md`](file:///home/nsp/Documents/p/beskar/beskar/docs/plans/02_MIDDLE_DRAWER_PANELS.md)
- Sub-Plan 03: Unified Bottom Launcher: [`docs/plans/03_UNIFIED_BOTTOM_LAUNCHER.md`](file:///home/nsp/Documents/p/beskar/beskar/docs/plans/03_UNIFIED_BOTTOM_LAUNCHER.md)
- Sub-Plan 04: Standalone Settings & Extensions: [`docs/plans/04_STANDALONE_SETTINGS_AND_EXTENSIONS.md`](file:///home/nsp/Documents/p/beskar/beskar/docs/plans/04_STANDALONE_SETTINGS_AND_EXTENSIONS.md)
- Sub-Plan 05: Multi-Agent Execution & QA: [`docs/plans/05_MULTI_AGENT_EXECUTION_AND_QA.md`](file:///home/nsp/Documents/p/beskar/beskar/docs/plans/05_MULTI_AGENT_EXECUTION_AND_QA.md)
