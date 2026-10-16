pub mod toast;
pub mod view;
pub mod widgets;

use beskar_services::{NotificationItem, NotificationStore};
use beskar_ui::components::InputState;
use gpui_kit::layer_shell::{Anchor as LayerAnchor, KeyboardInteractivity, Layer, LayerShellOptions};
use gpui_kit::prelude::*;
use gpui_kit::*;
use std::sync::Mutex;
use std::time::Duration;
use tracing::info;

use crate::panel_host::{PanelHost, PanelModule, Slot};

pub struct Reply {
    pub id: u32,
    pub input: InputState,
    pub pending: bool,
    pub failed: bool,
}

pub struct NotificationCenterView {
    pub items: Vec<NotificationItem>,
    pub latest: Option<NotificationItem>,
    pub reply: Option<Reply>,
    pub text_system: WindowTextSystem,
    pub focus: FocusHandle,
    _events: Task<()>,
    expiry: Option<Task<()>>,
    response: Option<Task<()>>,
}

impl PanelModule for NotificationCenterView {
    const ID: &'static str = "notification_center";

    fn slot() -> Slot {
        Slot::Right
    }

    fn size() -> Size<Pixels> {
        Size::new(px(widgets::WIDTH), px(widgets::HISTORY_HEIGHT))
    }

    fn anchor() -> LayerAnchor {
        LayerAnchor::TOP | LayerAnchor::RIGHT
    }

    fn margin() -> (Pixels, Pixels, Pixels, Pixels) {
        (px(48.0), px(16.0), px(0.0), px(0.0))
    }

    fn keyboard_interactivity() -> KeyboardInteractivity {
        KeyboardInteractivity::OnDemand
    }

    fn build(cx: &mut Context<Self>) -> Self {
        Self::new(cx)
    }
}

impl NotificationCenterView {
    pub fn new(cx: &mut Context<Self>) -> Self {
        let store = NotificationStore::global();
        let mut changes = store.subscribe();
        let events = cx.spawn(async move |this, cx| {
            while changes.changed().await.is_ok() {
                if this
                    .update(cx, |module: &mut Self, cx| module.refresh(cx))
                    .is_err()
                {
                    break;
                }
            }
        });

        let latest = store.get_latest_active_notification();
        let text_system = WindowTextSystem::new(cx.text_system().clone());
        let focus = cx.focus_handle();

        Self {
            items: store.get_all_notifications(),
            latest,
            reply: None,
            text_system,
            focus,
            _events: events,
            expiry: None,
            response: None,
        }
    }

    pub fn refresh(&mut self, cx: &mut Context<Self>) {
        let store = NotificationStore::global();
        self.items = store.get_all_notifications();
        self.latest = store.get_latest_active_notification();
        if self.reply.as_ref().is_some_and(|reply| {
            !store.contains_notification(reply.id)
        }) {
            self.reply = None;
            self.response = None;
            store.set_hovered(false);
        }
        self.schedule_expiry(cx);
        cx.notify();
    }

    pub fn schedule_expiry(&mut self, cx: &mut Context<Self>) {
        self.expiry = None;
        if self.reply.is_some() {
            return;
        }
        let Some(item) = &self.latest else {
            return;
        };
        let remaining = item.timeout.saturating_sub(item.received_at.elapsed());
        let delay = if remaining.is_zero() {
            Duration::from_secs(60)
        } else {
            remaining
        };
        self.expiry = Some(cx.spawn(async move |this, cx| {
            cx.background_executor().timer(delay).await;
            let _ = this.update(cx, |module, cx| module.refresh(cx));
        }));
    }

    pub fn dismiss(&mut self, id: u32) {
        NotificationStore::global().remove_notification(id);
    }

    pub fn clear_all(&mut self) {
        NotificationStore::global().clear_all_notifications();
    }

