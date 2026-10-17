//! Convex Drawer Bézier geometry matching `references/minflair/.../ConvexDrawerShape.qml` and `SidebarWindow.qml`.
//! Implements continuous outward Bézier fillets/ears for edge-docked drawers:
//! - Bottom edge (Launcher, Clipboard, Wallpaper, Power Menu): flares outward into the bottom screen bezel
//! - Left edge (Dashboard): flares outward into the left screen bezel with seamless concave top/bottom ears
//! - Right edge (Control Center, Notifications): flares outward into the right screen bezel with seamless concave top/bottom ears
//! - Top edge (Music Player, Dynamic Center notch): flares outward into the top screen bezel

use gpui_kit::gpui::{Hsla, IntoElement, PathBuilder, Pixels, Point, Size, point, px};
use gpui_kit::prelude::*;
use gpui_kit::*;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ConvexDrawerEdge {
    Left,
    Right,
    Bottom,
    Top,
}

/// Size of the visible edge-attached surface at normalized reveal progress.
pub fn edge_reveal_size(size: Size<Pixels>, edge: ConvexDrawerEdge, progress: f32) -> Size<Pixels> {
    let progress = progress.clamp(0.0, 1.0);
    match edge {
        ConvexDrawerEdge::Left | ConvexDrawerEdge::Right => {
            Size::new(size.width * progress, size.height)
        }
        ConvexDrawerEdge::Bottom | ConvexDrawerEdge::Top => {
            Size::new(size.width, size.height * progress)
        }
    }
}

#[derive(Clone, Copy, Debug)]
enum OutlineCommand {
    MoveTo(f32, f32),
    LineTo(f32, f32),
    CubicTo {
        cp1: (f32, f32),
        cp2: (f32, f32),
        to: (f32, f32),
    },
    Close,
}

