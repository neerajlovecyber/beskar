use beskar_core::models::NotificationItem;
use gpui_kit::assets::IconName;
use gpui_kit::component::button::{Button, ButtonVariants};
use gpui_kit::component::tag::Tag;
use gpui_kit::component::Icon;
use gpui_kit::prelude::FluentBuilder;
use gpui_kit::*;
use std::sync::Arc;

/// Premium glass acrylic notification toast banner.
/// Dropped smoothly from the top bar when applications send desktop notifications.
#[derive(IntoElement)]
pub struct NotificationToastWidget {
    notification: NotificationItem,
    on_dismiss: Option<Arc<dyn Fn(u32) + Send + Sync>>,
    on_invoke: Option<Arc<dyn Fn(u32, String) + Send + Sync>>,
}

impl NotificationToastWidget {
    pub fn new(notification: NotificationItem) -> Self {
        Self {
            notification,
            on_dismiss: None,
            on_invoke: None,
        }
    }

    pub fn on_dismiss(mut self, handler: impl Fn(u32) + Send + Sync + 'static) -> Self {
        self.on_dismiss = Some(Arc::new(handler));
        self
    }

    pub fn on_invoke(
        mut self,
        handler: impl Fn(u32, String) + Send + Sync + 'static,
    ) -> Self {
        self.on_invoke = Some(Arc::new(handler));
        self
    }
}

impl RenderOnce for NotificationToastWidget {
    fn render(self, _window: &mut Window, _cx: &mut App) -> impl IntoElement {
        let notif = self.notification;
        let notif_id = notif.id;
        let on_dismiss = self.on_dismiss.clone();
        let on_invoke = self.on_invoke.clone();

        let is_critical = notif.urgency >= 2;

        div()
            .w(px(360.0))
            .flex()
            .flex_col()
            .p(px(12.0))
            .rounded(px(16.0))
            // Acrylic Glass surface
            .bg(hsla(220.0 / 360.0, 0.22, 0.10, 0.88))
            .border_1()
            .border_color(if is_critical {
                hsla(0.0, 0.75, 0.55, 0.45)
            } else {
                hsla(0.0, 0.0, 1.0, 0.14)
            })
            .shadow_lg()
            // Header: App info + close button
            .child(
                div()
                    .w_full()
                    .flex()
                    .items_center()
                    .justify_between()
                    .mb(px(6.0))
                    .child(
                        div()
                            .flex()
                            .items_center()
                            .gap(px(6.0))
                            // Badge icon
                            .child(
                                div()
                                    .size(px(18.0))
                                    .rounded(px(6.0))
                                    .flex()
                                    .items_center()
                                    .justify_center()
                                    .bg(if is_critical {
                                        hsla(0.0, 0.75, 0.45, 0.40)
                                    } else {
                                        hsla(215.0 / 360.0, 0.50, 0.30, 0.40)
                                    })
                                    .text_xs()
                                    .font_weight(FontWeight::BOLD)
                                    .text_color(if is_critical {
                                        hsla(0.0, 0.90, 0.70, 1.0)
                                    } else {
                                        hsla(215.0 / 360.0, 0.90, 0.70, 1.0)
                                    })
                                    .child(if is_critical { "!" } else { "✦" }),
                            )
                            // App name
                            .child(
                                div()
                                    .text_xs()
                                    .font_weight(FontWeight::BOLD)
                                    .text_color(hsla(220.0 / 360.0, 0.15, 0.80, 1.0))
                                    .child(if notif.app_name.is_empty() {
                                        "Notification".to_string()
                                    } else {
                                        notif.app_name
                                    }),
                            )
                            // Critical badge if applicable
                            .when(is_critical, |this| {
                                this.child(Tag::danger().child("URGENT"))
                            }),
                    )
                    // Close button
                    .child(
                        Button::new(("toast-close", notif_id))
                            .ghost()
                            .compact()
                            .icon(Icon::new(IconName::X).size(px(12.0)))
                            .when_some(on_dismiss, |btn, cb| {
                                btn.on_click(move |_, _, _| (cb)(notif_id))
                            }),
                    ),
            )
            // Summary / Title
            .when(!notif.summary.is_empty(), |this| {
                this.child(
                    div()
                        .w_full()
                        .text_sm()
                        .font_weight(FontWeight::BOLD)
                        .text_color(hsla(0.0, 0.0, 0.98, 1.0))
                        .mb(px(4.0))
                        .child(notif.summary),
                )
            })
            // Body text
            .when(!notif.body.is_empty(), |this| {
                this.child(
                    div()
                        .w_full()
                        .text_xs()
                        .line_height(relative(1.3))
                        .text_color(hsla(220.0 / 360.0, 0.15, 0.75, 0.90))
                        .mb(px(6.0))
                        .child(notif.body),
                )
            })
            // Quick Default Action click area
            .child(
                div()
                    .w_full()
                    .flex()
                    .justify_end()
                    .gap(px(8.0))
                    .mt(px(4.0))
                    .child(
                        Button::new(("toast-open", notif_id))
                            .primary()
                            .compact()
                            .label("Open")
                            .when_some(on_invoke, |btn, cb| {
                                btn.on_click(move |_, _, _| {
                                    (cb)(notif_id, "default".to_string())
                                })
                            }),
                    ),
            )
    }
}
