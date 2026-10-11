use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::RwLock;
use tracing::info;

use crate::hsl::{from_rgb, mix_rgba, tone};
use crate::palette::ExtractedPalette;
use crate::tokens::{HslaColor, ThemeTokens};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ThemePreset {
    Obsidian,
    CatppuccinMocha,
    GruvboxDark,
    Wallpaper,
}

impl ThemePreset {
    pub fn name(&self) -> &'static str {
        match self {
            Self::Obsidian => "Obsidian Glass (Default)",
            Self::CatppuccinMocha => "Catppuccin Mocha",
            Self::GruvboxDark => "Gruvbox Dark",
            Self::Wallpaper => "Dynamic Wallpaper Engine",
        }
    }
}

static CURRENT_PRESET: AtomicUsize = AtomicUsize::new(0); // 0 = Obsidian, 1 = Catppuccin, 2 = Gruvbox, 3 = Wallpaper
static GLOBAL_THEME: RwLock<Option<ThemeTokens>> = RwLock::new(None);

pub struct ThemeEngine;

impl ThemeEngine {
    /// Retrieve active ThemeTokens singleton
    pub fn current() -> ThemeTokens {
        if let Ok(guard) = GLOBAL_THEME.read() {
            if let Some(theme) = guard.as_ref() {
                return theme.clone();
            }
        }

        // Default fallback
        let default_theme = ThemeTokens::default();
        if let Ok(mut guard) = GLOBAL_THEME.write() {
            *guard = Some(default_theme.clone());
        }
        default_theme
    }

    /// Set theme directly
    pub fn set_theme(tokens: ThemeTokens) {
        if let Ok(mut guard) = GLOBAL_THEME.write() {
            *guard = Some(tokens);
        }
    }

    /// Set theme preset
    pub fn set_preset(preset: ThemePreset) {
        let code = match preset {
            ThemePreset::Obsidian => 0,
            ThemePreset::CatppuccinMocha => 1,
            ThemePreset::GruvboxDark => 2,
            ThemePreset::Wallpaper => 3,
        };
        CURRENT_PRESET.store(code, Ordering::Relaxed);

        let tokens = match preset {
            ThemePreset::Obsidian => ThemeTokens::default(),
            ThemePreset::CatppuccinMocha => Self::catppuccin_mocha(),
            ThemePreset::GruvboxDark => Self::gruvbox_dark(),
            ThemePreset::Wallpaper => {
                if let Some(path) = Self::detect_wallpaper_path() {
                    match Self::generate_from_wallpaper(&path) {
                        Ok(t) => t,
                        Err(err) => {
                            info!("Failed to extract wallpaper palette: {err}, falling back to default");
                            ThemeTokens::default()
                        }
                    }
                } else {
                    ThemeTokens::default()
                }
            }
        };

        Self::set_theme(tokens);
    }

    pub fn current_preset() -> ThemePreset {
        match CURRENT_PRESET.load(Ordering::Relaxed) {
            1 => ThemePreset::CatppuccinMocha,
            2 => ThemePreset::GruvboxDark,
            3 => ThemePreset::Wallpaper,
            _ => ThemePreset::Obsidian,
        }
    }

