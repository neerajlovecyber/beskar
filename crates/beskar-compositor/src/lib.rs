pub mod detector;
pub mod niri;
pub mod umbriel;

pub use detector::detect_compositor;
pub use niri::NiriBackend;
pub use umbriel::UmbrielBackend;
