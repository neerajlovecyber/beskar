use anyhow::Result;
use beskar_core::events::ServiceEvent;
use beskar_core::models::AudioState;
use std::process::Command;
use tokio::sync::mpsc;
use tracing::info;

pub struct AudioService;

impl Default for AudioService {
    fn default() -> Self {
        Self::new()
    }
}

impl AudioService {
    pub fn new() -> Self {
        Self
    }

    /// Read volume and mute state via wpctl or pactl
    pub fn read_state() -> AudioState {
        // Try wpctl first (PipeWire standard)
        if let Ok(output) = Command::new("wpctl")
            .args(["get-volume", "@DEFAULT_AUDIO_SINK@"])
            .output()
        {
            if output.status.success() {
                let text = String::from_utf8_lossy(&output.stdout);
                // format: "Volume: 0.65" or "Volume: 0.65 [MUTED]"
                let is_muted = text.contains("[MUTED]");
                let parts: Vec<&str> = text.split_whitespace().collect();
                if parts.len() >= 2 {
                    if let Ok(vol) = parts[1].parse::<f32>() {
                        return AudioState {
                            volume: vol,
                            is_muted,
                            default_sink_name: None,
                        };
                    }
                }
            }
        }

        AudioState {
            volume: 1.0,
            is_muted: false,
            default_sink_name: None,
        }
    }

    pub fn set_volume(delta_percent: i32) {
        let arg = if delta_percent >= 0 {
            format!("{}%+", delta_percent)
        } else {
            format!("{}%-", -delta_percent)
        };
        let _ = Command::new("wpctl")
            .args(["set-volume", "@DEFAULT_AUDIO_SINK@", &arg])
            .spawn();
    }

    pub fn toggle_mute() {
        let _ = Command::new("wpctl")
            .args(["set-mute", "@DEFAULT_AUDIO_SINK@", "toggle"])
            .spawn();
    }

    pub async fn start_listener(&self, tx: mpsc::Sender<ServiceEvent>) -> Result<()> {
        info!("Audio monitoring listener starting");
        tokio::spawn(async move {
            let mut last_state = None;
            loop {
                let current = Self::read_state();
                if last_state.as_ref() != Some(&current) {
                    last_state = Some(current.clone());
                    let _ = tx.send(ServiceEvent::Audio(current)).await;
                }
                tokio::time::sleep(tokio::time::Duration::from_millis(1500)).await;
            }
        });
        Ok(())
    }
}
