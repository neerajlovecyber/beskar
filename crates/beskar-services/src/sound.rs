use std::process::Command;
use tracing::debug;

/// Non-blocking sound cue feedback service.
/// Plays standard Freedesktop / Canberra sound theme cues without blocking the UI thread.
pub struct SoundService;

impl SoundService {
    fn play_id(sound_id: &'static str) {
        std::thread::spawn(move || {
            // Attempt 1: canberra-gtk-play
            let res = Command::new("canberra-gtk-play")
                .args(["-i", sound_id])
                .output();

            if res.is_ok() {
                return;
            }

            // Attempt 2: pw-play with standard freedesktop path
            let sound_path = format!("/usr/share/sounds/freedesktop/stereo/{}.oga", sound_id);
            if std::path::Path::new(&sound_path).exists() {
                let _ = Command::new("pw-play")
                    .arg(&sound_path)
                    .output();
            } else {
                debug!("Sound cue {} not played (no player or file)", sound_id);
            }
        });
    }

    /// Sound cue when volume level is adjusted
    pub fn play_volume_change() {
        Self::play_id("audio-volume-change");
    }

    /// Sound cue when a notification toast arrives
    pub fn play_notification() {
        Self::play_id("message");
    }

    /// Sound cue when the session locks
    pub fn play_lock() {
        Self::play_id("system-lock-screen");
    }

    /// Sound cue when an alert or bell is triggered
    pub fn play_bell() {
        Self::play_id("bell");
    }
}
