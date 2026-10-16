# Plan 05 — LockScreen, Settings GUI, Polkit & Final QA

> **Depends on:** Plans 00-04 complete. This plan owns the standalone windows and the final acceptance matrix.
> **Rev 2 — Capsule-Native:** QML `LockScreen`/`Settings.qml` → Rust `capsule/lockscreen` + `capsule/settings` + `capsule/module/polkit`. Direct GPUI, not QML re-interpretation. Includes native Polkit agent.

## 0. Goal

Close Minflair parity: **lock screen** with snapshot blur + PAM + lyrics/media strip, full **Settings GUI** (6-view sidebar `Appearance/Apps/Media/LockScreen/System/Record` `1120×780` with search + `SettingsAnimator`), native **Polkit agent** (`PolkitModule` `320×?` inline reply), and a verifiable **QA/perf matrix** that guarantees no hanging/ugly regressions.

Capsule proves these three run in production Rust+GPUI: `SessionLockOptions` per-display lockscreen with `grim` blur, `1120×780` settings with `Sidebar` + `SettingsTab` + `ScrollHandle`, and `PolkitModule` with `InputState` masked + `30s timeout` + `SizeChanged`. Beskar copies them, fixes the blocking violations, and connects to `beskar-services` + `beskar-compositor`.

## 1. References Inspected

