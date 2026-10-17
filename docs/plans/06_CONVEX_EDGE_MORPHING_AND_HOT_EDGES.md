# Sub-Plan 06: Convex Edge-Morphing, Full-Screen Scrims & Hot Edges

> **Module Focus:** Complete Shell Spatial Restructuring & Minflair/Capsule Convex Edge Parity  
> **Target Crates:** `crates/beskar-ui`, `crates/beskar-shell`  
> **Upstream References:**  
> - `references/minflair/config/quickshell/Modules/Bar/Styles/Convex/ConvexDesktop.qml` (Full-screen scrim canvas)  
> - `references/minflair/config/quickshell/Modules/Bar/Styles/Convex/ConvexPanels.qml` (Unified drawer manager & outside-click dismiss)  
> - `references/minflair/config/quickshell/Modules/Bar/Styles/Convex/ConvexDrawerShape.qml` (Convex Bézier curve edge math)  
> - `references/minflair/config/quickshell/Modules/Bar/Styles/Convex/ConvexBottomHost.qml` (Bottom drawer morphing)  
> - `references/minflair/config/quickshell/Core/Windows/SidebarWindow.qml` (Left/Right edge-docked sliding drawers)  
> - `references/capsule/crates/app/src/panel.rs` & `capsule/animator.rs` (GPUI LayerShell full-span options & spring animator)

---

## 1. Problem Diagnosis: Why Current UI Floats & Feels Broken

The user correctly identified that current panels appear as isolated, disconnected rectangles floating arbitrarily in the middle of the screen:
1. **Arbitrary Margins & Floating Windows**:
   - `PanelHost::open` currently creates standalone `LayerShell` windows sized strictly to the card (e.g. 460x740) with `margin: (px(48.0), px(16.0), px(0.0), px(0.0))` or `(px(0.0), px(0.0), px(54.0), px(0.0))`.
   - Result: Panels float disconnected from the display bezels, looking like generic floating popups rather than a bespoke desktop environment shell.
2. **Missing Scrim & Click-Through Bugs**:
   - Because the window bounds only cover the small card, clicking anywhere else on the screen clicks through to client apps (terminals, browsers) and **cannot close the drawer**.
3. **Missing Convex Bézier Edge Fillets**:
   - In Minflair, drawers are not simple rounded rectangles. The edge that touches the screen bezel has **convex Bézier fillets** (`flareWidth: 36, flareHeight: 36`) that curve outward and merge into the screen bezel (`ConvexDrawerShape.qml`).
4. **Lack of Hot Edges**:
   - Moving the cursor to screen boundaries does nothing. In Minflair and modern Wayland shells, touching the left/right/bottom edge smoothly triggers drawer expansion.
5. **Lack of Edge-Attached Slide & Morph**:
   - Panels pop into existence without emerging from the screen border.

---

## 2. Target Spatial Architecture (Convex Edge-Attached Model)

```
+-----------------------------------------------------------------------------------------------------------------------------+
| FULL-SCREEN TRANSPARENT LAYER-SHELL SCRIM (TOP | BOTTOM | LEFT | RIGHT, exclusive_zone: None, Layer: Overlay)              |
| Outside Click -> Dismisses Active Open Drawer                                                                               |
|                                                                                                                             |
| ┌────────────────────────────────────────────────┐                                       ┌────────────────────────────────┐ |
| │ [LEFT SCREEN EDGE: x = 0]                      │                                       │    [RIGHT SCREEN EDGE: x = W]  │ |
| │ ╭───────────────────────                       │                                       │                        ──────╮ │ |
| │ │ GITHUB DEV DASHBOARD  (Convex Top Flare)     │                                       │ (Convex Top Flare)   CONTROL │ │ |
| │ │                                              │                                       │                       CENTER │ │ |
| │ │ 52-Week Contribution Heatmap                 │                                       │ Quick Toggles Matrix         │ │ |
| │ │ Commit Streaks & Active PRs                  │                                       │ PipeWire Volume & Brightness │ │ |
| │ │ System Vitals (CPU/RAM/Disk)                 │                                       │ Power Profiles & Battery     │ │ |
| │ │                                              │                                       │                              │ │ |
| │ ╰───────────────────────                       │                                       │                        ──────╯ │ |
| │ (Convex Bottom Flare)                          │                                       │ (Convex Bottom Flare)          │ |
| └────────────────────────────────────────────────┘                                       └────────────────────────────────┘ |
|                                                                                                                             |
|                                                                                                                             |
|                                    ┌────────────────────────────────────────────────────────┐                               |
|                                    │  ╭──────────────────────────────────────────────────╮  │                               |
|                                    │  │  BOTTOM UNIFIED OMNI-LAUNCHER / SPOTLIGHT BAR    │  │                               |
|                                    │  │  Math Calculator • Desktop Apps • Power Actions  │  │                               |
|                                    │  ╰──────────────────────────────────────────────────╯  │                               |
|                                    │  [BOTTOM SCREEN EDGE: y = H, Convex Bezel Fillets]     │                               |
|                                    └────────────────────────────────────────────────────────┘                               |
+-----------------------------------------------------------------------------------------------------------------------------+
```

