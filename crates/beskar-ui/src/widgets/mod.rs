pub mod clipboard;
pub mod control_center;
pub mod dashboard;
pub mod dynamic_center;
pub mod launcher;
pub mod lockscreen;
pub mod music_player;
pub mod notification_center;
pub mod notification_toast;
pub mod power_menu;
pub mod screen_capture;
pub mod settings;
pub mod vitals;
pub mod wallpaper_selector;
pub mod workspaces;

pub use clipboard::ClipboardWidget;
pub use control_center::ControlCenterWidget;
pub use dashboard::DashboardWidget;
pub use dynamic_center::DynamicCenterWidget;
pub use launcher::LauncherWidget;
pub use lockscreen::LockScreenWidget;
pub use music_player::MusicPlayerWidget;
pub use notification_center::NotificationCenterWidget;
pub use notification_toast::NotificationToastWidget;
pub use power_menu::{PowerAction, PowerMenuWidget};
pub use screen_capture::{CaptureMode, ScreenCaptureWidget};
pub use settings::{SettingsCategory, SettingsConfig, SettingsWidget};
pub use vitals::VitalsWidget;
pub use wallpaper_selector::{WallpaperItem, WallpaperSelectorWidget};
pub use workspaces::WorkspacesWidget;


