use gpui_kit::prelude::FluentBuilder;
use gpui_kit::*;

/// An Island Pill container featuring dark glassmorphic styling,
/// subtle hairline borders, and hover responsiveness directly styled
/// from the iRiS and Suzuha aesthetic design tokens.
#[derive(IntoElement)]
pub struct IslandPill {
    content: Vec<AnyElement>,
    padding_x: Pixels,
    padding_y: Pixels,
    is_interactive: bool,
    is_convex: bool,
}

impl IslandPill {
    pub fn new() -> Self {
        Self {
            content: Vec::new(),
            padding_x: px(14.0),

            padding_y: px(6.0),
            is_interactive: true,
            is_convex: false,
        }
    }

    pub fn convex(mut self, convex: bool) -> Self {
        self.is_convex = convex;
        self
    }

    pub fn padding(mut self, x: Pixels, y: Pixels) -> Self {
        self.padding_x = x;
        self.padding_y = y;
        self
    }


    pub fn child(mut self, child: impl IntoElement) -> Self {
        self.content.push(child.into_any_element());
        self
    }
}

impl RenderOnce for IslandPill {
    fn render(self, _window: &mut Window, _cx: &mut App) -> impl IntoElement {
        let is_convex = self.is_convex;
        div()
            .relative()
            .flex()
            .items_center()
            .px(self.padding_x)
            .py(self.padding_y)
            .when(is_convex, |s| s.rounded_b(px(14.0)))
            .when(!is_convex, |s| s.rounded(px(18.0)))
            // Deep obsidian acrylic core: 96% in convex mode, 84% in floating island mode
            .bg(if is_convex {
                hsla(250.0 / 360.0, 0.16, 0.06, 0.96)
            } else {
                hsla(240.0 / 360.0, 0.14, 0.07, 0.84)
            })
            // Outer 1px perimeter boundary with ultra-subtle sheen
            .border_1()
            .border_color(hsla(240.0 / 360.0, 0.10, 1.0, 0.12))
            // Soft atmospheric drop shadow (elevation depth)
            .shadow_md()

            // Specular top highlight simulating acrylic glass light catching
            .child(
                div()
                    .absolute()
                    .top_0()
                    .left(px(14.0))
                    .right(px(14.0))
                    .h(px(1.0))
                    .bg(hsla(0.0, 0.0, 1.0, 0.18)),
            )
            .when(self.is_interactive, |this| {
                this.hover(|style| {
                    style
                        // Elevated surface luminance on cursor hover
                        .bg(hsla(240.0 / 360.0, 0.14, 0.13, 0.94))
                        // Warm amber edge reflection from iRiS design language
                        .border_color(hsla(45.0 / 360.0, 0.85, 0.65, 0.35))
                        .shadow_lg()
                })
            })
            .children(self.content)
    }
}
