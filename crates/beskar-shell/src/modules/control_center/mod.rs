use beskar_services::audio::AudioService;
use beskar_services::battery::BatteryService;
use beskar_ui::ControlCenterWidget;
use gpui_kit::component::slider::{SliderEvent, SliderState};
use gpui_kit::*;

use crate::panel_host::{PanelHost, PanelModule};

#[derive(Debug, Clone)]
enum ControlCenterMsg {
    ToggleWifi,
    ToggleBluetooth,
    ChangeVolume(i32),
    SetVolumePercent(u8),
    ToggleMute,
    ChangeBrightness(i32),
    SetBrightnessPercent(u8),
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
    volume_slider: Entity<SliderState>,
    brightness_slider: Entity<SliderState>,
    _subscriptions: Vec<Subscription>,
    focus_handle: FocusHandle,
    msg_tx: tokio::sync::mpsc::UnboundedSender<ControlCenterMsg>,
}

impl PanelModule for ControlCenterView {
    const ID: &'static str = "control_center";

    fn build(cx: &mut Context<Self>) -> Self {
        Self::new(cx)
    }
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
        let bus = beskar_services::HardwareBus::new_linux();

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
                        let this_weak = this.clone();
                        let bus_clone = bus.clone();
                        cx.spawn(async move |cx| {
                            let _ = bus_clone.set_wifi_power(next_state).await;
                            if next_state {
                                let (_, ssid) = bus_clone.get_wifi_state().await;
                                let _ = this_weak.update(cx, |this, cx| {
                                    this.wifi_ssid = ssid;
                                    cx.notify();
                                });
                            }
                        })
                        .detach();
                    }
                    ControlCenterMsg::ToggleBluetooth => {
                        let is_on = this.update(cx, |t, _| t.is_bt_on).unwrap_or(true);
                        let next_state = !is_on;
                        let _ = this.update(cx, |this, cx| {
                            this.is_bt_on = next_state;
                            cx.notify();
                        });
                        let bus_clone = bus.clone();
                        tokio::spawn(async move {
                            let _ = bus_clone.set_bluetooth_power(next_state).await;
                        });
                    }
                    ControlCenterMsg::ChangeVolume(delta) => {
                        let _ = this.update(cx, |this, cx| {
                            let new_vol = (this.volume_percent as i32 + delta).clamp(0, 100) as u8;
                            this.volume_percent = new_vol;
                            this.is_muted = false;
                            cx.notify();
                        });
                        let bus_clone = bus.clone();
                        tokio::spawn(async move {
                            let _ = bus_clone.set_audio_volume(delta).await;
                        });
                    }
                    ControlCenterMsg::SetVolumePercent(pct) => {
                        let _ = this.update(cx, |this, cx| {
                            this.volume_percent = pct;
                            this.is_muted = false;
                            cx.notify();
                        });
                        let bus_clone = bus.clone();
                        tokio::spawn(async move {
                            let _ = bus_clone.set_audio_volume_percent(pct).await;
                        });
                    }
                    ControlCenterMsg::ToggleMute => {
                        let _ = this.update(cx, |this, cx| {
                            this.is_muted = !this.is_muted;
                            cx.notify();
                        });
                        let bus_clone = bus.clone();
                        tokio::spawn(async move {
                            let _ = bus_clone.toggle_audio_mute().await;
                        });
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
                        let bus_clone = bus.clone();
                        tokio::spawn(async move {
                            let _ = bus_clone.set_brightness(new_bright).await;
                        });
                    }
                    ControlCenterMsg::SetBrightnessPercent(pct) => {
                        let _ = this.update(cx, |this, cx| {
                            this.brightness_percent = pct;
                            cx.notify();
                        });
                        let bus_clone = bus.clone();
                        tokio::spawn(async move {
                            let _ = bus_clone.set_brightness(pct).await;
                        });
                    }
                    ControlCenterMsg::SetPowerProfile(prof) => {
                        let prof_clone = prof.clone();
                        let _ = this.update(cx, |this, cx| {
                            this.active_power_profile = prof;
                            cx.notify();
                        });
                        let bus_clone = bus.clone();
                        tokio::spawn(async move {
                            let _ = bus_clone.set_power_profile(&prof_clone).await;
                        });
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
                            let this_weak = this.clone();
                            let bus_clone = bus.clone();
                            cx.spawn(async move |cx| {
                                let networks = bus_clone.scan_wifi_networks().await;
                                let _ = this_weak.update(cx, |this, cx| {
                                    this.wifi_networks = networks;
                                    cx.notify();
                                });
                            })
                            .detach();
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
                            let this_weak = this.clone();
                            let bus_clone = bus.clone();
                            cx.spawn(async move |cx| {
                                let devices = bus_clone.list_bluetooth_devices().await;
                                let _ = this_weak.update(cx, |this, cx| {
                                    this.bt_devices = devices;
                                    cx.notify();
                                });
                            })
                            .detach();
                        }
                    }
                    ControlCenterMsg::ConnectWifi(ssid) => {
                        let _ = this.update(cx, |this, cx| {
                            this.wifi_ssid = Some(ssid.clone());
                            cx.notify();
                        });
                        let bus_clone = bus.clone();
                        tokio::spawn(async move {
                            let _ = bus_clone.connect_wifi(&ssid, None).await;
                        });
                    }
                    ControlCenterMsg::OpenLauncher => {
                        let _ = this.update(cx, |_, cx| {
                            PanelHost::toggle_by_id("launcher", cx);
                        });
                    }
                    ControlCenterMsg::OpenClipboard => {
                        let _ = this.update(cx, |_, cx| {
                            PanelHost::toggle_by_id("clipboard", cx);
                        });
                    }
                    ControlCenterMsg::OpenPower => {
                        let _ = this.update(cx, |_, cx| {
                            PanelHost::toggle_by_id("power_menu", cx);
                        });
                    }
                    ControlCenterMsg::OpenSettings => {
                        let _ = this.update(cx, |_, cx| {
                            PanelHost::toggle_by_id("settings", cx);
                        });
                    }
                    ControlCenterMsg::Close => {
                        let _ = this.update(cx, |_, cx| {
                            PanelHost::close(cx);
                        });
                    }
                }
            }
        })
        .detach();

        let vol_initial = (aud.volume * 100.0).round().clamp(0.0, 100.0);
        let volume_slider = cx.new(|_| {
            SliderState::new()
                .min(0.0)
                .max(100.0)
                .step(1.0)
                .default_value(vol_initial)
        });

        let brightness_slider = cx.new(|_| {
            SliderState::new()
                .min(5.0)
                .max(100.0)
                .step(1.0)
                .default_value(brightness_percent.clamp(5, 100) as f32)
        });

        let sub_vol = {
            let tx = msg_tx.clone();
            cx.subscribe(&volume_slider, move |this, _, event: &SliderEvent, cx| {
                let val = match event {
                    SliderEvent::Change(v) | SliderEvent::Release(v) => v.end(),
                };
                let pct = val.round().clamp(0.0, 100.0) as u8;
                if this.volume_percent != pct {
                    this.volume_percent = pct;
                    this.is_muted = false;
                    let _ = tx.send(ControlCenterMsg::SetVolumePercent(pct));
                    cx.notify();
                }
            })
        };

        let sub_bright = {
            let tx = msg_tx.clone();
            cx.subscribe(&brightness_slider, move |this, _, event: &SliderEvent, cx| {
                let val = match event {
                    SliderEvent::Change(v) | SliderEvent::Release(v) => v.end(),
                };
                let pct = val.round().clamp(5.0, 100.0) as u8;
                if this.brightness_percent != pct {
                    this.brightness_percent = pct;
                    let _ = tx.send(ControlCenterMsg::SetBrightnessPercent(pct));
                    cx.notify();
                }
            })
        };

        Self {
            volume_percent: vol_initial as u8,
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
            volume_slider,
            brightness_slider,
            _subscriptions: vec![sub_vol, sub_bright],
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
                PanelHost::forget(ControlCenterView::ID);
                window.remove_window();
            })
            .on_key_down(cx.listener(|_, event: &KeyDownEvent, window, cx| {
                if event.keystroke.key == "escape" {
                    PanelHost::forget(ControlCenterView::ID);
                    window.remove_window();
                    cx.stop_propagation();
                }
            }))
            .child(
                div()
                    .id("cc-outer-scroll")
                    .w(px(380.0))
                    .max_h(px(760.0))
                    .overflow_y_scroll()
                    .pb(px(8.0))
                    .on_mouse_down(MouseButton::Left, |_, _, cx| {
                        cx.stop_propagation();
                    })
                    .child(
                        ControlCenterWidget::new(self.volume_percent, self.battery_percent)
                            .volume_slider(self.volume_slider.clone())
                            .brightness_slider(self.brightness_slider.clone())
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
