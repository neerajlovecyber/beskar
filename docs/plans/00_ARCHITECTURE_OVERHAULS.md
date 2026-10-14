# Plan 00 — Architecture Overhauls (Hard Gate)

> **Status:** `REQUIRED FIRST — blocks Plans 01-05.`
> No feature plan may start until this one passes `cargo check`, `cargo test`, and the audits below.

## 0. Goal

Eliminate the hanging / ugly / thin regressions once and for all so later Minflair ports do not reintroduce them. All cross-cutting decisions are made here; later plans only consume the contracts.

## 1. References Inspected (read before coding)

| Contract | Upstream source | Concrete files to extract |
|----------|----------------|---------------------------|
| OverlayHost deep module | `references/gpui-shell` | `crates/app/src/panel.rs` (single-panel mutex, fullscreen scrim, Escape, backdrop, focus trap), `crates/app/src/bar/view.rs:62-121` (hotplug `observe_global` reload) |
| Service Lifecycle / RunToken | `references/gpui-shell` | `crates/services/src/lifecycle.rs:46-145` (`Lifecycle`, `RunToken{generation}`, `ManagedService`) |
| Async hardware adapters | `references/wayle` | `crates/wayle-widgets/src/{audio,backlight,network,bluetooth,battery}` (all `spawn_blocking` + `zbus`) |
| D-Bus streams | `references/icebar` | `src/modules/tray.rs`, `src/subscription.rs` (StatusNotifierWatcher, menu streaming, `zbus` patterns) |
| Minflair slot contract | `references/minflair` | `config/quickshell/Core/Services/AppState.qml:63-82` (`getSlot`, focus vs bar slots), `config/quickshell/Core/Services/SettingsService.qml:207-263` (debounced JSON persist) |
| Theme/shader pipeline | `references/suzuha`, `references/pleamar` | `src/theme.rs`, `shaders/`, `src/gpu.rs` |

Skills (normative): `.agents/skills/gpui-kit/SKILL.md`, `.agents/skills/gpui-kit-design-guides/SKILL.md`. Do not build hand-rolled `div()` sliders/lists/modals.

## 2. Deep Exploration Findings (what is broken today)

1. **Single-slot OverlayHost.** `crates/beskar-shell/src/panel_host.rs:54` is `ACTIVE_PANEL: Mutex<Option<(id, handle)>>`. Minflair `AppState.qml:28` has 4 mutually-exclusive slots: `focus` (launcher/clipboard/wallpaper/powerMenu/screenshot close each other, never bar widgets), `left` (`dashboard`), `center` (`music`), `right` (`controlCenter|notificationsCenter|clock|systemTray_*`). Beskar cannot express this; opening any overlay closes any other overlay even across slots.
2. **Hotplug reconciliation clobbers state.** `crates/beskar-shell/src/main.rs:130` calls `bar::reload_bars(Vec::new(), 1, None, ...)` every 2s on display change, overwriting live compositor workspaces/windows. `crates/beskar-compositor/src/niri.rs:83-202` lacks `WorkspaceFocused` dispatch on `WorkspaceActivated` and has no `RunToken::alive()` guard.
3. **Main-thread blocking risk.** `crates/beskar-shell/src/modules/wallpaper_selector/mod.rs:51` (`swww/feh`), `screen_capture/view.rs:57-81` (`sh -c`, `pidof`), `power_menu/mod.rs:113` inline; only some paths use `spawn_blocking` (`crates/beskar-services/src/hardware_bus.rs:66-168`, `bar/actions.rs:76`).
4. **BarHost not unified.** `crates/beskar-shell/src/bar/view.rs:313-349` renders a flat row (`div` + 1px border) and never paints `crates/beskar-ui/src/convex.rs:83-195` `getPath()` Bézier notch. `references/minflair/config/quickshell/Modules/Bar/Bar.qml:16-32` exposes `leftWidth/centerX/centerWidth/isExpanded/blockX` for both Convex and Island via `IBarStyle`.
5. **Theme/config signal disconnected.** `crates/beskar-core/src/config.rs:181-198` has `subscribe_config()` but `bar/view.rs:266` and `main.rs:55-64` read `ShellConfig::load()` ad-hoc; `ThemeEngine::set_preset` not wired to the signal.

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
- **Source:** cherry-pick `references/gpui-shell/crates/app/src/panel.rs`; adapt to GPUI `WindowKind::LayerShell`.

### 3.2 Service Lifecycle / RunToken (deep module)

- **Location:** new `crates/beskar-services/src/lifecycle.rs` + trait use in `crates/beskar-compositor/src/niri.rs` and hardware services.
- **Extract:** `references/gpui-shell/crates/services/src/lifecycle.rs:46-210` verbatim (rename `ServiceMode` if colliding) — `Lifecycle{status, mode, generation: AtomicU64}`, `RunToken{alive(), set(), error()}`.
- **Apply to:** `NiriBackend::start_listener` (loop checks `token.alive()`), `AudioService`, `NetworkManager`, `BlueZ`, `UPower/Battery` (replace raw `thread::spawn` / `std::process::Command` loops).
- **Rule:** any looping D-Bus/socket reader holds a `RunToken` and breaks when `!alive()`; `stop()` bumps generation; callers via `ManagedService::ensure_started()` for lazy services.

