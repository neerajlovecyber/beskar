pub mod engine;
pub mod hsl;
pub mod palette;
pub mod tokens;

pub use engine::{ThemeEngine, ThemePreset};
pub use hsl::{Hsl, contrast_ratio, from_rgb, mix_rgba, perceived_lightness, to_rgb, tone};
pub use palette::{ExtractedPalette, median_cut_quantize, sample_image};
pub use tokens::*;

/// Subsurface separable Gaussian acrylic blur shader source (WGSL)
pub const BACKDROP_SHADER: &str = include_str!("../shaders/backdrop.wgsl");

/// Liquid organic SDF union and shadow blur shader source (WGSL)
pub const LIQUID_SHADER: &str = include_str!("../shaders/liquid.wgsl");

/// High-performance vector shape, glass, and dispersion shader source (WGSL)
pub const SHAPE_SHADER: &str = include_str!("../shaders/shape.wgsl");
