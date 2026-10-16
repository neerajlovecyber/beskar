pub struct PowerProfilesService;

impl PowerProfilesService {
    pub fn get_profile() -> String {
        if let Ok(content) = std::fs::read_to_string("/sys/firmware/acpi/platform_profile") {
            let p = content.trim();
            if !p.is_empty() {
                return match p {
                    "low-power" => "power-saver".to_string(),
                    other => other.to_string(),
                };
            }
        }

        if let Ok(out) = std::process::Command::new("powerprofilesctl").arg("get").output() {
            String::from_utf8_lossy(&out.stdout).trim().to_string()
        } else {
            "balanced".to_string()
        }
    }

    pub fn set_profile(profile: &str) {
        let profile = profile.to_string();
        tokio::task::spawn_blocking(move || {
            let _ = std::process::Command::new("powerprofilesctl")
                .args(["set", &profile])
                .spawn();
        });
    }
}
