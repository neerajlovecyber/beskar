//! Window state and visible bounds geometry for Beskar Bar and Satellites.
//! Ported directly from `references/capsule/crates/app/src/capsule/window_state.rs`.

use beskar_core::config::BarPosition;
use gpui_kit::gpui::{AnyWindowHandle, Bounds, Pixels, Size, point};

#[derive(Clone, Debug)]
pub struct BarWindowState {
    pub handle: Option<AnyWindowHandle>,
    pub margin: f32,
    pub radius: f32,
    pub is_convex: bool,
    pub position: BarPosition,
}

impl BarWindowState {
    pub fn new(position: BarPosition, is_convex: bool) -> Self {
        Self {
            handle: None,
            margin: 0.0,
            radius: 0.0,
            is_convex,
            position,
        }
    }
}

pub fn effective_margin(is_convex: bool, margin: f32) -> f32 {
    if is_convex {
        0.0
    } else {
        margin.max(0.0)
    }
}

pub fn visible_bounds(
    viewport: Size<Pixels>,
    size: Size<Pixels>,
    margin: Pixels,
    location: &BarPosition,
) -> Bounds<Pixels> {
    let y = match location {
        BarPosition::Top => margin,
        BarPosition::Bottom => viewport.height - margin - size.height,
    };
    Bounds {
        origin: point((viewport.width - size.width) / 2.0, y),
        size,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use gpui_kit::gpui::px;

    #[test]
    fn concave_attaches_to_the_edge_without_losing_normal_margin() {
        assert_eq!(effective_margin(true, 24.0), 0.0);
        assert_eq!(effective_margin(false, 24.0), 24.0);
        assert_eq!(effective_margin(false, -24.0), 0.0);
    }

    #[test]
    fn centered_bounds_keep_the_screen_edge_fixed_during_growth() {
        let viewport = Size {
            width: px(400.0),
            height: px(308.0),
        };
        for height in [16.0, 25.0, 60.0, 300.0] {
            let dimensions = Size {
                width: px(172.0),
                height: px(height),
            };
            let top = visible_bounds(viewport, dimensions, px(8.0), &BarPosition::Top);
            assert_eq!(top.origin, point(px(114.0), px(8.0)));
            let bottom = visible_bounds(viewport, dimensions, px(8.0), &BarPosition::Bottom);
            assert_eq!(bottom.origin.y + bottom.size.height, px(300.0));
        }
    }
}
