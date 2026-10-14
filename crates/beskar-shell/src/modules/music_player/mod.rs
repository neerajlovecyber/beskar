pub mod view;
use self::view::MusicPlayerWidget;
use gpui_kit::*;

use crate::panel_host::{LayerAnchor, PanelHost, PanelModule};

#[derive(Debug, Clone)]
enum MusicMsg {
    PlayPause,
    Prev,
    Next,
    Seek(f32),
    ToggleLoop,
    ToggleShuffle,
    Close,
}

pub struct MusicPlayerView {
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
    focus_handle: FocusHandle,
    msg_tx: tokio::sync::mpsc::UnboundedSender<MusicMsg>,
}

impl PanelModule for MusicPlayerView {
    const ID: &'static str = "music_player";

    fn size() -> Size<Pixels> {
        Size::new(px(430.0), px(560.0))
    }

    fn anchor() -> LayerAnchor {
        LayerAnchor::TOP
    }

    fn margin() -> (Pixels, Pixels, Pixels, Pixels) {
        (px(48.0), px(0.0), px(0.0), px(0.0))
    }

    fn build(cx: &mut Context<Self>) -> Self {
        Self::new(cx)
    }
}

impl MusicPlayerView {
    pub fn new(cx: &mut Context<Self>) -> Self {
        let focus_handle = cx.focus_handle();
        let (msg_tx, mut msg_rx) = tokio::sync::mpsc::unbounded_channel::<MusicMsg>();

        let media = beskar_services::MprisService::read_state();
        let title = media
            .as_ref()
            .and_then(|m| m.title.clone())
            .unwrap_or_else(|| "No Media Playing".to_string());
        let artist = media
            .as_ref()
            .and_then(|m| m.artist.clone())
            .unwrap_or_else(|| "Idle Audio Service".to_string());
        let album = media.as_ref().and_then(|m| m.album.clone());
        let player_name = media
            .as_ref()
            .map(|m| m.player_name.clone())
            .unwrap_or_else(|| "MPRIS".to_string());
        let is_playing = media.as_ref().map(|m| m.is_playing).unwrap_or(false);
        let duration_secs = media
            .as_ref()
            .map(|m| (m.duration_ms / 1000) as u32)
            .unwrap_or(215);
        let position_secs = media
            .as_ref()
            .map(|m| (m.position_ms / 1000) as u32)
            .unwrap_or(45);

        // Responsive spectrum bars animation loop
        cx.spawn(async move |this, cx| {
            let mut tick: u32 = 0;
            loop {
                tokio::time::sleep(tokio::time::Duration::from_millis(80)).await;
                tick = tick.wrapping_add(1);

                let polled_media = if tick.is_multiple_of(12) {
                    beskar_services::MprisService::read_state()
                } else {
                    None
                };

                let generated_bars: Vec<u8> = if is_playing
                    || polled_media.as_ref().is_some_and(|m| m.is_playing)
                {
                    (0..32)
                        .map(|i| {
                            let phase = (tick as f32 * 0.18 + i as f32 * 0.35).sin().abs();
                            let harmonic = (tick as f32 * 0.28 + i as f32 * 0.55).cos().abs();
                            ((phase * 50.0 + harmonic * 40.0 + 8.0).min(99.0)) as u8
                        })
                        .collect()
                } else {
                    (0..32).map(|_| 4).collect()
                };

                let res = this.update(cx, |this, cx| {
                    if let Some(ref m) = polled_media {
                        this.title = m
                            .title
                            .clone()
                            .unwrap_or_else(|| "No Media Playing".to_string());
                        this.artist = m
                            .artist
                            .clone()
                            .unwrap_or_else(|| "Idle Audio Service".to_string());
                        this.player_name = m.player_name.clone();
                        this.is_playing = m.is_playing;
                    }
                    this.cava_bars = generated_bars;
                    cx.notify();
                });
                if res.is_err() {
                    break;
                }
            }
        })
        .detach();

        cx.spawn(async move |this, cx| {
            while let Some(msg) = msg_rx.recv().await {
                match msg {
                    MusicMsg::PlayPause => {
                        beskar_services::MprisService::play_pause();
                    }
                    MusicMsg::Prev => {
                        beskar_services::MprisService::previous();
                    }
                    MusicMsg::Next => {
                        beskar_services::MprisService::next();
                    }
                    MusicMsg::Seek(fraction) => {
                        let _ = std::process::Command::new("playerctl")
                            .args(["position", &format!("{:.1}", fraction * 200.0)])
                            .spawn();
                    }
                    MusicMsg::ToggleLoop => {
                        let _ = this.update(cx, |this, cx| {
                            this.is_looping = !this.is_looping;
                            cx.notify();
                        });
                    }
                    MusicMsg::ToggleShuffle => {
                        let _ = this.update(cx, |this, cx| {
                            this.is_shuffling = !this.is_shuffling;
                            cx.notify();
                        });
                    }
                    MusicMsg::Close => {
                        let _ = this.update(cx, |_, cx| {
                            PanelHost::close(cx);
                        });
                    }
                }
            }
        })
        .detach();

        Self {
            title,
            artist,
            album,
            player_name,
            is_playing,
            position_secs,
            duration_secs,
            cava_bars: (0..32).map(|_| 6).collect(),
            is_looping: false,
            is_shuffling: false,
            focus_handle,
            msg_tx,
        }
    }
}

impl Focusable for MusicPlayerView {
    fn focus_handle(&self, _cx: &App) -> FocusHandle {
        self.focus_handle.clone()
    }
}

impl Render for MusicPlayerView {
    fn render(&mut self, _window: &mut Window, cx: &mut Context<Self>) -> impl IntoElement {
        let tx_pp = self.msg_tx.clone();
        let tx_prev = self.msg_tx.clone();
        let tx_next = self.msg_tx.clone();
        let tx_seek = self.msg_tx.clone();
        let tx_loop = self.msg_tx.clone();
        let tx_shuf = self.msg_tx.clone();
        let tx_close = self.msg_tx.clone();

        div()
            .id("music-player-card")
            .w(px(430.0))
            .max_h(px(560.0))
            .overflow_y_scroll()
            .pb(px(8.0))
            .track_focus(&self.focus_handle)
            .key_context("MusicPlayerView")
            .on_key_down(cx.listener(|_this, event: &KeyDownEvent, _window, cx| {
                if event.keystroke.key == "escape" {
                    PanelHost::close(cx);
                    cx.stop_propagation();
                }
            }))
            .child(
                MusicPlayerWidget::new(self.title.clone(), self.artist.clone(), self.is_playing)
                    .album(self.album.clone())
                    .player_name(self.player_name.clone())
                    .position(self.position_secs, self.duration_secs)
                    .cava_bars(self.cava_bars.clone())
                    .loop_mode(self.is_looping)
                    .shuffle(self.is_shuffling)
                    .on_play_pause(move || {
                        let _ = tx_pp.send(MusicMsg::PlayPause);
                    })
                    .on_prev(move || {
                        let _ = tx_prev.send(MusicMsg::Prev);
                    })
                    .on_next(move || {
                        let _ = tx_next.send(MusicMsg::Next);
                    })
                    .on_seek(move |frac| {
                        let _ = tx_seek.send(MusicMsg::Seek(frac));
                    })
                    .on_toggle_loop(move || {
                        let _ = tx_loop.send(MusicMsg::ToggleLoop);
                    })
                    .on_toggle_shuffle(move || {
                        let _ = tx_shuf.send(MusicMsg::ToggleShuffle);
                    })
                    .on_close(move || {
                        let _ = tx_close.send(MusicMsg::Close);
                    }),
            )
    }
}
