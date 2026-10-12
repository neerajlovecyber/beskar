use std::env;
use std::thread;

use anyhow::{Result, anyhow};
use async_trait::async_trait;
use hyprland::{
    data::{Client, Clients, Monitors, Workspace as HWorkspace, Workspaces},
    dispatch::{
        Dispatch, DispatchType, WindowIdentifier, WorkspaceIdentifierWithSpecial,
    },
    event_listener::EventListener,
    prelude::*,
};
use tokio::sync::mpsc;
use tracing::{debug, error, info};

use beskar_core::events::CompositorEvent;
use beskar_core::models::{OutputInfo, WindowInfo, WorkspaceInfo};
use beskar_core::traits::{CompositorBackend, CompositorKind};

/// Multi-compositor backend implementation for Hyprland.
///
/// Communicates over `/tmp/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket.sock` and
/// `.socket2.sock` using `hyprland-rs`.
#[derive(Default)]
pub struct HyprlandBackend;

impl HyprlandBackend {
    pub fn new() -> Self {
        Self
    }
}

#[async_trait]
impl CompositorBackend for HyprlandBackend {
    fn kind(&self) -> CompositorKind {
        CompositorKind::Hyprland
    }

    fn is_available(&self) -> bool {
        env::var_os("HYPRLAND_INSTANCE_SIGNATURE").is_some()
    }

    async fn start_listener(&self, tx: mpsc::Sender<CompositorEvent>) -> Result<()> {
        if !self.is_available() {
            return Err(anyhow!("HYPRLAND_INSTANCE_SIGNATURE environment variable not set"));
        }

        info!("Starting Hyprland live IPC event stream");

        thread::spawn(move || {
            let mut listener = EventListener::new();

            // 1. Workspace focus changed
            {
                let tx = tx.clone();
                listener.add_workspace_changed_handler(move |evt| {
                    let ws_id = evt.id.max(1) as u64;
                    debug!("Hyprland workspace changed to #{}", ws_id);
                    let _ = tx.try_send(CompositorEvent::WorkspaceFocused(ws_id));

                    // Refresh all workspaces
                    if let Ok(workspaces) = Workspaces::get() {
                        let active_id = HWorkspace::get_active().ok().map(|w| w.id);
                        let list: Vec<WorkspaceInfo> = workspaces
                            .into_iter()
                            .map(|w| {
                                let is_focused = Some(w.id) == active_id;
                                WorkspaceInfo {
                                    id: w.id.max(1) as u64,
                                    idx: (w.id.max(1) % 255) as u8,
                                    name: Some(w.name),
                                    output: w.monitor,
                                    is_active: is_focused,
                                    is_focused,
                                }
                            })
                            .collect();
                        let _ = tx.try_send(CompositorEvent::WorkspacesChanged(list));
                    }
                });
            }

            // 2. Active window changed
            {
                let tx = tx.clone();
                listener.add_active_window_changed_handler(move |evt| {
                    let win = evt.map(|w| WindowInfo {
                        id: 0,
                        title: Some(w.title),
                        app_id: Some(w.class),
                        workspace_id: None,
                        is_focused: true,
                    });
                    let _ = tx.try_send(CompositorEvent::WindowFocused(win));
                });
            }

            // 3. Window opened/closed/moved
            {
                let tx = tx.clone();
                listener.add_window_opened_handler(move |_| {
                    Self::refresh_windows_sync(&tx);
                });
            }
            {
                let tx = tx.clone();
                listener.add_window_closed_handler(move |_| {
                    Self::refresh_windows_sync(&tx);
                });
            }

            // 4. Monitors / outputs changed
            {
                let tx = tx.clone();
                listener.add_monitor_added_handler(move |_| {
                    let _ = tx.try_send(CompositorEvent::OutputsChanged);
                });
            }
            {
                let tx = tx.clone();
                listener.add_monitor_removed_handler(move |_| {
                    let _ = tx.try_send(CompositorEvent::OutputsChanged);
                });
            }

            if let Err(e) = listener.start_listener() {
                error!("Hyprland event stream exited with error: {}", e);
            }
        });

        Ok(())
    }

