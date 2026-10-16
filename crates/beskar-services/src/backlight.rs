pub struct BacklightService;

impl BacklightService {
    pub fn get_brightness() -> u8 {
        if let Ok(out) = std::process::Command::new("brightnessctl").arg("-m").output() {
            let s = String::from_utf8_lossy(&out.stdout);
            for part in s.split(',') {
                if part.ends_with('%')
                    && let Ok(v) = part.trim_end_matches('%').parse::<u8>() {
                        return v;
                    }
            }
        }
        100
    }

    pub fn set_brightness(pct: u8) {
        let clamped = pct.clamp(1, 100);
        tokio::task::spawn_blocking(move || {
            let _ = std::process::Command::new("brightnessctl")
                .args(["set", &format!("{}%", clamped)])
                .spawn();
        });
    }
}
