use gpui_kit::assets::IconName;
use gpui_kit::component::button::{Button, ButtonVariants};
use gpui_kit::component::Icon;
use gpui_kit::prelude::FluentBuilder;
use gpui_kit::*;
use std::sync::Arc;

/// Dynamic Center Island component adapted from minflair's `IslandCenterPill.qml`
/// and Apple Dynamic Island mechanics.
///
/// Features:
/// - Primary clock readout (e.g. "9:25 AM")
/// - Optional date readout (e.g. "Sat, Oct 10")
/// - Divider hairline
/// - Now Playing media indicator with Lucide Play/Pause icon & interactive click
/// - Dynamic Island pill expansion and status transitions
#[derive(IntoElement)]
pub struct DynamicCenterWidget {
    time_str: String,
    date_str: Option<String>,
    media_title: Option<String>,
    media_artist: Option<String>,
    is_playing: bool,
    notification: Option<(String, String)>,
    width: Option<Pixels>,
    cava_bands: Option<[u8; 4]>,
    on_play_pause: Option<Arc<dyn Fn() + Send + Sync>>,
    on_clock_click: Option<Arc<dyn Fn(&mut Window, &mut App) + Send + Sync>>,
    on_media_click: Option<Arc<dyn Fn(&mut Window, &mut App) + Send + Sync>>,
}

impl DynamicCenterWidget {
    pub fn new(time_str: impl Into<String>) -> Self {
        Self {
            time_str: time_str.into(),
            date_str: None,
            media_title: None,
            media_artist: None,
            is_playing: false,
            notification: None,
            width: None,
            cava_bands: None,
            on_play_pause: None,
            on_clock_click: None,
            on_media_click: None,
        }
    }

    pub fn cava_bands(mut self, bands: [u8; 4]) -> Self {
        self.cava_bands = Some(bands);
        self
    }

    pub fn notification(mut self, notif: Option<(String, String)>) -> Self {
        self.notification = notif;
        self
    }

    pub fn width(mut self, width: Pixels) -> Self {
        self.width = Some(width);
        self
    }

    pub fn date(mut self, date_str: Option<String>) -> Self {
        self.date_str = date_str;
        self
    }

    pub fn media(mut self, title: Option<String>, artist: Option<String>, is_playing: bool) -> Self {
        self.media_title = title;
        self.media_artist = artist;
        self.is_playing = is_playing;
        self
    }

    pub fn on_play_pause(mut self, handler: impl Fn() + Send + Sync + 'static) -> Self {
        self.on_play_pause = Some(Arc::new(handler));
        self
    }

    pub fn on_clock_click(mut self, handler: impl Fn(&mut Window, &mut App) + Send + Sync + 'static) -> Self {
        self.on_clock_click = Some(Arc::new(handler));
        self
    }

    pub fn on_media_click(mut self, handler: impl Fn(&mut Window, &mut App) + Send + Sync + 'static) -> Self {
        self.on_media_click = Some(Arc::new(handler));
        self
    }
}

