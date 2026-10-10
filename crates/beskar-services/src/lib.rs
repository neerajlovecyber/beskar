pub mod audio;
pub mod auth;
pub mod battery;
pub mod bluez;
pub mod desktop;
pub mod files;
pub mod hub;
pub mod mpris;
pub mod mpris_pleamar;
pub mod networkmanager;
pub mod notifications;
pub mod sysvalue;
pub mod tray;

pub use audio::AudioService;
pub use auth::verify as verify_password;
pub use battery::BatteryService;
pub use desktop::{launch as launch_app, list_apps};
pub use hub::{SystemHub, SystemSnapshot};
pub use mpris::MprisService;
pub use sysvalue::SysValue;

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_list_apps_discovery() {
        let apps = list_apps();
        assert!(!apps.is_empty(), "Should discover installed desktop applications");
        let first = &apps[0];
        assert!(!first.name.is_empty(), "App should have a name");
    }
}
