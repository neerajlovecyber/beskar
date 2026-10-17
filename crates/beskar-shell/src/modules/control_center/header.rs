use gpui_kit::assets::IconName;
use gpui_kit::component::Icon;
use gpui_kit::component::button::{Button, ButtonVariants};
use gpui_kit::prelude::FluentBuilder;
use gpui_kit::*;
use std::sync::Arc;

pub fn render_header(on_close: Option<Arc<dyn Fn() + Send + Sync>>) -> impl IntoElement {
    div()
        .flex()
        .items_center()
        .justify_between()
        .child(
            div()
                .text_sm()
                .font_weight(FontWeight::BOLD)
                .text_color(beskar_theme::Theme::fg())
                .child("Control Center"),
        )
        .when_some(on_close, |this, cb| {
            this.child(
                Button::new("cc-close-btn")
                    .ghost()
                    .compact()
                    .icon(Icon::new(IconName::X).size(px(12.0)))
                    .on_click(move |_, _, _| {
                        (cb)();
                    }),
            )
        })
}
