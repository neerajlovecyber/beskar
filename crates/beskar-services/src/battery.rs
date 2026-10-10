use std::fs;
use std::path::{Path, PathBuf};
use anyhow::Result;
use beskar_core::events::ServiceEvent;
use beskar_core::models::BatteryState;
use tokio::sync::mpsc;
use tracing::info;

const POWER_SUPPLIES: &str = "/sys/class/power_supply";

pub struct BatteryService {
    path: Option<PathBuf>,
}

impl Default for BatteryService {
    fn default() -> Self {
        Self::new()
    }
}

impl BatteryService {
    pub fn new() -> Self {
        Self {
            path: find_battery_path(),
        }
    }

    /// Read the real battery state directly from Linux sysfs
    pub fn read_state(&self) -> BatteryState {
        let Some(path) = &self.path else {
            // Desktop or virtual machine without a battery
            return BatteryState {
                percentage: 100.0,
                is_charging: false,
                is_plugged_in: true,
                power_watts: None,
            };
        };

        let capacity_str = read_file_trimmed(path, "capacity");
        let percentage = capacity_str.parse::<f32>().unwrap_or(100.0);

        let status = read_file_trimmed(path, "status");
        let is_charging = status == "Charging";
        let is_plugged_in = is_charging || status == "Full" || status == "Not charging";

        BatteryState {
            percentage,
            is_charging,
            is_plugged_in,
            power_watts: None,
        }
    }

    pub async fn current_state(&self) -> Result<Option<BatteryState>> {
        Ok(Some(self.read_state()))
    }

    pub async fn start_listener(&self, tx: mpsc::Sender<ServiceEvent>) -> Result<()> {
        info!("Battery polling listener starting");
        let path = self.path.clone();
        let mut last_state = None;
        loop {
            let current = if let Some(p) = &path {
                let capacity = read_file_trimmed(p, "capacity").parse::<f32>().unwrap_or(100.0);
                let status = read_file_trimmed(p, "status");
                let is_charging = status == "Charging";
                let is_plugged_in = is_charging || status == "Full" || status == "Not charging";
                BatteryState {
                    percentage: capacity,
                    is_charging,
                    is_plugged_in,
                    power_watts: None,
                }
            } else {
                BatteryState {
                    percentage: 100.0,
                    is_charging: false,
                    is_plugged_in: true,
                    power_watts: None,
                }
            };

            if last_state.as_ref() != Some(&current) {
                last_state = Some(current.clone());
                let _ = tx.send(ServiceEvent::Battery(current)).await;
            }

            tokio::time::sleep(tokio::time::Duration::from_secs(5)).await;
        }
    }
}

fn find_battery_path() -> Option<PathBuf> {
    let entries = fs::read_dir(POWER_SUPPLIES).ok()?;
    for entry in entries.flatten() {
        let path = entry.path();
        if read_file_trimmed(&path, "type") == "Battery" {
            return Some(path);
        }
    }
    None
}

fn read_file_trimmed(folder: &Path, name: &str) -> String {
    fs::read_to_string(folder.join(name))
        .map(|s| s.trim().to_string())
        .unwrap_or_default()
}
