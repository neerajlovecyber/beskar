use std::sync::Arc;

use beskar_core::models::WindowInfo;
use beskar_core::traits::CompositorBackend;
use beskar_services::{AudioService, MprisService};
use beskar_ui::BarActions;

use super::view::BarAction;

/// Construct all interactive callbacks for the BeskarBar.
pub fn build_bar_actions(
    compositor: Arc<dyn CompositorBackend>,
    action_tx: tokio::sync::mpsc::UnboundedSender<BarAction>,
    active_window: Option<&WindowInfo>,
) -> BarActions {
    let comp = compositor.clone();
    let on_select_ws = Arc::new(move |id: u64| {
        let c = comp.clone();
        tokio::spawn(async move {
            let _ = c.focus_workspace(id).await;
        });
    });

    let comp_scroll = compositor.clone();
    let on_scroll_ws = Arc::new(move |dir: i32| {
        let c = comp_scroll.clone();
        tokio::spawn(async move {
            let _ = c.scroll_workspace(dir).await;
        });
    });

    let on_play_pause = Arc::new(|| {
        MprisService::play_pause();
    });

    let on_volume_click = Arc::new(|| {
        AudioService::toggle_mute();
    });

    let on_volume_scroll = Arc::new(|delta: i32| {
        beskar_services::AudioService::set_volume(delta);
        beskar_services::SoundService::play_volume_change();
    });

    let atx_cc = action_tx.clone();
    let on_control_center_click = Arc::new(move || {
        let _ = atx_cc.send(BarAction::ToggleControlCenter);
    });

    let atx_notif = action_tx.clone();
    let on_clock_click = Arc::new(move || {
        let _ = atx_notif.send(BarAction::ToggleNotificationCenter);
    });

    let atx_music = action_tx.clone();
    let on_music_click = Arc::new(move || {
        let _ = atx_music.send(BarAction::ToggleMusic);
    });

    let atx_dash = action_tx.clone();
    let on_dashboard_click = Arc::new(move || {
        let _ = atx_dash.send(BarAction::ToggleDashboard);
    });

    let atx_cap = action_tx.clone();
    let on_capture_click = Arc::new(move || {
        let _ = atx_cap.send(BarAction::ToggleScreenCapture);
    });

    let atx_wall = action_tx.clone();
    let on_wallpaper_click = Arc::new(move || {
        let _ = atx_wall.send(BarAction::ToggleWallpaperSelector);
    });

    let atx_l = action_tx.clone();
    let on_launcher_click = Arc::new(move || {
        let _ = atx_l.send(BarAction::ToggleLauncher);
    });

    let atx_p = action_tx.clone();
    let on_power_click = Arc::new(move || {
        let _ = atx_p.send(BarAction::TogglePowerMenu);
    });

    let on_tray_click = Arc::new(|id: String| {
        tokio::task::spawn_blocking(move || {
            let _ = beskar_services::tray::command(
                "tray.activate",
                &[beskar_services::sysvalue::SysValue::Text(id)],
            );
        });
    });

    let on_tray_menu = Arc::new(|id: String| {
        tokio::task::spawn_blocking(move || {
            let _ = beskar_services::tray::command(
                "tray.context",
                &[beskar_services::sysvalue::SysValue::Text(id)],
            );
        });
    });

    let comp_close = compositor;
    let active_win_id = active_window.map(|w| w.id);
    let on_window_close = Arc::new(move || {
        if let Some(id) = active_win_id {
            let c = comp_close.clone();
            tokio::spawn(async move {
                let _ = c.close_window(id).await;
            });
        } else {
            tokio::task::spawn_blocking(|| {
                let _ = std::process::Command::new("niri")
                    .args(["msg", "action", "close-window"])
                    .spawn();
            });
        }
    });

    let on_window_click = Arc::new(|| {
        tokio::task::spawn_blocking(|| {
            let _ = std::process::Command::new("niri")
                .args(["msg", "action", "fullscreen-window"])
                .spawn();
        });
    });

    BarActions {
        on_select_ws: Some(on_select_ws),
        on_scroll_ws: Some(on_scroll_ws),
        on_play_pause: Some(on_play_pause),
        on_volume_click: Some(on_volume_click),
        on_volume_scroll: Some(on_volume_scroll),
        on_control_center_click: Some(on_control_center_click),
        on_power_click: Some(on_power_click),
        on_launcher_click: Some(on_launcher_click),
        on_clock_click: Some(on_clock_click),
        on_dashboard_click: Some(on_dashboard_click),
        on_music_click: Some(on_music_click),
        on_capture_click: Some(on_capture_click),
        on_wallpaper_click: Some(on_wallpaper_click),
        on_tray_click: Some(on_tray_click),
        on_tray_menu: Some(on_tray_menu),
        on_window_click: Some(on_window_click),
        on_window_close: Some(on_window_close),
    }
}
