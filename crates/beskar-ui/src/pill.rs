use gpui::{div, hsla, px, AnyElement, IntoElement, ParentElement, Pixels, RenderOnce, Styled, Window, App};

/// An Island Pill container featuring dark glassmorphic styling,
/// subtle hairline borders, and hover responsiveness directly styled
/// from the iRiS and Suzuha aesthetic design tokens.
#[derive(IntoElement)]
pub struct IslandPill {
    content: Vec<AnyElement>,
    padding_x: Pixels,
    padding_y: Pixels,
    is_interactive: bool,
}

impl IslandPill {
    pub fn new() -> Self {
        Self {
            content: Vec::new(),
            padding_x: px(14.0),
            padding_y: px(6.0),
            is_interactive: true,
        }
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
        div()
            .flex()
            .items_center()
            .px(self.padding_x)
            .py(self.padding_y)
            .rounded(px(18.0))
            // Obsidian dark acrylic background with 1px border
            .bg(hsla(240.0 / 360.0, 0.12, 0.08, 0.82))
            .border_1()
            .border_color(hsla(240.0 / 360.0, 0.08, 1.0, 0.10))
            .shadow_sm()
            .when(self.is_interactive, |this| {
                this.hover(|style| {
                    style
                        .bg(hsla(240.0 / 360.0, 0.12, 0.14, 0.92))
                        .border_color(hsla(45.0 / 360.0, 0.85, 0.65, 0.25))
                })
            })
            .children(self.content)
    }
}
