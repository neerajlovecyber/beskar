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
pub mod hardware_bus;
pub mod tray;
pub mod updates;
pub mod vitals;
pub mod watcher;
pub mod wallpaper;
pub mod polkit;

pub use hardware_bus::{HardwareBus, HardwarePlatform, LinuxHardwareAdapter, MockHardwareAdapter, MockHardwareState};
pub use logind::listen_logind_lock;
pub use vitals::{VitalsService, VitalsSnapshot, CpuMetrics, MemoryMetrics, DiskMetrics, ThermalMetrics};
pub use watcher::{FileWatcherService, WatchEvent};
pub use wallpaper::WallpaperService;
pub use polkit::{PolkitService, PolkitAuthRequest, authenticate_user};

pub use audio::{AudioService, AudioSinkItem};
pub use auth::verify as verify_password;
pub use backlight::BacklightService;
pub use battery::BatteryService;
pub use beskar_core::models::BatteryState;
pub use cava::CavaService;
pub use clipboard::{ClipboardContent, ClipboardEntry, ClipboardItem, ClipboardService, Snippet};
pub use desktop::{launch as launch_app, list_apps};
pub use github::{ContributionDay, GithubProfile, GithubService, GithubState};
pub use hub::{SystemHub, SystemSnapshot};
pub use power_profiles::PowerProfilesService;
pub use mpris::{MediaTrack, MprisService};
pub use sound::SoundService;
pub use sysvalue::SysValue;
pub use tray::TrayService;
pub use notifications::{NotificationItem, NotificationStore};
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
        if networkmanager::available() {
            if let Ok(c) = zbus::blocking::Connection::system() {
                if let Some(nm) = zbus::blocking::Proxy::new(&c, "org.freedesktop.NetworkManager", "/org/freedesktop/NetworkManager", "org.freedesktop.NetworkManager").ok() {
                    let is_on = nm.get_property::<bool>("WirelessEnabled").unwrap_or(false);
                    let mut active_ssid = None;
                    if is_on {
                        if let Ok(primary) = nm.get_property::<zbus::zvariant::OwnedObjectPath>("PrimaryConnection") {
                            if primary.as_str() != "/" {
                                if let Ok(act) = zbus::blocking::Proxy::new(&c, "org.freedesktop.NetworkManager", primary.as_str(), "org.freedesktop.NetworkManager.Connection.Active") {
                                    let t = act.get_property::<String>("Type").unwrap_or_default();
                                    if t == "802-11-wireless" {
                                        active_ssid = act.get_property::<String>("Id").ok();
                                    }
                                }
                            }
                        }
                    }
                    return (is_on, active_ssid);
                }
            }
        }
        (true, None)
    }

    pub fn scan_networks() -> Vec<WifiAccessPoint> {
        let mut list = Vec::new();
        if networkmanager::available() {
            if let Ok(c) = zbus::blocking::Connection::system() {
                let dev_paths = networkmanager::wifi_devices(&c);
                for dev in dev_paths {
                    if let Ok(w) = zbus::blocking::Proxy::new(&c, "org.freedesktop.NetworkManager", dev.as_str(), "org.freedesktop.NetworkManager.Device.Wireless") {
                        let active: Option<zbus::zvariant::OwnedObjectPath> = w.get_property("ActiveAccessPoint").ok();
                        let points: Vec<zbus::zvariant::OwnedObjectPath> = w.call("GetAllAccessPoints", &()).unwrap_or_default();
                        for ap in points {
                            if let Ok(p) = zbus::blocking::Proxy::new(&c, "org.freedesktop.NetworkManager", ap.as_str(), "org.freedesktop.NetworkManager.AccessPoint") {
                                let ssid = p.get_property::<Vec<u8>>("Ssid").map(|b| String::from_utf8_lossy(&b).into_owned()).unwrap_or_default();
                                if ssid.is_empty() {
                                    continue;
                                }
                                let signal = p.get_property::<u8>("Strength").unwrap_or(50);
                                let flags = |k: &str| p.get_property::<u32>(k).unwrap_or(0);
                                let secure = flags("WpaFlags") != 0 || flags("RsnFlags") != 0 || flags("Flags") & 1 != 0;
                                let is_active = active.as_ref().is_some_and(|a| a == &ap);

                                if let Some(existing) = list.iter_mut().find(|x: &&mut WifiAccessPoint| x.ssid == ssid) {
                                    existing.signal = existing.signal.max(signal);
                                    existing.is_active |= is_active;
                                } else {
                                    list.push(WifiAccessPoint {
                                        ssid,
                                        signal,
                                        security: if secure { "WPA2/WPA3".to_string() } else { "Open".to_string() },
                                        is_active,
                                    });
                                }
                            }
                        }
                    }
                }
            }
        }
        list.sort_by(|a, b| b.is_active.cmp(&a.is_active).then_with(|| b.signal.cmp(&a.signal)));
        list
    }

    pub async fn scan_networks_async() -> Vec<WifiAccessPoint> {
        tokio::task::spawn_blocking(Self::scan_networks)
            .await
            .unwrap_or_default()
    }

    pub fn connect(ssid: &str, password: Option<&str>) {
        let args = if let Some(pw) = password {
            vec![SysValue::Text(ssid.to_string()), SysValue::Text(pw.to_string())]
        } else {
            vec![SysValue::Text(ssid.to_string())]
        };
        let _ = networkmanager::command("network.connect", &args);
    }

    pub fn toggle_wifi(current_on: bool) {
        let _ = networkmanager::command("network.wifi", &[SysValue::Bool(!current_on)]);
    }
}

