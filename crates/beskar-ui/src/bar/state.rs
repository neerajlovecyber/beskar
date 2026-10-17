use beskar_core::models::{WindowInfo, WorkspaceInfo};
use gpui_kit::assets::IconName;
use std::sync::Arc;

pub fn resolve_window_icon(app_id: Option<&str>, title: Option<&str>) -> IconName {
    let text = format!(
        "{} {}",
        app_id.unwrap_or_default().to_lowercase(),
        title.unwrap_or_default().to_lowercase()
    );

    if text.contains("firefox") || text.contains("chrome") || text.contains("browser") {
        IconName::Globe
    } else if text.contains("term")
        || text.contains("kitty")
        || text.contains("alacritty")
        || text.contains("wezterm")
    {
        IconName::Terminal
    } else if text.contains("code")
        || text.contains("zed")
        || text.contains("nvim")
        || text.contains("vim")
    {
        IconName::Code
    } else if text.contains("files")
        || text.contains("folder")
        || text.contains("nautilus")
        || text.contains("thunar")
        || text.contains("dolphin")
    {
        IconName::Folder
    } else if text.contains("music") || text.contains("spotify") {
        IconName::Music
    } else if text.contains("discord") || text.contains("slack") || text.contains("telegram") {
        IconName::MessageSquare
    } else if text.contains("settings") {
        IconName::Settings
    } else {
        IconName::AppWindow
    }
}

/// Grouped snapshot of live system and shell telemetry for BeskarBar.
#[derive(Clone, Default)]
pub struct BarState {
    pub bar_style: beskar_core::config::BarStyleConfig,
    pub is_convex: bool,
    pub workspaces: Vec<WorkspaceInfo>,
    pub active_ws: Option<u64>,
    pub active_window: Option<WindowInfo>,
    pub workspace_windows: Vec<WindowInfo>,
    pub all_windows: Vec<WindowInfo>,
    pub time_str: String,
    pub date_str: Option<String>,
    pub media: Option<(String, String, bool)>,
    pub notification: Option<(String, String)>,
    pub volume_percent: u8,
    pub is_muted: bool,
    pub battery_percent: u8,
    pub is_charging: bool,
    pub cpu_usage: Option<f32>,
    pub ram_usage: Option<f32>,
    pub animated_center_width: Option<f32>,
    pub cava_bands: Option<[u8; 4]>,
    pub tray_items: Vec<beskar_core::models::TrayItem>,
    pub modules_left: Option<Vec<beskar_core::config::BarModule>>,
    pub modules_center: Option<Vec<beskar_core::config::BarModule>>,
    pub modules_right: Option<Vec<beskar_core::config::BarModule>>,
    pub geometry: Option<crate::convex::ConvexGeometry>,
}

/// Unified Bar Style contract (mirrors Minflair Bar.qml:16-32 and Capsule island topology).
/// Exposes width geometry for Left, Center (x + width), and Right regions.
pub trait BarStyle {
    /// Return the four core layout widths: (left_width, center_x, center_width, right_width)
    fn widths(&self) -> (f32, f32, f32, f32);
    /// Whether the central dynamic island is currently expanded
    fn is_expanded(&self) -> bool;
}

impl BarStyle for BarState {
    fn widths(&self) -> (f32, f32, f32, f32) {
        let center_w = self.animated_center_width.unwrap_or(150.0).max(140.0);
        if let Some(geom) = &self.geometry {
            (geom.left_w, geom.center_x, geom.center_w, geom.right_w)
        } else {
            (320.0, 960.0 - center_w / 2.0, center_w, 360.0)
        }
    }

    fn is_expanded(&self) -> bool {
        self.animated_center_width.map_or(false, |w| w > 200.0)
    }
}

pub type BarUiCallback = Arc<dyn Fn(&mut gpui_kit::Window, &mut gpui_kit::App) + Send + Sync>;
pub type BarTrayMenuCallback = Arc<dyn Fn(String, &mut gpui_kit::Window, &mut gpui_kit::App) + Send + Sync>;

/// Callbacks for interactive bar actions.
#[derive(Clone, Default)]
pub struct BarActions {
    pub on_select_ws: Option<Arc<dyn Fn(u64) + Send + Sync>>,
    pub on_scroll_ws: Option<Arc<dyn Fn(i32) + Send + Sync>>,
    pub on_select_window: Option<Arc<dyn Fn(u64) + Send + Sync>>,
    pub on_play_pause: Option<Arc<dyn Fn() + Send + Sync>>,
    pub on_volume_click: Option<Arc<dyn Fn() + Send + Sync>>,
    pub on_volume_scroll: Option<Arc<dyn Fn(i32) + Send + Sync>>,
    pub on_control_center_click: Option<BarUiCallback>,
    pub on_power_click: Option<BarUiCallback>,
    pub on_launcher_click: Option<BarUiCallback>,
    pub on_clock_click: Option<BarUiCallback>,
    pub on_dashboard_click: Option<BarUiCallback>,
    pub on_music_click: Option<BarUiCallback>,
    pub on_capture_click: Option<BarUiCallback>,
    pub on_wallpaper_click: Option<BarUiCallback>,
    pub on_tray_click: Option<Arc<dyn Fn(String) + Send + Sync>>,
    pub on_tray_menu: Option<BarTrayMenuCallback>,
    pub on_window_click: Option<Arc<dyn Fn() + Send + Sync>>,
    pub on_window_close: Option<Arc<dyn Fn() + Send + Sync>>,
}
