# Plan 00 — Architecture Overhauls (Hard Gate)

> **Status:** `REQUIRED FIRST — blocks Plans 01-05.`
> No feature plan may start until this one passes `cargo check`, `cargo test`, and the audits below.
> **Rev 2 — Capsule-Native:** Animator spring physics and LayerShell dynamic sizing are now hard gates. Copy Rust from Capsule, not QML.

## 0. Goal

Eliminate the hanging / ugly / thin regressions once and for all and install the contracts that Capsule proves work in production Rust+GPUI. Later plans only consume these contracts; none re-derive physics or window sizing.

## 1. References Inspected (read before coding)

| Contract | Upstream source | Concrete files to extract (line ranges) |
|----------|----------------|------------------------------------------|
| OverlayHost deep module | `references/gpui-shell` | `crates/app/src/panel.rs` (single-panel mutex, fullscreen scrim, Escape, backdrop, focus trap), `crates/app/src/bar/view.rs:62-121` (`observe_global` hotplug reload) |
| Service Lifecycle / RunToken | `references/gpui-shell` | `crates/services/src/lifecycle.rs:46-210` (`Lifecycle{status,mode,generation}`, `RunToken{alive,set,error}`) — unchanged |
| **Animator spring physics** | **`references/capsule`** | **`crates/app/src/capsule/animator.rs:1-139`** (`spring_eval(zeta)`, `apple_island_morph(expanding)`, `struct Animator{current,start,target,started_at,duration,content_started_at,content_progress}`, `transition_to`, `reveal_content`, `content_scale`, `advance/advance_size`) + tests `144-244` |
| **LayerShell dynamic sizing** | **`references/capsule`** | **`crates/app/src/panel.rs:25-80`** (`CapsulePanel::window_options` — `maximum_window_size`, `display.bounds().size`, `exclusive_zone` from `AppState.config.ui`, `Anchor::TOP|LEFT|RIGHT` vs `BOTTOM`, `Layer::Top`, `KeyboardInteractivity::OnDemand`, `inactive_frame_interval=None`, bounds `Bounds{origin px(0), size}`), **`crates/app/src/capsule/window_state.rs`** (`visible_bounds(viewport, size, margin, location)`, `WindowState{style,radius,margin}`), **`crates/app/src/capsule/satellite/layout.rs:17-77`** (`SatelliteLayout::new` viewport clamping, `Side::Below` fallback) |
| **Panel host patterns** | `references/capsule` | `crates/app/src/panel.rs:222-331` (`SettingsPanel::surface_options` fullscreen scrim `TOP|BOTTOM|LEFT|RIGHT exclusive_zone -1`, `LockScreenPanel::window_options` `SessionLockOptions`) |
| Async hardware adapters | `references/wayle` | `crates/wayle-widgets/src/{audio,backlight,network,bluetooth,battery}` (`spawn_blocking` + `zbus`) |
| D-Bus streams | `references/icebar` | `src/modules/tray.rs`, `src/subscription.rs` |
| Minflair slot contract | `references/minflair` | `config/quickshell/Core/Services/AppState.qml:63-82` (`getSlot` Focus vs Left/Center/Right) — retained for Beskar `Slot` semantics |
| Theme/shader pipeline | `references/suzuha`, `references/pleamar` | `src/theme.rs`, `shaders/`, `src/gpu.rs` |

Skills (normative): `.agents/skills/gpui-kit/SKILL.md`, `.agents/skills/gpui-kit-design-guides/SKILL.md`. Do not build hand-rolled `div()` sliders/lists/modals.

## 2. Deep Exploration Findings (what is broken today)

1. **Single-slot OverlayHost.** `crates/beskar-shell/src/panel_host.rs:54` is `ACTIVE_PANEL: Mutex<Option<(id, handle)>>`. Minflair `AppState.qml:28` has 4 mutually-exclusive slots: `focus` (launcher/clipboard/wallpaper/powerMenu/screenshot), `left` (`dashboard`), `center` (`music`), `right` (`controlCenter|notificationsCenter|clock|systemTray_*`). Beskar cannot express this; opening any overlay closes any other overlay even across slots. Capsule avoids this by **not using a global OverlayHost** — `Capsule` itself is the single bar window, `Satellite` manages left/right panels inside its bounds, `Orbit` manages expanded orbs. Beskar keeps `OverlayHost` but must adopt Slot-per-slot mutex.

