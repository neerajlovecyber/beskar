use anyhow::Result;
use tokio::sync::mpsc;
use tracing::info;
use beskar_core::events::ServiceEvent;
use beskar_core::models::MediaState;

pub struct MprisService;

impl MprisService {
    pub fn new() -> Self {
        Self
    }

    pub async fn start_listener(&self, _tx: mpsc::Sender<ServiceEvent>) -> Result<()> {
        info!("MPRIS D-Bus listener starting");
        Ok(())
    }

    pub async fn current_state(&self) -> Result<Option<MediaState>> {
        Ok(None)
    }
}
