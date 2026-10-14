pub mod bt_list;
pub mod footer;
pub mod header;
pub mod power_profiles;
pub mod quick_toggles;
pub mod sliders;
pub mod wifi_list;

use std::sync::Arc;
use beskar_services::audio::AudioService;
use beskar_services::battery::BatteryService;
use gpui_kit::component::slider::{SliderEvent, SliderState};
use gpui_kit::prelude::FluentBuilder;
use gpui_kit::*;

use crate::modules::clipboard::ClipboardView;
use crate::modules::launcher::LauncherView;
use crate::modules::power_menu::PowerMenuView;
use crate::modules::settings::SettingsView;
use crate::panel_host::{PanelHost, PanelModule};

#[allow(dead_code)]
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
    SelectAudioSink(String),
    ToggleWifiList,
    ToggleBtList,
    ConnectWifi(String),
    OpenLauncher,
    OpenClipboard,
    OpenPower,
    OpenSettings,
    Close,
}

/// Fully autonomous, self-contained Control Center module view.
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
    sinks: Vec<beskar_services::AudioSinkItem>,
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
        let focus_handle = cx.focus_handle();
        let (msg_tx, mut msg_rx) = tokio::sync::mpsc::unbounded_channel::<ControlCenterMsg>();
        let bus = beskar_services::HardwareBus::new_linux();
        let bus_init = bus.clone();

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
                            this.volume_percent = (this.volume_percent as i32 + delta).clamp(0, 100) as u8;
                            this.is_muted = false;
                            cx.notify();
                        });
                        let bus_clone = bus.clone();
                        tokio::spawn(async move { let _ = bus_clone.set_audio_volume(delta).await; });
                    }
                    ControlCenterMsg::SetVolumePercent(pct) => {
                        let _ = this.update(cx, |this, cx| {
                            this.volume_percent = pct;
                            this.is_muted = false;
                            cx.notify();
                        });
                        let bus_clone = bus.clone();
                        tokio::spawn(async move { let _ = bus_clone.set_audio_volume_percent(pct).await; });
                    }
                    ControlCenterMsg::ToggleMute => {
                        let _ = this.update(cx, |this, cx| {
                            this.is_muted = !this.is_muted;
                            cx.notify();
                        });
                        let bus_clone = bus.clone();
                        tokio::spawn(async move { let _ = bus_clone.toggle_audio_mute().await; });
                    }
                    ControlCenterMsg::SelectAudioSink(sink_name) => {
                        let this_weak = this.clone();
                        cx.spawn(async move |cx| {
                            let sinks = tokio::task::spawn_blocking(move || {
                                beskar_services::AudioService::set_default_sink(&sink_name);
                                beskar_services::AudioService::list_sinks()
                            }).await.unwrap_or_default();
                            let _ = this_weak.update(cx, |this, cx| {
                                this.sinks = sinks;
                                cx.notify();
                            });
                        }).detach();
                    }
                    ControlCenterMsg::ChangeBrightness(delta) => {
                        let new_bright = this.update(cx, |t, _| (t.brightness_percent as i32 + delta).clamp(5, 100) as u8).unwrap_or(50);
                        let _ = this.update(cx, |this, cx| {
                            this.brightness_percent = new_bright;
                            cx.notify();
                        });
                        let bus_clone = bus.clone();
                        tokio::spawn(async move { let _ = bus_clone.set_brightness(new_bright).await; });
                    }
                    ControlCenterMsg::SetBrightnessPercent(pct) => {
                        let _ = this.update(cx, |this, cx| {
                            this.brightness_percent = pct;
                            cx.notify();
                        });
                        let bus_clone = bus.clone();
                        tokio::spawn(async move { let _ = bus_clone.set_brightness(pct).await; });
                    }
                    ControlCenterMsg::SetPowerProfile(prof) => {
                        let prof_clone = prof.clone();
                        let _ = this.update(cx, |this, cx| {
                            this.active_power_profile = prof;
                            cx.notify();
                        });
                        let bus_clone = bus.clone();
                        tokio::spawn(async move { let _ = bus_clone.set_power_profile(&prof_clone).await; });
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
                        let bus_clone = bus.clone();
                        let this_weak = this.clone();
                        cx.spawn(async move |cx| {
                            let _ = bus_clone.connect_wifi(&ssid, None).await;
                            let (_, active_ssid) = bus_clone.get_wifi_state().await;
                            let _ = this_weak.update(cx, |this, cx| {
                                this.wifi_ssid = active_ssid;
                                this.show_wifi_list = false;
                                cx.notify();
                            });
                        })
                        .detach();
                    }
                    ControlCenterMsg::OpenLauncher => { let _ = this.update(cx, |_, cx| PanelHost::toggle::<LauncherView>(cx)); }
                    ControlCenterMsg::OpenClipboard => { let _ = this.update(cx, |_, cx| PanelHost::toggle::<ClipboardView>(cx)); }
                    ControlCenterMsg::OpenPower => { let _ = this.update(cx, |_, cx| PanelHost::toggle::<PowerMenuView>(cx)); }
                    ControlCenterMsg::OpenSettings => { let _ = this.update(cx, |_, cx| PanelHost::toggle::<SettingsView>(cx)); }
                    ControlCenterMsg::Close => { let _ = this.update(cx, |_, cx| PanelHost::close(cx)); }
                }
            }
        })
        .detach();

        cx.spawn(async move |this, cx| {
            let (vol, muted) = bus_init.get_audio_volume().await;
            let (is_wifi, ssid) = bus_init.get_wifi_state().await;
            let is_bt = bus_init.get_bluetooth_state().await;
            let bright = bus_init.get_brightness().await;
            let profile = bus_init.get_power_profile().await;
            let bat = tokio::task::spawn_blocking(|| BatteryService::new().read_state())
                .await
                .unwrap_or_default();
            let sinks = tokio::task::spawn_blocking(AudioService::list_sinks)
                .await
                .unwrap_or_default();

            let _ = this.update(cx, |this, cx| {
                this.volume_percent = vol;
                this.is_muted = muted;
                this.is_wifi_on = is_wifi;
                this.wifi_ssid = ssid;
                this.is_bt_on = is_bt;
                this.brightness_percent = bright;
                this.active_power_profile = profile;
                this.battery_percent = bat.percentage.round() as u8;
                this.is_charging = bat.is_charging;
                this.sinks = sinks;
                this.volume_slider = Self::make_volume_slider(vol as f32, cx, this.msg_tx.clone(), &mut this._subscriptions);
                this.brightness_slider = Self::make_brightness_slider(bright as f32, cx, this.msg_tx.clone(), &mut this._subscriptions);
                cx.notify();
            });
        })
        .detach();

        let mut subs = Vec::new();
        let volume_slider = Self::make_volume_slider(80.0, cx, msg_tx.clone(), &mut subs);
        let brightness_slider = Self::make_brightness_slider(100.0, cx, msg_tx.clone(), &mut subs);

        Self {
            volume_percent: 80,
            battery_percent: 100,
            is_muted: false,
            is_charging: false,
            brightness_percent: 100,
            active_power_profile: "balanced".to_string(),
            is_wifi_on: true,
            wifi_ssid: None,
            is_bt_on: false,
            sinks: Vec::new(),
            wifi_networks: Vec::new(),
            bt_devices: Vec::new(),
            show_wifi_list: false,
            show_bt_list: false,
            volume_slider,
            brightness_slider,
            _subscriptions: subs,
            focus_handle,
            msg_tx,
        }
    }

    fn make_volume_slider(val: f32, cx: &mut Context<Self>, tx: tokio::sync::mpsc::UnboundedSender<ControlCenterMsg>, subs: &mut Vec<Subscription>) -> Entity<SliderState> {
        let slider = cx.new(|_| SliderState::new().min(0.0).max(100.0).step(1.0).default_value(val));
        subs.push(cx.subscribe(&slider, move |_this, _slider, event: &SliderEvent, _cx| {
            let v = match event { SliderEvent::Change(v) | SliderEvent::Release(v) => v.end() };
            let _ = tx.send(ControlCenterMsg::SetVolumePercent(v.round().clamp(0.0, 100.0) as u8));
        }));
        slider
    }

    fn make_brightness_slider(val: f32, cx: &mut Context<Self>, tx: tokio::sync::mpsc::UnboundedSender<ControlCenterMsg>, subs: &mut Vec<Subscription>) -> Entity<SliderState> {
        let slider = cx.new(|_| SliderState::new().min(5.0).max(100.0).step(1.0).default_value(val.clamp(5.0, 100.0)));
        subs.push(cx.subscribe(&slider, move |_this, _slider, event: &SliderEvent, _cx| {
            let v = match event { SliderEvent::Change(v) | SliderEvent::Release(v) => v.end() };
            let _ = tx.send(ControlCenterMsg::SetBrightnessPercent(v.round().clamp(5.0, 100.0) as u8));
        }));
        slider
    }
}

