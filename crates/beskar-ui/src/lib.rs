pub mod bar;
pub mod convex;
pub mod pill;
pub mod spring;
pub mod widgets;

pub use bar::{BarActions, BarState, BeskarBar};
pub use convex::{ConvexBarShape, ConvexGeometry};
pub use pill::IslandPill;
pub use spring::{SpringConfig, SpringValue};
pub use widgets::{
    CaptureMode, ClipboardWidget, DashboardWidget, DynamicCenterWidget, LauncherWidget, LockScreenWidget,
    MusicPlayerWidget, NotificationCenterWidget, NotificationToastWidget, PowerAction, PowerMenuWidget, ScreenCaptureWidget,
    SettingsCategory, SettingsConfig, SettingsWidget, VitalsWidget, WallpaperItem, WallpaperSelectorWidget, WorkspacesWidget,
};

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_capture_mode_properties() {
        assert_eq!(CaptureMode::FullScreen.label(), "Full Screen");
        assert_eq!(CaptureMode::SelectArea.label(), "Select Area");
        assert_eq!(CaptureMode::ExtractTextOcr.label(), "Extract Text (OCR)");
        assert_eq!(CaptureMode::RecordToggle.label(), "Screen Record");
    }

    #[test]
    fn test_wallpaper_discovery() {
        let walls = WallpaperSelectorWidget::discover_wallpapers();
        assert!(walls.is_empty() || !walls[0].name.is_empty());
    }
}