2. **Hotplug reconciliation clobbers state.** `crates/beskar-shell/src/main.rs:130` calls `bar::reload_bars(Vec::new(), 1, None, ...)` every 2s on display change, overwriting live compositor workspaces/windows. `crates/beskar-compositor/src/niri.rs:83-202` lacks `WorkspaceFocused` dispatch on `WorkspaceActivated` and has no `RunToken::alive()` guard.

3. **Main-thread blocking risk.** `crates/beskar-shell/src/modules/wallpaper_selector/mod.rs:51` (`swww/feh`), `screen_capture/view.rs:57-81` (`sh -c`, `pidof`), `power_menu/mod.rs:113` inline; only some paths use `spawn_blocking`. **Capsule itself violates this:** `crates/app/src/panel.rs:165-166` `Command::new("sh").args(["-c", "grim -g … | magick/convert …"])` on the UI thread inside `LockScreenPanel::open_all`'s `thread::scope`, and `crates/app/src/lockscreen/view.rs:116` `std::thread::spawn(|| PamService::authenticate_current_user(&pass))` + blocking `rx.try_recv` poll loop. Both must be fixed on extraction.

4. **BarHost not unified.** `crates/beskar-shell/src/bar/view.rs:313-349` renders a flat row (`div` + 1px border) and never paints concave notch. `references/minflair/Modules/Bar/Bar.qml:16-32` exposes `leftWidth/centerX/centerWidth/isExpanded/blockX` for both Convex and Island via `IBarStyle`. Capsule replaces this with `Animator::size()` + `window_state::visible_bounds` — the bar window **is** the island; there is no separate `BarHost`.

5. **Theme/config signal disconnected.** `crates/beskar-core/src/config.rs:181-198` has `subscribe_config()` but `bar/view.rs:266` and `main.rs:55-64` read `ShellConfig::load()` ad-hoc; `ThemeEngine::set_preset` not wired to the signal.

6. **No spring contract.** `crates/beskar-ui/src/spring.rs` has a placeholder `SpringValue` (lerp), not Capsule's under-damped spring (`zeta 0.73/0.77`, `omega0 = 2π/sqrt(1-zeta²)`, `envelope exp(-beta t)`, `osc cos+sin`, powf `0.92/1.04` asymmetry for expand vs collapse). Without copying `capsule/animator.rs:15-44`, Plan 01 morph will reintroduce jank.

7. **LayerShell geometry is naive.** `crates/beskar-shell/src/bar/mod.rs:37-87` uses `floor/round` on `display.bounds()` without `maximum_window_size` clamping or `exclusive_zone` derivation from `config.ui`. Fractional scale (`wl_output.scale` integer vs logical size) will clip at 1.25/1.5/2.0. Capsule's `CapsulePanel::window_options` + `window_state::visible_bounds` + `SatelliteLayout::new` already handle this.

## 3. Contracts to Establish (outputs of this plan)

### 3.1 Deep OverlayHost module (deep module: weak seam)

- **Location:** `crates/beskar-shell/src/panel_host.rs` (rewrite, keep `PanelHost` name + `OverlayHost` alias).
- **Interface (public, narrow):**
  ```rust
  pub enum Slot { Focus, Left, Center, Right }
  impl PanelModule {
      const ID: &str;
      fn slot() -> Slot;
      fn size() -> Size<Pixels>;
      // anchor/margin/keyboard_interactivity/layer/build as today
  }
  pub struct PanelHost;
  impl PanelHost {
      pub fn open<M: PanelModule>(cx: &mut App) -> bool;
      pub fn close(cx: &mut App) -> Option<&'static str>;
      pub fn toggle<M: PanelModule>(cx: &mut App) -> bool;
      pub fn toggle_by_id(id: &str, cx: &mut App) -> bool; // for beskar-msg IPC
      pub fn is_open(id: &str) -> bool;
  }
  ```
