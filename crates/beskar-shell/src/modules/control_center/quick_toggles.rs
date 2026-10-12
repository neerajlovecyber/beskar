use gpui_kit::assets::IconName;
use gpui_kit::component::button::{Button, ButtonVariants};
use gpui_kit::component::switch::Switch;
use gpui_kit::component::Icon;
use gpui_kit::prelude::FluentBuilder;
use gpui_kit::*;
use std::sync::Arc;

pub fn render_quick_toggles(
    is_wifi_on: bool,
    wifi_label: String,
    show_wifi_list: bool,
    on_wifi: Option<Arc<dyn Fn() + Send + Sync>>,
    on_wifi_list: Option<Arc<dyn Fn() + Send + Sync>>,
    is_bt_on: bool,
    bt_label: &'static str,
    show_bt_list: bool,
    on_bt: Option<Arc<dyn Fn() + Send + Sync>>,
    on_bt_list: Option<Arc<dyn Fn() + Send + Sync>>,
) -> impl IntoElement {
    div()
        .flex()
        .gap(px(10.0))
        // Wi-Fi Tile
        .child(
            div()
                .id("cc-wifi-tile")
                .flex_1()
                .p(px(10.0))
                .rounded(px(14.0))
                .bg(if is_wifi_on {
                    beskar_theme::Theme::accent_alpha(0.18)
                } else {
                    beskar_theme::Theme::glass_fill(0.05)
                })
                .border_1()
                .border_color(if is_wifi_on {
                    beskar_theme::Theme::accent_alpha(0.40)
                } else {
                    beskar_theme::Theme::subtle_border()
                })
                .flex()
                .items_center()
                .justify_between()
                .child(
                    div()
                        .flex()
                        .items_center()
                        .gap(px(8.0))
                        .min_w_0()
                        .cursor_pointer()
                        .when_some(on_wifi.clone(), |el, cb| {
                            el.on_mouse_down(MouseButton::Left, move |_, _, _| (cb)())
                        })
                        .child(
                            div()
                                .w(px(28.0))
                                .h(px(28.0))
                                .flex_shrink_0()
                                .rounded_full()
                                .bg(if is_wifi_on {
                                    beskar_theme::Theme::accent()
                                } else {
                                    beskar_theme::Theme::glass_fill(0.10)
                                })
                                .flex()
                                .items_center()
                                .justify_center()
                                .child(
                                    Icon::new(IconName::Wifi)
                                        .size(px(14.0))
                                        .text_color(if is_wifi_on {
                                            beskar_theme::Theme::glass_dark(0.90)
                                        } else {
                                            beskar_theme::Theme::muted()
                                        }),
                                ),
                        )
                        .child(
                            div()
                                .flex()
                                .flex_col()
                                .min_w_0()
                                .child(
                                    div()
                                        .text_xs()
                                        .font_weight(FontWeight::BOLD)
                                        .text_color(beskar_theme::Theme::fg())
                                        .child("Wi-Fi"),
                                )
                                .child(
                                    div()
                                        .text_xs()
                                        .text_color(beskar_theme::Theme::muted())
                                        .overflow_hidden()
                                        .whitespace_nowrap()
                                        .text_ellipsis()
                                        .child(wifi_label),
                                ),
                        ),
                )
                .child(
                    div()
                        .flex()
                        .items_center()
                        .gap(px(4.0))
                        .flex_shrink_0()
                        .child(
                            Switch::new("cc-wifi-switch")
                                .checked(is_wifi_on)
                                .on_click({
                                    let on_wifi = on_wifi.clone();
                                    move |_, _, _| {
                                        if let Some(cb) = on_wifi.as_ref() {
                                            cb();
                                        }
                                    }
                                }),
                        )
                        .child(
                            Button::new("cc-wifi-chevron")
                                .ghost()
                                .compact()
                                .icon(
                                    Icon::new(if show_wifi_list {
                                        IconName::ChevronUp
                                    } else {
                                        IconName::ChevronDown
                                    })
                                    .size(px(12.0)),
                                )
                                .when_some(on_wifi_list, |btn, cb| {
                                    btn.on_click(move |_, _, _| (cb)())
                                }),
                        ),
                ),
        )
        // Bluetooth Tile
        .child(
            div()
                .id("cc-bt-tile")
                .flex_1()
                .p(px(10.0))
                .rounded(px(14.0))
                .bg(if is_bt_on {
                    beskar_theme::Theme::info_alpha(0.18)
                } else {
                    beskar_theme::Theme::glass_fill(0.05)
                })
                .border_1()
                .border_color(if is_bt_on {
                    beskar_theme::Theme::info_alpha(0.40)
                } else {
                    beskar_theme::Theme::subtle_border()
                })
                .flex()
                .items_center()
                .justify_between()
                .child(
                    div()
                        .flex()
                        .items_center()
                        .gap(px(8.0))
                        .min_w_0()
                        .cursor_pointer()
                        .when_some(on_bt.clone(), |el, cb| {
                            el.on_mouse_down(MouseButton::Left, move |_, _, _| (cb)())
                        })
                        .child(
                            div()
                                .w(px(28.0))
                                .h(px(28.0))
                                .flex_shrink_0()
                                .rounded_full()
                                .bg(if is_bt_on {
                                    beskar_theme::Theme::info()
                                } else {
                                    beskar_theme::Theme::glass_fill(0.10)
                                })
                                .flex()
                                .items_center()
                                .justify_center()
                                .child(
                                    Icon::new(IconName::Bluetooth)
                                        .size(px(14.0))
                                        .text_color(if is_bt_on {
                                            beskar_theme::Theme::fg()
                                        } else {
                                            beskar_theme::Theme::muted()
                                        }),
                                ),
                        )
                        .child(
                            div()
                                .flex()
                                .flex_col()
                                .min_w_0()
                                .child(
                                    div()
                                        .text_xs()
                                        .font_weight(FontWeight::BOLD)
                                        .text_color(beskar_theme::Theme::fg())
                                        .child("Bluetooth"),
                                )
                                .child(
                                    div()
                                        .text_xs()
                                        .text_color(beskar_theme::Theme::muted())
                                        .overflow_hidden()
                                        .whitespace_nowrap()
                                        .text_ellipsis()
                                        .child(bt_label),
                                ),
                        ),
                )
                .child(
                    div()
                        .flex()
                        .items_center()
                        .gap(px(4.0))
                        .flex_shrink_0()
                        .child(
                            Switch::new("cc-bt-switch")
                                .checked(is_bt_on)
                                .on_click({
                                    let on_bt = on_bt.clone();
                                    move |_, _, _| {
                                        if let Some(cb) = on_bt.as_ref() {
                                            cb();
                                        }
                                    }
                                }),
                        )
                        .child(
                            Button::new("cc-bt-chevron")
                                .ghost()
                                .compact()
                                .icon(
                                    Icon::new(if show_bt_list {
                                        IconName::ChevronUp
                                    } else {
                                        IconName::ChevronDown
                                    })
                                    .size(px(12.0)),
                                )
                                .when_some(on_bt_list, |btn, cb| {
                                    btn.on_click(move |_, _, _| (cb)())
                                }),
                        ),
                ),
        )
}
