use gpui_kit::assets::IconName;
use gpui_kit::component::button::{Button, ButtonVariants};
use gpui_kit::component::tag::Tag;
use gpui_kit::component::Icon;
use gpui_kit::prelude::FluentBuilder;
use gpui_kit::*;
use std::sync::Arc;

pub fn render_power_profiles(
    active_power_profile: &str,
    on_profile: Option<Arc<dyn Fn(String) + Send + Sync>>,
) -> impl IntoElement {
    div()
        .p(px(10.0))
        .rounded(px(14.0))
        .bg(beskar_theme::Theme::glass_fill(0.04))
        .border_1()
        .border_color(beskar_theme::Theme::subtle_border())
        .flex()
        .flex_col()
        .gap(px(8.0))
        .child(
            div()
                .text_xs()
                .font_weight(FontWeight::MEDIUM)
                .text_color(beskar_theme::Theme::text_secondary())
                .child("Power Profile"),
        )
        .child(
            div()
                .flex()
                .gap(px(6.0))
                .children(["power-saver", "balanced", "performance"].iter().map(|&prof| {
                    let is_active = active_power_profile == prof;
                    let label = match prof {
                        "power-saver" => "Saver",
                        "balanced" => "Balanced",
                        "performance" => "Performance",
                        _ => prof,
                    };
                    let on_p = on_profile.clone();
                    let prof_str = prof.to_string();
                    let btn = Button::new(SharedString::from(format!("prof-{}", prof)))
                        .flex_1()
                        .label(label);
                    let btn = if is_active {
                        btn.primary()
                    } else {
                        btn.ghost()
                    };
                    btn.when_some(on_p, move |b, cb| {
                        b.on_click(move |_, _, _| (cb)(prof_str.clone()))
                    })
                })),
        )
}

pub fn render_battery_card(
    battery_percent: u8,
    is_charging: bool,
) -> impl IntoElement {
    div()
        .p(px(10.0))
        .rounded(px(14.0))
        .bg(beskar_theme::Theme::glass_fill(0.04))
        .border_1()
        .border_color(beskar_theme::Theme::subtle_border())
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
                        IconName::BatteryFull
                    })
                    .size(px(16.0))
                    .text_color(if is_charging {
                        beskar_theme::Theme::success()
                    } else {
                        beskar_theme::Theme::fg()
                    }),
                )
                .child(
                    div()
                        .text_xs()
                        .font_weight(FontWeight::MEDIUM)
                        .text_color(beskar_theme::Theme::fg())
                        .child(if is_charging {
                            "Battery Charging"
                        } else {
                            "Battery Normal"
                        }),
                ),
        )
        .child(if is_charging {
            Tag::primary().child(format!("{}%", battery_percent))
        } else {
            Tag::secondary().child(format!("{}%", battery_percent))
        })
}
