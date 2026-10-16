use std::collections::VecDeque;
use std::fs::{self, File};
use std::io::{BufReader, BufWriter};
use std::path::PathBuf;
use std::sync::{Arc, Mutex, OnceLock};

use arboard::Clipboard;
pub use beskar_core::ClipboardEntry;
use serde::{Deserialize, Serialize};
use tracing::{debug, error, info, warn};

const MAX_HISTORY_DEFAULT: usize = 100;

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ClipboardItem {
    pub id: String,
    pub preview: String,
    pub is_image: bool,
    pub image_path: Option<PathBuf>,
}

#[derive(Debug, Clone)]
pub enum ClipboardContent {
    Text(String),
    Image(Vec<u8>),
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Snippet {
    pub id: String,
    pub title: String,
    pub content: String,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct SnippetsConfig {
    #[serde(default)]
    pub snippets: Vec<Snippet>,
}

impl SnippetsConfig {
    pub fn get_path() -> PathBuf {
        let base = std::env::var("XDG_CONFIG_HOME")
            .map(PathBuf::from)
            .unwrap_or_else(|_| {
                let home = std::env::var("HOME").unwrap_or_else(|_| ".".to_string());
                PathBuf::from(home).join(".config")
            });
        base.join("beskar").join("snippets.json")
    }

    pub fn load() -> Self {
        let path = Self::get_path();
        if path.exists() {
            if let Ok(file) = File::open(&path) {
                let reader = BufReader::new(file);
                if let Ok(cfg) = serde_json::from_reader(reader) {
                    return cfg;
                }
            }
        }
        let default_cfg = Self::default();
        let _ = default_cfg.save();
        default_cfg
    }

    pub fn save(&self) -> std::io::Result<()> {
        let path = Self::get_path();
        if let Some(parent) = path.parent() {
            let _ = fs::create_dir_all(parent);
        }
        let file = File::create(path)?;
        let writer = BufWriter::new(file);
        serde_json::to_writer_pretty(writer, self)?;
        Ok(())
    }

    pub fn add(&mut self, title: String, content: String) -> Snippet {
        let timestamp = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|duration| duration.as_millis())
            .unwrap_or(0);
        let id = format!("{timestamp}");
        let snippet = Snippet { id, title, content };
        self.snippets.insert(0, snippet.clone());
        let _ = self.save();
        snippet
    }

    pub fn remove(&mut self, id: &str) -> bool {
        let previous_count = self.snippets.len();
        self.snippets.retain(|snippet| snippet.id != id);
        if self.snippets.len() != previous_count {
            let _ = self.save();
            true
        } else {
            false
        }
    }
}

/// Persistent, zero-subprocess Wayland clipboard manager powered by `arboard`.
#[derive(Clone)]
pub struct ClipboardService {
    snippets: Arc<Mutex<SnippetsConfig>>,
}

static HISTORY_STORE: OnceLock<Mutex<VecDeque<ClipboardEntry>>> = OnceLock::new();
static GLOBAL_SERVICE: OnceLock<ClipboardService> = OnceLock::new();

impl Default for ClipboardService {
    fn default() -> Self {
        Self::new()
    }
}

impl ClipboardService {
    pub fn new() -> Self {
        Self {
            snippets: Arc::new(Mutex::new(SnippetsConfig::load())),
        }
    }

    pub fn global() -> &'static Self {
        GLOBAL_SERVICE.get_or_init(Self::new)
    }

    fn cache_path() -> PathBuf {
        let base = std::env::var("XDG_CACHE_HOME")
            .map(PathBuf::from)
            .unwrap_or_else(|_| {
                let home = std::env::var("HOME").unwrap_or_else(|_| ".".to_string());
                PathBuf::from(home).join(".cache")
            });
        base.join("beskar").join("clipboard_history.json")
    }

