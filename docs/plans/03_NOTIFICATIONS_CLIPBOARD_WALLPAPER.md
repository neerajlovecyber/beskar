# Plan 03 — Notification Stack, Clipboard, Wallpaper

> **Depends on:** Plan 00 (OverlayHost, Lifecycle, **Animator**, Theme). Parallel with 01/02 after 00.
> **Rev 2 — Capsule-Native:** QML `NotificationService`/`ClipboardService` translation replaced by Rust GPUI `module/notification.rs` + `module/clipboard.rs` + `widgets/*` cherry-picks.

## 0. Goal

Port the 3 focused overlays that share mutual-exclusion: freedesktop Notifications (toast layer + center/history with inline reply), Clipboard history + Snippets grid (2-column gallery), and Wallpaper selector with dynamic palette engine — by copying Capsule's GPUI modules, not re-deriving Minflair QML delegates.

## 1. References Inspected

| Area | Upstream | Files (with line ranges) |
|------|----------|--------------------------|
| **Notifications — module** | **`references/capsule`** | **`crates/app/src/capsule/module/notification.rs:1-288`** (`NotificationModule{items,latest,history,reply: Option<Reply{id,input,pending,failed}>, popup_height, text_system, focus, expiry, response}`, `new(cx)` subscribes `NotificationStore::global().subscribe()` + `observe_global<Theme>`, `update_popup_height`, `open(history,cx)`, `set_active`, `refresh(cx)` dedup + reply cleanup + `NotificationChanged`, `schedule_expiry` 60s fallback else `timeout - elapsed`, `dismiss`, `action(id,key,window,cx)` inline-reply vs `invoke_action`, `cancel_reply`, `send_reply` oneshot + `spawn_tokio(reply).await`, `key_down` Escape/Enter/InputState routing, `size()->440×{HISTORY 400 or popup_height}`, `Render` id `notification-module` focus track) |
| **Notifications — widgets** | **`references/capsule`** | **`crates/app/src/capsule/widgets/notification.rs:1-493`** (`WIDTH 440 HISTORY_HEIGHT 400`, `visible_action`, `action_label` i18n `notifications_module.reply/open`, `measure(text,size,weight,wrap,cx,text_system)->Size` via `text_system.shape_text` + `WIDTH-32` wrap + 4 lines clamp, `actions_height` row packing `width 30 + measure 11` min `width`, `popup_height(item,replying,failed,cx,text_system)` `32+32+10+summary+body+10+actions` max 3 rows `28+6`, reply `84+24`, `render(module,theme,cx)` header `18 SEMIBOLD + Badge + trash/close IconButton`, `list.reverse()` cards, `card(module,item,popup,theme,cx)` `32 pill icon + dismiss`, `content` default-action click, `Chip` actions, `Input` reply `36×INNER_RADIUS` + cancel/send `Button`, failed `theme.red()`, tests `458-493`) |
| **Clipboard — module** | **`references/capsule`** | **`crates/app/src/capsule/module/clipboard.rs:1-312`** (`ClipboardModule{model:ClipboardModel, search_input:InputState, loading,busy,error,pinned,images:HashMap<String,Arc<Image>>, scroll:ScrollHandle, generation, sender:UnboundedSender<Request>, worker}`, `new(cx)` `worker::start(clipboard)` + channel loop `size()+scroll_to_item+SizeChanged`, `open(cx)` `generation+1 clear/search("") loading`, `search/query switch_tab/select/request/copy/pin/remove/clear/key_down` Escape/Enter/Tab/arrow/home/end/InputState routing, `size()->480×{BASE+80 or rows*CARD_HEIGHT+GAP}` min 2 rows, `Render` focus track) |
| **Clipboard — widgets** | **`references/capsule`** | **`crates/app/src/capsule/widgets/clipboard.rs:1-509`** (`WIDTH 480 COLUMNS 2 CARD_HEIGHT 144 GRID_GAP 10 PADDING 16 HEADER 40 TABS 28 FOOTER 18 BASE_HEIGHT = PADDING*2+HEADER+TABS+FOOTER+GAP*3 MAX_HEIGHT = BASE+2*CARD_HEIGHT+GAP CARD_WIDTH=(WIDTH-PADDING*2-GRID_GAP)/2`, header `Input` search `cleanable rounded_full` + `trash/close` actions, tabs `History/Snippets` accent vs surface, gallery `overflow_y_scroll track_scroll`, empty states, 2-col rows `chunk(COLUMNS)`, card `border accent vs border(theme) bg selected vs surface` + `transitions bg ease_in_out`, image `144 CARD_WIDTH-4 ×104 rounded preview` vs text `12px CARD_HEIGHT-104 36 footer`, footer error/busy/hint + count, tests `498-508`) |
| **Clipboard — model/worker** | **`references/capsule`** | **`crates/app/src/capsule/module/clipboard/model.rs`** (`ClipboardModel{items,snippets,filtered,selected,tab:History|Snippets,query}`, `update/search/switch/navigate`), **`crates/app/src/capsule/module/clipboard/worker.rs`** (`Request{Active,Refresh,Copy,CopyText,Pin,Remove,Clear}`, `start(clipboard)->(sender,receiver,JoinHandle)`, dedup by content hash, `spawn_blocking` for arboard, image decode) |
| **Wallpaper selector** | `references/minflair` (kept) | `Modules/WallpaperSelector/*`, `Core/Services/WallpaperManager.qml`, `Scripts/theme/generate_theme.py` (Wallpaper HSL engine) — **no Capsule analog; keep Minflair palette flow** |
| **Aesthetics/Theme** | `references/suzuha`, `references/amane` | `src/theme.rs`, `src/theme/hsl.rs`, `src/liquid.rs`, `shaders/` (HSL wallpaper palette, glass acrylic) — unchanged |
| **GPUI Kit lists** | `references/gpui-kit` | `crates/component/src/{list,scroll,virtual_list,input,dialog}` — `InputState` maps 1:1 to `ui::components::InputState` in Capsule; ensure `gpui_kit::Input`/`ScrollHandle` seam |

