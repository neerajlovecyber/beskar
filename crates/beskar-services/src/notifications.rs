use crate::sysvalue::SysValue;
use std::collections::HashMap;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex, OnceLock};
use std::time::{Duration, Instant};
use tracing::{info, warn};

/// Freedesktop Notification item representing an incoming or historical notification.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct NotificationItem {
    pub id: u32,
    pub app_name: String,
    pub app_icon: String,
    pub summary: String,
    pub body: String,
    pub actions: Vec<(String, String)>,
    pub received_at: Instant,
    pub timeout: Duration,
    pub urgency: u8,
}

#[derive(Default)]
pub(crate) struct LatestNotification {
    pub(crate) item: Option<NotificationItem>,
    pub(crate) hovered_at: Option<Instant>,
}

/// Global, reactive notification store conforming strictly to Capsule's NotificationStore API.
#[derive(Clone)]
pub struct NotificationStore {
    pub(crate) items: Arc<Mutex<Vec<NotificationItem>>>,
    pub(crate) latest_notification: Arc<Mutex<LatestNotification>>,
    pub(crate) connection: Arc<OnceLock<zbus::Connection>>,
    pub(crate) senders: Arc<Mutex<HashMap<u32, zbus::names::OwnedUniqueName>>>,
    counter: Arc<Mutex<u32>>,
    dnd: Arc<AtomicBool>,
    changes: tokio::sync::watch::Sender<()>,
}

impl Default for NotificationStore {
    fn default() -> Self {
        Self::new()
    }
}

impl NotificationStore {
    pub fn new() -> Self {
        let (tx, _) = tokio::sync::watch::channel(());
        Self {
            items: Arc::new(Mutex::new(Vec::new())),
            latest_notification: Arc::new(Mutex::new(LatestNotification::default())),
            connection: Arc::new(OnceLock::new()),
            senders: Arc::new(Mutex::new(HashMap::new())),
            counter: Arc::new(Mutex::new(1)),
            dnd: Arc::new(AtomicBool::new(false)),
            changes: tx,
        }
    }