    /// Detect active wallpaper path from standard Linux Wayland configurations
    pub fn detect_wallpaper_path() -> Option<PathBuf> {
        let home = std::env::var("HOME").ok()?;

        // 1. Suzuha / Amane wallpaper-selection
        let amane_path = PathBuf::from(&home).join(".local/state/amane/wallpaper-selection");
        if amane_path.exists() {
            if let Ok(text) = std::fs::read_to_string(&amane_path) {
                let url = text.trim();
                let clean = url.strip_prefix("file://").unwrap_or(url);
                let p = PathBuf::from(clean);
                if p.exists() {
                    return Some(p);
                }
            }
        }

        // 2. ~/.current_wallpaper symlink or text file
        let cur_wall = PathBuf::from(&home).join(".current_wallpaper");
        if cur_wall.exists() {
            if let Ok(target) = std::fs::read_link(&cur_wall) {
                if target.exists() {
                    return Some(target);
                }
            }
            if let Ok(text) = std::fs::read_to_string(&cur_wall) {
                let p = PathBuf::from(text.trim());
                if p.exists() {
                    return Some(p);
                }
            }
        }

        // 3. Swww cache
        let swww_cache = PathBuf::from(&home).join(".cache/swww");
        if swww_cache.is_dir() {
            if let Ok(entries) = std::fs::read_dir(swww_cache) {
                for entry in entries.flatten() {
                    let path = entry.path();
                    if path.is_file() {
                        if let Ok(text) = std::fs::read_to_string(&path) {
                            let p = PathBuf::from(text.trim());
                            if p.exists() {
                                return Some(p);
                            }
                        }
                    }
                }
            }
        }

        // 4. Default pictures directory
        let pictures = PathBuf::from(&home).join("Pictures");
        if pictures.is_dir() {
            let candidates = ["wallpaper.png", "wallpaper.jpg", "wallpaper.webp", "bg.png", "bg.jpg"];
            for c in candidates {
                let p = pictures.join(c);
                if p.exists() {
                    return Some(p);
                }
            }
        }

        None
    }

    /// Dynamically generate ThemeTokens from an image or wallpaper
    pub fn generate_from_wallpaper(path: &Path) -> Result<ThemeTokens, anyhow::Error> {
        let palette = ExtractedPalette::from_image_path(path, 16)?;

        let base = palette.background;
        let seed = palette.accent;

        // Suzuha HSL derivation formulas
        let (sr, sg, sb) = tone((base[0], base[1], base[2]), 0.12, 0.28, 1.0, 1.0);
        let surface_rgba = (sr, sg, sb, 210);

        let (ar, ag, ab) = tone((seed[0], seed[1], seed[2]), 0.68, 0.58, 1.0, 1.0);
        let (ahr, ahg, ahb) = tone((seed[0], seed[1], seed[2]), 0.78, 0.48, 1.0, 1.0);
        let accent_rgba = (ar, ag, ab, 255);

        // Mix hover & active surfaces with subtle accent tints
        let hover_rgba = mix_rgba(surface_rgba, accent_rgba, 0.18);
        let active_rgba = mix_rgba(surface_rgba, accent_rgba, 0.28);
        let border_rgba = mix_rgba(surface_rgba, accent_rgba, 0.32);

        let (tr, tg, tb) = (palette.foreground[0], palette.foreground[1], palette.foreground[2]);
        let (str, stg, stb) = tone((base[0], base[1], base[2]), 0.72, 0.14, 1.0, 1.0);
        let (mtr, mtg, mtb) = tone((base[0], base[1], base[2]), 0.52, 0.16, 1.0, 1.0);

        let to_hsla_color = |r: u8, g: u8, b: u8, a: u8| -> HslaColor {
            let hsl = from_rgb(r, g, b);
            HslaColor::new(hsl.hue, hsl.saturation, hsl.lightness, f32::from(a) / 255.0)
        };

        let default = ThemeTokens::default();

        Ok(ThemeTokens {
            surface_bg: to_hsla_color(surface_rgba.0, surface_rgba.1, surface_rgba.2, surface_rgba.3),
            surface_hover: to_hsla_color(hover_rgba.0, hover_rgba.1, hover_rgba.2, hover_rgba.3),
            surface_active: to_hsla_color(active_rgba.0, active_rgba.1, active_rgba.2, active_rgba.3),
            surface_border: to_hsla_color(border_rgba.0, border_rgba.1, border_rgba.2, border_rgba.3),
            surface_glow: to_hsla_color(ar, ag, ab, 35),

            text_primary: to_hsla_color(tr, tg, tb, 255),
            text_secondary: to_hsla_color(str, stg, stb, 255),
            text_muted: to_hsla_color(mtr, mtg, mtb, 255),

            accent: to_hsla_color(ar, ag, ab, 255),
            accent_hover: to_hsla_color(ahr, ahg, ahb, 255),

            success: to_hsla_color(166, 227, 161, 255),
            warning: to_hsla_color(249, 226, 175, 255),
            danger: to_hsla_color(243, 139, 168, 255),

            bar_height: default.bar_height,
            pill_idle_height: default.pill_idle_height,
            pill_corner_radius: default.pill_corner_radius,
            notch_flare_width: default.notch_flare_width,
            notch_flare_height: default.notch_flare_height,
            notch_bottom_radius: default.notch_bottom_radius,
            spring_stiffness: default.spring_stiffness,
            spring_damping: default.spring_damping,
        })
    }

