//! Convex Drawer Bézier geometry matching `references/minflair/.../ConvexDrawerShape.qml`.
//! Implements continuous outward Bézier flares for edge-docked drawers:
//! - Bottom edge (Launcher, Clipboard, Wallpaper, Power Menu): flares outward into the bottom screen bezel
//! - Left edge (Dashboard): flares outward into the left screen bezel
//! - Right edge (Control Center, Notifications): flares outward into the right screen bezel

use gpui_kit::gpui::{
    Hsla, IntoElement, PathBuilder, Pixels, Size, point, px,
};
use gpui_kit::prelude::*;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ConvexDrawerEdge {
    Left,
    Right,
    Bottom,
    Top,
}

/// Renders a hardware-accelerated continuous Bézier convex shape that seamlessly
/// integrates an edge-docked panel with the screen bezel.
pub fn convex_drawer_background(
    size: Size<Pixels>,
    edge: ConvexDrawerEdge,
    fill_color: Hsla,
    flare_size: f32,
    corner_radius: f32,
) -> impl IntoElement {
    let w = f32::from(size.width).max(1.0);
    let h = f32::from(size.height).max(1.0);
    let fw = flare_size.min(w * 0.25).max(4.0);
    let fh = flare_size.min(h * 0.25).max(4.0);
    let r = corner_radius.min(w * 0.5).min(h * 0.5).max(4.0);
    let k = 0.552_284_8;

    gpui_kit::gpui::canvas(
        |_, _, _| (),
        move |bounds, _, window, _| {
            let ox = bounds.origin.x;
            let oy = bounds.origin.y;
            let pt = |x: f32, y: f32| point(ox + px(x), oy + px(y));

            let mut path = PathBuilder::fill();
            match edge {
                ConvexDrawerEdge::Bottom => {
                    // Starts at bottom-left corner against the screen edge (0, h)
                    path.move_to(pt(0.0, h));
                    // Outward Bézier flare transitioning from screen bezel to drawer left wall
                    path.cubic_bezier_to(
                        pt(fw, h - fh),
                        pt(fw * (1.0 - k), h),
                        pt(fw, h - fh * (1.0 - k)),
                    );
                    // Straight left edge up to top-left rounded corner
                    path.line_to(pt(fw, r));
                    // Top-left rounded corner
                    path.cubic_bezier_to(
                        pt(fw + r, 0.0),
                        pt(fw, r * (1.0 - k)),
                        pt(fw + r * (1.0 - k), 0.0),
                    );
                    // Top horizontal edge
                    path.line_to(pt(w - fw - r, 0.0));
                    // Top-right rounded corner
                    path.cubic_bezier_to(
                        pt(w - fw, r),
                        pt(w - fw - r * (1.0 - k), 0.0),
                        pt(w - fw, r * (1.0 - k)),
                    );
                    // Straight right edge down to bottom flare
                    path.line_to(pt(w - fw, h - fh));
                    // Outward Bézier flare transitioning into bottom screen bezel
                    path.cubic_bezier_to(
                        pt(w, h),
                        pt(w - fw, h - fh * (1.0 - k)),
                        pt(w - fw * (1.0 - k), h),
                    );
                    // Flush along the bottom screen edge
                    path.line_to(pt(0.0, h));
                    path.close();
                }
                ConvexDrawerEdge::Left => {
                    // Starts at top-left corner against the screen edge (0, 0)
                    path.move_to(pt(0.0, 0.0));
                    // Outward Bézier flare transitioning into top edge of drawer
                    path.cubic_bezier_to(
                        pt(fw, fh),
                        pt(0.0, fh * (1.0 - k)),
                        pt(fw * (1.0 - k), fh),
                    );
                    // Top horizontal edge to top-right corner
                    path.line_to(pt(w - r, fh));
                    // Top-right rounded corner
                    path.cubic_bezier_to(
                        pt(w, fh + r),
                        pt(w - r * (1.0 - k), fh),
                        pt(w, fh + r * (1.0 - k)),
                    );
                    // Right edge down to bottom-right corner
                    path.line_to(pt(w, h - fh - r));
                    // Bottom-right rounded corner
                    path.cubic_bezier_to(
                        pt(w - r, h - fh),
                        pt(w, h - fh - r * (1.0 - k)),
                        pt(w - r * (1.0 - k), h - fh),
                    );
                    // Bottom horizontal edge back to flare
                    path.line_to(pt(fw, h - fh));
                    // Outward Bézier flare transitioning into bottom screen bezel
                    path.cubic_bezier_to(
                        pt(0.0, h),
                        pt(fw * (1.0 - k), h - fh),
                        pt(0.0, h - fh * (1.0 - k)),
                    );
                    // Flush along left screen edge
                    path.line_to(pt(0.0, 0.0));
                    path.close();
                }
                ConvexDrawerEdge::Right => {
                    // Starts at top-right corner against the right screen edge (w, 0)
                    path.move_to(pt(w, 0.0));
                    // Outward Bézier flare transitioning into top edge of drawer
                    path.cubic_bezier_to(
                        pt(w - fw, fh),
                        pt(w, fh * (1.0 - k)),
                        pt(w - fw * (1.0 - k), fh),
                    );
                    // Top horizontal edge to top-left corner
                    path.line_to(pt(r, fh));
                    // Top-left rounded corner
                    path.cubic_bezier_to(
                        pt(0.0, fh + r),
                        pt(r * (1.0 - k), fh),
                        pt(0.0, fh + r * (1.0 - k)),
                    );
                    // Left edge down to bottom-left corner
                    path.line_to(pt(0.0, h - fh - r));
                    // Bottom-left rounded corner
                    path.cubic_bezier_to(
                        pt(r, h - fh),
                        pt(0.0, h - fh - r * (1.0 - k)),
                        pt(r * (1.0 - k), h - fh),
                    );
                    // Bottom horizontal edge back to right flare
                    path.line_to(pt(w - fw, h - fh));
                    // Outward Bézier flare transitioning into right screen bezel
                    path.cubic_bezier_to(
                        pt(w, h),
                        pt(w - fw * (1.0 - k), h - fh),
                        pt(w, h - fh * (1.0 - k)),
                    );
                    // Flush along right screen edge
                    path.line_to(pt(w, 0.0));
                    path.close();
                }
                ConvexDrawerEdge::Top => {
                    // Top edge drawer (flaring into top screen bezel)
                    path.move_to(pt(0.0, 0.0));
                    path.cubic_bezier_to(
                        pt(fw, fh),
                        pt(fw * (1.0 - k), 0.0),
                        pt(fw, fh * (1.0 - k)),
                    );
                    path.line_to(pt(fw, h - r));
                    path.cubic_bezier_to(
                        pt(fw + r, h),
                        pt(fw, h - r * (1.0 - k)),
                        pt(fw + r * (1.0 - k), h),
                    );
                    path.line_to(pt(w - fw - r, h));
                    path.cubic_bezier_to(
                        pt(w - fw, h - r),
                        pt(w - fw - r * (1.0 - k), h),
                        pt(w - fw, h - r * (1.0 - k)),
                    );
                    path.line_to(pt(w - fw, fh));
                    path.cubic_bezier_to(
                        pt(w, 0.0),
                        pt(w - fw, fh * (1.0 - k)),
                        pt(w - fw * (1.0 - k), 0.0),
                    );
                    path.line_to(pt(0.0, 0.0));
                    path.close();
                }
            }

            if let Ok(path) = path.build() {
                window.paint_path(path, fill_color);
            }
        },
    )
    .absolute()
    .size_full()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_convex_drawer_edges() {
        let size = Size::new(px(500.0), px(600.0));
        let _ = convex_drawer_background(
            size,
            ConvexDrawerEdge::Bottom,
            gpui_kit::hsla(0.0, 0.0, 0.0, 1.0),
            28.0,
            20.0,
        );
        let _ = convex_drawer_background(
            size,
            ConvexDrawerEdge::Left,
            gpui_kit::hsla(0.0, 0.0, 0.0, 1.0),
            28.0,
            20.0,
        );
        let _ = convex_drawer_background(
            size,
            ConvexDrawerEdge::Right,
            gpui_kit::hsla(0.0, 0.0, 0.0, 1.0),
            28.0,
            20.0,
        );
    }
}
