use beskar_ui::LockScreenWidget;
use gpui_kit::layer_shell::KeyboardInteractivity;
use gpui_kit::*;

use crate::panel_host::{PanelHost, PanelModule};

/// Dedicated View for Fullscreen Lock Screen
pub struct LockScreenView {
    user_name: String,
    time_str: String,
    date_str: String,
    password: String,
    has_error: bool,
    focus_handle: FocusHandle,
    close_tx: tokio::sync::mpsc::UnboundedSender<()>,
}

impl PanelModule for LockScreenView {
    const ID: &'static str = "lock_screen";

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

        // 1. Overlay close listener
        cx.spawn(async move |_this, cx| {
            while let Some(()) = close_rx.recv().await {
                cx.update(|cx| {
                    PanelHost::close(cx);
                });
            }
        })
        .detach();

        // 2. Real-time Clock loop (updates time while locked)
        cx.spawn(async move |this, cx| {
            loop {
                let _ = cx
                    .background_executor()
                    .timer(std::time::Duration::from_secs(1))
                    .await;
                let now = chrono::Local::now();
                let time = now.format("%-I:%M %p").to_string();
                let date = now.format("%A, %B %-d").to_string();
                let res = this.update(cx, |this, cx| {
                    this.time_str = time;
                    this.date_str = date;
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
            password: String::new(),
            has_error: false,
            focus_handle,
            close_tx,
        }
    }
}

impl Focusable for LockScreenView {
    fn focus_handle(&self, _cx: &App) -> FocusHandle {
        self.focus_handle.clone()
    }
}

impl Render for LockScreenView {
    fn render(&mut self, _window: &mut Window, cx: &mut Context<Self>) -> impl IntoElement {
        let tx = self.close_tx.clone();
        let cancel_tx = self.close_tx.clone();

        div()
            .size_full()
            .track_focus(&self.focus_handle)
            .on_key_down(cx.listener(move |this, event: &KeyDownEvent, _window, cx| {
                let key = event.keystroke.key.as_str();
                match key {
                    "escape" => {
                        if !this.password.is_empty() {
                            this.password.clear();
                            this.has_error = false;
                            cx.notify();
                        } else {
                            let _ = this.close_tx.send(());
                        }
                        cx.stop_propagation();
                    }
                    "backspace" => {
                        this.password.pop();
                        this.has_error = false;
                        cx.notify();
                        cx.stop_propagation();
                    }
                    "enter" | "return" => {
                        let pwd = this.password.clone();
                        if pwd.is_empty() {
                            let _ = this.close_tx.send(());
                        } else {
                            cx.spawn(async move |this, cx| {
                                let ok = cx
                                    .background_executor()
                                    .spawn(async move { beskar_services::verify_password(&pwd) })
                                    .await;

                                let _ = this.update(cx, |this, cx| match ok {
                                    Ok(true) => {
                                        let _ = this.close_tx.send(());
                                    }
                                    _ => {
                                        this.has_error = true;
                                        this.password.clear();
                                        cx.notify();
                                    }
                                });
                            })
                            .detach();
                        }
                        cx.stop_propagation();
                    }
                    _ => {
                        if key.chars().count() == 1 {
                            let ch = key.chars().next().unwrap();
                            if !ch.is_control() {
                                this.password.push(ch);
                                this.has_error = false;
                                cx.notify();
                                cx.stop_propagation();
                            }
                        }
                    }
                }
            }))
            .child(
                LockScreenWidget::new(&self.user_name, &self.time_str, &self.date_str)
                    .password_len(self.password.len())
                    .error(self.has_error)
                    .on_unlock_attempt(move |_pwd| {
                        let _ = tx.send(());
                    })
                    .on_cancel(move || {
                        let _ = cancel_tx.send(());
                    }),
            )
    }
}