    pub fn action(&mut self, id: u32, key: String, window: &mut Window, cx: &mut Context<Self>) {
        if key != "inline-reply" {
            NotificationStore::global().invoke_action(id, key);
            return;
        }
        if !self
            .items
            .iter()
            .any(|item| item.id == id && item.actions.iter().any(|(k, _)| k == "inline-reply"))
        {
            return;
        }
        self.reply = Some(Reply {
            id,
            input: InputState::new("").with_focused(true).with_max_len(250),
            pending: false,
            failed: false,
        });
        NotificationStore::global().set_hovered(true);
        window.focus(&self.focus, cx);
        self.expiry = None;
        cx.notify();
    }

    pub fn cancel_reply(&mut self, cx: &mut Context<Self>) {
        if self.reply.as_ref().is_some_and(|reply| reply.pending) {
            return;
        }
        self.reply = None;
        NotificationStore::global().set_hovered(false);
        self.schedule_expiry(cx);
        cx.notify();
    }

    pub fn send_reply(&mut self, cx: &mut Context<Self>) {
        let Some(reply) = self
            .reply
            .as_mut()
            .filter(|reply| !reply.pending && !reply.input.is_empty())
        else {
            return;
        };
        let id = reply.id;
        let text = reply.input.text();
        reply.pending = true;
        reply.failed = false;
        let (sender, receiver) = tokio::sync::oneshot::channel();
        beskar_services::spawn_tokio(async move {
            let result = NotificationStore::global().reply(id, text).await;
            let _ = sender.send(result);
        });
        self.response = Some(cx.spawn(async move |this, cx| {
            let result = receiver.await;
            let _ = this.update(cx, |module, cx| {
                if let Some(reply) = module.reply.as_mut().filter(|reply| reply.id == id) {
                    reply.pending = false;
                    reply.failed = !matches!(result, Ok(Ok(())));
                    if !reply.failed {
                        module.reply = None;
                    }
                    cx.notify();
                }
            });
        }));
        cx.notify();
    }

    fn key_down(&mut self, event: &KeyDownEvent, _: &mut Window, cx: &mut Context<Self>) {
        let key = event.keystroke.key.as_str();
        if key == "escape" {
            if self.reply.is_some() {
                self.cancel_reply(cx);
            } else {
                PanelHost::close(cx);
            }
            cx.stop_propagation();
            return;
        }
        if key == "enter" && self.reply.is_some() {
            self.send_reply(cx);
            cx.stop_propagation();
            return;
        }
        let Some(reply) = self.reply.as_mut().filter(|reply| !reply.pending) else {
            return;
        };
        if reply.input.handle_key_down(event, cx) {
            reply.failed = false;
            cx.stop_propagation();
            cx.notify();
        }
    }
}

impl Focusable for NotificationCenterView {
    fn focus_handle(&self, _cx: &App) -> FocusHandle {
        self.focus.clone()
    }
}

impl Render for NotificationCenterView {
    fn render(&mut self, _: &mut Window, cx: &mut Context<Self>) -> impl IntoElement {
        div()
            .id("notification-center-module")
            .size_full()
            .track_focus(&self.focus)
            .on_key_down(cx.listener(Self::key_down))
            .child(widgets::render(self, cx))
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Notification Toast Overlay Window System
// ─────────────────────────────────────────────────────────────────────────────

static NOTIFICATION_OVERLAY: Mutex<Option<AnyWindowHandle>> = Mutex::new(None);
static NOTIFICATION_QUEUE: Mutex<Vec<beskar_core::models::NotificationItem>> = Mutex::new(Vec::new());

pub fn forget_notification_overlay() {
    let mut guard = NOTIFICATION_OVERLAY.lock().unwrap();
    guard.take();
}

pub fn sync_notification_toasts(notifications: Vec<beskar_core::models::NotificationItem>, cx: &mut App) {
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
                toast::NotificationToastWidget::new(n)
                    .on_dismiss(|id| {
                        beskar_services::notifications::dismiss(id);
                    })
                    .on_invoke(|id, key| {
                        beskar_services::notifications::invoke(id, &key);
                    })
            }))
    }
}