- **Behavior:** fullscreen transparent LayerShell scrim per overlay (`Anchor::TOP|BOTTOM|LEFT|RIGHT`, `exclusive_zone=None`, `WindowBackgroundAppearance::Transparent`), bounded inner card with `Scrollable`, single `on_mouse_down_out` → close, `Escape` focus trap, per-`Slot` mutual exclusion mirroring `AppState.qml:getSlot` (Focus closes Focus only; Left/Center/Right close same slot only). One `ACTIVE_BY_SLOT: [Option<(id, handle)>; 4]`.
- **Source:** cherry-pick `references/gpui-shell/crates/app/src/panel.rs`; for fullscreen card geometry, follow `references/capsule/crates/app/src/panel.rs:244-260` `SettingsPanel::surface_options` (`Anchor::TOP|BOTTOM|LEFT|RIGHT`, `exclusive_zone Some(px(-1.0))`, `bounds Size::default` — compositor assigns).

### 3.2 Service Lifecycle / RunToken (deep module)

- **Location:** new `crates/beskar-services/src/lifecycle.rs` + trait use in `crates/beskar-compositor/src/niri.rs` and hardware services.
- **Extract:** `references/gpui-shell/crates/services/src/lifecycle.rs:46-210` verbatim (rename `ServiceMode` if colliding) — `Lifecycle{status, mode, generation: AtomicU64}`, `RunToken{alive(), set(), error()}`.
- **Apply to:** `NiriBackend::start_listener` (loop checks `token.alive()`), `AudioService`, `NetworkManager`, `BlueZ`, `UPower/Battery` (replace raw `thread::spawn` / `std::process::Command` loops).
- **Rule:** any looping D-Bus/socket reader holds a `RunToken` and breaks when `!alive()`; `stop()` bumps generation; callers via `ManagedService::ensure_started()` for lazy services.

### 3.3 Zero main-thread blocking audit (now includes Capsule violations)

- **Locations:** `crates/beskar-shell/src/modules/**/mod.rs`, `crates/beskar-services/src/*.rs`, **and every cherry-picked Capsule file**.
- **Rule:** every `std::process::Command::new("nmcli"|"bluetoothctl"|"wpctl"|"brightnessctl"|"playerctl"|"swww"|"feh"|"pidof"|"wf-recorder"|"grim"|"magick"|"convert")` or `std::thread::spawn(|| PamService::authenticate…)` must be inside `tokio::task::spawn_blocking` or async `zbus`/`services::spawn_tokio` — never in `render`, `View::new`, or `cx.update` synchronously.
- **Capsule fixes required before merge:**
  - `panel.rs:145-181` blur snapshot `sh -c "grim -g '{geom}' -t ppm - | magick …"` → `spawn_blocking(move || Command::new("sh")…)` or `tokio::process::Command`, write to `/tmp/capsule_lock_blur_*` then `exists()` check; never block `open_all`.
  - `lockscreen/view.rs:116-128` PAM `std::thread::spawn` → `spawn_blocking` + `cx.spawn(async move |this,cx| { this.update… })` pattern already in Capsule's `polkit.rs:144-152`, reuse.
  - `dashboard/actions.rs` (if any `Command` for wifi/bt/audio) → `zbus` via `AppState.network/system` or `spawn_blocking`.
- **Output:** `cargo grep` report showing 0 violations after this plan. Add a CI `grep` guard if desired.

### 3.4 Animator spring contract (NEW — Capsule-native)

- **Location:** `crates/beskar-ui/src/spring.rs` (rewrite; keep re-export alias `SpringValue` if used elsewhere).
- **Cherry-pick verbatim from `references/capsule/crates/app/src/capsule/animator.rs:1-139`:**
  ```rust
  // Pure fns — copy exactly, do not retune:
  fn spring_eval(t: f32, zeta: f32) -> f32 { /* wd=2π, omega0=wd/sqrt(1-zeta²), beta=zeta*omega0, scale=1/(1-exp(-beta)), envelope exp(-beta t), osc cos+beta/wd sin */ }
  pub fn apple_island_morph(t: f32, expanding: bool) -> (f32,f32) { /* (t.powf(0.92), t.powf(1.04)) when expanding else swapped, spring_eval(uw,0.73), spring_eval(uh,0.77) */ }

  pub struct Animator {
      current: Size<Pixels>, start: Size<Pixels>, target: Size<Pixels>,
      started_at: Option<Instant>, duration: Duration,
      content_started_at: Option<Instant>, content_progress: f32,
  }
  impl Animator {
      pub fn new(size: Size<Pixels>, duration: Duration) -> Self;
      pub fn set_duration(&mut self, duration: Duration);
      pub fn animating(&self) -> bool;
      pub fn size(&self) -> Size<Pixels>;
      pub fn transition_to(&mut self, target: Size<Pixels>, now: Instant);
      pub fn content_progress(&self) -> f32;
      pub fn content_scale(&self) -> f32; // 0.98 + progress*0.02
      pub fn reveal_content(&mut self, now: Instant); // content_progress=0, duration.min(160ms), easeOutCubic
      pub fn advance(&mut self, now: Instant) -> bool; // size + content, cubic (1-(1-t)^3) for content
      fn advance_size(&mut self, now: Instant) -> bool; // apple_island_morph dispatch, max(px(1.0))
  }
  ```
