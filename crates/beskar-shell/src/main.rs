use std::sync::Arc;
use beskar_compositor::detect_compositor;
use beskar_core::models::{AppItem, NotificationItem, WorkspaceInfo};
use beskar_core::traits::CompositorBackend;
use beskar_services::{AudioService, BatteryService, MprisService};
use beskar_ui::{
    BeskarBar, ControlCenterWidget, LauncherWidget, LockScreenWidget, NotificationToastWidget,
};
use chrono::Local;
use gpui_kit::assets::AllAssets;
use gpui_kit::layer_shell::{Anchor as LayerAnchor, KeyboardInteractivity, Layer, LayerShellOptions};
use gpui_kit::prelude::FluentBuilder;
use gpui_kit::*;
use tracing::info;
use tracing_subscriber::EnvFilter;

/// Height of the bar surface in logical pixels.
const BAR_HEIGHT: f32 = 48.0;
/// Top margin — the gap between the screen edge and the bar surface, creating the floating look.
const BAR_MARGIN_TOP: f32 = 6.0;

#[derive(Debug, Clone)]
enum BarAction {
    ToggleControlCenter,
    ToggleLauncher,
    ToggleLockScreen,
}

struct DesktopBarView {
    workspaces: Vec<WorkspaceInfo>,
    active_ws: u64,
    time_str: String,
    date_str: String,
    battery_percent: u8,
    is_charging: bool,
    volume_percent: u8,
    is_muted: bool,
    media: Option<(String, String, bool)>,
    island_spring: beskar_ui::SpringValue,
    tray_items: Vec<beskar_core::models::TrayItem>,
    notifications: Vec<NotificationItem>,
    apps: Vec<AppItem>,
    show_control_center: bool,
    show_launcher: bool,
    show_lock_screen: bool,
    action_tx: tokio::sync::mpsc::UnboundedSender<BarAction>,
    compositor: Arc<dyn CompositorBackend>,
}

impl DesktopBarView {
    fn new(
        workspaces: Vec<WorkspaceInfo>,
        active_ws: u64,
        compositor: Arc<dyn CompositorBackend>,
        cx: &mut Context<Self>,
    ) -> Self {
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
        let initial_target_w = if has_initial_media { 320.0 } else { 120.0 };
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

                let target_width = if media.is_some() { 320.0 } else { 120.0 };

                let res = this.update(cx, |this, cx| {
                    this.battery_percent = snap.battery.percentage.round() as u8;
                    this.is_charging = snap.battery.is_charging;
                    this.volume_percent = (snap.audio.volume * 100.0).round() as u8;
                    this.is_muted = snap.audio.is_muted;
                    this.media = media;
                    this.tray_items = snap.tray;
                    this.notifications = snap.notifications;
                    this.island_spring.set_target(target_width);
                    cx.notify();
                });
                if res.is_err() {
                    break;
                }
            }
        })
        .detach();

        // 3. 60 FPS Physics Frame Loop for fluid Island morphing
        cx.spawn(async move |this, cx| {
            loop {
                let _ = cx
                    .background_executor()
                    .timer(std::time::Duration::from_millis(16)) // ~60 FPS
                    .await;
                let res = this.update(cx, |this, cx| {
                    if !this.island_spring.is_settled() {
                        this.island_spring.step(1.0 / 60.0);
                        cx.notify();
                    }
                });
                if res.is_err() {
                    break;
                }
            }
        })
        .detach();

        // 4. UI Actions Channel (e.g. Control Center toggle)
        let (action_tx, mut action_rx) = tokio::sync::mpsc::unbounded_channel::<BarAction>();
        cx.spawn(async move |this, cx| {
            while let Some(action) = action_rx.recv().await {
                let res = this.update(cx, |this, cx| {
                    match action {
                        BarAction::ToggleControlCenter => {
                            this.show_control_center = !this.show_control_center;
                            cx.notify();
                        }
                        BarAction::ToggleLauncher => {
                            this.show_launcher = !this.show_launcher;
                            cx.notify();
                        }
                        BarAction::ToggleLockScreen => {
                            this.show_lock_screen = !this.show_lock_screen;
                            cx.notify();
                        }
                    }
                });
                if res.is_err() {
                    break;
                }
            }
        })
        .detach();

        // 5. Live Niri Compositor Event Stream
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
                        _ => {}
                    }
                });
                if res.is_err() {
                    break;
                }
            }
        })
        .detach();

        let apps = beskar_services::list_apps();

        Self {
            workspaces,
            active_ws,
            time_str,
            date_str,
            battery_percent: bat.percentage.round() as u8,
            is_charging: bat.is_charging,
            volume_percent: (aud.volume * 100.0).round() as u8,
            is_muted: aud.is_muted,
            media: initial_media,
            island_spring,
            tray_items: Vec::new(),
            notifications: Vec::new(),
            apps,
            show_control_center: false,
            show_launcher: false,
            show_lock_screen: false,
            action_tx,
            compositor,
        }
    }
}

