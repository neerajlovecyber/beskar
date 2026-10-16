//! Deprecated convex module. Pure Capsule-native concave Bézier math lives in `widgets::style`.
//! Ported directly from `references/capsule`.

use gpui_kit::*;
pub use crate::bar::ConcaveBarWidget;
pub use crate::widgets::style::{concave_background, concave_radii};

#[derive(Debug, Clone, Copy, Default)]
pub struct ConvexGeometry {
    pub width: f32,
    pub height: f32,
    pub left_w: f32,
    pub center_x: f32,
    pub center_w: f32,
    pub right_w: f32,
}

impl ConvexGeometry {
    pub fn auto_calculate(
        screen_width: f32,
        bar_height: f32,
        left_w: f32,
        center_w: f32,
        right_w: f32,
    ) -> Self {
        let center_x = ((screen_width - center_w) * 0.5).max(left_w + 16.0);
        Self {
            width: screen_width,
            height: bar_height,
            left_w,
            center_x,
            center_w,
            right_w,
        }
    }
}

/// Backward compatibility shim forwarding directly to `ConcaveBarWidget` using `concave_background`.
#[derive(IntoElement)]
pub struct ConvexBarShape {
    geometry: ConvexGeometry,
    fill_color: Hsla,
}

impl ConvexBarShape {
    pub fn new(geom: ConvexGeometry, fill_color: Hsla, _border_color: Hsla) -> Self {
        Self {
            geometry: geom,
            fill_color,
        }
    }
}

impl RenderOnce for ConvexBarShape {
    fn render(self, _window: &mut Window, _cx: &mut App) -> impl IntoElement {
        let size = Size::new(px(self.geometry.center_w), px(self.geometry.height.max(38.0)));
        ConcaveBarWidget::new(size).color(self.fill_color)
    }
}
