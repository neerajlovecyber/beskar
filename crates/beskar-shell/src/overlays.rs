use beskar_core::models::AppItem;
use beskar_services::audio::AudioService;
use beskar_services::battery::BatteryService;
use beskar_ui::{ControlCenterWidget, LauncherWidget, LockScreenWidget, PowerMenuWidget};
use gpui_kit::layer_shell::{
    Anchor as LayerAnchor, KeyboardInteractivity, Layer, LayerShellOptions,
};
use gpui_kit::*;

use std::sync::Mutex;
use tracing::info;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum OverlayKind {
    Launcher,
    PowerMenu,
    ControlCenter,
    LockScreen,
}

static ACTIVE_OVERLAY: Mutex<Option<(OverlayKind, AnyWindowHandle)>> = Mutex::new(None);

pub fn forget_overlay(kind: OverlayKind) {
    let mut guard = ACTIVE_OVERLAY.lock().unwrap();
    if guard.as_ref().is_some_and(|(k, _)| *k == kind) {
        guard.take();
    }
}

pub fn close_active_overlay(cx: &mut App) -> Option<OverlayKind> {
    let mut guard = ACTIVE_OVERLAY.lock().unwrap();
    if let Some((kind, handle)) = guard.take() {
        let _ = cx.update_window(handle, |_, window, _| {
            window.remove_window();
        });
        Some(kind)
    } else {
        None
    }
}

#[allow(dead_code)]
pub fn is_overlay_open(kind: OverlayKind) -> bool {
    let guard = ACTIVE_OVERLAY.lock().unwrap();
    guard.as_ref().is_some_and(|(k, _)| *k == kind)
}


/// Toggle the App Launcher window.
pub fn toggle_launcher(cx: &mut App) {
    if close_active_overlay(cx) == Some(OverlayKind::Launcher) {
        return;
    }

    let options = WindowOptions {
        titlebar: None,
        window_bounds: Some(WindowBounds::Windowed(Bounds {
            origin: point(px(0.), px(0.)),
            size: Size::new(px(580.), px(460.)),
        })),
        app_id: Some("beskar-launcher".to_string()),
        window_background: WindowBackgroundAppearance::Transparent,
        kind: WindowKind::LayerShell(LayerShellOptions {
            namespace: "beskar-launcher".to_string(),
            layer: Layer::Overlay,
            anchor: LayerAnchor::TOP,
            exclusive_zone: None,
            margin: Some((px(48.), px(0.), px(0.), px(0.))),
            keyboard_interactivity: KeyboardInteractivity::Exclusive,
            ..Default::default()
        }),
        focus: true,
        ..Default::default()
    };

    if let Ok(handle) = cx.open_window(options, move |_window, cx| {
        cx.new(|cx| LauncherView::new(cx))
    }) {
        let mut guard = ACTIVE_OVERLAY.lock().unwrap();
        *guard = Some((OverlayKind::Launcher, handle.into()));
        info!("Opened dedicated LayerShell App Launcher overlay window");
    }
}

/// Toggle the Power Menu window.
pub fn toggle_power_menu(cx: &mut App) {
    if close_active_overlay(cx) == Some(OverlayKind::PowerMenu) {
        return;
    }

    let options = WindowOptions {
        titlebar: None,
        window_bounds: Some(WindowBounds::Windowed(Bounds {
            origin: point(px(0.), px(0.)),
            size: Size::new(px(240.), px(290.)),
        })),
        app_id: Some("beskar-power-menu".to_string()),
        window_background: WindowBackgroundAppearance::Transparent,
        kind: WindowKind::LayerShell(LayerShellOptions {
            namespace: "beskar-power-menu".to_string(),
            layer: Layer::Overlay,
            anchor: LayerAnchor::TOP | LayerAnchor::RIGHT,
            exclusive_zone: None,
            margin: Some((px(48.), px(12.), px(0.), px(0.))),
            keyboard_interactivity: KeyboardInteractivity::OnDemand,
            ..Default::default()
        }),
        focus: true,
        ..Default::default()
    };

    if let Ok(handle) = cx.open_window(options, move |_window, cx| {
        cx.new(|cx| PowerMenuView::new(cx))
    }) {
        let mut guard = ACTIVE_OVERLAY.lock().unwrap();
        *guard = Some((OverlayKind::PowerMenu, handle.into()));
        info!("Opened dedicated LayerShell Power Menu overlay window");
    }
}

