use gpui_kit::prelude::FluentBuilder;
use gpui_kit::*;
use gpui_kit::assets::IconName;
use gpui_kit::component::Icon;
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
    width: Option<Pixels>,
    on_play_pause: Option<Arc<dyn Fn() + Send + Sync>>,
}

impl DynamicCenterWidget {
    pub fn new(time_str: impl Into<String>) -> Self {
        Self {
            time_str: time_str.into(),
            date_str: None,
            media_title: None,
            media_artist: None,
            is_playing: false,
            width: None,
            on_play_pause: None,
        }
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
}

impl RenderOnce for DynamicCenterWidget {
    fn render(self, _window: &mut Window, _cx: &mut App) -> impl IntoElement {
        let has_media = self.media_title.is_some();
        let on_play_pause = self.on_play_pause;

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
            container = container.w(w);
        }

        container
            // When no media is playing, show subtle date badge next to time
            .when(!has_media && self.date_str.is_some(), |this| {
                this.child(
                    div()
                        .text_xs()
                        .font_weight(FontWeight::MEDIUM)
                        .text_color(hsla(0.0, 0.0, 0.65, 1.0))
                        .child(self.date_str.unwrap_or_default()),
                )
                .child(
                    div()
                        .w(px(3.0))
                        .h(px(3.0))
                        .rounded_full()
                        .bg(hsla(45.0 / 360.0, 0.90, 0.60, 0.80)),
                )
            })
            .child(
                // Time label
                div()
                    .text_xs()
                    .font_weight(FontWeight::BOLD)
                    .text_color(hsla(0.0, 0.0, 0.95, 1.0))
                    .child(self.time_str),
            )
            .when(has_media, |this| {
                let play_icon = if self.is_playing {
                    IconName::Pause
                } else {
                    IconName::Play
                };

                this.child(
                    // Subtle vertical divider hairline
                    div()
                        .w(px(1.0))
                        .h(px(12.0))
                        .bg(hsla(0.0, 0.0, 1.0, 0.20)),
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
                                .h(if self.is_playing { px(7.0) } else { px(3.0) })
                                .rounded(px(1.0))
                                .bg(hsla(185.0 / 360.0, 0.85, 0.60, 0.90)),
                        )
                        .child(
                            div()
                                .w(px(2.0))
                                .h(if self.is_playing { px(12.0) } else { px(4.0) })
                                .rounded(px(1.0))
                                .bg(hsla(185.0 / 360.0, 0.85, 0.60, 0.90)),
                        )
                        .child(
                            div()
                                .w(px(2.0))
                                .h(if self.is_playing { px(8.0) } else { px(3.0) })
                                .rounded(px(1.0))
                                .bg(hsla(185.0 / 360.0, 0.85, 0.60, 0.90)),
                        )
                        .child(
                            div()
                                .w(px(2.0))
                                .h(if self.is_playing { px(10.0) } else { px(5.0) })
                                .rounded(px(1.0))
                                .bg(hsla(185.0 / 360.0, 0.85, 0.60, 0.90)),
                        ),
                )
                .child(
                    // Media indicator with play/pause state
                    div()
                        .flex()
                        .items_center()
                        .gap(px(6.0))
                        .text_xs()
                        .text_color(hsla(0.0, 0.0, 0.85, 1.0))
                        .child(
                            div()
                                .w(px(14.0))
                                .h(px(14.0))
                                .flex()
                                .items_center()
                                .justify_center()
                                .text_color(hsla(185.0 / 360.0, 0.90, 0.60, 1.0))
                                .hover(|style| style.text_color(hsla(185.0 / 360.0, 1.0, 0.75, 1.0)).cursor_pointer())
                                .when_some(on_play_pause, |el, cb| {
                                    el.on_mouse_down(MouseButton::Left, move |_, _, _| (cb)())
                                })
                                .child(Icon::new(play_icon).size(px(11.0))),
                        )

                        .child(
                            div()
                                .max_w(px(240.0))
                                .overflow_hidden()
                                .child(media_text),
                        ),
                )
            })
    }
}
