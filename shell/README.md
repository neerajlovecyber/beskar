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
| **App Switcher** | [`shell/appswitcher.plm`](appswitcher.plm) | macOS Cmd+Tab application switcher HUD showing running windows from niri/Wayland with active selection capsule and focus switching. |
| **Clipboard History** | [`shell/clipboard.plm`](clipboard.plm) | macOS Super+V Clipboard Manager with live cliphist history, 1-click restore/paste, and Clear All action. |
| **System Settings** | [`shell/settings.plm`](settings.plm) | Dedicated macOS 2-column System Settings app: Appearance, Displays (eDP-1 + HDMI-A-1), Sound, Wi-Fi, Bluetooth, Notifications, Wallpaper picker (awww), Software Update (yay/pacman), and About This Mac specs. |
| **Lock Screen** | [`shell/lock.plm`](lock.plm) | Native Wayland session lock (`ext-session-lock` protocol) with full-screen blur, Apple typography clock, avatar, password verification via PAM, and spring headshake. |
| **Session Dialog** | [`shell/session.plm`](session.plm) | macOS Shutdown/Restart/Logout confirmation dialog with 60-second automatic timer and window reopen toggle. |
| **Screen Capture & Record HUD** | [`shell/capture.plm`](capture.plm) | macOS Cmd+Shift+5 floating HUD with Entire Screen, Selected Window, Selected Area capture (`grim`+`slurp`), and video recording (`wf-recorder`). |
| **Frame (top bar + dock)** | [`shell/topbar.plm`](topbar.plm) | One full-screen glass silhouette: a thin ring round all four edges with curved inner corners, three content-sized islands hanging from the top, and the dock rising from the bottom. Islands are as wide as their content and morph with springs. Logic (workspace, weather, app launch) in `topbar.luau`. |
| **Control Center** | [`shell/control_center.plm`](control_center.plm) | 4-page panel: overview, Wi-Fi picker, Bluetooth picker, Audio outputs selector, and Appearance/Glass look customizer. |
| **Notification Center** | [`shell/notifications.plm`](notifications.plm) | The notification server. The bell opens a centre of macOS-style cards (icon, bold title, two lines of body, hover ×, Clear All); a new notification also drops a banner from the right island. |
| **Wallpapers** | [`shell/wallpapers.plm`](wallpapers.plm) | Super+W picker: thumbnails of `~/Pictures/wallpapers`, Beskar's built-in wallpapers (`assets/wallpapers/`, from iNiR) and the system's; applies with a transition (awww) and remembers the choice. |
| **Dashboard** | [`shell/dashboard.plm`](dashboard.plm) | Drops from the centre island when you click the clock: date, live weather, CPU / memory / disk, world clocks. |
| **Bezel OSD (HUD)** | [`shell/osd.plm`](osd.plm) | Centered floating bezel HUD for Volume and Brightness adjustments with auto-dismiss timer and spring physics. |
| **Spotlight Search** | [`shell/spotlight.plm`](spotlight.plm) | Centered search bar with live fuzzy filtering of desktop applications, arrow-key navigation, and Enter to launch. |
| **Apple Menu** | [`shell/apple_menu.plm`](apple_menu.plm) | Dropdown providing quick access to About, System Settings, Screen Lock, Reboot, and Power off. |
| **Supervisor & CLI** | [`shell/start.sh`](start.sh) | Process supervisor, theme persistence, and CLI hotkey runner. |

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
./shell/start.sh notifications         # Toggle Notification Center & Widgets (recommend: Super+N)
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
