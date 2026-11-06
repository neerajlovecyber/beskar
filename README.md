#  Beskar macOS Shell

A modern, fluid, GPU-accelerated macOS desktop shell for Wayland compositors (Niri, Hyprland, Sway), powered by the **Pleamar** engine.

Featuring native hardware frosted glass shaders (`frost: auto`), spring physics animations, and zero-thread freezes.

---

## 🌟 Key Features

- ** Top Menu Bar (`shell/topbar.plm`)**:
  - Apple menu (``), active window/app title, standard macOS menus (`File`, `Edit`, `View`, `Window`, `Help`).
  - Right status bar with battery percentage and charging indicator, Wi-Fi status, volume status, Control Center trigger, date, and clock.
- **🏝️ Bottom Dock (`shell/dock.plm`)**:
  - Floating frosted glass capsule with rounded corners.
  - Interactive icon magnification with spring physics (`scale = 1.0 + hot * 0.28`).
  - Running app indicator dots and launch bindings.
- **🔍 Spotlight Search (`shell/spotlight.plm`)**:
  - Centered overlay modal with frosted glass background.
  - Real-time application search and filter over desktop `.desktop` entries.
  - Keyboard navigation (`Up`, `Down`, `Enter` to launch, `Escape` to dismiss).
- **🎛️ Control Center (`shell/control_center.plm`)**:
  - Frosted glass popover in the top-right corner.
  - Wi-Fi and Bluetooth connectivity cards.
  - Focus / Do Not Disturb card.
  - Real-time Display Brightness and Audio Volume sliders.
  - Now Playing / Media Player card with MPRIS playback controls.
- **⚡ Rock-Solid Performance**:
  - Decoupled spring renderer running directly in WGPU at 120+ FPS.
  - The rendering engine never hangs or freezes, even during heavy system load.
  - Sub-200ms cold start and ~80 MB RAM usage.

---

## 🚀 Quick Start

### 1. Launch the Shell
To start all macOS shell components:
```bash
./shell/start.sh
```

To stop all running components:
```bash
./shell/start.sh stop
```

---

## ⌨️ Compositor Keybindings

Add the following shortcuts to your compositor configuration:

### For Hyprland (`~/.config/hypr/hyprland.conf`)
```ini
# Toggle Spotlight Search (Super + Space)
bind = SUPER, SPACE, exec, /home/nsp/Documents/p/beskar/beskar/shell/start.sh spotlight

# Toggle Control Center (Super + C)
bind = SUPER, C, exec, /home/nsp/Documents/p/beskar/beskar/shell/start.sh control-center
```

### For Niri (`~/.config/niri/config.kdl`)
```kdl
binds {
    Mod+Space { spawn "/home/nsp/Documents/p/beskar/beskar/shell/start.sh" "spotlight"; }
    Mod+C     { spawn "/home/nsp/Documents/p/beskar/beskar/shell/start.sh" "control-center"; }
}
```

---

## 📁 Project Structure

```text
beskar/
├── bin/
│   └── pleamar                     # Compiled Pleamar release binary
├── shell/
│   ├── common/
│   │   └── palette.plm             # Apple HIG color definitions
│   ├── topbar.plm                  # Top Menu Bar scene
│   ├── dock.plm                    # Bottom Dock scene
│   ├── dock.luau                   # App launcher logic
│   ├── spotlight.plm               # Spotlight search scene
│   ├── spotlight.luau              # App filtering & launch logic
│   ├── control_center.plm          # Control Center popover scene
│   ├── control_center.luau         # Sliders & MPRIS control logic
│   └── start.sh                    # Unified startup & CLI controller
└── README.md
```
