use beskar_core::models::NotificationItem;
use beskar_ui::{NotificationCenterWidget, NotificationToastWidget};
use gpui_kit::layer_shell::{
    Anchor as LayerAnchor, KeyboardInteractivity, Layer, LayerShellOptions,
};
use gpui_kit::*;
use std::sync::Mutex;
use tracing::info;

use crate::panel_host::{PanelHost, PanelModule};

#[derive(Debug, Clone)]
enum NotifCenterMsg {
    Dismiss(u32),
    ClearAll,
    ToggleDnd,
    Close,
}

pub struct NotificationCenterView {
    notifications: Vec<NotificationItem>,
    is_dnd: bool,
    focus_handle: FocusHandle,
    msg_tx: tokio::sync::mpsc::UnboundedSender<NotifCenterMsg>,
}

impl PanelModule for NotificationCenterView {
    const ID: &'static str = "notification_center";

    fn build(cx: &mut Context<Self>) -> Self {
        Self::new(cx)
    }
}

impl NotificationCenterView {
    pub fn new(cx: &mut Context<Self>) -> Self {
        let focus_handle = cx.focus_handle();
        let (msg_tx, mut msg_rx) = tokio::sync::mpsc::unbounded_channel::<NotifCenterMsg>();
        let notifications = beskar_services::notifications::get_notifications();

        cx.spawn(async move |this, cx| {
            while let Some(msg) = msg_rx.recv().await {
                match msg {
                    NotifCenterMsg::Dismiss(id) => {
                        beskar_services::notifications::dismiss(id);
                        let _ = this.update(cx, |this, cx| {
                            this.notifications.retain(|n| n.id != id);
                            cx.notify();
                        });
                    }
                    NotifCenterMsg::ClearAll => {
                        beskar_services::notifications::clear_all();
                        let _ = this.update(cx, |this, cx| {
                            this.notifications.clear();
                            cx.notify();
                        });
                    }
                    NotifCenterMsg::ToggleDnd => {
                        let _ = this.update(cx, |this, cx| {
                            this.is_dnd = !this.is_dnd;
                            cx.notify();
                        });
                    }
                    NotifCenterMsg::Close => {
                        let _ = this.update(cx, |_, cx| {
                            PanelHost::close(cx);
                        });
                    }
                }
            }
        })
        .detach();

        Self {
            notifications,
            is_dnd: false,
            focus_handle,
            msg_tx,
        }
    }
}

impl Focusable for NotificationCenterView {
    fn focus_handle(&self, _cx: &App) -> FocusHandle {
        self.focus_handle.clone()
    }
}

impl Render for NotificationCenterView {
    fn render(&mut self, _window: &mut Window, cx: &mut Context<Self>) -> impl IntoElement {
        let tx_d = self.msg_tx.clone();
        let tx_c = self.msg_tx.clone();
        let tx_dnd = self.msg_tx.clone();
        let tx_close = self.msg_tx.clone();

        div()
            .id("notification-center-backdrop")
            .size_full()
            .flex()
            .justify_end()
            .pt(px(56.0))
            .pr(px(16.0))
            .track_focus(&self.focus_handle)
            .key_context("NotificationCenterView")
            .on_mouse_down(MouseButton::Left, move |_, window, _cx| {
                PanelHost::forget(NotificationCenterView::ID);
                window.remove_window();
            })
            .on_key_down(cx.listener(|_this, event: &KeyDownEvent, window, cx| {
                if event.keystroke.key == "escape" {
                    PanelHost::forget(NotificationCenterView::ID);
                    window.remove_window();
                    cx.stop_propagation();
                }
            }))
            .child(
                div()
                    .id("notif-center-outer")
                    .w(px(380.0))
                    .max_h(px(700.0))
                    .overflow_y_scroll()
                    .pb(px(8.0))
                    .on_mouse_down(MouseButton::Left, |_, _, cx| {
                        cx.stop_propagation();
                    })
                    .child(
                        NotificationCenterWidget::new(self.notifications.clone())
                            .dnd(self.is_dnd)
                            .on_dismiss(move |id| {
                                let _ = tx_d.send(NotifCenterMsg::Dismiss(id));
                            })
                            .on_clear_all(move || {
                                let _ = tx_c.send(NotifCenterMsg::ClearAll);
                            })
                            .on_toggle_dnd(move || {
                                let _ = tx_dnd.send(NotifCenterMsg::ToggleDnd);
                            })
                            .on_close(move || {
                                let _ = tx_close.send(NotifCenterMsg::Close);
                            }),
                    ),
            )
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Notification Toast Overlay Window System
// ─────────────────────────────────────────────────────────────────────────────

static NOTIFICATION_OVERLAY: Mutex<Option<AnyWindowHandle>> = Mutex::new(None);
static NOTIFICATION_QUEUE: Mutex<Vec<NotificationItem>> = Mutex::new(Vec::new());

pub fn forget_notification_overlay() {
    let mut guard = NOTIFICATION_OVERLAY.lock().unwrap();
    guard.take();
}

pub fn sync_notification_toasts(notifications: Vec<NotificationItem>, cx: &mut App) {
    let mut queue_guard = NOTIFICATION_QUEUE.lock().unwrap();
    *queue_guard = notifications.clone();
    drop(queue_guard);

    let mut guard = NOTIFICATION_OVERLAY.lock().unwrap();
    if notifications.is_empty() {
        if let Some(handle) = guard.take() {
            let _ = cx.update_window(handle, |_, window, _| {
                window.remove_window();
            });
        }
        return;
    }

    if let Some(handle) = guard.as_ref() {
        let _ = cx.update_window(*handle, |_, window, _| {
            window.refresh();
        });
    } else {
        let options = WindowOptions {
            titlebar: None,
            window_bounds: Some(WindowBounds::Windowed(Bounds {
                origin: point(px(0.), px(0.)),
                size: Size::new(px(380.), px(460.)),
            })),
            app_id: Some("beskar-notifications".to_string()),
            window_background: WindowBackgroundAppearance::Transparent,
            kind: WindowKind::LayerShell(LayerShellOptions {
                namespace: "beskar-notifications".to_string(),
                layer: Layer::Overlay,
                anchor: LayerAnchor::TOP | LayerAnchor::RIGHT,
                exclusive_zone: None,
                margin: Some((px(48.), px(16.), px(0.), px(0.))),
                keyboard_interactivity: KeyboardInteractivity::None,
                ..Default::default()
            }),
            focus: false,
            ..Default::default()
        };

        if let Ok(handle) = cx.open_window(options, move |_window, cx| {
            cx.new(|_cx| NotificationToastQueueView)
        }) {
            *guard = Some(handle.into());
            info!("Opened dedicated LayerShell Notification Toast Queue window");
        }
    }
}

pub struct NotificationToastQueueView;

impl Render for NotificationToastQueueView {
    fn render(&mut self, window: &mut Window, _cx: &mut Context<Self>) -> impl IntoElement {
        let notifs = {
            let guard = NOTIFICATION_QUEUE.lock().unwrap();
            guard.clone()
        };

        if notifs.is_empty() {
            forget_notification_overlay();
            window.remove_window();
            return div();
        }

        div()
            .w(px(380.0))
            .flex()
            .flex_col()
            .gap(px(8.0))
            .children(notifs.into_iter().take(4).map(|n| {
                NotificationToastWidget::new(n)
                    .on_dismiss(|id| {
                        beskar_services::notifications::dismiss(id);
                    })
                    .on_invoke(|id, key| {
                        beskar_services::notifications::invoke(id, &key);
                    })
            }))
    }
}
