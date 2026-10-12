//! Asynchronous HardwareBus Seam for Beskar Shell
//!
//! Encapsulates all underlying platform hardware interactions (Wi-Fi, Bluetooth,
//! Audio, Display Brightness, and Power Profiles) behind a non-blocking asynchronous
//! interface. Provides:
//! - `HardwarePlatform` trait
//! - `LinuxHardwareAdapter` executing via `tokio::task::spawn_blocking` and `zbus`
//! - `MockHardwareAdapter` for deterministic in-memory unit tests in CI/offline environments
//! - `HardwareBus` facade

use std::sync::Arc;
use async_trait::async_trait;
use tokio::sync::RwLock;

use crate::{
    AudioService, BacklightService, BluetoothDeviceItem, BluetoothHelper, NetworkHelper,
    PowerProfilesService, WifiAccessPoint,
};

/// Abstraction for all hardware platform subsystems.
#[async_trait]
pub trait HardwarePlatform: Send + Sync {
    // ── Wi-Fi ──
    async fn get_wifi_state(&self) -> (bool, Option<String>);
    async fn scan_wifi_networks(&self) -> Vec<WifiAccessPoint>;
    async fn set_wifi_power(&self, enabled: bool) -> anyhow::Result<()>;
    async fn connect_wifi(&self, ssid: &str, password: Option<&str>) -> anyhow::Result<()>;

    // ── Bluetooth ──
    async fn get_bluetooth_state(&self) -> bool;
    async fn list_bluetooth_devices(&self) -> Vec<BluetoothDeviceItem>;
    async fn set_bluetooth_power(&self, enabled: bool) -> anyhow::Result<()>;
    async fn connect_bluetooth(&self, address: &str) -> anyhow::Result<()>;

    // ── Audio ──
    async fn get_audio_volume(&self) -> (u8, bool);
    async fn set_audio_volume(&self, delta: i32) -> anyhow::Result<()>;
    async fn set_audio_volume_percent(&self, percent: u8) -> anyhow::Result<()>;
    async fn toggle_audio_mute(&self) -> anyhow::Result<()>;

    // ── Display Brightness ──
    async fn get_brightness(&self) -> u8;
    async fn set_brightness(&self, percent: u8) -> anyhow::Result<()>;

    // ── Power Profiles ──
    async fn get_power_profile(&self) -> String;
    async fn set_power_profile(&self, profile: &str) -> anyhow::Result<()>;
}

// ─────────────────────────────────────────────────────────────────────────────
// Production Linux Hardware Adapter
// ─────────────────────────────────────────────────────────────────────────────

#[derive(Default)]
pub struct LinuxHardwareAdapter;

impl LinuxHardwareAdapter {
    pub fn new() -> Self {
        Self
    }
}

#[async_trait]
impl HardwarePlatform for LinuxHardwareAdapter {
    async fn get_wifi_state(&self) -> (bool, Option<String>) {
        tokio::task::spawn_blocking(NetworkHelper::get_wifi_status)
            .await
            .unwrap_or((false, None))
    }

    async fn scan_wifi_networks(&self) -> Vec<WifiAccessPoint> {
        NetworkHelper::scan_networks_async().await
    }

    async fn set_wifi_power(&self, enabled: bool) -> anyhow::Result<()> {
        tokio::task::spawn_blocking(move || {
            NetworkHelper::toggle_wifi(!enabled);
        })
        .await?;
        Ok(())
    }

    async fn connect_wifi(&self, ssid: &str, password: Option<&str>) -> anyhow::Result<()> {
        let ssid = ssid.to_string();
        let pw = password.map(|s| s.to_string());
        tokio::task::spawn_blocking(move || {
            NetworkHelper::connect(&ssid, pw.as_deref());
        })
        .await?;
        Ok(())
    }

    async fn get_bluetooth_state(&self) -> bool {
        tokio::task::spawn_blocking(BluetoothHelper::get_bluetooth_status)
            .await
            .unwrap_or(false)
    }

    async fn list_bluetooth_devices(&self) -> Vec<BluetoothDeviceItem> {
        BluetoothHelper::list_devices_async().await
    }

    async fn set_bluetooth_power(&self, enabled: bool) -> anyhow::Result<()> {
        tokio::task::spawn_blocking(move || {
            BluetoothHelper::toggle_bluetooth(!enabled);
        })
        .await?;
        Ok(())
    }

