pub mod control_center;
pub mod dynamic_center;
pub mod launcher;
pub mod lockscreen;
pub mod notification_toast;
pub mod vitals;
pub mod workspaces;

pub use control_center::ControlCenterWidget;
pub use dynamic_center::DynamicCenterWidget;
pub use launcher::LauncherWidget;
pub use lockscreen::LockScreenWidget;
pub use notification_toast::NotificationToastWidget;
pub use vitals::VitalsWidget;
pub use workspaces::WorkspacesWidget;
