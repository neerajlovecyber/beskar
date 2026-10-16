//! Audio Output Satellite Detail Widget
//! Ported directly from `references/capsule/crates/app/src/capsule/widgets/dashboard/details/audio.rs`.

use beskar_services::AudioSinkItem;
use gpui_kit::assets::IconName;
use gpui_kit::component::Icon;
use gpui_kit::prelude::FluentBuilder;
use gpui_kit::*;
use std::sync::Arc;

pub const WIDTH: f32 = 320.0;
pub const HEIGHT: f32 = 300.0;

#[derive(IntoElement)]
pub struct AudioDetailWidget {
    sinks: Vec<AudioSinkItem>,
    volume_percent: u8,
    is_muted: bool,
    on_select_sink: Option<Arc<dyn Fn(String) + Send + Sync>>,
    on_volume_change: Option<Arc<dyn Fn(u8) + Send + Sync>>,
    on_mute_toggle: Option<Arc<dyn Fn() + Send + Sync>>,
    on_close: Option<Arc<dyn Fn() + Send + Sync>>,
}

impl AudioDetailWidget {
    pub fn new(sinks: Vec<AudioSinkItem>, volume_percent: u8, is_muted: bool) -> Self {
        Self {
            sinks,
            volume_percent,
            is_muted,
            on_select_sink: None,
            on_volume_change: None,
            on_mute_toggle: None,
            on_close: None,
        }
    }

    pub fn on_select_sink(mut self, handler: impl Fn(String) + Send + Sync + 'static) -> Self {
        self.on_select_sink = Some(Arc::new(handler));
        self
    }

    pub fn on_volume_change(mut self, handler: impl Fn(u8) + Send + Sync + 'static) -> Self {
        self.on_volume_change = Some(Arc::new(handler));
        self
    }

    pub fn on_mute_toggle(mut self, handler: impl Fn() + Send + Sync + 'static) -> Self {
        self.on_mute_toggle = Some(Arc::new(handler));
        self
    }

    pub fn on_close(mut self, handler: impl Fn() + Send + Sync + 'static) -> Self {
        self.on_close = Some(Arc::new(handler));
        self
    }
}