    async fn connect_bluetooth(&self, address: &str) -> anyhow::Result<()> {
        let addr = address.to_string();
        tokio::task::spawn_blocking(move || {
            BluetoothHelper::connect(&addr);
        })
        .await?;
        Ok(())
    }

    async fn get_audio_volume(&self) -> (u8, bool) {
        let state = AudioService::read_state();
        ((state.volume * 100.0).round() as u8, state.is_muted)
    }

    async fn set_audio_volume(&self, delta: i32) -> anyhow::Result<()> {
        tokio::task::spawn_blocking(move || {
            AudioService::set_volume(delta);
        })
        .await?;
        Ok(())
    }

    async fn set_audio_volume_percent(&self, percent: u8) -> anyhow::Result<()> {
        tokio::task::spawn_blocking(move || {
            AudioService::set_volume_percent(percent);
        })
        .await?;
        Ok(())
    }

    async fn toggle_audio_mute(&self) -> anyhow::Result<()> {
        tokio::task::spawn_blocking(AudioService::toggle_mute).await?;
        Ok(())
    }

    async fn get_brightness(&self) -> u8 {
        tokio::task::spawn_blocking(BacklightService::get_brightness)
            .await
            .unwrap_or(80)
    }

    async fn set_brightness(&self, percent: u8) -> anyhow::Result<()> {
        tokio::task::spawn_blocking(move || {
            BacklightService::set_brightness(percent);
        })
        .await?;
        Ok(())
    }

    async fn get_power_profile(&self) -> String {
        tokio::task::spawn_blocking(PowerProfilesService::get_profile)
            .await
            .unwrap_or_else(|_| "balanced".to_string())
    }

