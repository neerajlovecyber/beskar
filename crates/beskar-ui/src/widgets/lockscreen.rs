use gpui_kit::assets::IconName;
use gpui_kit::component::button::{Button, ButtonVariants};
use gpui_kit::component::tag::Tag;
use gpui_kit::component::Icon;
use gpui_kit::prelude::FluentBuilder;
use gpui_kit::*;
use std::sync::Arc;

/// Premium fullscreen PAM desktop lock screen overlay adapted from Suzuha and Iris.
/// Features atmospheric giant clock, date, user session profile avatar, and interactive password authentication.
#[derive(IntoElement)]
pub struct LockScreenWidget {
    user_name: String,
    time_str: String,
    date_str: String,
    password_len: usize,
    has_error: bool,
    wallpaper_path: Option<String>,
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
            wallpaper_path: None,
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

    pub fn wallpaper(mut self, path: Option<String>) -> Self {
        self.wallpaper_path = path;
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
        let danger_color: gpui_kit::Hsla = beskar_theme::ThemeEngine::current().danger.into();

        let masked_dots = "•".repeat(self.password_len);

        div()
            .relative()
            .size_full()
            .flex()
            .flex_col()
            .items_center()
            .justify_center()
            // Deep obsidian atmospheric acrylic backdrop (darkened by 72% per Suzuha)
            .bg(beskar_theme::Theme::bg())
            // Top lock hint badge (Suzuha style)
            .child(
                div()
                    .absolute()
                    .top(px(40.0))
                    .child(
                        Tag::secondary()
                            .child(Icon::new(IconName::Lock).size(px(12.0)).text_color(beskar_theme::Theme::accent()))
                            .child("Session Locked"),
                    ),
            )
            // Clock & Date Section
            .child(
                div()
                    .flex()
                    .flex_col()
                    .items_center()
                    .mb(px(40.0))
                    .child(
                        div()
                            .text_size(px(80.0))
                            .line_height(relative(1.0))
                            .font_weight(FontWeight::BOLD)
                            .text_color(beskar_theme::Theme::fg())
                            .child(self.time_str),
                    )
                    .child(
                        div()
                            .mt(px(10.0))
                            .text_lg()
                            .font_weight(FontWeight::MEDIUM)
                            .text_color(beskar_theme::Theme::muted())
                            .child(self.date_str),
                    ),
            )
            // Profile & Password Card (Frosted Glass Acrylic)
            .child(
                div()
                    .w(px(340.0))
                    .flex()
                    .flex_col()
                    .items_center()
                    .p(px(28.0))
                    .rounded(px(24.0))
                    .bg(beskar_theme::Theme::bg_secondary())
                    .border_1()
                    .border_color(if self.has_error {
                        beskar_theme::ThemeEngine::current().danger.into()
                    } else {
                        beskar_theme::Theme::border()
                    })
                    .shadow_2xl()
                    // User Session Avatar
                    .child(
                        div()
                            .size(px(68.0))
                            .rounded_full()
                            .flex()
                            .items_center()
                            .justify_center()
                            .bg(beskar_theme::Theme::bg_accent())
                            .border_2()
                            .border_color(beskar_theme::Theme::accent())
                            .text_2xl()
                            .font_weight(FontWeight::BOLD)
                            .text_color(beskar_theme::Theme::fg())
                            .mb(px(14.0))
                            .child(
                                self.user_name
                                    .chars()
                                    .next()
                                    .unwrap_or('U')
                                    .to_uppercase()
                                    .to_string(),
                            ),
                    )
                    // Username Readout
                    .child(
                        div()
                            .text_base()
                            .font_weight(FontWeight::SEMIBOLD)
                            .text_color(beskar_theme::Theme::fg())
                            .mb(px(18.0))
                            .child(self.user_name),
                    )
                    // Password input field capsule
                    .child(
                        div()
                            .w_full()
                            .h(px(44.0))
                            .px(px(16.0))
                            .rounded(px(14.0))
                            .flex()
                            .items_center()
                            .justify_between()
                            .bg(beskar_theme::Theme::glass_dark(0.50))
                            .border_1()
                            .border_color(if self.has_error {
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
                                    } else {
                                        "Type password to unlock...".to_string()
                                    }),
                            )
                            // Submit arrow button
                            .child(
                                Button::new("unlock-submit")
                                    .primary()
                                    .compact()
                                    .label("→")
                                    .when_some(on_unlock, |btn, cb| {
                                        btn.on_click(move |_, _, _| (cb)(String::new()))
                                    }),
                            ),
                    )
                    // Error message if authentication failed
                    .when(self.has_error, |this| {
                        this.child(
                            div()
                                .mt(px(10.0))
                                .text_xs()
                                .font_weight(FontWeight::MEDIUM)
                                .text_color(danger_color)
                                .child("Incorrect password, try again"),
                        )
                    })
                    // Cancel / dismiss button
                    .child(
                        Button::new("unlock-cancel")
                            .ghost()
                            .compact()
                            .label("Cancel")
                            .when_some(on_cancel, |btn, cb| {
                                btn.on_click(move |_, _, _| (cb)())
                            }),
                    ),
            )
            // Bottom hint (Suzuha style)
            .child(
                div()
                    .absolute()
                    .bottom(px(32.0))
                    .text_xs()
                    .text_color(beskar_theme::Theme::muted())
                    .child("Press Enter or arrow to unlock • Escape to clear"),
            )
    }
}
