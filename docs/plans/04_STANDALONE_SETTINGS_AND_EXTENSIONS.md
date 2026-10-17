# Sub-Plan 04: Standalone Settings & Extension Manager

> **Module Focus:** Standalone Preferences Application & Extension Ecosystem  
> **Target Crates:** `crates/beskar-ui`, `crates/beskar-shell`, `crates/beskar-services`, `crates/beskar-theme`  
> **Upstream References:**  
> - `references/minflair/config/quickshell/Modules/Settings/` & `PackageManager/` (Settings views, package list)  
> - `references/capsule/crates/app/src/settings/` (GPUI Settings sidebar, views, layout)  
> - `references/wayle/crates/wayle-settings/` (macOS/GTK style preferences app layout)

---

## 1. Application Architecture & Navigation

The Settings application is built as a top-level, standalone application surface (either Wayland `xdg-toplevel` or high-layer window) using a Master-Detail layout with GPUI Kit primitives:

```
+-----------------------------------------------------------------------------------------------------------------------------+
| BESKAR SETTINGS                                                                                                  [—] [□] [✕] |
+-----------------------------------------------------------------------------------------------------------------------------+
| ┌───────────────────────────┐ ┌───────────────────────────────────────────────────────────────────────────────────────────┐ |
| │ 🔍 Search Settings...     │ │  KEYBINDS CHEAT SHEET & MANAGER                                                           │ |
| │                           │ │  ───────────────────────────────────────────────────────────────────────────────────────  │ |
| │  PREFERENCES              │ │  Search shortcuts: [ 🔍 Filter by action or key... ]                                      │ |
| │  󰌌 Keybinds               │ │                                                                                           │ |
| │  󰏔 Package & Extensions   │ │  WINDOW MANAGEMENT:                                                                       │ |
| │  󰔎 Appearance & Themes    │ │  • Close Focused Window         [ Super + Q         ]  [ Edit ]                           │ |
| │  󰋋 Audio & Hardware       │ │  • Toggle Floating / Tile       [ Super + Space     ]  [ Edit ]                           │ |
| │  󰍹 Displays & Notch        │ │  • Toggle Fullscreen Mode       [ Super + F         ]  [ Edit ]                           │ |
| │                           │ │                                                                                           │ |
| │  COMPOSITOR               │ │  SHELL SURFACES:                                                                          │ |
| │  󰑣 Niri / Hyprland Rules  │ │  • Open Bottom Unified Launcher [ Super + D         ]  [ Edit ]                           │ |
| │  󰖩 Network & Bluetooth    │ │  • Toggle Control Center        [ Super + C         ]  [ Edit ]                           │ |
| │  󰒓 System Information     │ │  • Toggle GitHub Dashboard      [ Super + G         ]  [ Edit ]                           │ |
| └───────────────────────────┘ └───────────────────────────────────────────────────────────────────────────────────────────┘ |
|   (Sidebar Width: 240px)        (Detail Content Surface: Responsive Width)                                                  |
+-----------------------------------------------------------------------------------------------------------------------------+
```

---

## 2. Core Functional Views

### 1. Keybinds Cheat Sheet & Custom Shortcut Editor
- **Interactive Cheat Sheet**:
  - Automatically loads configured keybindings from Niri (`~/.config/niri/config.kdl`) and Hyprland (`~/.config/hypr/hyprland.conf`).
  - Categorized under: Window Management, Workspaces, Launchers & Shell Surfaces, Media Controls, and Screenshots.
- **Shortcut Recorder Modal**:
  - Clicking `[ Edit ]` opens a recorder modal that intercepts raw Wayland key events (`Super`, `Alt`, `Ctrl`, `Shift` + Key).
  - Built-in conflict detection: Alerts the user if the combination is already mapped.
  - Automatically updates the compositor config file without syntax errors.

### 2. Package Manager & Extension Store
Inspired by Minflair and Capsule's plugin architecture:
- **Catalog View**:
  - Lists available extensions, widgets, dynamic notch cards, and community themes.
  - Displays extension icon, name, author, version, description, and status tag (`Installed`, `Update Available`, `Disabled`).
  - Built using `gpui_kit::component::table::DataTable` and `Badge`.
- **Extension Life Cycle**:
  - Enable / disable toggle using `gpui_kit::component::switch::Switch`.
  - One-click install/uninstall through Git clone or tarball extraction into `~/.local/share/beskar/extensions/`.
  - Sandboxed runtime configuration schemas (JSON/TOML).

### 3. Appearance, Dynamic HSL Themes & Blur Shaders
- **Color Engine**:
  - Generates full color palettes dynamically from current wallpaper using `beskar_theme::hsl` and `palette.rs`.
  - Manual color adjustments: Primary Accent, Surface Glass, Background Opacity, Border Radius.
- **Convex Notch & Convex Bar Adjustments**:
  - Live slider controls for fillet curve tension, notch height, notch width, and spring damping.
- **Glass Acrylic Backdrop Shaders**:
  - Custom WGSL shader parameters: Blur radius, chromatic aberration, saturation boost, noise grain.

---

## 3. GPUI Kit Component Bindings

```rust
use gpui_kit::component::{
    button::Button,
    input::Input,
    sidebar::Sidebar,
    switch::Switch,
    table::{DataTable, TableColumn},
    tabs::Tabs,
};

// Keybinding Editor Row
div()
    .flex()
    .items_center()
    .justify_between()
    .child(div().child("Open Unified Launcher"))
    .child(
        div()
            .flex()
            .gap_2()
            .child(Kbd::new("Super + D"))
            .child(Button::new("edit-btn").label("Edit").on_click(cx.listener(|this, _, cx| {
                this.record_keybinding("open_launcher");
            })))
    )
```

---

## 4. Implementation Milestones

- [ ] **M4.1: Standalone Application Window & Navigation**
  - Implement Master-Detail layout with `Sidebar` and smooth view transitions.
  - Implement top-bar search filter for quick preference discovery.
- [ ] **M4.2: Keybinds Reader & Conflict-Safe Editor**
  - Parse Niri KDL and Hyprland config files.
  - Build interactive key recorder modal with modifier combination tracking.
- [ ] **M4.3: Package & Extension Manager**
  - Define extension manifest schema (`manifest.json`: id, version, permissions, entrypoint).
  - Build `DataTable` extension listing with install, remove, and toggle switches.
- [ ] **M4.4: Appearance, Theme & Shader Controls**
  - Expose live HSL palette adjustments, wallpaper selection, and blur sliders.
  - Persist user configuration in `~/.config/beskar/config.json`.
