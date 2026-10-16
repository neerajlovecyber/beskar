pub mod view;

use self::view::PolkitWidget;
use beskar_services::polkit::{authenticate_user, PolkitAuthRequest, PolkitService};
use beskar_ui::InputState;
use gpui_kit::layer_shell::KeyboardInteractivity;
use gpui_kit::*;

use crate::panel_host::{LayerAnchor, PanelHost, PanelModule, Slot};

#[derive(Debug, Clone)]
enum PolkitMsg {
    Submit,
    Cancel,
}

/// Dedicated modal view for Polkit privileged authentication prompts.
pub struct PolkitView {
    request: Option<PolkitAuthRequest>,
    password_input: InputState,
    error: Option<String>,
    authenticating: bool,
    focus_handle: FocusHandle,
    responder: Option<tokio::sync::oneshot::Sender<Result<(), String>>>,
    close_tx: tokio::sync::mpsc::UnboundedSender<()>,
    msg_tx: tokio::sync::mpsc::UnboundedSender<PolkitMsg>,
}

impl PanelModule for PolkitView {
    const ID: &'static str = "polkit";

    fn slot() -> Slot {
        Slot::Focus
    }

    fn size() -> Size<Pixels> {
        Size::new(px(432.0), px(280.0))
    }

    fn anchor() -> LayerAnchor {
        LayerAnchor::TOP
    }

    fn margin() -> (Pixels, Pixels, Pixels, Pixels) {
        (px(140.0), px(0.0), px(0.0), px(0.0))
    }

    fn keyboard_interactivity() -> KeyboardInteractivity {
        KeyboardInteractivity::Exclusive
    }

    fn build(cx: &mut Context<Self>) -> Self {
        Self::new(cx)
    }
}

impl PolkitView {
    pub fn new(cx: &mut Context<Self>) -> Self {
        let focus_handle = cx.focus_handle();
        let (close_tx, mut close_rx) = tokio::sync::mpsc::unbounded_channel::<()>();
        let (msg_tx, mut msg_rx) = tokio::sync::mpsc::unbounded_channel::<PolkitMsg>();

        let service = PolkitService::new();
        let (initial_req, initial_responder) = service.pop_request().unzip();

        let password_input = InputState::new("").with_masked(true).with_focused(true);

        // 1. Overlay close listener
        cx.spawn(async move |_this, cx| {
            while let Some(()) = close_rx.recv().await {
                let _ = cx.update(|cx| {
                    PanelHost::close_if_active("polkit", cx);
                });
            }
        })
        .detach();

        // 2. Button action listener
        cx.spawn(async move |this, cx| {
            while let Some(msg) = msg_rx.recv().await {
                let _ = this.update(cx, |this, cx| match msg {
                    PolkitMsg::Submit => this.submit(cx),
                    PolkitMsg::Cancel => this.cancel(),
                });
            }
        })
        .detach();

        // 2. Request queue monitor loop
        let service_clone = service.clone();
        cx.spawn(async move |this, cx| {
            loop {
                service_clone.wait_for_change().await;

                // Check cancelled
                while let Some(cookie) = service_clone.pop_cancelled() {
                    let _ = this.update(cx, |this, cx| {
                        if this.request.as_ref().is_some_and(|r| r.cookie == cookie) {
                            this.finish(Err("Cancelled by Polkit Authority".into()));
                            let _ = this.close_tx.send(());
                            cx.notify();
                        }
                    });
                }

                // Check new requests if vacant
                let res = this.update(cx, |this, cx| {
                    if this.request.is_none() {
                        if let Some((req, responder)) = service_clone.pop_request() {
                            if !responder.is_closed() {
                                this.request = Some(req);
                                this.responder = Some(responder);
                                this.password_input.clear();
                                this.error = None;
                                this.authenticating = false;
                                cx.notify();
                            }
                        }
                    }
                });

                if res.is_err() {
                    break;
                }
            }
        })
        .detach();

        Self {
            request: initial_req,
            password_input,
            error: None,
            authenticating: false,
            focus_handle,
            responder: initial_responder,
            close_tx,
            msg_tx,
        }
    }

    fn finish(&mut self, result: Result<(), String>) {
        if let Some(resp) = self.responder.take() {
            let _ = resp.send(result);
        }
        self.request = None;
        self.password_input.clear();
        self.error = None;
        self.authenticating = false;
    }

    pub fn cancel(&mut self) {
        self.finish(Err("Cancelled by user".into()));
        let _ = self.close_tx.send(());
    }

    pub fn submit(&mut self, cx: &mut Context<Self>) {
        if self.authenticating || self.password_input.is_empty() {
            return;
        }

        let Some(req) = &self.request else {
            return;
        };

        let user = req.user_name.clone();
        let cookie = req.cookie.clone();
        let pass = self.password_input.text();
        self.password_input.clear();

        self.authenticating = true;
        self.error = None;
        cx.notify();

        let (tx, rx) = tokio::sync::oneshot::channel::<Result<(), String>>();
        beskar_services::spawn_tokio(async move {
            let res = tokio::time::timeout(
                std::time::Duration::from_secs(30),
                authenticate_user(&user, &cookie, &pass),
            )
            .await
            .unwrap_or(Err("Authentication timed out after 30 seconds.".to_string()));
            let _ = tx.send(res);
        });

        cx.spawn(async move |this, cx| {
            let result = rx.await.unwrap_or(Err("Internal authentication error".to_string()));
            let _ = this.update(cx, |this, cx| {
                this.authenticating = false;
                match result {
                    Ok(()) => {
                        this.finish(Ok(()));
                        let _ = this.close_tx.send(());
                    }
                    Err(err) => {
                        this.error = Some(err);
                        this.password_input.clear();
                        cx.notify();
                    }
                }
            });
        })
        .detach();
    }
}

impl Focusable for PolkitView {
    fn focus_handle(&self, _cx: &App) -> FocusHandle {
        self.focus_handle.clone()
    }
}

impl Render for PolkitView {
    fn render(&mut self, _window: &mut Window, cx: &mut Context<Self>) -> impl IntoElement {
        let (user_name, action_id, message) = if let Some(req) = &self.request {
            (req.user_name.clone(), req.action_id.clone(), req.message.clone())
        } else {
            ("root".to_string(), "org.freedesktop.policykit.exec".to_string(), "".to_string())
        };

        div()
            .size_full()
            .track_focus(&self.focus_handle)
            .key_context("Polkit")
            .on_key_down(cx.listener(|this, event: &KeyDownEvent, _window, cx| {
                let key = event.keystroke.key.as_str();
                match key {
                    "escape" => {
                        this.cancel();
                        cx.stop_propagation();
                    }
                    "enter" | "return" => {
                        this.submit(cx);
                        cx.stop_propagation();
                    }
                    _ => {
                        if !this.authenticating && this.password_input.handle_key_down(event, cx) {
                            this.error = None;
                            cx.notify();
                            cx.stop_propagation();
                        }
                    }
                }
            }))
            .child({
                let tx_sub = self.msg_tx.clone();
                let tx_can = self.msg_tx.clone();
                PolkitWidget::new(user_name, action_id, message)
                    .password_len(self.password_input.len())
                    .error(self.error.clone())
                    .authenticating(self.authenticating)
                    .on_submit(move || {
                        let _ = tx_sub.send(PolkitMsg::Submit);
                    })
                    .on_cancel(move || {
                        let _ = tx_can.send(PolkitMsg::Cancel);
                    })
            })
    }
}
