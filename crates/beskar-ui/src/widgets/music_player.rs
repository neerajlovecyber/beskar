use gpui_kit::assets::IconName;
use gpui_kit::component::Icon;
use gpui_kit::prelude::FluentBuilder;
use gpui_kit::*;
use std::sync::Arc;

/// Dedicated Music Player Overlay Widget matching Minflair's MiniMusicWidget.qml
/// Features:
/// - 28-36 animated CAVA audio spectrum frequency bars
/// - Scrubbable seek progress bar with elapsed and total timestamps
/// - Full MPRIS transport controls: Prev, Play/Pause, Next, Loop, Shuffle
/// - Album art container with rounded corners and fallback icon
/// - Track title, artist, and active player source badge
#[derive(IntoElement)]
pub struct MusicPlayerWidget {
    title: String,
    artist: String,
    album: Option<String>,
    player_name: String,
    is_playing: bool,
    position_secs: u32,
    duration_secs: u32,
    cava_bars: Vec<u8>,
    is_looping: bool,
    is_shuffling: bool,
    on_play_pause: Option<Arc<dyn Fn() + Send + Sync>>,
    on_prev: Option<Arc<dyn Fn() + Send + Sync>>,
    on_next: Option<Arc<dyn Fn() + Send + Sync>>,
    on_seek: Option<Arc<dyn Fn(f32) + Send + Sync>>,
    on_toggle_loop: Option<Arc<dyn Fn() + Send + Sync>>,
    on_toggle_shuffle: Option<Arc<dyn Fn() + Send + Sync>>,
    on_close: Option<Arc<dyn Fn() + Send + Sync>>,
}

impl MusicPlayerWidget {
    pub fn new(
        title: impl Into<String>,
        artist: impl Into<String>,
        is_playing: bool,
    ) -> Self {
        Self {
            title: title.into(),
            artist: artist.into(),
            album: None,
            player_name: "Media Player".to_string(),
            is_playing,
            position_secs: 45,
            duration_secs: 215,
            cava_bars: Vec::new(),
            is_looping: false,
            is_shuffling: false,
            on_play_pause: None,
            on_prev: None,
            on_next: None,
            on_seek: None,
            on_toggle_loop: None,
            on_toggle_shuffle: None,
            on_close: None,
        }
    }

    pub fn album(mut self, album: Option<String>) -> Self {
        self.album = album;
        self
    }

    pub fn player_name(mut self, player_name: impl Into<String>) -> Self {
        self.player_name = player_name.into();
        self
    }

    pub fn position(mut self, pos: u32, duration: u32) -> Self {
        self.position_secs = pos;
        self.duration_secs = duration;
        self
    }

    pub fn cava_bars(mut self, bars: Vec<u8>) -> Self {
        self.cava_bars = bars;
        self
    }

    pub fn loop_mode(mut self, is_looping: bool) -> Self {
        self.is_looping = is_looping;
        self
    }

    pub fn shuffle(mut self, is_shuffling: bool) -> Self {
        self.is_shuffling = is_shuffling;
        self
    }

    pub fn on_play_pause(mut self, handler: impl Fn() + Send + Sync + 'static) -> Self {
        self.on_play_pause = Some(Arc::new(handler));
        self
    }

    pub fn on_prev(mut self, handler: impl Fn() + Send + Sync + 'static) -> Self {
        self.on_prev = Some(Arc::new(handler));
        self
    }

    pub fn on_next(mut self, handler: impl Fn() + Send + Sync + 'static) -> Self {
        self.on_next = Some(Arc::new(handler));
        self
    }

    pub fn on_seek(mut self, handler: impl Fn(f32) + Send + Sync + 'static) -> Self {
        self.on_seek = Some(Arc::new(handler));
        self
    }

    pub fn on_toggle_loop(mut self, handler: impl Fn() + Send + Sync + 'static) -> Self {
        self.on_toggle_loop = Some(Arc::new(handler));
        self
    }

    pub fn on_toggle_shuffle(mut self, handler: impl Fn() + Send + Sync + 'static) -> Self {
        self.on_toggle_shuffle = Some(Arc::new(handler));
        self
    }

    pub fn on_close(mut self, handler: impl Fn() + Send + Sync + 'static) -> Self {
        self.on_close = Some(Arc::new(handler));
        self
    }
}