impl Render for DesktopBarView {
    fn render(&mut self, _: &mut Window, _: &mut Context<Self>) -> impl IntoElement {
        let comp = self.compositor.clone();
        let on_select_ws = Arc::new(move |id: u64| {
            let c = comp.clone();
            std::thread::spawn(move || {
                let _ = futures::executor::block_on(async { c.focus_workspace(id).await });
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
        });

        let atx_cc = self.action_tx.clone();
        let on_control_center_click = Arc::new(move || {
            let _ = atx_cc.send(BarAction::ToggleControlCenter);
        });

        let atx_l = self.action_tx.clone();
        let on_launcher_click = Arc::new(move || {
            let _ = atx_l.send(BarAction::ToggleLauncher);
        });

        let atx_p = self.action_tx.clone();
        let on_power_click = Arc::new(move || {
            let _ = atx_p.send(BarAction::ToggleLockScreen);
        });

        let show_cc = self.show_control_center;

        div()
            .relative()
            .size_full()
            .flex()
            .items_center()
            .child(BeskarBar::live_islands(
                self.workspaces.clone(),
                Some(self.active_ws),
                &self.time_str,
                Some(self.date_str.clone()),
                self.media.clone(),
                self.volume_percent,
                self.is_muted,
                self.battery_percent,
                self.is_charging,
                Some(self.island_spring.current),
                self.tray_items.clone(),
                Some(on_select_ws),
                None,
                Some(on_play_pause),
                Some(on_volume_click),
                Some(on_volume_scroll),
                Some(on_control_center_click),
                Some(on_power_click),
                Some(on_launcher_click),
            ))
            // Quick Settings / Control Center slide-down card
            .when(show_cc, |this| {
                this.child(
                    div()
                        .absolute()
                        .top(px(BAR_HEIGHT + 8.0))
                        .right(px(12.0))
                        .child(
                            ControlCenterWidget::new(
                                self.volume_percent,
                                self.battery_percent,
                            )
                            .muted(self.is_muted)
                            .charging(self.is_charging)
                            .wifi(true, None)
                            .bluetooth(true),
                        ),
                )
            })
            // App Launcher Spotlight overlay
            .when(self.show_launcher, |this| {
                let atx_c = self.action_tx.clone();
                let atx_launch = self.action_tx.clone();
                this.child(
                    div()
                        .absolute()
                        .top(px(BAR_HEIGHT + 16.0))
                        .left_0()
                        .right_0()
                        .flex()
                        .justify_center()
                        .child(
                            LauncherWidget::new(self.apps.clone())
                                .on_launch(move |cmd| {
                                    let _ = beskar_services::launch_app(&cmd);
                                    let _ = atx_launch.send(BarAction::ToggleLauncher);
                                })
                                .on_close(move || {
                                    let _ = atx_c.send(BarAction::ToggleLauncher);
                                }),
                        ),
                )
            })
            // Lock Screen Fullscreen overlay
            .when(self.show_lock_screen, |this| {
                let atx_u = self.action_tx.clone();
                let atx_cancel = self.action_tx.clone();
                this.child(
                    div()
                        .absolute()
                        .size_full()
                        .child(
                            LockScreenWidget::new("User", &self.time_str, &self.date_str)
                                .on_unlock_attempt(move |_| {
                                    let _ = atx_u.send(BarAction::ToggleLockScreen);
                                })
                                .on_cancel(move || {
                                    let _ = atx_cancel.send(BarAction::ToggleLockScreen);
                                }),
                        ),
                )
            })
            // Notification Drop Toast stack
            .when(!self.notifications.is_empty(), |this| {
                let notifs = self.notifications.clone();
                this.child(
                    div()
                        .absolute()
                        .top(px(BAR_HEIGHT + 8.0))
                        .right(px(16.0))
                        .flex()
                        .flex_col()
                        .gap(px(8.0))
                        .children(notifs.into_iter().take(3).map(|n| {
                            NotificationToastWidget::new(n)
                                .on_dismiss(|id| {
                                    beskar_services::notifications::dismiss(id);
                                })
                                .on_invoke(|id, key| {
                                    beskar_services::notifications::invoke(id, &key);
                                })
                        })),
                )
            })
    }
}

/// Build the LayerShell window options for the bar.
fn bar_window_options(display_id: Option<DisplayId>, cx: &App) -> WindowOptions {
    let display_size = display_id
        .and_then(|id| cx.find_display(id))
        .or_else(|| cx.primary_display())
        .map(|display| display.bounds().size)
        .unwrap_or_else(|| Size::new(px(1920.), px(1080.)));

    WindowOptions {
        display_id,
        titlebar: None,
        window_bounds: Some(WindowBounds::Windowed(Bounds {
            origin: point(px(0.), px(0.)),
            size: Size::new(display_size.width, px(BAR_HEIGHT)),
        })),
        app_id: Some("beskar-bar".to_string()),
        window_background: WindowBackgroundAppearance::Transparent,
        kind: WindowKind::LayerShell(LayerShellOptions {
            namespace: "beskar-bar".to_string(),
            layer: Layer::Top,
            anchor: LayerAnchor::LEFT | LayerAnchor::RIGHT | LayerAnchor::TOP,
            exclusive_zone: Some(px(BAR_HEIGHT + BAR_MARGIN_TOP)),
            margin: Some((px(BAR_MARGIN_TOP), px(0.), px(0.), px(0.))),
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

    info!(
        "Opening Beskar Shell layer-shell bar (Active Workspace ID: {}, Total Found: {})...",
        active_ws,
        initial_workspaces.len()
    );

    let comp_for_bar = compositor.clone();

    // Run the GPUI application event loop WITH embedded AllAssets registered!
    gpui_kit::application()
        .with_assets(AllAssets)
        .run(move |cx| {
            gpui_kit::init(cx);

            let initial_workspaces = initial_workspaces;
            let active_ws = active_ws;
            let compositor = comp_for_bar.clone();

            cx.spawn(async move |cx| {
                cx.background_executor()
                    .timer(std::time::Duration::from_millis(100))
                    .await;

                cx.update(|cx| {
                    let displays = cx.displays();
                    if displays.is_empty() {
                        info!("No displays found, opening bar on default display");
                        open_bar(None, initial_workspaces, active_ws, compositor.clone(), cx);
                    } else {
                        for d in displays {
                            info!("Opening bar on display {:?}", d.id());
                            open_bar(
                                Some(d.id()),
                                initial_workspaces.clone(),
                                active_ws,
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

fn open_bar(
    display_id: Option<DisplayId>,
    workspaces: Vec<WorkspaceInfo>,
    active_ws: u64,
    compositor: Arc<dyn CompositorBackend>,
    cx: &mut App,
) {
    let options = bar_window_options(display_id, cx);
    match cx.open_window(options, move |_window, cx| {
        cx.new(|cx| DesktopBarView::new(workspaces, active_ws, compositor, cx))
    }) {
        Ok(_) => info!("Beskar bar opened successfully"),
        Err(e) => tracing::warn!("Failed to open bar window: {}", e),
    }
}
