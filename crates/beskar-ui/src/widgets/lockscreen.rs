use gpui_kit::prelude::FluentBuilder;
use gpui_kit::*;
use std::sync::Arc;

/// Premium fullscreen PAM desktop lock screen overlay.
/// Features atmospheric clock, date, user session profile, and password authentication.
#[derive(IntoElement)]
pub struct LockScreenWidget {
    user_name: String,
    time_str: String,
    date_str: String,
    password_len: usize,
    has_error: bool,
    on_unlock_attempt: Option<Arc<dyn Fn(String) + Send + Sync>>,
    on_cancel: Option<Arc<dyn Fn() + Send + Sync>>,
}

impl LockScreenWidget {
    pub fn new(
        user_name: impl Into<String>,
        time_str: impl Into<String>,
        date_str: impl Into<String>,
    ) -> Self {
        Self {
            user_name: user_name.into(),
            time_str: time_str.into(),
            date_str: date_str.into(),
            password_len: 0,
            has_error: false,
            on_unlock_attempt: None,
            on_cancel: None,
        }
    }

    pub fn password_len(mut self, len: usize) -> Self {
        self.password_len = len;
        self
    }

    pub fn error(mut self, error: bool) -> Self {
        self.has_error = error;
        self
    }

    pub fn on_unlock_attempt(
        mut self,
        handler: impl Fn(String) + Send + Sync + 'static,
    ) -> Self {
        self.on_unlock_attempt = Some(Arc::new(handler));
        self
    }

    pub fn on_cancel(mut self, handler: impl Fn() + Send + Sync + 'static) -> Self {
        self.on_cancel = Some(Arc::new(handler));
        self
    }
}

impl RenderOnce for LockScreenWidget {
    fn render(self, _window: &mut Window, _cx: &mut App) -> impl IntoElement {
        let on_unlock = self.on_unlock_attempt.clone();
        let on_cancel = self.on_cancel.clone();

        let masked_dots = "•".repeat(self.password_len.max(1));

        div()
            .size_full()
            .flex()
            .flex_col()
            .items_center()
            .justify_center()
            // Deep obsidian atmospheric acrylic backdrop
            .bg(hsla(220.0 / 360.0, 0.25, 0.05, 0.95))
            // Clock & Date Section
            .child(
                div()
                    .flex()
                    .flex_col()
                    .items_center()
                    .mb(px(48.0))
                    .child(
                        div()
                            .text_size(px(72.0))
                            .line_height(relative(1.0))
                            .font_weight(FontWeight::BOLD)
                            .text_color(hsla(0.0, 0.0, 1.0, 0.95))
                            .child(self.time_str),
                    )
                    .child(
                        div()
                            .mt(px(8.0))
                            .text_base()
                            .font_weight(FontWeight::MEDIUM)
                            .text_color(hsla(215.0 / 360.0, 0.30, 0.70, 0.85))
                            .child(self.date_str),
                    ),
            )
            // Profile & Password Card
            .child(
                div()
                    .w(px(320.0))
                    .flex()
                    .flex_col()
                    .items_center()
                    .p(px(24.0))
                    .rounded(px(20.0))
                    .bg(hsla(220.0 / 360.0, 0.20, 0.10, 0.80))
                    .border_1()
                    .border_color(if self.has_error {
                        hsla(0.0, 0.75, 0.55, 0.60)
                    } else {
                        hsla(0.0, 0.0, 1.0, 0.12)
                    })
                    .shadow_xl()
                    // User Avatar
                    .child(
                        div()
                            .size(px(64.0))
                            .rounded_full()
                            .flex()
                            .items_center()
                            .justify_center()
                            .bg(hsla(215.0 / 360.0, 0.60, 0.35, 0.40))
                            .border_2()
                            .border_color(hsla(215.0 / 360.0, 0.80, 0.65, 0.60))
                            .text_2xl()
                            .font_weight(FontWeight::BOLD)
                            .text_color(hsla(0.0, 0.0, 1.0, 0.95))
                            .mb(px(12.0))
                            .child(
                                self.user_name
                                    .chars()
                                    .next()
                                    .unwrap_or('U')
                                    .to_uppercase()
                                    .to_string(),
                            ),
                    )
                    // Username
                    .child(
                        div()
                            .text_base()
                            .font_weight(FontWeight::SEMIBOLD)
                            .text_color(hsla(0.0, 0.0, 0.95, 1.0))
                            .mb(px(16.0))
                            .child(self.user_name),
                    )
                    // Password input field pill
                    .child(
                        div()
                            .w_full()
                            .h(px(40.0))
                            .px(px(14.0))
                            .rounded(px(12.0))
                            .flex()
                            .items_center()
                            .justify_between()
                            .bg(hsla(0.0, 0.0, 0.0, 0.40))
                            .border_1()
                            .border_color(if self.has_error {
                                hsla(0.0, 0.75, 0.55, 0.60)
                            } else {
                                hsla(0.0, 0.0, 1.0, 0.15)
                            })
                            .child(
                                div()
                                    .text_sm()
                                    .text_color(if self.password_len > 0 {
                                        hsla(0.0, 0.0, 1.0, 0.90)
                                    } else {
                                        hsla(0.0, 0.0, 0.45, 0.80)
                                    })
                                    .child(if self.password_len > 0 {
                                        masked_dots
                                    } else {
                                        "Enter password...".to_string()
                                    }),
                            )
                            // Submit arrow button
                            .child(
                                div()
                                    .size(px(26.0))
                                    .rounded(px(8.0))
                                    .flex()
                                    .items_center()
                                    .justify_center()
                                    .bg(hsla(215.0 / 360.0, 0.60, 0.45, 0.50))
                                    .text_xs()
                                    .font_weight(FontWeight::BOLD)
                                    .text_color(hsla(0.0, 0.0, 1.0, 1.0))
                                    .hover(|s| {
                                        s.bg(hsla(215.0 / 360.0, 0.70, 0.55, 0.70))
                                            .cursor_pointer()
                                    })
                                    .on_mouse_down(MouseButton::Left, move |_, _, _| {
                                        if let Some(handler) = on_unlock.as_ref() {
                                            handler(String::new());
                                        }
                                    })
                                    .child("→"),
                            ),
                    )
                    // Error message if authentication failed
                    .when(self.has_error, |this| {
                        this.child(
                            div()
                                .mt(px(8.0))
                                .text_xs()
                                .font_weight(FontWeight::MEDIUM)
                                .text_color(hsla(0.0, 0.85, 0.70, 1.0))
                                .child("Incorrect password, please try again"),
                        )
                    })
                    // Cancel / dismiss button
                    .child(
                        div()
                            .mt(px(16.0))
                            .text_xs()
                            .text_color(hsla(0.0, 0.0, 0.55, 0.80))
                            .hover(|s| {
                                s.text_color(hsla(0.0, 0.0, 0.85, 1.0))
                                    .cursor_pointer()
                            })
                            .on_mouse_down(MouseButton::Left, move |_, _, _| {
                                if let Some(handler) = on_cancel.as_ref() {
                                    handler();
                                }
                            })
                            .child("Cancel"),
                    ),
            )
    }
}
