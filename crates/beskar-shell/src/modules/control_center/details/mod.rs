pub mod audio;
pub mod calendar;
pub mod connectivity;
pub mod tray;

pub use audio::AudioDetailWidget;
pub use calendar::CalendarWidget;
pub use connectivity::{ConnectivityDetailWidget, ConnectivityTab};
pub use tray::{TrayDetailWidget, TrayMenuItem};