    pub fn global() -> &'static Self {
        static INSTANCE: OnceLock<NotificationStore> = OnceLock::new();
        INSTANCE.get_or_init(|| {
            let store = NotificationStore::new();
            let store_clone = store.clone();
            crate::spawn_tokio(async move {
                if let Err(e) = start_notification_server_inner(store_clone).await {
                    warn!("Failed to start D-Bus NotificationServer: {e}");
                }
            });
            store
        })
    }

    pub fn subscribe(&self) -> tokio::sync::watch::Receiver<()> {
        self.changes.subscribe()
    }

    pub fn add_notification(
        &self,
        app_name: String,
        app_icon: String,
        summary: String,
        body: String,
        timeout_ms: i32,
    ) -> u32 {
        self.add_notification_with_actions(
            (app_name, app_icon, summary, body),
            timeout_ms,
            Vec::new(),
            None,
            1,
        )
    }

    pub fn add_notification_with_actions(
        &self,
        content: (String, String, String, String),
        timeout_ms: i32,
        actions: Vec<String>,
        sender: Option<zbus::names::OwnedUniqueName>,
        urgency: u8,
    ) -> u32 {
        let mut senders = self
            .senders
            .lock()
            .unwrap_or_else(|error| error.into_inner());
        let (app_name, app_icon, summary, body) = content;
        let mut cnt_guard = self
            .counter
            .lock()
            .unwrap_or_else(|error| error.into_inner());
        let id = *cnt_guard;
        *cnt_guard = cnt_guard.wrapping_add(1).max(1);
        if let Some(sender) = sender {
            senders.insert(id, sender);
        } else {
            senders.remove(&id);
        }

        let timeout_duration = if timeout_ms > 0 {
            Duration::from_millis(timeout_ms as u64)
        } else {
            Duration::from_secs(5)
        };

        let parsed_actions: Vec<(String, String)> = actions
            .chunks_exact(2)
            .map(|chunk| (chunk[0].clone(), chunk[1].clone()))
            .collect();

        let item = NotificationItem {
            id,
            app_name,
            app_icon,
            summary: strip_markup(&summary),
            body: strip_markup(&body),
            actions: parsed_actions,
            received_at: Instant::now(),
            timeout: timeout_duration,
            urgency,
        };

        if let Ok(mut items_guard) = self.items.lock() {
            if items_guard.len() >= 100 {
                items_guard.remove(0);
            }
            items_guard.push(item.clone());
        }

        if !self.is_dnd_enabled() {
            if let Ok(mut latest_guard) = self.latest_notification.lock() {
                *latest_guard = LatestNotification {
                    item: Some(item),
                    hovered_at: None,
                };
            }
        }

        let _ = self.changes.send(());
        id
    }

    pub fn is_dnd_enabled(&self) -> bool {
        self.dnd.load(Ordering::SeqCst)
    }

    pub fn set_dnd(&self, enabled: bool) {
        self.dnd.store(enabled, Ordering::SeqCst);
        let _ = self.changes.send(());
    }

    pub fn toggle_dnd(&self) -> bool {
        let prev = self.dnd.fetch_xor(true, Ordering::SeqCst);
        let _ = self.changes.send(());
        !prev
    }

    pub fn get_latest_active_notification(&self) -> Option<NotificationItem> {
        if self.is_dnd_enabled() {
            return None;
        }
        if let Ok(guard) = self.latest_notification.lock() {
            if let Some(item) = guard.item.as_ref() {
                let is_hover_active = guard
                    .hovered_at
                    .as_ref()
                    .is_some_and(|hovered_at| hovered_at.elapsed() < Duration::from_secs(60));
                if is_hover_active || item.received_at.elapsed() < item.timeout {
                    return Some(item.clone());
                }
            }
        }
        None
    }

    pub fn set_hovered(&self, hovered: bool) {
        self.set_hovered_at(hovered, Instant::now());
        let _ = self.changes.send(());
    }

    pub fn set_hovered_at(&self, hovered: bool, now: Instant) {
        let Ok(mut latest) = self.latest_notification.lock() else {
            return;
        };
        if hovered {
            if latest.hovered_at.is_none()
                && latest.item.as_ref().is_some_and(|item| {
                    now.saturating_duration_since(item.received_at) < item.timeout
                })
            {
                latest.hovered_at = Some(now);
            }
        } else if let Some(hovered_at) = latest.hovered_at.take() {
            if let Some(item) = latest.item.as_mut() {
                let paused_duration = now
                    .saturating_duration_since(hovered_at)
                    .min(Duration::from_secs(60));
                if let Some(received_at) = item.received_at.checked_add(paused_duration) {
                    item.received_at = received_at;
                }
            }
        }
    }

    pub fn invoke_action(&self, id: u32, key: String) {
        let valid = self.items.lock().is_ok_and(|items| {
            items
                .iter()
                .any(|item| item.id == id && item.actions.iter().any(|(action, _)| action == &key))
        });
        if !valid {
            return;
        }
        let Some(connection) = self.connection.get().cloned() else {
            self.remove_notification(id);
            return;
        };
        let store = self.clone();
        crate::spawn_tokio(async move {
            if connection
                .emit_signal(
                    None::<&str>,
                    "/org/freedesktop/Notifications",
                    "org.freedesktop.Notifications",
                    "ActionInvoked",
                    &(id, &key),
                )
                .await
                .is_ok()
            {
                store.remove_notification(id);
            }
        });
    }

    pub async fn reply(&self, id: u32, text: String) -> anyhow::Result<()> {
        anyhow::ensure!(!text.trim().is_empty(), "Reply text must not be blank");
        {
            let items = self
                .items
                .lock()
                .map_err(|_| anyhow::anyhow!("Notification store lock is poisoned"))?;
            let item = items
                .iter()
                .find(|item| item.id == id)
                .ok_or_else(|| anyhow::anyhow!("Notification {id} was not found"))?;
            anyhow::ensure!(
                item.actions.iter().any(|(key, _)| key == "inline-reply"),
                "Notification {id} does not advertise inline-reply"
            );
        }
        let sender = self
            .senders
            .lock()
            .map_err(|_| anyhow::anyhow!("Notification sender map lock is poisoned"))?
            .get(&id)
            .cloned()
            .ok_or_else(|| anyhow::anyhow!("Notification {id} has no recorded sender"))?;
        let connection = self
            .connection
            .get()
            .ok_or_else(|| anyhow::anyhow!("Notification server connection is not initialized"))?;
        let emitter =
            zbus::object_server::SignalEmitter::new(connection, "/org/freedesktop/Notifications")?
                .set_destination(sender.into());
        NotificationServer::notification_replied(&emitter, id, text).await?;
        self.remove_notification(id);
        Ok(())
    }

    pub fn contains_notification(&self, id: u32) -> bool {
        self.items
            .lock()
            .is_ok_and(|items| items.iter().any(|item| item.id == id))
    }

    pub fn get_all_notifications(&self) -> Vec<NotificationItem> {
        self.items.lock().map(|i| i.clone()).unwrap_or_default()
    }

    pub fn remove_notification(&self, id: u32) {
        let mut senders = self
            .senders
            .lock()
            .unwrap_or_else(|error| error.into_inner());
        senders.remove(&id);
        if let Ok(mut items_guard) = self.items.lock() {
            items_guard.retain(|item| item.id != id);
        }
        if let Ok(mut latest_guard) = self.latest_notification.lock() {
            if let Some(item) = latest_guard.item.as_ref() {
                if item.id == id {
                    *latest_guard = LatestNotification::default();
                }
            }
        }
        let _ = self.changes.send(());
    }

    pub fn clear_all_notifications(&self) {
        let mut senders = self
            .senders
            .lock()
            .unwrap_or_else(|error| error.into_inner());
        senders.clear();
        if let Ok(mut items_guard) = self.items.lock() {
            items_guard.clear();
        }
        if let Ok(mut latest_guard) = self.latest_notification.lock() {
            *latest_guard = LatestNotification::default();
        }
        let _ = self.changes.send(());
    }
}

