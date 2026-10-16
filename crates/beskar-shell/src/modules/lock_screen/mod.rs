pub mod view;
use self::view::LockScreenWidget;
use gpui_kit::layer_shell::KeyboardInteractivity;
use gpui_kit::*;

use crate::panel_host::{LayerAnchor, PanelHost, PanelModule, Slot};
use beskar_services::{BatteryService, BatteryState, MediaTrack, MprisService};
use beskar_ui::InputState;

/// Dedicated View for Fullscreen Lock Screen
pub struct LockScreenView {
    user_name: String,
    time_str: String,
    date_str: String,
    password_input: InputState,
    has_error: bool,
    is_checking: bool,
    blurred_wallpaper: Option<String>,
    media_track: Option<MediaTrack>,
    battery: Option<BatteryState>,
    focus_handle: FocusHandle,
    close_tx: tokio::sync::mpsc::UnboundedSender<()>,
    submit_tx: tokio::sync::mpsc::UnboundedSender<()>,
}

impl PanelModule for LockScreenView {
    const ID: &'static str = "lock_screen";

    fn slot() -> Slot {
        Slot::Focus
    }

    fn size() -> Size<Pixels> {
        Size::new(px(1920.0), px(1080.0))
    }

    fn anchor() -> LayerAnchor {
        LayerAnchor::TOP | LayerAnchor::BOTTOM | LayerAnchor::LEFT | LayerAnchor::RIGHT
    }

    fn margin() -> (Pixels, Pixels, Pixels, Pixels) {
        (px(0.0), px(0.0), px(0.0), px(0.0))
    }

    fn keyboard_interactivity() -> KeyboardInteractivity {
        KeyboardInteractivity::Exclusive
    }

    fn build(cx: &mut Context<Self>) -> Self {
        Self::new(cx)
    }
}

impl LockScreenView {
    pub fn new(cx: &mut Context<Self>) -> Self {
        let user_name = std::env::var("USER").unwrap_or_else(|_| "User".to_string());
        let now = chrono::Local::now();
        let time_str = now.format("%-I:%M %p").to_string();
        let date_str = now.format("%A, %B %-d").to_string();
        let focus_handle = cx.focus_handle();
        let (close_tx, mut close_rx) = tokio::sync::mpsc::unbounded_channel::<()>();
        let (submit_tx, mut submit_rx) = tokio::sync::mpsc::unbounded_channel::<()>();

        let password_input = InputState::new("").with_masked(true).with_focused(true);
        let media_track = MprisService::fetch_all_players().into_iter().next();
        let battery = Some(BatteryService::new().read_state());

        // Spawn async wallpaper blur resolution without blocking UI thread
        cx.spawn(async move |this, cx| {
            let blur_res = tokio::task::spawn_blocking(|| {
                beskar_services::WallpaperService::get_blurred_wallpaper()
            })
            .await
            .ok()
            .flatten();
            if let Some(blur_path) = blur_res {
                let _ = this.update(cx, |this, cx| {
                    this.blurred_wallpaper = Some(blur_path.to_string_lossy().to_string());
                    cx.notify();
                });
            }
        })
        .detach();

        // 1. Overlay close listener
        cx.spawn(async move |_this, cx| {
            while let Some(()) = close_rx.recv().await {
                cx.update(|cx| {
                    PanelHost::close(cx);
                });
            }
        })
        .detach();

        // 2. Submit password listener
        cx.spawn(async move |this, cx| {
            while let Some(()) = submit_rx.recv().await {
                let _ = this.update(cx, |this, cx| {
                    this.submit_password(cx);
                });
            }
        })
        .detach();

        // 2. Real-time Clock and status loop (updates time and telemetry while locked)
        cx.spawn(async move |this, cx| {
            loop {
                let _ = cx
                    .background_executor()
                    .timer(std::time::Duration::from_secs(1))
                    .await;
                let now = chrono::Local::now();
                let time = now.format("%-I:%M %p").to_string();
                let date = now.format("%A, %B %-d").to_string();
                let media = MprisService::fetch_all_players().into_iter().next();
                let bat = Some(BatteryService::new().read_state());

                let res = this.update(cx, |this, cx| {
                    this.time_str = time;
                    this.date_str = date;
                    this.media_track = media;
                    this.battery = bat;
                    cx.notify();
                });
                if res.is_err() {
                    break;
                }
            }
        })
        .detach();

        Self {
            user_name,
            time_str,
            date_str,
            password_input,
            has_error: false,
            is_checking: false,
            blurred_wallpaper: None,
            media_track,
            battery,
            focus_handle,
            close_tx,
            submit_tx,
        }
    }

    fn submit_password(&mut self, cx: &mut Context<Self>) {
        let pass = self.password_input.text();
        if pass.is_empty() || self.is_checking {
            return;
        }

        self.is_checking = true;
        self.has_error = false;
        cx.notify();

        let (tx, rx) = tokio::sync::oneshot::channel::<bool>();
        tokio::task::spawn_blocking(move || {
            let valid = std::panic::catch_unwind(|| {
                beskar_services::verify_password(&pass).unwrap_or(false)
            })
            .unwrap_or(false);
            let _ = tx.send(valid);
        });

        cx.spawn(async move |this, cx| {
            let valid = rx.await.unwrap_or(false);
            let _ = this.update(cx, |this, cx| {
                this.is_checking = false;
                if valid {
                    let _ = this.close_tx.send(());
                } else {
                    this.has_error = true;
                    this.password_input.clear();
                    cx.notify();
                }
            });
        })
        .detach();
    }
}

impl Focusable for LockScreenView {
    fn focus_handle(&self, _cx: &App) -> FocusHandle {
        self.focus_handle.clone()
    }
}

impl Render for LockScreenView {
    fn render(&mut self, _window: &mut Window, cx: &mut Context<Self>) -> impl IntoElement {
        let cancel_tx = self.close_tx.clone();
        let submit_tx = self.submit_tx.clone();

        div()
            .size_full()
            .track_focus(&self.focus_handle)
            .on_key_down(cx.listener(|this, event: &KeyDownEvent, _window, cx| {
                let key = event.keystroke.key.as_str();
                match key {
                    "escape" => {
                        if !this.password_input.is_empty() {
                            this.password_input.clear();
                            this.has_error = false;
                            cx.notify();
                        } else {
                            let _ = this.close_tx.send(());
                        }
                        cx.stop_propagation();
                    }
                    "enter" | "return" => {
                        this.submit_password(cx);
                        cx.stop_propagation();
                    }
                    _ => {
                        if this.password_input.handle_key_down(event, cx) {
                            this.has_error = false;
                            cx.notify();
                            cx.stop_propagation();
                        }
                    }
                }
            }))
            .child(
                LockScreenWidget::new(&self.user_name, &self.time_str, &self.date_str)
                    .password_len(self.password_input.len())
                    .error(self.has_error)
                    .checking(self.is_checking)
                    .wallpaper(self.blurred_wallpaper.clone())
                    .battery(self.battery.clone())
                    .media(self.media_track.clone())
                    .on_unlock_attempt(move |_pwd| {
                        let _ = submit_tx.send(());
                    })
                    .on_cancel(move || {
                        let _ = cancel_tx.send(());
                    }),
            )
    }
}
