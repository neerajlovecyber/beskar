use gpui_kit::assets::IconName;
use gpui_kit::component::Icon;
use gpui_kit::prelude::FluentBuilder;
use gpui_kit::*;
use std::sync::Arc;

pub fn render_quick_toggles(
    is_wifi_on: bool,
    wifi_label: String,
    _show_wifi_list: bool,
    on_wifi: Option<Arc<dyn Fn() + Send + Sync>>,
    on_wifi_list: Option<Arc<dyn Fn() + Send + Sync>>,
    is_bt_on: bool,
    bt_label: &'static str,
    _show_bt_list: bool,
    on_bt: Option<Arc<dyn Fn() + Send + Sync>>,
    on_bt_list: Option<Arc<dyn Fn() + Send + Sync>>,
    is_night_light_on: bool,
    on_night_light: Option<Arc<dyn Fn() + Send + Sync>>,
    is_caffeine_on: bool,
    on_caffeine: Option<Arc<dyn Fn() + Send + Sync>>,
    is_game_mode_on: bool,
    on_game_mode: Option<Arc<dyn Fn() + Send + Sync>>,
    battery_percent: u8,
    is_charging: bool,
) -> impl IntoElement {
    div()
        .flex()
        .flex_col()
        .gap(px(8.0))
        .w_full()
        // Row 1: Wi-Fi & Bluetooth
        .child(
            div()
                .flex()
                .gap(px(8.0))
                .w_full()
                .child(render_toggle_tile(
                    "cc-wifi-tile",
                    IconName::Wifi,
                    "Wi-Fi",
                    &wifi_label,
                    is_wifi_on,
                    on_wifi,
                    on_wifi_list,
                ))
                .child(render_toggle_tile(
                    "cc-bt-tile",
                    IconName::Bluetooth,
                    "Bluetooth",
                    bt_label,
                    is_bt_on,
                    on_bt,
                    on_bt_list,
                )),
        )
        // Row 2: Night Light & Caffeine
        .child(
            div()
                .flex()
                .gap(px(8.0))
                .w_full()
                .child(render_toggle_tile(
                    "cc-night-tile",
                    IconName::Moon,
                    "Night Light",
                    if is_night_light_on { "On" } else { "Off" },
                    is_night_light_on,
                    on_night_light,
                    None,
                ))
                .child(render_toggle_tile(
                    "cc-caffeine-tile",
                    IconName::Coffee,
                    "Caffeine",
                    if is_caffeine_on { "Active" } else { "Off" },
                    is_caffeine_on,
                    on_caffeine,
                    None,
                )),
        )
        // Row 3: Game Mode & Battery
        .child(
            div()
                .flex()
                .gap(px(8.0))
                .w_full()
                .child(render_toggle_tile(
                    "cc-game-tile",
                    IconName::Gamepad2,
                    "Game Mode",
                    if is_game_mode_on { "Enabled" } else { "Off" },
                    is_game_mode_on,
                    on_game_mode,
                    None,
                ))
                .child(render_battery_tile(battery_percent, is_charging)),
        )
}

