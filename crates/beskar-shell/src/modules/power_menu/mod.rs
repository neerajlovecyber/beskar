use beskar_ui::{PowerAction, PowerMenuWidget};
use gpui_kit::*;

use crate::panel_host::{PanelHost, PanelModule};

#[derive(Debug, Clone)]
enum PowerMenuMsg {
    Select(usize),
    RequestConfirm(PowerAction),
    CancelConfirm,
    ConfirmSelect(usize),
    Action(PowerAction),
    Close,
}

/// Dedicated View for Power Menu
pub struct PowerMenuView {
    selected_index: usize,
    pending_action: Option<PowerAction>,
    confirm_index: usize,
    focus_handle: FocusHandle,
    msg_tx: tokio::sync::mpsc::UnboundedSender<PowerMenuMsg>,
}

impl PanelModule for PowerMenuView {
    const ID: &'static str = "power_menu";

    fn build(cx: &mut Context<Self>) -> Self {
        Self::new(cx)
    }
}

impl PowerMenuView {
    pub fn new(cx: &mut Context<Self>) -> Self {
        let focus_handle = cx.focus_handle();
        let (msg_tx, mut msg_rx) = tokio::sync::mpsc::unbounded_channel::<PowerMenuMsg>();

        cx.spawn(async move |this, cx| {
            while let Some(msg) = msg_rx.recv().await {
                let _ = this.update(cx, |this, cx| {
                    match msg {
                        PowerMenuMsg::Select(idx) => {
                            if this.selected_index != idx {
                                this.selected_index = idx;
                                cx.notify();
                            }
                        }
                        PowerMenuMsg::RequestConfirm(action) => {
                            this.pending_action = Some(action);
                            this.confirm_index = 1;
                            cx.notify();
                        }
                        PowerMenuMsg::CancelConfirm => {
                            this.pending_action = None;
                            cx.notify();
                        }
                        PowerMenuMsg::ConfirmSelect(idx) => {
                            if this.confirm_index != idx {
                                this.confirm_index = idx;
                                cx.notify();
                            }
                        }
                        PowerMenuMsg::Action(action) => {
                            if action == PowerAction::Lock {
                                PanelHost::close(cx);
                                PanelHost::toggle_by_id("lock_screen", cx);
                            } else {
                                let cmd = action.default_command();
                                let _ = std::process::Command::new("sh").args(["-c", cmd]).spawn();
                                PanelHost::close(cx);
                            }
                        }
                        PowerMenuMsg::Close => {
                            PanelHost::close(cx);
                        }
                    }
                });
            }
        })
        .detach();

        Self {
            selected_index: 0,
            pending_action: None,
            confirm_index: 1,
            focus_handle,
            msg_tx,
        }
    }
}

impl Focusable for PowerMenuView {
    fn focus_handle(&self, _cx: &App) -> FocusHandle {
        self.focus_handle.clone()
    }
}

impl Render for PowerMenuView {
    fn render(&mut self, _window: &mut Window, cx: &mut Context<Self>) -> impl IntoElement {
        let tx_sel = self.msg_tx.clone();
        let tx_req = self.msg_tx.clone();
        let tx_cancel = self.msg_tx.clone();
        let tx_conf_sel = self.msg_tx.clone();
        let tx_act = self.msg_tx.clone();
        let tx_close = self.msg_tx.clone();
        let msg_tx = self.msg_tx.clone();

        div()
            .id("power-menu-backdrop")
            .size_full()
            .flex()
            .items_center()
            .justify_center()
            .track_focus(&self.focus_handle)
            .key_context("PowerMenu")
            .on_mouse_down(MouseButton::Left, move |_, window, _cx| {
                PanelHost::forget(PowerMenuView::ID);
                window.remove_window();
            })
            .on_key_down(cx.listener(move |this, event: &KeyDownEvent, window, cx| {
                match event.keystroke.key.as_str() {
                    "escape" => {
                        if this.pending_action.is_some() {
                            this.pending_action = None;
                            cx.notify();
                        } else {
                            PanelHost::forget(PowerMenuView::ID);
                            window.remove_window();
                        }
                        cx.stop_propagation();
                    }
                    "1" => {
                        let _ = msg_tx.send(PowerMenuMsg::Action(PowerAction::Lock));
                        cx.stop_propagation();
                    }
                    "2" => {
                        this.pending_action = Some(PowerAction::Suspend);
                        this.confirm_index = 1;
                        cx.notify();
                        cx.stop_propagation();
                    }
                    "3" => {
                        this.pending_action = Some(PowerAction::Logout);
                        this.confirm_index = 1;
                        cx.notify();
                        cx.stop_propagation();
                    }
                    "4" => {
                        this.pending_action = Some(PowerAction::Restart);
                        this.confirm_index = 1;
                        cx.notify();
                        cx.stop_propagation();
                    }
                    "5" => {
                        this.pending_action = Some(PowerAction::Shutdown);
                        this.confirm_index = 1;
                        cx.notify();
                        cx.stop_propagation();
                    }
                    "left" | "h" | "up" | "k" => {
                        if this.pending_action.is_some() {
                            this.confirm_index = 0;
                        } else {
                            this.selected_index = this.selected_index.saturating_sub(1);
                        }
                        cx.notify();
                        cx.stop_propagation();
                    }
                    "right" | "l" | "down" | "j" | "tab" => {
                        if this.pending_action.is_some() {
                            this.confirm_index = 1;
                        } else {
                            this.selected_index = (this.selected_index + 1)
                                .min(PowerAction::ALL.len().saturating_sub(1));
                        }
                        cx.notify();
                        cx.stop_propagation();
                    }
                    "enter" | "return" | "space" => {
                        if let Some(pending) = this.pending_action {
                            if this.confirm_index == 1 {
                                let _ = msg_tx.send(PowerMenuMsg::Action(pending));
                            } else {
                                this.pending_action = None;
                                cx.notify();
                            }
                        } else {
                            let action = PowerAction::ALL[this.selected_index];
                            if action.requires_confirmation() {
                                this.pending_action = Some(action);
                                this.confirm_index = 1;
                                cx.notify();
                            } else {
                                let _ = msg_tx.send(PowerMenuMsg::Action(action));
                            }
                        }
                        cx.stop_propagation();
                    }
                    _ => {}
                }
            }))
            .child(
                div()
                    .on_mouse_down(MouseButton::Left, |_, _, cx| {
                        cx.stop_propagation();
                    })
                    .child(
                        PowerMenuWidget::new()
                            .selected_index(self.selected_index)
                            .pending_action(self.pending_action)
                            .confirm_index(self.confirm_index)
                            .on_select(move |idx| {
                                let _ = tx_sel.send(PowerMenuMsg::Select(idx));
                            })
                            .on_request_confirm(move |action| {
                                let _ = tx_req.send(PowerMenuMsg::RequestConfirm(action));
                            })
                            .on_cancel_confirm(move || {
                                let _ = tx_cancel.send(PowerMenuMsg::CancelConfirm);
                            })
                            .on_confirm_select(move |idx| {
                                let _ = tx_conf_sel.send(PowerMenuMsg::ConfirmSelect(idx));
                            })
                            .on_action(move |action| {
                                let _ = tx_act.send(PowerMenuMsg::Action(action));
                            })
                            .on_close(move || {
                                let _ = tx_close.send(PowerMenuMsg::Close);
                            }),
                    ),
            )
    }
}
