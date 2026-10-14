use std::sync::Arc;

use beskar_core::models::WindowInfo;
use beskar_core::traits::CompositorBackend;
use beskar_services::{AudioService, MprisService};
use beskar_ui::BarActions;
use gpui_kit::{App, Window};

/// Construct all interactive callbacks for the BeskarBar.
pub fn build_bar_actions(
    compositor: Arc<dyn CompositorBackend>,
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

    let on_control_center_click = Arc::new(|_: &mut Window, cx: &mut App| {
        crate::modules::toggle_control_center(cx);
    });

    let on_clock_click = Arc::new(|_: &mut Window, cx: &mut App| {
        crate::modules::toggle_notification_center(cx);
    });

    let on_music_click = Arc::new(|_: &mut Window, cx: &mut App| {
        crate::modules::toggle_music(cx);
    });

    let on_dashboard_click = Arc::new(|_: &mut Window, cx: &mut App| {
        crate::modules::toggle_dashboard(cx);
    });

    let on_capture_click = Arc::new(|_: &mut Window, cx: &mut App| {
        crate::modules::toggle_screencapture(cx);
    });

    let on_wallpaper_click = Arc::new(|_: &mut Window, cx: &mut App| {
        crate::modules::toggle_wallpaper_selector(cx);
    });

    let on_launcher_click = Arc::new(|_: &mut Window, cx: &mut App| {
        crate::modules::toggle_launcher(cx);
    });

    let on_power_click = Arc::new(|_: &mut Window, cx: &mut App| {
        crate::modules::toggle_power_menu(cx);
    });

    let on_tray_click = Arc::new(|id: String| {
        tokio::task::spawn_blocking(move || {
            let _ = beskar_services::tray::command(
                "tray.activate",
                &[beskar_services::sysvalue::SysValue::Text(id)],
            );
        });
    });

    let on_tray_menu = Arc::new(move |id: String, _: &mut Window, cx: &mut App| {
        crate::modules::open_tray_menu(id, cx);
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

