# Beskar Desktop Shell — Minflair Pure-Rust Porting Blueprint & Plan

This document establishes the architecture, deep exploration protocol, and execution roadmap for porting **Minflair** (QML/Quickshell) to **Pure Rust** (GPUI + `gpui-kit`) within the Beskar workspace.

---

## Master Phase Checklist & Progress Tracker

- [x] **Phase 1: Foundation Theme Tokens & Power Menu (`powerMenu`)** `[COMPLETED]`
  - [x] Deep Exploration of `PowerMenuContent.qml`, `ActionMenu.qml`, and `Theme.qml`
  - [x] Implement Semantic Theme Tokens in `beskar-theme` matching Minflair
  - [x] Implement 2-Stage Horizontal `PowerMenuWidget` in `beskar-ui`
  - [x] Wire Keyboard Navigation (Arrow Keys, Enter, Space, Escape)
  - [x] Wire Real Process Execution (`systemctl`, `loginctl`, `niri`)
  - [x] Integrate into `beskar-shell` with centered LayerShell geometry & exclusive focus grab
  - [x] Verify compilation cleanly across all workspace crates
- [x] **Phase 2: App Discovery Engine & Full App Launcher (`launcher`)** `[COMPLETED]`
  - [x] Deep Exploration of `LauncherContent.qml`, `LauncherItemDelegate.qml`, `scripts/get_apps.py`
  - [x] Scan Flatpak export applications (`~/.local/share/flatpak/exports/...` and `/var/lib/flatpak/...`) in `beskar-services`
  - [x] Implement Minflair obsidian glass `LauncherWidget` with live prefix/contains/category scoring
  - [x] Add windowed list display (max 8 visible items matching Minflair)
  - [x] Category-based Lucide icons and active `↵ Open` action pill
  - [x] Wire keyboard navigation & live typing event loop in `LauncherView` (letters, backspace, space, up/down arrows, enter, escape, readline shortcuts)
  - [x] Centered LayerShell window geometry (640×460px, top margin 100px, exclusive focus)
- [ ] **Phase 3: Dynamic Bar Host & Bar Styles (`Convex`, `Island`, `Gaming`)** `[NEXT UP]`
  - [ ] Deep Exploration of `BarStyleConfig.qml`, `BarWidgetLoader.qml`, `ConvexShape.qml`, `IslandBar.qml`, `GamingBar.qml`
  - [ ] Full Sub-plan & Architecture Specification
  - [ ] Implementation & Check-off
- [ ] **Phase 4: Multi-Page Control Center (`controlCenter`) & Hardware D-Bus** `[PENDING]`
  - [ ] Deep Exploration of `QuickSettings.qml`, NetworkManager, and BlueZ scripts
  - [ ] Full Sub-plan & Architecture Specification
  - [ ] Implementation & Check-off
- [ ] **Phase 5: Wallpaper Selector (`wallpaper`) & Dynamic Palette Engine** `[PENDING]`
  - [ ] Deep Exploration of `WallpaperSelectorContent.qml`, `WallpaperManager.qml`, `generate_theme.py`
  - [ ] Full Sub-plan & Architecture Specification
  - [ ] Implementation & Check-off
- [ ] **Phase 6: Notifications Center & Standalone Preferences GUI** `[PENDING]`
  - [ ] Deep Exploration of `NotificationService.qml` and `Settings.qml`
  - [ ] Full Sub-plan & Architecture Specification
  - [ ] Implementation & Check-off

---

## 1. System Architecture Mapping (Minflair ➔ Pure Rust)

```
┌────────────────────────────────────────────────────────────────────────┐
│                        beskar-shell (Main Runtime)                     │
│  - LayerShell Manager (Top Bar, Centered Overlays, Anchored Popovers)  │
│  - AppState Coordinator (Focus grabs, Slot exclusivity, Dismissals)   │
└──────────────────────────────────┬─────────────────────────────────────┘
                                   │
       ┌───────────────────────────┴───────────────────────────┐
       ▼                                                       ▼
┌─────────────────────────────────┐   ┌──────────────────────────────────┐
│     beskar-ui (Pure Rust)       │   │  beskar-services (Pure Rust)     │
│  - Bar Styles (Convex / Island) │   │  - SettingsService (JSON store)  │
│  - Dynamic Slot Loader          │   │  - Audio (Pulse/PipeWire)        │
│  - Power Menu (2-stage)         │   │  - NetworkManager & BlueZ D-Bus  │
│  - Launcher (Live Fuzzy Search) │   │  - Wallpaper & Matugen Theme     │
│  - Control Center Multi-Page    │   │  - Freedesktop Notifications     │
└──────────────┬──────────────────┘   └────────────────┬─────────────────┘
               │                                       │
               └───────────────────┬───────────────────┘
                                   ▼
┌────────────────────────────────────────────────────────────────────────┐
│             beskar-theme (Semantic Tokens & Spring Physics)            │
│  bg, bg_secondary, bg_tertiary, fg, muted, border, accent, complementary│
└────────────────────────────────────────────────────────────────────────┘
```

---

