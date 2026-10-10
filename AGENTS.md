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
