use beskar_core::models::AppItem;
use beskar_ui::LauncherWidget;
use gpui_kit::*;

use crate::panel_host::{PanelHost, PanelModule};

#[derive(Debug, Clone)]
enum LauncherMsg {
    ClearQuery,
    Select(usize),
    Launch(String),
    Close,
}

/// Dedicated View for App Launcher
pub struct LauncherView {
    query: String,
    selected_idx: usize,
    apps: Vec<AppItem>,
    focus_handle: FocusHandle,
    msg_tx: tokio::sync::mpsc::UnboundedSender<LauncherMsg>,
}

impl PanelModule for LauncherView {
    const ID: &'static str = "launcher";

    fn build(cx: &mut Context<Self>) -> Self {
        Self::new(cx)
    }
}

impl LauncherView {
    pub fn new(cx: &mut Context<Self>) -> Self {
        let apps = beskar_services::list_apps();
        let focus_handle = cx.focus_handle();
        let (msg_tx, mut msg_rx) = tokio::sync::mpsc::unbounded_channel::<LauncherMsg>();

        cx.spawn(async move |this, cx| {
            while let Some(msg) = msg_rx.recv().await {
                let _ = this.update(cx, |this, cx| match msg {
                    LauncherMsg::ClearQuery => {
                        this.query.clear();
                        this.selected_idx = 0;
                        cx.notify();
                    }
                    LauncherMsg::Select(idx) => {
                        if this.selected_idx != idx {
                            this.selected_idx = idx;
                            cx.notify();
                        }
                    }
                    LauncherMsg::Launch(cmd) => {
                        let _ = beskar_services::launch_app(&cmd);
                        PanelHost::close(cx);
                    }
                    LauncherMsg::Close => {
                        PanelHost::close(cx);
                    }
                });
            }
        })
        .detach();

        Self {
            query: String::new(),
            selected_idx: 0,
            apps,
            focus_handle,
            msg_tx,
        }
    }
}

impl Focusable for LauncherView {
    fn focus_handle(&self, _cx: &App) -> FocusHandle {
        self.focus_handle.clone()
    }
}

impl Render for LauncherView {
    fn render(&mut self, _window: &mut Window, cx: &mut Context<Self>) -> impl IntoElement {
        let tx_sel = self.msg_tx.clone();
        let tx_launch = self.msg_tx.clone();
        let tx_clear = self.msg_tx.clone();
        let tx_close = self.msg_tx.clone();

        div()
            .id("launcher-backdrop")
            .size_full()
            .flex()
            .flex_col()
            .items_center()
            .pt(px(90.0))
            .track_focus(&self.focus_handle)
            .key_context("Launcher")
            .on_mouse_down(MouseButton::Left, move |_, window, _cx| {
                PanelHost::forget(LauncherView::ID);
                window.remove_window();
            })
            .on_key_down(cx.listener(move |this, event: &KeyDownEvent, window, cx| {
                let key = event.keystroke.key.as_str();
                let mods = &event.keystroke.modifiers;

                match key {
                    "escape" => {
                        if !this.query.is_empty() {
                            this.query.clear();
                            this.selected_idx = 0;
                            cx.notify();
                        } else {
                            PanelHost::forget(LauncherView::ID);
                            window.remove_window();
                        }
                        cx.stop_propagation();
                    }
                    "up" => {
                        this.selected_idx = this.selected_idx.saturating_sub(1);
                        cx.notify();
                        cx.stop_propagation();
                    }
                    "down" => {
                        let filtered = LauncherWidget::filter_and_rank(&this.apps, &this.query);
                        this.selected_idx =
                            (this.selected_idx + 1).min(filtered.len().saturating_sub(1));
                        cx.notify();
                        cx.stop_propagation();
                    }
                    "enter" | "return" => {
                        let filtered = LauncherWidget::filter_and_rank(&this.apps, &this.query);
                        if let Some(app) = filtered.get(this.selected_idx) {
                            let _ = beskar_services::launch_app(&app.exec);
                            PanelHost::forget(LauncherView::ID);
                            window.remove_window();
                        }
                        cx.stop_propagation();
                    }
                    "backspace" => {
                        this.query.pop();
                        this.selected_idx = 0;
                        cx.notify();
                        cx.stop_propagation();
                    }
                    "space" if !mods.control && !mods.alt && !mods.platform => {
                        this.query.push(' ');
                        this.selected_idx = 0;
                        cx.notify();
                        cx.stop_propagation();
                    }
                    _ => {
                        if mods.control {
                            match key {
                                "n" => {
                                    let filtered =
                                        LauncherWidget::filter_and_rank(&this.apps, &this.query);
                                    this.selected_idx = (this.selected_idx + 1)
                                        .min(filtered.len().saturating_sub(1));
                                    cx.notify();
                                    cx.stop_propagation();
                                }
                                "p" => {
                                    this.selected_idx = this.selected_idx.saturating_sub(1);
                                    cx.notify();
                                    cx.stop_propagation();
                                }
                                "u" => {
                                    this.query.clear();
                                    this.selected_idx = 0;
                                    cx.notify();
                                    cx.stop_propagation();
                                }
                                "c" => {
                                    PanelHost::forget(LauncherView::ID);
                                    window.remove_window();
                                    cx.stop_propagation();
                                }
                                _ => {}
                            }
                        } else if !mods.alt && !mods.platform
                            && event.keystroke.key.chars().count() == 1 {
                            let ch = event.keystroke.key.chars().next().unwrap();
                            this.query.push(ch);
                            this.selected_idx = 0;
                            cx.notify();
                            cx.stop_propagation();
                        }
                    }
                }
            }))
            .child(
                div()
                    .w(px(700.0))
                    .on_mouse_down(MouseButton::Left, |_, _, cx| {
                        cx.stop_propagation();
                    })
                    .child(
                        LauncherWidget::new(self.apps.clone())
                            .query(self.query.clone())
                            .selected_idx(self.selected_idx)
                            .on_select(move |idx| {
                                let _ = tx_sel.send(LauncherMsg::Select(idx));
                            })
                            .on_launch(move |cmd| {
                                let _ = tx_launch.send(LauncherMsg::Launch(cmd));
                            })
                            .on_clear(move || {
                                let _ = tx_clear.send(LauncherMsg::ClearQuery);
                            })
                            .on_close(move || {
                                let _ = tx_close.send(LauncherMsg::Close);
                            }),
                    ),
            )
    }
}