impl RenderOnce for MusicPlayerWidget {
    fn render(self, _window: &mut Window, _cx: &mut App) -> impl IntoElement {
        let title = if self.title.is_empty() { "No track playing".to_string() } else { self.title };
        let artist = if self.artist.is_empty() { "Unknown artist".to_string() } else { self.artist };
        let is_playing = self.is_playing;
        let pos_secs = self.position_secs;
        let dur_secs = if self.duration_secs == 0 { 1 } else { self.duration_secs };
        let progress = (pos_secs as f32 / dur_secs as f32).clamp(0.0, 1.0);

        let on_play_pause = self.on_play_pause;
        let on_prev = self.on_prev;
        let on_next = self.on_next;
        let on_seek = self.on_seek;
        let on_toggle_loop = self.on_toggle_loop;
        let on_toggle_shuffle = self.on_toggle_shuffle;
        let on_close = self.on_close;

        div()
            .w(px(430.0))
            .flex()
            .flex_col()
            .gap(px(12.0))
            .p(px(18.0))
            .rounded(px(22.0))
            .bg(beskar_theme::Theme::bg())
            .border_1()
            .border_color(beskar_theme::Theme::border())
            .shadow_lg()
            // Top: Header with player badge & close button
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
                                    .w(px(20.0))
                                    .h(px(20.0))
                                    .rounded_md()
                                    .bg(hsla(45.0 / 360.0, 0.90, 0.55, 0.20))
                                    .flex()
                                    .items_center()
                                    .justify_center()
                                    .text_color(beskar_theme::Theme::accent())
                                    .child(Icon::new(IconName::Music).size(px(12.0))),
                            )
                            .child(
                                div()
                                    .text_xs()
                                    .font_weight(FontWeight::BOLD)
                                    .text_color(beskar_theme::Theme::accent())
                                    .child(self.player_name),
                            ),
                    )
                    .when_some(on_close, |el, cb| {
                        el.child(
                            div()
                                .w(px(24.0))
                                .h(px(24.0))
                                .rounded_md()
                                .flex()
                                .items_center()
                                .justify_center()
                                .bg(beskar_theme::Theme::bg_secondary())
                                .text_color(beskar_theme::Theme::muted())
                                .hover(|s| s.bg(hsla(0.0, 0.8, 0.5, 0.25)).text_color(hsla(0.0, 0.9, 0.7, 1.0)).cursor_pointer())
                                .on_mouse_down(MouseButton::Left, move |_, _, _| (cb)())
                                .child(Icon::new(IconName::X).size(px(12.0))),
                        )
                    }),
            )
            // Middle: Album Art + Track Info + Live CAVA bars
            .child(
                div()
                    .flex()
                    .gap(px(14.0))
                    // Album art square
                    .child(
                        div()
                            .w(px(72.0))
                            .h(px(72.0))
                            .rounded(px(16.0))
                            .bg(beskar_theme::Theme::bg_secondary())
                            .border_1()
                            .border_color(hsla(0.0, 0.0, 1.0, 0.08))
                            .flex()
                            .items_center()
                            .justify_center()
                            .text_color(beskar_theme::Theme::accent())
                            .child(Icon::new(IconName::Disc).size(px(36.0))),
                    )
                    // Track metadata & live CAVA spectrum
                    .child(
                        div()
                            .flex()
                            .flex_col()
                            .flex_1()
                            .justify_between()
                            .child(
                                div()
                                    .flex()
                                    .flex_col()
                                    .gap(px(2.0))
                                    .child(
                                        div()
                                            .text_sm()
                                            .font_weight(FontWeight::BOLD)
                                            .text_color(beskar_theme::Theme::fg())
                                            .overflow_hidden()
                                            .child(title),
                                    )
                                    .child(
                                        div()
                                            .text_xs()
                                            .text_color(beskar_theme::Theme::muted())
                                            .overflow_hidden()
                                            .child(artist),
                                    ),
                            )
                            // 28-36 CAVA Spectrum Bars
                            .child(render_cava_spectrum(&self.cava_bars, is_playing)),
                    ),
            )
            // Seekable Progress Bar with Elapsed & Total Timestamps
            .child(
                div()
                    .flex()
                    .flex_col()
                    .gap(px(4.0))
                    .pt(px(2.0))
                    .child(
                        render_progress_bar(progress, on_seek)
                    )
                    .child(
                        div()
                            .flex()
                            .items_center()
                            .justify_between()
                            .child(
                                div()
                                    .text_xs()
                                    .text_color(beskar_theme::Theme::muted())
                                    .child(format_time(pos_secs)),
                            )
                            .child(
                                div()
                                    .text_xs()
                                    .text_color(beskar_theme::Theme::muted())
                                    .child(format_time(dur_secs)),
                            ),
                    ),
            )
            // Bottom Transport Controls (Shuffle, Prev, Play/Pause, Next, Loop)
            .child(
                div()
                    .flex()
                    .items_center()
                    .justify_center()
                    .gap(px(14.0))
                    .pt(px(2.0))
                    // Shuffle Button
                    .child(
                        div()
                            .w(px(28.0))
                            .h(px(28.0))
                            .rounded_md()
                            .flex()
                            .items_center()
                            .justify_center()
                            .text_color(if self.is_shuffling { beskar_theme::Theme::accent() } else { beskar_theme::Theme::muted() })
                            .hover(|s| s.bg(beskar_theme::Theme::bg_secondary()).cursor_pointer())
                            .when_some(on_toggle_shuffle, |el, cb| {
                                el.on_mouse_down(MouseButton::Left, move |_, _, _| (cb)())
                            })
                            .child(Icon::new(IconName::Shuffle).size(px(14.0))),
                    )
                    // Previous Track Button
                    .child(
                        div()
                            .w(px(32.0))
                            .h(px(32.0))
                            .rounded_md()
                            .flex()
                            .items_center()
                            .justify_center()
                            .text_color(beskar_theme::Theme::fg())
                            .hover(|s| s.bg(beskar_theme::Theme::bg_secondary()).cursor_pointer())
                            .when_some(on_prev, |el, cb| {
                                el.on_mouse_down(MouseButton::Left, move |_, _, _| (cb)())
                            })
                            .child(Icon::new(IconName::SkipBack).size(px(16.0))),
                    )
                    // Play / Pause Enlarged Pill Button
                    .child(
                        div()
                            .w(px(40.0))
                            .h(px(40.0))
                            .rounded_full()
                            .bg(beskar_theme::Theme::accent())
                            .text_color(hsla(0.0, 0.0, 0.1, 1.0))
                            .flex()
                            .items_center()
                            .justify_center()
                            .hover(|s| s.bg(hsla(45.0 / 360.0, 1.0, 0.65, 1.0)).cursor_pointer())
                            .when_some(on_play_pause, |el, cb| {
                                el.on_mouse_down(MouseButton::Left, move |_, _, _| (cb)())
                            })
                            .child(Icon::new(if is_playing { IconName::Pause } else { IconName::Play }).size(px(18.0))),
                    )
                    // Next Track Button
                    .child(
                        div()
                            .w(px(32.0))
                            .h(px(32.0))
                            .rounded_md()
                            .flex()
                            .items_center()
                            .justify_center()
                            .text_color(beskar_theme::Theme::fg())
                            .hover(|s| s.bg(beskar_theme::Theme::bg_secondary()).cursor_pointer())
                            .when_some(on_next, |el, cb| {
                                el.on_mouse_down(MouseButton::Left, move |_, _, _| (cb)())
                            })
                            .child(Icon::new(IconName::SkipForward).size(px(16.0))),
                    )
                    // Loop Mode Button
                    .child(
                        div()
                            .w(px(28.0))
                            .h(px(28.0))
                            .rounded_md()
                            .flex()
                            .items_center()
                            .justify_center()
                            .text_color(if self.is_looping { beskar_theme::Theme::accent() } else { beskar_theme::Theme::muted() })
                            .hover(|s| s.bg(beskar_theme::Theme::bg_secondary()).cursor_pointer())
                            .when_some(on_toggle_loop, |el, cb| {
                                el.on_mouse_down(MouseButton::Left, move |_, _, _| (cb)())
                            })
                            .child(Icon::new(IconName::Repeat).size(px(14.0))),
                    ),
            )
    }
}