fn convex_outline_commands(
    size: Size<Pixels>,
    edge: ConvexDrawerEdge,
    flare_size: f32,
    corner_radius: f32,
) -> Vec<OutlineCommand> {
    let w = f32::from(size.width).max(1.0);
    let h = f32::from(size.height).max(1.0);
    let fw = flare_size.max(0.0).min(w * 0.35);
    let fh = flare_size.max(0.0).min(h * 0.25);
    let r = corner_radius.max(0.0).min((w - fw).max(0.0) * 0.5).min((h - fh * 2.0).max(0.0) * 0.5);
    let k = 0.552_284_8;
    let kf = fw * k;
    let kh = fh * k;
    let kr = r * k;

    match edge {
        ConvexDrawerEdge::Bottom => vec![
            OutlineCommand::MoveTo(0.0, h),
            // Concave bottom-left fillet transitioning out from screen bottom edge
            OutlineCommand::CubicTo {
                cp1: (kf, h),
                cp2: (fw, h - kh),
                to: (fw, h - fh),
            },
            // Left vertical side up to top rounded corner
            OutlineCommand::LineTo(fw, r),
            // Top-left convex rounded corner
            OutlineCommand::CubicTo {
                cp1: (fw, r - kr),
                cp2: (fw + r - kr, 0.0),
                to: (fw + r, 0.0),
            },
            // Top horizontal edge
            OutlineCommand::LineTo(w - fw - r, 0.0),
            // Top-right convex rounded corner
            OutlineCommand::CubicTo {
                cp1: (w - fw - r + kr, 0.0),
                cp2: (w - fw, r - kr),
                to: (w - fw, r),
            },
            // Right vertical side down to bottom flare
            OutlineCommand::LineTo(w - fw, h - fh),
            // Concave bottom-right fillet transitioning back into screen bottom edge
            OutlineCommand::CubicTo {
                cp1: (w - fw, h - kh),
                cp2: (w - kf, h),
                to: (w, h),
            },
            OutlineCommand::LineTo(0.0, h),
            OutlineCommand::Close,
        ],
        ConvexDrawerEdge::Left => vec![
            // Docked flush against left screen edge (x = 0)
            OutlineCommand::MoveTo(0.0, 0.0),
            // Concave top-outer fillet (ear curve) transitioning from x=0 into top edge at y=fh
            OutlineCommand::CubicTo {
                cp1: (0.0, kh),
                cp2: (kf, fh),
                to: (fw, fh),
            },
            // Top horizontal edge to inner corner
            OutlineCommand::LineTo(w - r, fh),
            // Top-right convex rounded corner
            OutlineCommand::CubicTo {
                cp1: (w - r + kr, fh),
                cp2: (w, fh + r - kr),
                to: (w, fh + r),
            },
            // Right vertical card edge
            OutlineCommand::LineTo(w, h - fh - r),
            // Bottom-right convex rounded corner
            OutlineCommand::CubicTo {
                cp1: (w, h - fh - r + kr),
                cp2: (w - r + kr, h - fh),
                to: (w - r, h - fh),
            },
            // Bottom horizontal edge
            OutlineCommand::LineTo(fw, h - fh),
            // Concave bottom-outer fillet (ear curve) transitioning back into screen edge at (0, h)
            OutlineCommand::CubicTo {
                cp1: (kf, h - fh),
                cp2: (0.0, h - kh),
                to: (0.0, h),
            },
            OutlineCommand::LineTo(0.0, 0.0),
            OutlineCommand::Close,
        ],
        ConvexDrawerEdge::Right => vec![
            // Docked flush against right screen edge (x = w)
            OutlineCommand::MoveTo(w, 0.0),
            // Concave top-outer fillet (ear curve) transitioning from x=w into top edge at y=fh
            OutlineCommand::CubicTo {
                cp1: (w, kh),
                cp2: (w - kf, fh),
                to: (w - fw, fh),
            },
            // Top horizontal edge to inner corner
            OutlineCommand::LineTo(r, fh),
            // Top-left convex rounded corner
            OutlineCommand::CubicTo {
                cp1: (r - kr, fh),
                cp2: (0.0, fh + r - kr),
                to: (0.0, fh + r),
            },
            // Left vertical card edge
            OutlineCommand::LineTo(0.0, h - fh - r),
            // Bottom-left convex rounded corner
            OutlineCommand::CubicTo {
                cp1: (0.0, h - fh - r + kr),
                cp2: (r - kr, h - fh),
                to: (r, h - fh),
            },
            // Bottom horizontal edge
            OutlineCommand::LineTo(w - fw, h - fh),
            // Concave bottom-outer fillet (ear curve) transitioning back into screen edge at (w, h)
            OutlineCommand::CubicTo {
                cp1: (w - kf, h - fh),
                cp2: (w, h - kh),
                to: (w, h),
            },
            OutlineCommand::LineTo(w, 0.0),
            OutlineCommand::Close,
        ],
        ConvexDrawerEdge::Top => vec![
            // Docked flush against top screen edge (y = 0)
            OutlineCommand::MoveTo(0.0, 0.0),
            // Concave top-left flare transitioning down into notch
            OutlineCommand::CubicTo {
                cp1: (kf, 0.0),
                cp2: (fw, kh),
                to: (fw, fh),
            },
            // Left vertical edge down to bottom corner
            OutlineCommand::LineTo(fw, h - r),
            // Bottom-left convex rounded corner
            OutlineCommand::CubicTo {
                cp1: (fw, h - r + kr),
                cp2: (fw + r - kr, h),
                to: (fw + r, h),
            },
            // Bottom horizontal edge
            OutlineCommand::LineTo(w - fw - r, h),
            // Bottom-right convex rounded corner
            OutlineCommand::CubicTo {
                cp1: (w - fw - r + kr, h),
                cp2: (w - fw, h - r + kr),
                to: (w - fw, h - r),
            },
            // Right vertical edge up to flare
            OutlineCommand::LineTo(w - fw, fh),
            // Concave top-right flare transitioning back to screen top edge
            OutlineCommand::CubicTo {
                cp1: (w - fw, kh),
                cp2: (w - kf, 0.0),
                to: (w, 0.0),
            },
            OutlineCommand::LineTo(0.0, 0.0),
            OutlineCommand::Close,
        ],
    }
}

