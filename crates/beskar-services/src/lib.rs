pub mod audio;
pub mod auth;
pub mod backlight;
pub mod battery;
pub mod bluez;
pub mod cava;
pub mod clipboard;
pub mod desktop;
pub mod files;
pub mod github;
pub mod hub;
pub mod logind;
pub mod mpris;
pub mod mpris_pleamar;
pub mod networkmanager;
pub mod notifications;
pub mod power_profiles;
pub mod sound;
pub mod sysvalue;
pub mod tray;
pub mod updates;

pub use logind::listen_logind_lock;

pub use audio::AudioService;
pub use auth::verify as verify_password;
pub use backlight::BacklightService;
pub use battery::BatteryService;
pub use cava::CavaService;
pub use clipboard::{ClipboardEntry, ClipboardService};
pub use desktop::{launch as launch_app, list_apps};
pub use github::{ContributionDay, GithubProfile, GithubService, GithubState};
pub use hub::{SystemHub, SystemSnapshot};
pub use power_profiles::PowerProfilesService;
pub use mpris::MprisService;
pub use sound::SoundService;
pub use sysvalue::SysValue;
pub use updates::{SystemUpdatesState, UpdateService};


#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct WifiAccessPoint {
    pub ssid: String,
    pub signal: u8,
    pub security: String,
    pub is_active: bool,
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct BluetoothDeviceItem {
    pub address: String,
    pub name: String,
    pub is_connected: bool,
    pub battery_percent: Option<u8>,
}

/// Lightweight synchronous helper for NetworkManager Wi-Fi status and control.
pub struct NetworkHelper;

impl NetworkHelper {
    pub fn get_wifi_status() -> (bool, Option<String>) {
        if let Ok(output) = std::process::Command::new("nmcli").args(["radio", "wifi"]).output() {
            let is_on = String::from_utf8_lossy(&output.stdout).trim() == "enabled";
            let mut ssid = None;
            if is_on
                && let Ok(out) = std::process::Command::new("nmcli")
                    .args(["-t", "-f", "active,ssid", "dev", "wifi"])
                    .output()
                {
                    let text = String::from_utf8_lossy(&out.stdout);
                    for line in text.lines() {
                        if line.starts_with("yes:") {
                            let name = line.trim_start_matches("yes:").trim().to_string();
                            if !name.is_empty() {
                                ssid = Some(name);
                                break;
                            }
                        }
                    }
                }
            (is_on, ssid)
        } else {
            (true, None)
        }
    }

    pub fn scan_networks() -> Vec<WifiAccessPoint> {
        let mut list = Vec::new();
        if let Ok(out) = std::process::Command::new("nmcli")
            .args(["-t", "-f", "SSID,SIGNAL,SECURITY,IN-USE", "dev", "wifi"])
            .output()
        {
            let text = String::from_utf8_lossy(&out.stdout);
            for line in text.lines() {
                let parts: Vec<&str> = line.split(':').collect();
                if parts.len() >= 4 {
                    let ssid = parts[0].trim().to_string();
                    if !ssid.is_empty() && !list.iter().any(|w: &WifiAccessPoint| w.ssid == ssid) {
                        let signal = parts[1].trim().parse::<u8>().unwrap_or(50);
                        let security = parts[2].trim().to_string();
                        let is_active = parts[3].trim() == "*";
                        list.push(WifiAccessPoint {
                            ssid,
                            signal,
                            security,
                            is_active,
                        });
                    }
                }
            }
        }
        list.sort_by(|a, b| b.is_active.cmp(&a.is_active).then_with(|| b.signal.cmp(&a.signal)));
        list
    }

    pub fn connect(ssid: &str, password: Option<&str>) {
        let mut cmd = std::process::Command::new("nmcli");
        cmd.args(["dev", "wifi", "connect", ssid]);
        if let Some(pw) = password
            && !pw.is_empty() {
                cmd.args(["password", pw]);
            }
        let _ = cmd.spawn();
    }