- **Tests:** copy `animator.rs:141-244` (`interrupted_transition_preserves_displayed_size`, `expansion_and_contraction_match_the_original_spring`, `content_reveals_even_when_dimensions_do_not_change`, `replacing_content_during_a_resize_preserves_the_current_dimensions`, `rapid_content_changes_restart_the_reveal_and_settle`, `zero_duration_finishes_immediately`) into `crates/beskar-ui/src/spring.rs` `#[cfg(test)]`.
- **Adaptation seam:** `Theme` not needed here; `Duration` from `AppState.config.ui.animation_duration_ms` (capsule) → `beskar-core::config::ShellConfig` equivalent. `px(1.0)` clamp stays.
- **Frame loop contract (for Plans 01/02/04):** callers drive `animator.advance(Instant::now())` inside `window.on_next_frame` or `cx.spawn(async move |this,cx| { background_executor.timer(compositor.get_frame_duration().max(16ms)).await … })` exactly as `capsule/satellite/mod.rs:241-265` and `capsule/mod.rs` `animation_frame_pending`. Beskar's `bar/view.rs:82-164` adaptive loop (16ms animating / 300ms idle) is replaced by this compositor-aware loop.
- **Consumers:** `crates/beskar-ui/src/bar/mod.rs` (bar window size), `crates/beskar-shell/src/modules/dashboard` + `music_player` (center island), `crates/beskar-shell/src/modules/control_center` (Satellite), `crates/beskar-shell/src/panel_host.rs` (orb/satellite expansion is driven by `Orbit::State::OrbExpanded::animator: Animator` — see Plan 01).

### 3.5 LayerShell dynamic sizing contract (NEW — Capsule-native)

- **Location:** `crates/beskar-shell/src/panel_host.rs` + `crates/beskar-shell/src/bar/mod.rs:37-87` + new `crates/beskar-shell/src/window_state.rs` (or `crates/beskar-ui/src/window_state.rs`) — prefer `crates/beskar-shell/src/window_state.rs` to mirror `capsule/window_state.rs`.
- **Cherry-pick:**
  - `references/capsule/crates/app/src/panel.rs:25-80` `CapsulePanel::window_options(&module_manager, cx)` → `BarHost::window_options(cx)`:
    - `let size = Capsule::maximum_window_size(&module_manager, cx.displays().first().map(|d| d.bounds().size), cx)` — **copy `maximum_window_size` from `capsule/mod.rs` + `window_state.rs`** (iterates module sizes, picks max width/height, clamps to `display.size`).
    - `exclusive_zone = AppState.config.get().ui.exclusive_zone()` else `25.0+8.0`; `WindowOptions{ titlebar:None, window_bounds: display_bounds.map(WindowBounds::Windowed), app_id:"beskar-panel", linux_window_background:Transparent, kind: LayerShell{ namespace:"beskar-panel", layer:Top, anchor: TOP|LEFT|RIGHT (or BOTTOM per CapsuleLocation), margin Some((0,0,0,0)), exclusive_zone Some(px(exclusive_zone)), keyboard_interactivity:OnDemand }, inactive_frame_interval:None, bounds: Bounds{origin px(0), size} }`.
    - After construction, override `anchor` via `config.ui.capsule_location` (`Top→Anchor::TOP`, `Bottom→Anchor::BOTTOM`) — keep Beskar `bar_position`.
  - `references/capsule/crates/app/src/capsule/window_state.rs` `visible_bounds(viewport, size, margin, location)` and `WindowState{ style: CapsuleStyle::Concave|Default, radius: f32, margin: f32 }` → `beskar-shell::window_state::visible_bounds` + `BarWindowState`. Used by bar render (`capsule/mod.rs:155-161` presentation call) and satellite/orbit layout.
  - `references/capsule/crates/app/src/panel.rs:244-260` `SettingsPanel::surface_options` for fullscreen scrim overlays: `WindowOptions{ display_id, titlebar:None, window_bounds: Windowed(Bounds::default()), app_id:"beskar-settings", kind: LayerShell{ namespace:"beskar-settings", layer:Overlay, anchor: TOP|BOTTOM|LEFT|RIGHT, exclusive_zone: Some(px(-1.0)), keyboard_interactivity:OnDemand } }` — size `default()` so compositor assigns.
  - `references/capsule/crates/app/src/capsule/satellite/layout.rs:26-77` `SatelliteLayout::new(viewport, capsule, desired, gap, preferred, progress)` — **copy verbatim** for Plan 02 satellite OSDs. Clamps width to `viewport.width`, picks `Left` if `capsule.origin.x - gap >= width` else `Right` else `Below`, computes `target_y`, `height min(viewport.height - target_y)`, `progress` offset `16*(1-progress)` with direction, `Below` center-clamped.
