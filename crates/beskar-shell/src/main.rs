#![recursion_limit = "1024"]

pub mod bar;
pub mod modules;
pub mod panel_host;

use beskar_compositor::detect_compositor;
use gpui_kit::assets::AllAssets;
use tracing::info;
use tracing_subscriber::EnvFilter;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    tracing_subscriber::fmt()
        .with_env_filter(EnvFilter::from_default_env().add_directive("beskar=info".parse()?))
        .init();

    info!("Starting Beskar Shell (Pure Rust + GPUI Wayland Desktop Shell)...");

    let compositor = detect_compositor();
    info!("Active compositor backend: {:?}", compositor.kind());

    // Query initial workspace list from active compositor session
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

                let _ = cx.update(|cx| {
                    bar::open_all_bars(
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
                });

                // Display hotplug reconciliation loop: detects connect/disconnect events
                let comp_hotplug = compositor;
                let mut last_display_ids = cx.update(|cx| {
                    cx.displays().into_iter().map(|d| d.id()).collect::<Vec<_>>()
                });

                loop {
                    cx.background_executor()
                        .timer(std::time::Duration::from_millis(2000))
                        .await;

                    let current_ids = cx.update(|cx| {
                        cx.displays().into_iter().map(|d| d.id()).collect::<Vec<_>>()
                    });

                    if current_ids != last_display_ids {
                        info!(
                            "Display hotplug detected (previously {:?}, now {:?}). Reconciling bars...",
                            last_display_ids, current_ids
                        );
                        last_display_ids = current_ids;
                        let comp = comp_hotplug.clone();
                        let _ = cx.update(move |cx| {
                            let cfg = beskar_core::config::ShellConfig::load();
                            let is_convex = cfg.bar_style == beskar_core::config::BarStyleConfig::Convex;
                            let bar_position = cfg.bar_position;
                            let bar_height = cfg.bar_height.max(28.0);
                            let bar_margin_top = if is_convex { 0.0 } else { 8.0 };

                            bar::reload_bars(
                                Vec::new(),
                                1,
                                None,
                                is_convex,
                                bar_height,
                                bar_margin_top,
                                bar_position,
                                comp,
                                cx,
                            );
                        });
                    }
                }
            })
            .detach();
        });

    Ok(())
}
