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

impl Default for IslandPill {
    fn default() -> Self {
        Self::new()
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
            // Dynamic acrylic core from active Theme
            .bg(if is_convex {
                beskar_theme::Theme::bg()
            } else {
                let mut b = beskar_theme::Theme::bg();
                b.a = (b.a * 0.90).clamp(0.0, 1.0);
                b
            })
            // Outer 1px perimeter boundary with subtle sheen
            .border_1()
            .border_color(beskar_theme::Theme::border())
            // Soft atmospheric drop shadow (elevation depth)
            .shadow_md()
            .when(self.is_interactive, |this| {
                this.hover(|style| {
                    style
                        // Elevated surface luminance on cursor hover
                        .bg(beskar_theme::Theme::bg_secondary())
                        // Accent edge reflection
                        .border_color(beskar_theme::Theme::accent())
                        .shadow_lg()
                })
            })
            .children(self.content)
    }
}