---

## 3. Four Core Implementation Pillars

### Pillar 1: Full-Screen Layer-Shell Scrim Host
- Redesign `PanelHost` in `crates/beskar-shell/src/panel_host.rs`:
  - When opening a drawer/panel, `PanelHost` opens a **Full-Screen Transparent LayerShell Window** spanning the display:
    `LayerAnchor::TOP | LayerAnchor::BOTTOM | LayerAnchor::LEFT | LayerAnchor::RIGHT`.
  - Margin: `(px(0.0), px(0.0), px(0.0), px(0.0))`.
  - Exclusive Zone: `None`.
  - Transparent background (`WindowBackgroundAppearance::Transparent`).
  - Outside-click backdrop: A full-screen interactive surface intercepts clicks outside the inner drawer and invokes `PanelHost::close(cx)`.
  - Keyboard Focus: `KeyboardInteractivity::OnDemand` with an Escape key listener to close active drawers.

### Pillar 2: Edge-Attached Geometry & Morphing
- Instead of centered or disconnected floating boxes:
  - **Left Drawer (Dashboard)**: Positioned at `origin.x = 0`, vertically centered (or flush with top bar). Slides in along the X axis from `-width` to `0`.
  - **Right Drawer (Control Center)**: Positioned at `origin.x = display_width - drawer_width`, flush with the right screen bezel. Slides in along the X axis from `+width` to `0`.
  - **Bottom Drawer (Omni-Launcher / Clipboard / Power)**: Positioned at `origin.y = display_height - drawer_height`, centered horizontally, flush with the bottom screen bezel. Slides in along the Y axis from `+height` to `0`.
  - **Dynamic Center Notch**: Morphs downwards from the top bar bezel (`top: 0`), growing dynamically from the notch dimensions.

### Pillar 3: Convex Bézier Edge Fillet Primitives (`ConvexEdgeShape`)
- Implement `ConvexDrawerContainer` in `crates/beskar-ui/src/widgets/convex_shape.rs`:
  - Mathematical curve equivalent to Minflair's `ConvexDrawerShape.qml`:
    - **Left Edge Drawer**: The left border is straight against the screen edge (`x = 0`). The top-left and bottom-left junctions feature continuous cubic Bézier outward flares (`flareWidth: 28px, flareHeight: 28px`) transitioning smoothly into the screen edge.
    - **Right Edge Drawer**: The right border is straight against `x = width`. Top-right and bottom-right junctions flare into the right screen bezel.
    - **Bottom Edge Drawer**: The bottom border is straight against `y = height`. Bottom-left and bottom-right junctions flare into the bottom screen bezel.

### Pillar 4: Wayland Hot-Edges Engine
- In `crates/beskar-shell/src/hot_edges.rs`:
  - Deploy lightweight, invisible edge trigger strips on the display boundaries:
    - **Left Hot Edge**: 2px wide strip spanning the left screen height. On cursor enter / hover -> opens Left Drawer.
    - **Right Hot Edge**: 2px wide strip spanning the right screen height. On cursor enter / hover -> opens Right Control Center Drawer.
    - **Bottom Hot Edge**: 2px high strip spanning the bottom screen width. On cursor enter / hover -> opens Bottom Launcher.
  - Debounce timer (e.g. 120ms dwell time) prevents accidental triggers during window resizing or fast cursor travel.
  - Configurable toggle in Settings (`enable_hot_edges`).

---

## 4. Implementation Phasing & Work Breakdown

- [ ] **Step 1: ScrimHost Container (`PanelHost` Overhaul)**
  - Rewrite `panel_host.rs` to spawn full-screen scrim windows with backdrop dismissal.
  - Implement `ScrimContainer` view wrapping panel contents with edge-anchored alignment (`Left`, `Right`, `Bottom`, `Center`).
- [ ] **Step 2: Convex Bézier Edge Shape Component**
  - Implement `ConvexDrawerContainer` with edge-fillet geometry for `Left`, `Right`, and `Bottom` edges.
  - Replace generic floating card wrappers in `DashboardView`, `ControlCenterView`, and `LauncherView`.
- [ ] **Step 3: Edge Slide & Morph Animations**
  - Implement smooth transition progress (`0.0 -> 1.0`) so drawers slide smoothly out of the screen bezel.
- [ ] **Step 4: Wayland Hot-Edges Trigger Strips**
  - Create `HotEdgesManager` registering 2px layer-shell edge sensors on `TOP`, `LEFT`, `RIGHT`, `BOTTOM`.
- [ ] **Step 5: Top Bar App Launcher & Edge Integration**
  - Ensure top bar app launcher and workspace buttons trigger the edge-docked bottom launcher smoothly.
- [ ] **Step 6: Build Verification & Regression Tests**
  - Run `cargo check --workspace` and unit test suites to ensure 0 errors and 0 warnings.