/// Render 28-36 animated CAVA bars matching MusicCavaBars.qml
fn render_cava_spectrum(bars: &[u8], is_playing: bool) -> impl IntoElement {
    let bar_count = 28;
    let min_height = 3.0f32;
    let max_height = 20.0f32;

    div()
        .flex()
        .items_end()
        .gap(px(2.0))
        .h(px(max_height))
        .children((0..bar_count).map(|i| {
            let sample_idx = (i * 35 / (bar_count - 1)).min(35);
            let val = if is_playing && sample_idx < bars.len() {
                bars[sample_idx] as f32
            } else if is_playing {
                15.0f32
            } else {
                0.0f32
            };
            let h = min_height + (val / 100.0) * (max_height - min_height);

            div()
                .w(px(3.0))
                .h(px(h.clamp(min_height, max_height)))
                .rounded_xs()
                .bg(beskar_theme::Theme::accent())
        }))
}

/// Scrubbable Progress Bar with click-to-seek
fn render_progress_bar(progress: f32, on_seek: Option<Arc<dyn Fn(f32) + Send + Sync>>) -> impl IntoElement {
    let pct = (progress * 100.0).clamp(0.0, 100.0);

    div()
        .w_full()
        .h(px(6.0))
        .rounded_full()
        .bg(hsla(0.0, 0.0, 1.0, 0.12))
        .hover(|s| s.cursor_pointer())
        .when_some(on_seek, |el, cb| {
            el.on_mouse_down(MouseButton::Left, move |event, _window, _cx| {
                let x: f32 = event.position.x.into();
                let frac = (x / 400.0).clamp(0.0, 1.0);
                (cb)(frac);
            })
        })
        .child(
            div()
                .w(relative(pct / 100.0))
                .h_full()
                .rounded_full()
                .bg(beskar_theme::Theme::accent()),
        )
}

fn format_time(secs: u32) -> String {
    let m = secs / 60;
    let s = secs % 60;
    format!("{}:{:02}", m, s)
}
