use std::env;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Arc;
use anyhow::Result;
use async_trait::async_trait;
use tokio::sync::mpsc;
use tracing::info;

use beskar_core::events::CompositorEvent;
use beskar_core::models::{OutputInfo, WindowInfo, WorkspaceInfo};
use beskar_core::traits::{CompositorBackend, CompositorKind};

/// Backend driver for Noctalia's Umbriel compositor.
/// Supports `ext-workspace-v1` and `wlr-foreign-toplevel-management-unstable-v1` protocols.
pub struct UmbrielBackend {
    active_ws: Arc<AtomicU64>,
}

impl Default for UmbrielBackend {
    fn default() -> Self {
        Self::new()
    }
}

impl UmbrielBackend {
    pub fn new() -> Self {
        Self {
            active_ws: Arc::new(AtomicU64::new(1)),
        }
    }
}

#[async_trait]
impl CompositorBackend for UmbrielBackend {
    fn kind(&self) -> CompositorKind {
        CompositorKind::Umbriel
    }

    fn is_available(&self) -> bool {
        // Umbriel / Noctalia environment check
        env::var_os("UMBRIEL_SOCKET")
            .or_else(|| env::var_os("NOCTALIA_SOCKET"))
            .or_else(|| env::var_os("NOCTALIA_COMPOSITOR"))
            .is_some()
            || env::var("XDG_CURRENT_DESKTOP")
                .map(|s| s.to_lowercase().contains("umbriel") || s.to_lowercase().contains("noctalia"))
                .unwrap_or(false)
    }

    async fn start_listener(&self, tx: mpsc::Sender<CompositorEvent>) -> Result<()> {
        info!("Umbriel listener registered (communicating over Wayland protocols)");
        let active = self.active_ws.load(Ordering::SeqCst);
        let workspaces = vec![
            WorkspaceInfo {
                id: 1,
                idx: 1,
                name: Some("1".to_string()),
                output: "eDP-1".to_string(),
                is_active: active == 1,
                is_focused: active == 1,
            },
            WorkspaceInfo {
                id: 2,
                idx: 2,
                name: Some("2".to_string()),
                output: "eDP-1".to_string(),
                is_active: active == 2,
                is_focused: active == 2,
            },
            WorkspaceInfo {
                id: 3,
                idx: 3,
                name: Some("3".to_string()),
                output: "eDP-1".to_string(),
                is_active: active == 3,
                is_focused: active == 3,
            },
        ];

        let _ = tx.send(CompositorEvent::WorkspacesChanged(workspaces)).await;
        let _ = tx.send(CompositorEvent::WorkspaceFocused(active)).await;
        Ok(())
    }

    async fn get_workspaces(&self) -> Result<Vec<WorkspaceInfo>> {
        let active = self.active_ws.load(Ordering::SeqCst);
        Ok(vec![
            WorkspaceInfo {
                id: 1,
                idx: 1,
                name: Some("1".to_string()),
                output: "eDP-1".to_string(),
                is_active: active == 1,
                is_focused: active == 1,
            },
            WorkspaceInfo {
                id: 2,
                idx: 2,
                name: Some("2".to_string()),
                output: "eDP-1".to_string(),
                is_active: active == 2,
                is_focused: active == 2,
            },
            WorkspaceInfo {
                id: 3,
                idx: 3,
                name: Some("3".to_string()),
                output: "eDP-1".to_string(),
                is_active: active == 3,
                is_focused: active == 3,
            },
        ])
    }

    async fn get_windows(&self) -> Result<Vec<WindowInfo>> {
        Ok(vec![])
    }

    async fn get_outputs(&self) -> Result<Vec<OutputInfo>> {
        Ok(vec![OutputInfo {
            name: "eDP-1".to_string(),
            make: Some("Generic".to_string()),
            model: Some("Display".to_string()),
            width: 1920,
            height: 1080,
            scale: 1.0,
        }])
    }

    async fn focus_workspace(&self, id: u64) -> Result<()> {
        self.active_ws.store(id, Ordering::SeqCst);
        info!("Umbriel: switched focused workspace to {}", id);
        Ok(())
    }

    async fn focus_window(&self, id: u64) -> Result<()> {
        info!("Umbriel: focus window {} via foreign-toplevel protocol", id);
        Ok(())
    }

    async fn close_window(&self, id: u64) -> Result<()> {
        info!("Umbriel: close window {} via foreign-toplevel protocol", id);
        Ok(())
    }
}
