//! Concave continuous Bézier Bar Widget for Beskar matching `references/minflair` / `capsule`.
//! Renders seamless concave outer corner fillets (ear-curves) and rounded inner corners for:
//! - Left Island: Flush against screen top and left edge, concave fillet flaring into the top bezel
//! - Center Island: Hanging from screen top, concave fillets flaring into top bezel on both sides
//! - Right Island: Flush against screen top and right edge, concave fillet flaring into the top bezel on the left

use gpui_kit::gpui::{Hsla, IntoElement, PathBuilder, Pixels, Size, point, px};
use gpui_kit::prelude::*;
use gpui_kit::*;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum ConcaveBarPosition {
    Left,
    #[default]
    Center,
    Right,
}

#[derive(IntoElement)]
pub struct ConcaveBarWidget {
    size: Size<Pixels>,
    position: ConcaveBarPosition,
    radius: f32,
    color: Hsla,
    content: Option<AnyElement>,
}

impl ConcaveBarWidget {
    pub fn new(size: Size<Pixels>) -> Self {
        Self {
            size,
            position: ConcaveBarPosition::Center,
            radius: 16.0,
            color: beskar_theme::Theme::bg(),
            content: None,
        }
    }

    pub fn position(mut self, position: ConcaveBarPosition) -> Self {
        self.position = position;
        self
    }

    pub fn radius(mut self, radius: f32) -> Self {
        self.radius = radius;
        self
    }

    pub fn color(mut self, color: Hsla) -> Self {
        self.color = color;
        self
    }

    pub fn child(mut self, content: impl IntoElement) -> Self {
        self.content = Some(content.into_any_element());
        self
    }
}

impl RenderOnce for ConcaveBarWidget {
    fn render(self, _window: &mut Window, _cx: &mut App) -> impl IntoElement {
        let size = self.size;
        let pos = self.position;
        let radius = self.radius;
        let color = self.color;

        div()
            .relative()
            .w(size.width)
            .h(size.height)
            .flex_shrink_0()
            .child(render_bar_module_background(size, pos, radius, color))
            .when_some(self.content, |this, content| {
                match pos {
                    ConcaveBarPosition::Left => this.child(
                        div()
                            .relative()
                            .size_full()
                            .pl(px(10.0))
                            .pr(px(14.0))
                            .flex()
                            .items_center()
                            .child(content),
                    ),
                    ConcaveBarPosition::Center => this.child(
                        div()
                            .relative()
                            .size_full()
                            .px(px(12.0))
                            .flex()
                            .items_center()
                            .justify_center()
                            .child(content),
                    ),
                    ConcaveBarPosition::Right => this.child(
                        div()
                            .relative()
                            .size_full()
                            .pl(px(14.0))
                            .pr(px(10.0))
                            .flex()
                            .items_center()
                            .justify_end()
                            .child(content),
                    ),
                }
            })
    }
}

fn render_bar_module_background(
    size: Size<Pixels>,
    position: ConcaveBarPosition,
    corner_radius: f32,
    color: Hsla,
) -> impl IntoElement {
    let w = f32::from(size.width).max(1.0);
    let h = f32::from(size.height).max(1.0);
    let fw = 18.0_f32;
    let fh = 16.0_f32;
    let r = corner_radius.min(w * 0.4).min(h * 0.5);
    let k = 0.552_284_8_f32;
    let kf = fw * k;
    let kh = fh * k;
    let kr = r * k;

    gpui_kit::gpui::canvas(
        |_, _, _| (),
        move |bounds, _, window, _| {
            let ox = bounds.origin.x;
            let oy = bounds.origin.y;
            let pt = |x: f32, y: f32| point(ox + px(x), oy + px(y));

            let mut path = PathBuilder::fill();
            match position {
                ConcaveBarPosition::Left => {
                    // Start at top-left screen corner
                    path.move_to(pt(0.0, 0.0));
                    // Down left screen frame
                    path.line_to(pt(0.0, h));
                    // Horizontal bottom edge to inner corner
                    path.line_to(pt(w - r, h));
                    // Rounded bottom-right corner
                    path.cubic_bezier_to(
                        pt(w, h - r),
                        pt(w - r + kr, h),
                        pt(w, h - kr),
                    );
                    // Straight line up to flare start
                    path.line_to(pt(w, fh));
                    // Concave ear-curve flaring right into top screen border
                    path.cubic_bezier_to(
                        pt(w + fw, 0.0),
                        pt(w, fh - kh),
                        pt(w + fw - kf, 0.0),
                    );
                    // Close along top screen border
                    path.line_to(pt(0.0, 0.0));
                    path.close();
                }
                ConcaveBarPosition::Center => {
                    // Start on top screen border at left flare
                    path.move_to(pt(-fw, 0.0));
                    // Concave flare curving down into center notch
                    path.cubic_bezier_to(
                        pt(0.0, fh),
                        pt(-fw + kf, 0.0),
                        pt(0.0, fh - kh),
                    );
                    // Down left edge to bottom corner
                    path.line_to(pt(0.0, h - r));
                    // Rounded bottom-left corner
                    path.cubic_bezier_to(
                        pt(r, h),
                        pt(0.0, h - kr),
                        pt(r - kr, h),
                    );
                    // Horizontal bottom edge
                    path.line_to(pt(w - r, h));
                    // Rounded bottom-right corner
                    path.cubic_bezier_to(
                        pt(w, h - r),
                        pt(w - r + kr, h),
                        pt(w, h - kr),
                    );
                    // Up right edge to flare start
                    path.line_to(pt(w, fh));
                    // Concave flare curving up into top screen border
                    path.cubic_bezier_to(
                        pt(w + fw, 0.0),
                        pt(w, fh - kh),
                        pt(w + fw - kf, 0.0),
                    );
                    // Close along top screen border
                    path.line_to(pt(-fw, 0.0));
                    path.close();
                }
                ConcaveBarPosition::Right => {
                    // Start on top screen border at left flare
                    path.move_to(pt(-fw, 0.0));
                    // Concave flare curving down into right module
                    path.cubic_bezier_to(
                        pt(0.0, fh),
                        pt(-fw + kf, 0.0),
                        pt(0.0, fh - kh),
                    );
                    // Down left edge to bottom corner
                    path.line_to(pt(0.0, h - r));
                    // Rounded bottom-left corner
                    path.cubic_bezier_to(
                        pt(r, h),
                        pt(0.0, h - kr),
                        pt(r - kr, h),
                    );
                    // Horizontal bottom edge to right screen frame
                    path.line_to(pt(w, h));
                    // Up right screen frame
                    path.line_to(pt(w, 0.0));
                    // Close along top screen border
                    path.line_to(pt(-fw, 0.0));
                    path.close();
                }
            }

            if let Ok(path) = path.build() {
                window.paint_path(path, color);
            }
        },
    )
    .absolute()
    .size_full()
}