**Archived Minflair rows superseded:** `Modules/{Notifications,NotificationCenter,Clipboard}/*`, `Core/Services/{NotificationService,NotificationData,ClipboardService}.qml`, `Modules/Bar/Components/BaseNotifLayer.qml` — replaced by Capsule rows above.

## 2. Architecture

```
crates/beskar-services/src/
  notifications.rs   (freedesktop Notifications D-Bus: notify-send + zbus — already exists; keep but expose NotificationStore::global() singleton like Capsule)
    -> align API to Capsule's NotificationStore::{subscribe, get_all_notifications, get_latest_active_notification, remove_notification, clear_all_notifications, invoke_action, reply, set_hovered, contains_notification, is_dnd_enabled}
  clipboard.rs       (wayland-data-control via arboard + snacks/pinned store — align to Capsule's services::clipboard::{ClipboardContent, ClipboardService})
  watcher.rs         (wallpaper file watcher via notify — already exists)
  palette.rs         (HSL palette extraction from wallpaper — extract suzuha/amane; no Capsule analog)

crates/beskar-shell/src/modules/
  notification_center/
    mod.rs            <- CapsuleModuleManager integration: NotificationModule (Capsule IDs -> Beskar Slot mapping)
    view.rs           <- thin re-export of capsule/widgets/notification::render (or fork with beskar-theme)
  clipboard/
    mod.rs            <- ClipboardModule (Capsule IDs -> Beskar Slot::Focus)
    model.rs          <- copy capsule/module/clipboard/model.rs
    worker.rs         <- copy capsule/module/clipboard/worker.rs (adapt AppState.clipboard -> beskar clipboard service)
  wallpaper_selector/
    mod.rs            <- PanelModule Slot::Focus (keep existing grid, but apply via spawn_blocking swww/feh)
    view.rs           <- grid + preview + search Input (gpui_kit)

crates/beskar-ui/src/widgets/
  notification_row.rs <- if forking: copy capsule/widgets/notification.rs card() + popup_height/actions_height/measure
  clipboard_row.rs    <- if forking: copy capsule/widgets/clipboard.rs row/card rendering + action() helper
  // Alternatively: crates/beskar-shell/src/modules/notification_center/widgets.rs and clipboard/widgets.rs hold the copies
```

**Slot mapping:**