- **Fractional-scale fix:** replace naive `floor/round` with `gpui-shell/crates/app/src/state.rs:logical_display_size` fallback (`cx.primary_display()` else `wl_output.scale` integer vs GPUI logical bounds). Capsule already does `cx.displays().first().map(|d| d.bounds().size)` — GPUI's `bounds()` is already logical; do not double-round.
- **Hotplug fix:** `main.rs:107-141` → delete `reload_bars(Vec::new(),1,None,…)`; instead `cx.observe_global::<Config>` / config signal like `gpui-shell/bar/view.rs:124-129` and query `compositor` for fresh workspaces on actual hotplug (via `AppState` watch).

### 3.6 Unified BarHost interface + Theme & Config reactive signal (updated)

- **Location:** `crates/beskar-ui/src/bar/mod.rs` + `crates/beskar-shell/src/bar/mod.rs:37-87` + `crates/beskar-core/src/config.rs:181-198`.
- **Contract (BarHost):** `trait BarStyle { fn widths(&self) -> (leftW, centerX, centerW, rightW); fn is_expanded(&self) -> bool; }` analog of `Bar.qml:16-32`. Now **driven by `Animator::size()`** instead of ad-hoc `SpringValue`. `bar_window_options` must use §3.5 pattern, not bare `floor()/round()`.
- **Contract (Theme/Config):** `ShellConfig::save()` already calls `notify_config_changed`; wire `DesktopBarView` + `main.rs` to a single subscription that updates `is_convex`, `bar_height`, `bar_position`, and `ThemeEngine::set_preset` atomically. `capsule` reads `AppState.config.get().ui.{animation_duration_ms, capsule_round, satellite_round, gap, cards_round, clock_format}` — expose same via `beskar-core::config`. Persist fields: `barStyle`, `barIslandExpanded`, `barSlot{L1..R3}`, `themePreset` + `capsule_location`, `animation_duration_ms`, `exclusive_zone`.
- **Capsule theme mapping:** `ui::theme::Theme` (`background/surface/foreground/accent/background_alt/light_mix/on_accent/red/green/foreground_muted`) → `beskar-theme::ThemeEngine`. Helpers `style::background/surface/hover/selected/border/raised/accent_card` in `capsule/widgets/style.rs:132-173` map to `beskar-theme` tokens; keep `opaque()`/`tint()` semantics.

## 4. File Map

