use std::process::Command;
use std::sync::atomic::{AtomicU64, Ordering};
use std::time::{SystemTime, UNIX_EPOCH};
use tracing::debug;

static LAST_VOLUME_PLAY_MS: AtomicU64 = AtomicU64::new(0);

/// Non-blocking sound cue feedback service.
/// Plays standard Freedesktop / Canberra sound theme cues asynchronously without blocking any thread.
pub struct SoundService;

impl SoundService {
    fn now_ms() -> u64 {
        SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map(|d| d.as_millis() as u64)
            .unwrap_or(0)
    }

    fn play_id(sound_id: &'static str) {
        tokio::task::spawn_blocking(move || {
            // Attempt 1: canberra-gtk-play (fire and forget with spawn())
            if let Ok(mut child) = Command::new("canberra-gtk-play")
                .args(["-i", sound_id])
                .spawn()
            {
                let _ = child.wait();
                return;
            }

            // Attempt 2: pw-play with standard freedesktop path (fire and forget)
            let sound_path = format!("/usr/share/sounds/freedesktop/stereo/{}.oga", sound_id);
            if std::path::Path::new(&sound_path).exists() {
                if let Ok(mut child) = Command::new("pw-play").arg(&sound_path).spawn() {
                    let _ = child.wait();
                }
            } else {
                debug!("Sound cue {} not played (no player or file)", sound_id);
            }
        });
    }

    /// Sound cue when volume level is adjusted (debounced to max 1 per 120ms)
    pub fn play_volume_change() {
        let now = Self::now_ms();
        let prev = LAST_VOLUME_PLAY_MS.load(Ordering::Relaxed);
        if now.saturating_sub(prev) < 120 {
            return;
        }
        LAST_VOLUME_PLAY_MS.store(now, Ordering::Relaxed);
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
