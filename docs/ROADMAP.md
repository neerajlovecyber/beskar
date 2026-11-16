# Beskar roadmap

Current customization priorities: [Customization plan](archive/CUSTOMIZATION_PLAN.md) (2026-11-14), with audited gaps, phased scope and acceptance criteria.
Broader feature priorities and reference review: [Next features and unification](archive/NEXT_FEATURES_PLAN.md). This file remains the inventory; the linked plans define upcoming slices.

Feature inventory compared with the iNiR / iRiS references; the customization plan records the latest local snapshot inspected. Tick a box when it is done and tested
(on the live shell where possible, otherwise in a nested niri, as `AGENTS.md` describes).

## Done so far
- [x] Frame, islands, panels that grow out of the bar and the dock
- [x] Music, notifications (grouping optional), capture and recording, app switcher, session dialog, Spotlight
- [x] Settings (8 tabs, real controls), lock screen (PAM, no bypass), idle lock (off by default)
- [x] Desktop widgets (12 kinds), edit mode with grid / tidy / undo / presets, widget bar grown out of the dock
- [x] Shared notes and to-dos in Today and desktop widgets, one editor, autosave and Undo
- [x] Colour engine from the wallpaper (Tonal / Vibrant / Neutral / Soft), applied to the whole shell
- [x] Wallpaper painted by pleamar (circle / fade / wipe reveal), `awww` removed
- [x] Other apps wear the theme: kitty, alacritty, ghostty, foot, GTK 3/4 + libadwaita (Files), Qt

## 1. Things that break or confuse in daily use
- [x] **Polkit agent**: a password dialog when an app needs admin rights (`polkit.plm`; tested with `pkexec true`: dialog, wrong password, cancel)
- [x] **First run and install**: `./beskar install | doctor | update | welcome`, first-run welcome (3 pages), niri wired through an include file
- [ ] **Power and display basics**
  - [x] Night light (Settings → Night Light & Power: off / always / sunset to sunrise, three warmths; wlsunset)
  - [x] Power profiles (saver / balanced / performance) in Settings → Night Light & Power (a Control Center tile is still to do)
  - [ ] Game mode (quiet the shell while a game runs)
  - [x] Privacy dots: camera / microphone in use (bar)

## 2. Big visible features
- [x] **Window overview and live previews** (pleamar `thumbnails` service) in the app switcher, an overview and the dock
- [x] **The Island, second round**: timers, charging, screenshots, camera / mic as live activities in the centre pill
- [ ] **Widgets, second round**
  - [x] Notes and to-do (shared Personal owner and saved content)
  - [x] Shared timer with panel, widget, pause/resume and restart recovery
  - [ ] World clock
  - [ ] Lyrics, screen time
  - [ ] Stacks (several widgets in one place) and saved desktops
  - [ ] Widgets on the lock screen
- [ ] **Wallpaper features**
  - [ ] Transition choice in the existing wallpaper picker (circle / fade / wipe; C2a); extra effects later
  - [ ] Favourites, web sources (Wallhaven)
  - [ ] Pause live wallpapers under a maximised window; video wallpapers (skwd-wall or similar)

## 3. Customization
- [ ] Search individual settings from Settings and Spotlight; safe group defaults and undo (C1)
- [ ] Validated, versioned, atomic preference saves with backwards-compatible loading (C1)
- [ ] Saved looks, reduced motion, bounded typography/density and theme targets (C2)
- [ ] Bar module visibility/order, dock pin ordering/sizing and output policy (C3)
- [ ] Named saved desktops and per-widget options; then stacks (C4)
- [ ] Selective data-only import/export with recovery and Beskar-owned shortcut editing (C5)
- [ ] Quiet policies and independent display Keep/Revert recovery (C6)

## 4. Polish and ecosystem
- [ ] Emoji picker, hot corners, keyboard cheat-sheet overlay, screenshot region selector with annotation
- [ ] Languages (dates and texts follow the system language)
- [ ] Use more of the wallpaper palette (text, cards, status colours)
- [ ] Lock screen: Caps Lock warning; turn on idle lock once unlocking is proven twice in a row
- [ ] Banner swipe-to-dismiss, top bar auto-hide, Focus mode, calendar events (needs a source)
- [x] Top bar performance (idle CPU at ~0.2%, music playback frames halved, background polls and process storms eliminated)
- [ ] Plugins / a hub for widgets and themes (large; only when the rest is stable)

## Not planned
- Mascot and decorative widgets from iNiR; Wallpaper Engine scenes unless asked for.
