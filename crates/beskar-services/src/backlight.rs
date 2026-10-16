pub struct BacklightService;

impl BacklightService {
    pub fn get_brightness() -> u8 {
        if let Ok(entries) = std::fs::read_dir("/sys/class/backlight") {
            for entry in entries.flatten() {
                let path = entry.path();
                let cur = std::fs::read_to_string(path.join("brightness"));
                let max = std::fs::read_to_string(path.join("max_brightness"));
                if let (Ok(cur_str), Ok(max_str)) = (cur, max) {
                    if let (Ok(c), Ok(m)) = (
                        cur_str.trim().parse::<f32>(),
                        max_str.trim().parse::<f32>(),
                    ) {
                        if m > 0.0 {
                            return ((c / m) * 100.0).round().clamp(1.0, 100.0) as u8;
                        }
                    }
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
