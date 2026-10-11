use anyhow::Result;
use beskar_core::events::ServiceEvent;
use beskar_core::models::MediaState;
use std::process::Command;
use tokio::sync::mpsc;
use tracing::info;

pub struct MprisService;

impl Default for MprisService {
    fn default() -> Self {
        Self::new()
    }
}

impl MprisService {
    pub fn new() -> Self {
        Self
    }

    /// Read active media player metadata and playback status
    pub fn read_state() -> Option<MediaState> {
        let output = Command::new("playerctl")
            .args(["metadata", "--format", "{{status}}:::{{artist}}:::{{title}}:::{{playerName}}"])
            .output()
            .ok()?;

        if !output.status.success() {
            return None;
        }

        let line = String::from_utf8_lossy(&output.stdout);
        let trimmed = line.trim();
        if trimmed.is_empty() {
            return None;
        }

        let parts: Vec<&str> = trimmed.split(":::").collect();
        if parts.len() < 3 {
            return None;
        }

        let status = parts[0].trim();
        let artist = parts[1].trim();
        let title = parts[2].trim();
        let player = if parts.len() > 3 { parts[3].trim() } else { "Media" };

        if title.is_empty() {
            return None;
        }

        Some(MediaState {
            player_name: player.to_string(),
            title: Some(title.to_string()),
            artist: if artist.is_empty() { None } else { Some(artist.to_string()) },
            album: None,
            is_playing: status.eq_ignore_ascii_case("Playing"),
            art_url: None,
            position_ms: 0,
            duration_ms: 0,
        })
    }

    pub fn play_pause() {
        let _ = Command::new("playerctl").arg("play-pause").spawn();
    }

    pub fn next() {
        let _ = Command::new("playerctl").arg("next").spawn();
    }

    pub fn previous() {
        let _ = Command::new("playerctl").arg("previous").spawn();
    }

    pub async fn start_listener(&self, tx: mpsc::Sender<ServiceEvent>) -> Result<()> {
        info!("MPRIS media monitoring listener starting");
        let mut last_state = None;
        loop {
            let current = Self::read_state();
            if last_state != current {
                last_state = current.clone();
                if let Some(media) = current {
                    let _ = tx.send(ServiceEvent::Media(media)).await;
                } else {
                    let _ = tx.send(ServiceEvent::Media(MediaState::default())).await;
                }
            }
            tokio::time::sleep(tokio::time::Duration::from_millis(1000)).await;
        }
    }
}