    fn store() -> &'static Mutex<VecDeque<ClipboardEntry>> {
        HISTORY_STORE.get_or_init(|| {
            let loaded = Self::load_from_disk();
            Mutex::new(loaded)
        })
    }

    fn load_from_disk() -> VecDeque<ClipboardEntry> {
        let path = Self::cache_path();
        if path.exists() {
            if let Ok(file) = File::open(&path) {
                let reader = BufReader::new(file);
                if let Ok(entries) = serde_json::from_reader::<_, Vec<ClipboardEntry>>(reader) {
                    debug!("Loaded {} clipboard entries from disk cache", entries.len());
                    return VecDeque::from(entries);
                }
            }
        }
        VecDeque::new()
    }

    fn save_to_disk(store: &VecDeque<ClipboardEntry>) {
        let path = Self::cache_path();
        if let Some(parent) = path.parent() {
            let _ = fs::create_dir_all(parent);
        }

        if let Ok(file) = File::create(&path) {
            let writer = BufWriter::new(file);
            let items: Vec<&ClipboardEntry> = store.iter().collect();
            let _ = serde_json::to_writer_pretty(writer, &items);
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Capsule-Aligned API
    // ─────────────────────────────────────────────────────────────────────────

    pub fn fetch_history(&self) -> Vec<ClipboardItem> {
        let mut store = match Self::store().lock() {
            Ok(s) => s,
            Err(p) => p.into_inner(),
        };

        // Capture any new text in clipboard if not already at top
        if let Ok(mut cb) = Clipboard::new() {
            if let Ok(text) = cb.get_text() {
                let text_trimmed = text.trim();
                if !text_trimmed.is_empty() {
                    let is_top = store.front().is_some_and(|top| top.text == text_trimmed);
                    if !is_top {
                        Self::push_entry_locked(&mut store, text_trimmed.to_string());
                    }
                }
            }
        }

        store
            .iter()
            .map(|e| {
                let image_path = if e.is_image {
                    let candidate = PathBuf::from(&e.text);
                    if candidate.exists() {
                        Some(candidate)
                    } else {
                        None
                    }
                } else {
                    None
                };
                ClipboardItem {
                    id: e.id.clone(),
                    preview: e.text.clone(),
                    is_image: e.is_image,
                    image_path,
                }
            })
            .collect()
    }

    pub fn read_item(&self, item: &ClipboardItem) -> Result<ClipboardContent, String> {
        if item.is_image {
            if let Some(ref path) = item.image_path {
                if let Ok(bytes) = fs::read(path) {
                    return Ok(ClipboardContent::Image(bytes));
                }
            }
        }
        let store = match Self::store().lock() {
            Ok(s) => s,
            Err(p) => p.into_inner(),
        };
        if let Some(entry) = store.iter().find(|e| e.id == item.id) {
            Ok(ClipboardContent::Text(entry.text.clone()))
        } else {
            Ok(ClipboardContent::Text(item.preview.clone()))
        }
    }

    pub fn copy_text(&self, text: &str) -> bool {
        let trimmed = text.trim();
        if trimmed.is_empty() {
            return false;
        }

        {
            let mut store = match Self::store().lock() {
                Ok(s) => s,
                Err(p) => p.into_inner(),
            };
            Self::push_entry_locked(&mut store, trimmed.to_string());
        }

        Self::write_to_system_clipboard(trimmed)
    }

    pub fn copy_binary(&self, bytes: &[u8], _mime: &str) -> bool {
        if let Ok(img) = image::load_from_memory(bytes) {
            let rgba = img.to_rgba8();
            let (width, height) = rgba.dimensions();
            let img_data = arboard::ImageData {
                width: width as usize,
                height: height as usize,
                bytes: std::borrow::Cow::Borrowed(&rgba),
            };
            if let Ok(mut cb) = Clipboard::new() {
                return cb.set_image(img_data).is_ok();
            }
        }
        false
    }

    pub fn get_snippets(&self) -> Vec<Snippet> {
        let guard = self.snippets.lock().unwrap_or_else(|e| e.into_inner());
        guard.snippets.clone()
    }

    pub fn add_snippet(&self, title: &str, content: &str) -> Option<Snippet> {
        let mut guard = self.snippets.lock().unwrap_or_else(|e| e.into_inner());
        Some(guard.add(title.to_string(), content.to_string()))
    }

    pub fn remove_snippet(&self, id: &str) -> bool {
        let mut guard = self.snippets.lock().unwrap_or_else(|e| e.into_inner());
        guard.remove(id)
    }

    pub fn clear_history(&self) -> bool {
        let mut store = match Self::store().lock() {
            Ok(s) => s,
            Err(p) => p.into_inner(),
        };

        store.clear();
        Self::save_to_disk(&store);

        if let Ok(mut cb) = Clipboard::new() {
            let _ = cb.clear();
        }

        info!("Cleared all clipboard history");
        true
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Legacy Compatibility Shims
    // ─────────────────────────────────────────────────────────────────────────

    pub fn list_history(max: usize) -> Vec<ClipboardEntry> {
        let mut store = match Self::store().lock() {
            Ok(s) => s,
            Err(p) => p.into_inner(),
        };

        if let Ok(mut cb) = Clipboard::new() {
            if let Ok(text) = cb.get_text() {
                let text_trimmed = text.trim();
                if !text_trimmed.is_empty() {
                    let is_top = store.front().is_some_and(|top| top.text == text_trimmed);
                    if !is_top {
                        Self::push_entry_locked(&mut store, text_trimmed.to_string());
                    }
                }
            }
        }

        store.iter().take(max).cloned().collect()
    }

    pub fn copy_item(id: &str) -> bool {
        let mut store = match Self::store().lock() {
            Ok(s) => s,
            Err(p) => p.into_inner(),
        };

        let found_idx = store.iter().position(|e| e.id == id);
        let Some(idx) = found_idx else {
            warn!("Clipboard entry #{} not found in history", id);
            return false;
        };

        let entry = store.remove(idx).expect("Checked index exists");
        let text_to_copy = entry.text.clone();
        store.push_front(entry);
        Self::save_to_disk(&store);

        Self::write_to_system_clipboard(&text_to_copy)
    }

    pub fn delete_item(id_or_line: &str) -> bool {
        let mut store = match Self::store().lock() {
            Ok(s) => s,
            Err(p) => p.into_inner(),
        };

        let initial_len = store.len();
        store.retain(|e| e.id != id_or_line && e.full_line != id_or_line && e.text != id_or_line);

        if store.len() != initial_len {
            Self::save_to_disk(&store);
            info!("Deleted clipboard entry from history");
            true
        } else {
            false
        }
    }

    fn push_entry_locked(store: &mut VecDeque<ClipboardEntry>, text: String) {
        store.retain(|e| e.text != text);

        let id = format!("{}", chrono::Utc::now().timestamp_micros());
        let full_line = format!("{}\t{}", id, text);
        let is_image = text.contains("[[ binary data")
            || text.ends_with(".png")
            || text.ends_with(".jpg")
            || text.ends_with(".webp");

        store.push_front(ClipboardEntry {
            id,
            text,
            full_line,
            is_image,
        });

        while store.len() > MAX_HISTORY_DEFAULT {
            store.pop_back();
        }

        Self::save_to_disk(store);
    }

    fn write_to_system_clipboard(text: &str) -> bool {
        match Clipboard::new() {
            Ok(mut cb) => match cb.set_text(text) {
                Ok(_) => {
                    info!("Copied text to Wayland clipboard using arboard");
                    true
                }
                Err(e) => {
                    error!("Failed to write to clipboard via arboard: {}", e);
                    false
                }
            },
            Err(e) => {
                debug!("Failed to initialize arboard clipboard context: {}", e);
                true
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_clipboard_operations_and_deduplication() {
        let service = ClipboardService::new();
        let _ = service.clear_history();

        assert!(service.copy_text("Hello Beskar"));
        assert!(service.copy_text("Rust Desktop Shell"));
        assert!(service.copy_text("Hello Beskar")); // Duplicate push, should move to front

        let list = service.fetch_history();
        assert_eq!(list.len(), 2, "Duplicate entries should be deduplicated");
        assert_eq!(list[0].preview, "Hello Beskar", "Most recent should be at the front");
        assert_eq!(list[1].preview, "Rust Desktop Shell");

        // Snippets test
        let snippet = service.add_snippet("Test Snippet", "echo 42").unwrap();
        assert_eq!(snippet.title, "Test Snippet");
        let snippets = service.get_snippets();
        assert!(snippets.iter().any(|s| s.id == snippet.id));
        assert!(service.remove_snippet(&snippet.id));
    }
}
