use beskar_services::{BatteryState, NotificationItem};
use beskar_theme::Theme;
use beskar_ui::widgets::dashboard::{card, CONTROLS, HEADER, SLIDER};
use beskar_ui::widgets::style;
use beskar_ui::{DimensionTracker, Slider};
use gpui_kit::gpui::{
    div, px, svg, AnyElement, App, FontWeight, InteractiveElement, IntoElement,
    MouseDownEvent, ParentElement, StatefulInteractiveElement, Styled, Window,
};
use gpui_kit::prelude::*;
use std::sync::Arc;

pub struct DashboardCallbacks {
    pub on_toggle_wifi: Arc<dyn Fn() + Send + Sync>,
    pub on_toggle_bluetooth: Arc<dyn Fn() + Send + Sync>,
    pub on_toggle_dnd: Arc<dyn Fn() + Send + Sync>,
    pub on_mute: Arc<dyn Fn() + Send + Sync>,
    pub on_clear_notifications: Arc<dyn Fn() + Send + Sync>,
    pub on_remove_notification: Arc<dyn Fn(u32) + Send + Sync>,
    pub on_open_settings: Arc<dyn Fn() + Send + Sync>,
    pub on_media_play_pause: Arc<dyn Fn() + Send + Sync>,
    pub on_media_prev: Arc<dyn Fn() + Send + Sync>,
    pub on_media_next: Arc<dyn Fn() + Send + Sync>,
    pub on_media_seek: Arc<dyn Fn(f64) + Send + Sync>,
}

pub fn render_header(
    date: &str,
    battery: Option<&BatteryState>,
    on_settings: Arc<dyn Fn() + Send + Sync>,
) -> AnyElement {
    let mut header = div()
        .id("dashboard-header")
        .flex()
        .items_center()
        .justify_between()
        .w_full()
        .h(px(HEADER))
        .flex_shrink_0()
        .gap(px(8.0));

    let leading = div()
        .id("dashboard-calendar")
        .min_w_0()
        .text_size(px(12.0))
        .text_color(Theme::foreground_muted())
        .whitespace_nowrap()
        .text_ellipsis()
        .child(date.to_string());

    let mut trailing = div().flex().items_center().gap(px(8.0)).flex_shrink_0();
    if let Some(bat) = battery {
        let is_charging = bat.is_charging;
        let pct = bat.percentage.round() as u32;
        trailing = trailing.child(
            div()
                .flex()
                .items_center()
                .gap(px(4.0))
                .text_size(px(12.0))
                .child(
                    svg()
                        .path(if is_charging {
                            "battery-charging.svg"
                        } else if pct <= 20 {
                            "battery-low.svg"
                        } else {
                            "battery-full.svg"
                        })
                        .size(px(16.0))
                        .text_color(Theme::foreground_muted()),
                )
                .child(format!("{}%", pct)),
        );
    }

    trailing = trailing.child(
        div()
            .id("dashboard-settings")
            .size(px(28.0))
            .flex_shrink_0()
            .rounded_full()
            .bg(style::surface())
            .flex()
            .items_center()
            .justify_center()
            .cursor_pointer()
            .hover(|s| s.bg(style::hover()))
            .on_click(move |_, _, _| on_settings())
            .child(
                svg()
                    .path("settings.svg")
                    .size(px(16.0))
                    .text_color(Theme::foreground()),
            ),
    );

    header = header.child(leading).child(trailing);
    header.into_any_element()
}

pub fn render_connectivity_pill(
    id: &'static str,
    title: &str,
    subtitle: &str,
    icon: &'static str,
    enabled: bool,
    on_toggle: Arc<dyn Fn() + Send + Sync>,
) -> AnyElement {
    let cb = on_toggle.clone();
    div()
        .id(id)
        .w_full()
        .h(px(CONTROLS))
        .flex_shrink_0()
        .rounded(px(18.0))
        .bg(style::surface())
        .px(px(12.0))
        .flex()
        .items_center()
        .gap(px(10.0))
        .cursor_pointer()
        .hover(|s| s.bg(style::hover()))
        .on_click(move |_, _, _| cb())
        .child(
            div()
                .id(format!("{id}-toggle"))
                .size(px(40.0))
                .flex_shrink_0()
                .rounded_full()
                .bg(if enabled {
                    Theme::accent()
                } else {
                    style::background()
                })
                .flex()
                .items_center()
                .justify_center()
                .child(
                    svg()
                        .path(icon)
                        .size(px(20.0))
                        .text_color(if enabled {
                            style::on_accent()
                        } else {
                            Theme::foreground_muted()
                        }),
                ),
        )
        .child(
            div()
                .flex_1()
                .min_w_0()
                .flex()
                .flex_col()
                .gap(px(2.0))
                .child(
                    div()
                        .text_size(px(15.0))
                        .font_weight(FontWeight::MEDIUM)
                        .text_ellipsis()
                        .child(title.to_string()),
                )
                .child(
                    div()
                        .text_size(px(12.0))
                        .text_color(Theme::foreground_muted())
                        .text_ellipsis()
                        .child(subtitle.to_string()),
                ),
        )
        .into_any_element()
}

