pub mod detector;
pub mod hyprland;
pub mod niri;
pub mod umbriel;

pub use detector::detect_compositor;
pub use hyprland::HyprlandBackend;
pub use niri::NiriBackend;
pub use umbriel::UmbrielBackend;
