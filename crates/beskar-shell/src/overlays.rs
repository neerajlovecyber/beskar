use beskar_core::models::{AppItem, NotificationItem};
use beskar_services::audio::AudioService;
use beskar_services::battery::BatteryService;
use beskar_ui::{
    ControlCenterWidget, LauncherWidget, LockScreenWidget, NotificationToastWidget,
    PowerAction, PowerMenuWidget, SettingsCategory, SettingsConfig, SettingsWidget,
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
            size: Size::new(px(700.), px(480.)),
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
            size: Size::new(px(380.), px(72.)),
        })),
        app_id: Some("beskar-power-menu".to_string()),
        window_background: WindowBackgroundAppearance::Transparent,
        kind: WindowKind::LayerShell(LayerShellOptions {
            namespace: "beskar-power-menu".to_string(),
            layer: Layer::Overlay,
            anchor: LayerAnchor::TOP,
            exclusive_zone: None,
            margin: Some((px(56.), px(0.), px(0.), px(0.))),
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
            margin: Some((px(56.), px(12.), px(0.), px(0.))),
            keyboard_interactivity: KeyboardInteractivity::Exclusive,
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

/// Toggle the Preferences / Settings window.
pub fn toggle_settings(cx: &mut App) {
    if close_active_overlay(cx) == Some(OverlayKind::Settings) {
        return;
    }

    let options = WindowOptions {
        titlebar: None,
        window_bounds: Some(WindowBounds::Windowed(Bounds {
            origin: point(px(0.), px(0.)),
            size: Size::new(px(760.), px(520.)),
        })),
        app_id: Some("beskar-settings".to_string()),
        window_background: WindowBackgroundAppearance::Transparent,
        kind: WindowKind::LayerShell(LayerShellOptions {
            namespace: "beskar-settings".to_string(),
            layer: Layer::Overlay,
            anchor: LayerAnchor::TOP,
            exclusive_zone: None,
            margin: Some((px(60.), px(0.), px(0.), px(0.))),
            keyboard_interactivity: KeyboardInteractivity::Exclusive,
            ..Default::default()
        }),
        focus: true,
        ..Default::default()
    };

    if let Ok(handle) = cx.open_window(options, move |_window, cx| {
        cx.new(|cx| SettingsView::new(cx))
    }) {
        let mut guard = ACTIVE_OVERLAY.lock().unwrap();
        *guard = Some((OverlayKind::Settings, handle.into()));
        info!("Opened dedicated LayerShell Settings preferences overlay window");
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

impl Render for LauncherView {
    fn render(&mut self, window: &mut Window, cx: &mut Context<Self>) -> impl IntoElement {
        if !self.focus_handle.is_focused(window) {
            self.focus_handle.focus(window, cx);
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

impl Render for PowerMenuView {
    fn render(&mut self, window: &mut Window, cx: &mut Context<Self>) -> impl IntoElement {
        if !self.focus_handle.is_focused(window) {
            self.focus_handle.focus(window, cx);
        }

        let tx_sel = self.msg_tx.clone();
        let tx_req = self.msg_tx.clone();
        let tx_cancel = self.msg_tx.clone();
        let tx_conf_sel = self.msg_tx.clone();
        let tx_act = self.msg_tx.clone();
        let tx_close = self.msg_tx.clone();
        let msg_tx = self.msg_tx.clone();

        div()
            .size_full()
            .flex()
            .items_center()
            .justify_center()
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

#[derive(Debug, Clone)]
enum ControlCenterMsg {
    ToggleWifi,
    ToggleBluetooth,
    ChangeVolume(i32),
    ToggleMute,
    OpenLauncher,
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
    is_wifi_on: bool,
    wifi_ssid: Option<String>,
    is_bt_on: bool,
    focus_handle: FocusHandle,
    msg_tx: tokio::sync::mpsc::UnboundedSender<ControlCenterMsg>,
}

impl ControlCenterView {
    pub fn new(cx: &mut Context<Self>) -> Self {
        let aud = AudioService::read_state();
        let bat = BatteryService::new().read_state();
        let (is_wifi_on, wifi_ssid) = beskar_services::NetworkHelper::get_wifi_status();
        let is_bt_on = beskar_services::BluetoothHelper::get_bluetooth_status();
        let focus_handle = cx.focus_handle();
        let (msg_tx, mut msg_rx) = tokio::sync::mpsc::unbounded_channel::<ControlCenterMsg>();

        cx.spawn(async move |this, cx| {
            while let Some(msg) = msg_rx.recv().await {
                let _ = this.update(cx, |this, cx| match msg {
                    ControlCenterMsg::ToggleWifi => {
                        beskar_services::NetworkHelper::toggle_wifi(this.is_wifi_on);
                        this.is_wifi_on = !this.is_wifi_on;
                        if !this.is_wifi_on {
                            this.wifi_ssid = None;
                        } else {
                            let (_, ssid) = beskar_services::NetworkHelper::get_wifi_status();
                            this.wifi_ssid = ssid;
                        }
                        cx.notify();
                    }
                    ControlCenterMsg::ToggleBluetooth => {
                        beskar_services::BluetoothHelper::toggle_bluetooth(this.is_bt_on);
                        this.is_bt_on = !this.is_bt_on;
                        cx.notify();
                    }
                    ControlCenterMsg::ChangeVolume(delta) => {
                        beskar_services::AudioService::set_volume(delta);
                        let new_vol = (this.volume_percent as i32 + delta).clamp(0, 100) as u8;
                        this.volume_percent = new_vol;
                        cx.notify();
                    }
                    ControlCenterMsg::ToggleMute => {
                        beskar_services::AudioService::toggle_mute();
                        this.is_muted = !this.is_muted;
                        cx.notify();
                    }
                    ControlCenterMsg::OpenLauncher => {
                        close_active_overlay(cx);
                        toggle_launcher(cx);
                    }
                    ControlCenterMsg::OpenPower => {
                        close_active_overlay(cx);
                        toggle_power_menu(cx);
                    }
                    ControlCenterMsg::OpenSettings => {
                        close_active_overlay(cx);
                        toggle_settings(cx);
                    }
                    ControlCenterMsg::Close => {
                        close_active_overlay(cx);
                    }
                });
            }
        })
        .detach();

        Self {
            volume_percent: (aud.volume * 100.0).round() as u8,
            battery_percent: bat.percentage.round() as u8,
            is_muted: aud.is_muted,
            is_charging: bat.is_charging,
            is_wifi_on,
            wifi_ssid,
            is_bt_on,
            focus_handle,
            msg_tx,
        }
    }
}

impl Render for ControlCenterView {
    fn render(&mut self, window: &mut Window, cx: &mut Context<Self>) -> impl IntoElement {
        if !self.focus_handle.is_focused(window) {
            self.focus_handle.focus(window, cx);
        }

        let tx_vol = self.msg_tx.clone();
        let tx_mute = self.msg_tx.clone();
        let tx_wifi = self.msg_tx.clone();
        let tx_bt = self.msg_tx.clone();
        let tx_launcher = self.msg_tx.clone();
        let tx_power = self.msg_tx.clone();
        let tx_settings = self.msg_tx.clone();
        let tx_close = self.msg_tx.clone();

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
                    .wifi(self.is_wifi_on, self.wifi_ssid.clone())
                    .bluetooth(self.is_bt_on)
                    .on_volume_change(move |delta| {
                        let _ = tx_vol.send(ControlCenterMsg::ChangeVolume(delta));
                    })
                    .on_toggle_mute(move || {
                        let _ = tx_mute.send(ControlCenterMsg::ToggleMute);
                    })
                    .on_toggle_wifi(move || {
                        let _ = tx_wifi.send(ControlCenterMsg::ToggleWifi);
                    })
                    .on_toggle_bluetooth(move || {
                        let _ = tx_bt.send(ControlCenterMsg::ToggleBluetooth);
                    })
                    .on_open_launcher(move || {
                        let _ = tx_launcher.send(ControlCenterMsg::OpenLauncher);
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
                        cx.notify();
                    }
                    SettingsMsg::ToggleWindowTitle(val) => {
                        this.config.show_active_window_title = val;
                        cx.notify();
                    }
                    SettingsMsg::ToggleMedia(val) => {
                        this.config.morph_on_media = val;
                        cx.notify();
                    }
                    SettingsMsg::SelectAccent(idx) => {
                        this.config.accent_color_idx = idx;
                        cx.notify();
                    }
                    SettingsMsg::SelectPreset(preset) => {
                        beskar_theme::ThemeEngine::set_preset(preset);
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

impl Render for SettingsView {
    fn render(&mut self, window: &mut Window, cx: &mut Context<Self>) -> impl IntoElement {
        if !self.focus_handle.is_focused(window) {
            self.focus_handle.focus(window, cx);
        }

        let tx_cat = self.msg_tx.clone();
        let tx_notch = self.msg_tx.clone();
        let tx_win = self.msg_tx.clone();
        let tx_media = self.msg_tx.clone();
        let tx_accent = self.msg_tx.clone();
        let tx_preset = self.msg_tx.clone();
        let tx_test = self.msg_tx.clone();
        let tx_close = self.msg_tx.clone();

        div()
            .size_full()
            .flex()
            .items_center()
            .justify_center()
            .track_focus(&self.focus_handle)
            .on_key_down(cx.listener(|_, event: &KeyDownEvent, window, cx| {
                if event.keystroke.key == "escape" {
                    forget_overlay(OverlayKind::Settings);
                    window.remove_window();
                    cx.stop_propagation();
                }
            }))
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
                let _ = cx.update(|cx| {
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

impl Render for LockScreenView {
    fn render(&mut self, window: &mut Window, cx: &mut Context<Self>) -> impl IntoElement {
        if !self.focus_handle.is_focused(window) {
            self.focus_handle.focus(window, cx);
        }

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

