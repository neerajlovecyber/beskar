use std::{
    env,
    io::{BufRead, BufReader, Write as _},
    os::unix::net::UnixStream,
    thread,
};

use anyhow::{Context, Result, anyhow};
use async_trait::async_trait;
use niri_ipc::{
    Action, Event, Reply, Request, WorkspaceReferenceArg,
    state::{EventStreamState, EventStreamStatePart},
};
use tokio::sync::mpsc;
use tracing::{debug, error, info};

use beskar_core::events::CompositorEvent;
use beskar_core::models::{OutputInfo, WindowInfo, WorkspaceInfo};
use beskar_core::traits::{CompositorBackend, CompositorKind};

#[derive(Default)]
pub struct NiriBackend;

impl NiriBackend {
    pub fn new() -> Self {
        Self
    }

    /// Connect to the niri IPC socket.
    fn connect() -> Result<UnixStream> {
        let socket_path = env::var_os("NIRI_SOCKET")
            .or_else(|| env::var_os("NIRI_SOCKET_PATH"))
            .ok_or_else(|| anyhow!("NIRI_SOCKET or NIRI_SOCKET_PATH environment variable not set"))?;

        UnixStream::connect(socket_path).context("Failed to connect to Niri socket")
    }

    /// Send a single action request to niri and read the reply.
    fn send_action(action: Action) -> Result<()> {
        let mut stream = Self::connect()?;
        let mut json = serde_json::to_string(&Request::Action(action))?;
        json.push('\n');
        stream.write_all(json.as_bytes())?;
        stream.flush()?;

        let mut reader = BufReader::new(stream);
        let mut response_line = String::new();
        reader.read_line(&mut response_line)?;

        let reply: Reply = serde_json::from_str(&response_line)?;
        reply.map_err(|e| anyhow!("Niri error: {}", e)).map(|_| ())
    }

    /// Request a standard query from niri
    fn query(request: Request) -> Result<niri_ipc::Response> {
        let mut stream = Self::connect()?;
        let mut json = serde_json::to_string(&request)?;
        json.push('\n');
        stream.write_all(json.as_bytes())?;
        stream.flush()?;

        let mut reader = BufReader::new(stream);
        let mut response_line = String::new();
        reader.read_line(&mut response_line)?;

        let reply: Reply = serde_json::from_str(&response_line)?;
        reply.map_err(|e| anyhow!("Niri error: {}", e))
    }
}

#[async_trait]
impl CompositorBackend for NiriBackend {
    fn kind(&self) -> CompositorKind {
        CompositorKind::Niri
    }

    fn is_available(&self) -> bool {
        env::var_os("NIRI_SOCKET")
            .or_else(|| env::var_os("NIRI_SOCKET_PATH"))
            .is_some()
    }

