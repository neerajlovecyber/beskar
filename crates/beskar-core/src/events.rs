use crate::models::{AudioState, BatteryState, BluetoothState, MediaState, NetworkState, WindowInfo, WorkspaceInfo};

#[derive(Debug, Clone)]
pub enum CompositorEvent {
    WorkspacesChanged(Vec<WorkspaceInfo>),
    WorkspaceFocused(u64),
    WindowsChanged(Vec<WindowInfo>),
    WindowFocused(Option<WindowInfo>),
    OutputsChanged,
}

#[derive(Debug, Clone)]
pub enum ServiceEvent {
    Media(MediaState),
    Battery(BatteryState),
    Audio(AudioState),
    Network(NetworkState),
    Bluetooth(BluetoothState),
    Tray(Vec<crate::models::TrayItem>),
    Notifications(Vec<crate::models::NotificationItem>),
    TrayChanged,
}

#[derive(Debug, Clone)]
pub enum ShellEvent {
    Compositor(CompositorEvent),
    Service(ServiceEvent),
}