impl RenderOnce for DynamicCenterWidget {
    fn render(self, _window: &mut Window, _cx: &mut App) -> impl IntoElement {
        let has_media = self.media_title.is_some();
        let has_notification = self.notification.is_some();
        let on_play_pause = self.on_play_pause;
        let on_clock_click = self.on_clock_click;
        let on_media_click = self.on_media_click;

        let media_text = match (&self.media_artist, &self.media_title) {
            (Some(artist), Some(title)) => format!("{} – {}", artist, title),
            (None, Some(title)) => title.clone(),
            _ => String::new(),
        };

        let mut container = div()
            .flex()
            .items_center()
            .justify_center()
            .gap(px(10.0));

        if let Some(w) = self.width {
            container = container.min_w(w);
        }

        let hour = chrono::Local::now().format("%H").to_string().parse::<u32>().unwrap_or(12);
        let is_day = (6..18).contains(&hour);

        // Primary Clock & Date Pill with comfortable, balanced spacing
        let clock_content = div()
            .flex()
            .items_center()
            .gap(px(8.0))
            .px(px(10.0))
            .py(px(3.0))
            .rounded_md()
            .hover(|s| s.bg(beskar_theme::Theme::bg_secondary()).cursor_pointer())
            .when_some(on_clock_click, |el, cb| {
                el.on_mouse_down(MouseButton::Left, move |_, window, cx| (cb)(window, cx))
            })
            .child(
                Icon::new(if is_day { IconName::Sun } else { IconName::Moon })
                    .size(px(13.0))
                    .text_color(if is_day { beskar_theme::Theme::accent() } else { beskar_theme::Theme::info() })
            )
            // When no media is playing, show subtle date badge next to time
            .when(!has_media && self.date_str.is_some(), |this| {
                this.child(
                    div()
                        .text_xs()
                        .font_weight(FontWeight::MEDIUM)
                        .text_color(beskar_theme::Theme::text_secondary())
                        .child(self.date_str.unwrap_or_default()),
                )
                .child(
                    div()
                        .mx(px(3.0))
                        .w(px(3.0))
                        .h(px(3.0))
                        .rounded_full()
                        .bg(beskar_theme::Theme::accent_alpha(0.80)),
                )
            })
            .child(
                // Time label
                div()
                    .text_xs()
                    .font_weight(FontWeight::BOLD)
                    .text_color(beskar_theme::Theme::fg())
                    .child(self.time_str),
            );

        container
            .child(clock_content)
            .when_some(self.notification, |this, (notif_title, notif_body)| {
                this.child(
                    div()
                        .w(px(1.0))
                        .h(px(12.0))
                        .bg(beskar_theme::Theme::subtle_border()),
                )
                .child(
                    div()
                        .flex()
                        .items_center()
                        .gap(px(6.0))
                        .text_xs()
                        .text_color(beskar_theme::Theme::accent())
                        .child(Icon::new(IconName::Bell).size(px(12.0)))
                        .child(
                            div()
                                .font_weight(FontWeight::SEMIBOLD)
                                .text_color(beskar_theme::Theme::fg())
                                .child(notif_title),
                        )
                        .child(
                            div()
                                .max_w(px(180.0))
                                .overflow_hidden()
                                .text_color(beskar_theme::Theme::text_secondary())
                                .child(notif_body),
                        ),
                )
            })
            .when(has_media && !has_notification, |this| {
                let play_icon = if self.is_playing {
                    IconName::Pause
                } else {
                    IconName::Play
                };

                let on_media = on_media_click.clone();

                let (h0, h1, h2, h3) = if let Some([c0, c1, c2, c3]) = self.cava_bands {
                    (
                        (3.0 + (c0 as f32 / 100.0) * 9.0).clamp(3.0, 12.0),
                        (3.0 + (c1 as f32 / 100.0) * 9.0).clamp(3.0, 12.0),
                        (3.0 + (c2 as f32 / 100.0) * 9.0).clamp(3.0, 12.0),
                        (3.0 + (c3 as f32 / 100.0) * 9.0).clamp(3.0, 12.0),
                    )
                } else if self.is_playing {
                    (7.0, 12.0, 8.0, 10.0)
                } else {
                    (3.0, 3.0, 3.0, 3.0)
                };

                this.child(
                    // Subtle vertical divider hairline
                    div()
                        .w(px(1.0))
                        .h(px(12.0))
                        .bg(beskar_theme::Theme::subtle_border()),
                )
                .child(
                    // 4-bar dynamic audio equalizer matching reference screenshot
                    div()
                        .flex()
                        .items_end()
                        .gap(px(2.0))
                        .h(px(12.0))
                        .child(
                            div()
                                .w(px(2.0))
                                .h(px(h0))
                                .rounded(px(1.0))
                                .bg(beskar_theme::Theme::accent()),
                        )
                        .child(
                            div()
                                .w(px(2.0))
                                .h(px(h1))
                                .rounded(px(1.0))
                                .bg(beskar_theme::Theme::accent()),
                        )
                        .child(
                            div()
                                .w(px(2.0))
                                .h(px(h2))
                                .rounded(px(1.0))
                                .bg(beskar_theme::Theme::accent()),
                        )
                        .child(
                            div()
                                .w(px(2.0))
                                .h(px(h3))
                                .rounded(px(1.0))
                                .bg(beskar_theme::Theme::accent()),
                        ),
                )
                .child(
                    // Media indicator with play/pause state
                    div()
                        .flex()
                        .items_center()
                        .gap(px(6.0))
                        .text_xs()
                        .text_color(beskar_theme::Theme::fg())
                        .child(
                            Button::new("dyn-play-pause")
                                .ghost()
                                .compact()
                                .icon(Icon::new(play_icon).size(px(12.0)))
                                .when_some(on_play_pause, |btn, cb| {
                                    btn.on_click(move |_, _, _| (cb)())
                                }),
                        )
                        .child(
                            div()
                                .max_w(px(240.0))
                                .overflow_hidden()
                                .px(px(4.0))
                                .py(px(2.0))
                                .rounded_md()
                                .hover(|s| s.bg(beskar_theme::Theme::bg_secondary()).cursor_pointer())
                                .when_some(on_media, |el, cb| {
                                    el.on_mouse_down(MouseButton::Left, move |_, window, cx| (cb)(window, cx))
                                })
                                .child(media_text),
                        ),
                )
            })
    }
}
