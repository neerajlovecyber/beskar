//! Atomic Modules Subsystem for Beskar Desktop Shell
//!
//! Every feature (Control Center, Launcher, Power Menu, Clipboard, etc.)
//! is an isolated vertical-slice atomic module.

pub mod clipboard;
pub mod control_center;
pub mod dashboard;
pub mod launcher;
pub mod lock_screen;
pub mod music_player;
pub mod notification_center;
pub mod power_menu;
pub mod screen_capture;
pub mod settings;
pub mod tray_menu;
pub mod wallpaper_selector;

pub use clipboard::ClipboardView;
pub use control_center::ControlCenterView;
pub use dashboard::DashboardView;
pub use launcher::LauncherView;
pub use lock_screen::LockScreenView;
pub use music_player::MusicPlayerView;
pub use notification_center::{
    forget_notification_overlay, sync_notification_toasts, NotificationCenterView,
    NotificationToastQueueView,
};
pub use power_menu::PowerMenuView;
pub use screen_capture::ScreenCaptureView;
pub use settings::SettingsView;
pub use tray_menu::{open_tray_menu, TrayMenuView};
pub use wallpaper_selector::WallpaperSelectorView;

use crate::panel_host::PanelHost;
use gpui_kit::App;

/// Register all atomic desktop shell modules into PanelHost for dynamic IPC dispatch.
pub fn register_all_modules() {
    PanelHost::register::<launcher::LauncherView>();
    PanelHost::register::<control_center::ControlCenterView>();
    PanelHost::register::<power_menu::PowerMenuView>();
    PanelHost::register::<clipboard::ClipboardView>();
    PanelHost::register::<settings::SettingsView>();
    PanelHost::register::<music_player::MusicPlayerView>();
    PanelHost::register::<notification_center::NotificationCenterView>();
    PanelHost::register::<screen_capture::ScreenCaptureView>();
    PanelHost::register::<wallpaper_selector::WallpaperSelectorView>();
    PanelHost::register::<lock_screen::LockScreenView>();
    PanelHost::register::<dashboard::DashboardView>();
    PanelHost::register::<tray_menu::TrayMenuView>();
}

// ─────────────────────────────────────────────────────────────────────────────
// Strongly-typed toggle convenience helpers
// ─────────────────────────────────────────────────────────────────────────────

pub fn toggle_launcher(cx: &mut App) {
    PanelHost::toggle::<launcher::LauncherView>(cx);
}

pub fn toggle_control_center(cx: &mut App) {
    PanelHost::toggle::<control_center::ControlCenterView>(cx);
}

pub fn toggle_power_menu(cx: &mut App) {
    PanelHost::toggle::<power_menu::PowerMenuView>(cx);
}

pub fn toggle_lockscreen(cx: &mut App) {
    PanelHost::toggle::<lock_screen::LockScreenView>(cx);
}

pub fn toggle_settings(cx: &mut App) {
    PanelHost::toggle::<settings::SettingsView>(cx);
}

pub fn toggle_clipboard(cx: &mut App) {
    PanelHost::toggle::<clipboard::ClipboardView>(cx);
}

pub fn toggle_dashboard(cx: &mut App) {
    PanelHost::toggle::<dashboard::DashboardView>(cx);
}

pub fn toggle_music(cx: &mut App) {
    PanelHost::toggle::<music_player::MusicPlayerView>(cx);
}

pub fn toggle_notification_center(cx: &mut App) {
    PanelHost::toggle::<notification_center::NotificationCenterView>(cx);
}

pub fn toggle_screencapture(cx: &mut App) {
    PanelHost::toggle::<screen_capture::ScreenCaptureView>(cx);
}

pub fn toggle_wallpaper_selector(cx: &mut App) {
    PanelHost::toggle::<wallpaper_selector::WallpaperSelectorView>(cx);
}

pub fn close_active_overlay(cx: &mut App) -> Option<&'static str> {
    PanelHost::close(cx)
}
