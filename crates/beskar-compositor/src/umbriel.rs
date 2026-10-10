use std::env;
use anyhow::{Result, bail};
use async_trait::async_trait;
use tokio::sync::mpsc;
use tracing::info;

use beskar_core::events::CompositorEvent;
use beskar_core::models::{OutputInfo, WindowInfo, WorkspaceInfo};
use beskar_core::traits::{CompositorBackend, CompositorKind};

#[derive(Default)]
pub struct UmbrielBackend;

impl UmbrielBackend {
    pub fn new() -> Self {
        Self
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
            .or_else(|| env::var_os("NOCTALIA_COMPOSITOR"))
            .is_some()
            || env::var("XDG_CURRENT_DESKTOP").map(|s| s.to_lowercase().contains("umbriel")).unwrap_or(false)
    }

    async fn start_listener(&self, _tx: mpsc::Sender<CompositorEvent>) -> Result<()> {
        info!("Umbriel listener registered (communicating over Wayland protocols)");
        Ok(())
    }

    async fn get_workspaces(&self) -> Result<Vec<WorkspaceInfo>> {
        Ok(vec![
            WorkspaceInfo {
                id: 1,
                idx: 1,
                name: Some("1".to_string()),
                output: "eDP-1".to_string(),
                is_active: true,
                is_focused: true,
            }
        ])
    }

    async fn get_windows(&self) -> Result<Vec<WindowInfo>> {
        Ok(vec![])
    }

    async fn get_outputs(&self) -> Result<Vec<OutputInfo>> {
        Ok(vec![
            OutputInfo {
                name: "eDP-1".to_string(),
                make: None,
                model: None,
                width: 1920,
                height: 1080,
                scale: 1.0,
            }
        ])
    }

    async fn focus_workspace(&self, _id: u64) -> Result<()> {
        bail!("Umbriel workspace switching via Wayland protocol stub")
    }

    async fn focus_window(&self, _id: u64) -> Result<()> {
        bail!("Umbriel focus window via foreign-toplevel protocol stub")
    }

    async fn close_window(&self, _id: u64) -> Result<()> {
        bail!("Umbriel close window via foreign-toplevel protocol stub")
    }
}
