#![recursion_limit = "512"]

pub mod modules;
pub mod panel_host;

use std::sync::Arc;
use beskar_compositor::detect_compositor;
use beskar_core::models::{NotificationItem, WindowInfo, WorkspaceInfo};

use beskar_core::traits::CompositorBackend;
use beskar_services::{AudioService, BatteryService, MprisService};
use beskar_ui::BeskarBar;
use chrono::Local;
use gpui_kit::assets::AllAssets;
use gpui_kit::layer_shell::{Anchor as LayerAnchor, KeyboardInteractivity, Layer, LayerShellOptions};
use gpui_kit::*;
use tracing::info;
use tracing_subscriber::EnvFilter;

#[allow(dead_code, clippy::enum_variant_names)]
enum BarAction {
    ToggleControlCenter,
    ToggleLauncher,
    TogglePowerMenu,
    ToggleSettings,
    ToggleLockScreen,
    ToggleClipboard,
    ToggleDashboard,
    ToggleMusic,
    ToggleNotificationCenter,
    ToggleScreenCapture,
    ToggleWallpaperSelector,
}

struct DesktopBarView {
    workspaces: Vec<WorkspaceInfo>,
    active_ws: u64,
    active_window: Option<WindowInfo>,
    time_str: String,
    date_str: String,
    battery_percent: u8,
    is_charging: bool,
    volume_percent: u8,
    is_muted: bool,
    media: Option<(String, String, bool)>,
    cava_bands: Option<[u8; 4]>,
    island_spring: beskar_ui::SpringValue,
    tray_items: Vec<beskar_core::models::TrayItem>,
    notifications: Vec<NotificationItem>,
    action_tx: tokio::sync::mpsc::UnboundedSender<BarAction>,
    compositor: Arc<dyn CompositorBackend>,
    is_convex: bool,
    config: beskar_core::config::ShellConfig,
}

