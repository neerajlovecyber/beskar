use beskar_services::WifiAccessPoint;
use gpui_kit::assets::IconName;
use gpui_kit::component::button::{Button, ButtonVariants};
use gpui_kit::component::tag::Tag;
use gpui_kit::component::Icon;
use gpui_kit::prelude::FluentBuilder;
use gpui_kit::*;
use std::sync::Arc;

pub fn render_wifi_list(
    wifi_networks: &[WifiAccessPoint],
    on_connect: Option<Arc<dyn Fn(String) + Send + Sync>>,
) -> impl IntoElement {
    div()
        .p(px(10.0))
        .rounded(px(12.0))
        .bg(beskar_theme::Theme::glass_fill(0.05))
        .border_1()
        .border_color(beskar_theme::Theme::subtle_border())
        .flex()
        .flex_col()
        .gap(px(6.0))
        .child(
            div()
                .text_xs()
                .font_weight(FontWeight::BOLD)
                .text_color(beskar_theme::Theme::accent())
                .child("Available Wi-Fi Networks"),
        )
        .child(if wifi_networks.is_empty() {
            div()
                .py(px(12.0))
                .flex()
                .items_center()
                .justify_center()
                .child(
                    div()
                        .text_xs()
                        .text_color(beskar_theme::Theme::muted())
                        .child("Scanning networks..."),
                )
                .into_any_element()
        } else {
            div()
                .id("cc-wifi-scroll-list")
                .flex()
                .flex_col()
                .gap(px(4.0))
                .max_h(px(180.0))
                .overflow_y_scroll()
                .children(wifi_networks.iter().enumerate().map(|(idx, ap)| {
                    let ssid_clone = ap.ssid.clone();
                    let on_c = on_connect.clone();
                    Button::new(("cc-wifi-item", idx))
                        .ghost()
                        .w_full()
                        .child(
                            div()
                                .flex()
                                .items_center()
                                .justify_between()
                                .w_full()
                                .child(
                                    div()
                                        .flex()
                                        .items_center()
                                        .gap(px(6.0))
                                        .child(
                                            Icon::new(IconName::Wifi)
                                                .size(px(12.0))
                                                .text_color(if ap.is_active {
                                                    beskar_theme::Theme::success()
                                                } else {
                                                    beskar_theme::Theme::text_secondary()
                                                }),
                                        )
                                        .child(
                                            div()
                                                .text_xs()
                                                .font_weight(if ap.is_active {
                                                    FontWeight::BOLD
                                                } else {
                                                    FontWeight::NORMAL
                                                })
                                                .text_color(beskar_theme::Theme::fg())
                                                .child(ap.ssid.clone()),
                                        ),
                                )
                                .child(Tag::secondary().child(format!("{}%", ap.signal))),
                        )
                        .when_some(on_c, move |btn, cb| {
                            btn.on_click(move |_, _, _| (cb)(ssid_clone.clone()))
                        })
                }))
                .into_any_element()
        })
}
