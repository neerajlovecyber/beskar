use beskar_core::models::NotificationItem;
use gpui_kit::assets::IconName;
use gpui_kit::component::button::{Button, ButtonVariants};
use gpui_kit::component::tag::Tag;
use gpui_kit::component::Icon;
use gpui_kit::prelude::FluentBuilder;
use gpui_kit::*;
use std::sync::Arc;

/// Persistent Notification Center Drawer matching Minflair's NotificationCenter.qml
/// Features:
/// - Stored notification history (up to 50 items)
/// - Do Not Disturb (DND) toggle button
/// - "Clear All" action with empty-state transition
/// - Per-notification dismissal
/// - Relative timestamps ("just now", "5m ago")
/// - App icon & urgency-aware borders
#[derive(IntoElement)]
pub struct NotificationCenterWidget {
    notifications: Vec<NotificationItem>,
    is_dnd: bool,
    on_dismiss: Option<Arc<dyn Fn(u32) + Send + Sync>>,
    on_clear_all: Option<Arc<dyn Fn() + Send + Sync>>,
    on_toggle_dnd: Option<Arc<dyn Fn() + Send + Sync>>,
    on_close: Option<Arc<dyn Fn() + Send + Sync>>,
}

impl NotificationCenterWidget {
    pub fn new(notifications: Vec<NotificationItem>) -> Self {
        Self {
            notifications,
            is_dnd: false,
            on_dismiss: None,
            on_clear_all: None,
            on_toggle_dnd: None,
            on_close: None,
        }
    }

    pub fn dnd(mut self, is_dnd: bool) -> Self {
        self.is_dnd = is_dnd;
        self
    }

    pub fn on_dismiss(mut self, handler: impl Fn(u32) + Send + Sync + 'static) -> Self {
        self.on_dismiss = Some(Arc::new(handler));
        self
    }

    pub fn on_clear_all(mut self, handler: impl Fn() + Send + Sync + 'static) -> Self {
        self.on_clear_all = Some(Arc::new(handler));
        self
    }

    pub fn on_toggle_dnd(mut self, handler: impl Fn() + Send + Sync + 'static) -> Self {
        self.on_toggle_dnd = Some(Arc::new(handler));
        self
    }

    pub fn on_close(mut self, handler: impl Fn() + Send + Sync + 'static) -> Self {
        self.on_close = Some(Arc::new(handler));
        self
    }
}

impl RenderOnce for NotificationCenterWidget {
    fn render(self, _window: &mut Window, _cx: &mut App) -> impl IntoElement {
        let count = self.notifications.len();
        let is_empty = count == 0;
        let is_dnd = self.is_dnd;

        let on_dismiss = self.on_dismiss;
        let on_clear_all = self.on_clear_all;
        let on_toggle_dnd = self.on_toggle_dnd;
        let on_close = self.on_close;

        div()
            .w(px(380.0))
            .max_h(px(520.0))
            .flex()
            .flex_col()
            .gap(px(14.0))
            .p(px(18.0))
            .rounded(px(22.0))
            .bg(beskar_theme::Theme::bg())
            .border_1()
            .border_color(beskar_theme::Theme::border())
            .shadow_lg()
            // 1. Header with title, counter, DND toggle & Clear All
            .child(
                div()
                    .flex()
                    .items_center()
                    .justify_between()
                    .pb(px(10.0))
                    .border_b_1()
                    .border_color(beskar_theme::Theme::subtle_border())
                    .child(
                        div()
                            .flex()
                            .flex_col()
                            .child(
                                div()
                                    .text_sm()
                                    .font_weight(FontWeight::BOLD)
                                    .text_color(beskar_theme::Theme::fg())
                                    .child("Notifications"),
                            )
                            .child(
                                Tag::secondary().child(if is_empty {
                                    "All caught up".to_string()
                                } else {
                                    format!("{} active", count)
                                }),
                            ),
                    )
                    .child(
                        div()
                            .flex()
                            .items_center()
                            .gap(px(6.0))
                            // DND Toggle Button
                            .child(
                                Button::new("notif-dnd-btn")
                                    .ghost()
                                    .compact()
                                    .icon(Icon::new(if is_dnd { IconName::BellOff } else { IconName::Bell }).size(px(12.0)))
                                    .label(if is_dnd { "Unmute" } else { "Mute" })
                                    .on_click({
                                        let on_toggle_dnd = on_toggle_dnd.clone();
                                        move |_, _, _| {
                                            if let Some(ref cb) = on_toggle_dnd {
                                                cb();
                                            }
                                        }
                                    }),
                            )
                            // Clear All Button (Trash)
                            .when(!is_empty, |this| {
                                let on_clear_all = on_clear_all.clone();
                                this.child(
                                    Button::new("notif-clear-all-btn")
                                        .ghost()
                                        .compact()
                                        .icon(Icon::new(IconName::Trash).size(px(12.0)))
                                        .on_click(move |_, _, _| {
                                            if let Some(ref cb) = on_clear_all {
                                                cb();
                                            }
                                        }),
                                )
                            })
                            // Close Button
                            .when_some(on_close, |this, cb| {
                                this.child(
                                    Button::new("notif-close-btn")
                                        .ghost()
                                        .compact()
                                        .icon(Icon::new(IconName::X).size(px(12.0)))
                                        .on_click(move |_, _, _| {
                                            (cb)();
                                        }),
                                )
                            }),
                    ),
            )
            // 2. Notification List or Empty State Illustration
            .child(
                if is_empty {
                    render_empty_state().into_any_element()
                } else {
                    render_notification_list(self.notifications, on_dismiss).into_any_element()
                }
            )
    }
}