    pub fn toggle_wifi(current_on: bool) {
        let arg = if current_on { "off" } else { "on" };
        let _ = std::process::Command::new("nmcli").args(["radio", "wifi", arg]).spawn();
    }
}

/// Lightweight synchronous helper for BlueZ Bluetooth status and control.
pub struct BluetoothHelper;

impl BluetoothHelper {
    pub fn get_bluetooth_status() -> bool {
        if let Ok(output) = std::process::Command::new("bluetoothctl").args(["show"]).output() {
            let text = String::from_utf8_lossy(&output.stdout);
            text.contains("Powered: yes")
        } else {
            false
        }
    }

    pub fn list_devices() -> Vec<BluetoothDeviceItem> {
        let mut list = Vec::new();
        if let Ok(out) = std::process::Command::new("bluetoothctl").arg("devices").output() {
            let text = String::from_utf8_lossy(&out.stdout);
            for line in text.lines() {
                let parts: Vec<&str> = line.split_whitespace().collect();
                if parts.len() >= 3 && parts[0] == "Device" {
                    let addr = parts[1].to_string();
                    let name = parts[2..].join(" ");
                    let mut is_connected = false;
                    let mut battery = None;

                    if let Ok(info) = std::process::Command::new("bluetoothctl").args(["info", &addr]).output() {
                        let info_str = String::from_utf8_lossy(&info.stdout);
                        if info_str.contains("Connected: yes") {
                            is_connected = true;
                        }
                        for l in info_str.lines() {
                            if l.contains("Battery Percentage:")
                                && let Some(pct_str) = l.split('(').nth(1)
                                    && let Some(num) = pct_str.split('%').next()
                                        && let Ok(v) = num.trim().parse::<u8>() {
                                            battery = Some(v);
                                        }
                        }
                    }

                    list.push(BluetoothDeviceItem {
                        address: addr,
                        name,
                        is_connected,
                        battery_percent: battery,
                    });
                }
            }
        }
        list.sort_by_key(|a| std::cmp::Reverse(a.is_connected));
        list
    }

    pub fn connect(address: &str) {
        let _ = std::process::Command::new("bluetoothctl").args(["connect", address]).spawn();
    }

    pub fn disconnect(address: &str) {
        let _ = std::process::Command::new("bluetoothctl").args(["disconnect", address]).spawn();
    }

    pub fn toggle_bluetooth(current_on: bool) {
        let arg = if current_on { "off" } else { "on" };
        let _ = std::process::Command::new("bluetoothctl").args(["power", arg]).spawn();
    }
}

use std::sync::OnceLock;

static TOKIO_RUNTIME: OnceLock<tokio::runtime::Runtime> = OnceLock::new();

/// Returns a reference to the shared multi-thread Tokio runtime for background services.
pub fn tokio_runtime() -> &'static tokio::runtime::Runtime {
    TOKIO_RUNTIME.get_or_init(|| {
        tokio::runtime::Builder::new_multi_thread()
            .enable_all()
            .thread_name("beskar-worker")
            .build()
            .expect("Failed to initialize background Tokio runtime")
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_list_apps_discovery() {
        let apps = list_apps();
        assert!(!apps.is_empty(), "Should discover installed desktop applications");
        let first = &apps[0];
        assert!(!first.name.is_empty(), "App should have a name");
        for app in apps.iter().take(5) {
            println!("APP: {} | ICON: {} (exists: {})", app.name, app.icon, std::path::Path::new(&app.icon).exists());
        }
    }

    #[test]
    fn test_github_state_contributions() {
        let state = GithubService::get_or_load("local_dev");
        assert_eq!(state.contributions.len(), 52 * 7, "Should generate exactly 364 cells for 52-week heatmap grid");
        assert!(!state.profile.top_repo_name.is_empty());
    }

    #[test]
    fn test_update_service_cached() {
        let state = UpdateService::cached();
        assert!(!state.is_checking);
    }

    #[test]
    fn test_power_profiles() {
        let profile = PowerProfilesService::get_profile();
        assert!(["power-saver", "balanced", "performance"].contains(&profile.as_str()));
    }
}
