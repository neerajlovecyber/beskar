# Plan 01 — Dynamic Bar Host & Bar Styles (Convex / Island / Gaming)

> **Depends on:** Plan 00 (OverlayHost, Lifecycle, **Animator spring contract**, **LayerShell dynamic sizing**, BarHost unified interface, Theme signal, blocking audit).
> Do not start until Plan 00 gate passes.
> **Rev 2 — Capsule-Native:** QML Bézier/spring tasks replaced by direct Rust port from `references/capsule`.

## 0. Goal

Make the bar the premium Minflair bar: **Concave continuous Bézier notch** vs **Island 3-pill morphing** vs Gaming telemetry, with real workspace pill and no thin/ugly regressions — by copying proven Rust GPUI geometry and spring physics, not re-deriving QML.

Beskar retains its **3-region topology (Left Workspaces + Center Morphing Island + Right System Tray/Vitals)** per Mandatory Decision. Capsule is a single centered `Capsule` window with `Orbit` satellites; Beskar adapts Capsule's `concave_background` + `Animator` primitives into the Left/Center/Right bar regions.

## 1. References Inspected (read before coding)

| Area | Upstream source | Files (with line ranges) |
|------|----------------|--------------------------|
| **Concave notch geometry** | **`references/capsule`** | **`crates/app/src/capsule/widgets/style.rs:27-130`** (`concave_radii(size,radius) -> (radius,shoulder)`, `concave_background(size,radius,bottom,color) -> canvas + PathBuilder cubic_bezier`, `concave_input_regions(bounds,radius,bottom) -> Vec<Bounds>`), tests `361-406` |
| **Island morphing spring** | **`references/capsule`** | **`crates/app/src/capsule/animator.rs:1-44`** (`spring_eval`, `apple_island_morph`), **`crates/app/src/capsule/orbit/animator.rs:1-61`** (orb fade `Animator{progress,start,target,started,duration}`, `transition(active,duration,now)`, `powi(3)` ease), **`crates/app/src/capsule/orbit/state.rs:10-92`** (`OrbExpanded{open, animator: Animator, height}`, `set_open`, `extra_width`, `content_opacity`, `bounds(orb,viewport,left,bottom)`) |
| **Orbit / capsule layout** | **`references/capsule`** | **`crates/app/src/capsule/orbit/mod.rs:16-20`** (`ORB_SIZE 26`, `USAGE_PANEL_WIDTH 220`, etc.), **`crates/app/src/capsule/orbit/state.rs:210-289`** (`layout(viewport,capsule,gap,location) -> OrbitVisual{ bounds, opacity, interactive }`, `satellite_gap`), **`crates/app/src/capsule/mod.rs:29-188`** (`Capsule::render` — `OutgoingContent{view,size,scale,opacity}`, `animator.content_scale/content_progress`, `concave` branch `rounded_tl/tr` vs `rounded_bl/br`, outgoing cross-fade `opacity * (1 - progress)`) |
| **Window state / sizing** | **`references/capsule`** | **`crates/app/src/capsule/window_state.rs`** (`visible_bounds`, `WindowState{style,radius,margin}`), **`crates/app/src/panel.rs:25-80`** (`CapsulePanel::window_options` `maximum_window_size`, `exclusive_zone`) |
| **Minflair style constants** | `references/minflair` (archived) | `Modules/Bar/Styles/Convex/ConvexShape.qml` (`flareWidth=18, flareHeight=16, bottomRadius=16, topBezel=2, baseHeight=44` — kept as fallback constants, **not** source of truth; Capsule's `radius/shoulder` derived from `size` replaces fixed flare math) |
| **Shell bar pattern** | `references/gpui-shell` | `crates/app/src/bar/view.rs`, `crates/ui/src/patterns/bar.rs` (LayerShell, `exclusive_zone`, retained for cross-check) |
| **Fractional scale** | `references/inir`, `references/gpui-shell` | `crates/app/src/state.rs:logical_display_size` |

**Do not read `references/minflair/.../ConvexShape.qml:27-69` to re-derive Bézier.** Read `capsule/widgets/style.rs:41-88` instead.

## 2. Architecture

```
crates/beskar-ui/src/
  spring.rs           <- Animator + spring_eval + apple_island_morph (from 00, consumed here)
  convex.rs           <- DEPRECATED as Bézier source — keep as re-export shim or delete getPath();
                        real concave math lives in widgets/style.rs pattern
  bar/
    mod.rs            <- BeskarBar (IBarStyle: widths/isExpanded/block), Slot loader dispatch,
                         drives Animator::transition_to for center pill width
    convex.rs         <- ConcaveBarWidget — calls concave_background(size,radius,bottom,color)
                        via gpui::canvas + PathBuilder (copy style.rs:41-88)
    island.rs         <- IslandBarWidget (3 pills + Animator morph + outgoing cross-fade)
    gaming.rs         <- GamingBarWidget (telemetry strip — keep, no Capsule analog)
    loader.rs         <- BarWidgetLoader Left/Center/Right dispatch
  pill.rs             <- pill capsule primitive (reuse for workspaces + status capsule)
  widgets/
    workspaces.rs     <- 10-slot workspaces (24x8 active capsule, 8x8 dots)
    vitals.rs         <- statusCapsule + standalone power button
    style.rs          <- NEW: port of capsule/widgets/style.rs concave + tint helpers
                         (concave_radii, concave_background, concave_input_regions,
                          background/surface/hover/selected/border/card/raised/accent_card)

crates/beskar-shell/src/
  bar/
    mod.rs            <- bar_window_options via CapsulePanel::window_options pattern (from 00)
    state.rs          <- BarState { workspaces, vitals, media, notification_toast, orbit? }
    view.rs           <- owns timers + HardwareBus + Vitals + compositor stream + config signal
                         + Animator frame loop (compositor.get_frame_duration().max(16ms))
                         feeds BeskarBar::from_state + sync_window
  window_state.rs     <- visible_bounds, BarWindowState (from 00, consumed here)
```

`BeskarBar` is **not** `Capsule`. `Capsule` is a single centered window that owns `Orbit` + `Satellite`. `BeskarBar` is a full-width `Layer::Top` bar (`Anchor::TOP|LEFT|RIGHT`) with 3 regions; only the **Center island** uses `Animator` + concave notch. Left/Right are static pills. `concave_background` is drawn as an **inner** canvas overlay on the bar's center notch, not as the whole window background (adapt `capsule/mod.rs:91-97` concave branch).

## 3. Tasks (copy, don't reinvent)

### 3.1 Concave Bézier Engine (deep module — copy Capsule, delete QML math)

- **Source:** `references/capsule/crates/app/src/capsule/widgets/style.rs:27-130` — **copy verbatim** into `crates/beskar-ui/src/widgets/style.rs` (or `crates/beskar-ui/src/style.rs` + re-export):
  ```rust
  // Pure fns — do not retune radii:
  pub fn concave_radii(size: Size<Pixels>, radius: f32) -> (f32, f32) { /* width/height max(0), radius max(0) min(width/2,height/2), shoulder 12 min(height/4,width/4) */ }
  pub fn concave_background(size: Size<Pixels>, radius: f32, bottom: bool, color: Hsla) -> impl IntoElement { /* canvas, shoulder offset, k=0.5522848, PathBuilder::fill, 4 cubic_bezier segments: top edge + right shoulder + bottom-right radius + bottom-left radius + left shoulder, close, paint_path */ }
  pub fn concave_input_regions(bounds: Bounds<Pixels>, radius: f32, bottom: bool) -> Vec<Bounds<Pixels>> { /* band_height 1px or height-radius-y, sample inset via sqrt(shoulder²-(sample-shoulder)²) or sqrt(radius²-(sample-height+radius)²), push Bounds */ }
  // Helpers: opaque, tint, background/surface/hover/selected/border/card/raised/accent_card/breadcrumb/panel_header — copy 132-354 if theming needs them, else map to beskar-theme tokens
  ```
- **Constants to delete:** `flareWidth=18, flareHeight=16, bottomRadius=16, topBezel=2, baseHeight=44` from old `convex.rs:83-195` `getPath()` — Capsule's `radius = capsular_round.min(22)`, `shoulder = 12 min(height/4,width/4)` replaces fixed flare. Keep `borderWidth=1 borderColor rgba(255,255,255,0.08)` as `style::border` alpha.

- **Paint:** `ConcaveBarWidget` (or `crates/beskar-ui/src/bar/convex.rs`) → `div().relative().w(size.width).h(size.height).when(concave, |s| s.child(concave_background(size, radius, bottom, hsla)))` exactly as `capsule/mod.rs:138-150`:
  ```rust
  let (radius, _) = concave_radii(size, window_state.radius);
  div().relative().w(size.width).h(size.height).flex_shrink_0()
      .when(concave, |s| s.child(concave_background(size, radius, bottom, background(&theme))))
      .child(bar_content)
  ```
  Add `card` ambient if needed (`style::card(theme, radius).bg(surface(theme))` — Capsule uses `surface` for satellite cards, `background` for capsule).

- **Input regions:** if Beskar bar needs click-through on notch shoulders, call `concave_input_regions(bounds, radius, bottom)` to produce `Vec<Bounds>` for hit-testing (Capsule uses it for `LayerShell` input region shaping). Otherwise skip — standard bar does not need it.

- **Tests:** copy `style.rs:361-406` (`concave_curves_fit_compact_and_expanded_capsules`, `concave_input_regions_follow_the_outline_on_both_edges`) — asserts `radius+shoulder <= height`, `radius*2 <= width`, `shoulder<=12`, top/bottom symmetry, `covered_height == height`.

- **Delete:** old `crates/beskar-ui/src/convex.rs:83-195` `getPath(w,h,lW,cX,cW,rW,tb,fw,fh,br,cH,baseH,cbr)` 7-segment path — superseded.

### 3.2 Island Morphing + Outgoing Cross-Fade (copy Animator + OrbExpanded pattern)

- **Animator drive:** `crates/beskar-shell/src/bar/view.rs` or `crates/beskar-ui/src/bar/mod.rs` owns `Animator` (from `spring.rs` Plan 00). On state change (media play/pause, notification toast in/out, `barIslandExpanded` toggle), call:
  ```rust
  let target = if expanded { size(px(360), px(height)) } else { size(px(180), px(height)) }; // or 320 for media
  animator.set_duration(Duration::from_millis(config.ui.animation_duration_ms));
  animator.transition_to(target, Instant::now());
  if content_changed { animator.reveal_content(Instant::now()); }
  ```
  Size constants: compact `180px`, media `320px`, notification toast `360px` — same as old plan, but **driven by `Animator` not `SpringValue`**.

- **Frame loop:** `window.on_next_frame` or `cx.spawn(async move |this,cx| { background_executor.timer(compositor.get_frame_duration().max(16ms)).await; let running = this.update(cx, |bar,cx| { let r = bar.animator.advance(Instant::now()); bar.sync_window(cx); cx.notify(); r }); … })` — copy `capsule/satellite/mod.rs:241-265` timer loop. Beskar's old `bar/view.rs:82-164` 16ms/300ms adaptive loop is replaced by compositor-aware loop.

- **Render — morph + scale + outgoing:**
  Adapt `capsule/mod.rs:52-137` inside `IslandBarWidget::render`:
  ```rust
  let size = animator.size();
  let progress = animator.content_progress(); // 0..1 cubic
  let scale = animator.content_scale();       // 0.98 + progress*0.02
  // outgoing cross-fade if content switched during morph:
  // Option<OutgoingContent{ view:size*scale, opacity: 1-progress }>
  div().w(size.width).h(size.height).flex_shrink_0()
      .when_some(outgoing.as_ref(), |s, o| s.child(
          div().absolute().top((size.height - o.size.height*scale)*0.5)
              .left((size.width - o.size.width*scale)*0.5)
              .w(o.size.width*scale).h(o.size.height*scale)
              .opacity(o.opacity * (1.0 - progress)).child(o.view.clone())
      ))
      .child(
          div().relative()
              .top(size.height*(1.0-scale)*0.5).left(size.width*(1.0-scale)*0.5)
              .w(size.width*scale).h(size.height*scale)
              .opacity(if outgoing.is_some() { progress } else { 1.0 })
              .child(center_content)
      )
  ```
  `bottom` bool flips `rounded_tl/tr` vs `rounded_bl/br` when `concave` (Capsule `capsule/mod.rs:91-97`).

- **OrbExpanded pattern (for satellite-like expansions):** if Beskar's Right `Usage`/`Power` pills need expand-in-place, copy `orbit/state.rs:10-92` `OrbExpanded::new(height)`, `set_open(open,duration,now)` (`animator.transition_to(220×144 or 26×26)`), `extra_width()`, `content_opacity()`, `bounds(orb,viewport,left,bottom)` — but `BeskarBar` Center pill can use plain `Animator` without `OrbExpanded` wrapper.

- **Not spawning detached windows:** in-place expand of pill container, not `PanelHost` overlay. Only tray menu uses overlay (Plan 02 Satellite).

### 3.3 Gaming Bar

- `GamingBarWidget`: high-contrast cyber strip mirroring `references/minflair/Modules/Bar/Styles/Gaming/GamingBar.qml` + `GamingOverlay.qml` (compact stats, latency counters — keep if missing data = hidden slots, not empty boxes). No Capsule analog; keep existing QML-derived spec but **drive width via `Animator`** if it needs morph.

### 3.4 Slot Loader + Workspaces + Status Capsule

- `BarWidgetLoader` Left `[brand_star, workspaces, active_window]`, Center `[clock, media, cava]`, Right `[tray, quickControls, vitals, power]` — mirroring `Bar.qml:63-81` but via `BarModule` enum in `crates/beskar-core/src/config.rs`.
- `WorkspacesWidget`: up to 10 slots, active = `24×8` capsule `#a77ef5`, occupied = `8×8` `0.65` opacity, empty = `8×8` `0.22`, hover `1.2x` scale, wheel scroll → `Action::FocusWorkspaceUp/Down` via `spawn_blocking` (`beskar-shell/src/bar/actions.rs:97-107` already correct). No Capsule analog (Capsule has no workspaces bar); keep Minflair spec but ensure `concave_input_regions` does not eat workspace clicks.
- `Vitals` right section: nested `statusCapsule` (`bg_secondary`, `rounded_full`, `28-32px` high: volume + battery + notifications bell + tray) + standalone `32×32` circular power button — match `BarRightSection.qml`. Capsule's `orbit` `ORB_SIZE 26` is adjacent reference for sizing.

### 3.5 LayerShell Geometry + Fractional Scale (consume Plan 00 contract)

- `crates/beskar-shell/src/bar/mod.rs:37-87` → replace naive `floor/round` with `maximum_window_size` + `visible_bounds` + `logical_display_size` fallback (`gpui-shell/crates/app/src/state.rs`). Keep `exclusive_zone = snapped_height + snapped_margin`, `Anchor::LEFT|RIGHT|TOP` (Top) etc. — but derive `snapped_height` from `Animator::size().height`, not fixed `44px`.
- `bar/view.rs:62-89` SystemHub subscription stays; no per-view `Command::new`.
- **Verification:** at 1.0/1.25/1.5/2.0 scale, concave flares meet notch shoulders with `k=0.5522848` control points (not `0.45/0.55` QML factors) — visual diff vs old Convex.

## 4. Acceptance

- [x] Concave mode: `concave_background` draws seamless cubic Bézier flares to notch shoulders at 1.0/1.25/1.5/2.0 scale; `concave_radii` tests pass; no seams/box artifacts; `border rgba(255,255,255,0.08)` + `surface`/`background` tokens correct.
- [x] `concave_input_regions` returns covering `Vec<Bounds>` with `covered_height == height`, symmetric top/bottom, `len < 40` (if used).
- [x] Island mode: 3 pills with obsidian `background` (`#030107` or `hsla(240,0.16,0.08,1.0)` via `style::background`), center pill morphs `180→320→360` via `Animator` (`spring_eval` zeta 0.73/0.77, powf 0.92/1.04), `content_scale 0.98→1.0` + outgoing cross-fade on content switch, compositor-aware `16ms.max` frame loop, no detached windows.
- [x] `Animator` interruption preserves `displayed` size (Plan 00 test), expansion vs contraction asymmetry correct.
- [x] Workspaces: click switches, wheel scrolls, active capsule `24×8` lavender, opacity dots correct, window open/close updates via `WindowsChanged` without lag; hit-test not broken by concave overlay.
- [x] Status capsule: nested capsule + standalone power button; volume/battery/tray present only when data available.
- [x] `bar_window_options` uses `maximum_window_size` + `exclusive_zone` + `visible_bounds`; fractional-scale snapping correct.
- [x] `cargo check && cargo test` green; no main-thread blocking introduced; `references/capsule/.../style.rs` diff matches `crates/beskar-ui/src/widgets/style.rs`.

## 5. Non-goals

- ControlCenter Satellite pages (Plan 02), notifications toasts beyond inline bar toast (Plan 03). This plan only installs `concave_background` + `Animator` + bar topology.
