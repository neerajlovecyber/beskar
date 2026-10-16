pub struct PowerProfilesService;

impl PowerProfilesService {
    pub fn get_profile() -> String {
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
