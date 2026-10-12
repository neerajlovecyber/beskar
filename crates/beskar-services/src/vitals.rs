use std::sync::OnceLock;
use std::time::Duration;

use serde::{Deserialize, Serialize};
use sysinfo::{Components, CpuRefreshKind, Disks, MemoryRefreshKind, RefreshKind, System};
use tokio::sync::watch;
use tracing::{debug, info};

/// Snapshot of system hardware vitals captured asynchronously.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct VitalsSnapshot {
    pub cpu: CpuMetrics,
    pub memory: MemoryMetrics,
    pub swap: MemoryMetrics,
    pub disks: Vec<DiskMetrics>,
    pub thermals: Vec<ThermalMetrics>,
}

/// CPU hardware metrics.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct CpuMetrics {
    /// Overall CPU usage across all cores (0.0 .. 100.0).
    pub global_usage_percent: f32,
    /// Per-core utilization percentage (0.0 .. 100.0).
    pub core_usages: Vec<f32>,
    /// Number of physical CPU cores.
    pub physical_cores: usize,
    /// Frequency of the first core in MHz.
    pub frequency_mhz: u64,
}

/// Memory / RAM and Swap metrics.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct MemoryMetrics {
    pub used_bytes: u64,
    pub total_bytes: u64,
    pub available_bytes: u64,
    pub usage_percent: f32,
    pub formatted_used: String,
    pub formatted_total: String,
}

/// Storage metrics for a mounted filesystem.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct DiskMetrics {
    pub mount_point: String,
    pub file_system: String,
    pub total_bytes: u64,
    pub available_bytes: u64,
    pub used_bytes: u64,
    pub usage_percent: f32,
    pub formatted_used: String,
    pub formatted_total: String,
}

/// Hardware thermal sensor readings.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct ThermalMetrics {
    pub label: String,
    pub temp_celsius: f32,
    pub critical_celsius: Option<f32>,
}

/// Asynchronous hardware vitals service backed by `sysinfo`.
///
/// Runs a low-overhead background loop on `tokio_runtime()` and streams
/// immutable `VitalsSnapshot` structs via a `tokio::sync::watch` channel.
/// UI views can call `VitalsService::global().snapshot()` on every render frame
/// with zero IO, zero locking contention, and zero UI freezes.
pub struct VitalsService {
    rx: watch::Receiver<VitalsSnapshot>,
}

static INSTANCE: OnceLock<VitalsService> = OnceLock::new();