impl DesktopBarView {
    fn new(
        workspaces: Vec<WorkspaceInfo>,
        active_ws: u64,
        active_window: Option<WindowInfo>,
        is_convex: bool,
        compositor: Arc<dyn CompositorBackend>,
        cx: &mut Context<Self>,
    ) -> Self {
        let initial_cfg = beskar_core::config::ShellConfig::load();
        let now = Local::now();
        let time_str = now.format("%-I:%M %p").to_string();
        let date_str = now.format("%a %b %-d").to_string();

        let battery_svc = BatteryService::new();
        let bat = battery_svc.read_state();
        let aud = AudioService::read_state();
        let med = MprisService::read_state();

        let initial_media = med.map(|m| {
            (
                m.title.unwrap_or_default(),
                m.artist.unwrap_or_default(),
                m.is_playing,
            )
        });

        // 1. Live Clock Timer: updates every 1 second
        cx.spawn(async move |this, cx| {
            loop {
                let _ = cx
                    .background_executor()
                    .timer(std::time::Duration::from_secs(1))
                    .await;
                let now = Local::now();
                let time = now.format("%-I:%M %p").to_string();
                let date = now.format("%a %b %-d").to_string();
                let res = this.update(cx, |this, cx| {
                    this.time_str = time;
                    this.date_str = date;
                    cx.notify();
                });
                if res.is_err() {
                    break;
                }
            }
        })
        .detach();

        let has_initial_media = initial_media.is_some();
        let initial_target_w = if has_initial_media { 320.0 } else { 180.0 };
        let island_spring = beskar_ui::SpringValue::new(initial_target_w, beskar_ui::SpringConfig::spatial());

        // 2. Reactive SystemHub: instant updates for audio, battery, and media
        let hub = Arc::new(beskar_services::SystemHub::new());
        let hub_clone = hub.clone();
        tokio::spawn(async move {
            let _ = hub_clone.start().await;
        });

        let mut sys_rx = hub.subscribe();
        cx.spawn(async move |this, cx| {
            while let Ok(snap) = sys_rx.recv().await {
                let media = snap.media.map(|m| {
                    (
                        m.title.unwrap_or_default(),
                        m.artist.unwrap_or_default(),
                        m.is_playing,
                    )
                });

                let active_notif = snap.notifications.first().map(|n| (n.summary.clone(), n.body.clone()));
                let target_width = if active_notif.is_some() {
                    360.0
                } else if media.is_some() {
                    320.0
                } else {
                    180.0
                };

                let res = this.update(cx, |this, cx| {
                    this.battery_percent = snap.battery.percentage.round() as u8;
                    this.is_charging = snap.battery.is_charging;
                    this.volume_percent = (snap.audio.volume * 100.0).round() as u8;
                    this.is_muted = snap.audio.is_muted;
                    this.media = media;
                    this.tray_items = snap.tray;
                    this.notifications = snap.notifications.clone();
                    this.island_spring.set_target(target_width);
                    modules::sync_notification_toasts(snap.notifications, cx);
                    cx.notify();
                });
                if res.is_err() {
                    break;
                }
            }
        })
        .detach();

        // 3. Adaptive Physics Frame Loop for fluid Island morphing
        cx.spawn(async move |this, cx| {
            loop {
                let mut is_animating = false;
                let res = this.update(cx, |this, cx| {
                    if !this.island_spring.is_settled() {
                        this.island_spring.step(1.0 / 60.0);
                        is_animating = true;
                        cx.notify();
                    }
                });
                if res.is_err() {
                    break;
                }

                let sleep_duration = if is_animating {
                    std::time::Duration::from_millis(16) // 60 FPS during motion
                } else {
                    std::time::Duration::from_millis(300) // Deep idle low-power sleep when settled
                };

                let _ = cx.background_executor().timer(sleep_duration).await;
            }
        })
        .detach();

        // 4. UI Actions Channel (e.g. Control Center toggle)
        let (action_tx, mut action_rx) = tokio::sync::mpsc::unbounded_channel::<BarAction>();
        cx.spawn(async move |this, cx| {
            while let Some(action) = action_rx.recv().await {
                let res = this.update(cx, |_this, cx| {
                    match action {
                        BarAction::ToggleControlCenter => {
                            modules::toggle_control_center(cx);
                        }
                        BarAction::ToggleLauncher => {
                            modules::toggle_launcher(cx);
                        }
                        BarAction::TogglePowerMenu => {
                            modules::toggle_power_menu(cx);
                        }
                        BarAction::ToggleSettings => {
                            modules::toggle_settings(cx);
                        }
                        BarAction::ToggleLockScreen => {
                            modules::toggle_lockscreen(cx);
                        }
                        BarAction::ToggleClipboard => {
                            modules::toggle_clipboard(cx);
                        }
                        BarAction::ToggleDashboard => {
                            modules::toggle_dashboard(cx);
                        }
                        BarAction::ToggleMusic => {
                            modules::toggle_music(cx);
                        }
                        BarAction::ToggleNotificationCenter => {
                            modules::toggle_notification_center(cx);
                        }
                        BarAction::ToggleScreenCapture => {
                            modules::toggle_screencapture(cx);
                        }
                        BarAction::ToggleWallpaperSelector => {
                            modules::toggle_wallpaper_selector(cx);
                        }
                    }
                });
                if res.is_err() {
                    break;
                }
            }
        })
        .detach();

        // 5. CAVA spectrum audio equalizer loop (4 bands for Dynamic Center island)
        cx.spawn(async move |this, cx| {
            let mut tick: u32 = 0;
            loop {
                let mut is_playing = false;
                let _ = this.update(cx, |this, _| {
                    is_playing = this.media.as_ref().is_some_and(|m| m.2);
                });

                let sleep_ms = if is_playing { 60 } else { 350 };
                tokio::time::sleep(tokio::time::Duration::from_millis(sleep_ms)).await;

                if is_playing {
                    tick = tick.wrapping_add(1);
                }

                let res = this.update(cx, |this, cx| {
                    if this.media.as_ref().is_some_and(|m| m.2) {
                        let b0 = (((tick as f32 * 0.20).sin().abs() * 70.0) + 20.0) as u8;
                        let b1 = (((tick as f32 * 0.28).cos().abs() * 80.0) + 15.0) as u8;
                        let b2 = (((tick as f32 * 0.35).sin().abs() * 90.0) + 25.0) as u8;
                        let b3 = (((tick as f32 * 0.22).cos().abs() * 60.0) + 10.0) as u8;
                        this.cava_bands = Some([b0, b1, b2, b3]);
                        cx.notify();
                    } else if this.cava_bands.is_some() {
                        this.cava_bands = None;
                        cx.notify();
                    }
                });
                if res.is_err() {
                    break;
                }
            }
        })
        .detach();

        // 5. Systemd logind Session Lock Listener
        let atx_lock = action_tx.clone();
        let (lock_tx, mut lock_rx) = tokio::sync::mpsc::unbounded_channel::<()>();
        beskar_services::listen_logind_lock(lock_tx);
        cx.spawn(async move |_this, _cx| {
            while let Some(()) = lock_rx.recv().await {
                let _ = atx_lock.send(BarAction::ToggleLockScreen);
            }
        })
        .detach();

        // 6. Live Niri Compositor Event Stream
        let (tx, mut rx) = tokio::sync::mpsc::channel(64);
        let comp_listener = compositor.clone();
        tokio::spawn(async move {
            let _ = comp_listener.start_listener(tx).await;
        });

        cx.spawn(async move |this, cx| {
            while let Some(event) = rx.recv().await {
                let res = this.update(cx, |this, cx| {
                    match event {
                        beskar_core::events::CompositorEvent::WorkspacesChanged(workspaces) => {
                            if let Some(active) =
                                workspaces.iter().find(|w| w.is_focused || w.is_active)
                            {
                                this.active_ws = active.id;
                            }
                            this.workspaces = workspaces;
                            cx.notify();
                        }
                        beskar_core::events::CompositorEvent::WorkspaceFocused(id) => {
                            this.active_ws = id;
                            cx.notify();
                        }
                        beskar_core::events::CompositorEvent::WindowFocused(active_win) => {
                            if this.active_window != active_win {
                                this.active_window = active_win;
                                cx.notify();
                            }
                        }
                        beskar_core::events::CompositorEvent::WindowsChanged(windows) => {
                            let focused = windows.iter().find(|w| w.is_focused).cloned();
                            if this.active_window != focused {
                                this.active_window = focused;
                                cx.notify();
                            }
                        }
                        _ => {}
                    }
                });
                if res.is_err() {
                    break;
                }
            }
        })
        .detach();

        // 7. Reactive Config Change Listener (Live Theme & Bar Style Switching)
        let mut cfg_rx = beskar_core::config::subscribe_config();
        cx.spawn(async move |this, cx| {
            while let Ok(cfg) = cfg_rx.recv().await {
                beskar_theme::ThemeEngine::set_preset(match cfg.theme_preset {
                    beskar_core::config::ThemePresetConfig::ObsidianGlass => beskar_theme::ThemePreset::Obsidian,
                    beskar_core::config::ThemePresetConfig::CatppuccinMocha => beskar_theme::ThemePreset::CatppuccinMocha,
                    beskar_core::config::ThemePresetConfig::GruvboxDark => beskar_theme::ThemePreset::GruvboxDark,
                    beskar_core::config::ThemePresetConfig::WallpaperAuto => beskar_theme::ThemePreset::Wallpaper,
                });

                let is_convex = cfg.bar_style == beskar_core::config::BarStyleConfig::Convex;
                let res = this.update(cx, |this, cx| {
                    this.is_convex = is_convex;
                    this.config = cfg;
                    cx.notify();
                });
                if res.is_err() {
                    break;
                }
            }
        })
        .detach();

        Self {
            workspaces,
            active_ws,
            active_window,
            time_str,
            date_str,
            battery_percent: bat.percentage.round() as u8,
            is_charging: bat.is_charging,
            volume_percent: (aud.volume * 100.0).round() as u8,
            is_muted: aud.is_muted,
            media: initial_media,
            cava_bands: None,
            island_spring,
            tray_items: Vec::new(),
            notifications: Vec::new(),
            action_tx,
            compositor,
            is_convex,
            config: initial_cfg,
        }
    }
}