## 2. Phase 1 Deep Exploration & Technical Specification

### Upstream References Inspected
- `references/minflair/config/quickshell/Modules/PowerMenu/PowerMenuContent.qml`
- `references/minflair/config/quickshell/Core/Components/ActionMenu.qml`
- `references/minflair/config/quickshell/Core/Theme.qml`
- `references/minflair/config/quickshell/Core/Constants.qml`

### Visual & Behavioral Mechanics from Minflair
1. **Dimensions**:
   - Each button is `64px` wide × `48px` (`Constants.size5Xl`) tall.
   - Default 5-button strip: width = `320px`, height = `48px`.
   - Card container: `8px` padding around the buttons, corner radius `16px` (`Constants.sizeLg`), frosted obsidian acrylic background (`hsla(240, 0.16, 0.08, 0.95)`), specular top highlight border (`hsla(0, 0, 1.0, 0.14)`).
2. **Action Model**:
   - `Lock`: Icon `Lock`, Label `"Lock"`, Command `loginctl lock-session`, `confirm: false`.
   - `Suspend`: Icon `Moon`, Label `"Suspend"`, Command `systemctl suspend`, `confirm: true`.
   - `Logout`: Icon `LogOut`, Label `"Logout"`, Command `niri msg action quit --skip-confirmation`, `confirm: true`.
   - `Reboot`: Icon `RotateCw`, Label `"Reboot"`, Command `systemctl reboot`, `confirm: true`.
   - `Shutdown`: Icon `Power`, Label `"Shutdown"`, Command `systemctl poweroff`, `confirm: true`.
3. **Stage 1 (Main Menu)**:
   - Horizontal list of 5 action items.
   - Active/focused item has filled accent pill (`Theme.accent`, radius `12px`).
   - Hovered item has `Theme.bgSecondary`.
   - Left/Right arrow keys navigate `currentIndex` (0..4).
   - Return / Enter / Space triggers selected action.
   - Escape closes the overlay.
4. **Stage 2 (Confirmation Prompt)**:
   - If triggered action has `confirm: false` (Lock): immediately executes command and dismisses overlay.
   - If triggered action has `confirm: true` (Suspend, Logout, Reboot, Shutdown):
     - View switches to confirmation stage.
     - Left side: bold label `"Confirm <Action>?"`.
     - Right side: two buttons:
       - `Cancel` (Icon `X`, label `"Cancel"`): resets back to Stage 1.
       - `Confirm` (Icon `Check`, label `"Confirm"`): executes command and dismisses overlay.
     - Left/Right arrow keys switch between Cancel (0) and Confirm (1).
     - Escape cancels and returns to Stage 1.

### Phase 1 Execution Plan (Status: COMPLETED)
1. **File Edits**:
   - `crates/beskar-ui/src/widgets/power_menu.rs`: Rewrote `PowerMenuWidget` implementing 2-stage state machine (Horizontal 5-button strip + Confirmation prompt), mouse hover/click callbacks, and obsidian glass styling.
   - `crates/beskar-shell/src/overlays.rs`: Updated `PowerMenuView` to manage active index, confirmation mode, keyboard events (Left, Right, Space, Return, Escape), and dispatch real system commands. Centered LayerShell geometry (`Anchor::TOP`, `margin: 64px`, `KeyboardInteractivity::Exclusive`).
2. **Interactive Testing & Build**:
   - Verified cleanly with `cargo check` and `cargo test`.

---

## 3. Phase 2 Deep Exploration & Technical Specification: App Launcher (`launcher`)

### Upstream References Inspected
- `references/minflair/config/quickshell/Modules/Launcher/LauncherContent.qml`
- `references/minflair/config/quickshell/Modules/Launcher/Components/LauncherItemDelegate.qml`
- `references/minflair/config/quickshell/Modules/Launcher/scripts/get_apps.py`

### Visual & Behavioral Mechanics from Minflair
1. **Window Dimensions & LayerShell**:
   - Centered on screen: `Anchor::TOP`, `margin_top = 100px`, `KeyboardInteractivity::Exclusive`.
   - Width: `640px`.
   - Dynamic Height: Auto-sized to `search_bar_height (52px) + (visible_items.min(8) * 44px) + padding`.
2. **Interactive Live Search Input**:
   - Full keyboard typing support (character insertion, backspace, space, delete).
   - Filter matches case-insensitively against `name`, `local_name`, `categories`, and `exec`.
   - Instant live list re-computation with zero latency.
3. **Keyboard Navigation Contract**:
   - `Down Arrow`: moves `selected_idx` forward (clamped to `filtered_apps.len() - 1`).
   - `Up Arrow`: moves `selected_idx` backward (clamped to 0).
   - `Enter / Return`: launches selected application via `setsid sh -c <exec>` and dismisses launcher.
   - `Escape`: clears search text if not empty; if already empty, dismisses launcher overlay.
