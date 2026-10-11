use beskar_core::config::{BarStyleConfig, ShellConfig, ThemePresetConfig};
use beskar_core::models::{AppItem, NotificationItem};
use beskar_services::audio::AudioService;
use beskar_services::battery::BatteryService;
use beskar_services::ClipboardEntry;

use beskar_ui::{
    CaptureMode, ClipboardWidget, ControlCenterWidget, DashboardWidget, LauncherWidget, LockScreenWidget,
    MusicPlayerWidget, NotificationCenterWidget, NotificationToastWidget, PowerAction, PowerMenuWidget,
    ScreenCaptureWidget, SettingsCategory, SettingsConfig, SettingsWidget, WallpaperItem, WallpaperSelectorWidget,
};
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
    Settings,
    Clipboard,
    Dashboard,
    Music,
    NotificationCenter,
    ScreenCapture,
    WallpaperSelector,
}


static ACTIVE_OVERLAY: Mutex<Option<(OverlayKind, AnyWindowHandle)>> = Mutex::new(None);

pub fn forget_overlay(kind: OverlayKind) {
    let mut guard = ACTIVE_OVERLAY.lock().unwrap();
    if guard.as_ref().is_some_and(|(k, _)| *k == kind) {
        guard.take();
    }
}

pub fn close_active_overlay(cx: &mut App) -> Option<OverlayKind> {
    let item = {
        let mut guard = ACTIVE_OVERLAY.lock().unwrap();
        guard.take()
    };
    if let Some((kind, handle)) = item {
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
        app_id: Some("beskar-launcher".to_string()),
        window_background: WindowBackgroundAppearance::Transparent,
        kind: WindowKind::LayerShell(LayerShellOptions {
            namespace: "beskar-launcher".to_string(),
            layer: Layer::Overlay,
            anchor: LayerAnchor::TOP | LayerAnchor::BOTTOM | LayerAnchor::LEFT | LayerAnchor::RIGHT,
            exclusive_zone: None,
            keyboard_interactivity: KeyboardInteractivity::OnDemand,
            ..Default::default()
        }),
        focus: true,
        ..Default::default()
    };

    if let Ok(handle) = cx.open_window(options, move |_window, cx| {
        cx.new(LauncherView::new)
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
        app_id: Some("beskar-power-menu".to_string()),
        window_background: WindowBackgroundAppearance::Transparent,
        kind: WindowKind::LayerShell(LayerShellOptions {
            namespace: "beskar-power-menu".to_string(),
            layer: Layer::Overlay,
            anchor: LayerAnchor::TOP | LayerAnchor::BOTTOM | LayerAnchor::LEFT | LayerAnchor::RIGHT,
            exclusive_zone: None,
            keyboard_interactivity: KeyboardInteractivity::OnDemand,
            ..Default::default()
        }),
        focus: true,
        ..Default::default()
    };

    if let Ok(handle) = cx.open_window(options, move |_window, cx| {
        cx.new(PowerMenuView::new)
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
        app_id: Some("beskar-control-center".to_string()),
        window_background: WindowBackgroundAppearance::Transparent,
        kind: WindowKind::LayerShell(LayerShellOptions {
            namespace: "beskar-control-center".to_string(),
            layer: Layer::Overlay,
            anchor: LayerAnchor::TOP | LayerAnchor::BOTTOM | LayerAnchor::LEFT | LayerAnchor::RIGHT,
            exclusive_zone: None,
            keyboard_interactivity: KeyboardInteractivity::OnDemand,
            ..Default::default()
        }),
        focus: true,
        ..Default::default()
    };

    if let Ok(handle) = cx.open_window(options, move |_window, cx| {
        cx.new(ControlCenterView::new)
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
        cx.new(LockScreenView::new)
    }) {
        let mut guard = ACTIVE_OVERLAY.lock().unwrap();
        *guard = Some((OverlayKind::LockScreen, handle.into()));
        info!("Opened dedicated LayerShell Lock Screen overlay window");
    }
}

/// Toggle the Preferences / Settings window.
pub fn toggle_settings(cx: &mut App) {
    if close_active_overlay(cx) == Some(OverlayKind::Settings) {
        return;
    }

    let options = WindowOptions {
        titlebar: None,
        app_id: Some("beskar-settings".to_string()),
        window_background: WindowBackgroundAppearance::Transparent,
        kind: WindowKind::LayerShell(LayerShellOptions {
            namespace: "beskar-settings".to_string(),
            layer: Layer::Overlay,
            anchor: LayerAnchor::TOP | LayerAnchor::BOTTOM | LayerAnchor::LEFT | LayerAnchor::RIGHT,
            exclusive_zone: None,
            keyboard_interactivity: KeyboardInteractivity::OnDemand,
            ..Default::default()
        }),
        focus: true,
        ..Default::default()
    };

    if let Ok(handle) = cx.open_window(options, move |_window, cx| {
        cx.new(SettingsView::new)
    }) {
        let mut guard = ACTIVE_OVERLAY.lock().unwrap();
        *guard = Some((OverlayKind::Settings, handle.into()));
        info!("Opened dedicated LayerShell Settings preferences overlay window");
    }
}

/// Toggle the dedicated LayerShell Clipboard History overlay window.
pub fn toggle_clipboard(cx: &mut App) {
    if close_active_overlay(cx) == Some(OverlayKind::Clipboard) {
        return;
    }

    let options = WindowOptions {
        titlebar: None,
        app_id: Some("beskar-clipboard".to_string()),
        window_background: WindowBackgroundAppearance::Transparent,
        kind: WindowKind::LayerShell(LayerShellOptions {
            namespace: "beskar-clipboard".to_string(),
            layer: Layer::Overlay,
            anchor: LayerAnchor::TOP | LayerAnchor::BOTTOM | LayerAnchor::LEFT | LayerAnchor::RIGHT,
            exclusive_zone: None,
            keyboard_interactivity: KeyboardInteractivity::OnDemand,
            ..Default::default()
        }),
        focus: true,
        ..Default::default()
    };

    if let Ok(handle) = cx.open_window(options, move |_window, cx| {
        cx.new(ClipboardView::new)
    }) {
        let mut guard = ACTIVE_OVERLAY.lock().unwrap();
        *guard = Some((OverlayKind::Clipboard, handle.into()));
        info!("Opened dedicated LayerShell Clipboard overlay window");
    }
}

/// Toggle the Developer Dashboard overlay window.
pub fn toggle_dashboard(cx: &mut App) {
    if close_active_overlay(cx) == Some(OverlayKind::Dashboard) {
        return;
    }

    let options = WindowOptions {
        titlebar: None,
        app_id: Some("beskar-dashboard".to_string()),
        window_background: WindowBackgroundAppearance::Transparent,
        kind: WindowKind::LayerShell(LayerShellOptions {
            namespace: "beskar-dashboard".to_string(),
            layer: Layer::Overlay,
            anchor: LayerAnchor::TOP | LayerAnchor::BOTTOM | LayerAnchor::LEFT | LayerAnchor::RIGHT,
            exclusive_zone: None,
            keyboard_interactivity: KeyboardInteractivity::OnDemand,
            ..Default::default()
        }),
        focus: true,
        ..Default::default()
    };

    if let Ok(handle) = cx.open_window(options, move |_window, cx| {
        cx.new(DashboardView::new)
    }) {
        let mut guard = ACTIVE_OVERLAY.lock().unwrap();
        *guard = Some((OverlayKind::Dashboard, handle.into()));
        info!("Opened dedicated LayerShell Developer Dashboard overlay window");
    }
}

/// Toggle the dedicated Music Player overlay window.
pub fn toggle_music(cx: &mut App) {
    if close_active_overlay(cx) == Some(OverlayKind::Music) {
        return;
    }

    let options = WindowOptions {
        titlebar: None,
        app_id: Some("beskar-music".to_string()),
        window_background: WindowBackgroundAppearance::Transparent,
        kind: WindowKind::LayerShell(LayerShellOptions {
            namespace: "beskar-music".to_string(),
            layer: Layer::Overlay,
            anchor: LayerAnchor::TOP | LayerAnchor::BOTTOM | LayerAnchor::LEFT | LayerAnchor::RIGHT,
            exclusive_zone: None,
            keyboard_interactivity: KeyboardInteractivity::OnDemand,
            ..Default::default()
        }),
        focus: true,
        ..Default::default()
    };

    if let Ok(handle) = cx.open_window(options, move |_window, cx| {
        cx.new(MusicPlayerView::new)
    }) {
        let mut guard = ACTIVE_OVERLAY.lock().unwrap();
        *guard = Some((OverlayKind::Music, handle.into()));
        info!("Opened dedicated LayerShell Music Player overlay window");
    }
}

/// Toggle the persistent Notification Center drawer.
pub fn toggle_notification_center(cx: &mut App) {
    if close_active_overlay(cx) == Some(OverlayKind::NotificationCenter) {
        return;
    }

    let options = WindowOptions {
        titlebar: None,
        app_id: Some("beskar-notifications".to_string()),
        window_background: WindowBackgroundAppearance::Transparent,
        kind: WindowKind::LayerShell(LayerShellOptions {
            namespace: "beskar-notifications".to_string(),
            layer: Layer::Overlay,
            anchor: LayerAnchor::TOP | LayerAnchor::BOTTOM | LayerAnchor::LEFT | LayerAnchor::RIGHT,
            exclusive_zone: None,
            keyboard_interactivity: KeyboardInteractivity::OnDemand,
            ..Default::default()
        }),
        focus: true,
        ..Default::default()
    };

    if let Ok(handle) = cx.open_window(options, move |_window, cx| {
        cx.new(NotificationCenterView::new)
    }) {
        let mut guard = ACTIVE_OVERLAY.lock().unwrap();
        *guard = Some((OverlayKind::NotificationCenter, handle.into()));
        info!("Opened dedicated LayerShell Notification Center overlay window");
    }
}

/// Toggle the Screen Capture tool modal.
pub fn toggle_screencapture(cx: &mut App) {
    if close_active_overlay(cx) == Some(OverlayKind::ScreenCapture) {
        return;
    }

    let options = WindowOptions {
        titlebar: None,
        app_id: Some("beskar-screencapture".to_string()),
        window_background: WindowBackgroundAppearance::Transparent,
        kind: WindowKind::LayerShell(LayerShellOptions {
            namespace: "beskar-screencapture".to_string(),
            layer: Layer::Overlay,
            anchor: LayerAnchor::TOP | LayerAnchor::BOTTOM | LayerAnchor::LEFT | LayerAnchor::RIGHT,
            exclusive_zone: None,
            keyboard_interactivity: KeyboardInteractivity::OnDemand,
            ..Default::default()
        }),
        focus: true,
        ..Default::default()
    };

    if let Ok(handle) = cx.open_window(options, move |_window, cx| {
        cx.new(ScreenCaptureView::new)
    }) {
        let mut guard = ACTIVE_OVERLAY.lock().unwrap();
        *guard = Some((OverlayKind::ScreenCapture, handle.into()));
        info!("Opened dedicated LayerShell Screen Capture overlay window");
    }
}

/// Toggle the Wallpaper Selector gallery modal.
pub fn toggle_wallpaper_selector(cx: &mut App) {
    if close_active_overlay(cx) == Some(OverlayKind::WallpaperSelector) {
        return;
    }

    let options = WindowOptions {
        titlebar: None,
        app_id: Some("beskar-wallpapers".to_string()),
        window_background: WindowBackgroundAppearance::Transparent,
        kind: WindowKind::LayerShell(LayerShellOptions {
            namespace: "beskar-wallpapers".to_string(),
            layer: Layer::Overlay,
            anchor: LayerAnchor::TOP | LayerAnchor::BOTTOM | LayerAnchor::LEFT | LayerAnchor::RIGHT,
            exclusive_zone: None,
            keyboard_interactivity: KeyboardInteractivity::OnDemand,
            ..Default::default()
        }),
        focus: true,
        ..Default::default()
    };

    if let Ok(handle) = cx.open_window(options, move |_window, cx| {
        cx.new(WallpaperSelectorView::new)
    }) {
        let mut guard = ACTIVE_OVERLAY.lock().unwrap();
        *guard = Some((OverlayKind::WallpaperSelector, handle.into()));
        info!("Opened dedicated LayerShell Wallpaper Selector overlay window");
    }
}



#[derive(Debug, Clone)]
enum LauncherMsg {
    ClearQuery,
    Select(usize),
    Launch(String),
    Close,
}

/// Dedicated View for App Launcher
pub struct LauncherView {
    query: String,
    selected_idx: usize,
    apps: Vec<AppItem>,
    focus_handle: FocusHandle,
    msg_tx: tokio::sync::mpsc::UnboundedSender<LauncherMsg>,
}

impl LauncherView {
    pub fn new(cx: &mut Context<Self>) -> Self {
        let apps = beskar_services::list_apps();
        let focus_handle = cx.focus_handle();
        let (msg_tx, mut msg_rx) = tokio::sync::mpsc::unbounded_channel::<LauncherMsg>();

        cx.spawn(async move |this, cx| {
            while let Some(msg) = msg_rx.recv().await {
                let _ = this.update(cx, |this, cx| match msg {
                    LauncherMsg::ClearQuery => {
                        this.query.clear();
                        this.selected_idx = 0;
                        cx.notify();
                    }
                    LauncherMsg::Select(idx) => {
                        if this.selected_idx != idx {
                            this.selected_idx = idx;
                            cx.notify();
                        }
                    }
                    LauncherMsg::Launch(cmd) => {
                        let _ = beskar_services::launch_app(&cmd);
                        close_active_overlay(cx);
                    }
                    LauncherMsg::Close => {
                        close_active_overlay(cx);
                    }
                });
            }
        })
        .detach();

        Self {
            query: String::new(),
            selected_idx: 0,
            apps,
            focus_handle,
            msg_tx,
        }
    }
}

impl Focusable for LauncherView {
    fn focus_handle(&self, _cx: &App) -> FocusHandle {
        self.focus_handle.clone()
    }
}

impl Render for LauncherView {
    fn render(&mut self, _window: &mut Window, cx: &mut Context<Self>) -> impl IntoElement {
        let tx_sel = self.msg_tx.clone();
        let tx_launch = self.msg_tx.clone();
        let tx_clear = self.msg_tx.clone();
        let tx_close = self.msg_tx.clone();

        div()
            .id("launcher-backdrop")
            .size_full()
            .flex()
            .flex_col()
            .items_center()
            .pt(px(90.0))
            .track_focus(&self.focus_handle)
            .key_context("Launcher")
            .on_mouse_down(MouseButton::Left, move |_, window, _cx| {
                forget_overlay(OverlayKind::Launcher);
                window.remove_window();
            })
            .on_key_down(cx.listener(move |this, event: &KeyDownEvent, window, cx| {
                let key = event.keystroke.key.as_str();
                let mods = &event.keystroke.modifiers;

                match key {
                    "escape" => {
                        if !this.query.is_empty() {
                            this.query.clear();
                            this.selected_idx = 0;
                            cx.notify();
                        } else {
                            forget_overlay(OverlayKind::Launcher);
                            window.remove_window();
                        }
                        cx.stop_propagation();
                    }
                    "up" => {
                        this.selected_idx = this.selected_idx.saturating_sub(1);
                        cx.notify();
                        cx.stop_propagation();
                    }
                    "down" => {
                        let filtered = LauncherWidget::filter_and_rank(&this.apps, &this.query);
                        this.selected_idx =
                            (this.selected_idx + 1).min(filtered.len().saturating_sub(1));
                        cx.notify();
                        cx.stop_propagation();
                    }
                    "enter" | "return" => {
                        let filtered = LauncherWidget::filter_and_rank(&this.apps, &this.query);
                        if let Some(app) = filtered.get(this.selected_idx) {
                            let _ = beskar_services::launch_app(&app.exec);
                            forget_overlay(OverlayKind::Launcher);
                            window.remove_window();
                        }
                        cx.stop_propagation();
                    }
                    "backspace" => {
                        this.query.pop();
                        this.selected_idx = 0;
                        cx.notify();
                        cx.stop_propagation();
                    }
                    "space" if !mods.control && !mods.alt && !mods.platform => {
                        this.query.push(' ');
                        this.selected_idx = 0;
                        cx.notify();
                        cx.stop_propagation();
                    }
                    _ => {
                        if mods.control {
                            match key {
                                "n" => {
                                    let filtered =
                                        LauncherWidget::filter_and_rank(&this.apps, &this.query);
                                    this.selected_idx = (this.selected_idx + 1)
                                        .min(filtered.len().saturating_sub(1));
                                    cx.notify();
                                    cx.stop_propagation();
                                }
                                "p" => {
                                    this.selected_idx = this.selected_idx.saturating_sub(1);
                                    cx.notify();
                                    cx.stop_propagation();
                                }
                                "u" => {
                                    this.query.clear();
                                    this.selected_idx = 0;
                                    cx.notify();
                                    cx.stop_propagation();
                                }
                                "c" => {
                                    forget_overlay(OverlayKind::Launcher);
                                    window.remove_window();
                                    cx.stop_propagation();
                                }
                                _ => {}
                            }
                        } else if !mods.alt && !mods.platform
                            && event.keystroke.key.chars().count() == 1 {
                            let ch = event.keystroke.key.chars().next().unwrap();
                            this.query.push(ch);
                            this.selected_idx = 0;
                            cx.notify();
                            cx.stop_propagation();
                        }
                    }
                }
            }))
            .child(
                div()
                    .w(px(700.0))
                    .on_mouse_down(MouseButton::Left, |_, _, cx| {
                        cx.stop_propagation();
                    })
                    .child(
                        LauncherWidget::new(self.apps.clone())
                            .query(self.query.clone())
                            .selected_idx(self.selected_idx)
                            .on_select(move |idx| {
                                let _ = tx_sel.send(LauncherMsg::Select(idx));
                            })
                            .on_launch(move |cmd| {
                                let _ = tx_launch.send(LauncherMsg::Launch(cmd));
                            })
                            .on_clear(move || {
                                let _ = tx_clear.send(LauncherMsg::ClearQuery);
                            })
                            .on_close(move || {
                                let _ = tx_close.send(LauncherMsg::Close);
                            }),
                    ),
            )
    }
}

#[derive(Debug, Clone)]
enum PowerMenuMsg {
    Select(usize),
    RequestConfirm(PowerAction),
    CancelConfirm,
    ConfirmSelect(usize),
    Action(PowerAction),
    Close,
}

/// Dedicated View for Power Menu
pub struct PowerMenuView {
    selected_index: usize,
    pending_action: Option<PowerAction>,
    confirm_index: usize,
    focus_handle: FocusHandle,
    msg_tx: tokio::sync::mpsc::UnboundedSender<PowerMenuMsg>,
}

impl PowerMenuView {
    pub fn new(cx: &mut Context<Self>) -> Self {
        let focus_handle = cx.focus_handle();
        let (msg_tx, mut msg_rx) = tokio::sync::mpsc::unbounded_channel::<PowerMenuMsg>();

        cx.spawn(async move |this, cx| {
            while let Some(msg) = msg_rx.recv().await {
                let _ = this.update(cx, |this, cx| {
                    match msg {
                        PowerMenuMsg::Select(idx) => {
                            if this.selected_index != idx {
                                this.selected_index = idx;
                                cx.notify();
                            }
                        }
                        PowerMenuMsg::RequestConfirm(action) => {
                            this.pending_action = Some(action);
                            this.confirm_index = 1;
                            cx.notify();
                        }
                        PowerMenuMsg::CancelConfirm => {
                            this.pending_action = None;
                            cx.notify();
                        }
                        PowerMenuMsg::ConfirmSelect(idx) => {
                            if this.confirm_index != idx {
                                this.confirm_index = idx;
                                cx.notify();
                            }
                        }
                        PowerMenuMsg::Action(action) => {
                            if action == PowerAction::Lock {
                                close_active_overlay(cx);
                                toggle_lockscreen(cx);
                            } else {
                                let cmd = action.default_command();
                                let _ = std::process::Command::new("sh").args(["-c", cmd]).spawn();
                                close_active_overlay(cx);
                            }
                        }
                        PowerMenuMsg::Close => {
                            close_active_overlay(cx);
                        }
                    }
                });
            }
        })
        .detach();

        Self {
            selected_index: 0,
            pending_action: None,
            confirm_index: 1,
            focus_handle,
            msg_tx,
        }
    }
}

impl Focusable for PowerMenuView {
    fn focus_handle(&self, _cx: &App) -> FocusHandle {
        self.focus_handle.clone()
    }
}

impl Render for PowerMenuView {
    fn render(&mut self, _window: &mut Window, cx: &mut Context<Self>) -> impl IntoElement {
        let tx_sel = self.msg_tx.clone();
        let tx_req = self.msg_tx.clone();
        let tx_cancel = self.msg_tx.clone();
        let tx_conf_sel = self.msg_tx.clone();
        let tx_act = self.msg_tx.clone();
        let tx_close = self.msg_tx.clone();
        let msg_tx = self.msg_tx.clone();

        div()
            .id("power-menu-backdrop")
            .size_full()
            .flex()
            .items_center()
            .justify_center()
            .track_focus(&self.focus_handle)
            .key_context("PowerMenu")
            .on_mouse_down(MouseButton::Left, move |_, window, _cx| {
                forget_overlay(OverlayKind::PowerMenu);
                window.remove_window();
            })
            .on_key_down(cx.listener(move |this, event: &KeyDownEvent, window, cx| {
                match event.keystroke.key.as_str() {
                    "escape" => {
                        if this.pending_action.is_some() {
                            this.pending_action = None;
                            cx.notify();
                        } else {
                            forget_overlay(OverlayKind::PowerMenu);
                            window.remove_window();
                        }
                        cx.stop_propagation();
                    }
                    "1" => {
                        let _ = msg_tx.send(PowerMenuMsg::Action(PowerAction::Lock));
                        cx.stop_propagation();
                    }
                    "2" => {
                        this.pending_action = Some(PowerAction::Suspend);
                        this.confirm_index = 1;
                        cx.notify();
                        cx.stop_propagation();
                    }
                    "3" => {
                        this.pending_action = Some(PowerAction::Logout);
                        this.confirm_index = 1;
                        cx.notify();
                        cx.stop_propagation();
                    }
                    "4" => {
                        this.pending_action = Some(PowerAction::Restart);
                        this.confirm_index = 1;
                        cx.notify();
                        cx.stop_propagation();
                    }
                    "5" => {
                        this.pending_action = Some(PowerAction::Shutdown);
                        this.confirm_index = 1;
                        cx.notify();
                        cx.stop_propagation();
                    }
                    "left" | "h" | "up" | "k" => {
                        if this.pending_action.is_some() {
                            this.confirm_index = 0;
                        } else {
                            this.selected_index = this.selected_index.saturating_sub(1);
                        }
                        cx.notify();
                        cx.stop_propagation();
                    }
                    "right" | "l" | "down" | "j" | "tab" => {
                        if this.pending_action.is_some() {
                            this.confirm_index = 1;
                        } else {
                            this.selected_index = (this.selected_index + 1)
                                .min(PowerAction::ALL.len().saturating_sub(1));
                        }
                        cx.notify();
                        cx.stop_propagation();
                    }
                    "enter" | "return" | "space" => {
                        if let Some(pending) = this.pending_action {
                            if this.confirm_index == 1 {
                                let _ = msg_tx.send(PowerMenuMsg::Action(pending));
                            } else {
                                this.pending_action = None;
                                cx.notify();
                            }
                        } else {
                            let action = PowerAction::ALL[this.selected_index];
                            if action.requires_confirmation() {
                                this.pending_action = Some(action);
                                this.confirm_index = 1;
                                cx.notify();
                            } else {
                                let _ = msg_tx.send(PowerMenuMsg::Action(action));
                            }
                        }
                        cx.stop_propagation();
                    }
                    _ => {}
                }
            }))
            .child(
                div()
                    .on_mouse_down(MouseButton::Left, |_, _, cx| {
                        cx.stop_propagation();
                    })
                    .child(
                        PowerMenuWidget::new()
                            .selected_index(self.selected_index)
                            .pending_action(self.pending_action)
                            .confirm_index(self.confirm_index)
                            .on_select(move |idx| {
                                let _ = tx_sel.send(PowerMenuMsg::Select(idx));
                            })
                            .on_request_confirm(move |action| {
                                let _ = tx_req.send(PowerMenuMsg::RequestConfirm(action));
                            })
                            .on_cancel_confirm(move || {
                                let _ = tx_cancel.send(PowerMenuMsg::CancelConfirm);
                            })
                            .on_confirm_select(move |idx| {
                                let _ = tx_conf_sel.send(PowerMenuMsg::ConfirmSelect(idx));
                            })
                            .on_action(move |action| {
                                let _ = tx_act.send(PowerMenuMsg::Action(action));
                            })
                            .on_close(move || {
                                let _ = tx_close.send(PowerMenuMsg::Close);
                            }),
                    ),
            )
    }
}

#[derive(Debug, Clone)]
enum ControlCenterMsg {
    ToggleWifi,
    ToggleBluetooth,
    ChangeVolume(i32),
    ToggleMute,
    ChangeBrightness(i32),
    SetPowerProfile(String),
    ToggleWifiList,
    ToggleBtList,
    ConnectWifi(String),
    OpenLauncher,
    OpenClipboard,
    OpenPower,
    OpenSettings,
    Close,
}

/// Dedicated View for Control Center
pub struct ControlCenterView {
    volume_percent: u8,
    battery_percent: u8,
    is_muted: bool,
    is_charging: bool,
    brightness_percent: u8,
    active_power_profile: String,
    is_wifi_on: bool,
    wifi_ssid: Option<String>,
    is_bt_on: bool,
    wifi_networks: Vec<beskar_services::WifiAccessPoint>,
    bt_devices: Vec<beskar_services::BluetoothDeviceItem>,
    show_wifi_list: bool,
    show_bt_list: bool,
    focus_handle: FocusHandle,
    msg_tx: tokio::sync::mpsc::UnboundedSender<ControlCenterMsg>,
}

impl ControlCenterView {
    pub fn new(cx: &mut Context<Self>) -> Self {
        let aud = AudioService::read_state();
        let bat = BatteryService::new().read_state();
        let (is_wifi_on, wifi_ssid) = beskar_services::NetworkHelper::get_wifi_status();
        let is_bt_on = beskar_services::BluetoothHelper::get_bluetooth_status();
        let brightness_percent = beskar_services::BacklightService::get_brightness();
        let active_power_profile = beskar_services::PowerProfilesService::get_profile();
        let focus_handle = cx.focus_handle();
        let (msg_tx, mut msg_rx) = tokio::sync::mpsc::unbounded_channel::<ControlCenterMsg>();

        cx.spawn(async move |this, cx| {
            while let Some(msg) = msg_rx.recv().await {
                match msg {
                    ControlCenterMsg::ToggleWifi => {
                        let is_on = this.update(cx, |t, _| t.is_wifi_on).unwrap_or(true);
                        let next_state = !is_on;
                        let _ = this.update(cx, |this, cx| {
                            this.is_wifi_on = next_state;
                            if !next_state {
                                this.wifi_ssid = None;
                            }
                            cx.notify();
                        });
                        tokio::task::spawn_blocking(move || {
                            beskar_services::NetworkHelper::toggle_wifi(is_on);
                        })
                        .await
                        .ok();
                        if next_state {
                            let (_, ssid) = tokio::task::spawn_blocking(|| {
                                beskar_services::NetworkHelper::get_wifi_status()
                            })
                            .await
                            .unwrap_or((false, None));
                            let _ = this.update(cx, |this, cx| {
                                this.wifi_ssid = ssid;
                                cx.notify();
                            });
                        }
                    }
                    ControlCenterMsg::ToggleBluetooth => {
                        let is_on = this.update(cx, |t, _| t.is_bt_on).unwrap_or(true);
                        let next_state = !is_on;
                        let _ = this.update(cx, |this, cx| {
                            this.is_bt_on = next_state;
                            cx.notify();
                        });
                        tokio::task::spawn_blocking(move || {
                            beskar_services::BluetoothHelper::toggle_bluetooth(is_on);
                        })
                        .await
                        .ok();
                    }
                    ControlCenterMsg::ChangeVolume(delta) => {
                        let _ = this.update(cx, |this, cx| {
                            let new_vol = (this.volume_percent as i32 + delta).clamp(0, 100) as u8;
                            this.volume_percent = new_vol;
                            this.is_muted = false;
                            cx.notify();
                        });
                        tokio::task::spawn_blocking(move || {
                            beskar_services::AudioService::set_volume(delta);
                        })
                        .await
                        .ok();
                    }
                    ControlCenterMsg::ToggleMute => {
                        let _ = this.update(cx, |this, cx| {
                            this.is_muted = !this.is_muted;
                            cx.notify();
                        });
                        tokio::task::spawn_blocking(|| {
                            beskar_services::AudioService::toggle_mute();
                        })
                        .await
                        .ok();
                    }
                    ControlCenterMsg::ChangeBrightness(delta) => {
                        let new_bright = this
                            .update(cx, |t, _| {
                                (t.brightness_percent as i32 + delta).clamp(5, 100) as u8
                            })
                            .unwrap_or(50);
                        let _ = this.update(cx, |this, cx| {
                            this.brightness_percent = new_bright;
                            cx.notify();
                        });
                        tokio::task::spawn_blocking(move || {
                            beskar_services::BacklightService::set_brightness(new_bright);
                        })
                        .await
                        .ok();
                    }
                    ControlCenterMsg::SetPowerProfile(prof) => {
                        let prof_clone = prof.clone();
                        let _ = this.update(cx, |this, cx| {
                            this.active_power_profile = prof;
                            cx.notify();
                        });
                        tokio::task::spawn_blocking(move || {
                            beskar_services::PowerProfilesService::set_profile(&prof_clone);
                        })
                        .await
                        .ok();
                    }
                    ControlCenterMsg::ToggleWifiList => {
                        let will_show = this
                            .update(cx, |t, cx| {
                                t.show_wifi_list = !t.show_wifi_list;
                                cx.notify();
                                t.show_wifi_list
                            })
                            .unwrap_or(false);
                        if will_show {
                            let networks = beskar_services::NetworkHelper::scan_networks_async().await;
                            let _ = this.update(cx, |this, cx| {
                                this.wifi_networks = networks;
                                cx.notify();
                            });
                        }
                    }
                    ControlCenterMsg::ToggleBtList => {
                        let will_show = this
                            .update(cx, |t, cx| {
                                t.show_bt_list = !t.show_bt_list;
                                cx.notify();
                                t.show_bt_list
                            })
                            .unwrap_or(false);
                        if will_show {
                            let devices = beskar_services::BluetoothHelper::list_devices_async().await;
                            let _ = this.update(cx, |this, cx| {
                                this.bt_devices = devices;
                                cx.notify();
                            });
                        }
                    }
                    ControlCenterMsg::ConnectWifi(ssid) => {
                        let _ = this.update(cx, |this, cx| {
                            this.wifi_ssid = Some(ssid.clone());
                            cx.notify();
                        });
                        tokio::task::spawn_blocking(move || {
                            beskar_services::NetworkHelper::connect(&ssid, None);
                        })
                        .await
                        .ok();
                    }
                    ControlCenterMsg::OpenLauncher => {
                        let _ = this.update(cx, |_, cx| {
                            close_active_overlay(cx);
                            toggle_launcher(cx);
                        });
                    }
                    ControlCenterMsg::OpenClipboard => {
                        let _ = this.update(cx, |_, cx| {
                            close_active_overlay(cx);
                            toggle_clipboard(cx);
                        });
                    }
                    ControlCenterMsg::OpenPower => {
                        let _ = this.update(cx, |_, cx| {
                            close_active_overlay(cx);
                            toggle_power_menu(cx);
                        });
                    }
                    ControlCenterMsg::OpenSettings => {
                        let _ = this.update(cx, |_, cx| {
                            close_active_overlay(cx);
                            toggle_settings(cx);
                        });
                    }
                    ControlCenterMsg::Close => {
                        let _ = this.update(cx, |_, cx| {
                            close_active_overlay(cx);
                        });
                    }
                }
            }
        })
        .detach();

        Self {
            volume_percent: (aud.volume * 100.0).round() as u8,
            battery_percent: bat.percentage.round() as u8,
            is_muted: aud.is_muted,
            is_charging: bat.is_charging,
            brightness_percent,
            active_power_profile,
            is_wifi_on,
            wifi_ssid,
            is_bt_on,
            wifi_networks: Vec::new(),
            bt_devices: Vec::new(),
            show_wifi_list: false,
            show_bt_list: false,
            focus_handle,
            msg_tx,
        }
    }
}

impl Focusable for ControlCenterView {
    fn focus_handle(&self, _cx: &App) -> FocusHandle {
        self.focus_handle.clone()
    }
}

impl Render for ControlCenterView {
    fn render(&mut self, _window: &mut Window, cx: &mut Context<Self>) -> impl IntoElement {
        let tx_vol = self.msg_tx.clone();
        let tx_mute = self.msg_tx.clone();
        let tx_bright = self.msg_tx.clone();
        let tx_prof = self.msg_tx.clone();
        let tx_wifi = self.msg_tx.clone();
        let tx_bt = self.msg_tx.clone();
        let tx_wlist = self.msg_tx.clone();
        let tx_blist = self.msg_tx.clone();
        let tx_conn = self.msg_tx.clone();
        let tx_launcher = self.msg_tx.clone();
        let tx_clipboard = self.msg_tx.clone();
        let tx_power = self.msg_tx.clone();
        let tx_settings = self.msg_tx.clone();
        let tx_close = self.msg_tx.clone();

        div()
            .id("control-center-backdrop")
            .size_full()
            .flex()
            .justify_end()
            .pt(px(56.0))
            .pr(px(16.0))
            .track_focus(&self.focus_handle)
            .key_context("ControlCenter")
            .on_mouse_down(MouseButton::Left, move |_, window, _cx| {
                forget_overlay(OverlayKind::ControlCenter);
                window.remove_window();
            })
            .on_key_down(cx.listener(|_, event: &KeyDownEvent, window, cx| {
                if event.keystroke.key == "escape" {
                    forget_overlay(OverlayKind::ControlCenter);
                    window.remove_window();
                    cx.stop_propagation();
                }
            }))
            .child(
                div()
                    .w(px(380.0))
                    .on_mouse_down(MouseButton::Left, |_, _, cx| {
                        cx.stop_propagation();
                    })
                    .child(
                        ControlCenterWidget::new(self.volume_percent, self.battery_percent)
                            .muted(self.is_muted)
                            .charging(self.is_charging)
                            .brightness(self.brightness_percent)
                            .power_profile(self.active_power_profile.clone())
                            .wifi(self.is_wifi_on, self.wifi_ssid.clone())
                            .bluetooth(self.is_bt_on)
                            .wifi_networks(self.wifi_networks.clone(), self.show_wifi_list)
                            .bt_devices(self.bt_devices.clone(), self.show_bt_list)
                            .on_volume_change(move |delta| {
                                let _ = tx_vol.send(ControlCenterMsg::ChangeVolume(delta));
                            })
                            .on_toggle_mute(move || {
                                let _ = tx_mute.send(ControlCenterMsg::ToggleMute);
                            })
                            .on_brightness_change(move |delta| {
                                let _ = tx_bright.send(ControlCenterMsg::ChangeBrightness(delta));
                            })
                            .on_set_power_profile(move |prof| {
                                let _ = tx_prof.send(ControlCenterMsg::SetPowerProfile(prof));
                            })
                            .on_toggle_wifi(move || {
                                let _ = tx_wifi.send(ControlCenterMsg::ToggleWifi);
                            })
                            .on_toggle_bluetooth(move || {
                                let _ = tx_bt.send(ControlCenterMsg::ToggleBluetooth);
                            })
                            .on_toggle_wifi_list(move || {
                                let _ = tx_wlist.send(ControlCenterMsg::ToggleWifiList);
                            })
                            .on_toggle_bt_list(move || {
                                let _ = tx_blist.send(ControlCenterMsg::ToggleBtList);
                            })
                            .on_connect_wifi(move |ssid| {
                                let _ = tx_conn.send(ControlCenterMsg::ConnectWifi(ssid));
                            })
                            .on_open_launcher(move || {
                                let _ = tx_launcher.send(ControlCenterMsg::OpenLauncher);
                            })
                            .on_open_clipboard(move || {
                                let _ = tx_clipboard.send(ControlCenterMsg::OpenClipboard);
                            })
                            .on_open_power(move || {
                                let _ = tx_power.send(ControlCenterMsg::OpenPower);
                            })
                            .on_open_settings(move || {
                                let _ = tx_settings.send(ControlCenterMsg::OpenSettings);
                            })
                            .on_close(move || {
                                let _ = tx_close.send(ControlCenterMsg::Close);
                            }),
                    ),
            )
    }
}

#[derive(Debug, Clone)]
enum SettingsMsg {
    SelectCategory(SettingsCategory),
    ToggleNotch(bool),
    ToggleWindowTitle(bool),
    ToggleMedia(bool),
    SelectAccent(usize),
    SelectPreset(beskar_theme::ThemePreset),
    TestNotification,
    Close,
}

/// Dedicated View for Settings / Preferences
pub struct SettingsView {
    config: SettingsConfig,
    focus_handle: FocusHandle,
    msg_tx: tokio::sync::mpsc::UnboundedSender<SettingsMsg>,
}

impl SettingsView {
    pub fn new(cx: &mut Context<Self>) -> Self {
        let focus_handle = cx.focus_handle();
        let (msg_tx, mut msg_rx) = tokio::sync::mpsc::unbounded_channel::<SettingsMsg>();

        let mut config = SettingsConfig::default();
        let shell_cfg = ShellConfig::load();
        config.island_mode_notch = shell_cfg.bar_style == BarStyleConfig::Convex;
        config.show_active_window_title = shell_cfg.show_workspaces;
        config.morph_on_media = shell_cfg.show_media_in_center;

        let aud = AudioService::read_state();
        let bat = BatteryService::new().read_state();
        let (is_wifi_on, _) = beskar_services::NetworkHelper::get_wifi_status();
        let is_bt_on = beskar_services::BluetoothHelper::get_bluetooth_status();
        config.volume_percent = (aud.volume * 100.0).round() as u8;
        config.battery_percent = bat.percentage.round() as u8;
        config.is_wifi_on = is_wifi_on;
        config.is_bt_on = is_bt_on;

        cx.spawn(async move |this, cx| {
            while let Some(msg) = msg_rx.recv().await {
                let _ = this.update(cx, |this, cx| match msg {
                    SettingsMsg::SelectCategory(cat) => {
                        this.config.active_category = cat;
                        cx.notify();
                    }
                    SettingsMsg::ToggleNotch(val) => {
                        this.config.island_mode_notch = val;
                        let mut shell_cfg = ShellConfig::load();
                        shell_cfg.bar_style = if val {
                            BarStyleConfig::Convex
                        } else {
                            BarStyleConfig::Island
                        };
                        let _ = shell_cfg.save();
                        cx.notify();
                    }
                    SettingsMsg::ToggleWindowTitle(val) => {
                        this.config.show_active_window_title = val;
                        let mut shell_cfg = ShellConfig::load();
                        shell_cfg.show_workspaces = val;
                        let _ = shell_cfg.save();
                        cx.notify();
                    }
                    SettingsMsg::ToggleMedia(val) => {
                        this.config.morph_on_media = val;
                        let mut shell_cfg = ShellConfig::load();
                        shell_cfg.show_media_in_center = val;
                        let _ = shell_cfg.save();
                        cx.notify();
                    }
                    SettingsMsg::SelectAccent(idx) => {
                        this.config.accent_color_idx = idx;
                        cx.notify();
                    }
                    SettingsMsg::SelectPreset(preset) => {
                        beskar_theme::ThemeEngine::set_preset(preset);
                        let mut shell_cfg = ShellConfig::load();
                        shell_cfg.theme_preset = match preset {
                            beskar_theme::ThemePreset::Obsidian => ThemePresetConfig::ObsidianGlass,
                            beskar_theme::ThemePreset::CatppuccinMocha => ThemePresetConfig::CatppuccinMocha,
                            beskar_theme::ThemePreset::GruvboxDark => ThemePresetConfig::GruvboxDark,
                            beskar_theme::ThemePreset::Wallpaper => ThemePresetConfig::WallpaperAuto,
                        };
                        let _ = shell_cfg.save();
                        cx.notify();
                    }
                    SettingsMsg::TestNotification => {
                        beskar_services::notifications::send_test(
                            "Beskar Shell",
                            "Dynamic island and control center settings updated!",
                        );
                    }
                    SettingsMsg::Close => {
                        close_active_overlay(cx);
                    }
                });
            }
        })
        .detach();


        Self {
            config,
            focus_handle,
            msg_tx,
        }
    }
}

impl Focusable for SettingsView {
    fn focus_handle(&self, _cx: &App) -> FocusHandle {
        self.focus_handle.clone()
    }
}

impl Render for SettingsView {
    fn render(&mut self, _window: &mut Window, cx: &mut Context<Self>) -> impl IntoElement {
        let tx_cat = self.msg_tx.clone();
        let tx_notch = self.msg_tx.clone();
        let tx_win = self.msg_tx.clone();
        let tx_media = self.msg_tx.clone();
        let tx_accent = self.msg_tx.clone();
        let tx_preset = self.msg_tx.clone();
        let tx_test = self.msg_tx.clone();
        let tx_close = self.msg_tx.clone();

        div()
            .id("settings-backdrop")
            .size_full()
            .flex()
            .items_center()
            .justify_center()
            .track_focus(&self.focus_handle)
            .key_context("Settings")
            .on_mouse_down(MouseButton::Left, move |_, window, _cx| {
                forget_overlay(OverlayKind::Settings);
                window.remove_window();
            })
            .on_key_down(cx.listener(|_, event: &KeyDownEvent, window, cx| {
                if event.keystroke.key == "escape" {
                    forget_overlay(OverlayKind::Settings);
                    window.remove_window();
                    cx.stop_propagation();
                }
            }))
            .child(
                div()
                    .on_mouse_down(MouseButton::Left, |_, _, cx| {
                        cx.stop_propagation();
                    })
                    .child(
                        SettingsWidget::new(self.config.clone())
                            .on_select_category(move |cat| {
                                let _ = tx_cat.send(SettingsMsg::SelectCategory(cat));
                            })
                            .on_toggle_notch_mode(move |val| {
                                let _ = tx_notch.send(SettingsMsg::ToggleNotch(val));
                            })
                            .on_toggle_window_title(move |val| {
                                let _ = tx_win.send(SettingsMsg::ToggleWindowTitle(val));
                            })
                            .on_toggle_media_morph(move |val| {
                                let _ = tx_media.send(SettingsMsg::ToggleMedia(val));
                            })
                            .on_select_accent(move |idx| {
                                let _ = tx_accent.send(SettingsMsg::SelectAccent(idx));
                            })
                            .on_select_preset(move |preset| {
                                let _ = tx_preset.send(SettingsMsg::SelectPreset(preset));
                            })
                            .on_test_notification(move || {
                                let _ = tx_test.send(SettingsMsg::TestNotification);
                            })
                            .on_close(move || {
                                let _ = tx_close.send(SettingsMsg::Close);
                            }),
                    ),
            )
    }
}

static NOTIFICATION_OVERLAY: Mutex<Option<AnyWindowHandle>> = Mutex::new(None);
static NOTIFICATION_QUEUE: Mutex<Vec<NotificationItem>> = Mutex::new(Vec::new());

pub fn forget_notification_overlay() {
    let mut guard = NOTIFICATION_OVERLAY.lock().unwrap();
    guard.take();
}

pub fn sync_notification_toasts(notifications: Vec<NotificationItem>, cx: &mut App) {
    let mut queue_guard = NOTIFICATION_QUEUE.lock().unwrap();
    *queue_guard = notifications.clone();
    drop(queue_guard);

    let mut guard = NOTIFICATION_OVERLAY.lock().unwrap();
    if notifications.is_empty() {
        if let Some(handle) = guard.take() {
            let _ = cx.update_window(handle, |_, window, _| {
                window.remove_window();
            });
        }
        return;
    }

    if let Some(handle) = guard.as_ref() {
        let _ = cx.update_window(*handle, |_, window, _| {
            window.refresh();
        });
    } else {
        let options = WindowOptions {
            titlebar: None,
            window_bounds: Some(WindowBounds::Windowed(Bounds {
                origin: point(px(0.), px(0.)),
                size: Size::new(px(380.), px(460.)),
            })),
            app_id: Some("beskar-notifications".to_string()),
            window_background: WindowBackgroundAppearance::Transparent,
            kind: WindowKind::LayerShell(LayerShellOptions {
                namespace: "beskar-notifications".to_string(),
                layer: Layer::Overlay,
                anchor: LayerAnchor::TOP | LayerAnchor::RIGHT,
                exclusive_zone: None,
                margin: Some((px(48.), px(16.), px(0.), px(0.))),
                keyboard_interactivity: KeyboardInteractivity::None,
                ..Default::default()
            }),
            focus: false,
            ..Default::default()
        };

        if let Ok(handle) = cx.open_window(options, move |_window, cx| {
            cx.new(|_cx| NotificationToastQueueView)
        }) {
            *guard = Some(handle.into());
            info!("Opened dedicated LayerShell Notification Toast Queue window");
        }
    }
}

pub struct NotificationToastQueueView;

impl Render for NotificationToastQueueView {
    fn render(&mut self, window: &mut Window, _cx: &mut Context<Self>) -> impl IntoElement {
        let notifs = {
            let guard = NOTIFICATION_QUEUE.lock().unwrap();
            guard.clone()
        };

        if notifs.is_empty() {
            forget_notification_overlay();
            window.remove_window();
            return div();
        }

        div()
            .w(px(380.0))
            .flex()
            .flex_col()
            .gap(px(8.0))
            .children(notifs.into_iter().take(4).map(|n| {
                NotificationToastWidget::new(n)
                    .on_dismiss(|id| {
                        beskar_services::notifications::dismiss(id);
                    })
                    .on_invoke(|id, key| {
                        beskar_services::notifications::invoke(id, &key);
                    })
            }))
    }
}

/// Dedicated View for Fullscreen Lock Screen
pub struct LockScreenView {
    user_name: String,
    time_str: String,
    date_str: String,
    password: String,
    has_error: bool,
    focus_handle: FocusHandle,
    close_tx: tokio::sync::mpsc::UnboundedSender<()>,
}

impl LockScreenView {
    pub fn new(cx: &mut Context<Self>) -> Self {
        let user_name = std::env::var("USER").unwrap_or_else(|_| "User".to_string());
        let now = chrono::Local::now();
        let time_str = now.format("%-I:%M %p").to_string();
        let date_str = now.format("%A, %B %-d").to_string();
        let focus_handle = cx.focus_handle();
        let (close_tx, mut close_rx) = tokio::sync::mpsc::unbounded_channel::<()>();

        // 1. Overlay close listener
        cx.spawn(async move |_this, cx| {
            while let Some(()) = close_rx.recv().await {
                cx.update(|cx| {
                    close_active_overlay(cx);
                });
            }
        })
        .detach();

        // 2. Real-time Clock loop (updates time while locked)
        cx.spawn(async move |this, cx| {
            loop {
                let _ = cx
                    .background_executor()
                    .timer(std::time::Duration::from_secs(1))
                    .await;
                let now = chrono::Local::now();
                let time = now.format("%-I:%M %p").to_string();
                let date = now.format("%A, %B %-d").to_string();
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

        Self {
            user_name,
            time_str,
            date_str,
            password: String::new(),
            has_error: false,
            focus_handle,
            close_tx,
        }
    }
}

impl Focusable for LockScreenView {
    fn focus_handle(&self, _cx: &App) -> FocusHandle {
        self.focus_handle.clone()
    }
}

impl Render for LockScreenView {
    fn render(&mut self, _window: &mut Window, cx: &mut Context<Self>) -> impl IntoElement {
        let tx = self.close_tx.clone();
        let cancel_tx = self.close_tx.clone();

        div()
            .size_full()
            .track_focus(&self.focus_handle)
            .on_key_down(cx.listener(move |this, event: &KeyDownEvent, _window, cx| {
                let key = event.keystroke.key.as_str();
                match key {
                    "escape" => {
                        if !this.password.is_empty() {
                            this.password.clear();
                            this.has_error = false;
                            cx.notify();
                        } else {
                            let _ = this.close_tx.send(());
                        }
                        cx.stop_propagation();
                    }
                    "backspace" => {
                        this.password.pop();
                        this.has_error = false;
                        cx.notify();
                        cx.stop_propagation();
                    }
                    "enter" | "return" => {
                        let pwd = this.password.clone();
                        if pwd.is_empty() {
                            let _ = this.close_tx.send(());
                        } else {
                            cx.spawn(async move |this, cx| {
                                let ok = cx
                                    .background_executor()
                                    .spawn(async move { beskar_services::verify_password(&pwd) })
                                    .await;

                                let _ = this.update(cx, |this, cx| match ok {
                                    Ok(true) => {
                                        let _ = this.close_tx.send(());
                                    }
                                    _ => {
                                        this.has_error = true;
                                        this.password.clear();
                                        cx.notify();
                                    }
                                });
                            })
                            .detach();
                        }
                        cx.stop_propagation();
                    }
                    _ => {
                        if key.chars().count() == 1 {
                            let ch = key.chars().next().unwrap();
                            if !ch.is_control() {
                                this.password.push(ch);
                                this.has_error = false;
                                cx.notify();
                                cx.stop_propagation();
                            }
                        }
                    }
                }
            }))
            .child(
                LockScreenWidget::new(&self.user_name, &self.time_str, &self.date_str)
                    .password_len(self.password.len())
                    .error(self.has_error)
                    .on_unlock_attempt(move |_pwd| {
                        let _ = tx.send(());
                    })
                    .on_cancel(move || {
                        let _ = cancel_tx.send(());
                    }),
            )
    }
}

#[derive(Debug, Clone)]
enum ClipboardMsg {
    Select(usize),
    Copy(String),
    Delete(String),
    ClearAll,
    ClearQuery,
    Close,
}

pub struct ClipboardView {
    query: String,
    items: Vec<ClipboardEntry>,
    selected_idx: usize,
    focus_handle: FocusHandle,
    msg_tx: tokio::sync::mpsc::UnboundedSender<ClipboardMsg>,
}

impl ClipboardView {
    pub fn new(cx: &mut Context<Self>) -> Self {
        let items = beskar_services::ClipboardService::list_history(50);
        let focus_handle = cx.focus_handle();
        let (msg_tx, mut msg_rx) = tokio::sync::mpsc::unbounded_channel::<ClipboardMsg>();

        cx.spawn(async move |this, cx| {
            while let Some(msg) = msg_rx.recv().await {
                let _ = this.update(cx, |this, cx| match msg {
                    ClipboardMsg::Select(idx) => {
                        this.selected_idx = idx;
                        cx.notify();
                    }
                    ClipboardMsg::Copy(id) => {
                        beskar_services::ClipboardService::copy_item(&id);
                        beskar_services::SoundService::play_volume_change();
                        close_active_overlay(cx);
                    }
                    ClipboardMsg::Delete(line) => {
                        beskar_services::ClipboardService::delete_item(&line);
                        this.items = beskar_services::ClipboardService::list_history(50);
                        this.selected_idx = this.selected_idx.min(this.items.len().saturating_sub(1));
                        cx.notify();
                    }
                    ClipboardMsg::ClearAll => {
                        beskar_services::ClipboardService::clear_history();
                        this.items.clear();
                        this.selected_idx = 0;
                        cx.notify();
                    }
                    ClipboardMsg::ClearQuery => {
                        this.query.clear();
                        this.selected_idx = 0;
                        cx.notify();
                    }
                    ClipboardMsg::Close => {
                        close_active_overlay(cx);
                    }
                });
            }
        })
        .detach();

        Self {
            query: String::new(),
            items,
            selected_idx: 0,
            focus_handle,
            msg_tx,
        }
    }
}

impl Focusable for ClipboardView {
    fn focus_handle(&self, _cx: &App) -> FocusHandle {
        self.focus_handle.clone()
    }
}

impl Render for ClipboardView {
    fn render(&mut self, _window: &mut Window, cx: &mut Context<Self>) -> impl IntoElement {
        let tx_sel = self.msg_tx.clone();
        let tx_cp = self.msg_tx.clone();
        let tx_del = self.msg_tx.clone();
        let tx_cp_key = self.msg_tx.clone();
        let tx_del_key = self.msg_tx.clone();
        let tx_clr = self.msg_tx.clone();
        let tx_clrq = self.msg_tx.clone();
        let tx_close = self.msg_tx.clone();

        div()
            .id("clipboard-backdrop")
            .size_full()
            .flex()
            .flex_col()
            .items_center()
            .pt(px(80.0))
            .track_focus(&self.focus_handle)
            .key_context("Clipboard")
            .on_mouse_down(MouseButton::Left, move |_, window, _cx| {
                forget_overlay(OverlayKind::Clipboard);
                window.remove_window();
            })
            .on_key_down(cx.listener(move |this, event: &KeyDownEvent, window, cx| {
                let key = event.keystroke.key.as_str();
                let mods = &event.keystroke.modifiers;

                match key {
                    "escape" => {
                        if !this.query.is_empty() {
                            this.query.clear();
                            this.selected_idx = 0;
                            cx.notify();
                        } else {
                            forget_overlay(OverlayKind::Clipboard);
                            window.remove_window();
                        }
                        cx.stop_propagation();
                    }
                    "up" => {
                        this.selected_idx = this.selected_idx.saturating_sub(1);
                        cx.notify();
                        cx.stop_propagation();
                    }
                    "down" => {
                        let filtered = ClipboardWidget::filter_items(&this.items, &this.query);
                        this.selected_idx =
                            (this.selected_idx + 1).min(filtered.len().saturating_sub(1));
                        cx.notify();
                        cx.stop_propagation();
                    }
                    "enter" | "return" => {
                        let filtered = ClipboardWidget::filter_items(&this.items, &this.query);
                        if let Some(item) = filtered.get(this.selected_idx) {
                            let id = item.id.clone();
                            let _ = tx_cp_key.send(ClipboardMsg::Copy(id));
                        }
                        cx.stop_propagation();
                    }
                    "delete" => {
                        let filtered = ClipboardWidget::filter_items(&this.items, &this.query);
                        if let Some(item) = filtered.get(this.selected_idx) {
                            let line = item.full_line.clone();
                            let _ = tx_del_key.send(ClipboardMsg::Delete(line));
                        }
                        cx.stop_propagation();
                    }
                    "backspace" => {
                        this.query.pop();
                        this.selected_idx = 0;
                        cx.notify();
                        cx.stop_propagation();
                    }
                    "space" if !mods.control && !mods.alt && !mods.platform => {
                        this.query.push(' ');
                        this.selected_idx = 0;
                        cx.notify();
                        cx.stop_propagation();
                    }
                    _ => {
                        if key.chars().count() == 1 && !mods.control && !mods.alt && !mods.platform {
                            let ch = key.chars().next().unwrap();
                            if !ch.is_control() {
                                this.query.push(ch);
                                this.selected_idx = 0;
                                cx.notify();
                                cx.stop_propagation();
                            }
                        }
                    }
                }
            }))
            .child(
                div()
                    .w(px(640.0))
                    .on_mouse_down(MouseButton::Left, |_, _, cx| {
                        cx.stop_propagation();
                    })
                    .child(
                        ClipboardWidget::new(self.items.clone())
                            .query(&self.query)
                            .selected_idx(self.selected_idx)
                            .on_select(move |idx| {
                                let _ = tx_sel.send(ClipboardMsg::Select(idx));
                            })
                            .on_copy(move |id| {
                                let _ = tx_cp.send(ClipboardMsg::Copy(id));
                            })
                            .on_delete(move |line| {
                                let _ = tx_del.send(ClipboardMsg::Delete(line));
                            })
                            .on_clear_all(move || {
                                let _ = tx_clr.send(ClipboardMsg::ClearAll);
                            })
                            .on_clear_query(move || {
                                let _ = tx_clrq.send(ClipboardMsg::ClearQuery);
                            })
                            .on_close(move || {
                                let _ = tx_close.send(ClipboardMsg::Close);
                            }),
                    ),
            )
    }
}

// ============================================================================
// Developer Dashboard View
// ============================================================================

#[derive(Debug, Clone)]
enum DashboardMsg {
    RefreshGithub,
    RefreshUpdates,
    RunUpdate,
    OpenProfile,
    Close,
}

pub struct DashboardView {
    github_state: beskar_services::GithubState,
    updates_state: beskar_services::SystemUpdatesState,
    focus_handle: FocusHandle,
    msg_tx: tokio::sync::mpsc::UnboundedSender<DashboardMsg>,
}

impl DashboardView {
    pub fn new(cx: &mut Context<Self>) -> Self {
        let focus_handle = cx.focus_handle();
        let (msg_tx, mut msg_rx) = tokio::sync::mpsc::unbounded_channel::<DashboardMsg>();

        let user = std::env::var("USER").unwrap_or_else(|_| "developer".to_string());
        let github_state = beskar_services::GithubService::get_or_load(&user);
        let updates_state = beskar_services::UpdateService::cached();

        cx.spawn(async move |this, cx| {
            while let Some(msg) = msg_rx.recv().await {
                match msg {
                    DashboardMsg::RefreshGithub => {
                        let user_clone = user.clone();
                        let state = cx
                            .background_executor()
                            .spawn(async move {
                                beskar_services::GithubService::fetch_github_profile_and_contributions(
                                    &user_clone,
                                )
                                .await
                            })
                            .await;
                        let _ = this.update(cx, |this, cx| {
                            this.github_state = state;
                            cx.notify();
                        });
                    }
                    DashboardMsg::RefreshUpdates => {
                        let state = cx
                            .background_executor()
                            .spawn(async move {
                                beskar_services::UpdateService::check_system_updates().await
                            })
                            .await;
                        let _ = this.update(cx, |this, cx| {
                            this.updates_state = state;
                            cx.notify();
                        });
                    }
                    DashboardMsg::RunUpdate => {
                        cx.background_executor()
                            .spawn(async move {
                                beskar_services::UpdateService::run_system_update();
                            })
                            .detach();
                    }
                    DashboardMsg::OpenProfile => {
                        let _ = std::process::Command::new("xdg-open")
                            .arg("https://github.com")
                            .spawn();
                    }
                    DashboardMsg::Close => {
                        let _ = this.update(cx, |_, cx| {
                            close_active_overlay(cx);
                        });
                    }
                }
            }
        })
        .detach();

        Self {
            github_state,
            updates_state,
            focus_handle,
            msg_tx,
        }
    }
}

impl Focusable for DashboardView {
    fn focus_handle(&self, _cx: &App) -> FocusHandle {
        self.focus_handle.clone()
    }
}

impl Render for DashboardView {
    fn render(&mut self, _window: &mut Window, cx: &mut Context<Self>) -> impl IntoElement {
        let tx_gh = self.msg_tx.clone();
        let tx_up = self.msg_tx.clone();
        let tx_run = self.msg_tx.clone();
        let tx_prof = self.msg_tx.clone();
        let tx_close = self.msg_tx.clone();

        div()
            .id("dashboard-backdrop")
            .size_full()
            .flex()
            .flex_col()
            .items_center()
            .pt(px(60.0))
            .track_focus(&self.focus_handle)
            .key_context("DashboardView")
            .on_mouse_down(MouseButton::Left, move |_, window, _cx| {
                forget_overlay(OverlayKind::Dashboard);
                window.remove_window();
            })
            .on_key_down(cx.listener(|_this, event: &KeyDownEvent, window, cx| {
                if event.keystroke.key == "escape" {
                    forget_overlay(OverlayKind::Dashboard);
                    window.remove_window();
                    cx.stop_propagation();
                }
            }))
            .child(
                div()
                    .on_mouse_down(MouseButton::Left, |_, _, cx| {
                        cx.stop_propagation();
                    })
                    .child(
                        DashboardWidget::new(self.github_state.clone(), self.updates_state.clone())
                            .on_refresh_github(move || {
                                let _ = tx_gh.send(DashboardMsg::RefreshGithub);
                            })
                            .on_refresh_updates(move || {
                                let _ = tx_up.send(DashboardMsg::RefreshUpdates);
                            })
                            .on_run_update(move || {
                                let _ = tx_run.send(DashboardMsg::RunUpdate);
                            })
                            .on_open_profile(move || {
                                let _ = tx_prof.send(DashboardMsg::OpenProfile);
                            })
                            .on_close(move || {
                                let _ = tx_close.send(DashboardMsg::Close);
                            }),
                    ),
            )
    }
}

// ============================================================================
// Dedicated Music Player View
// ============================================================================

#[derive(Debug, Clone)]
enum MusicMsg {
    PlayPause,
    Prev,
    Next,
    Seek(f32),
    ToggleLoop,
    ToggleShuffle,
    Close,
}

pub struct MusicPlayerView {
    title: String,
    artist: String,
    album: Option<String>,
    player_name: String,
    is_playing: bool,
    position_secs: u32,
    duration_secs: u32,
    cava_bars: Vec<u8>,
    is_looping: bool,
    is_shuffling: bool,
    focus_handle: FocusHandle,
    msg_tx: tokio::sync::mpsc::UnboundedSender<MusicMsg>,
}

impl MusicPlayerView {
    pub fn new(cx: &mut Context<Self>) -> Self {
        let focus_handle = cx.focus_handle();
        let (msg_tx, mut msg_rx) = tokio::sync::mpsc::unbounded_channel::<MusicMsg>();

        let media = beskar_services::MprisService::read_state();
        let title = media
            .as_ref()
            .and_then(|m| m.title.clone())
            .unwrap_or_else(|| "No Media Playing".to_string());
        let artist = media
            .as_ref()
            .and_then(|m| m.artist.clone())
            .unwrap_or_else(|| "Idle Audio Service".to_string());
        let album = media.as_ref().and_then(|m| m.album.clone());
        let player_name = media
            .as_ref()
            .map(|m| m.player_name.clone())
            .unwrap_or_else(|| "MPRIS".to_string());
        let is_playing = media.as_ref().map(|m| m.is_playing).unwrap_or(false);
        let duration_secs = media
            .as_ref()
            .map(|m| (m.duration_ms / 1000) as u32)
            .unwrap_or(215);
        let position_secs = media
            .as_ref()
            .map(|m| (m.position_ms / 1000) as u32)
            .unwrap_or(45);

        // Responsive spectrum bars animation loop
        cx.spawn(async move |this, cx| {
            let mut tick: u32 = 0;
            loop {
                tokio::time::sleep(tokio::time::Duration::from_millis(80)).await;
                tick = tick.wrapping_add(1);

                let polled_media = if tick.is_multiple_of(12) {
                    beskar_services::MprisService::read_state()
                } else {
                    None
                };

                let generated_bars: Vec<u8> = if is_playing
                    || polled_media.as_ref().is_some_and(|m| m.is_playing)
                {
                    (0..32)
                        .map(|i| {
                            let phase = (tick as f32 * 0.18 + i as f32 * 0.35).sin().abs();
                            let harmonic = (tick as f32 * 0.28 + i as f32 * 0.55).cos().abs();
                            ((phase * 50.0 + harmonic * 40.0 + 8.0).min(99.0)) as u8
                        })
                        .collect()
                } else {
                    (0..32).map(|_| 4).collect()
                };

                let res = this.update(cx, |this, cx| {
                    if let Some(ref m) = polled_media {
                        this.title = m
                            .title
                            .clone()
                            .unwrap_or_else(|| "No Media Playing".to_string());
                        this.artist = m
                            .artist
                            .clone()
                            .unwrap_or_else(|| "Idle Audio Service".to_string());
                        this.player_name = m.player_name.clone();
                        this.is_playing = m.is_playing;
                    }
                    this.cava_bars = generated_bars;
                    cx.notify();
                });
                if res.is_err() {
                    break;
                }
            }
        })
        .detach();

        cx.spawn(async move |this, cx| {
            while let Some(msg) = msg_rx.recv().await {
                match msg {
                    MusicMsg::PlayPause => {
                        beskar_services::MprisService::play_pause();
                    }
                    MusicMsg::Prev => {
                        beskar_services::MprisService::previous();
                    }
                    MusicMsg::Next => {
                        beskar_services::MprisService::next();
                    }
                    MusicMsg::Seek(fraction) => {
                        let _ = std::process::Command::new("playerctl")
                            .args(["position", &format!("{:.1}", fraction * 200.0)])
                            .spawn();
                    }
                    MusicMsg::ToggleLoop => {
                        let _ = this.update(cx, |this, cx| {
                            this.is_looping = !this.is_looping;
                            cx.notify();
                        });
                    }
                    MusicMsg::ToggleShuffle => {
                        let _ = this.update(cx, |this, cx| {
                            this.is_shuffling = !this.is_shuffling;
                            cx.notify();
                        });
                    }
                    MusicMsg::Close => {
                        let _ = this.update(cx, |_, cx| {
                            close_active_overlay(cx);
                        });
                    }
                }
            }
        })
        .detach();

        Self {
            title,
            artist,
            album,
            player_name,
            is_playing,
            position_secs,
            duration_secs,
            cava_bars: (0..32).map(|_| 6).collect(),
            is_looping: false,
            is_shuffling: false,
            focus_handle,
            msg_tx,
        }
    }
}

impl Focusable for MusicPlayerView {
    fn focus_handle(&self, _cx: &App) -> FocusHandle {
        self.focus_handle.clone()
    }
}

impl Render for MusicPlayerView {
    fn render(&mut self, _window: &mut Window, cx: &mut Context<Self>) -> impl IntoElement {
        let tx_pp = self.msg_tx.clone();
        let tx_prev = self.msg_tx.clone();
        let tx_next = self.msg_tx.clone();
        let tx_seek = self.msg_tx.clone();
        let tx_loop = self.msg_tx.clone();
        let tx_shuf = self.msg_tx.clone();
        let tx_close = self.msg_tx.clone();

        div()
            .id("music-player-backdrop")
            .size_full()
            .flex()
            .flex_col()
            .items_center()
            .pt(px(60.0))
            .track_focus(&self.focus_handle)
            .key_context("MusicPlayerView")
            .on_mouse_down(MouseButton::Left, move |_, window, _cx| {
                forget_overlay(OverlayKind::Music);
                window.remove_window();
            })
            .on_key_down(cx.listener(|_this, event: &KeyDownEvent, window, cx| {
                if event.keystroke.key == "escape" {
                    forget_overlay(OverlayKind::Music);
                    window.remove_window();
                    cx.stop_propagation();
                }
            }))
            .child(
                div()
                    .on_mouse_down(MouseButton::Left, |_, _, cx| {
                        cx.stop_propagation();
                    })
                    .child(
                        MusicPlayerWidget::new(self.title.clone(), self.artist.clone(), self.is_playing)
                            .album(self.album.clone())
                            .player_name(self.player_name.clone())
                            .position(self.position_secs, self.duration_secs)
                            .cava_bars(self.cava_bars.clone())
                            .loop_mode(self.is_looping)
                            .shuffle(self.is_shuffling)
                            .on_play_pause(move || {
                                let _ = tx_pp.send(MusicMsg::PlayPause);
                            })
                            .on_prev(move || {
                                let _ = tx_prev.send(MusicMsg::Prev);
                            })
                            .on_next(move || {
                                let _ = tx_next.send(MusicMsg::Next);
                            })
                            .on_seek(move |frac| {
                                let _ = tx_seek.send(MusicMsg::Seek(frac));
                            })
                            .on_toggle_loop(move || {
                                let _ = tx_loop.send(MusicMsg::ToggleLoop);
                            })
                            .on_toggle_shuffle(move || {
                                let _ = tx_shuf.send(MusicMsg::ToggleShuffle);
                            })
                            .on_close(move || {
                                let _ = tx_close.send(MusicMsg::Close);
                            }),
                    ),
            )
    }
}

// ============================================================================
// Notification Center View
// ============================================================================

#[derive(Debug, Clone)]
enum NotifCenterMsg {
    Dismiss(u32),
    ClearAll,
    ToggleDnd,
    Close,
}

pub struct NotificationCenterView {
    notifications: Vec<NotificationItem>,
    is_dnd: bool,
    focus_handle: FocusHandle,
    msg_tx: tokio::sync::mpsc::UnboundedSender<NotifCenterMsg>,
}

impl NotificationCenterView {
    pub fn new(cx: &mut Context<Self>) -> Self {
        let focus_handle = cx.focus_handle();
        let (msg_tx, mut msg_rx) = tokio::sync::mpsc::unbounded_channel::<NotifCenterMsg>();
        let notifications = beskar_services::notifications::get_notifications();

        cx.spawn(async move |this, cx| {
            while let Some(msg) = msg_rx.recv().await {
                match msg {
                    NotifCenterMsg::Dismiss(id) => {
                        beskar_services::notifications::dismiss(id);
                        let _ = this.update(cx, |this, cx| {
                            this.notifications.retain(|n| n.id != id);
                            cx.notify();
                        });
                    }
                    NotifCenterMsg::ClearAll => {
                        beskar_services::notifications::clear_all();
                        let _ = this.update(cx, |this, cx| {
                            this.notifications.clear();
                            cx.notify();
                        });
                    }
                    NotifCenterMsg::ToggleDnd => {
                        let _ = this.update(cx, |this, cx| {
                            this.is_dnd = !this.is_dnd;
                            cx.notify();
                        });
                    }
                    NotifCenterMsg::Close => {
                        let _ = this.update(cx, |_, cx| {
                            close_active_overlay(cx);
                        });
                    }
                }
            }
        })
        .detach();

        Self {
            notifications,
            is_dnd: false,
            focus_handle,
            msg_tx,
        }
    }
}

impl Focusable for NotificationCenterView {
    fn focus_handle(&self, _cx: &App) -> FocusHandle {
        self.focus_handle.clone()
    }
}

impl Render for NotificationCenterView {
    fn render(&mut self, _window: &mut Window, cx: &mut Context<Self>) -> impl IntoElement {
        let tx_d = self.msg_tx.clone();
        let tx_c = self.msg_tx.clone();
        let tx_dnd = self.msg_tx.clone();
        let tx_close = self.msg_tx.clone();

        div()
            .id("notification-center-backdrop")
            .size_full()
            .flex()
            .justify_end()
            .pt(px(56.0))
            .pr(px(16.0))
            .track_focus(&self.focus_handle)
            .key_context("NotificationCenterView")
            .on_mouse_down(MouseButton::Left, move |_, window, _cx| {
                forget_overlay(OverlayKind::NotificationCenter);
                window.remove_window();
            })
            .on_key_down(cx.listener(|_this, event: &KeyDownEvent, window, cx| {
                if event.keystroke.key == "escape" {
                    forget_overlay(OverlayKind::NotificationCenter);
                    window.remove_window();
                    cx.stop_propagation();
                }
            }))
            .child(
                div()
                    .w(px(380.0))
                    .on_mouse_down(MouseButton::Left, |_, _, cx| {
                        cx.stop_propagation();
                    })
                    .child(
                        NotificationCenterWidget::new(self.notifications.clone())
                            .dnd(self.is_dnd)
                            .on_dismiss(move |id| {
                                let _ = tx_d.send(NotifCenterMsg::Dismiss(id));
                            })
                            .on_clear_all(move || {
                                let _ = tx_c.send(NotifCenterMsg::ClearAll);
                            })
                            .on_toggle_dnd(move || {
                                let _ = tx_dnd.send(NotifCenterMsg::ToggleDnd);
                            })
                            .on_close(move || {
                                let _ = tx_close.send(NotifCenterMsg::Close);
                            }),
                    ),
            )
    }
}

// ============================================================================
// Screen Capture View
// ============================================================================

#[derive(Debug, Clone)]
enum ScreenCapMsg {
    Trigger(CaptureMode),
    Close,
}

pub struct ScreenCaptureView {
    is_recording: bool,
    focus_handle: FocusHandle,
    msg_tx: tokio::sync::mpsc::UnboundedSender<ScreenCapMsg>,
}

impl ScreenCaptureView {
    pub fn new(cx: &mut Context<Self>) -> Self {
        let focus_handle = cx.focus_handle();
        let check = std::process::Command::new("pidof")
            .arg("wf-recorder")
            .output();
        let is_recording = check.map(|o| o.status.success()).unwrap_or(false);
        let (msg_tx, mut msg_rx) = tokio::sync::mpsc::unbounded_channel::<ScreenCapMsg>();

        cx.spawn(async move |_this, cx| {
            while let Some(msg) = msg_rx.recv().await {
                match msg {
                    ScreenCapMsg::Trigger(mode) => {
                        cx.update(|cx| {
                            close_active_overlay(cx);
                        });
                        std::thread::spawn(move || {
                            std::thread::sleep(std::time::Duration::from_millis(200));
                            mode.execute();
                        });
                    }
                    ScreenCapMsg::Close => {
                        cx.update(|cx| {
                            close_active_overlay(cx);
                        });
                    }
                }
            }
        })
        .detach();

        Self {
            is_recording,
            focus_handle,
            msg_tx,
        }
    }
}

impl Focusable for ScreenCaptureView {
    fn focus_handle(&self, _cx: &App) -> FocusHandle {
        self.focus_handle.clone()
    }
}

impl Render for ScreenCaptureView {
    fn render(&mut self, _window: &mut Window, cx: &mut Context<Self>) -> impl IntoElement {
        let tx_trig = self.msg_tx.clone();
        let tx_close = self.msg_tx.clone();

        div()
            .id("screen-capture-backdrop")
            .size_full()
            .flex()
            .flex_col()
            .items_center()
            .pt(px(80.0))
            .track_focus(&self.focus_handle)
            .key_context("ScreenCaptureView")
            .on_mouse_down(MouseButton::Left, move |_, window, _cx| {
                forget_overlay(OverlayKind::ScreenCapture);
                window.remove_window();
            })
            .on_key_down(cx.listener(|_this, event: &KeyDownEvent, window, cx| {
                if event.keystroke.key == "escape" {
                    forget_overlay(OverlayKind::ScreenCapture);
                    window.remove_window();
                    cx.stop_propagation();
                }
            }))
            .child(
                div()
                    .on_mouse_down(MouseButton::Left, |_, _, cx| {
                        cx.stop_propagation();
                    })
                    .child(
                        ScreenCaptureWidget::new()
                            .recording(self.is_recording)
                            .on_trigger(move |mode| {
                                let _ = tx_trig.send(ScreenCapMsg::Trigger(mode));
                            })
                            .on_close(move || {
                                let _ = tx_close.send(ScreenCapMsg::Close);
                            }),
                    ),
            )
    }
}

// ============================================================================
// Wallpaper Selector View
// ============================================================================

#[derive(Debug, Clone)]
enum WallpaperMsg {
    Select(std::path::PathBuf),
    Close,
}

pub struct WallpaperSelectorView {
    wallpapers: Vec<WallpaperItem>,
    query: String,
    focus_handle: FocusHandle,
    msg_tx: tokio::sync::mpsc::UnboundedSender<WallpaperMsg>,
}

impl WallpaperSelectorView {
    pub fn new(cx: &mut Context<Self>) -> Self {
        let focus_handle = cx.focus_handle();
        let wallpapers = WallpaperSelectorWidget::discover_wallpapers();
        let (msg_tx, mut msg_rx) = tokio::sync::mpsc::unbounded_channel::<WallpaperMsg>();

        cx.spawn(async move |this, cx| {
            while let Some(msg) = msg_rx.recv().await {
                match msg {
                    WallpaperMsg::Select(path) => {
                        let path_str = path.to_string_lossy().to_string();
                        let _ = std::process::Command::new("swww")
                            .args(["img", &path_str, "--transition-type", "wipe"])
                            .spawn();
                        let _ = std::process::Command::new("feh")
                            .args(["--bg-fill", &path_str])
                            .spawn();

                        let _ = this.update(cx, |_, cx| {
                            close_active_overlay(cx);
                        });
                    }
                    WallpaperMsg::Close => {
                        let _ = this.update(cx, |_, cx| {
                            close_active_overlay(cx);
                        });
                    }
                }
            }
        })
        .detach();

        Self {
            wallpapers,
            query: String::new(),
            focus_handle,
            msg_tx,
        }
    }
}

impl Focusable for WallpaperSelectorView {
    fn focus_handle(&self, _cx: &App) -> FocusHandle {
        self.focus_handle.clone()
    }
}

impl Render for WallpaperSelectorView {
    fn render(&mut self, _window: &mut Window, cx: &mut Context<Self>) -> impl IntoElement {
        let tx_sel = self.msg_tx.clone();
        let tx_close = self.msg_tx.clone();

        div()
            .id("wallpaper-selector-backdrop")
            .size_full()
            .flex()
            .flex_col()
            .items_center()
            .pt(px(60.0))
            .track_focus(&self.focus_handle)
            .key_context("WallpaperSelectorView")
            .on_mouse_down(MouseButton::Left, move |_, window, _cx| {
                forget_overlay(OverlayKind::WallpaperSelector);
                window.remove_window();
            })
            .on_key_down(cx.listener(|this, event: &KeyDownEvent, window, cx| {
                if event.keystroke.key == "escape" {
                    if !this.query.is_empty() {
                        this.query.clear();
                        cx.notify();
                    } else {
                        forget_overlay(OverlayKind::WallpaperSelector);
                        window.remove_window();
                    }
                    cx.stop_propagation();
                }
            }))
            .child(
                div()
                    .w(px(720.0))
                    .on_mouse_down(MouseButton::Left, |_, _, cx| {
                        cx.stop_propagation();
                    })
                    .child(
                        WallpaperSelectorWidget::new(self.wallpapers.clone())
                            .query(&self.query)
                            .on_select(move |path| {
                                let _ = tx_sel.send(WallpaperMsg::Select(path));
                            })
                            .on_close(move || {
                                let _ = tx_close.send(WallpaperMsg::Close);
                            }),
                    ),
            )
    }
}


