use std::sync::Arc;

use beskar_core::models::{NotificationItem, WindowInfo, WorkspaceInfo};
use beskar_core::traits::CompositorBackend;
use beskar_services::{AudioService, BatteryService, MprisService, VitalsService};
use beskar_ui::BeskarBar;
use chrono::Local;
use gpui_kit::*;

use crate::modules;

#[allow(dead_code, clippy::enum_variant_names)]
pub enum BarAction {
    ToggleControlCenter,
    ToggleLauncher,
    TogglePowerMenu,
    ToggleSettings,
    ToggleLockScreen,
    ToggleClipboard,
    ToggleDashboard,
    ToggleMusic,
    ToggleNotificationCenter,
    ToggleScreenCapture,
    ToggleWallpaperSelector,
}

pub struct DesktopBarView {
    workspaces: Vec<WorkspaceInfo>,
    active_ws: u64,
    active_window: Option<WindowInfo>,
    time_str: String,
    date_str: String,
    battery_percent: u8,
    is_charging: bool,
    volume_percent: u8,
    is_muted: bool,
    cpu_percent: Option<f32>,
    ram_percent: Option<f32>,
    media: Option<(String, String, bool)>,
    cava_bands: Option<[u8; 4]>,
    island_spring: beskar_ui::SpringValue,
    tray_items: Vec<beskar_core::models::TrayItem>,
    notifications: Vec<NotificationItem>,
    action_tx: tokio::sync::mpsc::UnboundedSender<BarAction>,
    compositor: Arc<dyn CompositorBackend>,
    is_convex: bool,
    config: beskar_core::config::ShellConfig,
}

