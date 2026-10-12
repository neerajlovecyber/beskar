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

impl From<HslaColor> for gpui_kit::Hsla {
    fn from(c: HslaColor) -> Self {
        gpui_kit::hsla(c.h / 360.0, c.s, c.l, c.a)
    }
}

/// Centralized Minflair theme singleton matching `references/minflair/config/quickshell/Core/Theme.qml`.
#[derive(Debug, Clone, Copy)]
pub struct Theme;

impl Theme {
    /// Active surface background
    #[inline]
    pub fn bg() -> gpui_kit::Hsla {
        crate::engine::ThemeEngine::current().surface_bg.into()
    }

    /// Primary foreground text
    #[inline]
    pub fn fg() -> gpui_kit::Hsla {
        crate::engine::ThemeEngine::current().text_primary.into()
    }

    /// Primary accent
    #[inline]
    pub fn accent() -> gpui_kit::Hsla {
        crate::engine::ThemeEngine::current().accent.into()
    }

    /// Complementary accent (hue offset by 70 degrees)
    #[inline]
    pub fn accent_complementary() -> gpui_kit::Hsla {
        let t = crate::engine::ThemeEngine::current();
        gpui_kit::hsla(
            ((t.accent.h + 70.0).rem_euclid(360.0)) / 360.0,
            t.accent.s,
            t.accent.l,
            t.accent.a,
        )
    }

    /// Muted text and inactive icons
    #[inline]
    pub fn muted() -> gpui_kit::Hsla {
        crate::engine::ThemeEngine::current().text_muted.into()
    }

    /// Subtle perimeter border
    #[inline]
    pub fn border() -> gpui_kit::Hsla {
        crate::engine::ThemeEngine::current().surface_border.into()
    }

    /// Secondary background for hovered/selected pills and items
    #[inline]
    pub fn bg_secondary() -> gpui_kit::Hsla {
        crate::engine::ThemeEngine::current().surface_hover.into()
    }

    /// Tertiary background
    #[inline]
    pub fn bg_tertiary() -> gpui_kit::Hsla {
        crate::engine::ThemeEngine::current().surface_active.into()
    }

    /// Accent tinted background
    #[inline]
    pub fn bg_accent() -> gpui_kit::Hsla {
        let mut a = crate::engine::ThemeEngine::current().accent;
        a.a = 0.18;
        a.into()
    }

    /// Card / overlay shadow
    #[inline]
    pub fn shadow() -> gpui_kit::Hsla {
        gpui_kit::hsla(0.0, 0.0, 0.0, 0.75)
    }

    /// Secondary foreground text
    #[inline]
    pub fn text_secondary() -> gpui_kit::Hsla {
        crate::engine::ThemeEngine::current().text_secondary.into()
    }

    /// Status success color
    #[inline]
    pub fn success() -> gpui_kit::Hsla {
        crate::engine::ThemeEngine::current().success.into()
    }

    #[inline]
    pub fn success_alpha(alpha: f32) -> gpui_kit::Hsla {
        let mut c = crate::engine::ThemeEngine::current().success;
        c.a = alpha;
        c.into()
    }

    /// Status warning color
    #[inline]
    pub fn warning() -> gpui_kit::Hsla {
        crate::engine::ThemeEngine::current().warning.into()
    }

    #[inline]
    pub fn warning_alpha(alpha: f32) -> gpui_kit::Hsla {
        let mut c = crate::engine::ThemeEngine::current().warning;
        c.a = alpha;
        c.into()
    }

    /// Status danger / alert color
    #[inline]
    pub fn danger() -> gpui_kit::Hsla {
        crate::engine::ThemeEngine::current().danger.into()
    }

    #[inline]
    pub fn danger_alpha(alpha: f32) -> gpui_kit::Hsla {
        let mut c = crate::engine::ThemeEngine::current().danger;
        c.a = alpha;
        c.into()
    }

    /// Informational / Bluetooth accent color
    #[inline]
    pub fn info() -> gpui_kit::Hsla {
        crate::engine::ThemeEngine::current().info.into()
    }

    #[inline]
    pub fn info_alpha(alpha: f32) -> gpui_kit::Hsla {
        let mut c = crate::engine::ThemeEngine::current().info;
        c.a = alpha;
        c.into()
    }

    /// Primary accent with specified alpha
    #[inline]
    pub fn accent_alpha(alpha: f32) -> gpui_kit::Hsla {
        let mut c = crate::engine::ThemeEngine::current().accent;
        c.a = alpha;
        c.into()
    }

    /// High-level card background surface
    #[inline]
    pub fn card_bg() -> gpui_kit::Hsla {
        let mut s = crate::engine::ThemeEngine::current().surface_bg;
        s.a = 0.94;
        s.into()
    }

    /// Card boundary border
    #[inline]
    pub fn card_border() -> gpui_kit::Hsla {
        gpui_kit::hsla(240.0 / 360.0, 0.10, 1.0, 0.14)
    }

    /// Subtle divider border (8%-12% alpha)
    #[inline]
    pub fn subtle_border() -> gpui_kit::Hsla {
        gpui_kit::hsla(0.0, 0.0, 1.0, 0.10)
    }

    /// Transparent glass fill (white tinted by alpha)
    #[inline]
    pub fn glass_fill(alpha: f32) -> gpui_kit::Hsla {
        gpui_kit::hsla(0.0, 0.0, 1.0, alpha)
    }

    /// Transparent glass dark fill (black tinted by alpha)
    #[inline]
    pub fn glass_dark(alpha: f32) -> gpui_kit::Hsla {
        gpui_kit::hsla(0.0, 0.0, 0.0, alpha)
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
    pub info: HslaColor,

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
            info: HslaColor::new(210.0, 0.85, 0.60, 1.0),

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
