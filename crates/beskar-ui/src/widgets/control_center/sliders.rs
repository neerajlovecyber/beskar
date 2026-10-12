use gpui_kit::assets::IconName;
use gpui_kit::component::button::{Button, ButtonVariants};
use gpui_kit::component::slider::{Slider, SliderState};
use gpui_kit::component::tag::Tag;
use gpui_kit::component::Icon;
use gpui_kit::prelude::FluentBuilder;
use gpui_kit::*;
use std::sync::Arc;

pub fn render_volume_card(
    volume_percent: u8,
    is_muted: bool,
    volume_slider: Option<&Entity<SliderState>>,
    on_mute: Option<Arc<dyn Fn() + Send + Sync>>,
) -> impl IntoElement {
    div()
        .p(px(12.0))
        .rounded(px(14.0))
        .bg(beskar_theme::Theme::glass_fill(0.04))
        .border_1()
        .border_color(beskar_theme::Theme::subtle_border())
        .flex()
        .flex_col()
        .gap(px(8.0))
        .child(
            div()
                .flex()
                .items_center()
                .justify_between()
                .child(
                    div()
                        .flex()
                        .items_center()
                        .gap(px(6.0))
                        .child(
                            Button::new("cc-vol-mute")
                                .ghost()
                                .compact()
                                .icon(
                                    Icon::new(if is_muted {
                                        IconName::VolumeX
                                    } else {
                                        IconName::Volume2
                                    })
                                    .size(px(14.0))
                                    .text_color(beskar_theme::Theme::fg()),
                                )
                                .when_some(on_mute, |btn, cb| {
                                    btn.on_click(move |_, _, _| (cb)())
                                }),
                        )
                        .child(
                            div()
                                .text_xs()
                                .font_weight(FontWeight::MEDIUM)
                                .text_color(beskar_theme::Theme::fg())
                                .child("Master Volume"),
                        ),
                )
                .child(Tag::secondary().child(format!("{}%", volume_percent))),
        )
        .child(if let Some(slider) = volume_slider {
            div()
                .w_full()
                .px(px(2.0))
                .child(Slider::new(slider).w_full())
                .into_any_element()
        } else {
            div()
                .relative()
                .w_full()
                .h(px(8.0))
                .rounded_full()
                .bg(beskar_theme::Theme::glass_fill(0.10))
                .overflow_hidden()
                .child(
                    div()
                        .h_full()
                        .w(relative(volume_percent as f32 / 100.0))
                        .rounded_full()
                        .bg(if is_muted {
                            beskar_theme::Theme::muted()
                        } else {
                            beskar_theme::Theme::accent()
                        }),
                )
                .into_any_element()
        })
}

pub fn render_brightness_card(
    brightness_percent: u8,
    brightness_slider: Option<&Entity<SliderState>>,
) -> impl IntoElement {
    div()
        .p(px(12.0))
        .rounded(px(14.0))
        .bg(beskar_theme::Theme::glass_fill(0.04))
        .border_1()
        .border_color(beskar_theme::Theme::subtle_border())
        .flex()
        .flex_col()
        .gap(px(10.0))
        .child(
            div()
                .flex()
                .items_center()
                .justify_between()
                .child(
                    div()
                        .flex()
                        .items_center()
                        .gap(px(6.0))
                        .child(
                            Icon::new(IconName::Sun)
                                .size(px(14.0))
                                .text_color(beskar_theme::Theme::accent()),
                        )
                        .child(
                            div()
                                .text_xs()
                                .font_weight(FontWeight::MEDIUM)
                                .text_color(beskar_theme::Theme::fg())
                                .child("Display Brightness"),
                        ),
                )
                .child(Tag::secondary().child(format!("{}%", brightness_percent))),
        )
        .child(if let Some(slider) = brightness_slider {
            div()
                .w_full()
                .px(px(2.0))
                .child(Slider::new(slider).w_full())
                .into_any_element()
        } else {
            div()
                .relative()
                .w_full()
                .h(px(8.0))
                .rounded_full()
                .bg(beskar_theme::Theme::glass_fill(0.10))
                .overflow_hidden()
                .child(
                    div()
                        .h_full()
                        .w(relative(brightness_percent as f32 / 100.0))
                        .rounded_full()
                        .bg(beskar_theme::Theme::accent()),
                )
                .into_any_element()
        })
}