pub struct NotificationServer {
    pub(crate) store: NotificationStore,
}

#[zbus::interface(name = "org.freedesktop.Notifications")]
impl NotificationServer {
    #[allow(clippy::too_many_arguments)]
    pub(crate) async fn notify(
        &self,
        app_name: String,
        replaces_id: u32,
        app_icon: String,
        summary: String,
        body: String,
        actions: Vec<String>,
        hints: std::collections::HashMap<String, zbus::zvariant::Value<'_>>,
        expire_timeout: i32,
        #[zbus(header)] header: zbus::message::Header<'_>,
    ) -> u32 {
        let hint_urgency = hints
            .get("urgency")
            .and_then(|v| u8::try_from(v).ok())
            .unwrap_or(1);
        let id = self.store.add_notification_with_actions(
            (app_name, app_icon, summary, body),
            expire_timeout,
            actions,
            header.sender().map(|sender| sender.to_owned().into()),
            hint_urgency,
        );
        if replaces_id > 0 && replaces_id != id {
            self.store.remove_notification(replaces_id);
        }
        id
    }

    pub(crate) async fn close_notification(&self, id: u32) {
        self.store.remove_notification(id);
    }

    #[zbus(signal)]
    pub(crate) async fn notification_replied(
        emitter: &zbus::object_server::SignalEmitter<'_>,
        id: u32,
        text: String,
    ) -> zbus::Result<()>;

    #[zbus(signal)]
    pub(crate) async fn action_invoked(
        emitter: &zbus::object_server::SignalEmitter<'_>,
        id: u32,
        action_key: &str,
    ) -> zbus::Result<()>;

    #[zbus(signal)]
    pub(crate) async fn notification_closed(
        emitter: &zbus::object_server::SignalEmitter<'_>,
        id: u32,
        reason: u32,
    ) -> zbus::Result<()>;

    pub(crate) async fn get_capabilities(&self) -> Vec<String> {
        vec![
            "body".to_string(),
            "body-markup".to_string(),
            "actions".to_string(),
            "inline-reply".to_string(),
            "icon-static".to_string(),
            "persistence".to_string(),
        ]
    }

    pub(crate) async fn get_server_information(&self) -> (String, String, String, String) {
        (
            "Beskar Notifications".to_string(),
            "Beskar".to_string(),
            env!("CARGO_PKG_VERSION").to_string(),
            "1.2".to_string(),
        )
    }
}

async fn start_notification_server_inner(store: NotificationStore) -> anyhow::Result<()> {
    if store.connection.get().is_some() {
        return Ok(());
    }
    let server = NotificationServer {
        store: store.clone(),
    };
    use zbus::fdo::RequestNameFlags;
    let flags = RequestNameFlags::AllowReplacement | RequestNameFlags::ReplaceExisting;
    let connection = zbus::connection::Builder::session()?
        .serve_at("/org/freedesktop/Notifications", server)?
        .build()
        .await?;
    let _ = connection
        .request_name_with_flags("org.freedesktop.Notifications", flags)
        .await;
    let _ = store.connection.set(connection);
    info!("Freedesktop D-Bus NotificationServer active");
    Ok(())
}

fn strip_markup(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    let mut inside = false;
    for c in s.chars() {
        match c {
            '<' => inside = true,
            '>' if inside => inside = false,
            _ if !inside => out.push(c),
            _ => {}
        }
    }
    out.replace("&amp;", "&")
        .replace("&lt;", "<")
        .replace("&gt;", ">")
        .replace("&quot;", "\"")
        .replace("&apos;", "'")
}

