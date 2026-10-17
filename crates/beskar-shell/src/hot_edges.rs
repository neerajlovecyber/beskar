//! Wayland Hot-Edges Engine
//! Spawns thin transparent edge sensor strips on LEFT, RIGHT, and BOTTOM display edges
//! to detect cursor approach and reveal edge-docked drawers with debounce dwell time.

use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Mutex;
use std::time::Duration;
use gpui_kit::layer_shell::{Anchor as LayerAnchor, KeyboardInteractivity, Layer, LayerShellOptions};
use gpui_kit::prelude::*;
use gpui_kit::*;
use tracing::info;

use crate::modules::control_center::ControlCenterView;
use crate::modules::dashboard::DashboardView;
use crate::modules::launcher::LauncherView;
use crate::panel_host::PanelHost;

static HOT_EDGES_INITIALIZED: AtomicBool = AtomicBool::new(false);
static SENSOR_HANDLES: Mutex<Vec<AnyWindowHandle>> = Mutex::new(Vec::new());

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum HotEdgePosition {
    Left,
    Right,
    Bottom,
}

pub struct HotEdgeSensorView {
    position: HotEdgePosition,
    dwell_task: Option<Task<()>>,
}

impl HotEdgeSensorView {
    pub fn new(position: HotEdgePosition) -> Self {
        Self {
            position,
            dwell_task: None,
        }
    }

    fn on_hover_changed(&mut self, hovered: bool, cx: &mut Context<Self>) {
        if hovered {
            let pos = self.position;
            // 120ms debounce dwell prevents accidental misfires during rapid cursor movements
            self.dwell_task = Some(cx.spawn(async move |_this, cx| {
                cx.background_executor().timer(Duration::from_millis(120)).await;
                let _ = cx.update(|cx| {
                    match pos {
                        HotEdgePosition::Left => {
                            PanelHost::open::<DashboardView>(cx);
                        }
                        HotEdgePosition::Right => {
                            PanelHost::open::<ControlCenterView>(cx);
                        }
                        HotEdgePosition::Bottom => {
                            PanelHost::open::<LauncherView>(cx);
                        }
                    }
                });
            }));
        } else {
            self.dwell_task = None;
        }
    }
}

impl Render for HotEdgeSensorView {
    fn render(&mut self, _window: &mut Window, cx: &mut Context<Self>) -> impl IntoElement {
        let id_str = match self.position {
            HotEdgePosition::Left => "hot-edge-sensor-left",
            HotEdgePosition::Right => "hot-edge-sensor-right",
            HotEdgePosition::Bottom => "hot-edge-sensor-bottom",
        };

        div()
            .id(id_str)
            .size_full()
            .bg(gpui_kit::hsla(0.0, 0.0, 0.0, 0.001))
            .on_hover(cx.listener(|this, hovered: &bool, _window, cx| {
                this.on_hover_changed(*hovered, cx);
            }))
    }
}

pub struct HotEdgesManager;

impl HotEdgesManager {
    /// Initialize hot edges for the current display configuration.
    pub fn init(cx: &mut App) {
        if HOT_EDGES_INITIALIZED.swap(true, Ordering::SeqCst) {
            return;
        }

        Self::open_sensor(HotEdgePosition::Left, cx);
        Self::open_sensor(HotEdgePosition::Right, cx);
        Self::open_sensor(HotEdgePosition::Bottom, cx);
        info!("HotEdgesManager: initialized edge sensor strips (Left, Right, Bottom)");
    }

    fn open_sensor(position: HotEdgePosition, cx: &mut App) {
        let (namespace, anchor, bounds_size) = match position {
            HotEdgePosition::Left => (
                "beskar-hot-edge-left",
                LayerAnchor::LEFT | LayerAnchor::TOP | LayerAnchor::BOTTOM,
                Size::new(px(2.0), px(1080.0)),
            ),
            HotEdgePosition::Right => (
                "beskar-hot-edge-right",
                LayerAnchor::RIGHT | LayerAnchor::TOP | LayerAnchor::BOTTOM,
                Size::new(px(2.0), px(1080.0)),
            ),
            HotEdgePosition::Bottom => (
                "beskar-hot-edge-bottom",
                LayerAnchor::BOTTOM | LayerAnchor::LEFT | LayerAnchor::RIGHT,
                Size::new(px(1920.0), px(2.0)),
            ),
        };

        let options = WindowOptions {
            titlebar: None,
            window_bounds: Some(WindowBounds::Windowed(Bounds {
                origin: point(px(0.), px(0.)),
                size: bounds_size,
            })),
            app_id: Some(namespace.to_string()),
            window_background: WindowBackgroundAppearance::Transparent,
            kind: WindowKind::LayerShell(LayerShellOptions {
                namespace: namespace.to_string(),
                layer: Layer::Top,
                anchor,
                exclusive_zone: None,
                margin: None,
                keyboard_interactivity: KeyboardInteractivity::None,
                ..Default::default()
            }),
            focus: false,
            ..Default::default()
        };

        if let Ok(handle) = cx.open_window(options, move |_window, cx| {
            cx.new(|_cx| HotEdgeSensorView::new(position))
        }) {
            if let Ok(mut handles) = SENSOR_HANDLES.lock() {
                handles.push(handle.into());
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_hot_edge_position_mapping() {
        assert_ne!(HotEdgePosition::Left, HotEdgePosition::Right);
        assert_ne!(HotEdgePosition::Right, HotEdgePosition::Bottom);
    }
}