impl RenderOnce for AudioDetailWidget {
    fn render(self, _window: &mut Window, _cx: &mut App) -> impl IntoElement {
        let on_sel = self.on_select_sink;
        let on_mute = self.on_mute_toggle;
        let on_cls = self.on_close;

        let mut sink_list = div()
            .id("audio-sink-scroll-list")
            .flex_1()
            .flex()
            .flex_col()
            .gap(px(6.0))
            .overflow_y_scroll();

        if self.sinks.is_empty() {
            sink_list = sink_list.child(
                div()
                    .py(px(16.0))
                    .flex()
                    .items_center()
                    .justify_center()
                    .text_xs()
                    .text_color(beskar_theme::Theme::text_secondary())
                    .child("No audio output sinks available"),
            );
        } else {
            for sink in self.sinks {
                let name = sink.name.clone();
                let is_selected = sink.is_default;
                let desc_lower = sink.description.to_lowercase();
                let icon = if desc_lower.contains("headphone") || desc_lower.contains("headset") {
                    IconName::Headphones
                } else if desc_lower.contains("hdmi") || desc_lower.contains("displayport") {
                    IconName::Tv
                } else {
                    IconName::Volume2
                };

                let on_s = on_sel.clone();
                sink_list = sink_list.child(
                    div()
                        .w_full()
                        .p(px(10.0))
                        .rounded(px(10.0))
                        .flex()
                        .items_center()
                        .gap(px(10.0))
                        .cursor_pointer()
                        .bg(if is_selected {
                            beskar_theme::Theme::accent_alpha(0.18)
                        } else {
                            beskar_theme::Theme::glass_fill(0.04)
                        })
                        .border_1()
                        .border_color(if is_selected {
                            beskar_theme::Theme::accent_alpha(0.40)
                        } else {
                            beskar_theme::Theme::subtle_border()
                        })
                        .hover(|s| s.bg(beskar_theme::Theme::bg_secondary()))
                        .when_some(on_s, move |el, cb| {
                            el.on_mouse_down(MouseButton::Left, move |_, _, _| (cb)(name.clone()))
                        })
                        .child(
                            div()
                                .size(px(28.0))
                                .flex_shrink_0()
                                .rounded_full()
                                .bg(beskar_theme::Theme::bg())
                                .flex()
                                .items_center()
                                .justify_center()
                                .child(
                                    Icon::new(icon)
                                        .size(px(14.0))
                                        .text_color(if is_selected {
                                            beskar_theme::Theme::accent()
                                        } else {
                                            beskar_theme::Theme::text_secondary()
                                        }),
                                ),
                        )
                        .child(
                            div()
                                .flex_1()
                                .min_w_0()
                                .text_xs()
                                .font_weight(if is_selected {
                                    FontWeight::BOLD
                                } else {
                                    FontWeight::NORMAL
                                })
                                .text_color(beskar_theme::Theme::fg())
                                .text_ellipsis()
                                .child(sink.description),
                        ),
                );
            }
        }

        div()
            .w(px(WIDTH))
            .h(px(HEIGHT))
            .flex()
            .flex_col()
            .p(px(16.0))
            .gap(px(12.0))
            .rounded(px(16.0))
            .bg(beskar_theme::Theme::bg_secondary())
            .border_1()
            .border_color(beskar_theme::Theme::subtle_border())
            .overflow_hidden()
            .child(
                div()
                    .h(px(28.0))
                    .flex_shrink_0()
                    .flex()
                    .items_center()
                    .justify_between()
                    .child(
                        div()
                            .flex()
                            .items_center()
                            .gap(px(8.0))
                            .child(
                                Icon::new(IconName::Volume2)
                                    .size(px(16.0))
                                    .text_color(beskar_theme::Theme::accent()),
                            )
                            .child(
                                div()
                                    .text_size(px(13.0))
                                    .font_weight(FontWeight::MEDIUM)
                                    .child("Audio Output"),
                            ),
                    )
                    .when_some(on_cls, |parent, cb| {
                        parent.child(
                            div()
                                .size(px(24.0))
                                .flex()
                                .items_center()
                                .justify_center()
                                .rounded_full()
                                .cursor_pointer()
                                .hover(|s| s.bg(beskar_theme::Theme::bg()))
                                .on_mouse_down(MouseButton::Left, move |_, _, _| (cb)())
                                .child(Icon::new(IconName::X).size(px(14.0))),
                        )
                    }),
            )
            .child(
                div()
                    .flex()
                    .items_center()
                    .justify_between()
                    .p(px(8.0))
                    .rounded(px(10.0))
                    .bg(beskar_theme::Theme::glass_fill(0.04))
                    .child(
                        div()
                            .flex()
                            .items_center()
                            .gap(px(6.0))
                            .cursor_pointer()
                            .when_some(on_mute, |el, cb| {
                                el.on_mouse_down(MouseButton::Left, move |_, _, _| (cb)())
                            })
                            .child(
                                Icon::new(if self.is_muted {
                                    IconName::VolumeX
                                } else {
                                    IconName::Volume2
                                })
                                .size(px(14.0))
                                .text_color(if self.is_muted {
                                    beskar_theme::Theme::danger()
                                } else {
                                    beskar_theme::Theme::fg()
                                }),
                            )
                            .child(
                                div()
                                    .text_xs()
                                    .text_color(beskar_theme::Theme::fg())
                                    .child(if self.is_muted { "Muted" } else { "Unmuted" }),
                            ),
                    )
                    .child(
                        div()
                            .text_xs()
                            .font_weight(FontWeight::BOLD)
                            .text_color(beskar_theme::Theme::accent())
                            .child(format!("{}%", self.volume_percent)),
                    ),
            )
            .child(sink_list)
    }
}