// ─────────────────────────────────────────────────────────────────────────────
// Compatibility Shims for Hub, Bar and Legacy Services
// ─────────────────────────────────────────────────────────────────────────────

pub fn service(dispatch: Box<dyn Fn(SysValue) + Send>) -> bool {
    let store = NotificationStore::global();
    let mut rx = store.subscribe();
    crate::spawn_tokio(async move {
        // Send initial state
        let notifs = NotificationStore::global().get_all_notifications();
        dispatch(sysvalue_from_notifs(&notifs));

        while rx.changed().await.is_ok() {
            let notifs = NotificationStore::global().get_all_notifications();
            dispatch(sysvalue_from_notifs(&notifs));
        }
    });
    true
}

pub fn history(dispatch: Box<dyn Fn(SysValue) + Send>) -> bool {
    service(dispatch)
}

fn sysvalue_from_notifs(all: &[NotificationItem]) -> SysValue {
    let text = |s: &str| SysValue::Text(s.to_owned());
    SysValue::List(
        all.iter()
            .rev()
            .map(|a| {
                SysValue::Map(vec![
                    ("id".into(), SysValue::Num(a.id as f64)),
                    ("app".into(), text(&a.app_name)),
                    ("title".into(), text(&a.summary)),
                    ("body".into(), text(&a.body)),
                    ("icon".into(), text(&a.app_icon)),
                    ("image".into(), text("")),
                    ("urgency".into(), SysValue::Num(a.urgency as f64)),
                    ("time".into(), SysValue::Num(0.0)),
                    (
                        "actions".into(),
                        SysValue::List(
                            a.actions
                                .iter()
                                .map(|(k, l)| {
                                    SysValue::Map(vec![
                                        ("key".into(), text(k)),
                                        ("label".into(), text(l)),
                                    ])
                                })
                                .collect(),
                        ),
                    ),
                ])
            })
            .collect(),
    )
}

pub fn command(what: &str, args: &[SysValue]) -> Result<(), String> {
    match (what, args) {
        ("notifications.dismiss", [SysValue::Num(id)]) => {
            NotificationStore::global().remove_notification(*id as u32);
        }
        ("notifications.invoke", [SysValue::Num(id), SysValue::Text(key)]) => {
            NotificationStore::global().invoke_action(*id as u32, key.clone());
        }
        ("notifications.clear" | "notifications.clear_history", []) => {
            NotificationStore::global().clear_all_notifications();
        }
        _ => return Err(format!("Unsupported command '{what}'")),
    }
    Ok(())
}

pub fn dismiss(id: u32) {
    NotificationStore::global().remove_notification(id);
}

pub fn invoke(id: u32, key: &str) {
    NotificationStore::global().invoke_action(id, key.to_string());
}

pub fn clear() {
    NotificationStore::global().clear_all_notifications();
}

pub fn clear_all() {
    clear();
}

pub fn send_test(summary: &str, body: &str) {
    NotificationStore::global().add_notification(
        "Beskar Shell".to_string(),
        "preferences-system".to_string(),
        summary.to_string(),
        body.to_string(),
        8000,
    );
}

pub fn get_notifications() -> Vec<beskar_core::models::NotificationItem> {
    NotificationStore::global()
        .get_all_notifications()
        .into_iter()
        .rev()
        .map(|n| beskar_core::models::NotificationItem {
            id: n.id,
            app_name: n.app_name,
            summary: n.summary,
            body: n.body,
            icon: n.app_icon,
            urgency: n.urgency,
            time_secs: n.received_at.elapsed().as_secs(),
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_notification_store_crud_and_dnd() {
        let store = NotificationStore::new();
        assert_eq!(store.get_all_notifications().len(), 0);

        let id = store.add_notification(
            "TestApp".into(),
            "bell".into(),
            "Hello".into(),
            "World".into(),
            5000,
        );
        assert_eq!(store.get_all_notifications().len(), 1);
        assert!(store.contains_notification(id));

        let latest = store.get_latest_active_notification();
        assert!(latest.is_some());
        assert_eq!(latest.unwrap().summary, "Hello");

        // DND test
        store.set_dnd(true);
        assert!(store.is_dnd_enabled());
        assert!(store.get_latest_active_notification().is_none());

        store.set_dnd(false);
        assert!(store.get_latest_active_notification().is_some());

        // Hover test
        store.set_hovered(true);
        store.set_hovered(false);

        // Remove test
        store.remove_notification(id);
        assert_eq!(store.get_all_notifications().len(), 0);
        assert!(!store.contains_notification(id));
    }
}
