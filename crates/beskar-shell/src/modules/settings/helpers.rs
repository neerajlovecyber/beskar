use gpui_kit::component::tag::Tag;
use gpui_kit::*;

pub fn settings_card(title: &'static str) -> gpui::Div {
    div()
        .p(px(14.0))
        .rounded(px(14.0))
        .bg(beskar_theme::Theme::glass_fill(0.04))
        .border_1()
        .border_color(beskar_theme::Theme::card_border())
        .flex()
        .flex_col()
        .gap(px(10.0))
        .child(
            div()
                .text_xs()
                .font_weight(FontWeight::BOLD)
                .text_color(beskar_theme::Theme::text_secondary())
                .child(title),
        )
}

pub fn settings_row(
    title: &'static str,
    description: &'static str,
    control: impl IntoElement,
) -> gpui::Div {
    div()
        .flex()
        .items_center()
        .justify_between()
        .py(px(4.0))
        .child(
            div()
                .flex()
                .flex_col()
                .gap(px(2.0))
                .child(
                    div()
                        .text_xs()
                        .font_weight(FontWeight::BOLD)
                        .text_color(beskar_theme::Theme::fg())
                        .child(title),
                )
                .child(
                    div()
                        .text_xs()
                        .text_color(beskar_theme::Theme::text_secondary())
                        .child(description),
                ),
        )
        .child(control)
}

pub fn kbd_chip(label: &'static str) -> impl IntoElement {
    Tag::secondary().child(label)
}
