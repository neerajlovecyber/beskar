pub mod bt_list;
pub mod details;
pub mod footer;
pub mod header;
pub mod power_profiles;
pub mod quick_toggles;
pub mod satellite_host;
pub mod sliders;
pub mod wifi_list;

use beskar_services::audio::AudioService;
use beskar_services::battery::BatteryService;
use chrono::Datelike;
use gpui_kit::component::slider::{SliderEvent, SliderState};
use gpui_kit::prelude::FluentBuilder;
use gpui_kit::*;
use std::sync::Arc;

use crate::modules::clipboard::ClipboardView;
use crate::modules::launcher::LauncherView;
use crate::modules::power_menu::PowerMenuView;
use crate::modules::settings::SettingsView;
use crate::panel_host::{PanelEdge, PanelHost, PanelModule, Slot};

#[allow(dead_code)]
#[derive(Debug, Clone)]
enum ControlCenterMsg {
    ToggleWifi,
    ToggleBluetooth,
    ToggleNightLight,
    ToggleCaffeine,
    ToggleGameMode,
    ToggleMicMute,
    SetMicPercent(u8),
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
    ToggleSatellite(crate::satellite::SatelliteId),
    CloseSatellite(crate::satellite::SatelliteId),
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
    is_night_light_on: bool,
    is_caffeine_on: bool,
    is_game_mode_on: bool,
    is_mic_muted: bool,
    mic_percent: u8,
    volume_slider: Entity<SliderState>,
    brightness_slider: Entity<SliderState>,
    mic_slider: Entity<SliderState>,
    satellite: crate::satellite::Satellite,
    _subscriptions: Vec<Subscription>,
    focus_handle: FocusHandle,
    msg_tx: tokio::sync::mpsc::UnboundedSender<ControlCenterMsg>,
}

impl PanelModule for ControlCenterView {
    const ID: &'static str = "control_center";

    fn slot() -> Slot {
        Slot::Right
    }

    fn panel_edge() -> PanelEdge {
        PanelEdge::Right
    }

    fn size() -> Size<Pixels> {
        Size::new(px(400.0), px(440.0))
    }

    fn build(cx: &mut Context<Self>) -> Self {
        Self::new(cx)
    }