- Capsule `CapsuleModuleId::Notification` has two modes: `history=false` popup (toast, `popup_height` dynamic 126..~280) vs `history=true` overlay (`HISTORY_HEIGHT 400`). The popup is **not** a `PanelHost` overlay — it's rendered inline inside the capsule bar via `NotificationChanged` + `SizeChanged` (Capsule `capsule/mod.rs` `handle_module_event`). In Beskar's 3-region bar, the popup maps to **bar center pill toast** (`bar/view.rs:118-121` `sync_notification_toasts` + spring `180→360` expansion). The `history=true` variant maps to `PanelModule Slot::Right` center list (mutual-exclusive with ControlCenter Satellite).
- Capsule `CapsuleModuleId::Clipboard` → `PanelModule Slot::Focus` (closes launcher/wallpaper/powerMenu). Size `480 × (BASE_HEIGHT + body)` capped at `MAX_HEIGHT` (Beskar today uses fixed card; Capsule's `480×2-col×144` gallery already matches Minflair `ClipboardContent.qml` layout).

All Focus panels use Plan 00 scrim + bounded `Scrollable`/`VirtualList`, but **Capsule clipboard already uses `ScrollHandle` + `track_scroll` + 2-col gallery** — keep it, don't re-introduce `VirtualList` unless dataset exceeds Capsule's ~2 visible rows. For 100-item scroller with `VirtualList`, extend gallery to virtualized if needed.

## 3. Tasks

### 3.1 Notifications (toast layer + NotificationCenter — copy Capsule, adapt Beskar bar)

- **Module copy:**
  ```rust
  // From references/capsule/crates/app/src/capsule/module/notification.rs:13-288
  // Adapt `services::AppState.language.get(key)` → beskar i18n stub or keep AppState alias
  // Adapt `ui::components::InputState` → gpui_kit InputState or keep ui alias
  // Adapt `services::spawn_tokio` → tokio::task::spawn_blocking + zbus where needed
  pub struct NotificationModule { items, latest, history, reply: Option<Reply>, active, popup_height, text_system, focus, expiry, response, _events, _theme }
  pub struct Reply { id, input: InputState, pending, failed }
  // Keep CapsuleModule::size() => 440×{400 or popup_height} for overlay sizing;
  // Beskar BarHost recomputes bar window size from popup_height via maximum_window_size (Plan 00)
  ```

- **Widget copy:**
  ```rust
  // From references/capsule/crates/app/src/capsule/widgets/notification.rs:1-493
  // Constants: WIDTH 440 HISTORY_HEIGHT 400 — keep for NotificationCenter, but bar toast uses inline card
  // Keep popup_height() + actions_height() + measure() pure fns — they depend on theme.font_family() and WindowTextSystem
  // Keep render() header (Badge + IconButton trash/close), list reverse() + card(), card() app_icon resolve via launcher apps
  // Adapt `ui::components::{Badge,Button,Chip,IconButton,Input}` → gpui_kit equivalents:
  //   Badge::new(count).variant(Neutral) → gpui_kit::Badge
  //   IconButton::new(id, icon).size(30).tooltip().on_click → gpui_kit Button ghost
  //   Chip::new(id,label).on_click → gpui_kit Chip/Tag
  //   Input::from_state(id,&reply.input).h_px(36).rounded(INNER_RADIUS) → gpui_kit Input
  //   Button::new(id).label().variant(Primary/Secondary).size(Sm) → gpui_kit Button
  ```

- **D-Bus:** `org.freedesktop.Notifications` via `zbus` — **align `NotificationStore` API to Capsule's** (`subscribe() -> watch`, `get_all_notifications() -> Vec<NotificationItem>`, `get_latest_active_notification()->Option<NotificationItem>`, `timeout: Duration`, `received_at: Instant`, `hovered: bool`). Keep in-memory history capped at 100, expose `subscribe()` for bar toast + center. Copy `references/icebar` `zbus` patterns for `Notify`, `GetCapabilities`, `ActionInvoked`.

- **Bar toast (Beskar-specific wiring):**
  `crates/beskar-shell/src/bar/view.rs:118-121` already syncs `sync_notification_toasts`; ensure:
  - `history=false` popup → bar center pill inline (not overlay) + spring `180→360` via `Animator` (Plan 01).
  - `history=true` center → `Slot::Right` scrim card `Scrollable` list (header `Badge` count + `Clear All`/`Close`).
  - Expiry: `schedule_expiry` 60s fallback when `timeout==0` else `timeout - elapsed` — copy verbatim; Beskar's old timed dismiss may be removed.
  - Inline reply: `Reply` `InputState` `max_len 250` + `pending/failed` + `oneshot` to `store.reply(id,text).await` (Capsule `module/notification.rs:211-235`) — **wire to `spawn_tokio`, not inline**.

- **Adaptation — text measurement:**
  `measure()` uses `WindowTextSystem::shape_text(text, px(size), &[TextRun{font: theme.font_family(), weight}], wrap WIDTH-32, 4)` — keep `WindowTextSystem` (GPUI) but ensure `Theme::font_family()` maps to `beskar-theme::font_family`. Actions packing `width min WIDTH-32`, `rows min 3`, `rows*28 + (rows-1)*6` — copy verbatim for `popup_height` correctness.

- **Tests:** copy `capsule/widgets/notification.rs:453-493` (`popup_reserves_wrapped_summary_actions_and_reply_space`) — headless `Theme::default()`, multi-line summary wrapping, actions wrapping up to 6 very long labels → `96.0` height.

### 3.2 Clipboard (copy Capsule 2-col gallery + worker, keep Beskar Slot::Focus)

- **Model + Worker copy:**
  ```rust
  // From references/capsule/crates/app/src/capsule/module/clipboard/model.rs
  // ClipboardModel { items: Vec<ClipboardItem{id,preview,is_image}>, snippets: Vec<Snippet{id,title,content}>, filtered: Vec<usize>, selected, tab, query }
  // fn update(items,snippets), search(query), switch(tab), navigate(delta) clamped
  // From references/capsule/crates/app/src/capsule/module/clipboard/worker.rs
  // enum Request { Active(bool), Refresh, Copy(item,generation), CopyText(text,generation), Pin(item), Remove(id), Clear }
  // fn start(service) -> (UnboundedSender<Request>, Receiver<Reply{items,snippets,pinned,images,copied,generation,finished,error}>, JoinHandle)
  // Reply carries generation-matched write_to_clipboard + Close emit + SizeChanged + scroll_to_item
  ```

- **Module copy:** `crates/app/src/capsule/module/clipboard.rs:13-312` verbatim (adapt `AppState.clipboard` → `beskar-services::clipboard::ClipboardService`, `generation` matching for auto-close on copy). Key behaviors: `open` `generation.wrapping_add(1)` + `clear search`, `select` guards `index >= filtered.len`, `request` `busy` guard + `Pin` only when `tab==History && !is_image`, `Remove` only `tab==Snippets`, `key_down` Escape clears search else Close, Enter copies, Tab switches tabs, arrows navigate `±COLUMNS` or `±1` when search empty.

- **Widget copy:** `crates/app/src/capsule/widgets/clipboard.rs:1-509` dimensions + rendering:
  - Constants `WIDTH 480 COLUMNS 2 CARD_HEIGHT 144 GRID_GAP 10 PADDING 16 HEADER 40 TABS 28 FOOTER 18 BASE_HEIGHT / MAX_HEIGHT / CARD_WIDTH` — **keep**; verify `PADDING*2+HEADER+TABS+FOOTER+GAP*3 == BASE_HEIGHT`, `MAX_HEIGHT-BASE == 2*CARD+GRID_GAP`, `CARD_WIDTH*2+GRID_GAP+PADDING*2 == WIDTH` (tests 498-508).
  - Header: `Input` `cleanable rounded_full bg surface border_color border` + prefix `search.svg` — map to `gpui_kit::Input` props.
  - Tabs: `History/Snippets` pills `accent/on_accent` when active else `surface/foreground_muted`.
  - Gallery: `id clipboard-gallery` `flex_1 min_h_0 flex_col gap GRID_GAP overflow_y_scroll track_scroll(&scroll)`, empty states `loading/no_results/empty_history/empty_snippets` via `theme.foreground_muted`.
  - Rows: `chunks(COLUMNS)` → `row gap GRID_GAP h CARD_HEIGHT`, each card `w CARD_WIDTH h CARD_HEIGHT rounded INNER_RADIUS` `border accent|border(theme)` `bg selected|surface` + `transitions bg ease_in_out` + `on_mouse_move select` + `on_click copy`.
  - Image card ` CARD_WIDTH-4 ×104 rounded preview` + footer `wallpaper.svg + preview text` vs text card `12px + file-text.svg + pin + 13/19 preview`. Snippet card `pin.svg + title + close`.
  - Footer: `error (red) | busy (working) | hint (copy_hint)` + `filtered.len()` count.

- **Service:** `arboard` + `wayland-data-control` poll, capped at `SettingsService.clipboardMaxItems` (100 default), dedup by content hash, persist optional — keep Capsule worker's dedup; just adapt `ClipboardService` API.

- **UI mapping:** `VirtualList` is **not** needed — Capsule gallery uses `ScrollHandle` + `track_scroll` + `scroll_to_item(selected/COLUMNS)` with at most `2 rows` visible (`MAX_HEIGHT` caps). If Beskar wants 8-12 visible, extend `MAX_HEIGHT` or add `VirtualList`; default keeps Capsule caps.

- **Non-blocking:** worker's `Copy` does `cx.write_to_clipboard(ClipboardItem::new_string(text))` on generation match — already main-thread but cheap; image decode via `spawn_blocking` in worker.

### 3.3 Wallpaper Selector & Palette Engine (no Capsule analog — keep Minflair flow, fix blocking)

- Selector: `PanelModule Slot::Focus` grid of thumbnails (copy `WallpaperSelectorContent.qml` layout), search `Input`, preview, Apply. Execution via `spawn_blocking` (`swww` preferred, `feh` fallback — already `wallpaper_selector/mod.rs:51-54` but must be moved off render into `beskar-services::watcher` or `wallpaper_selector` service). Add Capsule-style `generation` if needed for rapid switches.

- Palette: extract dominant HSL from wallpaper (`references/suzuha/src/theme/hsl.rs` + `references/amane`), generate `bg/bg_secondary/fg/muted/border/accent/complementary` tokens for `beskar-theme`, expose via `ThemeEngine::set_palette`. Background `hsla(240,0.16,0.08,0.95)` obsidian glass + specular top border `hsla(0,0,1.0,0.14)` like PowerMenu spec (already in plan, unchanged).

## 4. Acceptance

- [ ] `NotificationModule` size `440×popup_height` (popup) vs `440×400` (history) correct; `popup_height` wrapping 4 lines + 3 action rows + reply `84+24` matches Capsule test; `measure` + `actions_height` pure fns pass headless test.
- [ ] Bar toast: new notification briefly expands bar center pill `180→360` via `Animator`, shows inline card with `Chip` actions + `Input` reply when `inline-reply` present, auto-expires via `schedule_expiry` (60s fallback), hover `set_hovered(true)` suppresses expiry; history panel groups reverse chronological, `Badge` count + `Clear All`/`Close` work, `Slot::Right` exclusive with ControlCenter.
- [ ] Clipboard: `Focus` exclusive with Launcher/PowerMenu/Wallpaper; `480×2-col×144` gallery with `COLUMNS 2` row packing, `Search` filter via `InputState`, `Tab` switches tabs, arrows/home/end navigate, `Enter` copies + generation-matched auto-close, `Pin`/`Remove`/`Clear` dispatched via `Request` channel busy-guarded, no render-thread blocking; dimensions test passes.
- [ ] Wallpaper grid previews, `swww`/`feh` via `spawn_blocking` (not in `render`), theme HSL palette updates without restart.
- [ ] All lists use `Scrollable`/`ScrollHandle` (Capsule pattern) or `VirtualList` if extended; inputs use `gpui_kit::Input` — no hand-rolled scroll; `IconButton`/`Chip`/`Button` map to `gpui_kit`.
- [ ] D-Bus `org.freedesktop.Notifications` `NotificationStore` aligns with Capsule API; `zbus` patterns from `icebar` preserved.
- [ ] `cargo check && cargo test` green; `grep -R "Command::new"` review clean (palette `swww` via `spawn_blocking`).

## 5. Non-goals

- Dashboard/music/capture — Plan 04. Lockscreen/settings — Plan 05.
- Wallpaper HSL engine detailed tuning — keep `suzuha/amane` extraction, not expanded here.
