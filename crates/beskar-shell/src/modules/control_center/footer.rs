use gpui_kit::assets::IconName;
use gpui_kit::component::button::{Button, ButtonVariants};
use gpui_kit::component::Icon;
use gpui_kit::prelude::FluentBuilder;
use gpui_kit::*;
use std::sync::Arc;

pub fn render_footer(
    on_launcher: Option<Arc<dyn Fn() + Send + Sync>>,
    on_clipboard: Option<Arc<dyn Fn() + Send + Sync>>,
    on_settings: Option<Arc<dyn Fn() + Send + Sync>>,
    on_power: Option<Arc<dyn Fn() + Send + Sync>>,
) -> impl IntoElement {
    div()
        .flex()
        .items_center()
        .gap(px(8.0))
        .when_some(on_launcher, |this, cb| {
            this.child(
                Button::new("cc-action-launcher")
                    .secondary()
                    .flex_1()
                    .icon(Icon::new(IconName::Search).size(px(12.0)))
                    .label("Apps")
                    .on_click(move |_, _, _| {
                        (cb)();
                    }),
            )
        })
        .when_some(on_clipboard, |this, cb| {
            this.child(
                Button::new("cc-action-clipboard")
                    .secondary()
                    .flex_1()
                    .icon(Icon::new(IconName::ClipboardList).size(px(12.0)))
                    .label("Clips")
                    .on_click(move |_, _, _| {
                        (cb)();
                    }),
            )
        })
        .when_some(on_settings, |this, cb| {
            this.child(
                Button::new("cc-action-settings")
                    .secondary()
                    .flex_1()
                    .icon(Icon::new(IconName::Settings).size(px(12.0)))
                    .label("Settings")
                    .on_click(move |_, _, _| {
                        (cb)();
                    }),
            )
        })
        .when_some(on_power, |this, cb| {
            this.child(
                Button::new("cc-action-power")
                    .secondary()
                    .flex_1()
                    .icon(Icon::new(IconName::Power).size(px(12.0)))
                    .label("Power")
                    .on_click(move |_, _, _| {
                        (cb)();
                    }),
            )
        })
}
