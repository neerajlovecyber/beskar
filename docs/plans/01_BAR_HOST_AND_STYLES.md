# Plan 01 — Dynamic Bar Host & Bar Styles (Convex / Island / Gaming)

> **Depends on:** Plan 00 (OverlayHost, Lifecycle, BarHost unified interface, Theme signal, blocking audit).
> Do not start until Plan 00 gate passes.

## 0. Goal

Make the bar the premium Minflair bar: Convex continuous Bézier notch vs Island 3-pill morphing vs Gaming telemetry, with real workspace pill and no thin/ugly regressions.

## 1. References Inspected (read before coding)

| Area | Upstream source | Files |
|------|----------------|-------|
| Convex geometry | `references/minflair` | `Modules/Bar/Styles/Convex/ConvexShape.qml` (getPath 7 segments, flareWidth=18, flareHeight=16, bottomRadius=16, topBezel=2, baseHeight=44), `ConvexBar.qml`, `ConvexCenter.qml`, `ConvexBottomHost.qml`, `ConvexNotifLayer.qml`, `ConvexFrameBezel.qml` |
| Island pills | `references/minflair` | `Modules/Bar/Styles/Island/IslandBar.qml`, `IslandCenterPill.qml`, `IslandLeftPill.qml`, `IslandRightPill.qml`, `IslandClock.qml`, `IslandMediaArt.qml`, `IslandContent.qml`, `IslandNotifLayer.qml`, `IslandBackground.qml` |
| Gaming | `references/minflair` | `Modules/Bar/Styles/Gaming/GamingBar.qml`, `GamingOverlay.qml` |
| Bar host + slots | `references/minflair` | `Modules/Bar/Bar.qml:16-32` (IBarStyle widths), `BarStyleConfig.qml`, `Components/BarWidgetLoader.qml`, `Components/{BarLeftSection,BarCenterSection,BarRightSection}.qml`, `Components/Workspaces.qml`, `Components/SystemTrayGroup.qml` |
| Shell bar pattern | `references/gpui-shell` | `crates/app/src/bar/view.rs`, `crates/ui/src/patterns/bar.rs` (LayerShell, fractional scale, exclusive_zone) |
| Fractional scale | `references/inir`, `references/gpui-shell` | `crates/app/src/state.rs:logical_display_size` (wl_output integer scale vs true logical size) |

## 2. Architecture

```
crates/beskar-ui/src/
  bar/
    mod.rs          <- BeskarBar (IBarStyle: widths/isExpanded/block), Slot loader dispatch
    convex.rs       <- ConvexBarWidget + canvas Bézier notch via gpui::canvas + PathBuilder
    island.rs       <- IslandBarWidget (3 pills + SpringValue morph + ThemedShadow)
    gaming.rs       <- GamingBarWidget (telemetry strip)
    loader.rs       <- BarWidgetLoader Left/Center/Right dispatch (brand/workspaces/clock/media/tray/vitals)
  convex.rs         <- extract getPath() Bézier math into pure fn (already 83-195, wire it)
  pill.rs           <- pill capsule primitive (reuse for workspaces + status capsule)
  spring.rs         <- SpringValue (already exists, used by island center width)
  widgets/
    workspaces.rs   <- 10-slot workspaces (24x8 active capsule, 8x8 dots, 0.65/0.22 opacity)
    vitals.rs       <- nested statusCapsule + standalone power button (clone BarRightSection.qml)
```

`crates/beskar-shell/src/bar/view.rs` owns timers + SystemHub + Vitals + compositor stream + config signal and feeds `BarState` into `BeskarBar::from_state`.

## 3. Tasks (copy, don't reinvent)

### 3.1 Convex Bézier Engine (deep module)

