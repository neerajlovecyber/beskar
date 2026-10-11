use serde::{Deserialize, Serialize};
use std::sync::Arc;
use tokio::sync::RwLock;

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct SystemUpdatesState {
    pub pacman_count: u32,
    pub aur_count: u32,
    pub is_checking: bool,
    pub last_checked: Option<String>,
}

pub struct UpdateService {
    state: Arc<RwLock<SystemUpdatesState>>,
}

impl Default for UpdateService {
    fn default() -> Self {
        Self::new()
    }
}

impl UpdateService {
    pub fn new() -> Self {
        Self {
            state: Arc::new(RwLock::new(SystemUpdatesState::default())),
        }
    }

    pub fn shared_state(&self) -> Arc<RwLock<SystemUpdatesState>> {
        self.state.clone()
    }

    pub fn read_state(&self) -> SystemUpdatesState {
        if let Ok(guard) = self.state.try_read() {
            guard.clone()
        } else {
            SystemUpdatesState::default()
        }
    }

    /// Read cached or initial state
    pub fn cached() -> SystemUpdatesState {
        SystemUpdatesState::default()
    }

    /// Asynchronously check system updates and return updated snapshot
    pub async fn check_system_updates() -> SystemUpdatesState {
        let svc = Self::new();
        svc.check_updates().await;
        svc.read_state()
    }

    /// Launch terminal system update
    pub fn run_system_update() {
        let terminals = [
            "alacritty",
            "kitty",
            "foot",
            "wezterm",
            "gnome-terminal",
            "konsole",
            "xterm",
        ];
        for term in terminals {
            if let Ok(child) = std::process::Command::new(term)
                .args(["-e", "paru", "-Syu"])
                .spawn()
            {
                let _ = child.id();
                return;
            }
        }
    }

    pub async fn check_updates(&self) {
        {
            let mut w = self.state.write().await;
            w.is_checking = true;
        }

        let pacman_count = tokio::task::spawn_blocking(|| {
            let out = std::process::Command::new("checkupdates").output();
            if let Ok(o) = out {
                if o.status.success() {
                    let s = String::from_utf8_lossy(&o.stdout);
                    return s.lines().count() as u32;
                }
            }
            0
        })
        .await
        .unwrap_or(0);

        let aur_count = tokio::task::spawn_blocking(|| {
            // Try paru first, then yay
            let out_paru = std::process::Command::new("paru").args(["-Qua"]).output();
            if let Ok(o) = out_paru {
                if o.status.success() {
                    let s = String::from_utf8_lossy(&o.stdout);
                    return s.lines().count() as u32;
                }
            }
            let out_yay = std::process::Command::new("yay").args(["-Qua"]).output();
            if let Ok(o) = out_yay {
                if o.status.success() {
                    let s = String::from_utf8_lossy(&o.stdout);
                    return s.lines().count() as u32;
                }
            }
            0
        })
        .await
        .unwrap_or(0);

        let mut w = self.state.write().await;
        w.is_checking = false;
        w.pacman_count = pacman_count;
        w.aur_count = aur_count;
        let now = chrono::Local::now();
        w.last_checked = Some(now.format("%H:%M").to_string());
    }
}
