//! Uniform start/stop lifecycle for services with background work.
//!
//! Extracted from `references/gpui-shell/crates/services/src/lifecycle.rs`
//! with `futures_signals::Mutable` replaced by `std::sync` + `tokio::sync::watch`
//! so no new workspace dependency is required. Semantics (generation
//! counter + RunToken::alive) are preserved verbatim.

use std::sync::{
    Arc,
    atomic::{AtomicU64, Ordering},
};

use serde::{Deserialize, Serialize};

/// How a service is brought up at startup.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum ServiceMode {
    #[default]
    Eager,
    Lazy,
    Off,
}

impl ServiceMode {
    pub const ALL: [ServiceMode; 3] = [ServiceMode::Eager, ServiceMode::Lazy, ServiceMode::Off];

    pub fn label(&self) -> &'static str {
        match self {
            ServiceMode::Eager => "eager",
            ServiceMode::Lazy => "lazy",
            ServiceMode::Off => "off",
        }
    }
}

/// Runtime status of a service.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ServiceStatus {
    Stopped,
    Initializing,
    Active,
    Error(Option<String>),
    Unavailable,
}

impl Default for ServiceStatus {
    fn default() -> Self {
        ServiceStatus::Stopped
    }
}

/// Shared status + run generation for one service.
#[derive(Debug, Clone)]
pub struct Lifecycle {
    status: Arc<std::sync::Mutex<ServiceStatus>>,
    mode: Arc<std::sync::Mutex<ServiceMode>>,
    generation: Arc<AtomicU64>,
    watch_tx: tokio::sync::watch::Sender<ServiceStatus>,
}

impl Lifecycle {
    pub fn new(mode: ServiceMode) -> Self {
        let (tx, _rx) = tokio::sync::watch::channel(ServiceStatus::Stopped);
        Self {
            status: Arc::new(std::sync::Mutex::new(ServiceStatus::Stopped)),
            mode: Arc::new(std::sync::Mutex::new(mode)),
            generation: Arc::new(AtomicU64::new(0)),
            watch_tx: tx,
        }
    }

    pub fn status(&self) -> ServiceStatus {
        self.status.lock().unwrap().clone()
    }

    pub fn status_watch(&self) -> tokio::sync::watch::Receiver<ServiceStatus> {
        self.watch_tx.subscribe()
    }

    pub fn mode(&self) -> ServiceMode {
        *self.mode.lock().unwrap()
    }

    pub fn set_mode(&self, mode: ServiceMode) {
        *self.mode.lock().unwrap() = mode;
    }

    /// True while the service is starting or running.
    pub fn is_up(&self) -> bool {
        !matches!(*self.status.lock().unwrap(), ServiceStatus::Stopped | ServiceStatus::Unavailable)
    }

    /// True when the service has never run or was stopped on request.
    pub fn is_stopped(&self) -> bool {
        matches!(*self.status.lock().unwrap(), ServiceStatus::Stopped)
    }

    /// Start a new run, invalidating any listener from a previous one.
    pub fn begin(&self) -> RunToken {
        let id = self.generation.fetch_add(1, Ordering::SeqCst) + 1;
        let token = RunToken {
            status: self.status.clone(),
            watch_tx: self.watch_tx.clone(),
            generation: self.generation.clone(),
            id,
        };
        token.set(ServiceStatus::Initializing);
        token
    }

    /// Stop the current run and mark the service stopped.
    pub fn stop(&self) {
        self.generation.fetch_add(1, Ordering::SeqCst);
        *self.status.lock().unwrap() = ServiceStatus::Stopped;
        let _ = self.watch_tx.send(ServiceStatus::Stopped);
    }

    /// Mark a service that has no work to do on this system.
    pub fn set_unavailable(&self) {
        self.generation.fetch_add(1, Ordering::SeqCst);
        *self.status.lock().unwrap() = ServiceStatus::Unavailable;
        let _ = self.watch_tx.send(ServiceStatus::Unavailable);
    }
}

impl Default for Lifecycle {
    fn default() -> Self {
        Self::new(ServiceMode::default())
    }
}

/// Handle held by a running listener.
#[derive(Debug, Clone)]
pub struct RunToken {
    status: Arc<std::sync::Mutex<ServiceStatus>>,
    watch_tx: tokio::sync::watch::Sender<ServiceStatus>,
    generation: Arc<AtomicU64>,
    id: u64,
}

impl RunToken {
    /// False once the service was stopped or restarted: exit the listener.
    pub fn alive(&self) -> bool {
        self.generation.load(Ordering::SeqCst) == self.id
    }

    pub fn set(&self, status: ServiceStatus) {
        if self.alive() {
            *self.status.lock().unwrap() = status.clone();
            let _ = self.watch_tx.send(status);
        }
    }

    pub fn active(&self) {
        self.set(ServiceStatus::Active);
    }

    pub fn error(&self, message: impl Into<String>) {
        self.set(ServiceStatus::Error(Some(message.into())));
    }
}

/// A service whose background work can be inspected and controlled.
pub trait ManagedService: Send + Sync {
    fn name(&self) -> &'static str;

    fn lifecycle(&self) -> &Lifecycle;

    fn memory_bytes(&self) -> usize;

    fn start(&self);

    fn controllable(&self) -> bool {
        true
    }

    fn status(&self) -> ServiceStatus {
        self.lifecycle().status()
    }

    fn mode(&self) -> ServiceMode {
        self.lifecycle().mode()
    }

    fn stop(&self) {
        self.lifecycle().stop();
    }

    fn restart(&self) {
        self.start();
    }

    fn ensure_started(&self) {
        if self.lifecycle().mode() == ServiceMode::Lazy && self.lifecycle().is_stopped() {
            self.start();
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn stop_and_restart_invalidate_the_previous_run() {
        let lifecycle = Lifecycle::new(ServiceMode::Eager);

        let first = lifecycle.begin();
        first.active();
        assert!(first.alive());
        assert_eq!(lifecycle.status(), ServiceStatus::Active);

        let second = lifecycle.begin();
        assert!(!first.alive());
        assert!(second.alive());

        first.error("stale");
        assert_eq!(lifecycle.status(), ServiceStatus::Initializing);

        second.active();
        lifecycle.stop();
        assert!(!second.alive());
        assert_eq!(lifecycle.status(), ServiceStatus::Stopped);
        assert!(!lifecycle.is_up());

        second.active();
        assert_eq!(lifecycle.status(), ServiceStatus::Stopped);
    }

    #[test]
    fn service_mode_labels() {
        assert_eq!(ServiceMode::Eager.label(), "eager");
        assert_eq!(ServiceMode::Lazy.label(), "lazy");
        assert_eq!(ServiceMode::Off.label(), "off");
    }
}