    async fn start_listener(&self, tx: mpsc::Sender<CompositorEvent>) -> Result<()> {
        info!("Spawning Niri event stream listener");

        thread::spawn(move || {
            let stream = match Self::connect() {
                Ok(s) => s,
                Err(err) => {
                    error!("Niri connect error: {}", err);
                    return;
                }
            };

            let request_json = match serde_json::to_string(&Request::EventStream) {
                Ok(j) => j + "\n",
                Err(e) => {
                    error!("Failed to serialize EventStream request: {}", e);
                    return;
                }
            };

            let mut stream = stream;
            if let Err(e) = stream.write_all(request_json.as_bytes()) {
                error!("Failed to write EventStream request: {}", e);
                return;
            }
            let _ = stream.flush();

            let mut reader = BufReader::new(stream);
            let mut line = String::new();
            if let Err(e) = reader.read_line(&mut line) {
                error!("Failed to read handshake: {}", e);
                return;
            }

            let reply: Reply = match serde_json::from_str(&line) {
                Ok(r) => r,
                Err(e) => {
                    error!("Handshake parse failed: {}", e);
                    return;
                }
            };

            if let Err(e) = reply {
                error!("Niri refused EventStream: {}", e);
                return;
            }

            let _ = reader.get_ref().shutdown(std::net::Shutdown::Write);
            let mut state = EventStreamState::default();

            loop {
                line.clear();
                match reader.read_line(&mut line) {
                    Ok(0) => break, // EOF
                    Ok(_) => {}
                    Err(e) => {
                        error!("Read error from Niri socket: {}", e);
                        break;
                    }
                }

                let event: Event = match serde_json::from_str(&line) {
                    Ok(ev) => ev,
                    Err(e) => {
                        debug!("Skipping unrecognized Niri event: {:?}", e);
                        continue;
                    }
                };

                state.apply(event);

                // Map workspaces
                let mut workspaces = Vec::new();
                for w in state.workspaces.workspaces.values() {
                    workspaces.push(WorkspaceInfo {
                        id: w.id,
                        idx: w.idx,
                        name: w.name.clone(),
                        output: w.output.clone().unwrap_or_default(),
                        is_active: w.is_active,
                        is_focused: w.is_focused,
                    });
                }
                workspaces.sort_by_key(|w| w.idx);

                // Map windows
                let mut windows = Vec::new();
                for win in state.windows.windows.values() {
                    windows.push(WindowInfo {
                        id: win.id,
                        title: win.title.clone(),
                        app_id: win.app_id.clone(),
                        workspace_id: win.workspace_id,
                        is_focused: win.is_focused,
                    });
                }

                let active_win = windows.iter().find(|w| w.is_focused).cloned();

                let _ = tx.blocking_send(CompositorEvent::WorkspacesChanged(workspaces));
                let _ = tx.blocking_send(CompositorEvent::WindowsChanged(windows));
                let _ = tx.blocking_send(CompositorEvent::WindowFocused(active_win));
            }

            info!("Niri event stream loop terminated");
        });

        Ok(())
    }

    async fn get_workspaces(&self) -> Result<Vec<WorkspaceInfo>> {
        let resp = Self::query(Request::Workspaces)?;
        let ws = match resp {
            niri_ipc::Response::Workspaces(w) => w,
            other => anyhow::bail!("Unexpected response from niri: {:?}", other),
        };
        let mut list: Vec<WorkspaceInfo> = ws
            .into_iter()
            .map(|w| WorkspaceInfo {
                id: w.id,
                idx: w.idx,
                name: w.name,
                output: w.output.unwrap_or_default(),
                is_active: w.is_active,
                is_focused: w.is_focused,
            })
            .collect();
        list.sort_by_key(|w| w.idx);
        Ok(list)
    }

    async fn get_windows(&self) -> Result<Vec<WindowInfo>> {
        let resp = Self::query(Request::Windows)?;
        let wins = match resp {
            niri_ipc::Response::Windows(w) => w,
            other => anyhow::bail!("Unexpected response from niri: {:?}", other),
        };
        Ok(wins
            .into_iter()
            .map(|win| WindowInfo {
                id: win.id,
                title: win.title,
                app_id: win.app_id,
                workspace_id: win.workspace_id,
                is_focused: win.is_focused,
            })
            .collect())
    }

    async fn get_outputs(&self) -> Result<Vec<OutputInfo>> {
        let resp = Self::query(Request::Outputs)?;
        let map = match resp {
            niri_ipc::Response::Outputs(m) => m,
            other => anyhow::bail!("Unexpected response from niri: {:?}", other),
        };
        Ok(map
            .into_iter()
            .map(|(name, out)| OutputInfo {
                name,
                make: Some(out.make),
                model: Some(out.model),
                width: out.modes.first().map(|m| m.width as u32).unwrap_or(1920),
                height: out.modes.first().map(|m| m.height as u32).unwrap_or(1080),
                scale: out.logical.map(|l| l.scale).unwrap_or(1.0),
            })
            .collect())
    }

    async fn focus_workspace(&self, id: u64) -> Result<()> {
        Self::send_action(Action::FocusWorkspace {
            reference: WorkspaceReferenceArg::Id(id),
        })
    }

    async fn focus_window(&self, id: u64) -> Result<()> {
        Self::send_action(Action::FocusWindow { id })
    }

    async fn close_window(&self, id: u64) -> Result<()> {
        Self::send_action(Action::CloseWindow { id: Some(id) })
    }

    async fn scroll_workspace(&self, dir: i32) -> Result<()> {
        if dir > 0 {
            Self::send_action(Action::FocusWorkspaceDown {})
        } else {
            Self::send_action(Action::FocusWorkspaceUp {})
        }
    }
}

