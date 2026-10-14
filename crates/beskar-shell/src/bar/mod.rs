pub mod actions;
pub mod view;

use std::sync::Arc;
use beskar_core::models::{WindowInfo, WorkspaceInfo};
use beskar_core::traits::CompositorBackend;
use gpui_kit::layer_shell::{Anchor as LayerAnchor, KeyboardInteractivity, Layer, LayerShellOptions};
use gpui_kit::*;
use tracing::info;

pub use view::DesktopBarView;

/// Build the LayerShell window options for the bar.
pub fn bar_window_options(
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

/// Open an individual bar LayerShell window on the specified display.
#[allow(clippy::too_many_arguments)]
pub fn open_bar(
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
