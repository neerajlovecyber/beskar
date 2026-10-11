use std::path::Path;
use image::GenericImageView;
use crate::hsl::{contrast_ratio, from_rgb, luminance, perceived_lightness};

const SAMPLE_SIDE: u32 = 64;
const MIN_ALPHA: u8 = 128;

/// Bucket of pixels for median cut partitioning
struct Bucket {
    pixels: Vec<[u8; 3]>,
}

impl Bucket {
    fn widest_channel(&self) -> (usize, u8) {
        let mut widest = 0;
        let mut widest_range = 0;

        for channel in 0..3 {
            let mut lowest = u8::MAX;
            let mut highest = u8::MIN;

            for pixel in &self.pixels {
                lowest = lowest.min(pixel[channel]);
                highest = highest.max(pixel[channel]);
            }

            let range = highest.saturating_sub(lowest);
            if range > widest_range {
                widest = channel;
                widest_range = range;
            }
        }

        (widest, widest_range)
    }

    fn average(&self) -> [u8; 3] {
        let mut total = [0u64; 3];
        for pixel in &self.pixels {
            for ch in 0..3 {
                total[ch] += u64::from(pixel[ch]);
            }
        }
        let count = self.pixels.len().max(1) as u64;
        [
            (total[0] / count) as u8,
            (total[1] / count) as u8,
            (total[2] / count) as u8,
        ]
    }
}

/// Quantize pixels to `count` dominant colors using median-cut
pub fn median_cut_quantize(pixels: Vec<[u8; 3]>, count: usize) -> Vec<[u8; 3]> {
    if pixels.is_empty() || count == 0 {
        return Vec::new();
    }

    let mut buckets = vec![Bucket { pixels }];

    while buckets.len() < count {
        let Some(index) = widest_bucket(&buckets) else {
            break;
        };

        let bucket = buckets.swap_remove(index);
        let (lower, upper) = split_bucket(bucket);
        buckets.push(lower);
        buckets.push(upper);
    }

    // Sort by largest bucket size first (most dominant color first)
    buckets.sort_by_key(|b| std::cmp::Reverse(b.pixels.len()));
    buckets.iter().map(Bucket::average).collect()
}

fn widest_bucket(buckets: &[Bucket]) -> Option<usize> {
    let mut widest = None;
    let mut widest_range = 0;

    for (index, bucket) in buckets.iter().enumerate() {
        if bucket.pixels.len() < 2 {
            continue;
        }
        let (_, range) = bucket.widest_channel();
        if range > widest_range {
            widest = Some(index);
            widest_range = range;
        }
    }

    widest
}

fn split_bucket(mut bucket: Bucket) -> (Bucket, Bucket) {
    let (channel, _) = bucket.widest_channel();
    bucket.pixels.sort_unstable_by_key(|pixel| pixel[channel]);
    let middle = bucket.pixels.len() / 2;
    let upper = bucket.pixels.split_off(middle);
    (bucket, Bucket { pixels: upper })
}

/// Sample pixels quickly from an image
pub fn sample_image(img: &image::DynamicImage) -> Vec<[u8; 3]> {
    let (width, height) = img.dimensions();
    let longest = width.max(height);
    let step = (longest / SAMPLE_SIDE).max(1);

    let mut picked = Vec::new();
    for y in (0..height).step_by(step as usize) {
        for x in (0..width).step_by(step as usize) {
            let pixel = img.get_pixel(x, y);
            if pixel[3] < MIN_ALPHA {
                continue;
            }
            picked.push([pixel[0], pixel[1], pixel[2]]);
        }
    }

    picked
}

/// Extracted palette result
#[derive(Debug, Clone)]
pub struct ExtractedPalette {
    pub colors: Vec<[u8; 3]>,
    pub dominant: [u8; 3],
    pub accent: [u8; 3],
    pub background: [u8; 3],
    pub foreground: [u8; 3],
    pub is_light: bool,
}

impl ExtractedPalette {
    pub fn from_image_path(path: &Path, count: usize) -> Result<Self, anyhow::Error> {
        let img = image::open(path)?;
        let pixels = sample_image(&img);
        let colors = median_cut_quantize(pixels, count);

        let dominant = colors.first().copied().unwrap_or([18, 18, 24]);
        let background = pick_darkest(&colors).unwrap_or([18, 18, 24]);
        let accent = pick_most_vivid(&colors).unwrap_or([167, 126, 245]);
        let foreground = pick_readable_on(background, &colors);

        let mut total_lightness = 0.0;
        for c in &colors {
            total_lightness += perceived_lightness(c[0], c[1], c[2]);
        }
        let avg_lightness = total_lightness / colors.len().max(1) as f32;
        let is_light = avg_lightness >= 50.0;

        Ok(Self {
            colors,
            dominant,
            accent,
            background,
            foreground,
            is_light,
        })
    }
}

pub fn pick_darkest(colors: &[[u8; 3]]) -> Option<[u8; 3]> {
    let mut darkest = *colors.first()?;
    for &color in colors {
        if luminance(color[0], color[1], color[2]) < luminance(darkest[0], darkest[1], darkest[2]) {
            darkest = color;
        }
    }
    Some(darkest)
}

pub fn pick_most_vivid(colors: &[[u8; 3]]) -> Option<[u8; 3]> {
    let mut vivid = *colors.first()?;
    let mut vivid_score = f32::MIN;

    const SATURATION_WEIGHT: f32 = 1.4;
    const TARGET_LUMINANCE: f32 = 0.52;
    const LUMINANCE_PENALTY: f32 = 0.35;

    for &color in colors {
        let hsl = from_rgb(color[0], color[1], color[2]);
        let lum = luminance(color[0], color[1], color[2]);
        let sat_score = hsl.saturation * SATURATION_WEIGHT;
        let dist = (lum - TARGET_LUMINANCE).abs() * LUMINANCE_PENALTY;
        let score = sat_score - dist;

        if score > vivid_score {
            vivid = color;
            vivid_score = score;
        }
    }

    Some(vivid)
}

pub fn pick_readable_on(bg: [u8; 3], colors: &[[u8; 3]]) -> [u8; 3] {
    let mut best = bg;
    let mut best_contrast = 1.0;

    for &color in colors {
        let c = contrast_ratio((color[0], color[1], color[2]), (bg[0], bg[1], bg[2]));
        if c > best_contrast {
            best = color;
            best_contrast = c;
        }
    }

    if best_contrast < 4.5 {
        let white_c = contrast_ratio((255, 255, 255), (bg[0], bg[1], bg[2]));
        let black_c = contrast_ratio((0, 0, 0), (bg[0], bg[1], bg[2]));
        if white_c >= black_c {
            return [245, 245, 248];
        } else {
            return [15, 15, 18];
        }
    }

    best
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_median_cut_quantize() {
        let mut pixels = Vec::new();
        for _ in 0..100 {
            pixels.push([255, 0, 0]); // Red
        }
        for _ in 0..50 {
            pixels.push([0, 255, 0]); // Green
        }
        for _ in 0..25 {
            pixels.push([0, 0, 255]); // Blue
        }

        let palette = median_cut_quantize(pixels, 3);
        assert_eq!(palette.len(), 3);
        assert_eq!(palette[0], [255, 0, 0]); // Most dominant first
    }

    #[test]
    fn test_pick_most_vivid() {
        let colors = vec![[20, 20, 20], [167, 126, 245], [200, 200, 200]];
        let vivid = pick_most_vivid(&colors).unwrap();
        assert_eq!(vivid, [167, 126, 245]);
    }
}
