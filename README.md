# 🛡️ Beskar Shell

A modular, hyper-performance Wayland desktop shell forged in pure **Rust** utilizing **GPUI** (Zed's vector GPU rendering engine via `wgpu`).

Beskar merges modern macOS aesthetics with an advanced GPU-accelerated **"Dynamic Island"** architecture, heavily inspired by the layout flexibility of **minflair** (Island Style) and **iNiR** (iRiS Island Engine), paired with the liquid color engine of **Suzuha**.

---

## 🌟 Key Features

- **🚀 Pure Rust & GPUI Engine**: Zero Electron, WebViews, QML runtime overhead, or GTK wrappers. Renders directly onto the GPU via `wgpu` with native Wayland LayerShell integration (`zwlr_layer_shell_v1`) locked at **120+ FPS**.
- **🏝️ 3-Region Dynamic Island Topology**:
  - **Left Island**: Workspace indicators, active application titles, and task switcher.
  - **Dynamic Center Island**: Compact capsule pill that smoothly yields and morphs into media player controls (MPRIS), notification banners, and status popups with spring physics.
  - **Right Island**: System hardware monitors (PipeWire volume slider, UPower battery, NetworkManager WiFi, power profiles, and `StatusNotifierItem` system tray).
- **🎨 Dual Aesthetic Modes**:
  - **Floating Island Mode**: Individual detached pills with backdrop blur and rounded borders.
  - **Convex Notch Mode**: Seamlessly anchored to the screen's top bezel with concave cubic Bézier fillets blending into the screen edge.
- **⚡ First-Class Compositor Integration**:
  - **[Niri](https://github.com/YaLTeR/niri)** (*Primary target*): Direct Unix socket communication via `niri-ipc` with real-time workspace and window event streams.
  - **[Umbriel](https://github.com/noctalia-dev/umbriel)** (*Secondary target*): Deep support for Noctalia's wlroots + SceneFX compositor.
  - **Hyprland / wlroots**: Compositor abstraction trait allowing transparent fallback.
- **🧩 Component Catalog powered by GPUI Kit**: Reusable accessible UI primitives (buttons, switches, sliders, popovers, tooltips, dialogs) backed by `gpui-kit`.

---

## 🏗️ Workspace Architecture

Beskar is structured as a modular Cargo workspace:

```text
beskar/
├── Cargo.toml
├── AGENTS.md                  # Reference reuse & coding directives
├── references/                # Isolated upstream reference bank (read-only)
└── crates/
    ├── beskar-core/           # CompositorBackend trait, data models, event bus
    ├── beskar-compositor/     # Niri IPC, Umbriel/wlroots, and Hyprland drivers
    ├── beskar-services/       # Non-blocking async D-Bus daemons (MPRIS, Tray, Battery, Audio)
    ├── beskar-theme/          # Wallpaper HSL dynamic color engine & iRiS style tokens
    ├── beskar-ui/             # GPUI island containers, morphing pills, and widgets
    └── beskar-shell/          # Main application binary and LayerShell window lifecycle
```

---

## 📦 Requirements

- **Linux** running a Wayland compositor (Niri, Umbriel, or Hyprland recommended).
- **Rust Toolchain**: 1.85+ (Edition 2024 support).
- **System Libraries**:
  - `wayland-client`
  - `pipewire` / `wireplumber` (for audio hardware controls)
  - `upower` & `networkmanager` (for battery and WiFi monitors)

---

## 🛠️ Getting Started

### 1. Clone the repository
```bash
git clone https://github.com/your-username/beskar.git
cd beskar
```

### 2. Verify compilation
```bash
cargo check --workspace
```

### 3. Run Beskar Shell
```bash
cargo run -p beskar-shell
```

---

## 📚 Upstream References & Proven Mechanics

Beskar enforces code reuse from battle-tested desktop shells isolated under `references/`:

| Upstream Project | Key Components Referenced |
| :--- | :--- |
| **`gpui-shell`** | Wayland LayerShell options, fractional scaling fixes, `niri-ipc` state tracking |
| **`inir` (iRiS)** | Dynamic Island layout geometry, spring physics, satellite yielding |
| **`minflair`** | Convex notch Bézier curve mathematics (`ConvexShape.qml`) |
| **`suzuha` & `amane`** | Dynamic wallpaper-derived HSL color engine and glass acrylic shaders |
| **`wayle`** | Pure Rust hardware widgets (PipeWire, UPower, BlueZ, NetworkManager) & settings GUI |
| **`icebar`** | Asynchronous `zbus` D-Bus streams (`tray.rs`, `subscription.rs`) |
| **`gpui-kit`** | 75+ polished GPUI desktop component primitives |

For development directives and guidelines, see [**`AGENTS.md`**](AGENTS.md).

---

## 📜 License

MIT License. Designed and crafted with precision for high-performance Linux desktops.
