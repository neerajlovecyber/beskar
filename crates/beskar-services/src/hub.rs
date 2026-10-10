use crate::{audio::AudioService, battery::BatteryService, mpris::MprisService};
use anyhow::Result;
use beskar_core::events::ServiceEvent;
use beskar_core::models::{AudioState, BatteryState, MediaState, TrayItem};
use tokio::sync::{broadcast, mpsc};
use tracing::info;

/// Combined snapshot of hardware and desktop system states.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct SystemSnapshot {
    pub audio: AudioState,
    pub battery: BatteryState,
    pub media: Option<MediaState>,
    pub tray: Vec<TrayItem>,
}

/// Deep module providing a single reactive stream for all system states.
/// Encapsulates PulseAudio sockets, UPower D-Bus connections, NetworkManager, BlueZ, System Tray, and MPRIS bus queries.
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

    /// Spawns background listeners for Audio, Battery, MPRIS, Tray, Network, and Bluetooth into a single broadcast stream.
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
            tray: Vec::new(),
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

        // Spawn copied pleamar Tray service
        let tray_tx = event_tx.clone();
        crate::tray::service(Box::new(move |val| {
            if let crate::sysvalue::SysValue::List(items) = val {
                let mut tray_items = Vec::new();
                for item in items {
                    if let crate::sysvalue::SysValue::Map(m) = item {
                        let find_str = |k: &str| {
                            m.iter()
                                .find(|(key, _)| key == k)
                                .and_then(|(_, v)| match v {
                                    crate::sysvalue::SysValue::Text(t) => Some(t.clone()),
                                    _ => None,
                                })
                                .unwrap_or_default()
                        };
                        let find_bool = |k: &str| {
                            m.iter()
                                .find(|(key, _)| key == k)
                                .and_then(|(_, v)| match v {
                                    crate::sysvalue::SysValue::Bool(b) => Some(*b),
                                    _ => None,
                                })
                                .unwrap_or(false)
                        };
                        tray_items.push(TrayItem {
                            key: find_str("key"),
                            id: find_str("id"),
                            title: find_str("title"),
                            icon: find_str("icon"),
                            status: find_str("status"),
                            has_menu: find_bool("menu"),
                        });
                    }
                }
                let _ = tray_tx.blocking_send(ServiceEvent::Tray(tray_items));
            }
        }));

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
                    ServiceEvent::Tray(tray) => {
                        state.tray = tray;
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
