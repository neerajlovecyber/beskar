# macOS Shell for Wayland Compositors (Pleamar Engine)

An ultra-performant, GPU-accelerated macOS Sequoia/Sonoma desktop shell for Wayland compositors (Hyprland, Sway, Pleamar-wm, Wayfire, etc.) engineered with the Pleamar UI declarative engine.

---

## 🖥 Components Architecture

```
                                [ MacTopBar ]
         (Apple Menu · Dynamic Window Title · Status Indicators · Clock)
                                       │
            ┌──────────────────────────┼──────────────────────────┐
            ▼                          ▼                          ▼
     [ MacAppleMenu ]          [ MacControlCenter ]         [ MacWidgets ]
  (About, Power, Reboot)    (Wi-Fi, BT, Sound, Display,  (Calendar, Weather,
                            Now Playing, Dark Mode,      Activity Monitor,
                            Marea Glass Customizer)       World Clock, Notices)
                                       │
                                       ▼
                                [ MacSpotlight ]
                          (System App Fuzzy Search)
                                       │
                                       ▼
                                  [ MacDock ]
                     (Magnification Capsule & App Launch)
```

| Component | File Path | Description |
| :--- | :--- | :--- |
| **App Switcher** | [`shell/appswitcher.plm`](file:///home/nsp/Documents/p/beskar/beskar/shell/appswitcher.plm) | macOS Cmd+Tab application switcher HUD showing running windows from niri/Wayland with active selection capsule and focus switching. |
| **Clipboard History** | [`shell/clipboard.plm`](file:///home/nsp/Documents/p/beskar/beskar/shell/clipboard.plm) | macOS Super+V Clipboard Manager with live cliphist history, 1-click restore/paste, and Clear All action. |
| **System Settings** | [`shell/settings.plm`](file:///home/nsp/Documents/p/beskar/beskar/shell/settings.plm) | Dedicated macOS 2-column System Settings app: Appearance, Displays (eDP-1 + HDMI-A-1), Sound, Wi-Fi, Bluetooth, Notifications, Wallpaper picker (awww), Software Update (yay/pacman), and About This Mac specs. |
| **Lock Screen** | [`shell/lock.plm`](file:///home/nsp/Documents/p/beskar/beskar/shell/lock.plm) | Native Wayland session lock (`ext-session-lock` protocol) with full-screen blur, Apple typography clock, avatar, password verification via PAM, and spring headshake. |
| **Session Dialog** | [`shell/session.plm`](file:///home/nsp/Documents/p/beskar/beskar/shell/session.plm) | macOS Shutdown/Restart/Logout confirmation dialog with 60-second automatic timer and window reopen toggle. |
| **Screen Capture & Record HUD** | [`shell/capture.plm`](file:///home/nsp/Documents/p/beskar/beskar/shell/capture.plm) | macOS Cmd+Shift+5 floating HUD with Entire Screen, Selected Window, Selected Area capture (`grim`+`slurp`), and video recording (`wf-recorder`). |
| **Top Menu Bar** | [`shell/topbar.plm`](file:///home/nsp/Documents/p/beskar/beskar/shell/topbar.plm) | Global 30px bar with Apple icon, dynamic active window title, battery, wifi, volume, Spotlight & Control Center triggers, and clickable clock. |
| **Dock** | [`shell/dock.plm`](file:///home/nsp/Documents/p/beskar/beskar/shell/dock.plm) | Floating bottom capsule with smooth spring magnification physics, running indicators, and specular rim. |
| **Control Center** | [`shell/control_center.plm`](file:///home/nsp/Documents/p/beskar/beskar/shell/control_center.plm) | 4-page panel: overview, Wi-Fi picker, Bluetooth picker, Audio outputs selector, and Appearance/Glass look customizer. |
| **Notification Center & Widgets** | [`shell/widgets.plm`](file:///home/nsp/Documents/p/beskar/beskar/shell/widgets.plm) | Right sliding sidebar featuring Calendar, Weather, Live Activity Monitor (CPU/RAM/Disk), World Clocks, and Notifications stream. |
| **Bezel OSD (HUD)** | [`shell/osd.plm`](file:///home/nsp/Documents/p/beskar/beskar/shell/osd.plm) | Centered floating bezel HUD for Volume and Brightness adjustments with auto-dismiss timer and spring physics. |
| **Spotlight Search** | [`shell/spotlight.plm`](file:///home/nsp/Documents/p/beskar/beskar/shell/spotlight.plm) | Centered search bar with live fuzzy filtering of desktop applications, arrow-key navigation, and Enter to launch. |
| **Apple Menu** | [`shell/apple_menu.plm`](file:///home/nsp/Documents/p/beskar/beskar/shell/apple_menu.plm) | Dropdown providing quick access to About, System Settings, Screen Lock, Reboot, and Power off. |
| **Supervisor & CLI** | [`shell/start.sh`](file:///home/nsp/Documents/p/beskar/beskar/shell/start.sh) | Process supervisor, theme persistence, and CLI hotkey runner. |

---

## 🎨 Themes & Glass Look Modes

### 1. Theme Modes
- **Dark Mode**: Smoked translucent backgrounds (`#161820`), crisp white text (`#f5f7f5`), high-contrast icons.
- **Light Mode**: Frosted bright acrylic (`#f6f7fb`), ink-dark typography (`#1d1d1f`), translucent white cards.

### 2. Glass Styles (Inspired by Marea)
- **Liquid Glass (`skin 0`)**: Deep blurred glass (`frost: 100%`, `glass: 85%`), specular hairline borders, and chromatic aberration free (`dispersion: 0`, `refraction: 0`).
- **Light Acrylic (`skin 1`)**: Soft translucent blur (`glass: 55%`, `tint: 40%`).
- **Classic Solid (`skin 2`)**: High-contrast opaque macOS HIG cards (`glass: 0%`), optimal for power efficiency and minimum compositor overhead.

All theme preferences are automatically persisted to `~/.config/pleamar_shell.json` and synchronized across all shell daemons and system-wide GTK (`gsettings set org.gnome.desktop.interface color-scheme`).

---

## 🚀 CLI Commands & Hotkeys

You can bind these commands to compositor keybindings:

```bash
# Manage Shell Lifecycle
./shell/start.sh              # Start all 11 shell daemons
./shell/start.sh restart      # Restart all components
./shell/start.sh status       # Check running state of all components
./shell/start.sh stop         # Terminate all components

# Interactive Overlays & Hotkeys
./shell/start.sh settings        # Toggle System Settings (recommend: Super+,)
./shell/start.sh lock            # Lock Screen via ext-session-lock (recommend: Super+Ctrl+Q)
./shell/start.sh session [0|1|2] # 0=Shutdown, 1=Restart, 2=Logout modal (recommend: Super+Escape)
./shell/start.sh capture         # Toggle Screen Capture & Record HUD (recommend: Super+Shift+5)
./shell/start.sh spotlight       # Toggle Spotlight search (recommend: Super+Space)
./shell/start.sh control-center  # Toggle Control Center (recommend: Super+C)
./shell/start.sh widgets         # Toggle Notification Center & Widgets (recommend: Super+N)
./shell/start.sh apple-menu      # Toggle Apple Menu (recommend: Super+A)
./shell/start.sh vol-up          # Increase Volume + popup Bezel OSD (XF86AudioRaiseVolume)
./shell/start.sh vol-down        # Decrease Volume + popup Bezel OSD (XF86AudioLowerVolume)
./shell/start.sh mute            # Toggle Mute + popup Bezel OSD (XF86AudioMute)
./shell/start.sh bright-up       # Increase Brightness + popup Bezel OSD (XF86MonBrightnessUp)
./shell/start.sh bright-down     # Decrease Brightness + popup Bezel OSD (XF86MonBrightnessDown)

# Theme Controls
./shell/start.sh dark-mode on    # Switch to Dark Mode
./shell/start.sh dark-mode off   # Switch to Light Mode
./shell/start.sh skin 0          # Switch to Liquid Glass
./shell/start.sh skin 1          # Switch to Light Acrylic
./shell/start.sh skin 2          # Switch to Classic Solid
```