/// Returns whether a point lies inside the painted convex outline.
pub fn convex_drawer_contains_point(
    size: Size<Pixels>,
    edge: ConvexDrawerEdge,
    point: Point<Pixels>,
) -> bool {
    const CURVE_STEPS: usize = 32;

    let commands = convex_outline_commands(size, edge, 24.0, 18.0);
    let mut outline = Vec::new();
    let mut current = (0.0, 0.0);
    let mut origin = current;
    for command in commands {
        match command {
            OutlineCommand::MoveTo(x, y) => {
                current = (x, y);
                origin = current;
                outline.push(current);
            }
            OutlineCommand::LineTo(x, y) => {
                current = (x, y);
                outline.push(current);
            }
            OutlineCommand::CubicTo { cp1, cp2, to } => {
                let start = current;
                for step in 1..=CURVE_STEPS {
                    let t = step as f32 / CURVE_STEPS as f32;
                    let inverse = 1.0 - t;
                    let x = inverse.powi(3) * start.0
                        + 3.0 * inverse.powi(2) * t * cp1.0
                        + 3.0 * inverse * t.powi(2) * cp2.0
                        + t.powi(3) * to.0;
                    let y = inverse.powi(3) * start.1
                        + 3.0 * inverse.powi(2) * t * cp1.1
                        + 3.0 * inverse * t.powi(2) * cp2.1
                        + t.powi(3) * to.1;
                    outline.push((x, y));
                }
                current = to;
            }
            OutlineCommand::Close => current = origin,
        }
    }

    let (point_x, point_y) = (f32::from(point.x), f32::from(point.y));
    let mut inside = false;
    for index in 0..outline.len() {
        let current = outline[index];
        let previous = outline[(index + outline.len() - 1) % outline.len()];
        if (current.1 > point_y) != (previous.1 > point_y)
            && point_x
                < (previous.0 - current.0) * (point_y - current.1) / (previous.1 - current.1)
                    + current.0
        {
            inside = !inside;
        }
    }
    inside
}

/// A clipped, theme-aware panel surface whose outline follows its docking edge.
#[derive(IntoElement)]
pub struct EdgeSurface {
    size: Size<Pixels>,
    edge: ConvexDrawerEdge,
    content: Option<AnyElement>,
}

impl EdgeSurface {
    pub fn new(size: Size<Pixels>, edge: ConvexDrawerEdge) -> Self {
        Self {
            size,
            edge,
            content: None,
        }
    }

    pub fn child(mut self, content: impl IntoElement) -> Self {
        self.content = Some(content.into_any_element());
        self
    }
}

impl RenderOnce for EdgeSurface {
    fn render(self, _window: &mut Window, _cx: &mut App) -> impl IntoElement {
        let flare = 24.0_f32;
        let radius = 18.0_f32;

        div()
            .relative()
            .w(self.size.width)
            .h(self.size.height)
            .overflow_hidden()
            .child(convex_drawer_background(
                self.size,
                self.edge,
                beskar_theme::Theme::card_bg(),
                flare,
                radius,
            ))
            .when_some(self.content, |surface, content| {
                match self.edge {
                    ConvexDrawerEdge::Left => surface.child(
                        div()
                            .relative()
                            .size_full()
                            .pl(px(8.0))
                            .pr(px(12.0))
                            .pt(px(flare))
                            .pb(px(flare))
                            .child(content),
                    ),
                    ConvexDrawerEdge::Right => surface.child(
                        div()
                            .relative()
                            .size_full()
                            .pl(px(12.0))
                            .pr(px(8.0))
                            .pt(px(flare))
                            .pb(px(flare))
                            .child(content),
                    ),
                    ConvexDrawerEdge::Bottom => surface.child(
                        div()
                            .relative()
                            .size_full()
                            .px(px(flare))
                            .pt(px(10.0))
                            .pb(px(8.0))
                            .child(content),
                    ),
                    ConvexDrawerEdge::Top => surface.child(
                        div()
                            .relative()
                            .size_full()
                            .px(px(flare))
                            .pt(px(8.0))
                            .pb(px(10.0))
                            .child(content),
                    ),
                }
            })
    }
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
    let commands = convex_outline_commands(size, edge, flare_size, corner_radius);