### 3.3 Zero main-thread blocking audit

- **Locations:** `crates/beskar-shell/src/modules/**/mod.rs`, `crates/beskar-services/src/*.rs`.
- **Rule:** every `std::process::Command::new("nmcli"|"bluetoothctl"|"wpctl"|"brightnessctl"|"playerctl"|"swww"|"feh"|"pidof"|"wf-recorder")` or `zbus` blocking call must be inside `tokio::task::spawn_blocking` or async `zbus` call — never in `render`, `View::new`, or `cx.update` synchronously.
- **Output:** `cargo grep` report showing 0 violations after this plan. Add a CI `grep` guard if desired.

### 3.4 Unified BarHost interface + fractional-scale snapping

- **Location:** `crates/beskar-ui/src/bar/mod.rs` + `crates/beskar-shell/src/bar/mod.rs:37-87` + `crates/beskar-shell/src/bar/view.rs`.
- **Contract:** `trait BarStyle { fn widths(&self) -> (leftW, centerX, centerW, rightW); fn is_expanded(&self) -> bool; }` analog of `Bar.qml:16-32`. `bar_window_options` must use `references/gpui-shell/crates/app/src/state.rs:logical_display_size` pattern (fallback to `cx.primary_display()`, handle fractional scale where `wl_output.scale` is integer but GPUI bounds are scaled), not bare `floor()/round()` alone.
- **Hotplug fix:** `main.rs:107-141` → delete `reload_bars(Vec::new(),…)` ; instead `cx.observe_global::<Config>` / config signal like `gpui-shell/bar/view.rs:124-129` and query compositor for fresh workspaces on actual hotplug.

### 3.5 Theme & Config reactive signal

- **Location:** `crates/beskar-core/src/config.rs:181-198` (keep `subscribe_config()`), `crates/beskar-theme/src/lib.rs`, `crates/beskar-shell/src/bar/view.rs:266-283`.
- **Contract:** `ShellConfig::save()` already calls `notify_config_changed`; wire `DesktopBarView` + `main.rs` to a single subscription that updates `is_convex`, `bar_height`, `bar_position`, and `ThemeEngine::set_preset` atomically. Persist fields: `barStyle`, `barIslandExpanded`, `barSlot{L1..R3}`, `themePreset` — mirror `SettingsService.qml:27-41` at minimum.

## 4. File Map

| Input (read) | Output (edit/create) | Notes |
|--------------|----------------------|-------|
| `crates/beskar-shell/src/panel_host.rs` | **rewrite** to slot-aware scrim host | Keep tests, add slot mutex tests |
| `crates/beskar-shell/src/main.rs:107-141` | **edit** remove display-poll clobber | Add `observe_global` reload |
| `crates/beskar-compositor/src/niri.rs:83-202` | **edit** add lifecycle + WorkspaceFocused | `_ = tx.try_send(WorkspaceFocused)` on `WorkspaceActivated` |
| `crates/beskar-core/src/config.rs` | **edit** keep signal, extend defaults | Ensure `modules_left/center/right` defaults |
| `crates/beskar-services/src/lifecycle.rs` | **new** copy of `gpui-shell/lifecycle.rs` |  |
| `crates/beskar-services/src/hardware_bus.rs` + others | **edit** wrap in lifecycle + spawn_blocking |  |
| `crates/beskar-ui/src/bar/mod.rs` | **edit** add `BarStyle` width contract |  |
| `crates/beskar-shell/src/bar/mod.rs:37-87` | **edit** fractional-scale snapping |  |

## 5. Acceptance (gate criteria — all must pass before Plans 01-05)

- [ ] `cargo check && cargo test` green across workspace.
- [ ] `panel_host` slot tests: opening `launcher` (Focus) does not close `dashboard` (Left); opening `controlCenter` (Right) closes `notificationsCenter` (Right) but not `music` (Center); `Escape` + backdrop click close only the scrim's slot.
- [ ] `niri.rs` emits `WorkspaceFocused(id)` on `WorkspaceActivated` and on `WorkspacesChanged` dedup, and respects `RunToken::alive()` restart.
- [ ] Display hotplug no longer calls `reload_bars(Vec::new(),1,None)` — verified by grepping `reload_bars` in `main.rs`.
- [ ] Zero `std::process::Command::new` outside `spawn_blocking`/async in `crates/beskar-shell/src` and `crates/beskar-services/src` (`grep -R "Command::new"` review).
- [ ] `logical_display_size` fallback present in `bar/mod.rs` for fractional scale.
- [ ] Config signal: changing `bar_style` in `config.json` hot-swaps without restart (manual test), `ThemeEngine::set_preset` follows signal.

## 6. Non-goals (deferred to later plans)

- Actual Convex Bézier painting (Plan 01), ControlCenter pages (Plan 02), notifications/clipboard/wallpaper (Plan 03), dashboard/music/capture (Plan 04), lockscreen/settings GUI (Plan 05). This plan only installs the contracts they depend on.