impl DesktopBarView {
    pub fn new(
        workspaces: Vec<WorkspaceInfo>,
        active_ws: u64,
        active_window: Option<WindowInfo>,
        is_convex: bool,
        compositor: Arc<dyn CompositorBackend>,
        cx: &mut Context<Self>,
    ) -> Self {
        let initial_cfg = beskar_core::config::ShellConfig::load();
        let now = Local::now();
        let time_str = now.format("%-I:%M %p").to_string();
        let date_str = now.format("%a %b %-d").to_string();

        let battery_svc = BatteryService::new();
        let bat = battery_svc.read_state();
        let aud = AudioService::read_state();
        let med = MprisService::read_state();
        let vitals = VitalsService::global().snapshot();

        let initial_media = med.map(|m| {
            (
                m.title.unwrap_or_default(),
                m.artist.unwrap_or_default(),
                m.is_playing,
            )
        });

        // 1. Live Clock Timer: updates every 1 second
        cx.spawn(async move |this, cx| {
            loop {
                let _ = cx
                    .background_executor()
                    .timer(std::time::Duration::from_secs(1))
                    .await;
                let now = Local::now();
                let time = now.format("%-I:%M %p").to_string();
                let date = now.format("%a %b %-d").to_string();
                let res = this.update(cx, |this, cx| {
                    this.time_str = time;
                    this.date_str = date;
                    cx.notify();
                });
                if res.is_err() {
                    break;
                }
            }
        })
        .detach();

        let has_initial_media = initial_media.is_some();
        let initial_target_w = if has_initial_media { 320.0 } else { 180.0 };
        let island_spring = beskar_ui::SpringValue::new(initial_target_w, beskar_ui::SpringConfig::spatial());

        // 2. Reactive SystemHub: instant updates for audio, battery, and media
        let hub = Arc::new(beskar_services::SystemHub::new());
        let hub_clone = hub.clone();
        tokio::spawn(async move {
            let _ = hub_clone.start().await;
        });

        let mut sys_rx = hub.subscribe();
        cx.spawn(async move |this, cx| {
            while let Ok(snap) = sys_rx.recv().await {
                let media = snap.media.map(|m| {
                    (
                        m.title.unwrap_or_default(),
                        m.artist.unwrap_or_default(),
                        m.is_playing,
                    )
                });

                let active_notif = snap.notifications.first().map(|n| (n.summary.clone(), n.body.clone()));
                let target_width = if active_notif.is_some() {
                    360.0
                } else if media.is_some() {
                    320.0
                } else {
                    180.0
                };

                let res = this.update(cx, |this, cx| {
                    this.battery_percent = snap.battery.percentage.round() as u8;
                    this.is_charging = snap.battery.is_charging;
                    this.volume_percent = (snap.audio.volume * 100.0).round() as u8;
                    this.is_muted = snap.audio.is_muted;
                    this.media = media;
                    this.tray_items = snap.tray;
                    this.notifications = snap.notifications.clone();
                    this.island_spring.set_target(target_width);
                    modules::sync_notification_toasts(snap.notifications, cx);
                    cx.notify();
                });
                if res.is_err() {
                    break;
                }
            }
        })
        .detach();

        // 3. System Vitals Stream (Real-time CPU and Memory Telemetry)
        let mut vitals_rx = VitalsService::global().subscribe();
        cx.spawn(async move |this, cx| {
            while vitals_rx.changed().await.is_ok() {
                let snap = vitals_rx.borrow().clone();
                let cpu = snap.cpu.global_usage_percent;
                let ram = snap.memory.usage_percent;
                let res = this.update(cx, |this, cx| {
                    this.cpu_percent = Some(cpu);
                    this.ram_percent = Some(ram);
                    cx.notify();
                });
                if res.is_err() {
                    break;
                }
            }
        })
        .detach();

        // 4. Adaptive Physics Frame Loop for fluid Island morphing
        cx.spawn(async move |this, cx| {
            loop {
                let mut is_animating = false;
                let res = this.update(cx, |this, cx| {
                    if !this.island_spring.is_settled() {
                        this.island_spring.step(1.0 / 60.0);
                        is_animating = true;
                        cx.notify();
                    }
                });
                if res.is_err() {
                    break;
                }

                let sleep_duration = if is_animating {
                    std::time::Duration::from_millis(16) // 60 FPS during motion
                } else {
                    std::time::Duration::from_millis(300) // Deep idle low-power sleep when settled
                };

                let _ = cx.background_executor().timer(sleep_duration).await;
            }
        })
        .detach();

        // 5. UI Actions Channel (e.g. Control Center toggle)
        let (action_tx, mut action_rx) = tokio::sync::mpsc::unbounded_channel::<BarAction>();
        cx.spawn(async move |this, cx| {
            while let Some(action) = action_rx.recv().await {
                let res = this.update(cx, |_this, cx| {
                    match action {
                        BarAction::ToggleControlCenter => {
                            modules::toggle_control_center(cx);
                        }
                        BarAction::ToggleLauncher => {
                            modules::toggle_launcher(cx);
                        }
                        BarAction::TogglePowerMenu => {
                            modules::toggle_power_menu(cx);
                        }
                        BarAction::ToggleSettings => {
                            modules::toggle_settings(cx);
                        }
                        BarAction::ToggleLockScreen => {
                            modules::toggle_lockscreen(cx);
                        }
                        BarAction::ToggleClipboard => {
                            modules::toggle_clipboard(cx);
                        }
                        BarAction::ToggleDashboard => {
                            modules::toggle_dashboard(cx);
                        }
                        BarAction::ToggleMusic => {
                            modules::toggle_music(cx);
                        }
                        BarAction::ToggleNotificationCenter => {
                            modules::toggle_notification_center(cx);
                        }
                        BarAction::ToggleScreenCapture => {
                            modules::toggle_screencapture(cx);
                        }
                        BarAction::ToggleWallpaperSelector => {
                            modules::toggle_wallpaper_selector(cx);
                        }
                    }
                });
                if res.is_err() {
                    break;
                }
            }
        })
        .detach();

        // 6. CAVA spectrum audio equalizer loop (4 bands for Dynamic Center island)
        cx.spawn(async move |this, cx| {
            let mut tick: u32 = 0;
            loop {
                let mut is_playing = false;
                let _ = this.update(cx, |this, _| {
                    is_playing = this.media.as_ref().is_some_and(|m| m.2);
                });

                let sleep_ms = if is_playing { 60 } else { 500 };
                let _ = cx
                    .background_executor()
                    .timer(std::time::Duration::from_millis(sleep_ms))
                    .await;

                if is_playing {
                    tick = tick.wrapping_add(1);
                }

                let res = this.update(cx, |this, cx| {
                    if this.media.as_ref().is_some_and(|m| m.2) {
                        let b0 = (((tick as f32 * 0.20).sin().abs() * 70.0) + 20.0) as u8;
                        let b1 = (((tick as f32 * 0.28).cos().abs() * 80.0) + 15.0) as u8;
                        let b2 = (((tick as f32 * 0.35).sin().abs() * 90.0) + 25.0) as u8;
                        let b3 = (((tick as f32 * 0.22).cos().abs() * 60.0) + 10.0) as u8;
                        this.cava_bands = Some([b0, b1, b2, b3]);
                        cx.notify();
                    } else if this.cava_bands.is_some() {
                        this.cava_bands = None;
                        cx.notify();
                    }
                });
                if res.is_err() {
                    break;
                }
            }
        })
        .detach();

        // 7. Systemd logind Session Lock Listener
        let atx_lock = action_tx.clone();
        let (lock_tx, mut lock_rx) = tokio::sync::mpsc::unbounded_channel::<()>();
        beskar_services::listen_logind_lock(lock_tx);
        cx.spawn(async move |_this, _cx| {
            while let Some(()) = lock_rx.recv().await {
                let _ = atx_lock.send(BarAction::ToggleLockScreen);
            }
        })
        .detach();

        // 8. Live Compositor Event Stream (256-event buffer with non-blocking dispatch)
        let (tx, mut rx) = tokio::sync::mpsc::channel(256);
        let comp_listener = compositor.clone();
        tokio::spawn(async move {
            let _ = comp_listener.start_listener(tx).await;
        });

        cx.spawn(async move |this, cx| {
            while let Some(event) = rx.recv().await {
                let res = this.update(cx, |this, cx| {
                    match event {
                        beskar_core::events::CompositorEvent::WorkspacesChanged(workspaces) => {
                            let active = workspaces
                                .iter()
                                .find(|w| w.is_focused || w.is_active)
                                .map(|w| w.id)
                                .unwrap_or(this.active_ws);
                            if this.workspaces != workspaces || this.active_ws != active {
                                this.active_ws = active;
                                this.workspaces = workspaces;
                                cx.notify();
                            }
                        }
                        beskar_core::events::CompositorEvent::WorkspaceFocused(id) => {
                            if this.active_ws != id {
                                this.active_ws = id;
                                cx.notify();
                            }
                        }
                        beskar_core::events::CompositorEvent::WindowFocused(active_win) => {
                            if this.active_window != active_win {
                                this.active_window = active_win;
                                cx.notify();
                            }
                        }
                        beskar_core::events::CompositorEvent::WindowsChanged(windows) => {
                            let focused = windows.iter().find(|w| w.is_focused).cloned();
                            if this.active_window != focused {
                                this.active_window = focused;
                                cx.notify();
                            }
                        }
                        _ => {}
                    }
                });
                if res.is_err() {
                    break;
                }
            }
        })
        .detach();

        // 9. Reactive Config Change Listener (Live Theme & Bar Style Switching)
        let mut cfg_rx = beskar_core::config::subscribe_config();
        cx.spawn(async move |this, cx| {
            while let Ok(cfg) = cfg_rx.recv().await {
                beskar_theme::ThemeEngine::set_preset(match cfg.theme_preset {
                    beskar_core::config::ThemePresetConfig::ObsidianGlass => beskar_theme::ThemePreset::Obsidian,
                    beskar_core::config::ThemePresetConfig::CatppuccinMocha => beskar_theme::ThemePreset::CatppuccinMocha,
                    beskar_core::config::ThemePresetConfig::GruvboxDark => beskar_theme::ThemePreset::GruvboxDark,
                    beskar_core::config::ThemePresetConfig::WallpaperAuto => beskar_theme::ThemePreset::Wallpaper,
                });

                let is_convex = cfg.bar_style == beskar_core::config::BarStyleConfig::Convex;
                let res = this.update(cx, |this, cx| {
                    this.is_convex = is_convex;
                    this.config = cfg;
                    cx.notify();
                });
                if res.is_err() {
                    break;
                }
            }
        })
        .detach();

        let initial_cpu = (vitals.cpu.global_usage_percent > 0.0).then_some(vitals.cpu.global_usage_percent);
        let initial_ram = (vitals.memory.usage_percent > 0.0).then_some(vitals.memory.usage_percent);

        Self {
            workspaces,
            active_ws,
            active_window,
            time_str,
            date_str,
            battery_percent: bat.percentage.round() as u8,
            is_charging: bat.is_charging,
            volume_percent: (aud.volume * 100.0).round() as u8,
            is_muted: aud.is_muted,
            cpu_percent: initial_cpu,
            ram_percent: initial_ram,
            media: initial_media,
            cava_bands: None,
            island_spring,
            tray_items: Vec::new(),
            notifications: Vec::new(),
            action_tx,
            compositor,
            is_convex,
            config: initial_cfg,
        }
    }
}

