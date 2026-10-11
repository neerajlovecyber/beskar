use std::io::BufRead;
use std::path::PathBuf;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use tokio::sync::broadcast;
use tracing::{info, warn};

pub struct CavaService {
    sender: broadcast::Sender<Vec<u8>>,
    is_running: Arc<AtomicBool>,
}

impl Default for CavaService {
    fn default() -> Self {
        Self::new()
    }
}

impl CavaService {
    pub fn new() -> Self {
        let (sender, _) = broadcast::channel(32);
        Self {
            sender,
            is_running: Arc::new(AtomicBool::new(false)),
        }
    }

    pub fn subscribe(&self) -> broadcast::Receiver<Vec<u8>> {
        self.sender.subscribe()
    }

    pub fn set_active(&self, active: bool) {
        let prev = self.is_running.swap(active, Ordering::SeqCst);
        if active && !prev {
            let tx = self.sender.clone();
            let is_running = self.is_running.clone();
            tokio::spawn(async move {
                run_cava_loop(tx, is_running).await;
            });
        }
    }
}

fn config_path() -> PathBuf {
    let base = std::env::var("XDG_CONFIG_HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|_| {
            let home = std::env::var("HOME").unwrap_or_else(|_| ".".to_string());
            PathBuf::from(home).join(".config")
        });
    let p = base.join("beskar");
    let _ = std::fs::create_dir_all(&p);
    p.join("cava.conf")
}

fn ensure_cava_config() -> PathBuf {
    let path = config_path();
    if !path.exists() {
        let conf = r#"[general]
bars = 36
framerate = 60

[smoothing]
monstercat = 1
noise_reduction = 65
gravity = 100

[output]
method = raw
raw_target = /dev/stdout
data_format = ascii
ascii_max_range = 100
bar_delimiter = 59
"#;
        let _ = std::fs::write(&path, conf);
    }
    path
}

async fn run_cava_loop(tx: broadcast::Sender<Vec<u8>>, is_running: Arc<AtomicBool>) {
    let conf = ensure_cava_config();
    let cava_available = std::process::Command::new("which")
        .arg("cava")
        .output()
        .map(|o| o.status.success())
        .unwrap_or(false);

    if cava_available {
        info!("Spawning CAVA spectrum visualizer daemon...");
        let tx_clone = tx.clone();
        let running_clone = is_running.clone();
        let res = tokio::task::spawn_blocking(move || {
            let mut child = match std::process::Command::new("cava")
                .arg("-p")
                .arg(conf)
                .stdout(std::process::Stdio::piped())
                .stderr(std::process::Stdio::null())
                .spawn()
            {
                Ok(c) => c,
                Err(e) => {
                    warn!("Failed to spawn cava daemon: {}", e);
                    return false;
                }
            };

            if let Some(stdout) = child.stdout.take() {
                let reader = std::io::BufReader::new(stdout);
                for line in reader.lines() {
                    if !running_clone.load(Ordering::SeqCst) {
                        break;
                    }
                    if let Ok(l) = line {
                        let trimmed = l.trim();
                        if trimmed.is_empty() {
                            continue;
                        }
                        let parts = trimmed.split(';');
                        let mut vals = Vec::with_capacity(36);
                        for p in parts.take(36) {
                            let v = p.parse::<u8>().unwrap_or(0);
                            vals.push(v);
                        }
                        if vals.len() < 36 {
                            vals.resize(36, 0);
                        }
                        let _ = tx_clone.send(vals);
                    } else {
                        break;
                    }
                }
                let _ = child.kill();
            }
            true
        })
        .await;

        if res.is_err() || matches!(res, Ok(false)) {
            run_procedural_fallback(tx, is_running).await;
        }
    } else {
        run_procedural_fallback(tx, is_running).await;
    }
}

/// Fallback procedural harmonic frequency synthesis when cava binary is not installed
async fn run_procedural_fallback(tx: broadcast::Sender<Vec<u8>>, is_running: Arc<AtomicBool>) {
    let mut frame = 0u64;
    let mut interval = tokio::time::interval(std::time::Duration::from_millis(16)); // 60 FPS
    while is_running.load(Ordering::SeqCst) {
        interval.tick().await;
        frame += 1;
        let phase = (frame as f32) * 0.12;
        let mut bars = Vec::with_capacity(36);
        for i in 0..36 {
            let harmonic1 = ((i as f32 * 0.28 + phase).sin() + 1.0) * 0.5;
            let harmonic2 = ((i as f32 * 0.65 - phase * 1.4).sin() + 1.0) * 0.5;
            let bass_boost = if i < 10 { 1.25 } else { 0.75 };
            let raw = (harmonic1 * 0.65 + harmonic2 * 0.35) * bass_boost * 90.0;
            let val = raw.clamp(8.0, 100.0) as u8;
            bars.push(val);
        }
        let _ = tx.send(bars);
    }
}
