# Beskar roadmap

What is missing compared with iNiR / iRiS 3.0, in the order we want to do it. Tick a box when it is done and tested
(on the live shell where possible, otherwise in a nested niri, as `AGENTS.md` describes).

## Done so far
- [x] Frame, islands, panels that grow out of the bar and the dock
- [x] Music, notifications (grouping optional), capture and recording, app switcher, session dialog, Spotlight
- [x] Settings (8 tabs, real controls), lock screen (PAM, no bypass), idle lock (off by default)
- [x] Desktop widgets (9 kinds), edit mode with grid / tidy / undo / presets, widget bar grown out of the dock
- [x] Colour engine from the wallpaper (Tonal / Vibrant / Neutral / Soft), applied to the whole shell
- [x] Wallpaper painted by pleamar (circle / fade / wipe reveal), `awww` removed
- [x] Other apps wear the theme: kitty, alacritty, ghostty, foot, GTK 3/4 + libadwaita (Files), Qt

## 1. Things that break or confuse in daily use
- [x] **Polkit agent**: a password dialog when an app needs admin rights (`polkit.plm`; tested with `pkexec true`: dialog, wrong password, cancel)
- [x] **First run and install**: `./beskar install | doctor | update | welcome`, first-run welcome (3 pages), niri wired through an include file
- [ ] **Power and display basics**
  - [ ] Night light
  - [ ] Power profiles (performance / balanced / saver) in the Control Center
  - [ ] Game mode (quiet the shell while a game runs)
  - [ ] Privacy dots: camera / microphone in use

## 2. Big visible features
- [ ] **Window overview and live previews** (pleamar `thumbnails` service) in the app switcher, an overview and the dock
- [ ] **The Island, second round**: timers, charging, screenshots, camera / mic as live activities in the centre pill
- [ ] **Widgets, second round**
  - [ ] Notes and to-do (saved to a file)
  - [ ] World clock and timers
  - [ ] Lyrics, screen time
  - [ ] Stacks (several widgets in one place) and saved desktops
  - [ ] Widgets on the lock screen
- [ ] **Wallpaper features**
  - [ ] Transition picker in Settings (circle / fade / wipe + slide, zoom, blinds, random)
  - [ ] Favourites, web sources (Wallhaven)
  - [ ] Pause live wallpapers under a maximised window; video wallpapers (skwd-wall or similar)

## 3. Polish and ecosystem
- [ ] Emoji picker, hot corners, keyboard cheat-sheet overlay, screenshot region selector with annotation
- [ ] Languages (dates and texts follow the system language)
- [ ] Use more of the wallpaper palette (text, cards, status colours)
- [ ] Lock screen: Caps Lock warning; turn on idle lock once unlocking is proven twice in a row
- [ ] Banner swipe-to-dismiss, top bar auto-hide, Focus mode, calendar events (needs a source)
- [ ] Top bar performance (it is the heaviest scene, about 8 to 9 % of a core)
- [ ] Plugins / a hub for widgets and themes (large; only when the rest is stable)

## Not planned
- Mascot and decorative widgets from iNiR; Wallpaper Engine scenes unless asked for.