    async fn set_power_profile(&self, profile: &str) -> anyhow::Result<()> {
        let prof = profile.to_string();
        tokio::task::spawn_blocking(move || {
            PowerProfilesService::set_profile(&prof);
        })
        .await?;
        Ok(())
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Deterministic In-Memory Mock Hardware Adapter
// ─────────────────────────────────────────────────────────────────────────────

#[derive(Debug, Clone)]
pub struct MockHardwareState {
    pub wifi_enabled: bool,
    pub wifi_ssid: Option<String>,
    pub wifi_networks: Vec<WifiAccessPoint>,
    pub bluetooth_enabled: bool,
    pub bluetooth_devices: Vec<BluetoothDeviceItem>,
    pub audio_volume: u8,
    pub audio_muted: bool,
    pub brightness: u8,
    pub power_profile: String,
}

impl Default for MockHardwareState {
    fn default() -> Self {
        Self {
            wifi_enabled: true,
            wifi_ssid: Some("MockNet-5G".to_string()),
            wifi_networks: vec![
                WifiAccessPoint {
                    ssid: "MockNet-5G".to_string(),
                    signal: 95,
                    security: "WPA2".to_string(),
                    is_active: true,
                },
                WifiAccessPoint {
                    ssid: "Guest-WiFi".to_string(),
                    signal: 70,
                    security: "WPA3".to_string(),
                    is_active: false,
                },
            ],
            bluetooth_enabled: true,
            bluetooth_devices: vec![
                BluetoothDeviceItem {
                    address: "AA:BB:CC:DD:EE:01".to_string(),
                    name: "Headphones Pro".to_string(),
                    is_connected: true,
                    battery_percent: Some(88),
                },
                BluetoothDeviceItem {
                    address: "AA:BB:CC:DD:EE:02".to_string(),
                    name: "Wireless Mouse".to_string(),
                    is_connected: false,
                    battery_percent: None,
                },
            ],
            audio_volume: 50,
            audio_muted: false,
            brightness: 75,
            power_profile: "balanced".to_string(),
        }
    }
}

pub struct MockHardwareAdapter {
    state: RwLock<MockHardwareState>,
}

impl MockHardwareAdapter {
    pub fn new() -> Self {
        Self {
            state: RwLock::new(MockHardwareState::default()),
        }
    }

    pub fn with_state(state: MockHardwareState) -> Self {
        Self {
            state: RwLock::new(state),
        }
    }

    pub async fn snapshot(&self) -> MockHardwareState {
        self.state.read().await.clone()
    }
}

impl Default for MockHardwareAdapter {
    fn default() -> Self {
        Self::new()
    }
}

#[async_trait]
impl HardwarePlatform for MockHardwareAdapter {
    async fn get_wifi_state(&self) -> (bool, Option<String>) {
        let s = self.state.read().await;
        (s.wifi_enabled, s.wifi_ssid.clone())
    }

    async fn scan_wifi_networks(&self) -> Vec<WifiAccessPoint> {
        let s = self.state.read().await;
        s.wifi_networks.clone()
    }

    async fn set_wifi_power(&self, enabled: bool) -> anyhow::Result<()> {
        let mut s = self.state.write().await;
        s.wifi_enabled = enabled;
        if !enabled {
            s.wifi_ssid = None;
        }
        Ok(())
    }

    async fn connect_wifi(&self, ssid: &str, _password: Option<&str>) -> anyhow::Result<()> {
        let mut s = self.state.write().await;
        s.wifi_enabled = true;
        s.wifi_ssid = Some(ssid.to_string());
        for net in &mut s.wifi_networks {
            net.is_active = net.ssid == ssid;
        }
        Ok(())
    }

    async fn get_bluetooth_state(&self) -> bool {
        let s = self.state.read().await;
        s.bluetooth_enabled
    }

    async fn list_bluetooth_devices(&self) -> Vec<BluetoothDeviceItem> {
        let s = self.state.read().await;
        s.bluetooth_devices.clone()
    }

    async fn set_bluetooth_power(&self, enabled: bool) -> anyhow::Result<()> {
        let mut s = self.state.write().await;
        s.bluetooth_enabled = enabled;
        Ok(())
    }

    async fn connect_bluetooth(&self, address: &str) -> anyhow::Result<()> {
        let mut s = self.state.write().await;
        for dev in &mut s.bluetooth_devices {
            if dev.address == address {
                dev.is_connected = true;
            }
        }
        Ok(())
    }

    async fn get_audio_volume(&self) -> (u8, bool) {
        let s = self.state.read().await;
        (s.audio_volume, s.audio_muted)
    }

    async fn set_audio_volume(&self, delta: i32) -> anyhow::Result<()> {
        let mut s = self.state.write().await;
        s.audio_volume = (s.audio_volume as i32 + delta).clamp(0, 100) as u8;
        s.audio_muted = false;
        Ok(())
    }

    async fn set_audio_volume_percent(&self, percent: u8) -> anyhow::Result<()> {
        let mut s = self.state.write().await;
        s.audio_volume = percent.clamp(0, 100);
        s.audio_muted = false;
        Ok(())
    }

    async fn toggle_audio_mute(&self) -> anyhow::Result<()> {
        let mut s = self.state.write().await;
        s.audio_muted = !s.audio_muted;
        Ok(())
    }

    async fn get_brightness(&self) -> u8 {
        let s = self.state.read().await;
        s.brightness
    }

    async fn set_brightness(&self, percent: u8) -> anyhow::Result<()> {
        let mut s = self.state.write().await;
        s.brightness = percent.clamp(5, 100);
        Ok(())
    }

    async fn get_power_profile(&self) -> String {
        let s = self.state.read().await;
        s.power_profile.clone()
    }

    async fn set_power_profile(&self, profile: &str) -> anyhow::Result<()> {
        let mut s = self.state.write().await;
        s.power_profile = profile.to_string();
        Ok(())
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// HardwareBus Unified Facade
// ─────────────────────────────────────────────────────────────────────────────

#[derive(Clone)]
pub struct HardwareBus {
    platform: Arc<dyn HardwarePlatform>,
}

impl HardwareBus {
    pub fn new(platform: Arc<dyn HardwarePlatform>) -> Self {
        Self { platform }
    }

    pub fn new_linux() -> Self {
        Self::new(Arc::new(LinuxHardwareAdapter::new()))
    }

    pub fn new_mock() -> Self {
        Self::new(Arc::new(MockHardwareAdapter::new()))
    }

    pub fn new_mock_with_state(state: MockHardwareState) -> Self {
        Self::new(Arc::new(MockHardwareAdapter::with_state(state)))
    }

    pub fn platform(&self) -> &Arc<dyn HardwarePlatform> {
        &self.platform
    }

    pub async fn get_wifi_state(&self) -> (bool, Option<String>) {
        self.platform.get_wifi_state().await
    }

    pub async fn scan_wifi_networks(&self) -> Vec<WifiAccessPoint> {
        self.platform.scan_wifi_networks().await
    }

    pub async fn set_wifi_power(&self, enabled: bool) -> anyhow::Result<()> {
        self.platform.set_wifi_power(enabled).await
    }

    pub async fn connect_wifi(&self, ssid: &str, password: Option<&str>) -> anyhow::Result<()> {
        self.platform.connect_wifi(ssid, password).await
    }

    pub async fn get_bluetooth_state(&self) -> bool {
        self.platform.get_bluetooth_state().await
    }

    pub async fn list_bluetooth_devices(&self) -> Vec<BluetoothDeviceItem> {
        self.platform.list_bluetooth_devices().await
    }

    pub async fn set_bluetooth_power(&self, enabled: bool) -> anyhow::Result<()> {
        self.platform.set_bluetooth_power(enabled).await
    }

    pub async fn connect_bluetooth(&self, address: &str) -> anyhow::Result<()> {
        self.platform.connect_bluetooth(address).await
    }

    pub async fn get_audio_volume(&self) -> (u8, bool) {
        self.platform.get_audio_volume().await
    }

    pub async fn set_audio_volume(&self, delta: i32) -> anyhow::Result<()> {
        self.platform.set_audio_volume(delta).await
    }

    pub async fn set_audio_volume_percent(&self, percent: u8) -> anyhow::Result<()> {
        self.platform.set_audio_volume_percent(percent).await
    }

    pub async fn toggle_audio_mute(&self) -> anyhow::Result<()> {
        self.platform.toggle_audio_mute().await
    }

    pub async fn get_brightness(&self) -> u8 {
        self.platform.get_brightness().await
    }

    pub async fn set_brightness(&self, percent: u8) -> anyhow::Result<()> {
        self.platform.set_brightness(percent).await
    }

    pub async fn get_power_profile(&self) -> String {
        self.platform.get_power_profile().await
    }

    pub async fn set_power_profile(&self, profile: &str) -> anyhow::Result<()> {
        self.platform.set_power_profile(profile).await
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_mock_hardware_bus_wifi_lifecycle() {
        let bus = HardwareBus::new_mock();
        let (enabled, ssid) = bus.get_wifi_state().await;
        assert!(enabled);
        assert_eq!(ssid, Some("MockNet-5G".to_string()));

        bus.set_wifi_power(false).await.unwrap();
        let (enabled, ssid) = bus.get_wifi_state().await;
        assert!(!enabled);
        assert_eq!(ssid, None);

        bus.connect_wifi("Guest-WiFi", None).await.unwrap();
        let (enabled, ssid) = bus.get_wifi_state().await;
        assert!(enabled);
        assert_eq!(ssid, Some("Guest-WiFi".to_string()));
    }

    #[tokio::test]
    async fn test_mock_hardware_bus_audio_controls() {
        let bus = HardwareBus::new_mock();
        let (vol, muted) = bus.get_audio_volume().await;
        assert_eq!(vol, 50);
        assert!(!muted);

        bus.set_audio_volume(15).await.unwrap();
        let (vol, _) = bus.get_audio_volume().await;
        assert_eq!(vol, 65);

        bus.toggle_audio_mute().await.unwrap();
        let (_, muted) = bus.get_audio_volume().await;
        assert!(muted);
    }

    #[tokio::test]
    async fn test_mock_hardware_bus_brightness_and_power() {
        let bus = HardwareBus::new_mock();
        assert_eq!(bus.get_brightness().await, 75);

        bus.set_brightness(90).await.unwrap();
        assert_eq!(bus.get_brightness().await, 90);

        assert_eq!(bus.get_power_profile().await, "balanced");
        bus.set_power_profile("performance").await.unwrap();
        assert_eq!(bus.get_power_profile().await, "performance");
    }

    #[tokio::test]
    async fn test_mock_hardware_bus_bluetooth_connect() {
        let bus = HardwareBus::new_mock();
        assert!(bus.get_bluetooth_state().await);

        let devices = bus.list_bluetooth_devices().await;
        assert_eq!(devices.len(), 2);
        assert!(!devices[1].is_connected);

        bus.connect_bluetooth("AA:BB:CC:DD:EE:02").await.unwrap();
        let devices = bus.list_bluetooth_devices().await;
        assert!(devices[1].is_connected);
    }
}
