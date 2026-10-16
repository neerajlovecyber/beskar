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

#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Serialize, Deserialize)]
pub enum BarPosition {
    #[serde(rename = "top")]
    #[default]
    Top,
    #[serde(rename = "bottom")]
    Bottom,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum BarModule {
    #[serde(rename = "brand_star")]
    BrandStar,
    #[serde(rename = "workspaces")]
    Workspaces,
    #[serde(rename = "active_window")]
    ActiveWindow,
    #[serde(rename = "clock")]
    Clock,
    #[serde(rename = "media")]
    Media,
    #[serde(rename = "cava")]
    Cava,
    #[serde(rename = "tray")]
    Tray,
    #[serde(rename = "quick_controls")]
    QuickControls,
    #[serde(rename = "vitals")]
    Vitals,
    #[serde(rename = "power")]
    Power,
}

fn default_true() -> bool {
    true
}

fn default_bar_height() -> f32 {
    38.0
}

fn default_island_spacing() -> f32 {
    12.0
}

fn default_animation_duration_ms() -> u32 {
    250
}
fn default_gap() -> f32 {
    8.0
}
fn default_capsule_round() -> f32 {
    16.0
}
fn default_satellite_round() -> f32 {
    16.0
}
fn default_cards_round() -> f32 {
    16.0
}
fn default_margin_top() -> f32 {
    8.0
}
fn default_exclusive_zone() -> f32 {
    33.0
}
fn default_idle_height() -> f32 {
    40.0
}

fn default_modules_left() -> Vec<BarModule> {
    vec![
        BarModule::BrandStar,
        BarModule::Workspaces,
        BarModule::ActiveWindow,
    ]
}

fn default_modules_center() -> Vec<BarModule> {
    vec![BarModule::Clock, BarModule::Media]
}

fn default_modules_right() -> Vec<BarModule> {
    vec![
        BarModule::Tray,
        BarModule::QuickControls,
        BarModule::Vitals,
        BarModule::Power,
    ]
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ShellConfig {
    #[serde(default)]
    pub bar_style: BarStyleConfig,
    #[serde(default)]
    pub bar_position: BarPosition,
    #[serde(default)]
    pub theme_preset: ThemePresetConfig,
    #[serde(default = "default_true")]
    pub sound_feedback: bool,
    #[serde(default = "default_true")]
    pub blur_enabled: bool,
    #[serde(default = "default_bar_height")]
    pub bar_height: f32,
    #[serde(default = "default_island_spacing")]
    pub island_spacing: f32,
    #[serde(default = "default_true")]
    pub multi_monitor: bool,
    #[serde(default = "default_true")]
    pub show_workspaces: bool,
    #[serde(default = "default_true")]
    pub show_media_in_center: bool,
    #[serde(default = "default_modules_left")]
    pub modules_left: Vec<BarModule>,
    #[serde(default = "default_modules_center")]
    pub modules_center: Vec<BarModule>,
    #[serde(default = "default_modules_right")]
    pub modules_right: Vec<BarModule>,
    #[serde(default = "default_animation_duration_ms")]
    pub animation_duration_ms: u32,
    #[serde(default = "default_gap")]
    pub gap: f32,
    #[serde(default = "default_capsule_round")]
    pub capsule_round: f32,
    #[serde(default = "default_satellite_round")]
    pub satellite_round: f32,
    #[serde(default = "default_cards_round")]
    pub cards_round: f32,
    #[serde(default = "default_margin_top")]
    pub margin_top: f32,
    #[serde(default = "default_exclusive_zone")]
    pub exclusive_zone: f32,
    #[serde(default = "default_idle_height")]
    pub idle_height: f32,
}

impl Default for ShellConfig {
    fn default() -> Self {
        Self {
            bar_style: BarStyleConfig::Island,
            bar_position: BarPosition::Top,
            theme_preset: ThemePresetConfig::WallpaperAuto,
            sound_feedback: true,
            blur_enabled: true,
            bar_height: 38.0,
            island_spacing: 12.0,
            multi_monitor: true,
            show_workspaces: true,
            show_media_in_center: true,
            modules_left: default_modules_left(),
            modules_center: default_modules_center(),
            modules_right: default_modules_right(),
            animation_duration_ms: default_animation_duration_ms(),
            gap: default_gap(),
            capsule_round: default_capsule_round(),
            satellite_round: default_satellite_round(),
            cards_round: default_cards_round(),
            margin_top: default_margin_top(),
            exclusive_zone: default_exclusive_zone(),
            idle_height: default_idle_height(),
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
            tracing::debug!("Loaded Beskar config from {}", path.display());
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

