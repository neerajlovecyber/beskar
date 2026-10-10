use std::sync::Arc;
use beskar_compositor::detect_compositor;
use beskar_core::models::WorkspaceInfo;
use beskar_core::traits::CompositorBackend;
use beskar_services::{AudioService, BatteryService, MprisService};
use beskar_ui::BeskarBar;
use chrono::Local;
use gpui_kit::assets::AllAssets;
use gpui_kit::layer_shell::{Anchor as LayerAnchor, KeyboardInteractivity, Layer, LayerShellOptions};
use gpui_kit::*;
use tracing::info;
use tracing_subscriber::EnvFilter;

/// Height of the bar surface in logical pixels.
const BAR_HEIGHT: f32 = 48.0;
/// Top margin — the gap between the screen edge and the bar surface, creating the floating look.
const BAR_MARGIN_TOP: f32 = 6.0;

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

        // 2. Hardware Stats Poller: updates battery, volume, and MPRIS every 1.5 seconds
        cx.spawn(async move |this, cx| {
            loop {
                let _ = cx
                    .background_executor()
                    .timer(std::time::Duration::from_millis(1500))
                    .await;
                let bat = battery_svc.read_state();
                let aud = AudioService::read_state();
                let med = MprisService::read_state();

                let media = med.map(|m| {
                    (
                        m.title.unwrap_or_default(),
                        m.artist.unwrap_or_default(),
                        m.is_playing,
                    )
                });

                let res = this.update(cx, |this, cx| {
                    this.battery_percent = bat.percentage.round() as u8;
                    this.is_charging = bat.is_charging;
                    this.volume_percent = (aud.volume * 100.0).round() as u8;
                    this.is_muted = aud.is_muted;
                    this.media = media;
                    cx.notify();
                });
                if res.is_err() {
                    break;
                }
            }
        })
        .detach();

        // 3. Live Niri Compositor Event Stream
        let (tx, mut rx) = tokio::sync::mpsc::channel(64);
        let comp_listener = compositor.clone();
        futures::executor::block_on(async {
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

        div()
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
                Some(on_select_ws),
                None,
                Some(on_play_pause),
                Some(on_volume_click),
                None,
            ))
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

fn main() -> anyhow::Result<()> {
    tracing_subscriber::fmt()
        .with_env_filter(EnvFilter::from_default_env().add_directive("beskar=info".parse()?))
        .init();

    info!("Starting Beskar Shell (Pure Rust + GPUI Wayland Desktop Shell)...");

    let compositor = detect_compositor();
    info!("Active compositor backend: {:?}", compositor.kind());

    // Query initial workspace list from active Niri session
    let (initial_workspaces, active_ws) = futures::executor::block_on(async {
        match compositor.get_workspaces().await {
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
        }
    });

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
