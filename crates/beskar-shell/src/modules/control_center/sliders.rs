use gpui_kit::assets::IconName;
use gpui_kit::component::Icon;
use gpui_kit::component::slider::{Slider, SliderState};
use gpui_kit::prelude::FluentBuilder;
use gpui_kit::*;
use std::sync::Arc;

/// Compact Sliders matching minflair QuickSettings.qml:
/// Groups Brightness, Volume, and Mic sliders into a single tight container
/// without bulky individual card borders or headers.
pub fn render_compact_sliders(
    brightness_percent: u8,
    brightness_slider: Option<&Entity<SliderState>>,
    volume_percent: u8,
    is_volume_muted: bool,
    volume_slider: Option<&Entity<SliderState>>,
    on_toggle_volume_mute: Option<Arc<dyn Fn() + Send + Sync>>,
    mic_percent: u8,
    is_mic_muted: bool,
    mic_slider: Option<&Entity<SliderState>>,
    on_toggle_mic_mute: Option<Arc<dyn Fn() + Send + Sync>>,
) -> impl IntoElement {
    div()
        .p(px(10.0))
        .rounded(px(12.0))
        .bg(beskar_theme::Theme::surface())
        .border_1()
        .border_color(beskar_theme::Theme::border())
        .flex()
        .flex_col()
        .gap(px(8.0))
        .w_full()
        // 1. Brightness Slider Row
        .child(render_slider_row(
            IconName::SunMedium,
            brightness_percent,
            false,
            brightness_slider,
            None,
        ))
        // 2. Volume Slider Row
        .child(render_slider_row(
            if is_volume_muted {
                IconName::VolumeX
            } else {
                IconName::Volume2
            },
            volume_percent,
            is_volume_muted,
            volume_slider,
            on_toggle_volume_mute,
        ))
        // 3. Mic Slider Row
        .child(render_slider_row(
            if is_mic_muted {
                IconName::MicOff
            } else {
                IconName::Mic
            },
            mic_percent,
            is_mic_muted,
            mic_slider,
            on_toggle_mic_mute,
        ))
}

fn render_slider_row(
    icon: IconName,
    percent: u8,
    is_muted: bool,
    slider: Option<&Entity<SliderState>>,
    on_toggle_mute: Option<Arc<dyn Fn() + Send + Sync>>,
) -> AnyElement {
    div()
        .flex()
        .items_center()
        .gap(px(8.0))
        .w_full()
        .child(
            div()
                .size(px(26.0))
                .flex_shrink_0()
                .rounded_full()
                .bg(if is_muted {
                    beskar_theme::Theme::bg_secondary()
                } else {
                    beskar_theme::Theme::accent_alpha(0.15)
                })
                .flex()
                .items_center()
                .justify_center()
                .cursor_pointer()
                .when_some(on_toggle_mute, |btn, cb| {
                    btn.on_mouse_down(MouseButton::Left, move |_, _, _| (cb)())
                })
                .child(
                    Icon::new(icon)
                        .size(px(13.0))
                        .text_color(if is_muted {
                            beskar_theme::Theme::foreground_muted()
                        } else {
                            beskar_theme::Theme::accent()
                        }),
                ),
        )
        .child(
            div()
                .flex_1()
                .min_w_0()
                .when_some(slider, |el, s| el.child(Slider::new(s))),
        )
        .child(
            div()
                .w(px(32.0))
                .flex_shrink_0()
                .text_right()
                .text_xs()
                .font_weight(FontWeight::MEDIUM)
                .text_color(if is_muted {
                    beskar_theme::Theme::foreground_muted()
                } else {
                    beskar_theme::Theme::fg()
                })
                .child(if is_muted {
                    "Mute".to_string()
                } else {
                    format!("{}%", percent)
                }),
        )
        .into_any_element()
}