| Input (read) | Output (edit/create) | Notes |
|--------------|----------------------|-------|
| `references/capsule/crates/app/src/capsule/animator.rs:1-139` | **`crates/beskar-ui/src/spring.rs` rewrite** | Copy `spring_eval`, `apple_island_morph`, `Animator` verbatim; keep `SpringValue` alias if needed; add tests `141-244` |
| `references/capsule/crates/app/src/capsule/window_state.rs` | **`crates/beskar-shell/src/window_state.rs` new** | Copy `visible_bounds`, `WindowState` |
| `references/capsule/crates/app/src/panel.rs:25-80, 244-260` | **`crates/beskar-shell/src/panel_host.rs` rewrite** → slot-aware scrim host | Add `maximum_window_size`, `BarHost::window_options`; keep tests, add slot mutex tests |
| `references/capsule/crates/app/src/capsule/satellite/layout.rs:17-77` | **`crates/beskar-shell/src/satellite_layout.rs` new (or re-export in `panel_host`)** | Copy `SatelliteLayout::new`, `Side`, `centered_y` for Plan 02 reuse |
| `crates/beskar-shell/src/main.rs:107-141` | **edit** remove display-poll clobber | Add `observe_global` reload |
| `crates/beskar-compositor/src/niri.rs:83-202` | **edit** add lifecycle + WorkspaceFocused | `_ = tx.try_send(WorkspaceFocused)` on `WorkspaceActivated` |
| `crates/beskar-core/src/config.rs` | **edit** keep signal, extend defaults | Ensure `modules_left/center/right`, `capsule_location`, `animation_duration_ms`, `exclusive_zone`, `gap`, `capsule_round` |
| `crates/beskar-services/src/lifecycle.rs` | **new** copy of `gpui-shell/lifecycle.rs` | |
| `crates/beskar-services/src/hardware_bus.rs` + others | **edit** wrap in lifecycle + spawn_blocking | |
| `crates/beskar-ui/src/bar/mod.rs` | **edit** add `BarStyle` + Animator wiring | |
| `crates/beskar-shell/src/bar/mod.rs:37-87` | **edit** fractional-scale snapping via Capsule pattern | Use `logical_display_size` + `visible_bounds` |

## 5. Acceptance (gate criteria — all must pass before Plans 01-05)

- [x] `cargo check && cargo test` green across workspace.
- [x] `Animator` unit tests pass: `interrupted_transition_preserves_displayed_size`, `expansion_and_contraction_match_the_original_spring` (zeta 0.73/0.77, powf 0.92/1.04), `content_reveals_even_when_dimensions_do_not_change`, `replacing_content_during_a_resize_preserves_the_current_dimensions`, `rapid_content_changes_restart_the_reveal_and_settle`, `zero_duration_finishes_immediately`.
- [x] `panel_host` slot tests: opening `launcher` (Focus) does not close `dashboard` (Left); opening `controlCenter` (Right) closes `notificationsCenter` (Right) but not `music` (Center); `Escape` + backdrop click close only the scrim's slot.
- [x] `niri.rs` emits `WorkspaceFocused(id)` on `WorkspaceActivated` and on `WorkspacesChanged` dedup, and respects `RunToken::alive()` restart.
- [x] Display hotplug no longer calls `reload_bars(Vec::new(),1,None)` — verified by grepping `reload_bars` in `main.rs`.
- [x] Zero `std::process::Command::new` outside `spawn_blocking`/`spawn_tokio`/async in `crates/beskar-shell/src` and `crates/beskar-services/src` (`grep -R "Command::new"` review) — includes fixed Capsule blur + PAM paths.
- [x] `BarHost::window_options` uses `maximum_window_size` + `exclusive_zone` from config + `Anchor` per `capsule_location`; `visible_bounds` + `SatelliteLayout::new` clamping present and tested.
- [x] `logical_display_size` fallback present in `bar/mod.rs` for fractional scale (tested at 1.0/1.25/1.5/2.0).
- [x] Config signal: changing `bar_style`/`capsule_location`/`animation_duration_ms` in `config.json` hot-swaps without restart (manual test), `ThemeEngine::set_preset` follows signal; `set_duration` propagates to `Animator`.
- [x] `frame loop` uses `compositor.get_frame_duration().max(16ms)` + `on_next_frame` pattern (no bare `std::thread::sleep` in UI).

## 6. Non-goals (deferred to later plans)

- Actual concave Bézier painting / `concave_background` call (Plan 01), Satellite OSD panels (Plan 02), notifications/clipboard/wallpaper (Plan 03), dashboard/music/capture (Plan 04), lockscreen/settings GUI (Plan 05). This plan only installs the `Animator` + `LayerShell` + `Lifecycle` contracts they depend on.
