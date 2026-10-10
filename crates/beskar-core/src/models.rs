use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct WorkspaceInfo {
    pub id: u64,
    pub idx: u8,
    pub name: Option<String>,
    pub output: String,
    pub is_active: bool,
    pub is_focused: bool,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct WindowInfo {
    pub id: u64,
    pub title: Option<String>,
    pub app_id: Option<String>,
    pub workspace_id: Option<u64>,
    pub is_focused: bool,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct OutputInfo {
    pub name: String,
    pub make: Option<String>,
    pub model: Option<String>,
    pub width: u32,
    pub height: u32,
    pub scale: f64,
}

#[derive(Debug, Clone, PartialEq, Default, Serialize, Deserialize)]
pub struct MediaState {
    pub player_name: String,
    pub title: Option<String>,
    pub artist: Option<String>,
    pub album: Option<String>,
    pub is_playing: bool,
    pub art_url: Option<String>,
    pub position_ms: u64,
    pub duration_ms: u64,
}

#[derive(Debug, Clone, PartialEq, Default, Serialize, Deserialize)]
pub struct BatteryState {
    pub percentage: f32,
    pub is_charging: bool,
    pub is_plugged_in: bool,
    pub power_watts: Option<f32>,
}

#[derive(Debug, Clone, PartialEq, Default, Serialize, Deserialize)]
pub struct AudioState {
    pub volume: f32, // 0.0 to 1.0 (or >1.0 for boost)
    pub is_muted: bool,
    pub default_sink_name: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Default, Serialize, Deserialize)]
pub struct NetworkState {
    pub is_connected: bool,
    pub ssid: Option<String>,
    pub signal_strength: u8, // 0 - 100
    pub is_ethernet: bool,
}

#[derive(Debug, Clone, PartialEq, Default, Serialize, Deserialize)]
pub struct BluetoothDevice {
    pub name: String,
    pub address: String,
    pub is_connected: bool,
    pub is_paired: bool,
    pub battery_percent: Option<u8>,
}

#[derive(Debug, Clone, PartialEq, Default, Serialize, Deserialize)]
pub struct BluetoothState {
    pub is_present: bool,
    pub is_powered: bool,
    pub connected_devices: Vec<BluetoothDevice>,
}

#[derive(Debug, Clone, PartialEq, Default, Serialize, Deserialize)]
pub struct TrayItem {
    pub key: String,
    pub id: String,
    pub title: String,
    pub icon: String,
    pub status: String,
    pub has_menu: bool,
}

#[derive(Debug, Clone, PartialEq, Default, Serialize, Deserialize)]
pub struct NotificationItem {
    pub id: u32,
    pub app_name: String,
    pub summary: String,
    pub body: String,
    pub icon: String,
    pub urgency: u8,
}

#[derive(Debug, Clone, PartialEq, Default, Serialize, Deserialize)]
pub struct AppItem {
    pub name: String,
    pub exec: String,
    pub icon: String,
    pub id: String,
    pub wmclass: String,
    pub local_name: String,
    pub categories: String,
}