/// Toggle the Control Center / Quick Settings window.
pub fn toggle_control_center(cx: &mut App) {
    if close_active_overlay(cx) == Some(OverlayKind::ControlCenter) {
        return;
    }

    let options = WindowOptions {
        titlebar: None,
        window_bounds: Some(WindowBounds::Windowed(Bounds {
            origin: point(px(0.), px(0.)),
            size: Size::new(px(360.), px(460.)),
        })),
        app_id: Some("beskar-control-center".to_string()),
        window_background: WindowBackgroundAppearance::Transparent,
        kind: WindowKind::LayerShell(LayerShellOptions {
            namespace: "beskar-control-center".to_string(),
            layer: Layer::Overlay,
            anchor: LayerAnchor::TOP | LayerAnchor::RIGHT,
            exclusive_zone: None,
            margin: Some((px(48.), px(12.), px(0.), px(0.))),
            keyboard_interactivity: KeyboardInteractivity::OnDemand,
            ..Default::default()
        }),
        focus: true,
        ..Default::default()
    };

    if let Ok(handle) = cx.open_window(options, move |_window, cx| {
        cx.new(|cx| ControlCenterView::new(cx))
    }) {
        let mut guard = ACTIVE_OVERLAY.lock().unwrap();
        *guard = Some((OverlayKind::ControlCenter, handle.into()));
        info!("Opened dedicated LayerShell Control Center overlay window");
    }
}

/// Toggle the Fullscreen Lock Screen window.
pub fn toggle_lockscreen(cx: &mut App) {
    if close_active_overlay(cx) == Some(OverlayKind::LockScreen) {
        return;
    }

    let options = WindowOptions {
        titlebar: None,
        app_id: Some("beskar-lockscreen".to_string()),
        window_background: WindowBackgroundAppearance::Transparent,
        kind: WindowKind::LayerShell(LayerShellOptions {
            namespace: "beskar-lockscreen".to_string(),
            layer: Layer::Overlay,
            anchor: LayerAnchor::TOP | LayerAnchor::BOTTOM | LayerAnchor::LEFT | LayerAnchor::RIGHT,
            exclusive_zone: None,
            keyboard_interactivity: KeyboardInteractivity::Exclusive,
            ..Default::default()
        }),
        focus: true,
        ..Default::default()
    };

    if let Ok(handle) = cx.open_window(options, move |_window, cx| {
        cx.new(|cx| LockScreenView::new(cx))
    }) {
        let mut guard = ACTIVE_OVERLAY.lock().unwrap();
        *guard = Some((OverlayKind::LockScreen, handle.into()));
        info!("Opened dedicated LayerShell Lock Screen overlay window");
    }
}


/// Dedicated View for App Launcher
pub struct LauncherView {
    apps: Vec<AppItem>,
    focus_handle: FocusHandle,
    close_tx: tokio::sync::mpsc::UnboundedSender<()>,
}


impl LauncherView {
    pub fn new(cx: &mut Context<Self>) -> Self {
        let apps = beskar_services::list_apps();
        let focus_handle = cx.focus_handle();
        let (close_tx, mut close_rx) = tokio::sync::mpsc::unbounded_channel::<()>();

        cx.spawn(async move |_this, cx| {
            while let Some(()) = close_rx.recv().await {
                let _ = cx.update(|cx| {
                    close_active_overlay(cx);
                });
            }
        })
        .detach();

        Self {
            apps,
            focus_handle,
            close_tx,
        }
    }
}

impl Render for LauncherView {
    fn render(&mut self, _window: &mut Window, cx: &mut Context<Self>) -> impl IntoElement {
        let close_tx = self.close_tx.clone();
        let launch_tx = self.close_tx.clone();

        div()
            .size_full()
            .track_focus(&self.focus_handle)
            .on_key_down(cx.listener(|_, event: &KeyDownEvent, window, cx| {
                if event.keystroke.key == "escape" {
                    forget_overlay(OverlayKind::Launcher);
                    window.remove_window();
                    cx.stop_propagation();
                }
            }))
            .child(
                LauncherWidget::new(self.apps.clone())
                    .on_launch(move |cmd| {
                        let _ = beskar_services::launch_app(&cmd);
                        let _ = launch_tx.send(());
                    })
                    .on_close(move || {
                        let _ = close_tx.send(());
                    }),
            )
    }
}

/// Dedicated View for Power Menu
pub struct PowerMenuView {
    focus_handle: FocusHandle,
    close_tx: tokio::sync::mpsc::UnboundedSender<()>,
}

impl PowerMenuView {
    pub fn new(cx: &mut Context<Self>) -> Self {
        let focus_handle = cx.focus_handle();
        let (close_tx, mut close_rx) = tokio::sync::mpsc::unbounded_channel::<()>();

        cx.spawn(async move |_this, cx| {
            while let Some(()) = close_rx.recv().await {
                let _ = cx.update(|cx| {
                    close_active_overlay(cx);
                });
            }
        })
        .detach();

        Self {
            focus_handle,
            close_tx,
        }
    }
}

