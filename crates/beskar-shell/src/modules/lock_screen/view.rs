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
    is_checking: bool,
    wallpaper_path: Option<String>,
    battery: Option<beskar_services::BatteryState>,
    media_track: Option<beskar_services::MediaTrack>,
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
            is_checking: false,
            wallpaper_path: None,
            battery: None,
            media_track: None,
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

    pub fn checking(mut self, checking: bool) -> Self {
        self.is_checking = checking;
        self
    }

    pub fn wallpaper(mut self, path: Option<String>) -> Self {
        self.wallpaper_path = path;
        self
    }

    pub fn battery(mut self, battery: Option<beskar_services::BatteryState>) -> Self {
        self.battery = battery;
        self
    }

    pub fn media(mut self, media: Option<beskar_services::MediaTrack>) -> Self {
        self.media_track = media;
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
            // Blurred wallpaper background if available
            .when_some(self.wallpaper_path, |this, path| {
                this.child(
                    div()
                        .absolute()
                        .inset_0()
                        .child(img(path).size_full().object_fit(ObjectFit::Cover))
                        .child(div().absolute().inset_0().bg(gpui_kit::hsla(0.0, 0.0, 0.0, 0.40))),
                )
            })
            // Top right status bar (Battery green badge + Wi-Fi)
            .child(
                div()
                    .absolute()
                    .top(px(32.0))
                    .right(px(40.0))
                    .flex()
                    .items_center()
                    .gap(px(10.0))
                    .when_some(self.battery, |d, bat| {
                        let is_charging = bat.is_charging;
                        let pct = bat.percentage.round() as u32;
                        d.child(
                            div()
                                .flex()
                                .items_center()
                                .gap(px(6.0))
                                .px(px(8.0))
                                .py(px(3.0))
                                .rounded(px(6.0))
                                .bg(beskar_theme::Theme::success_alpha(0.85))
                                .child(
                                    div()
                                        .text_xs()
                                        .font_weight(FontWeight::BOLD)
                                        .text_color(beskar_theme::Theme::bg())
                                        .child(format!("{}%", pct)),
                                )
                                .child(
                                    svg()
                                        .path(if is_charging {
                                            "battery-charging.svg"
                                        } else if pct <= 20 {
                                            "battery-low.svg"
                                        } else {
                                            "battery-full.svg"
                                        })
                                        .size(px(14.0))
                                        .text_color(beskar_theme::Theme::bg()),
                                ),
                        )
                    })
                    .child(
                        Icon::new(IconName::Wifi)
                            .size(px(16.0))
                            .text_color(beskar_theme::Theme::fg()),
                    ),
            )
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
                    .mb(px(20.0))
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
            // Media / Lyrics strip
            .when_some(self.media_track, |d, track| {
                d.child(
                    div()
                        .flex()
                        .items_center()
                        .gap(px(8.0))
                        .mb(px(24.0))
                        .px(px(16.0))
                        .py(px(6.0))
                        .rounded_full()
                        .bg(beskar_theme::Theme::glass_fill(0.12))
                        .border_1()
                        .border_color(beskar_theme::Theme::card_border())
                        .child(
                            Icon::new(IconName::Music)
                                .size(px(13.0))
                                .text_color(beskar_theme::Theme::accent()),
                        )
                        .child(
                            div()
                                .text_xs()
                                .font_weight(FontWeight::MEDIUM)
                                .text_color(beskar_theme::Theme::fg())
                                .child(format!("{} - {}", track.title, track.artist)),
                        ),
                )
            })
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
                                    .label(if self.is_checking { "…" } else { "→" })
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