impl Render for ControlCenterView {
    fn render(&mut self, _window: &mut Window, cx: &mut Context<Self>) -> impl IntoElement {
        let tx = self.msg_tx.clone();
        let (tx_wifi, tx_bt, tx_mute, tx_prof) = (tx.clone(), tx.clone(), tx.clone(), tx.clone());
        let (tx_wlist, tx_blist, tx_conn, tx_sink) = (tx.clone(), tx.clone(), tx.clone(), tx.clone());
        let (tx_launcher, tx_clipboard, tx_power, tx_settings, tx_close) =
            (tx.clone(), tx.clone(), tx.clone(), tx.clone(), tx.clone());
        let (tx_backdrop, tx_esc) = (tx.clone(), tx);

        let wifi_label = self.wifi_ssid.clone().unwrap_or_else(|| {
            if self.is_wifi_on {
                "Wi-Fi On".into()
            } else {
                "Wi-Fi Off".into()
            }
        });

        let bt_label = if self.is_bt_on {
            "Bluetooth On"
        } else {
            "Bluetooth Off"
        };

        div()
            .id("control-center-backdrop")
            .size_full()
            .flex()
            .justify_end()
            .pt(px(56.0))
            .pr(px(16.0))
            .track_focus(&self.focus_handle)
            .key_context("ControlCenter")
            .on_mouse_down(MouseButton::Left, move |_, _, _| {
                let _ = tx_backdrop.send(ControlCenterMsg::Close);
            })
            .on_key_down(cx.listener(move |_, event: &KeyDownEvent, _, cx| {
                if event.keystroke.key == "escape" {
                    let _ = tx_esc.send(ControlCenterMsg::Close);
                    cx.stop_propagation();
                }
            }))
            .child(
                div()
                    .id("cc-outer-scroll")
                    .w(px(390.0))
                    .max_h(px(760.0))
                    .overflow_y_scroll()
                    .pb(px(8.0))
                    .on_mouse_down(MouseButton::Left, |_, _, cx| {
                        cx.stop_propagation();
                    })
                    .child(
                        div()
                            .w(px(390.0))
                            .p(px(16.0))
                            .rounded(px(20.0))
                            .bg(beskar_theme::Theme::card_bg())
                            .border_1()
                            .border_color(beskar_theme::Theme::card_border())
                            .shadow_xl()
                            .flex()
                            .flex_col()
                            .gap(px(12.0))
                            // 1. Header
                            .child(header::render_header(Some(Arc::new(move || {
                                let _ = tx_close.send(ControlCenterMsg::Close);
                            }))))
                            // 2. Quick Toggles Grid
                            .child(quick_toggles::render_quick_toggles(
                                self.is_wifi_on,
                                wifi_label,
                                self.show_wifi_list,
                                Some(Arc::new(move || {
                                    let _ = tx_wifi.send(ControlCenterMsg::ToggleWifi);
                                })),
                                Some(Arc::new(move || {
                                    let _ = tx_wlist.send(ControlCenterMsg::ToggleWifiList);
                                })),
                                self.is_bt_on,
                                bt_label,
                                self.show_bt_list,
                                Some(Arc::new(move || {
                                    let _ = tx_bt.send(ControlCenterMsg::ToggleBluetooth);
                                })),
                                Some(Arc::new(move || {
                                    let _ = tx_blist.send(ControlCenterMsg::ToggleBtList);
                                })),
                            ))
                            // 3. Expandable Wi-Fi List
                            .when(self.show_wifi_list, |parent| {
                                parent.child(wifi_list::render_wifi_list(
                                    &self.wifi_networks,
                                    Some(Arc::new(move |ssid| {
                                        let _ = tx_conn.send(ControlCenterMsg::ConnectWifi(ssid));
                                    })),
                                ))
                            })
                            // 4. Expandable Bluetooth List
                            .when(self.show_bt_list, |parent| {
                                parent.child(bt_list::render_bt_list(&self.bt_devices))
                            })
                            // 5. Volume Slider & Output Sink Selector
                            .child(sliders::render_volume_card(
                                self.volume_percent,
                                self.is_muted,
                                Some(&self.volume_slider),
                                Some(Arc::new(move || {
                                    let _ = tx_mute.send(ControlCenterMsg::ToggleMute);
                                })),
                                &self.sinks,
                                Some(Arc::new(move |sink_name| {
                                    let _ = tx_sink.send(ControlCenterMsg::SelectAudioSink(sink_name));
                                })),
                            ))
                            // 6. Brightness Slider
                            .child(sliders::render_brightness_card(
                                self.brightness_percent,
                                Some(&self.brightness_slider),
                            ))
                            // 7. Power Profile Selector
                            .child(power_profiles::render_power_profiles(
                                &self.active_power_profile,
                                Some(Arc::new(move |prof| {
                                    let _ = tx_prof.send(ControlCenterMsg::SetPowerProfile(prof));
                                })),
                            ))
                            // 8. Battery Vitals
                            .child(power_profiles::render_battery_card(
                                self.battery_percent,
                                self.is_charging,
                            ))
                            // 9. Quick Actions Footer
                            .child(footer::render_footer(
                                Some(Arc::new(move || {
                                    let _ = tx_launcher.send(ControlCenterMsg::OpenLauncher);
                                })),
                                Some(Arc::new(move || {
                                    let _ = tx_clipboard.send(ControlCenterMsg::OpenClipboard);
                                })),
                                Some(Arc::new(move || {
                                    let _ = tx_settings.send(ControlCenterMsg::OpenSettings);
                                })),
                                Some(Arc::new(move || {
                                    let _ = tx_power.send(ControlCenterMsg::OpenPower);
                                })),
                            )),
                    ),
            )
    }
}
