use gpui_kit::assets::IconName;
use gpui_kit::component::Icon;
use gpui_kit::component::button::{Button, ButtonVariants};
use gpui_kit::prelude::FluentBuilder;
use gpui_kit::*;
use std::sync::Arc;

/// Performance Mode Row matching minflair PerformanceWidget.qml:
/// Clean horizontal row with label on the left (Performance Mode / Maximum system performance)
/// and a compact dropdown/selector pill on the right.
pub fn render_performance_row(
    active_power_profile: &str,
    on_profile: Option<Arc<dyn Fn(String) + Send + Sync>>,
) -> impl IntoElement {
    let description = match active_power_profile {
        "performance" => "Maximum system performance",
        "power-saver" => "Limits CPU and saves battery",
        _ => "Standard balanced profile",
    };

    let next_profile = match active_power_profile {
        "power-saver" => "balanced",
        "balanced" => "performance",
        _ => "power-saver",
    };

    let display_label = match active_power_profile {
        "power-saver" => "Saver",
        "performance" => "Performance",
        _ => "Balanced",
    };

    let on_p = on_profile.clone();
    let next_str = next_profile.to_string();

    div()
        .p(px(10.0))
        .rounded(px(12.0))
        .bg(beskar_theme::Theme::surface())
        .border_1()
        .border_color(beskar_theme::Theme::border())
        .flex()
        .items_center()
        .justify_between()
        .w_full()
        .child(
            div()
                .flex()
                .flex_col()
                .gap(px(1.0))
                .child(
                    div()
                        .text_xs()
                        .font_weight(FontWeight::BOLD)
                        .text_color(beskar_theme::Theme::fg())
                        .child("Performance Mode"),
                )
                .child(
                    div()
                        .text_xs()
                        .text_color(beskar_theme::Theme::foreground_muted())
                        .child(description),
                ),
        )
        .child(
            Button::new("perf-mode-btn")
                .secondary()
                .compact()
                .label(display_label)
                .icon(Icon::new(IconName::Zap).size(px(12.0)))
                .when_some(on_p, move |btn, cb| {
                    btn.on_click(move |_, _, _| (cb)(next_str.clone()))
                }),
        )
}

pub fn render_power_profiles(
    active_power_profile: &str,
    on_profile: Option<Arc<dyn Fn(String) + Send + Sync>>,
) -> impl IntoElement {
    render_performance_row(active_power_profile, on_profile)
}

pub fn render_battery_card(battery_percent: u8, is_charging: bool) -> impl IntoElement {
    div()
        .p(px(10.0))
        .rounded(px(12.0))
        .bg(beskar_theme::Theme::surface())
        .border_1()
        .border_color(beskar_theme::Theme::border())
        .flex()
        .items_center()
        .justify_between()
        .child(
            div()
                .flex()
                .items_center()
                .gap(px(8.0))
                .child(
                    Icon::new(if is_charging {
                        IconName::BatteryCharging
                    } else {
                        IconName::Battery
                    })
                    .size(px(14.0))
                    .text_color(beskar_theme::Theme::accent()),
                )
                .child(
                    div()
                        .text_xs()
                        .font_weight(FontWeight::MEDIUM)
                        .text_color(beskar_theme::Theme::fg())
                        .child("Battery Level"),
                ),
        )
        .child(
            div()
                .text_xs()
                .font_weight(FontWeight::BOLD)
                .text_color(beskar_theme::Theme::fg())
                .child(format!("{}%", battery_percent)),
        )
}
