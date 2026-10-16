pub mod actions;
pub mod view;

use std::collections::HashMap;
use std::sync::{Arc, Mutex};
use beskar_core::models::{WindowInfo, WorkspaceInfo};
use beskar_core::traits::CompositorBackend;
use gpui_kit::layer_shell::{Anchor as LayerAnchor, KeyboardInteractivity, Layer, LayerShellOptions};
use gpui_kit::*;
use tracing::info;

pub use view::DesktopBarView;

static WINDOW_DISPLAYS: Mutex<Option<HashMap<AnyWindowHandle, DisplayId>>> = Mutex::new(None);

/// Record which DisplayId a bar window belongs to.
pub fn record_window_display(handle: AnyWindowHandle, display_id: Option<DisplayId>) {
    if let Some(display_id) = display_id {
        if let Ok(mut guard) = WINDOW_DISPLAYS.lock() {
            guard
                .get_or_insert_with(HashMap::new)
                .insert(handle, display_id);
        }
    }
}

/// Look up the display a bar window was opened on.
pub fn display_id_for_window(window: &Window) -> Option<DisplayId> {
    WINDOW_DISPLAYS
        .lock()
        .ok()?
        .as_ref()?
        .get(&window.window_handle())
        .copied()
}

static CACHED_OUTPUTS: Mutex<Option<Vec<beskar_core::models::OutputInfo>>> = Mutex::new(None);

/// Update cached compositor outputs for monitor resolution and fractional scale lookups.
pub fn update_cached_outputs(outputs: Vec<beskar_core::models::OutputInfo>) {
    if let Ok(mut guard) = CACHED_OUTPUTS.lock() {
        *guard = Some(outputs);
    }
}

/// Logical (scale-corrected) size of the monitor backing a gpui display.
///
/// Prefer this over `PlatformDisplay::bounds()` for anything that has to
/// match the real screen extent. gpui derives its display bounds from the
/// integer `wl_output.scale`, and Wayland's core output protocol carries no
/// fractional scale - a screen running at 1.5 advertises 2, so gpui reports
/// two thirds of the true logical size.
pub fn logical_display_size(display_id: Option<DisplayId>, cx: &App) -> Size<Pixels> {
    if let Some(display) = display_id.and_then(|id| cx.find_display(id)) {
        if let Ok(display_uuid) = display.uuid() {
            if let Ok(guard) = CACHED_OUTPUTS.lock() {
                if let Some(ref outputs) = *guard {
                    let matched = outputs.iter().find(|out| {
                        uuid::Uuid::new_v5(&uuid::Uuid::NAMESPACE_DNS, out.name.as_bytes())
                            == display_uuid
                    });
                    if let Some(out) = matched {
                        if out.scale > 0.0 && out.width > 0 && out.height > 0 {
                            return Size::new(
                                px(out.width as f32 / out.scale as f32),
                                px(out.height as f32 / out.scale as f32),
                            );
                        }
                    }
                }
            }
        }
        return display.bounds().size;
    }

    cx.primary_display()
        .map(|d| d.bounds().size)
        .unwrap_or_else(|| Size::new(px(1920.0), px(1080.0)))
}

