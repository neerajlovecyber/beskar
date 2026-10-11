pub use beskar_core::ClipboardEntry;
use std::io::Write;

use std::process::{Command, Stdio};
use tracing::{debug, error, info};

pub struct ClipboardService;


impl ClipboardService {
    /// Read clipboard history using `cliphist list`
    pub fn list_history(max: usize) -> Vec<ClipboardEntry> {
        let output = match Command::new("cliphist").arg("list").output() {
            Ok(out) => out,
            Err(e) => {
                debug!("Failed to query cliphist: {}", e);
                return Vec::new();
            }
        };

        if !output.status.success() {
            return Vec::new();
        }

        let raw = String::from_utf8_lossy(&output.stdout);
        let mut entries = Vec::new();

        for line in raw.lines().take(max) {
            let line = line.trim();
            if line.is_empty() {
                continue;
            }

            if let Some((id_str, content)) = line.split_once('\t') {
                let id = id_str.trim().to_string();
                let text = content.trim().to_string();
                let is_image = text.contains("[[ binary data") || text.ends_with(".png") || text.ends_with(".jpg");

                entries.push(ClipboardEntry {
                    id,
                    text,
                    full_line: line.to_string(),
                    is_image,
                });
            }
        }

        entries
    }

    /// Decode the specified item and pipe directly into `wl-copy`
    pub fn copy_item(id: &str) -> bool {
        let decode_child = Command::new("cliphist")
            .args(["decode", id])
            .stdout(Stdio::piped())
            .spawn();

        match decode_child {
            Ok(decode) => {
                if let Some(stdout) = decode.stdout {
                    match Command::new("wl-copy").stdin(stdout).spawn() {
                        Ok(mut wl) => {
                            let _ = wl.wait();
                            info!("Copied clipboard entry #{} to active wayland clipboard", id);
                            true
                        }
                        Err(e) => {
                            error!("Failed to run wl-copy: {}", e);
                            false
                        }
                    }
                } else {
                    false
                }
            }
            Err(e) => {
                error!("Failed to decode cliphist item {}: {}", id, e);
                false
            }
        }
    }

    /// Delete a single entry from `cliphist`
    pub fn delete_item(full_line: &str) -> bool {
        match Command::new("cliphist")
            .arg("delete")
            .stdin(Stdio::piped())
            .spawn()
        {
            Ok(mut child) => {
                if let Some(mut stdin) = child.stdin.take() {
                    let _ = stdin.write_all(full_line.as_bytes());
                    let _ = stdin.write_all(b"\n");
                }
                let _ = child.wait();
                info!("Deleted clipboard entry from history");
                true
            }
            Err(e) => {
                error!("Failed to delete from cliphist: {}", e);
                false
            }
        }
    }

    /// Clear all history using `cliphist wipe`
    pub fn clear_history() -> bool {
        match Command::new("cliphist").arg("wipe").status() {
            Ok(status) => status.success(),
            Err(e) => {
                error!("Failed to wipe cliphist: {}", e);
                false
            }
        }
    }
}
