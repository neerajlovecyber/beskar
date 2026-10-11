use serde::{Deserialize, Serialize};
use std::path::PathBuf;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Serialize, Deserialize)]
pub enum BarStyleConfig {
    #[serde(rename = "island")]
    #[default]
    Island,
    #[serde(rename = "convex")]
    Convex,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Serialize, Deserialize)]
pub enum ThemePresetConfig {
    #[serde(rename = "obsidian")]
    ObsidianGlass,
    #[serde(rename = "catppuccin")]
    CatppuccinMocha,
    #[serde(rename = "gruvbox")]
    GruvboxDark,
    #[serde(rename = "wallpaper")]
    #[default]
    WallpaperAuto,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ShellConfig {
    pub bar_style: BarStyleConfig,
    pub theme_preset: ThemePresetConfig,
    pub sound_feedback: bool,
    pub blur_enabled: bool,
    pub bar_height: f32,
    pub island_spacing: f32,
    pub multi_monitor: bool,
    pub show_workspaces: bool,
    pub show_media_in_center: bool,
}

impl Default for ShellConfig {
    fn default() -> Self {
        Self {
            bar_style: BarStyleConfig::Island,
            theme_preset: ThemePresetConfig::WallpaperAuto,
            sound_feedback: true,
            blur_enabled: true,
            bar_height: 38.0,
            island_spacing: 12.0,
            multi_monitor: true,
            show_workspaces: true,
            show_media_in_center: true,
        }
    }
}

impl ShellConfig {
    pub fn config_path() -> PathBuf {
        let base = std::env::var("XDG_CONFIG_HOME")
            .map(PathBuf::from)
            .unwrap_or_else(|_| {
                let home = std::env::var("HOME").unwrap_or_else(|_| ".".to_string());
                PathBuf::from(home).join(".config")
            });
        base.join("beskar").join("config.json")
    }

    pub fn load() -> Self {
        let path = Self::config_path();
        if let Some(config) = std::fs::read_to_string(&path)
            .ok()
            .and_then(|c| serde_json::from_str::<Self>(&c).ok())
        {
            tracing::info!("Loaded Beskar config from {}", path.display());
            return config;
        }
        let default_config = Self::default();
        let _ = default_config.save();
        default_config
    }

    pub fn save(&self) -> std::io::Result<()> {
        let path = Self::config_path();
        if let Some(parent) = path.parent() {
            let _ = std::fs::create_dir_all(parent);
        }
        let json = serde_json::to_string_pretty(self)
            .map_err(std::io::Error::other)?;
        std::fs::write(&path, json)?;
        tracing::info!("Saved Beskar config to {}", path.display());
        notify_config_changed(self.clone());
        Ok(())
    }
}

static CONFIG_CHANNEL: std::sync::OnceLock<tokio::sync::broadcast::Sender<ShellConfig>> =
    std::sync::OnceLock::new();

fn get_config_channel() -> &'static tokio::sync::broadcast::Sender<ShellConfig> {
    CONFIG_CHANNEL.get_or_init(|| {
        let (tx, _) = tokio::sync::broadcast::channel(16);
        tx
    })
}

pub fn subscribe_config() -> tokio::sync::broadcast::Receiver<ShellConfig> {
    get_config_channel().subscribe()
}

pub fn notify_config_changed(cfg: ShellConfig) {
    let tx = get_config_channel();
    let _ = tx.send(cfg);
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_shell_config_serialization() {
        let config = ShellConfig::default();
        let json = serde_json::to_string_pretty(&config).expect("Serialize default config");
        assert!(json.contains("\"bar_style\": \"island\""));
        assert!(json.contains("\"theme_preset\": \"wallpaper\""));

        let deserialized: ShellConfig = serde_json::from_str(&json).expect("Deserialize config");
        assert_eq!(deserialized, config);
    }
}

