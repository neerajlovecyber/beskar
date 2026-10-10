use anyhow::Result;
use tokio::sync::mpsc;
use tracing::info;
use beskar_core::events::ServiceEvent;
use beskar_core::models::BatteryState;

pub struct BatteryService;

impl BatteryService {
    pub fn new() -> Self {
        Self
    }

    pub async fn start_listener(&self, _tx: mpsc::Sender<ServiceEvent>) -> Result<()> {
        info!("Battery UPower listener starting");
        Ok(())
    }

    pub async fn current_state(&self) -> Result<Option<BatteryState>> {
        Ok(Some(BatteryState {
            percentage: 85.0,
            is_charging: false,
            is_plugged_in: true,
            power_watts: None,
        }))
    }
}