impl Render for DesktopBarView {
    fn render(&mut self, _: &mut Window, _: &mut Context<Self>) -> impl IntoElement {
        let comp = self.compositor.clone();
        let on_select_ws = Arc::new(move |id: u64| {
            let c = comp.clone();
            tokio::spawn(async move {
                let _ = c.focus_workspace(id).await;
            });
        });

        let comp_scroll = self.compositor.clone();
        let on_scroll_ws = Arc::new(move |dir: i32| {
            let c = comp_scroll.clone();
            tokio::spawn(async move {
                let _ = c.scroll_workspace(dir).await;
            });
        });

        let on_play_pause = Arc::new(|| {
            MprisService::play_pause();
        });

        let on_volume_click = Arc::new(|| {
            AudioService::toggle_mute();
        });

        let on_volume_scroll = Arc::new(|delta: i32| {
            beskar_services::AudioService::set_volume(delta);
            beskar_services::SoundService::play_volume_change();
        });

        let atx_cc = self.action_tx.clone();
        let on_control_center_click = Arc::new(move || {
            let _ = atx_cc.send(BarAction::ToggleControlCenter);
        });

        let atx_notif = self.action_tx.clone();
        let on_clock_click = Arc::new(move || {
            let _ = atx_notif.send(BarAction::ToggleNotificationCenter);
        });

        let atx_music = self.action_tx.clone();
        let on_music_click = Arc::new(move || {
            let _ = atx_music.send(BarAction::ToggleMusic);
        });

        let atx_dash = self.action_tx.clone();
        let on_dashboard_click = Arc::new(move || {
            let _ = atx_dash.send(BarAction::ToggleDashboard);
        });

        let atx_cap = self.action_tx.clone();
        let on_capture_click = Arc::new(move || {
            let _ = atx_cap.send(BarAction::ToggleScreenCapture);
        });

        let atx_wall = self.action_tx.clone();
        let on_wallpaper_click = Arc::new(move || {
            let _ = atx_wall.send(BarAction::ToggleWallpaperSelector);
        });

        let atx_l = self.action_tx.clone();
        let on_launcher_click = Arc::new(move || {
            let _ = atx_l.send(BarAction::ToggleLauncher);
        });

        let atx_p = self.action_tx.clone();
        let on_power_click = Arc::new(move || {
            let _ = atx_p.send(BarAction::TogglePowerMenu);
        });

        let on_tray_click = Arc::new(|id: String| {
            tokio::task::spawn_blocking(move || {
                let _ = beskar_services::tray::command(
                    "tray.activate",
                    &[beskar_services::sysvalue::SysValue::Text(id)],
                );
            });
        });

        let on_tray_menu = Arc::new(|id: String| {
            tokio::task::spawn_blocking(move || {
                let _ = beskar_services::tray::command(
                    "tray.context",
                    &[beskar_services::sysvalue::SysValue::Text(id)],
                );
            });
        });

        let comp_close = self.compositor.clone();
        let active_win_id = self.active_window.as_ref().map(|w| w.id);
        let on_window_close = Arc::new(move || {
            if let Some(id) = active_win_id {
                let c = comp_close.clone();
                tokio::spawn(async move {
                    let _ = c.close_window(id).await;
                });
            } else {
                tokio::task::spawn_blocking(|| {
                    let _ = std::process::Command::new("niri")
                        .args(["msg", "action", "close-window"])
                        .spawn();
                });
            }
        });

        let on_window_click = Arc::new(|| {
            tokio::task::spawn_blocking(|| {
                let _ = std::process::Command::new("niri")
                    .args(["msg", "action", "fullscreen-window"])
                    .spawn();
            });
        });

        let active_notif = self.notifications.first().map(|n| (n.summary.clone(), n.body.clone()));
        let state = beskar_ui::BarState {
            is_convex: self.is_convex,
            workspaces: self.workspaces.clone(),
            active_ws: Some(self.active_ws),
            active_window: self.active_window.clone(),
            time_str: self.time_str.clone(),
            date_str: Some(self.date_str.clone()),
            media: self.media.clone(),
            notification: active_notif,
            volume_percent: self.volume_percent,
            is_muted: self.is_muted,
            battery_percent: self.battery_percent,
            is_charging: self.is_charging,
            animated_center_width: Some(self.island_spring.current),
            cava_bands: self.cava_bands,
            tray_items: self.tray_items.clone(),
            modules_left: Some(self.config.modules_left.clone()),
            modules_center: Some(self.config.modules_center.clone()),
            modules_right: Some(self.config.modules_right.clone()),
        };
        let actions = beskar_ui::BarActions {
            on_select_ws: Some(on_select_ws),
            on_scroll_ws: Some(on_scroll_ws),
            on_play_pause: Some(on_play_pause),
            on_volume_click: Some(on_volume_click),
            on_volume_scroll: Some(on_volume_scroll),
            on_control_center_click: Some(on_control_center_click),
            on_power_click: Some(on_power_click),
            on_launcher_click: Some(on_launcher_click),
            on_clock_click: Some(on_clock_click),
            on_dashboard_click: Some(on_dashboard_click),
            on_music_click: Some(on_music_click),
            on_capture_click: Some(on_capture_click),
            on_wallpaper_click: Some(on_wallpaper_click),
            on_tray_click: Some(on_tray_click),
            on_tray_menu: Some(on_tray_menu),
            on_window_click: Some(on_window_click),
            on_window_close: Some(on_window_close),
        };

        div()
            .relative()
            .size_full()
            .flex()
            .items_center()
            .child(BeskarBar::from_state(state, actions))
    }
}