    fn initial_focus_handle(&self, _cx: &App) -> Option<FocusHandle> {
        Some(self.focus_handle.clone())
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
                    ControlCenterMsg::ToggleNightLight => {
                        let _ = this.update(cx, |this, cx| {
                            this.is_night_light_on = !this.is_night_light_on;
                            cx.notify();
                        });
                    }
                    ControlCenterMsg::ToggleCaffeine => {
                        let _ = this.update(cx, |this, cx| {
                            this.is_caffeine_on = !this.is_caffeine_on;
                            cx.notify();
                        });
                    }
                    ControlCenterMsg::ToggleGameMode => {
                        let _ = this.update(cx, |this, cx| {
                            this.is_game_mode_on = !this.is_game_mode_on;
                            cx.notify();
                        });
                    }
                    ControlCenterMsg::ToggleMicMute => {
                        let _ = this.update(cx, |this, cx| {
                            this.is_mic_muted = !this.is_mic_muted;
                            cx.notify();
                        });
                    }
                    ControlCenterMsg::SetMicPercent(pct) => {
                        let _ = this.update(cx, |this, cx| {
                            this.mic_percent = pct;
                            cx.notify();
                        });
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
                            this.volume_percent =
                                (this.volume_percent as i32 + delta).clamp(0, 100) as u8;
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
                    ControlCenterMsg::SelectAudioSink(sink_name) => {
                        let this_weak = this.clone();
                        cx.spawn(async move |cx| {
                            let sinks = tokio::task::spawn_blocking(move || {
                                beskar_services::AudioService::set_default_sink(&sink_name);
                                beskar_services::AudioService::list_sinks()
                            })
                            .await
                            .unwrap_or_default();
                            let _ = this_weak.update(cx, |this, cx| {
                                this.sinks = sinks;
                                cx.notify();
                            });
                        })
                        .detach();
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
                    ControlCenterMsg::ToggleSatellite(id) => {
                        let will_open = this
                            .update(cx, |this, _| {
                                !this.satellite.contains(&id) || !this.satellite.open()
                            })
                            .unwrap_or(false);

                        if will_open {
                            match &id {
                                crate::satellite::SatelliteId::Wifi => {
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
                                crate::satellite::SatelliteId::Bluetooth => {
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
                                _ => {}
                            }
                        }

                        let _ = this.update(cx, |this, cx| {
                            let side = this.satellite.next_side(&id);
                            this.satellite.transition(
                                id,
                                will_open,
                                std::time::Duration::from_millis(180),
                                side,
                            );
                            cx.notify();
                        });
                    }
                    ControlCenterMsg::CloseSatellite(id) => {
                        let _ = this.update(cx, |this, cx| {
                            let side = this.satellite.next_side(&id);
                            this.satellite.transition(
                                id,
                                false,
                                std::time::Duration::from_millis(130),
                                side,
                            );
                            cx.notify();
                        });
                    }
                    ControlCenterMsg::OpenLauncher => {
                        let _ = this.update(cx, |_, cx| PanelHost::toggle::<LauncherView>(cx));
                    }
                    ControlCenterMsg::OpenClipboard => {
                        let _ = this.update(cx, |_, cx| PanelHost::toggle::<ClipboardView>(cx));
                    }
                    ControlCenterMsg::OpenPower => {
                        let _ = this.update(cx, |_, cx| PanelHost::toggle::<PowerMenuView>(cx));
                    }
                    ControlCenterMsg::OpenSettings => {
                        let _ = this.update(cx, |_, cx| PanelHost::toggle::<SettingsView>(cx));
                    }
                    ControlCenterMsg::Close => {
                        let _ = this.update(cx, |_, cx| {
                            PanelHost::close_by_id(ControlCenterView::ID, cx)
                        });
                    }
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
                this.volume_slider = Self::make_volume_slider(
                    vol as f32,
                    cx,
                    this.msg_tx.clone(),
                    &mut this._subscriptions,
                );
                this.brightness_slider = Self::make_brightness_slider(
                    bright as f32,
                    cx,
                    this.msg_tx.clone(),
                    &mut this._subscriptions,
                );
                this.mic_slider = Self::make_mic_slider(
                    100.0,
                    cx,
                    this.msg_tx.clone(),
                    &mut this._subscriptions,
                );
                cx.notify();
            });
        })
        .detach();

        let mut subs = Vec::new();
        let volume_slider = Self::make_volume_slider(80.0, cx, msg_tx.clone(), &mut subs);
        let brightness_slider = Self::make_brightness_slider(100.0, cx, msg_tx.clone(), &mut subs);
        let mic_slider = Self::make_mic_slider(100.0, cx, msg_tx.clone(), &mut subs);

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
            is_night_light_on: false,
            is_caffeine_on: false,
            is_game_mode_on: false,
            is_mic_muted: false,
            mic_percent: 100,
            volume_slider,
            brightness_slider,
            mic_slider,
            satellite: crate::satellite::Satellite::new(),
            _subscriptions: subs,
            focus_handle,
            msg_tx,
        }
    }

    fn make_volume_slider(
        val: f32,
        cx: &mut Context<Self>,
        tx: tokio::sync::mpsc::UnboundedSender<ControlCenterMsg>,
        subs: &mut Vec<Subscription>,
    ) -> Entity<SliderState> {
        let slider = cx.new(|_| {
            SliderState::new()
                .min(0.0)
                .max(100.0)
                .step(1.0)
                .default_value(val)
        });
        subs.push(
            cx.subscribe(&slider, move |_this, _slider, event: &SliderEvent, _cx| {
                let v = match event {
                    SliderEvent::Change(v) | SliderEvent::Release(v) => v.end(),
                };
                let _ = tx.send(ControlCenterMsg::SetVolumePercent(
                    v.round().clamp(0.0, 100.0) as u8,
                ));
            }),
        );
        slider
    }

    fn make_mic_slider(
        val: f32,
        cx: &mut Context<Self>,
        tx: tokio::sync::mpsc::UnboundedSender<ControlCenterMsg>,
        subs: &mut Vec<Subscription>,
    ) -> Entity<SliderState> {
        let slider = cx.new(|_| {
            SliderState::new()
                .min(0.0)
                .max(100.0)
                .step(1.0)
                .default_value(val.clamp(0.0, 100.0))
        });
        subs.push(
            cx.subscribe(&slider, move |_this, _slider, event: &SliderEvent, _cx| {
                let v = match event {
                    SliderEvent::Change(v) | SliderEvent::Release(v) => v.end(),
                };
                let _ = tx.send(ControlCenterMsg::SetMicPercent(
                    v.round().clamp(0.0, 100.0) as u8,
                ));
            }),
        );
        slider
    }

    fn make_brightness_slider(
        val: f32,
        cx: &mut Context<Self>,
        tx: tokio::sync::mpsc::UnboundedSender<ControlCenterMsg>,
        subs: &mut Vec<Subscription>,
    ) -> Entity<SliderState> {
        let slider = cx.new(|_| {
            SliderState::new()
                .min(5.0)
                .max(100.0)
                .step(1.0)
                .default_value(val.clamp(5.0, 100.0))
        });
        subs.push(
            cx.subscribe(&slider, move |_this, _slider, event: &SliderEvent, _cx| {
                let v = match event {
                    SliderEvent::Change(v) | SliderEvent::Release(v) => v.end(),
                };
                let _ = tx.send(ControlCenterMsg::SetBrightnessPercent(
                    v.round().clamp(5.0, 100.0) as u8,
                ));
            }),
        );
        slider
    }
}

