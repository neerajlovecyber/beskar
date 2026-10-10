use beskar_core::models::AppItem;
use beskar_services::audio::AudioService;
use beskar_services::battery::BatteryService;
use beskar_ui::{
    ControlCenterWidget, LauncherWidget, LockScreenWidget, PowerAction, PowerMenuWidget,
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
            size: Size::new(px(640.), px(460.)),
        })),
        app_id: Some("beskar-launcher".to_string()),
        window_background: WindowBackgroundAppearance::Transparent,
        kind: WindowKind::LayerShell(LayerShellOptions {
            namespace: "beskar-launcher".to_string(),
            layer: Layer::Overlay,
            anchor: LayerAnchor::TOP,
            exclusive_zone: None,
            margin: Some((px(100.), px(0.), px(0.), px(0.))),
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
            size: Size::new(px(356.), px(64.)),
        })),
        app_id: Some("beskar-power-menu".to_string()),
        window_background: WindowBackgroundAppearance::Transparent,
        kind: WindowKind::LayerShell(LayerShellOptions {
            namespace: "beskar-power-menu".to_string(),
            layer: Layer::Overlay,
            anchor: LayerAnchor::TOP,
            exclusive_zone: None,
            margin: Some((px(64.), px(0.), px(0.), px(0.))),
            keyboard_interactivity: KeyboardInteractivity::Exclusive,
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
                        this.selected_idx = idx;
                        cx.notify();
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

impl Render for LauncherView {
    fn render(&mut self, window: &mut Window, cx: &mut Context<Self>) -> impl IntoElement {
        if window.focused(cx).as_ref() != Some(&self.focus_handle) {
            window.focus(&self.focus_handle, cx);
        }

        let tx_sel = self.msg_tx.clone();
        let tx_launch = self.msg_tx.clone();
        let tx_clear = self.msg_tx.clone();
        let tx_close = self.msg_tx.clone();

        div()
            .size_full()
            .track_focus(&self.focus_handle)
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
                        } else if !mods.alt && !mods.platform {
                            if event.keystroke.key.chars().count() == 1 {
                                let ch = event.keystroke.key.chars().next().unwrap();
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
                            this.selected_index = idx;
                            cx.notify();
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
                            this.confirm_index = idx;
                            cx.notify();
                        }
                        PowerMenuMsg::Action(action) => {
                            let cmd = action.default_command();
                            let _ = std::process::Command::new("sh").args(["-c", cmd]).spawn();
                            close_active_overlay(cx);
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
            .size_full()
            .track_focus(&self.focus_handle)
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
                    "left" => {
                        if this.pending_action.is_some() {
                            this.confirm_index = 0;
                        } else {
                            this.selected_index = this.selected_index.saturating_sub(1);
                        }
                        cx.notify();
                        cx.stop_propagation();
                    }
                    "right" => {
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