/// Build the LayerShell window options for the bar.
fn bar_window_options(
    display_id: Option<DisplayId>,
    bar_height: f32,
    bar_margin: f32,
    bar_position: beskar_core::config::BarPosition,
    cx: &App,
) -> WindowOptions {
    let display_size = display_id
        .and_then(|id| cx.find_display(id))
        .or_else(|| cx.primary_display())
        .map(|display| display.bounds().size)
        .unwrap_or_else(|| Size::new(px(1920.), px(1080.)));

    let (anchor, margin) = match bar_position {
        beskar_core::config::BarPosition::Top => (
            LayerAnchor::LEFT | LayerAnchor::RIGHT | LayerAnchor::TOP,
            Some((px(bar_margin), px(0.), px(0.), px(0.))),
        ),
        beskar_core::config::BarPosition::Bottom => (
            LayerAnchor::LEFT | LayerAnchor::RIGHT | LayerAnchor::BOTTOM,
            Some((px(0.), px(0.), px(bar_margin), px(0.))),
        ),
    };

    WindowOptions {
        display_id,
        titlebar: None,
        window_bounds: Some(WindowBounds::Windowed(Bounds {
            origin: point(px(0.), px(0.)),
            size: Size::new(display_size.width, px(bar_height)),
        })),
        app_id: Some("beskar-bar".to_string()),
        window_background: WindowBackgroundAppearance::Transparent,
        kind: WindowKind::LayerShell(LayerShellOptions {
            namespace: "beskar-bar".to_string(),
            layer: Layer::Top,
            anchor,
            exclusive_zone: Some(px(bar_height + bar_margin)),
            margin,
            keyboard_interactivity: KeyboardInteractivity::None,
            ..Default::default()
        }),
        ..Default::default()
    }
}

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    tracing_subscriber::fmt()
        .with_env_filter(EnvFilter::from_default_env().add_directive("beskar=info".parse()?))
        .init();

    info!("Starting Beskar Shell (Pure Rust + GPUI Wayland Desktop Shell)...");

    let compositor = detect_compositor();
    info!("Active compositor backend: {:?}", compositor.kind());

    // Query initial workspace list from active Niri session
    let (initial_workspaces, active_ws) = match compositor.get_workspaces().await {
        Ok(workspaces) => {
            let active = workspaces
                .iter()
                .find(|w| w.is_focused || w.is_active)
                .map(|w| w.id)
                .unwrap_or(1);
            (workspaces, active)
        }
        Err(e) => {
            info!(
                "Could not query compositor workspaces: {}. Using defaults.",
                e
            );
            (Vec::new(), 1)
        }
    };

    let initial_window = match compositor.get_windows().await {
        Ok(windows) => windows.into_iter().find(|w| w.is_focused),
        Err(_) => None,
    };

    info!(
        "Opening Beskar Shell layer-shell bar (Active Workspace ID: {}, Total Found: {})...",
        active_ws,
        initial_workspaces.len()
    );

    let comp_for_bar = compositor.clone();

    // Load persisted ShellConfig and apply preset immediately
    let cfg = beskar_core::config::ShellConfig::load();
    beskar_theme::ThemeEngine::set_preset(match cfg.theme_preset {
        beskar_core::config::ThemePresetConfig::ObsidianGlass => beskar_theme::ThemePreset::Obsidian,
        beskar_core::config::ThemePresetConfig::CatppuccinMocha => beskar_theme::ThemePreset::CatppuccinMocha,
        beskar_core::config::ThemePresetConfig::GruvboxDark => beskar_theme::ThemePreset::GruvboxDark,
        beskar_core::config::ThemePresetConfig::WallpaperAuto => beskar_theme::ThemePreset::Wallpaper,
    });

    let is_convex = cfg.bar_style == beskar_core::config::BarStyleConfig::Convex;
    let bar_position = cfg.bar_position;
    let bar_height = cfg.bar_height.max(28.0);
    let bar_margin_top = if is_convex { 0.0 } else { 8.0 };

    // Run the GPUI application event loop WITH embedded AllAssets registered!
    gpui_kit::application()
        .with_assets(AllAssets)
        .run(move |cx| {
            gpui_kit::init(cx);
            gpui_kit::component::Theme::change(gpui_kit::component::ThemeMode::Dark, None, cx);
            modules::register_all_modules();

            let initial_workspaces = initial_workspaces;
            let active_ws = active_ws;
            let initial_window = initial_window;
            let compositor = comp_for_bar.clone();

            cx.spawn(async move |cx| {
                cx.background_executor()
                    .timer(std::time::Duration::from_millis(100))
                    .await;

                cx.update(|cx| {
                    let displays = cx.displays();
                    if displays.is_empty() {
                        info!("No displays found, opening bar on default display");
                        open_bar(
                            None,
                            initial_workspaces,
                            active_ws,
                            initial_window,
                            is_convex,
                            bar_height,
                            bar_margin_top,
                            bar_position,
                            compositor.clone(),
                            cx,
                        );
                    } else {
                        for d in displays {
                            info!("Opening bar on display {:?}", d.id());
                            open_bar(
                                Some(d.id()),
                                initial_workspaces.clone(),
                                active_ws,
                                initial_window.clone(),
                                is_convex,
                                bar_height,
                                bar_margin_top,
                                bar_position,
                                compositor.clone(),
                                cx,
                            );
                        }
                    }
                })
            })
            .detach();
        });

    Ok(())
}

#[allow(clippy::too_many_arguments)]
fn open_bar(
    display_id: Option<DisplayId>,
    workspaces: Vec<WorkspaceInfo>,
    active_ws: u64,
    initial_window: Option<WindowInfo>,
    is_convex: bool,
    bar_height: f32,
    bar_margin_top: f32,
    bar_position: beskar_core::config::BarPosition,
    compositor: Arc<dyn CompositorBackend>,
    cx: &mut App,
) {
    let options = bar_window_options(display_id, bar_height, bar_margin_top, bar_position, cx);
    match cx.open_window(options, move |_window, cx| {
        cx.new(|cx| {
            DesktopBarView::new(
                workspaces,
                active_ws,
                initial_window,
                is_convex,
                compositor,
                cx,
            )
        })
    }) {
        Ok(_) => info!("Beskar bar opened successfully"),
        Err(e) => tracing::warn!("Failed to open bar window: {}", e),
    }
}