/// Build the LayerShell window options for the bar with fractional-scale pixel snapping.
pub fn bar_window_options(
    display_id: Option<DisplayId>,
    bar_height: f32,
    bar_margin: f32,
    bar_position: beskar_core::config::BarPosition,
    cx: &App,
) -> WindowOptions {
    let display_size = logical_display_size(display_id, cx);

    // Fractional scale pixel snapping: ensure integer pixels to prevent subpixel artifacts
    let snapped_width = px(display_size.width.as_f32().floor());
    let snapped_height = px(bar_height.round());
    let snapped_margin = px(bar_margin.round());

    let (anchor, margin) = match bar_position {
        beskar_core::config::BarPosition::Top => (
            LayerAnchor::LEFT | LayerAnchor::RIGHT | LayerAnchor::TOP,
            Some((snapped_margin, px(0.), px(0.), px(0.))),
        ),
        beskar_core::config::BarPosition::Bottom => (
            LayerAnchor::LEFT | LayerAnchor::RIGHT | LayerAnchor::BOTTOM,
            Some((px(0.), px(0.), snapped_margin, px(0.))),
        ),
    };

    WindowOptions {
        display_id,
        titlebar: None,
        window_bounds: Some(WindowBounds::Windowed(Bounds {
            origin: point(px(0.), px(0.)),
            size: Size::new(snapped_width, snapped_height),
        })),
        app_id: Some("beskar-bar".to_string()),
        window_background: WindowBackgroundAppearance::Transparent,
        kind: WindowKind::LayerShell(LayerShellOptions {
            namespace: "beskar-bar".to_string(),
            layer: Layer::Top,
            anchor,
            exclusive_zone: Some(snapped_height + snapped_margin),
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
) -> bool {
    let options = bar_window_options(display_id, bar_height, bar_margin_top, bar_position, cx);
    match cx.open_window(options, move |window, cx| {
        record_window_display(window.window_handle(), display_id);
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
        Ok(_) => {
            info!("Beskar bar opened successfully on display {:?}", display_id);
            true
        }
        Err(e) => {
            tracing::warn!("Failed to open bar window on display {:?}: {}", display_id, e);
            false
        }
    }
}

/// Open bar windows across all enumerated displays.
#[allow(clippy::too_many_arguments)]
pub fn open_all_bars(
    workspaces: Vec<WorkspaceInfo>,
    active_ws: u64,
    initial_window: Option<WindowInfo>,
    is_convex: bool,
    bar_height: f32,
    bar_margin_top: f32,
    bar_position: beskar_core::config::BarPosition,
    compositor: Arc<dyn CompositorBackend>,
    cx: &mut App,
) -> usize {
    let mut opened = 0usize;
    let displays = cx.displays();
    if displays.is_empty() {
        info!("No displays found, opening bar on default display");
        if open_bar(
            None,
            workspaces,
            active_ws,
            initial_window,
            is_convex,
            bar_height,
            bar_margin_top,
            bar_position,
            compositor,
            cx,
        ) {
            opened += 1;
        }
    } else {
        info!("Opening bar on {} displays", displays.len());
        for d in displays {
            info!("Opening bar on display {:?}", d.id());
            if open_bar(
                Some(d.id()),
                workspaces.clone(),
                active_ws,
                initial_window.clone(),
                is_convex,
                bar_height,
                bar_margin_top,
                bar_position,
                compositor.clone(),
                cx,
            ) {
                opened += 1;
            }
        }
    }
    opened
}

/// Recreate all bar windows upon display hotplug or configuration change.
#[allow(clippy::too_many_arguments)]
pub fn reload_bars(
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
    let old_windows: Vec<_> = cx
        .windows()
        .into_iter()
        .filter(|h| h.downcast::<DesktopBarView>().is_some())
        .collect();

    let opened = open_all_bars(
        workspaces,
        active_ws,
        initial_window,
        is_convex,
        bar_height,
        bar_margin_top,
        bar_position,
        compositor,
        cx,
    );

    if opened > 0 {
        for handle in old_windows {
            let _ = handle.update(cx, |_, window, _| window.remove_window());
        }
    }
}

#[cfg(test)]
mod tests {
    #[core::prelude::v1::test]
    fn test_pixel_snapping_rounding() {
        let raw_width = 1920.7f32;
        let raw_height = 36.4f32;
        let raw_margin = 8.6f32;

        let snapped_width = raw_width.floor();
        let snapped_height = raw_height.round();
        let snapped_margin = raw_margin.round();

        assert_eq!(snapped_width, 1920.0);
        assert_eq!(snapped_height, 36.0);
        assert_eq!(snapped_margin, 9.0);
    }

    #[core::prelude::v1::test]
    fn test_fractional_scale_calculation() {
        for (width, scale, expected_logical) in [
            (1920, 1.0, 1920.0),
            (2560, 1.25, 2048.0),
            (3840, 1.5, 2560.0),
            (3840, 2.0, 1920.0),
        ] {
            let logical = width as f32 / scale as f32;
            assert_eq!(logical, expected_logical);
        }
    }
}