    gpui_kit::gpui::canvas(
        |_, _, _| (),
        move |bounds, _, window, _| {
            let ox = bounds.origin.x;
            let oy = bounds.origin.y;
            let pt = |x: f32, y: f32| point(ox + px(x), oy + px(y));

            let mut path = PathBuilder::fill();
            for command in commands {
                match command {
                    OutlineCommand::MoveTo(x, y) => path.move_to(pt(x, y)),
                    OutlineCommand::LineTo(x, y) => path.line_to(pt(x, y)),
                    OutlineCommand::CubicTo { cp1, cp2, to } => {
                        path.cubic_bezier_to(
                            pt(to.0, to.1),
                            pt(cp1.0, cp1.1),
                            pt(cp2.0, cp2.1),
                        );
                    }
                    OutlineCommand::Close => path.close(),
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

    #[core::prelude::v1::test]
    fn edge_reveal_grows_only_inward_from_its_owning_edge() {
        let size = Size::new(px(400.0), px(600.0));

        for edge in [ConvexDrawerEdge::Left, ConvexDrawerEdge::Right] {
            let collapsed = edge_reveal_size(size, edge, 0.0);
            let half = edge_reveal_size(size, edge, 0.5);
            let expanded = edge_reveal_size(size, edge, 1.0);
            assert_eq!(collapsed.width, px(0.0));
            assert_eq!(half.width, px(200.0));
            assert_eq!(expanded.width, size.width);
            assert_eq!(half.height, size.height);
        }

        for edge in [ConvexDrawerEdge::Bottom, ConvexDrawerEdge::Top] {
            let collapsed = edge_reveal_size(size, edge, 0.0);
            let half = edge_reveal_size(size, edge, 0.5);
            let expanded = edge_reveal_size(size, edge, 1.0);
            assert_eq!(collapsed.height, px(0.0));
            assert_eq!(half.height, px(300.0));
            assert_eq!(expanded.height, size.height);
            assert_eq!(half.width, size.width);
        }
    }

    #[core::prelude::v1::test]
    fn convex_hit_testing_excludes_transparent_corners_for_every_edge() {
        let size = Size::new(px(320.0), px(400.0));
        let center = point(px(160.0), px(200.0));
        let transparent_corner = [
            point(px(319.0), px(1.0)),
            point(px(1.0), px(1.0)),
            point(px(1.0), px(1.0)),
            point(px(1.0), px(399.0)),
        ];

        for (edge, outside) in [
            (ConvexDrawerEdge::Left, transparent_corner[0]),
            (ConvexDrawerEdge::Right, transparent_corner[1]),
            (ConvexDrawerEdge::Bottom, transparent_corner[2]),
            (ConvexDrawerEdge::Top, transparent_corner[3]),
        ] {
            assert!(convex_drawer_contains_point(size, edge, center));
            assert!(!convex_drawer_contains_point(size, edge, outside));
        }
    }

    #[core::prelude::v1::test]
    fn tiny_edge_surfaces_keep_outline_inside_their_bounds() {
        let size = Size::new(px(8.0), px(6.0));
        let outside = [
            point(px(7.0), px(0.0)),
            point(px(0.0), px(0.0)),
            point(px(0.0), px(0.0)),
            point(px(0.0), px(5.0)),
        ];

        for (edge, point) in [
            (ConvexDrawerEdge::Left, outside[0]),
            (ConvexDrawerEdge::Right, outside[1]),
            (ConvexDrawerEdge::Bottom, outside[2]),
            (ConvexDrawerEdge::Top, outside[3]),
        ] {
            assert!(!convex_drawer_contains_point(size, edge, point));
        }
    }

    #[core::prelude::v1::test]
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
            ConvexDrawerEdge::Top,
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