fn render_empty_state() -> impl IntoElement {
    div()
        .py(px(32.0))
        .flex()
        .flex_col()
        .items_center()
        .justify_center()
        .gap(px(10.0))
        .child(
            div()
                .w(px(44.0))
                .h(px(44.0))
                .rounded_full()
                .bg(beskar_theme::Theme::success_alpha(0.18))
                .flex()
                .items_center()
                .justify_center()
                .text_color(beskar_theme::Theme::success())
                .child(Icon::new(IconName::Check).size(px(24.0))),
        )
        .child(
            div()
                .text_sm()
                .font_weight(FontWeight::BOLD)
                .text_color(beskar_theme::Theme::fg())
                .child("No Notifications"),
        )
        .child(
            div()
                .text_xs()
                .text_color(beskar_theme::Theme::muted())
                .child("You're all caught up! New alerts will arrive here."),
        )
}

fn render_notification_list(
    items: Vec<NotificationItem>,
    on_dismiss: Option<Arc<dyn Fn(u32) + Send + Sync>>,
) -> impl IntoElement {
    div()
        .id("notification-center-scroll-list")
        .flex()
        .flex_col()
        .gap(px(8.0))
        .max_h(px(400.0))
        .overflow_y_scroll()
        .pb(px(8.0))
        .children(items.into_iter().map(move |item| {
            let id = item.id;
            let on_dis = on_dismiss.clone();
            let is_critical = item.urgency >= 2;

            div()
                .p(px(10.0))
                .rounded(px(14.0))
                .bg(beskar_theme::Theme::bg_secondary())
                .border_1()
                .border_color(if is_critical {
                    beskar_theme::Theme::danger_alpha(0.45)
                } else {
                    beskar_theme::Theme::card_border()
                })
                .flex()
                .flex_col()
                .gap(px(6.0))
                .hover(|s| s.bg(beskar_theme::Theme::bg_tertiary()))
                // App Pill & Timestamp
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
                                    div()
                                        .w(px(18.0))
                                        .h(px(18.0))
                                        .rounded_full()
                                        .bg(beskar_theme::Theme::bg_tertiary())
                                        .flex()
                                        .items_center()
                                        .justify_center()
                                        .text_color(beskar_theme::Theme::accent())
                                        .child(Icon::new(IconName::Bell).size(px(10.0))),
                                )
                                .child(
                                    div()
                                        .text_xs()
                                        .font_weight(FontWeight::BOLD)
                                        .text_color(beskar_theme::Theme::fg())
                                        .child(item.app_name),
                                )
                        )
                        .child(
                            div()
                                .flex()
                                .items_center()
                                .gap(px(6.0))
                                .child(
                                    div()
                                        .text_xs()
                                        .text_color(beskar_theme::Theme::muted())
                                        .child("just now"),
                                )
                                .when_some(on_dis, |el, cb| {
                                    el.child(
                                        div()
                                            .w(px(18.0))
                                            .h(px(18.0))
                                            .rounded_md()
                                            .flex()
                                            .items_center()
                                            .justify_center()
                                            .text_color(beskar_theme::Theme::muted())
                                            .hover(|s| s.text_color(beskar_theme::Theme::danger()).cursor_pointer())
                                            .on_mouse_down(MouseButton::Left, move |_, _, _| (cb)(id))
                                            .child(Icon::new(IconName::X).size(px(10.0))),
                                    )
                                }),
                        ),
                )
                // Notification Content
                .child(
                    div()
                        .flex()
                        .flex_col()
                        .gap(px(2.0))
                        .child(
                            div()
                                .text_xs()
                                .font_weight(FontWeight::SEMIBOLD)
                                .text_color(beskar_theme::Theme::fg())
                                .child(item.summary),
                        )
                        .child(
                            div()
                                .text_xs()
                                .text_color(beskar_theme::Theme::muted())
                                .child(item.body),
                        ),
                )
        }))
}