4. **Item Presentation (`LauncherItemDelegate`)**:
   - Item height: `44px`, corner radius `14px`.
   - Icon: `24px` × `24px` with resolved system icon path or SVG rocket fallback.
   - App Name: Primary font (`14px`), bold accent color when selected.
   - Category Badge: Subtitle badge on right edge indicating category (e.g., `Utility`, `Development`, `Internet`).
   - Active highlight: Glowing accent outline / background pill (`Theme.accent`).
5. **Execution Results (Status: COMPLETED)**:
   - `crates/beskar-services/src/desktop.rs`: Added Flatpak desktop exports paths (`~/.local/share/flatpak/exports/...` and `/var/lib/flatpak/...`).
   - `crates/beskar-ui/src/widgets/launcher.rs`: Implemented `LauncherWidget` with live search bar, dynamic prefix/word/contains/category scoring, 8-item windowed list view, category Lucide icons, and obsidian styling.
   - `crates/beskar-shell/src/overlays.rs`: Wired `LauncherView` with dedicated message channel, typing input, readline shortcuts (`Ctrl+N`, `Ctrl+P`, `Ctrl+U`, `Ctrl+C`), Up/Down arrows, Enter key app execution via `beskar_services::launch_app`, and ESC key clearing/dismissal. Centered LayerShell window geometry (640×460px, top margin 100px, exclusive focus).

---

## 4. Phase 3 Deep Exploration & Technical Specification: Dynamic Bar Host & Bar Styles (`Convex`, `Island`, `Gaming`)

### Upstream References Inspected
- `references/minflair/config/quickshell/Modules/Bar/Bar.qml`
- `references/minflair/config/quickshell/Modules/Bar/BarStyleConfig.qml`
- `references/minflair/config/quickshell/Modules/Bar/Styles/Convex/ConvexBar.qml`
- `references/minflair/config/quickshell/Modules/Bar/Styles/Convex/ConvexShape.qml`
- `references/minflair/config/quickshell/Modules/Bar/Styles/Island/IslandBar.qml`
- `references/minflair/config/quickshell/Modules/Bar/Styles/Gaming/GamingBar.qml`
- `references/minflair/config/quickshell/Modules/Bar/Components/BarWidgetLoader.qml`
- `references/minflair/config/quickshell/Modules/Bar/Components/Workspaces.qml`
- `references/minflair/config/quickshell/Modules/Bar/Components/SystemTrayGroup.qml`

### Visual & Behavioral Mechanics from Minflair
1. **Bar Style Modes**:
   - `BarStyle::Convex`:
     - Continuous top bar running across screen width.
     - Signature center Convex Notch dipping downward (`width: 380px`, `notch_height: 38px`, `fillet_radius: 16px`).
     - Uses inverse Bézier curves (`ConvexShape.qml`) connecting top wings to the center notch smoothly without harsh sharp angles.
     - Center notch hosts Dynamic Clock, Date, and Audio Cava / Vitals mini bars.
     - Left wing hosts Workspaces pill (`Workspaces.qml`) and Minflair app launcher button.
     - Right wing hosts System Tray (`SystemTrayGroup.qml`), Control Center toggle, and Power button.
   - `BarStyle::Island`:
     - 3 detached floating pills over the wallpaper (matching `IslandBar.qml`):
       - **Left Island**: Workspaces pill (active workspace indicator, urgent indicator, click to switch workspace).
       - **Center Island**: Dynamic Island pill (Clock / Date with hover reveal for music player & cava).
       - **Right Island**: Status & System Tray pill (Network, Volume, Battery, System Tray icons, Control Center trigger, Power button).
     - Margin: `8px` from top screen edge.
   - `BarStyle::Gaming`:
     - High-contrast cyber telemetry bar with compact stats and latency counters.
2. **Dynamic Slot Loader Architecture (`BarWidgetLoader`)**:
   - Left Slot: `[MinflairButton, Workspaces]`
   - Center Slot: `[Clock, Media, DynamicCenter]`
   - Right Slot: `[SystemTray, Vitals, ControlCenterButton, PowerButton]`
   - Each widget is an independent Pure-Rust GPUI component implementing the `RenderOnce` contract.
3. **Persistent Settings & Real-Time Switching**:
   - `SettingsService` stores `bar_style: BarStyle` (`Convex`, `Island`, `Gaming`).
   - The shell can hot-swap bar layouts or adjust bar height and padding instantaneously without restarting.

### Phase 3 Execution Plan
1. **Crate Layering**:
   - `crates/beskar-theme/src/tokens.rs`: Define `BarStyle` enum (`Convex`, `Island`, `Gaming`).
   - `crates/beskar-ui/src/bar/`:
     - `convex.rs`: `ConvexBarWidget` with SVG Bézier path / smooth fillet notch.
     - `island.rs`: `IslandBarWidget` with 3 detached floating islands.
     - `gaming.rs`: `GamingBarWidget` cyber layout.
     - `loader.rs`: `BarWidgetLoader` dispatching to slots (`Left`, `Center`, `Right`).
   - `crates/beskar-shell/src/bar.rs`: Update main top bar LayerShell window to render the active `BarStyle` dynamically.
2. **Interactive Testing & Build**:
   - Verify all 3 bar styles render cleanly in Pure Rust without layout errors or clipping.

