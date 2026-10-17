# Sub-Plan 02: Middle Drawer Panels (Left GitHub & Right Control Center)

> **Module Focus:** Middle Left (GitHub Dev Panel) & Middle Right (Control Center Drawer)  
> **Target Crates:** `crates/beskar-ui`, `crates/beskar-shell`, `crates/beskar-services`  
> **Upstream References:**  
> - `references/minflair/config/quickshell/Modules/ControlCenter/` (Control Center layout, toggles, audio sink selector)  
> - `references/minflair/config/quickshell/Modules/Dashboard/` (GitHub contribution heatmap, vitals)  
> - `references/wayle/crates/wayle-widgets/src/` (PipeWire volume/sinks, NetworkManager, UPower)  
> - `references/suzuha/src/theme.rs` (Glass acrylic backdrop styling)

---

## 1. Spatial Layout & Layer-Shell Scrim Model

Both the Left and Right drawers are positioned mid-screen vertically. To avoid multi-surface conflicts and click-through bugs, each drawer uses a **Full-Screen Transparent Scrim** with an inner card anchored to the respective edge.

```
+-----------------------------------------------------------------------------------------------------------------------------+
| FULL-SCREEN TRANSPARENT SCRIM (TOP | BOTTOM | LEFT | RIGHT, Layer: Overlay, Exclusive Zone: 0)                             |
|                                                                                                                             |
| ┌──────────────────────────────────────────────┐                   ┌────────────────────────────────────────────────────┐   |
| │  GITHUB DEV DASHBOARD                       │                   │ 󰒓 CONTROL CENTER                                   │   |
| │ ──────────────────────────────────────────── │                   │ ────────────────────────────────────────────────── │   |
| │  1,842 contributions in the last year        │                   │  QUICK TOGGLES:                                    │   |
| │  [■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■] │                   │  [ 󰖩 Wi-Fi: Home5G ]   [ 󰂯 Bluetooth: On ]       │   |
| │  Current Streak: 48 days | Longest: 112 days │                   │  [ 󰍛 Do Not Disturb ]  [ 󰃡 Night Light: 4500K ]   │   |
| │                                              │                   │  [ 󰔎 Dark Theme ]     [ 󰕲 Screen Record ]        │   |
| │  ACTIVE PULL REQUESTS:                       │                   │                                                    │   |
| │  • #142: feat(shell): unified launcher [PR]  │                   │  AUDIO OUTPUT SINK:                                │   |
| │  • #89:  fix(bar): fractional scaling  [CR]  │                   │  [ 󰋋 Headphones (HD 650)                      ▼ ] │   |
| │                                              │                   │  Volume:     [=========O=============] 68%         │   |
| │  SYSTEM DEV VITALS:                          │                   │                                                    │   |
| │  CPU: 12% | RAM: 4.8 / 32 GB | Disk: 48%     │                   │  DISPLAY BRIGHTNESS:                               │   |
| │                                              │                   │  Backlight:  [==============O========] 80%         │   |
| │  ACTIVE REPOSITORIES:                        │                   │                                                    │   |
| │  • ~/p/beskar (feature/unified-shell *)      │                   │  POWER PROFILE & BATTERY:                          │   |
| │  • ~/p/gpui-kit (main)                       │                   │  [ Eco ]  [● Balanced ]  [ Performance ]           │   |
| │                                              │                   │  Battery: 94% (Discharging, 6h 12m remaining)      │   |
| └──────────────────────────────────────────────┘                   │  [ 󰒓 Open All Settings ]                           │   |
|   (Middle-Left Drawer: Width: 420px)                               └────────────────────────────────────────────────────┘   |
|                                                                      (Middle-Right Drawer: Width: 380px)                    |
+-----------------------------------------------------------------------------------------------------------------------------+
```

---

## 2. Middle-Left: GitHub Contribution Graph & Dev Dashboard

### Architecture & Data Flow
1. **GitHub Telemetry Engine (`beskar_services::github`)**:
   - Queries GitHub GraphQL API for the user's `contributionsCollection` (52-week calendar grid: dates, counts, hex colors).
   - Local disk cache (`~/.cache/beskar/github_contributions.json`) with an hourly TTL to prevent API rate-limiting.
   - Calculates streak metrics (Current Streak, Longest Streak, Total Commits).
   - Ingests active open Pull Requests assigned to the user or requesting review.
