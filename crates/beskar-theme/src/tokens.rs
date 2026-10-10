use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
pub struct HslaColor {
    pub h: f32, // 0.0 - 360.0
    pub s: f32, // 0.0 - 1.0
    pub l: f32, // 0.0 - 1.0
    pub a: f32, // 0.0 - 1.0
}

impl HslaColor {
    pub const fn new(h: f32, s: f32, l: f32, a: f32) -> Self {
        Self { h, s, l, a }
    }
}

/// Aesthetic Theme Tokens combining Suzuha's dark acrylic surfaces with iRiS's gold/amber & neutral palette.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ThemeTokens {
    // Acrylic Subsurfaces
    pub surface_bg: HslaColor,
    pub surface_hover: HslaColor,
    pub surface_active: HslaColor,
    pub surface_border: HslaColor,
    pub surface_glow: HslaColor,

    // Typography & Accents
    pub text_primary: HslaColor,
    pub text_secondary: HslaColor,
    pub text_muted: HslaColor,
    pub accent: HslaColor,
    pub accent_hover: HslaColor,

    // Status Colors
    pub success: HslaColor,
    pub warning: HslaColor,
    pub danger: HslaColor,

    // Geometry & Motion Parameters (from iRiS & Suzuha)
    pub bar_height: f32,
    pub pill_idle_height: f32,
    pub pill_corner_radius: f32,
    pub notch_flare_width: f32,
    pub notch_flare_height: f32,
    pub notch_bottom_radius: f32,
    pub spring_stiffness: f32,
    pub spring_damping: f32,
}

impl Default for ThemeTokens {
    fn default() -> Self {
        Self {
            // Dark obsidian frosted acrylic (Suzuha style)
            surface_bg: HslaColor::new(240.0, 0.12, 0.08, 0.82),
            surface_hover: HslaColor::new(240.0, 0.12, 0.14, 0.90),
            surface_active: HslaColor::new(240.0, 0.15, 0.18, 0.95),
            surface_border: HslaColor::new(240.0, 0.08, 1.0, 0.08),
            surface_glow: HslaColor::new(45.0, 0.85, 0.65, 0.12),

            // Typography & iRiS Warm Amber/Gold Accents
            text_primary: HslaColor::new(0.0, 0.0, 0.96, 1.0),
            text_secondary: HslaColor::new(0.0, 0.0, 0.75, 1.0),
            text_muted: HslaColor::new(0.0, 0.0, 0.45, 1.0),
            accent: HslaColor::new(45.0, 0.90, 0.60, 1.0), // Amber gold from screenshot
            accent_hover: HslaColor::new(45.0, 0.95, 0.68, 1.0),

            success: HslaColor::new(142.0, 0.70, 0.55, 1.0),
            warning: HslaColor::new(42.0, 0.90, 0.55, 1.0),
            danger: HslaColor::new(350.0, 0.85, 0.60, 1.0),

            // Geometry tokens
            bar_height: 44.0,
            pill_idle_height: 34.0,
            pill_corner_radius: 17.0,
            notch_flare_width: 18.0,
            notch_flare_height: 16.0,
            notch_bottom_radius: 16.0,
            spring_stiffness: 180.0,
            spring_damping: 18.0,
        }
    }
}