impl Render for PowerMenuView {
    fn render(&mut self, _window: &mut Window, cx: &mut Context<Self>) -> impl IntoElement {
        let tx = self.close_tx.clone();
        let action_tx = self.close_tx.clone();

        div()
            .size_full()
            .track_focus(&self.focus_handle)
            .on_key_down(cx.listener(|_, event: &KeyDownEvent, window, cx| {
                if event.keystroke.key == "escape" {
                    forget_overlay(OverlayKind::PowerMenu);
                    window.remove_window();
                    cx.stop_propagation();
                }
            }))
            .child(
                PowerMenuWidget::new()
                    .on_action(move |action| {
                        let cmd = action.default_command();
                        let _ = std::process::Command::new("sh").args(["-c", cmd]).spawn();
                        let _ = action_tx.send(());
                    })
                    .on_close(move || {
                        let _ = tx.send(());
                    }),
            )
    }
}

/// Dedicated View for Control Center
pub struct ControlCenterView {
    volume_percent: u8,
    battery_percent: u8,
    is_muted: bool,
    is_charging: bool,
    focus_handle: FocusHandle,
    close_tx: tokio::sync::mpsc::UnboundedSender<()>,
}

impl ControlCenterView {
    pub fn new(cx: &mut Context<Self>) -> Self {
        let aud = AudioService::read_state();
        let bat = BatteryService::new().read_state();
        let focus_handle = cx.focus_handle();
        let (close_tx, mut close_rx) = tokio::sync::mpsc::unbounded_channel::<()>();

        cx.spawn(async move |_this, cx| {
            while let Some(()) = close_rx.recv().await {
                let _ = cx.update(|cx| {
                    close_active_overlay(cx);
                });
            }
        })
        .detach();

        Self {
            volume_percent: (aud.volume * 100.0).round() as u8,
            battery_percent: bat.percentage.round() as u8,
            is_muted: aud.is_muted,
            is_charging: bat.is_charging,
            focus_handle,
            close_tx,
        }
    }
}

impl Render for ControlCenterView {
    fn render(&mut self, _window: &mut Window, cx: &mut Context<Self>) -> impl IntoElement {
        let tx = self.close_tx.clone();

        div()
            .size_full()
            .track_focus(&self.focus_handle)
            .on_key_down(cx.listener(|_, event: &KeyDownEvent, window, cx| {
                if event.keystroke.key == "escape" {
                    forget_overlay(OverlayKind::ControlCenter);
                    window.remove_window();
                    cx.stop_propagation();
                }
            }))
            .child(
                ControlCenterWidget::new(self.volume_percent, self.battery_percent)
                    .muted(self.is_muted)
                    .charging(self.is_charging)
                    .wifi(true, None)
                    .bluetooth(true)
                    .on_close(move || {
                        let _ = tx.send(());
                    }),
            )
    }
}

/// Dedicated View for Fullscreen Lock Screen
pub struct LockScreenView {
    time_str: String,
    date_str: String,
    focus_handle: FocusHandle,
    close_tx: tokio::sync::mpsc::UnboundedSender<()>,
}

impl LockScreenView {
    pub fn new(cx: &mut Context<Self>) -> Self {
        let now = chrono::Local::now();
        let time_str = now.format("%-I:%M %p").to_string();
        let date_str = now.format("%A, %B %-d").to_string();
        let focus_handle = cx.focus_handle();
        let (close_tx, mut close_rx) = tokio::sync::mpsc::unbounded_channel::<()>();

        cx.spawn(async move |_this, cx| {
            while let Some(()) = close_rx.recv().await {
                let _ = cx.update(|cx| {
                    close_active_overlay(cx);
                });
            }
        })
        .detach();

        Self {
            time_str,
            date_str,
            focus_handle,
            close_tx,
        }
    }
}

impl Render for LockScreenView {
    fn render(&mut self, _window: &mut Window, _cx: &mut Context<Self>) -> impl IntoElement {
        let tx = self.close_tx.clone();
        let cancel_tx = self.close_tx.clone();

        div()
            .size_full()
            .track_focus(&self.focus_handle)
            .child(
                LockScreenWidget::new("User", &self.time_str, &self.date_str)
                    .on_unlock_attempt(move |_pwd| {
                        let _ = tx.send(());
                    })
                    .on_cancel(move || {
                        let _ = cancel_tx.send(());
                    }),
            )
    }
}