pub fn render_sound_slider(
    volume: u32,
    is_muted: bool,
    volume_tracker: &DimensionTracker,
    on_mute: Arc<dyn Fn() + Send + Sync>,
    on_mouse_down: impl Fn(&MouseDownEvent, &mut Window, &mut App) + 'static,
) -> AnyElement {
    let fraction = volume as f32 / 100.0;
    let cb_mute = on_mute.clone();

    let slider = Slider::new("dashboard-volume-slider")
        .fraction(fraction)
        .height(32.0)
        .flex_1(true)
        .icon(if is_muted {
            "volume-x.svg"
        } else {
            "volume-2.svg"
        })
        .icon_size(20.0)
        .track_bounds(volume_tracker)
        .track_color(style::background())
        .active_color(if is_muted {
            Theme::foreground_muted()
        } else {
            Theme::accent()
        })
        .on_mouse_down(on_mouse_down);

    card(18.0)
        .id("dashboard-sound")
        .w_full()
        .h(px(SLIDER))
        .flex_shrink_0()
        .px(px(12.0))
        .py(px(10.0))
        .flex()
        .flex_col()
        .gap(px(6.0))
        .child(
            div()
                .h(px(22.0))
                .flex_shrink_0()
                .flex()
                .items_center()
                .justify_between()
                .child(
                    div()
                        .id("dashboard-mute")
                        .text_size(px(16.0))
                        .font_weight(FontWeight::MEDIUM)
                        .cursor_pointer()
                        .on_click(move |_, _, _| cb_mute())
                        .child("Sound"),
                )
                .child(
                    div()
                        .text_size(px(14.0))
                        .text_color(Theme::foreground_muted())
                        .child(format!("{volume}%")),
                ),
        )
        .child(
            div()
                .w_full()
                .h(px(32.0))
                .flex_shrink_0()
                .flex()
                .items_center()
                .gap(px(8.0))
                .child(slider),
        )
        .into_any_element()
}

pub fn render_notifications_section(
    items: &[NotificationItem],
    on_clear: Arc<dyn Fn() + Send + Sync>,
    on_remove: Arc<dyn Fn(u32) + Send + Sync>,
) -> AnyElement {
    let count = items.len();
    let cb_clear = on_clear.clone();

    let header = div()
        .w_full()
        .min_w_0()
        .h(px(32.0))
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
                    div()
                        .text_size(px(14.0))
                        .font_weight(FontWeight::MEDIUM)
                        .child("Notifications"),
                )
                .child(
                    div()
                        .px(px(6.0))
                        .py(px(1.0))
                        .rounded_full()
                        .bg(style::surface())
                        .text_size(px(12.0))
                        .text_color(Theme::foreground_muted())
                        .child(count.to_string()),
                ),
        )
        .when(count > 0, |s| {
            s.child(
                div()
                    .id("dashboard-clear-notifications")
                    .size(px(28.0))
                    .flex_shrink_0()
                    .rounded(px(6.0))
                    .flex()
                    .items_center()
                    .justify_center()
                    .cursor_pointer()
                    .hover(|s| s.bg(style::hover()))
                    .on_click(move |_, _, _| cb_clear())
                    .child(
                        svg()
                            .path("trash.svg")
                            .size(px(16.0))
                            .text_color(Theme::foreground_muted()),
                    ),
            )
        });

    let mut list = div()
        .id("dashboard-notifications-list")
        .flex_1()
        .min_h_0()
        .w_full()
        .min_w_0()
        .max_w_full()
        .overflow_x_hidden()
        .overflow_y_scroll()
        .flex()
        .flex_col()
        .gap(px(6.0));

    if count == 0 {
        list = list.child(
            div()
                .w_full()
                .flex_1()
                .min_h(px(32.0))
                .flex()
                .items_center()
                .justify_center()
                .gap(px(10.0))
                .child(
                    svg()
                        .path("bell.svg")
                        .size(px(18.0))
                        .text_color(Theme::foreground_muted().opacity(0.65)),
                )
                .child(
                    div()
                        .text_size(px(13.0))
                        .text_color(Theme::foreground_muted())
                        .child("No notifications"),
                ),
        );
    }

    for item in items.iter().rev() {
        let id = item.id;
        let cb_rm = on_remove.clone();
        let app_name = if !item.app_name.is_empty() {
            &item.app_name
        } else {
            "Notification"
        };

        list = list.child(
            div()
                .id(format!("dashboard-notification-{}", id))
                .w_full()
                .p(px(8.0))
                .rounded(px(12.0))
                .bg(style::surface())
                .flex()
                .items_center()
                .justify_between()
                .gap(px(8.0))
                .child(
                    div()
                        .flex_1()
                        .min_w_0()
                        .flex()
                        .flex_col()
                        .gap(px(2.0))
                        .child(
                            div()
                                .text_size(px(13.0))
                                .font_weight(FontWeight::MEDIUM)
                                .text_ellipsis()
                                .child(item.summary.clone()),
                        )
                        .child(
                            div()
                                .text_size(px(11.0))
                                .text_color(Theme::foreground_muted())
                                .text_ellipsis()
                                .child(format!("{}: {}", app_name, item.body)),
                        ),
                )
                .child(
                    div()
                        .id(format!("dashboard-notif-close-{}", id))
                        .size(px(22.0))
                        .flex_shrink_0()
                        .rounded_full()
                        .flex()
                        .items_center()
                        .justify_center()
                        .cursor_pointer()
                        .hover(|s| s.bg(style::hover()))
                        .on_click(move |_, _, _| cb_rm(id))
                        .child(
                            svg()
                                .path("close.svg")
                                .size(px(12.0))
                                .text_color(Theme::foreground_muted()),
                        ),
                ),
        );
    }

    div()
        .w_full()
        .h_full()
        .flex()
        .flex_col()
        .gap(px(4.0))
        .child(header)
        .child(list)
        .into_any_element()
}
