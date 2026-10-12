use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex, OnceLock};
use std::time::{Duration, Instant};

use notify::{Config, Event, EventKind, RecommendedWatcher, RecursiveMode, Watcher};
use tokio::sync::broadcast;
use tracing::{debug, info, warn};

/// High-level event emitted when watched system or user files change.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum WatchEvent {
    /// The shell configuration file (~/.config/beskar/config.json) was modified or recreated.
    ConfigModified(PathBuf),
    /// A file within the wallpapers directory (~/Pictures/Wallpapers/) was added, changed, or deleted.
    WallpaperDirectoryChanged(PathBuf),
    /// A custom registered path was modified.
    Custom(PathBuf),
}

/// Asynchronous, debounced file watcher service backed by Linux inotify (`notify 8.0`).
///
/// Features:
/// - Watches `~/.config/beskar/` for dynamic theme, layout, and setting reloads.
/// - Watches `~/Pictures/Wallpapers/` for real-time wallpaper grid updates.
/// - Built-in 300ms debouncing to swallow text-editor atomic temporary file bursts.
/// - Distributes clean events over a non-blocking `tokio::sync::broadcast` stream.
pub struct FileWatcherService {
    tx: broadcast::Sender<WatchEvent>,
    watcher: Arc<Mutex<Option<RecommendedWatcher>>>,
}

static INSTANCE: OnceLock<FileWatcherService> = OnceLock::new();

impl FileWatcherService {
    /// Returns the global shared `FileWatcherService` instance.
    pub fn global() -> &'static Self {
        INSTANCE.get_or_init(|| {
            let (tx, _) = broadcast::channel(128);
            let tx_clone = tx.clone();
            let watcher_holder = Arc::new(Mutex::new(None));

            let service = Self {
                tx,
                watcher: watcher_holder.clone(),
            };

            // Initialize watcher in background runtime
            let _ = service.init_default_watches(tx_clone, watcher_holder);
            service
        })
    }

    /// Subscribe to live debounced file system events.
    pub fn subscribe(&self) -> broadcast::Receiver<WatchEvent> {
        self.tx.subscribe()
    }

    /// Register an additional directory or file path to watch.
    pub fn watch_path(&self, path: impl AsRef<Path>, recursive: bool) -> anyhow::Result<()> {
        let path = path.as_ref();
        if !path.exists() {
            let _ = std::fs::create_dir_all(path);
        }

        let mode = if recursive {
            RecursiveMode::Recursive
        } else {
            RecursiveMode::NonRecursive
        };

        if let Ok(mut lock) = self.watcher.lock() {
            if let Some(w) = lock.as_mut() {
                w.watch(path, mode)?;
                info!("Now watching path: {}", path.display());
            }
        }
        Ok(())
    }

    /// Standard configuration path: `~/.config/beskar/config.json`.
    pub fn config_path() -> PathBuf {
        let base = std::env::var("XDG_CONFIG_HOME")
            .map(PathBuf::from)
            .unwrap_or_else(|_| {
                let home = std::env::var("HOME").unwrap_or_else(|_| ".".to_string());
                PathBuf::from(home).join(".config")
            });
        base.join("beskar").join("config.json")
    }

    /// Standard wallpaper directory: `~/Pictures/Wallpapers`.
    pub fn wallpapers_dir() -> PathBuf {
        let home = std::env::var("HOME").unwrap_or_else(|_| ".".to_string());
        PathBuf::from(home).join("Pictures").join("Wallpapers")
    }

    fn init_default_watches(
        &self,
        tx: broadcast::Sender<WatchEvent>,
        watcher_holder: Arc<Mutex<Option<RecommendedWatcher>>>,
    ) -> anyhow::Result<()> {
        let (raw_tx, mut raw_rx) = tokio::sync::mpsc::channel::<PathBuf>(256);

        // 1. Set up synchronous RecommendedWatcher callback
        let mut watcher = RecommendedWatcher::new(
            move |res: notify::Result<Event>| match res {
                Ok(event) => {
                    if matches!(
                        event.kind,
                        EventKind::Create(_) | EventKind::Modify(_) | EventKind::Remove(_)
                    ) {
                        for path in event.paths {
                            let _ = raw_tx.blocking_send(path);
                        }
                    }
                }
                Err(e) => {
                    warn!("Inotify watcher error: {}", e);
                }
            },
            Config::default(),
        )?;

        // 2. Register default directories
        let config_file = Self::config_path();
        if let Some(parent) = config_file.parent() {
            let _ = std::fs::create_dir_all(parent);
            let _ = watcher.watch(parent, RecursiveMode::NonRecursive);
        }

        let wallpapers = Self::wallpapers_dir();
        let _ = std::fs::create_dir_all(&wallpapers);
        let _ = watcher.watch(&wallpapers, RecursiveMode::NonRecursive);

        // Store watcher handle
        if let Ok(mut lock) = watcher_holder.lock() {
            *lock = Some(watcher);
        }

        // 3. Spawn background debouncing loop on Tokio
        crate::tokio_runtime().spawn(async move {
            let mut pending: HashMap<PathBuf, Instant> = HashMap::new();
            let debounce_dur = Duration::from_millis(300);
            let mut ticker = tokio::time::interval(Duration::from_millis(100));

            let config_target = Self::config_path();
            let wallpapers_target = Self::wallpapers_dir();

            loop {
                tokio::select! {
                    Some(path) = raw_rx.recv() => {
                        pending.insert(path, Instant::now());
                    }
                    _ = ticker.tick() => {
                        let now = Instant::now();
                        let ready: Vec<PathBuf> = pending
                            .iter()
                            .filter(|(_, time)| now.duration_since(**time) >= debounce_dur)
                            .map(|(p, _)| p.clone())
                            .collect();

                        for path in ready {
                            pending.remove(&path);

                            // Categorize event
                            let event = if path == config_target || path.ends_with("config.json") {
                                WatchEvent::ConfigModified(path)
                            } else if path.starts_with(&wallpapers_target) {
                                WatchEvent::WallpaperDirectoryChanged(path)
                            } else {
                                WatchEvent::Custom(path)
                            };

                            debug!("Emitting debounced file watch event: {:?}", event);
                            let _ = tx.send(event);
                        }
                    }
                }
            }
        });

        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_config_path_structure() {
        let cfg = FileWatcherService::config_path();
        assert!(cfg.ends_with("beskar/config.json"));
    }

    #[test]
    fn test_wallpapers_dir_structure() {
        let wall = FileWatcherService::wallpapers_dir();
        assert!(wall.ends_with("Pictures/Wallpapers"));
    }
}