/// Lightweight synchronous helper for BlueZ Bluetooth status and control.
pub struct BluetoothHelper;

impl BluetoothHelper {
    pub fn get_bluetooth_status() -> bool {
        if bluez::available() {
            if let Ok(c) = zbus::blocking::Connection::system() {
                let val = bluez::now(&c);
                if let SysValue::Map(m) = val {
                    return m.iter().find(|(k, _)| k == "powered").and_then(|(_, v)| match v {
                        SysValue::Bool(b) => Some(*b),
                        _ => None,
                    }).unwrap_or(false);
                }
            }
        }
        false
    }

    pub fn list_devices() -> Vec<BluetoothDeviceItem> {
        let mut list = Vec::new();
        if bluez::available() {
            if let Ok(c) = zbus::blocking::Connection::system() {
                let val = bluez::now(&c);
                if let SysValue::Map(m) = val {
                    if let Some((_, SysValue::List(devs))) = m.into_iter().find(|(k, _)| k == "devices") {
                        for d in devs {
                            if let SysValue::Map(fields) = d {
                                let get_str = |k: &str| fields.iter().find(|(f, _)| f == k).and_then(|(_, v)| match v {
                                    SysValue::Text(t) => Some(t.clone()),
                                    _ => None,
                                }).unwrap_or_default();
                                let get_bool = |k: &str| fields.iter().find(|(f, _)| f == k).and_then(|(_, v)| match v {
                                    SysValue::Bool(b) => Some(*b),
                                    _ => None,
                                }).unwrap_or(false);
                                let get_num = |k: &str| fields.iter().find(|(f, _)| f == k).and_then(|(_, v)| match v {
                                    SysValue::Num(n) => Some(*n),
                                    _ => None,
                                });

                                let address = get_str("address");
                                let name = get_str("name");
                                let is_connected = get_bool("connected");
                                let battery = get_num("battery").filter(|n| *n >= 0.0).map(|n| (n * 100.0).round() as u8);

                                list.push(BluetoothDeviceItem {
                                    address,
                                    name,
                                    is_connected,
                                    battery_percent: battery,
                                });
                            }
                        }
                    }
                }
            }
        }
        list.sort_by_key(|a| std::cmp::Reverse(a.is_connected));
        list
    }

    pub async fn list_devices_async() -> Vec<BluetoothDeviceItem> {
        tokio::task::spawn_blocking(Self::list_devices)
            .await
            .unwrap_or_default()
    }

    pub fn connect(address: &str) {
        let _ = bluez::command("bluetooth.connect", &[SysValue::Text(address.to_string())]);
    }

    pub fn disconnect(address: &str) {
        let _ = bluez::command("bluetooth.disconnect", &[SysValue::Text(address.to_string())]);
    }

    pub fn toggle_bluetooth(current_on: bool) {
        let _ = bluez::command("bluetooth.power", &[SysValue::Bool(!current_on)]);
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

/// Spawns an asynchronous task onto the background Tokio runtime.
pub fn spawn_tokio<F>(future: F) -> tokio::task::JoinHandle<F::Output>
where
    F: std::future::Future + Send + 'static,
    F::Output: Send + 'static,
{
    tokio_runtime().spawn(future)
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
