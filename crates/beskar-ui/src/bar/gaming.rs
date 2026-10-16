//! High-contrast Cyber Gaming Bar Widget for Beskar.
//! Mirroring `references/minflair/config/quickshell/Modules/Bar/Styles/Gaming/GamingBar.qml`.

use gpui_kit::assets::IconName;
use gpui_kit::component::Icon;
use gpui_kit::*;

#[derive(IntoElement)]
pub struct GamingBarWidget {
    left: Vec<AnyElement>,
    center: Vec<AnyElement>,
    right: Vec<AnyElement>,
    padding_x: Pixels,
}

impl GamingBarWidget {
    pub fn new() -> Self {
        Self {
            left: Vec::new(),
            center: Vec::new(),
            right: Vec::new(),
            padding_x: px(12.0),
        }
    }

    pub fn left(mut self, elements: impl IntoIterator<Item = AnyElement>) -> Self {
        self.left.extend(elements);
        self
    }

    pub fn center(mut self, elements: impl IntoIterator<Item = AnyElement>) -> Self {
        self.center.extend(elements);
        self
    }

    pub fn right(mut self, elements: impl IntoIterator<Item = AnyElement>) -> Self {
        self.right.extend(elements);
        self
    }
}

impl Default for GamingBarWidget {
    fn default() -> Self {
        Self::new()
    }
}

impl RenderOnce for GamingBarWidget {
    fn render(self, _window: &mut Window, _cx: &mut App) -> impl IntoElement {
        let gaming_badge = div()
            .flex()
            .items_center()
            .gap(px(6.0))
            .px(px(8.0))
            .py(px(3.0))
            .bg(beskar_theme::Theme::accent())
            .text_color(beskar_theme::Theme::bg())
            .font_weight(FontWeight::BOLD)
            .text_size(px(11.0))
            .child(
                Icon::new(IconName::Activity)
                    .size(px(13.0))
                    .text_color(beskar_theme::Theme::bg()),
            )
            .child("GAMING");

        let divider = div()
            .w(px(1.0))
            .h(px(16.0))
            .bg(beskar_theme::Theme::subtle_border());

        div()
            .relative()
            .size_full()
            .bg(beskar_theme::Theme::bg())
            .border_b_1()
            .border_color(beskar_theme::Theme::subtle_border())
            .child(
                div()
                    .absolute()
                    .top_0()
                    .bottom_0()
                    .left_0()
                    .pl(self.padding_x)
                    .flex()
                    .items_center()
                    .gap(px(8.0))
                    .child(gaming_badge)
                    .child(divider)
                    .children(self.left),
            )
            .child(
                div()
                    .absolute()
                    .inset_0()
                    .flex()
                    .items_center()
                    .justify_center()
                    .children(self.center),
            )
            .child(
                div()
                    .absolute()
                    .top_0()
                    .bottom_0()
                    .right_0()
                    .pr(self.padding_x)
                    .flex()
                    .items_center()
                    .justify_end()
                    .children(self.right),
            )
    }
}
