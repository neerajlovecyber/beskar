use anyhow::Result;
use async_trait::async_trait;
use tokio::sync::mpsc;

use crate::events::CompositorEvent;
use crate::models::{OutputInfo, WindowInfo, WorkspaceInfo};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CompositorKind {
    Niri,
    Umbriel,
    Hyprland,
    GenericWlroots,
}

#[async_trait]
pub trait CompositorBackend: Send + Sync {
    /// Return the name / kind of this compositor backend
    fn kind(&self) -> CompositorKind;

    /// Check if this compositor is currently running in the environment
    fn is_available(&self) -> bool;

    /// Subscribe to the live compositor event stream
    async fn start_listener(&self, tx: mpsc::Sender<CompositorEvent>) -> Result<()>;

    /// Fetch current workspaces snapshot
    async fn get_workspaces(&self) -> Result<Vec<WorkspaceInfo>>;

    /// Fetch current windows snapshot
    async fn get_windows(&self) -> Result<Vec<WindowInfo>>;

    /// Fetch current outputs snapshot
    async fn get_outputs(&self) -> Result<Vec<OutputInfo>>;

    /// Request switching focus to a workspace
    async fn focus_workspace(&self, id: u64) -> Result<()>;

    /// Request focusing a specific window
    async fn focus_window(&self, id: u64) -> Result<()>;

    /// Request closing a window
    async fn close_window(&self, id: u64) -> Result<()>;

    /// Request scrolling workspace (up/down)
    async fn scroll_workspace(&self, _dir: i32) -> Result<()> {
        Ok(())
    }
}