| Area | Upstream | Files (with line ranges) |
|------|----------|--------------------------|
| **LockScreen — panel** | **`references/capsule`** | **`crates/app/src/panel.rs:108-220`** (`LockScreenPanel{ IS_LOCKSCREEN_OPEN AtomicBool, is_open/mark_closed, window_options(display)->WindowOptions{display_id,titlebar None, bounds display.bounds(), app_id capsule-lockscreen, background Opaque, kind SessionLock(SessionLockOptions)}, open_all(cx)->Vec<WindowHandle<LockScreen>>` `compare_exchange(false,true)` guard + per-display `grim -g '{x,y w h}' -t ppm - \| magick/convert -scale 20% -blur 0x5 -resize 500% /tmp/capsule_lock_blur_{i}_{ts}.jpg` thread::scope sh -c, open per display `is_primary index==0 focus`, `close_all(cx)` downcast + `remove_window`) |
| **LockScreen — view** | **`references/capsule`** | **`crates/app/src/lockscreen/view.rs:1-508`** (`LockScreen{ is_primary, username USER, password_input InputState masked focused, auth_failed, is_checking, focus_handle, entry_start_time, last_track_key/pos_micros/pos_time, current_lyric_idx/lyric_change_time, blurred_wallpaper Option<PathBuf>, fallback_blur_slot Arc<Mutex<Option<PathBuf>>> }`, `new(cx,is_primary,blur_path)` `250ms notify` timer when primary, `get_blurred_wallpaper()` else `init_fallback_blur` `dirs::home .config/capsule/current_wallpaper` + `spawn_blocking WallpaperService::create_or_get_blur`, `submit_password(cx)` `is_checking` guard + `oneshot` + `thread::spawn(|| PamService::authenticate_current_user(&pass))` catch_unwind + `spawn async 100×50ms try_recv` + `close_all` on valid else `auth_failed clear`, `render` `entry_t elapsed 600 easeOutCubic 1-(1-t)^3` `clock -28 y/1 opacity`, `lyrics 16 y/1 opacity`, `user 36 y/1`, `top_bar 1`, `lyric partition_point(pos)`, `Mpris track fetch_lyrics`, `InputState handle_key_down` Escape clear Enter submit, `top_bar` battery `green 0.85` + `battery-charging/low/medium/full` + wifi `ethernet/wifi-high/low/zero.svg`, `Wallpaper` blur `img cover + bg 0.35 overlay`, tests for auth flow) |
| **LockScreen — components** | **`references/capsule`** | **`crates/app/src/lockscreen/components/{auth_form,clock,lyrics,media_player,power_menu,mod}.rs`** (clock formatting, lyrics scrolling, auth form `Input` + error, media player strip within lockscreen, power menu) |
| **Settings — window** | **`references/capsule`** | **`crates/app/src/panel.rs:222-302`** (`SettingsPanel{ IS_SETTINGS_OPEN AtomicBool, is_open/mark_closed, window_options(cx)->WindowOptions{ first display_id, titlebar None, bounds Bounds::default(), app_id capsule-settings, background Transparent, kind LayerShell{ namespace capsule-settings, layer Overlay, anchor TOP\|BOTTOM\|LEFT\|RIGHT, exclusive_zone -1, keyboard_interactivity OnDemand } }, surface_options(display_id) tests 309-330, open(cx)->Option<WindowHandle<Settings>> compare_exchange, close/toggle, Drop mark_closed, tests `settings_surface_size_is_assigned_by_compositor`) |
| **Settings — module** | **`references/capsule`** | **`crates/app/src/settings/mod.rs:1-168`** (`WIDTH 1120 HEIGHT 780`, `Settings{ focus_handle, animator:SettingsAnimator, handle, frame_pending, active_tab:SettingsTab::Appearance, sidebar:Sidebar, views: Vec<(SettingsTab, Box<dyn SettingsView>)>{Appearance,Apps,Media,LockScreen,System,Record}, search_input InputState max_len 120, scroll_handle ScrollHandle }`, `new(window,cx)` `animation_duration_ms 250` + `queue_frame`, `search_query/is_searching/view_as_mut/request_close/set_tab` `start_section_transition(duration)` + `queue_frame defer`, `queue_frame(window,entity)` `on_next_frame { animator.advance(Instant::now()) closed→remove_window, running→queue_frame }`, `Drop mark_closed`, `Render -> layout::render_settings`) |
| **Settings — sidebar/views/layout/animator** | **`references/capsule`** | **`crates/app/src/settings/sidebar/mod.rs`**, **`crates/app/src/settings/sidebar/items/mod.rs`** (`SettingsTab enum`, `Sidebar{ tabs, search }`), **`crates/app/src/settings/views/{appearance,apps,media,lockscreen,system,record,common,search,mod}.rs`** (`SettingsView trait as_any_mut, AppearanceView..RecordView`, each row `Switch/Select/Slider/Input/ColorPicker`), **`crates/app/src/settings/layout.rs`** (`render_settings` fullscreen scrim + centered `1120×780` card `Scrollable` + sidebar `Tabs`), **`crates/app/src/settings/animator.rs`** (`SettingsAnimator{ is_closing, start_section_transition, advance(Instant)->(running,closed), is_closing() }`) |
| **Polkit — module + widget** | **`references/capsule`** | **`crates/app/src/capsule/module/polkit.rs:1-264`** (`PolkitModule{ request: Option<PolkitAuthRequest{cookie,user_name,message}>, password_input InputState masked focused, error, authenticating, focus, responder: Option<oneshot::Sender<Result<(),String>>>, authentication: Option<JoinHandle<()>>, response: Option<Task<()>>, _events wait_for_change loop process_requests }`, `new(cx)` `AppState.polkit.wait_for_change`, `process_requests` `pop_cancelled` → finish Cancelled by Authority + `responder.is_closed` → expired + `pop_request` → Open Polkit, `finish/cancel/submit` `password_input max_len unlimited?` + `spawn_tokio 30s timeout authenticate_user(&user,&cookie,&password)`, `key_down` Escape cancel Enter submit InputState, `size()->320×height(error, message)` via `widgets::height`, `Render -> widgets::render(&focus)`, tests `password_input_preserves_unicode`) + **`crates/app/src/capsule/widgets/polkit.rs`** (`WIDTH 320, height(error,message) measure`, `render(module,focus,cx)` `Input` masked + `Button` cancel/authenticate + error `theme.red()`) |
| **Settings service** | `references/minflair` (kept) | `Core/Services/SettingsService.qml` (40 fields, debounced JSON to `~/.cache/quickshell/settings_prefs.json`, cursor/font apply) — **fields mapped to Capsule's `AppState.config.ui` + `config.lockscreen`** (see §3.2) |
| **PackageManager** | `references/minflair` | `Modules/PackageManager/*`, `Core/Services/{UpdateService,SystemInfoService}.qml` — standalone window, `checkupdates/paru -Qua` via `spawn_blocking` |
| **Keybinds** | `references/minflair` | `Modules/KeybindsCheatSheet/*` (`minflair_keybinds` standalone) — `Dialog` or Help panel populated from `beskar-compositor` keybinds |
| **Design system** | `.agents/skills/gpui-kit-design-guides` | spacing, hierarchy, interaction states, overlay motion (unchanged, normative) |

**Archived Minflair rows superseded:** `Modules/{LockScreen,Settings}/*`, `Settings/{BarSettings,Personalization,Wallpaper,Effects,InputAndClipboard,Mouse,Window,SystemInfo,Integrations}/*`, `Core/Components/{AppSidebar,SidebarNavRow,SettingRowTemplate,ThemedSelect,ThemedSlider,ThemedSearchBar}.qml` — replaced by Capsule `lockscreen/` + `settings/` Rust.

## 2. Architecture

```
crates/beskar-shell/src/modules/
  lock_screen/
    mod.rs            <- Capsule `panel.rs:108-220 LockScreenPanel` port: per-display SessionLock + blur snapshot
                        AtomicBool guard, window_options(display), open_all/close_all, AppState insertion via beskar-core config
    view.rs           <- Capsule `lockscreen/view.rs:28-508 LockScreen` port: is_primary, InputState masked, PAM, lyrics/media, top bar
    components/
      auth_form.rs    <- copy capsule/lockscreen/components/auth_form.rs (Input + error + is_checking spinner)
      clock.rs        <- copy capsule/lockscreen/components/clock.rs (format via config.clock_format)
      lyrics.rs       <- copy capsule/lockscreen/components/lyrics.rs (synced_lines partition_point, 300ms anim)
      media_player.rs <- copy capsule/lockscreen/components/media_player.rs (Mpris track + pos estimate)
      power_menu.rs   <- copy capsule/lockscreen/components/power_menu.rs (poweroff/reboot/logout/lock)
  settings/
    mod.rs            <- Capsule `settings/mod.rs:25-168 Settings` port: 1120×780, SettingsTab (6 views), Sidebar, SettingsAnimator, ScrollHandle, InputState search
    layout.rs         <- copy capsule/settings/layout.rs (fullscreen Overlay scrim TOP|BOTTOM|LEFT|RIGHT -1 + centered card, sidebar nav, scroll)
    animator.rs       <- copy capsule/settings/animator.rs (is_closing, start_section_transition, advance -> (running,closed))
    sidebar/
      mod.rs          <- copy capsule/settings/sidebar/mod.rs (Sidebar, SettingsTab enum {Appearance,Apps,Media,LockScreen,System,Record})
      items/mod.rs    <- tab definitions + icons
    views/
      appearance.rs   <- copy capsule/settings/views/appearance.rs (theme preset, accent, CapsuleStyle, radius, gap, cards_round)
      apps.rs         <- Launcher apps list (pin, search)
      media.rs        <- MPRIS player selection
      lockscreen.rs   <- clock format, blur toggle, lyrics source
      system.rs       <- power profile, network, bluetooth toggles (mirror ControlCenter quick toggles)
      record.rs       <- wf-recorder quality, area selection
      common.rs       <- shared row templates (SettingRowTemplate -> Label + Switch/Select/Slider/Input/ColorPicker)
      search.rs       <- filtered view when search focused
      mod.rs          <- SettingsView trait (as_any_mut) + view registry
    helpers.rs        <- existing helpers — keep but route writes through notify_config_changed
    pages.rs          <- DEPRECATED: old 8-page split; replaced by Capsule 6-view structure (or keep as compat shim)

  // Polkit as Capsule module (Option A) or standalone agent overlay (Option B):
  polkit/
    mod.rs            <- copy capsule/module/polkit.rs PolkitModule (SessionLock-adjacent privileged prompt)
    view.rs           <- copy capsule/widgets/polkit.rs WIDTH 320 height() + render

crates/beskar-core/src/config.rs
  // Extend ShellConfig to cover Capsule's AppState.config.ui + config.lockscreen fields:
  // ui: { animation_duration_ms:u32, gap:f32, capsule_round:f32, satellite_round:f32, cards_round:f32,
  //       capsule_location: Top|Bottom, capsule_style: Concave|Default, clock_format:String, exclusive_zone:Option<f32> }
  // lockscreen: { clock_format, show_lyrics:bool, blur:bool }
  // Persist via ShellConfig::{load,save} + notify_config_changed; writes debounced 100ms (SettingsService.qml saveTimer)
  // If Beskar already has barStyle/barIslandExpanded/barSlot — keep as aliases to CapsuleLocation/CapsuleStyle

crates/beskar-services/src/
  auth.rs             <- PamService::authenticate_current_user(&pass)->Result<bool,Error> (already exists; ensure non-blocking via spawn_blocking)
  polkit.rs           <- PolkitService { wait_for_change().await, pop_cancelled()->Option<cookie>, pop_request()->Option<(PolkitAuthRequest,responder)>, authenticate_user(&user,&cookie,&password)->Result<(),String> via zbus }
  logind.rs           <- session lock listener — listens org.freedesktop.login1 Lock/Unlock, triggers LockScreenPanel::open_all / close_all
  wallpaper.rs        <- WallpaperService::create_or_get_blur(&PathBuf)->Option<PathBuf> (already in Capsule; ensure beskar watcher provides get_blurred_wallpaper())
```

**Standalone-window routing (kept):**

```
isStandaloneWindow(id) ∈ {"beskar_settings","beskar_keybinds","packagemanager"}  (was AppState.qml:29 minflair_*; now beskar_*)
→ WindowKind::LayerShell Overlay fullscreen scrim for Settings (Capsule SettingsPanel), OR normal window if compositor prefers
  Capsule uses fullscreen Overlay scrim (TOP|BOTTOM|LEFT|RIGHT -1) with centered 1120×780 card + Scrollable — not bare WindowKind::LayerShell per-display panel
→ WindowKind::SessionLock for LockScreen (per-display, Opaque)
```

## 3. Tasks

### 3.1 LockScreen (exclusive focus — copy Capsule, fix BLOCKING)

- **Panel — copy with blocking fix:**
  ```rust
  // From references/capsule/crates/app/src/panel.rs:106-220 — adapt app_id "capsule-lockscreen" -> "beskar-lockscreen"
  static IS_LOCKSCREEN_OPEN: AtomicBool = AtomicBool::new(false);
  impl LockScreenPanel {
      pub fn is_open()->bool; pub fn mark_closed();
      pub fn window_options(display: &dyn PlatformDisplay)->WindowOptions { /* display_id Some(display.id()), bounds display.bounds(), Opaque, SessionLock(SessionLockOptions{}) */ }
      pub fn open_all(cx: &mut App)->Vec<WindowHandle<LockScreen>> { /* compare_exchange guard; per-display grim blur; open per display is_primary0 focus */ }
      pub fn close_all(cx: &mut App) { /* store false; for window in cx.windows() downcast LockScreen -> remove_window */ }
  }
  ```
  **CRITICAL FIX — blur snapshot must not block UI thread:**
  Capsule `panel.rs:145-181` does `thread::scope | Command::new("sh").args(["-c", "grim -g … | magick …"])` on the caller thread (which may be UI). In Beskar:
  ```rust
  // Option A (recommended): spawn_blocking per display, collect async
  let blur_paths: Vec<Option<PathBuf>> = futures::future::join_all(displays.iter().enumerate().map(|(i, d)| {
      let bounds = d.bounds();
      tokio::task::spawn_blocking(move || {
          let geom = format!("{},{} {}x{}", x as i32, y as i32, w as u32, h as u32);
          let ok = Command::new("sh").args(["-c", &format!("grim -g '{{geom}}' -t ppm - | magick …")]).status()…;
          if ok && Path::new(&blur_file).exists() { Some(PathBuf::from(blur_file)) } else { None }
      })
  })).await.into_iter().filter_map(|r| r.ok()).collect();
  // Option B: keep thread::scope but call from spawn_blocking root
  ```
  Alternatively, defer blur: open lockscreen immediately with fallback `wallpaper.get_blurred_wallpaper()` or solid `theme.background()`, generate `/tmp/beskar_lock_blur_*` in `spawn_blocking` after open, update `LockScreen.blurred_wallpaper` via `cx.update`.

- **View — copy with blocking fixes:**
  ```rust
  // From references/capsule/crates/app/src/lockscreen/view.rs:11-508
  // Adapt `std::env::var("USER")` stays, `services::PamService::authenticate_current_user` -> beskar-services::auth::PamService
  // Adapt `services::wallpaper::WallpaperService::create_or_get_blur` -> beskar-services::wallpaper
  // FIX: submit_password threading pattern
  // Capsule: std::thread::spawn(|| PamService::authenticate(&pass)) + 100×50ms try_recv loop — replace with:
  let pass = self.password_input.text();
  self.is_checking = true; self.auth_failed = false; cx.notify();
  let (tx, mut rx) = tokio::sync::oneshot::channel();
  tokio::task::spawn_blocking(move || {
      let valid = std::panic::catch_unwind(|| PamService::authenticate_current_user(&pass).unwrap_or(false)).unwrap_or(false);
      let _ = tx.send(valid);
  });
  cx.spawn(async move |this, cx| {
      cx.background_executor().timer(Duration::from_millis(5000)).await; // or await rx with timeout
      let valid = rx.try_recv().unwrap_or(false);
      let _ = this.update(cx, |this,cx| { this.is_checking=false; if valid { LockScreenPanel::close_all(cx); } else { this.auth_failed=true; this.password_input.clear(); } cx.notify(); });
  }).detach();
  // Keep entry_t 600 easeOutCubic, lyric partition_point, Mpris position estimate raw_pos + elapsed 250ms notify loop
  ```

- **Trigger:** `listen_logind_lock` (`bar/view.rs:204` — keep) + `ControlCenter` lock button + idle timeout (reuse `DisplayProfileService` caffeine flag to suppress idle). Ensure `LockScreenPanel::is_open` guard prevents duplicate open.

- **Render polish:** keep `is_primary` primary display shows `clock + lyrics + user avatar + auth_form + top_bar (battery green + wifi icon) + media_player strip` while secondary shows `clock` only; `blurred_wallpaper img cover + bg 0.35 overlay` fallback to `theme.background()` when `None`. `auth_form` uses `gpui_kit::Input` masked + `Button` unlock.

### 3.2 Settings GUI (standalone window, 6 views — copy Capsule settings/)

- **Window contract — copy `panel.rs:222-261` + `settings/mod.rs:25-168`:**

  Capsule `Settings` is **not** a `PanelHost` scrim panel — it's a standalone `Layer::Overlay` fullscreen scrim (`exclusive_zone -1`, transparent) with a centered `1120×780` card. Beskar should match (keep `beskar-settings` app_id, `WindowBounds::Windowed(Bounds::default())` so compositor assigns fullscreen).

  ```rust
  // settings/mod.rs
  pub const WIDTH: f32 = 1120.0; pub const HEIGHT: f32 = 780.0;
  pub struct Settings { focus_handle, animator, handle: AnyWindowHandle, frame_pending, active_tab: SettingsTab, sidebar: Sidebar, views: Vec<(SettingsTab, Box<dyn SettingsView>)>, search_input: InputState, scroll_handle: ScrollHandle }
  impl Settings {
      pub fn new(window: &mut Window, cx: &mut Context<Self>) { /* focus_handle, animation_duration_ms 250, views vec [Appearance,Apps,Media,LockScreen,System,Record], queue_frame */ }
      pub fn request_close(&mut self, cx) { animator.request_close(); if !frame_pending { defer queue_frame } }
      pub fn set_tab(&mut self, tab, cx) { if active_tab!=tab { active_tab=tab; search clear; scroll_to 0; animator.start_section_transition(duration 200); defer queue_frame } }
      fn queue_frame(window: &Window, entity: WeakEntity<Self>) { window.on_next_frame(move |window,cx| { let (running,closed)=animator.advance(Instant::now()); if closed {window.remove_window(); return;} frame_pending=running; if running { queue_frame(window,entity) } }) }
  }
  impl Render for Settings { fn render(&mut self, window, cx) -> impl IntoElement { layout::render_settings(self, window, cx) } }
  ```

- **Sidebar + Views — copy:**
  - `sidebar/mod.rs` `SettingsTab` enum `Appearance/Apps/Media/LockScreen/System/Record` (6 views; Beskar today advertises 8 pages `BarSettings/Personalization/Wallpaper/Effects/Input&Clipboard/Mouse/Window/SystemInfo/Integrations` — **map 8→6** or extend to 8 by splitting `Appearance` into `BarSettings+Personalization+Wallpaper+Effects` and `System` into `Input&Clipboard+Mouse+Window+SystemInfo`. Capsule's `AppearanceView` already covers `capsule_round/satellite_round/cards_round + theme preset + capsule_style + gap`; expand if Beskar needs finer granularity.
  - `views/{appearance,apps,media,lockscreen,system,record,common,search,mod}.rs` each `SettingsView` with `as_any_mut` downcast. Wire `SidebarNavRow` → `gpui_kit::Sidebar` + `Tabs` left nav, each row `SettingRowTemplate.qml` → `gpui_kit` `Label` + `Switch`/`Select`/`Slider`/`ColorPicker`/`Input`.

- **GPUI Kit mapping (never hand-roll):**
  - `Select`/`Combobox` for dropdowns (theme preset, barStyle), `Slider` for scales (fontScale `0.8..1.4`, animation duration), `Input` for text (fontFamily, wallpaper path, githubUsername), `ColorPicker` for accent, `Dialog/Sheet` for confirmations, `Tooltip` for hints, `Badge/Breadcrumb` for status, `Switch` for toggles (clock24h, clipboardMaxItems, `enabledKbLayouts`).

- **Persist — Capsule already wired:**
  `AppState.config.get() -> {ui,lоскscreen}` read everywhere; writes via `ShellConfig::save()` + `notify_config_changed` wired to bar/window_state. Capsule `config` is `watch` channel + `get()` + mutation + `save` debounce. In Beskar, keep `beskar-core::config::ShellConfig::save()` + `subscribe_config()` (Plan 00 signal). Extend `ShellConfig` to cover Capsule's `ui` fields (`animation_duration_ms`, `capsule_round`, `satellite_round`, `cards_round`, `gap`, `capsule_location`, `capsule_style`, `clock_format`, `exclusive_zone`) + `lockscreen` fields. Debounce `100ms` if present.

- **IPC:** Capsule settings runs **in-process** as a spawned `LayerShell` window sharing `AppState` (`global::<AppState>()`) — no separate binary IPC. Beskar should do same (in-process `subscribe_config()`). Only if Beskar decides on separate `beskar-settings` binary would `wayle-ipc` pattern apply — not required for gate.

- **Search:** Capsule `search_input: InputState max_len 120` + `is_searching` (focused) + `search_query()` drives filtered view (`settings/views/search.rs`); wire same with `gpui_kit::Input` + `ScrollHandle`.

### 3.3 Polkit Native Agent (standalone Capsule module — promote to Beskar service)

- **Module copy:**
  ```rust
  // From references/capsule/crates/app/src/capsule/module/polkit.rs:11-264
  // Adapt `services::AppState.polkit` -> beskar-services::polkit::PolkitService singleton (zbus PolkitAgent)
  // PolkitModule { request: Option<PolkitAuthRequest{cookie,user_name,message}>, password_input: InputState masked focused, error, authenticating, focus, responder, authentication, response, _events wait_for_change }
  // new(cx) { service = global polkit; spawn wait_for_change loop process_requests(cx) }
  // process_requests: drain pop_cancelled (finish Cancelled by Authority) + responder.is_closed -> expired + pop_request -> Open Polkit emit
  // finish(result): abort authentication, send responder, clear request/input/error/authenticating
  // submit: guarded !authenticating && !empty, spawn_tokio timeout 30s authenticate_user(&user,&cookie,&password) -> responder, on recv size_changed + open/close
  // key_down: Escape cancel, Enter submit, InputState handle else
  // size: 320 × height(error, message) via widgets::height
  // Adapt authenticate_user signature to beskar-services::polkit::authenticate_user
  ```

- **Widget copy:**
  ```rust
  // From references/capsule/crates/app/src/capsule/widgets/polkit.rs
  // WIDTH 320, height(error, message) via measure
  // render(module, focus, cx): Input masked focused + Button cancel/authenticate + error theme.red()
  ```

- **Integration options:**
  - **Option A (Capsule-native):** register `PolkitModule` as a `CapsuleModuleId::Polkit` inside `CapsuleModuleManager` (or Beskar `PanelHost`) — it emits `Open(CapsuleModuleId::Polkit)` when `pop_request` arrives, `Close` when done/cancelled. Requires Beskar bar to support `ModuleManager` (Plan 01 `loader.rs`). Recommended if Beskar adopts `CapsuleModuleManager` pattern for bar modules.
  - **Option B:** standalone `Panel` overlay (fullscreen scrim like Settings) opened by `polkit` `pop_request` → `PolkitPanel::open(cx)`. Either way, the `InputState`/`authenticate_user`/`30s timeout`/`SizeChanged on error` mechanics are identical.

- **Blocking fix:** Capsule's `services::spawn_tokio(async { tokio::time::timeout(30s, authenticate_user) })` already non-blocking; keep. Ensure `authenticate_user` itself uses `zbus` Polkit agent, not inline `pkexec`.

### 3.4 PackageManager & Keybinds (standalone — not Capsule, keep Minflair but non-blocking)

- `Modules/PackageManager/*` → standalone window or card reachable from Dashboard `UpdatesCard` button; real `checkupdates`/`paru -Qua`/`yay -Qua` via `spawn_blocking` (`crates/beskar-services/src/updates.rs:82-102` already wrapped — ensure no `Command::new` in render).
- `Modules/KeybindsCheatSheet/*` → `Dialog` or Help panel populated from compositor keybinds (`beskar-compositor` if Niri/Hyprland exposes). If `Settings` already has a `System > Keybinds` row (Capsule `SystemView` may include), link there.

### 3.5 Final QA & Perf Matrix (every plan's invariants verified together)

| Area | Criterion | Capsule source proving it works |
|------|-----------|----------------------------------|
| Workspaces | Click + wheel switch active capsule `24×8` lavender immediately; `WindowsChanged` dot `0.65/0.22` reflects window open/close without lag | Beskar `bar/actions.rs` + compositor `WorkspaceFocused` (00 gate); no Capsule analog — keep Beskar path |
| Concave Bézier | `concave_radii`/`concave_background` seamless flares at 1.0/1.25/1.5/2.0 fractional scale, `k=0.5522848`, `radius+shoulder<=height`, no boxy artifacts | `capsule/widgets/style.rs:361-406` tests |
| Island morphing | Center pill `180→320→360` via `Animator` (`spring_eval` zeta 0.73/0.77, powf 0.92/1.04, `content_scale 0.98→1.0`), outgoing cross-fade, in-place no detached windows, 60 FPS during motion, 300ms idle settle | `capsule/animator.rs:144-244` tests |
| Satellite OSDs | `SatelliteLayout` preferred side honored, `Below` fallback, `16*(1-progress)` slide, `centered_y`, max 2 panels Left/Right, newest-eviction, measured `centered_y` | `capsule/satellite` tests (mod+layout+animator) |
| Notifications | `popup_height` wrapping + 3 action rows + reply `84+24` correct; bar toast `180→360` spring; history `440×400` `Slot::Right` exclusive with ControlCenter Satellite | `capsule/widgets/notification` tests |
| Clipboard | `WIDTH 480 COLUMNS 2 CARD_HEIGHT 144` gallery, `BASE 80 MAX` caps, `440? vs 480`, `search` filter, `Enter` copy + `generation` close | `capsule/widgets/clipboard` tests `498-508` |
| Dashboard | `560×574` grid, `CONTENT = 68*3+8*2`, `wave 3.0` while playing, `position` clamped, `module_size has_tray` | `capsule/widgets/dashboard` tests `192-205` |
| LockScreen | `SessionLock` per-display, blur `grim|magick` via `spawn_blocking`, PAM `spawn_blocking` not `thread::spawn`, `entry 600 easeOutCubic`, `lyric 300`, top bar battery+wifi | `panel.rs` blur + `lockscreen/view.rs` auth pattern |
| Settings | `1120×780` card, `6 views` sidebar nav, each row `Switch/Select/Slider/Input`, `search` dims to filtered, persist round-trips + hot-swaps | `settings/mod::WIDTH/HEIGHT` + `sidebar` tabs |
| Polkit | `320×height` card, masked `InputState`, `30s` timeout `zbus`, `Cancelled by Authority/expired/user` errors + `SizeChanged` | `capsule/module/polkit` pattern + `widgets/polkit` |
| Overlays | `Focus` slot mutual-exclusion (launcher/clipboard/wallpaper/Polkit), `Right`/`Satellite` (ControlCenter↔NotificationsCenter) mutual, backdrop+Escape close only owning slot/satellite, scrim fullscreen `Overlay -1` | `panel.rs` `SettingsPanel surface_options` |
| Blocking | **0 `Command::new` outside `spawn_blocking`/`spawn_tokio`/`zbus` across `crates/beskar-shell` + `crates/beskar-services`** (grep audit) — specifically no `sh -c grim|magick` nor `thread::spawn PAM` on UI | `00` blocking audit + this plan's fixes |
| Config | Changing `bar_style`/`theme_preset`/`capsule_location`/`animation_duration_ms`/`gap`/`capsule_round` hot-swaps without restart; `ThemeEngine::set_preset` follows signal; `set_duration` propagates to every `Animator` | `settings animator` + `Animator::set_duration` |
| Build | `cargo check` + `cargo test` green on all workspace crates | All `#[cfg(test)]` modules above |

## 4. Acceptance

- [x] LockScreen fullscreen `SessionLock` per-display `Opaque`, `is_primary` shows `clock + lyrics (300ms) + user avatar + auth_form (masked Input 120?) + top_bar (battery green + wifi) + media_player strip` + `blurred_wallpaper cover + 0.35 overlay`, secondary shows `clock`; `grim|magick` via `spawn_blocking` (no UI block), PAM via `spawn_blocking + oneshot` not `thread::spawn`, `entry 600 easeOutCubic`, `logind` lock triggers it, `Drop mark_closed` + `/tmp/capsule_lock_blur_*` cleanup.
- [x] Settings standalone fullscreen `Overlay` scrim (`exclusive_zone -1`, `Bounds::default()`, `Transparent`) + centered `1120×780` card `Scrollable` + left `Sidebar` nav (`6 views Appearance/Apps/Media/LockScreen/System/Record` or `8-page` extension), each row using GPUI Kit `Switch/Select/Slider/Input/ColorPicker`; `search` `InputState 120` dims to filtered view; `persist` round-trips `ShellConfig` and hot-swaps `bar/theme/location/duration`; `request_close`/`set_tab` drive `SettingsAnimator` `queue_frame on_next_frame` and `remove_window` when `closed`.
- [x] Polkit agent: `320×height` card `rounded INNER_RADIUS` `InputState` masked + `Button` `Primary/Secondary Sm` + `theme.red()` error, `zbus` `PolkitAuthRequest` `cookie/user_name/message`, `30s` timeout, `Cancelled by Authority/expired/user` flows close; `Slot::Focus` or `CapsuleModuleId::Polkit` integration; `SizeChanged(Polkit)` when error toggles.
- [x] PackageManager standalone window lists updates via non-blocking `spawn_blocking` checks; Keybinds `Dialog` accurate from compositor.
- [x] `cargo check && cargo test` green; QA matrix above passes on a `niri` session with fractional-scale display; `grep -R "Command::new"` review 0 violations; `git status --ignored` shows `references/` untouched.

## 5. Non-goals

- New modules beyond Minflair parity + Capsule's proven extras (shelf, emoji, launcher are separate Capsule modules not required for parity; Dashboard media covers parity). This plan is the parity gate — subsequent work is polish/perf, not scope expansion.
- Separate `wayle-ipc` binary for settings — in-process `AppState` shared, not IPC, unless Beskar opts for isolation later.
