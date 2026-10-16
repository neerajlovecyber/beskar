//! Satellite layout math and helpers for UI placement.
//! Ported directly from `references/capsule/crates/app/src/capsule/satellite/layout.rs`.

use gpui_kit::gpui::{point, px, Bounds, Pixels, Size};

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Side {
    Left,
    Right,
    Below,
}

#[derive(Clone, Copy, Debug, PartialEq)]
pub struct SatelliteLayout {
    pub bounds: Bounds<Pixels>,
    pub content_size: Size<Pixels>,
    pub side: Side,
}

pub fn centered_y(
    capsule: Bounds<Pixels>,
    height: Pixels,
    viewport_height: Pixels,
) -> Pixels {
    (capsule.origin.y + (capsule.size.height - height) / 2.0)
        .clamp(px(0.0), (viewport_height - height).max(px(0.0)))
}

impl SatelliteLayout {
    pub fn new(
        viewport: Size<Pixels>,
        capsule: Bounds<Pixels>,
        desired: Size<Pixels>,
        gap: Pixels,
        preferred: Side,
        progress: f32,
    ) -> Self {
        let gap = gap.max(px(0.0));
        let width = desired.width.min(viewport.width).max(px(1.0));
        let left_space = capsule.origin.x - gap;
        let right_edge = capsule.origin.x + capsule.size.width;
        let right_space = viewport.width - right_edge - gap;
        let side = if preferred == Side::Right && right_space >= width {
            Side::Right
        } else if left_space >= width {
            Side::Left
        } else if right_space >= width {
            Side::Right
        } else {
            Side::Below
        };
        let target_y = match side {
            Side::Below => capsule.origin.y + capsule.size.height + gap,
            _ => capsule.origin.y,
        };
        let height = desired
            .height
            .min((viewport.height - target_y).max(px(1.0)));
        let y = target_y.min((viewport.height - height).max(px(0.0)));
        let content_size = Size {
            width,
            height,
        };
        let progress = progress.clamp(0.0, 1.0);
        let offset = px(16.0) * (1.0 - progress);
        let (x, y) = match side {
            Side::Left => (capsule.origin.x - gap - width + offset, y),
            Side::Right => (right_edge + gap - offset, y),
            Side::Below => (
                (capsule.origin.x + (capsule.size.width - width) / 2.0)
                    .clamp(px(0.0), (viewport.width - width).max(px(0.0))),
                (y - offset).max(px(0.0)),
            ),
        };
        Self {
            bounds: Bounds {
                origin: point(x, y),
                size: content_size,
            },
            content_size,
            side,
        }
    }
}
