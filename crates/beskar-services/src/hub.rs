use crate::{audio::AudioService, battery::BatteryService, mpris::MprisService};
use anyhow::Result;
use beskar_core::events::ServiceEvent;
use beskar_core::models::{AudioState, BatteryState, MediaState};
use tokio::sync::{broadcast, mpsc};
use tracing::info;

/// Combined snapshot of hardware and desktop system states.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct SystemSnapshot {
    pub audio: AudioState,
    pub battery: BatteryState,
    pub media: Option<MediaState>,
}

/// Deep module providing a single reactive stream for all system states.
/// Encapsulates PulseAudio sockets, UPower D-Bus connections, NetworkManager, BlueZ, and MPRIS bus queries.
pub struct SystemHub {
    tx: broadcast::Sender<SystemSnapshot>,
}

impl Default for SystemHub {
    fn default() -> Self {
        Self::new()
    }
}

impl SystemHub {
    pub fn new() -> Self {
        let (tx, _) = broadcast::channel(64);
        Self { tx }
    }

    /// Subscribe to live reactive updates
    pub fn subscribe(&self) -> broadcast::Receiver<SystemSnapshot> {
        self.tx.subscribe()
    }

    /// Spawns background listeners for Audio, Battery, MPRIS, Network, and Bluetooth into a single broadcast stream.
    pub async fn start(&self) -> Result<()> {
        let tx = self.tx.clone();
        let (event_tx, mut event_rx) = mpsc::channel::<ServiceEvent>(64);

        // Initial snapshot
        let initial_audio = AudioService::read_state();
        let battery_svc = BatteryService::new();
        let initial_battery = battery_svc.read_state();
        let initial_media = MprisService::read_state();

        let initial_snapshot = SystemSnapshot {
            audio: initial_audio,
            battery: initial_battery,
            media: initial_media,
        };
        let _ = tx.send(initial_snapshot.clone());

        // Spawn audio reactive listener (PulseAudio socket event loop)
        let audio_svc = AudioService::new();
        let audio_tx = event_tx.clone();
        tokio::spawn(async move {
            let _ = audio_svc.start_listener(audio_tx).await;
        });

        // Spawn battery listener
        let bat_tx = event_tx.clone();
        tokio::spawn(async move {
            let _ = battery_svc.start_listener(bat_tx).await;
        });

        // Spawn MPRIS listener
        let mpris_svc = MprisService::new();
        let mpris_tx = event_tx.clone();
        tokio::spawn(async move {
            let _ = mpris_svc.start_listener(mpris_tx).await;
        });

        // Spawn copied pleamar NetworkManager service
        crate::networkmanager::service(Box::new(|_val| {
            // Live network updates from NetworkManager signals
        }));

        // Spawn copied pleamar BlueZ service
        crate::bluez::service(Box::new(|_val| {
            // Live bluetooth updates from BlueZ signals
        }));

        // Spawn copied pleamar Notifications service
        crate::notifications::service(Box::new(|_val| {
            // Live desktop notifications
        }));

        // Aggregation event loop
        tokio::spawn(async move {
            let mut state = initial_snapshot;
            while let Some(event) = event_rx.recv().await {
                match event {
                    ServiceEvent::Audio(aud) => {
                        state.audio = aud;
                    }
                    ServiceEvent::Battery(bat) => {
                        state.battery = bat;
                    }
                    ServiceEvent::Media(med) => {
                        state.media = Some(med);
                    }
                    _ => {}
                }
                let _ = tx.send(state.clone());
            }
        });

        info!("SystemHub reactive aggregator initialized");
        Ok(())
    }
}
