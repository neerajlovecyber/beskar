# Beskar

A macOS-style glass desktop shell for the [niri](https://github.com/YaLTeR/niri) Wayland compositor,
written in [pleamar](https://github.com/k4ditano/pleamar): declarative scenes (`.plm`) drawn on the GPU,
with small sandboxed Luau scripts (`.luau`) for the logic.

It is one thin glass **frame** round the whole screen (a ring, three islands hanging from the top, a dock
rising from the bottom), plus the panels you open from it: Control Center, notifications, Spotlight,
clipboard history, wallpapers, Settings and a lock screen. It looks like a Mac, but it is its own thing: nothing
is named after Apple, and nothing is hard-coded to one machine.

> **Status:** a personal project under active development, tested on one machine (CachyOS, niri,
> two monitors). Expect rough edges. Issues and pull requests are welcome.

---

## What's in it

**The frame** (`shell/topbar.plm`) is a single glass silhouette, so every junction melts into the next:

- **Left island:** the gem button (opens the power menu: About, Settings, Lock, Sleep, Log Out, Restart, Shut Down), a capsule per workspace of the monitor it is on, then the icons of the apps open in the current workspace (the focused one highlighted).
- **Centre island:** date, time and weather. Click it for the dashboard. It also shows new notifications and the volume / brightness feedback, growing around them.
- **Right island:** tray apps, Wi-Fi (with signal), Bluetooth while a device is connected, battery, Control
  Center, and the notification bell (with an unread count and a Do Not Disturb slash). Each icon does
  something when clicked.
- **Dock:** starts with a file manager and a terminal. Running apps appear with a dot; click to focus or launch,
  right-click to *Keep in Dock* / *Remove from Dock* / *Quit*. It hides while a window is on the monitor and
  comes back when the pointer reaches the bottom edge.
- Islands are as wide as their content and morph with springs when it changes.

**Panels** (one open at a time, the others close). The power menu, Control Center, dashboard and notification centre all grow out of the bar's islands: the island itself stretches down into the panel, as one piece of glass:

| Panel | Opens with | What it does |
| :--- | :--- | :--- |
| **Control Center** | the switches icon, the Wi-Fi / Bluetooth icons, `Super+Shift+C` | Wi-Fi and Bluetooth (join networks with a password, connect, pair, per-app volume), Now Playing with seek, Do Not Disturb, dark mode, brightness and volume sliders, shortcuts |
| **Notifications** | the bell, `Super+N` | The notification server; grows out of the right island. Cards with icon, title and body, hover ×, Clear All, a saved history ("Earlier"), a banner that appears inside the centre pill |
| **Dashboard** | click the clock | Date, live weather, CPU / memory / disk, battery, clocks |
| **Spotlight** | `Super+Space` | Search and launch apps |
| **Clipboard** | `Super+V` | Clipboard history (cliphist) |
| **Wallpapers** | `Super+W` | Thumbnails of your wallpapers and the built-in ones; applies with a transition |
| **Settings** | Control Center → Settings | Appearance (dark mode, glass skin, accent colour), displays, sound, Wi-Fi, Bluetooth, wallpaper, about this PC |
| **Power menu** | the gem button | Grows out of the left island |
| **Lock screen** | `start.sh lock` | `ext-session-lock`, password checked by PAM |
| **Also** | | App switcher, screenshot / screen-recording toolbar, session (shut down / restart / log out) dialog |

**One colour system** (`shell/common/theme.plm`): dark mode, three glass skins and seven accent colours reach every
scene. The accent can follow your wallpaper.

---

## Requirements

- **niri** (workspaces, windows and outputs are read with `niri msg`)
- **[pleamar](https://github.com/k4ditano/pleamar)**, built from source: needs a Rust toolchain. `start.sh` builds it
  into `bin/` the first time if it is missing (expects a checkout at `cloned_repos/pleamar`)
- **matugen** (colours from the wallpaper), **ImageMagick** (`magick`), **fd**, **curl**
- **grim**, **slurp** and **wf-recorder** (screenshots and recording), **wl-clipboard** and **cliphist** (clipboard)
- A **Nerd Font** (a few status glyphs), and a PipeWire/PulseAudio, NetworkManager and BlueZ desktop for the
  audio, Wi-Fi and Bluetooth pages
- Optional: `yay` / `paru` / `pacman` for the software-update page

## Install and run

```bash
git clone https://github.com/neerajlovecyber/beskar
cd beskar
git clone https://github.com/k4ditano/pleamar cloned_repos/pleamar   # the runtime
./shell/start.sh                                                     # builds pleamar if needed, starts everything
```

`./shell/start.sh stop` stops it; `status` and `restart` do what they say. To start it with your session,
run `start.sh` from niri's `spawn-at-startup`.

### niri configuration

Add the shortcuts (use your own path) and keep windows clear of the 6 px ring:

```kdl
layout {
    struts { left 6; right 6; bottom 6; }
}

binds {
    Mod+Space       { spawn "/path/to/beskar/shell/start.sh" "spotlight"; }
    Mod+V           { spawn "/path/to/beskar/shell/start.sh" "clipboard"; }
    Mod+N           { spawn "/path/to/beskar/shell/start.sh" "notifications"; }
    Mod+W           { spawn "/path/to/beskar/shell/start.sh" "wallpapers"; }
    Mod+Shift+C     { spawn "/path/to/beskar/shell/start.sh" "control-center"; }
}
```

The other commands: `settings`, `lock`, `session [0|1|2]`, `capture`, `appswitcher`, `dashboard`,
`vol-up|vol-down|mute`, `bright-up|bright-down`, `dark-mode [on|off]`, `skin [0|1|2]`.

---

## Configuring it

Everything is plain files under your home; nothing is hard-coded.

| File | What it holds |
| :--- | :--- |
| `~/.config/pleamar_shell.json` | Dark mode, glass skin, accent (written by Settings, restored by `start.sh`) |
| `~/.config/beskar/dock` | Pinned dock apps, one desktop id per line (`org.gnome.Nautilus`, `kitty`, …). Delete it for the defaults |
| `~/.config/beskar/tray-hide` | Tray icons to hide, one id per line. nm-applet and blueman are hidden by default; write `-nm-applet` to show one |
| `~/.config/beskar/location` | `LAT LON City` for the weather. Without it the place is looked up once from your IP and saved here |
| `~/.config/beskar/wallpaper` | The wallpaper you picked (restored at login) |
| `~/Pictures/wallpapers` | Your wallpapers (also `~/Pictures/Wallpapers`, `~/Wallpapers`); files named *screenshot* or *mock* are skipped |
| `~/.local/share/beskar/wallpapers` | The built-in wallpapers, copied here from `assets/wallpapers/` |
| `~/.local/share/pleamar/notifications/history.json` | Dismissed notifications ("Earlier") |

---

## How it is built

Each panel is its own pleamar scene, run as its own process by `shell/start.sh`; they talk through
`say <scene> "fact …"`. A few shared pieces keep them consistent:

| Piece | What it does |
| :--- | :--- |
| `shell/common/theme.plm` | The colour tokens and the `dark_mode` / `skin` / `accent` facts, included by every scene |
| `shell/exclusive.luau` | Opening a panel closes the others |
| `shell/location.luau` | Where you are, for the weather and clocks |
| `shell/topbar.plm` + `.luau` | The frame, dock and tray in one scene (one process, drawn on every monitor) |

```text
beskar/
├── assets/wallpapers/       built-in wallpapers (from iNiR, see its README)
├── shell/
│   ├── common/theme.plm     colours
│   ├── *.plm                one scene per panel
│   ├── *.luau               each scene's logic
│   └── start.sh             starts, stops and drives everything
├── docs/                    pleamar's language notes and recipes
├── AGENTS.md                the rules and pitfalls learned while building this
└── bin/                     the pleamar binary (not committed)
```

If you want to change something, read [`AGENTS.md`](AGENTS.md) first: it lists the tools
(`pleamar --check`, `--say … describe`) and the pitfalls (right-click quits a scene unless it has an
`on press right` rule, props on per-monitor surfaces, the Luau sandbox, …).

---

## Credits

- [pleamar](https://github.com/k4ditano/pleamar) by k4ditano, the runtime and language
- [Marea](https://github.com/k4ditano/marea-plm), the reference for notifications, wallpapers, Bluetooth and Wi-Fi handling
- [iNiR](https://github.com/snowarch/iNiR) (GPL-3.0), for the island and frame ideas and the built-in wallpapers;
  artwork credit belongs to the original artists
- The macOS design language is the inspiration; Beskar is not affiliated with Apple

There is no licence file for this repository yet.
