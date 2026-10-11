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
| **Settings GUI & IPC** | `references/wayle` | `crates/wayle-settings/`, `crates/wayle-ipc/` (macOS/GTK style preferences app layout) |
| **GPUI Component Catalog (75+ Primitives)** | `references/gpui-kit` / crates.io `gpui-kit` | `crates/component/src/` (Button, Switch, Slider, Popover, Dialog, Tooltip, Input, Menu, Tabs) |
| **Shell Runtime, WGPU Shaders & Protocols** | `references/pleamar` | `src/gpu.rs`, `src/render.rs`, `src/shape.wgsl`, `src/platform/` (Wayland layer-shell, Pure-Rust audio/PulseAudio, wgpu/wgsl rendering pipeline) |

---

## 3. Implementation Workflow Rules

1. **Check References First**: Before creating or modifying any file, search `references/` with `grep_search` or `view_file` to find the exact working implementation.
2. **Direct Extraction**: Port the data structures, error handling, socket/D-Bus loops, and layout algorithms directly into the Beskar workspace.
3. **Preserve Isolation**: Never modify files inside `references/` or allow git to track them. All references must remain read-only upstream mirrors.
4. **Fast Compilation & Verifiability**: Ensure all copied modules compile cleanly and integrate into Beskar's modular crate architecture (`crates/beskar-*`).

---

## 4. Installed Workspace Skills: GPUI Kit & Design Guides

The repository includes specialized agent skills under `.agents/skills/`. Agents **must** read and follow these guides when building or styling UI components:

1. **`gpui-kit` Skill** ([`.agents/skills/gpui-kit/SKILL.md`](file:///home/nsp/Documents/p/beskar/beskar/.agents/skills/gpui-kit/SKILL.md)):
   - **Normative Coding Guides**: Read before making architecture, state-ownership, public API, naming, or testing decisions.
   - Covers: Component catalogs (`Button`, `Input`, `Select`, `Dialog`, `Sheet`, `Tabs`, `Sidebar`, `List`, `DataTable`, `Slider`, `Switch`), state management, global state, window overlays, async tasks, contexts, and `ElementId`.
2. **`gpui-kit-design-guides` Skill** ([`.agents/skills/gpui-kit-design-guides/SKILL.md`](file:///home/nsp/Documents/p/beskar/beskar/.agents/skills/gpui-kit-design-guides/SKILL.md)):
   - **Normative Design Guides**: Read before designing or altering any screen, layout, spacing, visual hierarchy, color density, interaction state, overlay, or motion curve.
   - Pairs with the `iRiS` and `Suzuha` aesthetic rules to ensure premium desktop craftsmanship.

---

## 5. Mandatory GPUI Kit Component Catalog & Usage Rules

**Do not build hand-rolled UI primitives with unstyled `div()`s.** Always reach for the battle-tested, accessible primitives provided by `gpui-kit` (`gpui_kit::component`):

### 1. Basic Components
- **`Button`** (`gpui_kit::component::button::Button`): Interactive buttons with primary, secondary, danger, and ghost variants.
- **`Slider`** (`gpui_kit::component::slider::Slider`): Value selection from a range (use for volume, display brightness). Never roll custom mouse-drag progress bars.
- **`Switch`** / **`Toggle`** (`gpui_kit::component::switch::Switch`): Binary on/off control (use for Wi-Fi, Bluetooth, DND, Notch mode).
- **`Badge`** / **`Tag`** (`gpui_kit::component::badge::Badge`): Status indicators, counts, and category labels.
- **`Spinner`** / **`Progress`** (`gpui_kit::component::spinner::Spinner`): Async loading indicators and determinate progress rings.
- **`Tooltip`** (`gpui_kit::component::tooltip::Tooltip`): Hover hints for icons and controls.
- **`Avatar`**, **`Kbd`**, **`Label`**, **`Accordion`**, **`Collapsible`**: Structured content, shortcuts, and expandable panels.

### 2. Form Components
- **`Input`** (`gpui_kit::component::input::Input`): Single-line text input with clear triggers, icons, and focus management (use for app search, wallpaper search, clipboard filter).
- **`Textarea`**, **`Select`**, **`Combobox`**, **`ColorPicker`**, **`NumberInput`**: Complex inputs and picker surfaces.

### 3. Layout & Overlay Components
- **`Scrollable`** (`gpui_kit::component::scroll::Scrollable`): Standardized scroll container with mouse-wheel tracking and scrollbars. Always use for scrollable lists to avoid boundary clipping.
- **`Dialog`**, **`Sheet`**, **`Popover`**: Modals, slide-ins, and floating popups with automatic backdrop dismissal.
- **`Notification`**: Window-level toast notifications.
- **`Sidebar`**, **`Toolbar`**, **`StatusBar`**: Structural application layouts.

### 4. Advanced Components
- **`Command`**: Searchable command palette.
- **`List`** / **`VirtualList`**: High-performance virtualized list rendering for large datasets (e.g. app launchers, clipboard history).
- **`DataTable`**, **`Tabs`**, **`Tree`**, **`Menu`**: Tabbed and hierarchical interfaces.

---

## 6. Deep Module Architecture Directives (`/codebase-design`)

To prevent recurring regressions such as clipped surfaces, unresponsive clicks, and UI thread freezes:

1. **Deep Overlay Architecture**:
   - Do NOT duplicate LayerShell window options and backdrop logic across 10 individual overlays.
   - Overlays must be managed through a deep `OverlayHost` module with a minimal interface (`cx.open_overlay(...)` / `cx.close_overlay(...)`).
   - The implementation encapsulates: full-screen LayerShell scrims (`TOP | BOTTOM | LEFT | RIGHT`), mutual exclusivity mutexes, backdrop click dismissal, Escape keybindings, and focus trap.

2. **Zero Main-Thread Blocking**:
   - NEVER invoke blocking CLI commands (`nmcli`, `bluetoothctl`, `wpctl`, `brightnessctl`) inside GPUI's UI thread (`cx.update`, `render`, or `View::new`).
   - All platform interactions must live behind async adapters or `tokio::task::spawn_blocking` to guarantee a 60/120 FPS responsive shell.

3. **Strict LayerShell Geometry Bounds**:
   - Modals and overlays must never use sub-screen fixed window sizes that can be outgrown by dynamic content.
   - Use fullscreen transparent scrims with sized inner cards and bounded internal scroll containers (`.overflow_y_scroll()`).