- Extract `references/minflair/.../Convex/ConvexShape.qml:27-69` `getPath(w,h,lW,cX,cW,rW,tb,fw,fh,br,cH,baseH,cbr)` into `crates/beskar-ui/src/convex.rs` pure `fn convex_path(...) -> Path` using `gpui::PathBuilder` cubic Bézier (already drafted). Constants: `baseHeight=44.0`, `flareWidth=18.0`, `flareHeight=16.0`, `bottomRadius=16.0`, `topBezel=2.0`, `borderWidth=1.0, borderColor=rgba(255,255,255,0.08)`.
- Paint via `canvas()` background in `ConvexBarWidget`; add `ThemedShadow` ambient drop (match `ConvexShape.qml:92-100` MultiEffect conditional on `!gameModeActive && powerProfile != "power-saver"`).
- Verify no box artifacts: flares must smoothly meet `topBezel` with inverse Bézier (control-point `0.45`/`0.55` factors from QML), not sharp angles.

### 3.2 Island Morphing Pills

- `IslandBarWidget`: 3 detached floating pills (`margin 8px` from top per `MINFLAIR_PORTING_PLAN:3.1`), each `rounded_full`, `bg=#030107 96%`, lavender accent `#a77ef5`.
- Center pill: compact `180px` → `320px` (media) → `360px` (notification toast) via `SpringValue` (already `bar/view.rs:82-164` adaptive loop: 16ms animating / 300ms idle). Copy `IslandCenterPill.qml` spring params.
- Not spawning detached windows: in-place expand of the pill container, not `PanelHost` overlay. Only tray menu uses overlay.

### 3.3 Gaming Bar

- `GamingBarWidget`: high-contrast cyber strip mirroring `GamingBar.qml` + `GamingOverlay.qml` (compact stats, latency counters — keep if missing data = hidden slots, not empty boxes).

### 3.4 Slot Loader + Workspaces + Status Capsule

- `BarWidgetLoader` Left `[brand_star, workspaces, active_window]`, Center `[clock, media, cava]`, Right `[tray, quickControls, vitals, power]` — mirroring `Bar.qml:63-81` but via `BarModule` enum in `crates/beskar-core/src/config.rs`.
- `WorkspacesWidget`: up to 10 slots, active = `24×8` capsule `#a77ef5`, occupied = `8×8` `0.65` opacity, empty = `8×8` `0.22`, hover `1.2x` scale, wheel scroll → `Action::FocusWorkspaceUp/Down` via `spawn_blocking` (`beskar-shell/src/bar/actions.rs:97-107` already correct).
- `Vitals` right section: nested `statusCapsule` (`bg_secondary`, `rounded_full`, `28-32px` high: volume + battery + notifications bell + tray) + standalone `32×32` circular power button — match `BarRightSection.qml`.

### 3.5 LayerShell Geometry + Fractional Scale

- `crates/beskar-shell/src/bar/mod.rs:37-87` → replace naive `floor/round` with `logical_display_size` fallback (`gpui-shell/crates/app/src/state.rs`). Keep `exclusive_zone = snapped_height + snapped_margin`, `Anchor::LEFT|RIGHT|TOP` (Top) etc.
- `bar/view.rs:62-89` SystemHub subscription stays; no per-view `Command::new`.

## 4. Acceptance

- [ ] Convex mode: seamless Bézier flares to top edge, zero seams/box artifacts at 1.0/1.25/1.5/2.0 scale; shadow matches `ThemedShadow`.
- [ ] Island mode: 3 pills with `#030107` obsidian, center pill morphs width spring-animated on media/notification, no detached windows.
- [ ] Workspaces: click switches, wheel scrolls, active capsule `24×8` lavender, opacity dots correct, window open/close updates dot opacity instantly via `WindowsChanged`.
- [ ] Status capsule: nested capsule + standalone power button; volume/battery/tray present only when data available.
- [ ] `cargo check && cargo test` green; no main-thread blocking introduced.

## 5. Non-goals

- ControlCenter pages, notifications toasts beyond inline bar toast, clipboard/wallpaper — Plan 02/03.
