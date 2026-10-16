use beskar_ui::components::{Button, ButtonSize, ButtonVariant};
use gpui_kit::assets::IconName;
use gpui_kit::component::Icon;
use gpui_kit::prelude::FluentBuilder;
use gpui_kit::*;
use std::sync::Arc;

pub const WIDTH: f32 = 432.0;
pub const MIN_HEIGHT: f32 = 250.0;

/// Polkit authentication prompt dialog widget
#[derive(IntoElement)]
pub struct PolkitWidget {
    user_name: String,
    action_id: String,
    message: String,
    password_len: usize,
    error: Option<String>,
    authenticating: bool,
    on_submit: Option<Arc<dyn Fn() + Send + Sync>>,
    on_cancel: Option<Arc<dyn Fn() + Send + Sync>>,
}

impl PolkitWidget {
    pub fn new(
        user_name: impl Into<String>,
        action_id: impl Into<String>,
        message: impl Into<String>,
    ) -> Self {
        Self {
            user_name: user_name.into(),
            action_id: action_id.into(),
            message: message.into(),
            password_len: 0,
            error: None,
            authenticating: false,
            on_submit: None,
            on_cancel: None,
        }
    }

    pub fn password_len(mut self, len: usize) -> Self {
        self.password_len = len;
        self
    }

    pub fn error(mut self, error: Option<String>) -> Self {
        self.error = error;
        self
    }

    pub fn authenticating(mut self, authenticating: bool) -> Self {
        self.authenticating = authenticating;
        self
    }

    pub fn on_submit(mut self, handler: impl Fn() + Send + Sync + 'static) -> Self {
        self.on_submit = Some(Arc::new(handler));
        self
    }

    pub fn on_cancel(mut self, handler: impl Fn() + Send + Sync + 'static) -> Self {
        self.on_cancel = Some(Arc::new(handler));
        self
    }
}

impl RenderOnce for PolkitWidget {
    fn render(self, _window: &mut Window, _cx: &mut App) -> impl IntoElement {
        let on_submit = self.on_submit.clone();
        let on_cancel = self.on_cancel.clone();
        let danger_color: gpui_kit::Hsla = beskar_theme::ThemeEngine::current().danger.into();
        let masked_dots = "•".repeat(self.password_len);

        div()
            .w(px(WIDTH))
            .p(px(24.0))
            .rounded(px(20.0))
            .bg(beskar_theme::Theme::bg())
            .border_1()
            .border_color(if self.error.is_some() {
                danger_color
            } else {
                beskar_theme::Theme::border()
            })
            .shadow_2xl()
            .flex()
            .flex_col()
            .gap(px(16.0))
            // ── Header: Lock icon & title ──
            .child(
                div()
                    .flex()
                    .items_center()
                    .gap(px(12.0))
                    .child(
                        div()
                            .size(px(36.0))
                            .rounded_full()
                            .bg(beskar_theme::Theme::bg_accent())
                            .border_1()
                            .border_color(beskar_theme::Theme::accent())
                            .flex()
                            .items_center()
                            .justify_center()
                            .child(
                                Icon::new(IconName::Lock)
                                    .size(px(18.0))
                                    .text_color(beskar_theme::Theme::accent()),
                            ),
                    )
                    .child(
                        div()
                            .flex()
                            .flex_col()
                            .child(
                                div()
                                    .text_base()
                                    .font_weight(FontWeight::BOLD)
                                    .text_color(beskar_theme::Theme::fg())
                                    .child("Authentication Required"),
                            )
                            .child(
                                div()
                                    .text_xs()
                                    .text_color(beskar_theme::Theme::muted())
                                    .child(format!("User: {} • {}", self.user_name, self.action_id)),
                            ),
                    ),
            )
            // ── Message explanation ──
            .child(
                div()
                    .p(px(12.0))
                    .rounded(px(10.0))
                    .bg(beskar_theme::Theme::bg_secondary())
                    .border_1()
                    .border_color(beskar_theme::Theme::subtle_border())
                    .text_xs()
                    .line_height(relative(1.4))
                    .text_color(beskar_theme::Theme::fg())
                    .child(if self.message.is_empty() {
                        "Privileged authorization is requested to perform this action.".to_string()
                    } else {
                        self.message
                    }),
            )
            // ── Password input field ──
            .child(
                div()
                    .w_full()
                    .h(px(42.0))
                    .px(px(14.0))
                    .rounded(px(10.0))
                    .flex()
                    .items_center()
                    .justify_between()
                    .bg(beskar_theme::Theme::glass_dark(0.50))
                    .border_1()
                    .border_color(if self.error.is_some() {
                        danger_color
                    } else {
                        beskar_theme::Theme::border()
                    })
                    .child(
                        div()
                            .text_sm()
                            .text_color(if self.password_len > 0 {
                                beskar_theme::Theme::fg()
                            } else {
                                beskar_theme::Theme::muted()
                            })
                            .child(if self.password_len > 0 {
                                masked_dots
                            } else if self.authenticating {
                                "Verifying credentials...".to_string()
                            } else {
                                "Enter password for authentication...".to_string()
                            }),
                    ),
            )
            // ── Error feedback ──
            .when_some(self.error, |d, err| {
                d.child(
                    div()
                        .text_xs()
                        .font_weight(FontWeight::MEDIUM)
                        .text_color(danger_color)
                        .child(err),
                )
            })
            // ── Actions: Cancel & Authenticate ──
            .child(
                div()
                    .flex()
                    .justify_end()
                    .gap(px(10.0))
                    .mt(px(4.0))
                    .child(
                        Button::new("polkit-cancel")
                            .variant(ButtonVariant::Ghost)
                            .size(ButtonSize::Sm)
                            .label("Cancel")
                            .disabled(self.authenticating)
                            .when_some(on_cancel, |btn, cb| {
                                btn.on_click(move |_, _, _| (cb)())
                            }),
                    )
                    .child(
                        Button::new("polkit-authenticate")
                            .variant(ButtonVariant::Primary)
                            .size(ButtonSize::Sm)
                            .label(if self.authenticating { "Checking..." } else { "Authenticate" })
                            .disabled(self.authenticating || self.password_len == 0)
                            .when_some(on_submit, |btn, cb| {
                                btn.on_click(move |_, _, _| (cb)())
                            }),
                    ),
            )
    }
}