    async fn get_workspaces(&self) -> Result<Vec<WorkspaceInfo>> {
        let workspaces = Workspaces::get().map_err(|e| anyhow!("Failed to fetch Hyprland workspaces: {}", e))?;
        let active_id = HWorkspace::get_active().ok().map(|w| w.id);

        let list = workspaces
            .into_iter()
            .map(|w| {
                let is_focused = Some(w.id) == active_id;
                WorkspaceInfo {
                    id: w.id.max(1) as u64,
                    idx: (w.id.max(1) % 255) as u8,
                    name: Some(w.name),
                    output: w.monitor,
                    is_active: is_focused,
                    is_focused,
                }
            })
            .collect();

        Ok(list)
    }

    async fn get_windows(&self) -> Result<Vec<WindowInfo>> {
        let clients = Clients::get().map_err(|e| anyhow!("Failed to fetch Hyprland clients: {}", e))?;
        let active_address = Client::get_active().ok().flatten().map(|c| c.address);

        let list = clients
            .into_iter()
            .map(|c| {
                let is_focused = Some(&c.address) == active_address.as_ref();
                WindowInfo {
                    id: c.pid as u64,
                    title: Some(c.title),
                    app_id: Some(c.class),
                    workspace_id: Some(c.workspace.id.max(1) as u64),
                    is_focused,
                }
            })
            .collect();

        Ok(list)
    }

    async fn get_outputs(&self) -> Result<Vec<OutputInfo>> {
        let monitors = Monitors::get().map_err(|e| anyhow!("Failed to fetch Hyprland monitors: {}", e))?;

        let list = monitors
            .into_iter()
            .map(|m| OutputInfo {
                name: m.name,
                make: None,
                model: Some(m.description),
                width: m.width as u32,
                height: m.height as u32,
                scale: m.scale as f64,
            })
            .collect();

        Ok(list)
    }

    async fn focus_workspace(&self, id: u64) -> Result<()> {
        Dispatch::call(DispatchType::Workspace(WorkspaceIdentifierWithSpecial::Id(
            id as i32,
        )))
        .map_err(|e| anyhow!("Failed to focus Hyprland workspace: {}", e))?;
        Ok(())
    }

    async fn focus_window(&self, id: u64) -> Result<()> {
        Dispatch::call(DispatchType::FocusWindow(WindowIdentifier::ProcessId(
            id as u32,
        )))
        .map_err(|e| anyhow!("Failed to focus Hyprland window: {}", e))?;
        Ok(())
    }

    async fn close_window(&self, id: u64) -> Result<()> {
        Dispatch::call(DispatchType::CloseWindow(WindowIdentifier::ProcessId(
            id as u32,
        )))
        .map_err(|e| anyhow!("Failed to close Hyprland window: {}", e))?;
        Ok(())
    }

    async fn scroll_workspace(&self, dir: i32) -> Result<()> {
        let d = if dir > 0 { "+1" } else { "-1" };
        Dispatch::call(DispatchType::Workspace(
            WorkspaceIdentifierWithSpecial::Relative(d.to_string().parse()?),
        ))
        .map_err(|e| anyhow!("Failed to scroll Hyprland workspace: {}", e))?;
        Ok(())
    }
}

impl HyprlandBackend {
    fn refresh_windows_sync(tx: &mpsc::Sender<CompositorEvent>) {
        if let Ok(clients) = Clients::get() {
            let active_address = Client::get_active().ok().flatten().map(|c| c.address);
            let list: Vec<WindowInfo> = clients
                .into_iter()
                .map(|c| {
                    let is_focused = Some(&c.address) == active_address.as_ref();
                    WindowInfo {
                        id: c.pid as u64,
                        title: Some(c.title),
                        app_id: Some(c.class),
                        workspace_id: Some(c.workspace.id.max(1) as u64),
                        is_focused,
                    }
                })
                .collect();
            let _ = tx.try_send(CompositorEvent::WindowsChanged(list));
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_hyprland_backend_kind_and_detection() {
        let backend = HyprlandBackend::new();
        assert_eq!(backend.kind(), CompositorKind::Hyprland);

        // When environment variable is unset, should return false gracefully
        unsafe {
            env::remove_var("HYPRLAND_INSTANCE_SIGNATURE");
        }
        assert!(!backend.is_available());

        // When environment variable is set, should detect as available
        unsafe {
            env::set_var("HYPRLAND_INSTANCE_SIGNATURE", "test_hyprland_session_123");
        }
        assert!(backend.is_available());

        unsafe {
            env::remove_var("HYPRLAND_INSTANCE_SIGNATURE");
        }
    }
}
