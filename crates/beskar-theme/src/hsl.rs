use gpui_kit::Hsla;

/// Hue in degrees 0.0..=360.0, Saturation 0.0..=1.0, Lightness 0.0..=1.0.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Hsl {
    pub hue: f32,
    pub saturation: f32,
    pub lightness: f32,
}

impl Hsl {
    pub fn new(hue: f32, saturation: f32, lightness: f32) -> Self {
        Self {
            hue: hue.rem_euclid(360.0),
            saturation: saturation.clamp(0.0, 1.0),
            lightness: lightness.clamp(0.0, 1.0),
        }
    }

    pub fn to_hsla(self, alpha: f32) -> Hsla {
        gpui_kit::hsla(self.hue / 360.0, self.saturation, self.lightness, alpha.clamp(0.0, 1.0))
    }
}

pub fn from_rgb(r: u8, g: u8, b: u8) -> Hsl {
    let red = f32::from(r) / 255.0;
    let green = f32::from(g) / 255.0;
    let blue = f32::from(b) / 255.0;

    let highest = red.max(green).max(blue);
    let lowest = red.min(green).min(blue);

    let lightness = (highest + lowest) / 2.0;
    let spread = highest - lowest;

    if spread == 0.0 {
        return Hsl {
            hue: 0.0,
            saturation: 0.0,
            lightness,
        };
    }

    let saturation = spread / (1.0 - (2.0 * lightness - 1.0).abs());

    let sector = if highest == red {
        ((green - blue) / spread).rem_euclid(6.0)
    } else if highest == green {
        (blue - red) / spread + 2.0
    } else {
        (red - green) / spread + 4.0
    };

    Hsl {
        hue: sector * 60.0,
        saturation: saturation.clamp(0.0, 1.0),
        lightness: lightness.clamp(0.0, 1.0),
    }
}

pub fn to_rgb(hsl: Hsl) -> (u8, u8, u8) {
    let chroma = (1.0 - (2.0 * hsl.lightness - 1.0).abs()) * hsl.saturation;
    let sector = hsl.hue / 60.0;
    let second = chroma * (1.0 - (sector.rem_euclid(2.0) - 1.0).abs());

    let (red, green, blue) = match sector as u32 {
        0 => (chroma, second, 0.0),
        1 => (second, chroma, 0.0),
        2 => (0.0, chroma, second),
        3 => (0.0, second, chroma),
        4 => (second, 0.0, chroma),
        _ => (chroma, 0.0, second),
    };

    let lift = hsl.lightness - chroma / 2.0;

    (channel(red + lift), channel(green + lift), channel(blue + lift))
}

fn channel(value: f32) -> u8 {
    (value.clamp(0.0, 1.0) * 255.0).round() as u8
}

/// Linear relative luminance (WCAG definition)
pub fn luminance(r: u8, g: u8, b: u8) -> f32 {
    let linear = |val: u8| -> f32 {
        let v = f32::from(val) / 255.0;
        if v <= 0.04045 {
            v / 12.92
        } else {
            ((v + 0.055) / 1.055).powf(2.4)
        }
    };

    linear(r) * 0.2126 + linear(g) * 0.7152 + linear(b) * 0.0722
}

/// Perceived lightness (0.0 for black to 100.0 for white, 50.0 is middle grey)
pub fn perceived_lightness(r: u8, g: u8, b: u8) -> f32 {
    let lum = luminance(r, g, b);
    if lum <= 216.0 / 24389.0 {
        lum * 24389.0 / 27.0
    } else {
        116.0 * lum.cbrt() - 16.0
    }
}

/// Contrast ratio between two colors (1.0 up to 21.0)
pub fn contrast_ratio(c1: (u8, u8, u8), c2: (u8, u8, u8)) -> f32 {
    let l1 = luminance(c1.0, c1.1, c1.2);
    let l2 = luminance(c2.0, c2.1, c2.2);
    let lighter = l1.max(l2);
    let darker = l1.min(l2);
    (lighter + 0.05) / (darker + 0.05)
}

/// Retones an RGB color to target lightness, enforcing minimum colorfulness
pub fn tone(
    rgb: (u8, u8, u8),
    target_lightness: f32,
    min_saturation: f32,
    saturation_tuning: f32,
    contrast_tuning: f32,
) -> (u8, u8, u8) {
    let orig = from_rgb(rgb.0, rgb.1, rgb.2);
    let sat = orig.saturation.min(0.85).max(min_saturation);
    let sat = (sat * saturation_tuning).clamp(0.0, 1.0);
    let lit = 0.5 + (target_lightness - 0.5) * contrast_tuning;

    to_rgb(Hsl {
        hue: orig.hue,
        saturation: sat,
        lightness: lit.clamp(0.02, 0.98),
    })
}

/// Alpha blend two RGBA colors
pub fn mix_rgba(
    c1: (u8, u8, u8, u8),
    c2: (u8, u8, u8, u8),
    amount: f32,
) -> (u8, u8, u8, u8) {
    let amount = amount.clamp(0.0, 1.0);
    let a1 = f32::from(c1.3) / 255.0;
    let a2 = f32::from(c2.3) / 255.0;
    let alpha = a1 + (a2 - a1) * amount;

    if alpha <= 0.001 {
        return (0, 0, 0, 0);
    }

    let blend = |from: u8, to: u8| -> u8 {
        let f = f32::from(from) * a1;
        let t = f32::from(to) * a2;
        ((f + (t - f) * amount) / alpha).round().clamp(0.0, 255.0) as u8
    };

    (
        blend(c1.0, c2.0),
        blend(c1.1, c2.1),
        blend(c1.2, c2.2),
        (alpha * 255.0).round().clamp(0.0, 255.0) as u8,
    )
}