impl Render for DesktopBarView {
    fn render(&mut self, _: &mut Window, _: &mut Context<Self>) -> impl IntoElement {
        let actions = crate::bar::actions::build_bar_actions(
            self.compositor.clone(),
            self.action_tx.clone(),
            self.active_window.as_ref(),
        );

        let active_notif = self.notifications.first().map(|n| (n.summary.clone(), n.body.clone()));
        let state = beskar_ui::BarState {
            is_convex: self.is_convex,
            workspaces: self.workspaces.clone(),
            active_ws: Some(self.active_ws),
            active_window: self.active_window.clone(),
            time_str: self.time_str.clone(),
            date_str: Some(self.date_str.clone()),
            media: self.media.clone(),
            notification: active_notif,
            volume_percent: self.volume_percent,
            is_muted: self.is_muted,
            battery_percent: self.battery_percent,
            is_charging: self.is_charging,
            cpu_usage: self.cpu_percent,
            ram_usage: self.ram_percent,
            animated_center_width: Some(self.island_spring.current),
            cava_bands: self.cava_bands,
            tray_items: self.tray_items.clone(),
            modules_left: Some(self.config.modules_left.clone()),
            modules_center: Some(self.config.modules_center.clone()),
            modules_right: Some(self.config.modules_right.clone()),
        };

        div()
            .relative()
            .size_full()
            .flex()
            .items_center()
            .child(BeskarBar::from_state(state, actions))
    }
}
