# Beskar Desktop Shell - Domain Glossary

This document establishes the canonical domain vocabulary for Beskar Shell. Use these terms consistently in code, module names, interfaces, and architecture discussions.

---

### Core Concepts

- **OverlayHost**: The subsystem responsible for opening, closing, and tracking interactive layer-shell surfaces (Launcher, Control Center, Settings, etc.). Enforces full-screen transparent scrims, outside-click dismissal, keyboard focus traps, and mutual exclusivity.
- **IslandBar**: The primary Wayland desktop bar displaying workspaces, active window info, and status islands with smooth convex Bézier fillets.
- **HardwareBus**: Asynchronous platform service abstraction for system hardware (Wi-Fi, Bluetooth, Audio via PipeWire/WirePlumber, Backlight, Battery via UPower, and Power Profiles). Emits non-blocking event streams to the UI.
- **ThemeEngine**: Dynamic color extraction and palette system generating harmonious HSL tokens from the desktop wallpaper with glass acrylic shaders.
- **CompositorBridge**: Compositor IPC connector (Niri, Hyprland, Sway) streaming workspace transitions, window focus changes, and compositor actions.
