//! Concave continuous Bézier Bar Widget for Beskar.
//! Ported directly from `references/capsule/crates/app/src/capsule/mod.rs:138-150`
//! using `concave_background` from `widgets::style`.

use gpui_kit::*;
use crate::widgets::style::{concave_background, concave_radii};

#[derive(IntoElement)]
pub struct ConcaveBarWidget {
    size: Size<Pixels>,
    radius: f32,
    bottom: bool,
    color: Hsla,
    content: Option<AnyElement>,
}

impl ConcaveBarWidget {
    pub fn new(size: Size<Pixels>) -> Self {
        Self {
            size,
            radius: 16.0,
            bottom: false,
            color: beskar_theme::Theme::bg(),
            content: None,
        }
    }

    pub fn radius(mut self, radius: f32) -> Self {
        self.radius = radius;
        self
    }

    pub fn bottom(mut self, bottom: bool) -> Self {
        self.bottom = bottom;
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
        let (radius, _) = concave_radii(self.size, self.radius);
        div()
            .relative()
            .w(self.size.width)
            .h(self.size.height)
            .flex_shrink_0()
            .child(concave_background(self.size, radius, self.bottom, self.color))
            .children(self.content)
    }
}