2. **Local Git & System Vitals**:
   - Scans configured project folders (e.g., `~/Documents/p/*`) for active git branch status and uncommitted changes.
   - Polling CPU and Memory load via non-blocking `sysinfo` queries executed in Tokio background tasks.

### Heatmap Grid Rendering
- Grid rendered via GPUI layout primitives: 52 columns x 7 rows.
- Each contribution square has 4 intensity levels mapped to the active theme palette (`beskar_theme::palette`).
- Hovering any square triggers a `gpui_kit::component::tooltip::Tooltip` showing exact date and commit count.

---

## 3. Middle-Right: Unified Control Center

### Quick Toggles Matrix
- Built using `gpui_kit::component::switch::Switch` or toggleable `gpui_kit::component::button::Button` with active indicator badges.
- **Wi-Fi Toggle**: Reads NetworkManager active connection, toggles wireless interface, opens Wi-Fi network selection list.
- **Bluetooth Toggle**: Reads BlueZ power status, connected devices (AirPods, keyboards, mouse).
- **Do Not Disturb (DND)**: Toggles notification suppression state in `beskar_services::notifications`.
- **Night Light**: Controls Wayland gamma temperature via `wlsunset` or compositor IPC.
- **Dark / Light Theme**: Switches between dark and light HSL palettes in `beskar_theme::engine`.

### PipeWire Audio Sinks & Volume
- Uses `pulseaudio` / PipeWire native bindings from `beskar_services::audio`.
- Dropdown selector for active audio sink (Speakers, USB DAC, Bluetooth Headphones) using `gpui_kit::component::select::Select`.
- Volume adjustment using `gpui_kit::component::slider::Slider`:
  - Instant tactile feedback without audio clipping.
  - Mute toggle button.

### Display Backlight Brightness
- Reads and updates `/sys/class/backlight` via `beskar_services::backlight`.
- Controlled via `gpui_kit::component::slider::Slider`.

### Power Profiles & Battery
- Communicates with `power-profiles-daemon` over D-Bus (`net.hadess.PowerProfiles`).
- Segments: `Power Saver`, `Balanced`, `Performance` using `gpui_kit::component::tabs::Tabs` or segmented button group.
- Reads UPower battery state, health percentage, and time-to-empty / time-to-full.

---

## 4. GPUI Kit Component Usage Guide

```rust
// Control Center UI Excerpt
use gpui_kit::component::{
    button::{Button, ButtonVariant},
    slider::Slider,
    switch::Switch,
    tooltip::Tooltip,
};

// 1. Audio Slider
Slider::new("volume-slider", self.volume)
    .min(0.0)
    .max(1.0)
    .step(0.01)
    .on_change(cx.listener(|this, val, cx| {
        this.set_system_volume(val);
    }));

// 2. Quick Toggle Button
Button::new("toggle-wifi")
    .variant(if self.wifi_enabled { ButtonVariant::Primary } else { ButtonVariant::Ghost })
    .icon("wifi")
    .label("Home5G")
    .on_click(cx.listener(|this, _, cx| {
        this.toggle_wifi();
    }));
```

---

## 5. Implementation Milestones

- [ ] **M2.1: Scrim & Drawer LayerShell Host**
  - Create reusable `DrawerHost` view supporting left and right slide-in animations.
  - Implement backdrop dismissal on click and Escape keybinding.
- [ ] **M2.2: GitHub Telemetry & Heatmap Widget**
  - Implement GitHub GraphQL contribution fetcher with token support and local caching.
  - Build 52x7 contribution square grid with hover tooltips and streak calculations.
  - Implement active PR cards and repository status list.
- [ ] **M2.3: Control Center Quick Toggles Matrix**
  - Connect NetworkManager, BlueZ, DND, and Theme engine to toggle buttons.
  - Add smooth transition indicators for connected states.
- [ ] **M2.4: PipeWire Audio & Brightness Sliders**
  - Embed `gpui_kit::component::slider::Slider` for volume and backlight.
  - Implement sink switching menu for output devices.
- [ ] **M2.5: Power Profiles & Battery Telemetry**
  - Connect D-Bus proxy for `power-profiles-daemon`.
  - Display battery charging rate and remaining time estimates.