impl VitalsService {
    /// Returns the global shared `VitalsService` instance, starting the background worker on first access.
    pub fn global() -> &'static Self {
        INSTANCE.get_or_init(|| {
            let (tx, rx) = watch::channel(VitalsSnapshot::default());

            // Spawn background metrics collection task on the shared multi-thread Tokio runtime
            crate::tokio_runtime().spawn(async move {
                Self::worker_loop(tx).await;
            });

            Self { rx }
        })
    }

    /// Retrieve an instantaneous cached snapshot of current system vitals with 0ms latency.
    pub fn snapshot(&self) -> VitalsSnapshot {
        self.rx.borrow().clone()
    }

    /// Subscribe to live periodic vitals snapshot updates.
    pub fn subscribe(&self) -> watch::Receiver<VitalsSnapshot> {
        self.rx.clone()
    }

    /// Background worker loop periodically polling `sysinfo` APIs.
    async fn worker_loop(tx: watch::Sender<VitalsSnapshot>) {
        info!("System vitals background monitoring engine started");

        let mut sys = System::new_with_specifics(
            RefreshKind::nothing()
                .with_cpu(CpuRefreshKind::everything())
                .with_memory(MemoryRefreshKind::everything()),
        );

        let mut disks = Disks::new();
        let mut components = Components::new();

        // Initial CPU baseline reading
        sys.refresh_cpu_all();
        tokio::time::sleep(sysinfo::MINIMUM_CPU_UPDATE_INTERVAL).await;

        let mut ticker = tokio::time::interval(Duration::from_millis(1500));
        ticker.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Skip);

        loop {
            ticker.tick().await;

            // 1. Refresh System, Disks, and Components
            sys.refresh_cpu_all();
            sys.refresh_memory();
            disks.refresh(true);
            components.refresh(true);

            // 2. Gather CPU Metrics
            let global_usage_percent = sys.global_cpu_usage();
            let core_usages: Vec<f32> = sys.cpus().iter().map(|c| c.cpu_usage()).collect();
            let physical_cores = sys.physical_core_count().unwrap_or_else(|| sys.cpus().len());
            let frequency_mhz = sys.cpus().first().map(|c| c.frequency()).unwrap_or(0);

            let cpu = CpuMetrics {
                global_usage_percent,
                core_usages,
                physical_cores,
                frequency_mhz,
            };

            // 3. Gather Memory Metrics
            let total_mem = sys.total_memory();
            let used_mem = sys.used_memory();
            let avail_mem = sys.available_memory();
            let mem_percent = if total_mem > 0 {
                (used_mem as f32 / total_mem as f32) * 100.0
            } else {
                0.0
            };

            let memory = MemoryMetrics {
                used_bytes: used_mem,
                total_bytes: total_mem,
                available_bytes: avail_mem,
                usage_percent: mem_percent,
                formatted_used: format_bytes(used_mem),
                formatted_total: format_bytes(total_mem),
            };

            // 4. Gather Swap Metrics
            let total_swap = sys.total_swap();
            let used_swap = sys.used_swap();
            let swap_percent = if total_swap > 0 {
                (used_swap as f32 / total_swap as f32) * 100.0
            } else {
                0.0
            };

            let swap = MemoryMetrics {
                used_bytes: used_swap,
                total_bytes: total_swap,
                available_bytes: total_swap.saturating_sub(used_swap),
                usage_percent: swap_percent,
                formatted_used: format_bytes(used_swap),
                formatted_total: format_bytes(total_swap),
            };

            // 5. Gather Disk Metrics (Root and primary physical mounts)
            let mut disk_metrics = Vec::new();
            for disk in disks.list() {
                let mount = disk.mount_point().to_string_lossy().to_string();
                // Filter out pseudo and dev filesystems, keep root and physical mounts
                if mount.starts_with("/run") || mount.starts_with("/dev") || mount.starts_with("/proc") || mount.starts_with("/sys") {
                    continue;
                }
                let total = disk.total_space();
                let available = disk.available_space();
                let used = total.saturating_sub(available);
                let percent = if total > 0 {
                    (used as f32 / total as f32) * 100.0
                } else {
                    0.0
                };

                disk_metrics.push(DiskMetrics {
                    mount_point: mount,
                    file_system: disk.file_system().to_string_lossy().to_string(),
                    total_bytes: total,
                    available_bytes: available,
                    used_bytes: used,
                    usage_percent: percent,
                    formatted_used: format_bytes(used),
                    formatted_total: format_bytes(total),
                });
            }

            // 6. Gather Thermal Metrics
            let mut thermals = Vec::new();
            for comp in components.list() {
                let label = comp.label().to_string();
                if let Some(temp) = comp.temperature() {
                    if temp > 0.0 {
                        thermals.push(ThermalMetrics {
                            label,
                            temp_celsius: temp,
                            critical_celsius: comp.critical(),
                        });
                    }
                }
            }

            let snapshot = VitalsSnapshot {
                cpu,
                memory,
                swap,
                disks: disk_metrics,
                thermals,
            };

            let _ = tx.send(snapshot);
            debug!("Vitals snapshot updated: CPU {:.1}%, RAM {:.1}%", global_usage_percent, mem_percent);
        }
    }
}

/// Helper function to format raw byte counts into human-readable units (KB, MB, GB, TB).
pub fn format_bytes(bytes: u64) -> String {
    const KB: f64 = 1024.0;
    const MB: f64 = KB * 1024.0;
    const GB: f64 = MB * 1024.0;
    const TB: f64 = GB * 1024.0;

    let b = bytes as f64;
    if b >= TB {
        format!("{:.1} TB", b / TB)
    } else if b >= GB {
        format!("{:.1} GB", b / GB)
    } else if b >= MB {
        format!("{:.1} MB", b / MB)
    } else if b >= KB {
        format!("{:.0} KB", b / KB)
    } else {
        format!("{} B", bytes)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_format_bytes() {
        assert_eq!(format_bytes(500), "500 B");
        assert_eq!(format_bytes(1024), "1 KB");
        assert_eq!(format_bytes(1024 * 1024 * 512), "512.0 MB");
        assert_eq!(format_bytes(1024 * 1024 * 1024 * 16), "16.0 GB");
    }

    #[test]
    fn test_vitals_snapshot_collection() {
        let mut sys = System::new_with_specifics(
            RefreshKind::nothing()
                .with_cpu(CpuRefreshKind::everything())
                .with_memory(MemoryRefreshKind::everything()),
        );
        sys.refresh_cpu_all();
        sys.refresh_memory();

        assert!(sys.total_memory() > 0, "System must report non-zero total memory");
        assert!(!sys.cpus().is_empty(), "System must report at least 1 CPU core");
    }
}