    /// Catppuccin Mocha preset
    pub fn catppuccin_mocha() -> ThemeTokens {
        ThemeTokens {
            surface_bg: HslaColor::new(240.0, 0.21, 0.12, 0.88),    // Crust / Mantle
            surface_hover: HslaColor::new(237.0, 0.16, 0.23, 0.92), // Surface0
            surface_active: HslaColor::new(237.0, 0.16, 0.28, 0.95),// Surface1
            surface_border: HslaColor::new(237.0, 0.16, 0.35, 0.25),// Surface2
            surface_glow: HslaColor::new(267.0, 0.84, 0.81, 0.15),  // Mauve glow

            text_primary: HslaColor::new(226.0, 0.64, 0.88, 1.0),   // Text
            text_secondary: HslaColor::new(228.0, 0.39, 0.80, 1.0), // Subtext0
            text_muted: HslaColor::new(228.0, 0.24, 0.60, 1.0),     // Overlay0

            accent: HslaColor::new(267.0, 0.84, 0.81, 1.0),         // Mauve
            accent_hover: HslaColor::new(267.0, 0.90, 0.86, 1.0),

            success: HslaColor::new(115.0, 0.54, 0.76, 1.0),        // Green
            warning: HslaColor::new(40.0, 0.86, 0.83, 1.0),         // Yellow
            danger: HslaColor::new(343.0, 0.81, 0.75, 1.0),         // Red

            ..Default::default()
        }
    }

    /// Gruvbox Dark preset
    pub fn gruvbox_dark() -> ThemeTokens {
        ThemeTokens {
            surface_bg: HslaColor::new(0.0, 0.0, 0.11, 0.90),       // bg0 (#1d2021)
            surface_hover: HslaColor::new(45.0, 0.05, 0.20, 0.92),  // bg1
            surface_active: HslaColor::new(45.0, 0.05, 0.26, 0.95), // bg2
            surface_border: HslaColor::new(45.0, 0.05, 0.40, 0.20),
            surface_glow: HslaColor::new(24.0, 0.75, 0.55, 0.15),   // Orange glow

            text_primary: HslaColor::new(43.0, 0.29, 0.86, 1.0),    // fg0 (#fbf1c7)
            text_secondary: HslaColor::new(43.0, 0.20, 0.75, 1.0),  // fg1
            text_muted: HslaColor::new(43.0, 0.10, 0.55, 1.0),      // gray

            accent: HslaColor::new(24.0, 0.95, 0.55, 1.0),          // Orange (#fe8019)
            accent_hover: HslaColor::new(24.0, 1.0, 0.62, 1.0),

            success: HslaColor::new(76.0, 0.65, 0.55, 1.0),         // Green (#b8bb26)
            warning: HslaColor::new(43.0, 0.80, 0.55, 1.0),         // Yellow (#fabd2f)
            danger: HslaColor::new(0.0, 0.75, 0.60, 1.0),           // Red (#fb4934)

            ..Default::default()
        }
    }
}