fn render_toggle_tile(
    id: &'static str,
    icon: IconName,
    title: &'static str,
    subtitle: &str,
    is_active: bool,
    on_toggle: Option<Arc<dyn Fn() + Send + Sync>>,
    on_menu: Option<Arc<dyn Fn() + Send + Sync>>,
) -> AnyElement {
    let has_menu = on_menu.is_some();

    div()
        .id(id)
        .flex_1()
        .min_w_0()
        .h(px(46.0))
        .px(px(8.0))
        .py(px(6.0))
        .rounded(px(12.0))
        .bg(if is_active {
            beskar_theme::Theme::accent_alpha(0.18)
        } else {
            beskar_theme::Theme::surface()
        })
        .border_1()
        .border_color(if is_active {
            beskar_theme::Theme::accent_alpha(0.40)
        } else {
            beskar_theme::Theme::border()
        })
        .flex()
        .items_center()
        .justify_between()
        .child(
            div()
                .flex()
                .items_center()
                .gap(px(6.0))
                .flex_1()
                .min_w_0()
                .cursor_pointer()
                .when_some(on_toggle, |el, cb| {
                    el.on_mouse_down(MouseButton::Left, move |_, _, _| (cb)())
                })
                .child(
                    div()
                        .size(px(26.0))
                        .flex_shrink_0()
                        .rounded_full()
                        .bg(if is_active {
                            beskar_theme::Theme::accent()
                        } else {
                            beskar_theme::Theme::bg_secondary()
                        })
                        .flex()
                        .items_center()
                        .justify_center()
                        .child(
                            Icon::new(icon)
                                .size(px(13.0))
                                .text_color(if is_active {
                                    beskar_theme::Theme::bg()
                                } else {
                                    beskar_theme::Theme::foreground_muted()
                                }),
                        ),
                )
                .child(
                    div()
                        .flex()
                        .flex_col()
                        .flex_1()
                        .min_w_0()
                        .child(
                            div()
                                .text_xs()
                                .font_weight(FontWeight::BOLD)
                                .text_color(beskar_theme::Theme::fg())
                                .overflow_hidden()
                                .whitespace_nowrap()
                                .text_ellipsis()
                                .child(title),
                        )
                        .child(
                            div()
                                .text_xs()
                                .text_color(if is_active {
                                    beskar_theme::Theme::accent()
                                } else {
                                    beskar_theme::Theme::foreground_muted()
                                })
                                .overflow_hidden()
                                .whitespace_nowrap()
                                .text_ellipsis()
                                .child(subtitle.to_string()),
                        ),
                ),
        )
        .when(has_menu, |tile| {
            tile.child(
                div()
                    .p(px(2.0))
                    .rounded_md()
                    .cursor_pointer()
                    .hover(|s| s.bg(beskar_theme::Theme::accent_alpha(0.15)))
                    .when_some(on_menu, |el, cb| {
                        el.on_mouse_down(MouseButton::Left, move |_, _, _| (cb)())
                    })
                    .child(
                        Icon::new(IconName::ChevronRight)
                            .size(px(12.0))
                            .text_color(beskar_theme::Theme::foreground_muted()),
                    ),
            )
        })
        .into_any_element()
}

fn render_battery_tile(battery_percent: u8, is_charging: bool) -> AnyElement {
    let icon = if is_charging {
        IconName::BatteryCharging
    } else if battery_percent > 80 {
        IconName::BatteryFull
    } else if battery_percent > 40 {
        IconName::BatteryMedium
    } else {
        IconName::BatteryLow
    };

    let status_str = if is_charging {
        format!("{}% · Charging", battery_percent)
    } else {
        format!("{}% · Battery", battery_percent)
    };

    div()
        .id("cc-battery-tile")
        .flex_1()
        .min_w_0()
        .h(px(46.0))
        .px(px(8.0))
        .py(px(6.0))
        .rounded(px(12.0))
        .bg(beskar_theme::Theme::surface())
        .border_1()
        .border_color(beskar_theme::Theme::border())
        .flex()
        .items_center()
        .gap(px(6.0))
        .child(
            div()
                .size(px(26.0))
                .flex_shrink_0()
                .rounded_full()
                .bg(if is_charging {
                    beskar_theme::Theme::accent_alpha(0.2)
                } else {
                    beskar_theme::Theme::bg_secondary()
                })
                .flex()
                .items_center()
                .justify_center()
                .child(
                    Icon::new(icon)
                        .size(px(13.0))
                        .text_color(if is_charging {
                            beskar_theme::Theme::accent()
                        } else {
                            beskar_theme::Theme::foreground_muted()
                        }),
                ),
        )
        .child(
            div()
                .flex()
                .flex_col()
                .flex_1()
                .min_w_0()
                .child(
                    div()
                        .text_xs()
                        .font_weight(FontWeight::BOLD)
                        .text_color(beskar_theme::Theme::fg())
                        .child("Battery"),
                )
                .child(
                    div()
                        .text_xs()
                        .text_color(if is_charging {
                            beskar_theme::Theme::accent()
                        } else {
                            beskar_theme::Theme::foreground_muted()
                        })
                        .overflow_hidden()
                        .whitespace_nowrap()
                        .text_ellipsis()
                        .child(status_str),
                ),
        )
        .into_any_element()
}