impl Render for ControlCenterView {
    fn render(&mut self, _window: &mut Window, cx: &mut Context<Self>) -> impl IntoElement {
        let tx = self.msg_tx.clone();
        let (tx_wifi, tx_bt, tx_mute, tx_prof) = (tx.clone(), tx.clone(), tx.clone(), tx.clone());
        let (tx_night, tx_caffeine, tx_game, tx_mic_mute) = (tx.clone(), tx.clone(), tx.clone(), tx.clone());
        let (tx_wlist, tx_blist, tx_conn, _tx_sink) =
            (tx.clone(), tx.clone(), tx.clone(), tx.clone());
        let (_tx_launcher, _tx_clipboard, _tx_power, _tx_settings, tx_close) =
            (tx.clone(), tx.clone(), tx.clone(), tx.clone(), tx.clone());
        let tx_esc = tx;

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
            .id("control-center-outer")
            .w(px(400.0))
            .max_h(px(440.0))
            .overflow_y_scroll()
            .pb(px(8.0))
            .track_focus(&self.focus_handle)
            .key_context("ControlCenter")
            .on_key_down(cx.listener(move |this, event: &KeyDownEvent, _, cx| {
                if event.keystroke.key == "escape" {
                    if this.satellite.open() {
                        let ids: Vec<_> =
                            this.satellite.panels.iter().map(|p| p.id.clone()).collect();
                        for id in ids {
                            this.satellite.transition(
                                id,
                                false,
                                std::time::Duration::from_millis(130),
                                crate::satellite::Side::Left,
                            );
                        }
                        cx.notify();
                    } else {
                        let _ = tx_esc.send(ControlCenterMsg::Close);
                    }
                    cx.stop_propagation();
                }
            }))
            .when(self.satellite.open(), |parent| {
                let visuals = self.satellite.layout(
                    Size::new(px(1200.0), px(760.0)),
                    Bounds {
                        origin: point(px(390.0), px(0.0)),
                        size: Size::new(px(400.0), px(440.0)),
                    },
                    px(12.0),
                    &[],
                );
                let tx_c_cal = tx_close.clone();
                let tx_c_aud = tx_close.clone();
                let tx_c_wifi = tx_close.clone();
                let tx_c_bt = tx_close.clone();

                let mut overlay = satellite_host::SatelliteOverlayHost::new().visuals(visuals);
                let now = chrono::Local::now();
                overlay = overlay.panel(
                    crate::satellite::SatelliteId::Calendar,
                    details::CalendarWidget::new(now.year(), now.month()).on_close(move || {
                        let _ = tx_c_cal.send(ControlCenterMsg::CloseSatellite(
                            crate::satellite::SatelliteId::Calendar,
                        ));
                    }),
                );
                overlay = overlay.panel(
                    crate::satellite::SatelliteId::Audio,
                    details::AudioDetailWidget::new(
                        self.sinks.clone(),
                        self.volume_percent,
                        self.is_muted,
                    )
                    .on_close(move || {
                        let _ = tx_c_aud.send(ControlCenterMsg::CloseSatellite(
                            crate::satellite::SatelliteId::Audio,
                        ));
                    }),
                );
                overlay = overlay.panel(
                    crate::satellite::SatelliteId::Wifi,
                    details::ConnectivityDetailWidget::new(details::ConnectivityTab::Wifi)
                        .wifi_enabled(self.is_wifi_on)
                        .wifi_networks(self.wifi_networks.clone())
                        .bt_enabled(self.is_bt_on)
                        .bt_devices(self.bt_devices.clone())
                        .on_close(move || {
                            let _ = tx_c_wifi.send(ControlCenterMsg::CloseSatellite(
                                crate::satellite::SatelliteId::Wifi,
                            ));
                        }),
                );
                overlay = overlay.panel(
                    crate::satellite::SatelliteId::Bluetooth,
                    details::ConnectivityDetailWidget::new(details::ConnectivityTab::Bluetooth)
                        .wifi_enabled(self.is_wifi_on)
                        .wifi_networks(self.wifi_networks.clone())
                        .bt_enabled(self.is_bt_on)
                        .bt_devices(self.bt_devices.clone())
                        .on_close(move || {
                            let _ = tx_c_bt.send(ControlCenterMsg::CloseSatellite(
                                crate::satellite::SatelliteId::Bluetooth,
                            ));
                        }),
                );
                parent.child(overlay)
            })
            .child(
                div()
                    .w(px(400.0))
                    .p(px(12.0))
                    .flex()
                    .flex_col()
                    .gap(px(12.0))
                    // 1. Header
                    .child(header::render_header(Some(Arc::new(move || {
                        let _ = tx_close.send(ControlCenterMsg::Close);
                    }))))
                    // 2. 2x3 Quick Toggles Grid (Wi-Fi, Bluetooth, Night Light, Caffeine, Game Mode, Battery)
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
                        self.is_night_light_on,
                        Some(Arc::new(move || {
                            let _ = tx_night.send(ControlCenterMsg::ToggleNightLight);
                        })),
                        self.is_caffeine_on,
                        Some(Arc::new(move || {
                            let _ = tx_caffeine.send(ControlCenterMsg::ToggleCaffeine);
                        })),
                        self.is_game_mode_on,
                        Some(Arc::new(move || {
                            let _ = tx_game.send(ControlCenterMsg::ToggleGameMode);
                        })),
                        self.battery_percent,
                        self.is_charging,
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
                    // 5. Compact Sliders: Brightness, Volume, and Mic in a single tight container
                    .child(sliders::render_compact_sliders(
                        self.brightness_percent,
                        Some(&self.brightness_slider),
                        self.volume_percent,
                        self.is_muted,
                        Some(&self.volume_slider),
                        Some(Arc::new(move || {
                            let _ = tx_mute.send(ControlCenterMsg::ToggleMute);
                        })),
                        self.mic_percent,
                        self.is_mic_muted,
                        Some(&self.mic_slider),
                        Some(Arc::new(move || {
                            let _ = tx_mic_mute.send(ControlCenterMsg::ToggleMicMute);
                        })),
                    ))
                    // 6. Performance Mode Row
                    .child(power_profiles::render_performance_row(
                        &self.active_power_profile,
                        Some(Arc::new(move |prof| {
                            let _ = tx_prof.send(ControlCenterMsg::SetPowerProfile(prof));
                        })),
                    )),
            )
    }
}
