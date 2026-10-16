use std::collections::hash_map::DefaultHasher;
use std::hash::{Hash, Hasher};
use std::path::{Path, PathBuf};

pub struct WallpaperService;

impl WallpaperService {
    /// Detect or read current wallpaper path from ~/.config/beskar/current_wallpaper or theme engine.
    pub fn get_current_wallpaper() -> Option<PathBuf> {
        let home = std::env::var("HOME").ok()?;
        let path = PathBuf::from(home).join(".config/beskar/current_wallpaper");
        if path.exists() {
            if let Ok(content) = std::fs::read_to_string(&path) {
                let trimmed = content.trim();
                let p = PathBuf::from(trimmed);
                if p.exists() {
                    return Some(p);
                }
            }
        }

        // Fallback: check ~/.config/capsule/current_wallpaper
        let home = std::env::var("HOME").ok()?;
        let alt = PathBuf::from(home).join(".config/capsule/current_wallpaper");
        if alt.exists() {
            if let Ok(content) = std::fs::read_to_string(&alt) {
                let p = PathBuf::from(content.trim());
                if p.exists() {
                    return Some(p);
                }
            }
        }

        None
    }

    /// Retrieve blurred version of current wallpaper if available.
    pub fn get_blurred_wallpaper() -> Option<PathBuf> {
        let current = Self::get_current_wallpaper()?;
        Self::create_or_get_blur(&current)
    }

    /// Non-blocking safe: compute and cache downscaled Gaussian blurred wallpaper in /tmp/beskar_blur
    pub fn create_or_get_blur(src: &Path) -> Option<PathBuf> {
        let metadata = std::fs::metadata(src).ok()?;
        let modified = metadata
            .modified()
            .ok()
            .and_then(|t| t.duration_since(std::time::UNIX_EPOCH).ok())
            .map(|d| d.as_secs())
            .unwrap_or(0);

        let mut hasher = DefaultHasher::new();
        src.hash(&mut hasher);
        modified.hash(&mut hasher);
        let hash = hasher.finish();

        let cache_dir = PathBuf::from("/tmp/beskar_blur");
        let _ = std::fs::create_dir_all(&cache_dir);
        let cached_path = cache_dir.join(format!("{:x}.jpg", hash));

        if cached_path.exists() {
            return Some(cached_path);
        }

        let img = image::open(src).ok()?;
        let orig_w = img.width();
        let orig_h = img.height();
        if orig_w == 0 || orig_h == 0 {
            return None;
        }

        let target_w = 960.min(orig_w).max(1);
        let target_h = ((target_w as f32 * (orig_h as f32 / orig_w as f32)) as u32).max(1);

        let downscaled = img
            .resize_exact(target_w, target_h, image::imageops::FilterType::Triangle)
            .to_rgba8();
        let blurred = image::imageops::blur(&downscaled, 4.5);
        blurred.save(&cached_path).ok()?;

        Some(cached_path)
    }
}
