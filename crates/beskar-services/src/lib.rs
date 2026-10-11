pub mod audio;
pub mod auth;
pub mod battery;
pub mod bluez;
pub mod clipboard;
pub mod desktop;
pub mod files;
pub mod hub;
pub mod logind;
pub mod mpris;
pub mod mpris_pleamar;
pub mod networkmanager;
pub mod notifications;
pub mod sound;
pub mod sysvalue;
pub mod tray;

pub use logind::listen_logind_lock;

pub use audio::AudioService;
pub use auth::verify as verify_password;
pub use battery::BatteryService;
pub use clipboard::{ClipboardEntry, ClipboardService};
pub use desktop::{launch as launch_app, list_apps};
pub use hub::{SystemHub, SystemSnapshot};
pub use mpris::MprisService;
pub use sound::SoundService;
pub use sysvalue::SysValue;


/// Lightweight synchronous helper for NetworkManager Wi-Fi status and control.
pub struct NetworkHelper;

impl NetworkHelper {
    pub fn get_wifi_status() -> (bool, Option<String>) {
        if let Ok(output) = std::process::Command::new("nmcli").args(["radio", "wifi"]).output() {
            let is_on = String::from_utf8_lossy(&output.stdout).trim() == "enabled";
            let mut ssid = None;
            if is_on {
                if let Ok(out) = std::process::Command::new("nmcli")
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
            }
            (is_on, ssid)
        } else {
            (true, None)
        }
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
}
