use beskar_services::{BluetoothDeviceItem, WifiAccessPoint};
use gpui_kit::assets::IconName;
use gpui_kit::component::button::{Button, ButtonVariants};
use gpui_kit::component::switch::Switch;
use gpui_kit::component::tag::Tag;
use gpui_kit::component::Icon;
use gpui_kit::prelude::FluentBuilder;
use gpui_kit::*;
use std::sync::Arc;

/// Quick Settings & Control Center popover card.
/// Adapted from minflair's `QuickSettings.qml` and macOS / iOS Control Center.
/// Features:
/// - Wi-Fi tile (toggle + active SSID + expandable network list)
/// - Bluetooth tile (toggle + status + expandable device list)
/// - Master Volume slider with mute toggle and step buttons
/// - Master Display Brightness slider with step buttons
/// - Power Profile switcher (Power Saver, Balanced, Performance)
/// - Battery health & charging status
/// - Quick app actions footer (Apps, Clips, Settings, Power)
#[derive(IntoElement)]
pub struct ControlCenterWidget {
    volume_percent: u8,
    is_muted: bool,
    brightness_percent: u8,
    active_power_profile: String,
    battery_percent: u8,
    is_charging: bool,
    wifi_ssid: Option<String>,
    is_wifi_on: bool,
    is_bt_on: bool,
    wifi_networks: Vec<WifiAccessPoint>,
    bt_devices: Vec<BluetoothDeviceItem>,
    show_wifi_list: bool,
    show_bt_list: bool,
    on_volume_change: Option<Arc<dyn Fn(i32) + Send + Sync>>,
    on_toggle_mute: Option<Arc<dyn Fn() + Send + Sync>>,
    on_brightness_change: Option<Arc<dyn Fn(i32) + Send + Sync>>,
    on_set_power_profile: Option<Arc<dyn Fn(String) + Send + Sync>>,
    on_toggle_wifi: Option<Arc<dyn Fn() + Send + Sync>>,
    on_toggle_bluetooth: Option<Arc<dyn Fn() + Send + Sync>>,
    on_toggle_wifi_list: Option<Arc<dyn Fn() + Send + Sync>>,
    on_toggle_bt_list: Option<Arc<dyn Fn() + Send + Sync>>,
    on_connect_wifi: Option<Arc<dyn Fn(String) + Send + Sync>>,
    on_open_launcher: Option<Arc<dyn Fn() + Send + Sync>>,
    on_open_clipboard: Option<Arc<dyn Fn() + Send + Sync>>,
    on_open_power: Option<Arc<dyn Fn() + Send + Sync>>,
    on_open_settings: Option<Arc<dyn Fn() + Send + Sync>>,
    on_close: Option<Arc<dyn Fn() + Send + Sync>>,
}

impl ControlCenterWidget {
    pub fn new(volume_percent: u8, battery_percent: u8) -> Self {
        Self {
            volume_percent,
            is_muted: false,
            brightness_percent: 80,
            active_power_profile: "balanced".to_string(),
            battery_percent,
            is_charging: false,
            wifi_ssid: None,
            is_wifi_on: true,
            is_bt_on: true,
            wifi_networks: Vec::new(),
            bt_devices: Vec::new(),
            show_wifi_list: false,
            show_bt_list: false,
            on_volume_change: None,
            on_toggle_mute: None,
            on_brightness_change: None,
            on_set_power_profile: None,
            on_toggle_wifi: None,
            on_toggle_bluetooth: None,
            on_toggle_wifi_list: None,
            on_toggle_bt_list: None,
            on_connect_wifi: None,
            on_open_launcher: None,
            on_open_clipboard: None,
            on_open_power: None,
            on_open_settings: None,
            on_close: None,
        }
    }

    pub fn muted(mut self, muted: bool) -> Self {
        self.is_muted = muted;
        self
    }

    pub fn brightness(mut self, pct: u8) -> Self {
        self.brightness_percent = pct;
        self
    }

    pub fn power_profile(mut self, profile: impl Into<String>) -> Self {
        self.active_power_profile = profile.into();
        self
    }

    pub fn charging(mut self, charging: bool) -> Self {
        self.is_charging = charging;
        self
    }

    pub fn wifi(mut self, is_on: bool, ssid: Option<String>) -> Self {
        self.is_wifi_on = is_on;
        self.wifi_ssid = ssid;
        self
    }

    pub fn bluetooth(mut self, is_on: bool) -> Self {
        self.is_bt_on = is_on;
        self
    }

    pub fn wifi_networks(mut self, list: Vec<WifiAccessPoint>, show: bool) -> Self {
        self.wifi_networks = list;
        self.show_wifi_list = show;
        self
    }

    pub fn bt_devices(mut self, list: Vec<BluetoothDeviceItem>, show: bool) -> Self {
        self.bt_devices = list;
        self.show_bt_list = show;
        self
    }

    pub fn on_volume_change(mut self, handler: impl Fn(i32) + Send + Sync + 'static) -> Self {
        self.on_volume_change = Some(Arc::new(handler));
        self
    }

    pub fn on_toggle_mute(mut self, handler: impl Fn() + Send + Sync + 'static) -> Self {
        self.on_toggle_mute = Some(Arc::new(handler));
        self
    }

    pub fn on_brightness_change(mut self, handler: impl Fn(i32) + Send + Sync + 'static) -> Self {
        self.on_brightness_change = Some(Arc::new(handler));
        self
    }

    pub fn on_set_power_profile(
        mut self,
        handler: impl Fn(String) + Send + Sync + 'static,
    ) -> Self {
        self.on_set_power_profile = Some(Arc::new(handler));
        self
    }

    pub fn on_toggle_wifi(mut self, handler: impl Fn() + Send + Sync + 'static) -> Self {
        self.on_toggle_wifi = Some(Arc::new(handler));
        self
    }

    pub fn on_toggle_bluetooth(mut self, handler: impl Fn() + Send + Sync + 'static) -> Self {
        self.on_toggle_bluetooth = Some(Arc::new(handler));
        self
    }

    pub fn on_toggle_wifi_list(mut self, handler: impl Fn() + Send + Sync + 'static) -> Self {
        self.on_toggle_wifi_list = Some(Arc::new(handler));
        self
    }

    pub fn on_toggle_bt_list(mut self, handler: impl Fn() + Send + Sync + 'static) -> Self {
        self.on_toggle_bt_list = Some(Arc::new(handler));
        self
    }

    pub fn on_connect_wifi(mut self, handler: impl Fn(String) + Send + Sync + 'static) -> Self {
        self.on_connect_wifi = Some(Arc::new(handler));
        self
    }

    pub fn on_open_launcher(mut self, handler: impl Fn() + Send + Sync + 'static) -> Self {
        self.on_open_launcher = Some(Arc::new(handler));
        self
    }

    pub fn on_open_clipboard(mut self, handler: impl Fn() + Send + Sync + 'static) -> Self {
        self.on_open_clipboard = Some(Arc::new(handler));
        self
    }

    pub fn on_open_power(mut self, handler: impl Fn() + Send + Sync + 'static) -> Self {
        self.on_open_power = Some(Arc::new(handler));
        self
    }

    pub fn on_open_settings(mut self, handler: impl Fn() + Send + Sync + 'static) -> Self {
        self.on_open_settings = Some(Arc::new(handler));
        self
    }

    pub fn on_close(mut self, handler: impl Fn() + Send + Sync + 'static) -> Self {
        self.on_close = Some(Arc::new(handler));
        self
    }
}

impl RenderOnce for ControlCenterWidget {
    fn render(self, _window: &mut Window, _cx: &mut App) -> impl IntoElement {
        let on_vol = self.on_volume_change;
        let on_mute = self.on_toggle_mute;
        let on_bright = self.on_brightness_change;
        let on_profile = self.on_set_power_profile;
        let on_wifi = self.on_toggle_wifi;
        let on_bt = self.on_toggle_bluetooth;
        let on_wifi_list = self.on_toggle_wifi_list;
        let on_bt_list = self.on_toggle_bt_list;
        let on_connect = self.on_connect_wifi;
        let on_launcher = self.on_open_launcher;
        let on_clipboard = self.on_open_clipboard;
        let on_settings = self.on_open_settings;
        let on_power = self.on_open_power;
        let on_close = self.on_close;

        let wifi_label = self
            .wifi_ssid
            .unwrap_or_else(|| {
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
            .w(px(390.0))
            .p(px(16.0))
            .rounded(px(20.0))
            // Frosted Obsidian Acrylic Glass
            .bg(hsla(240.0 / 360.0, 0.14, 0.08, 0.94))
            .border_1()
            .border_color(hsla(240.0 / 360.0, 0.10, 1.0, 0.14))
            .shadow_xl()
            .flex()
            .flex_col()
            .gap(px(12.0))
            // ── Top Header Row ──
            .child(
                div()
                    .flex()
                    .items_center()
                    .justify_between()
                    .child(
                        div()
                            .text_sm()
                            .font_weight(FontWeight::BOLD)
                            .text_color(hsla(0.0, 0.0, 0.95, 1.0))
                            .child("Control Center"),
                    )
                    .when_some(on_close, |this, cb| {
                        this.child(
                            Button::new("cc-close-btn")
                                .ghost()
                                .compact()
                                .icon(Icon::new(IconName::X).size(px(12.0)))
                                .on_click(move |_, _, _| {
                                    (cb)();
                                }),
                        )
                    }),
            )
            // ── Quick Toggle Grid (Wi-Fi & Bluetooth Cards) ──
            .child(
                div()
                    .flex()
                    .gap(px(10.0))
                    // Wi-Fi Tile
                    .child(
                        div()
                            .id("cc-wifi-tile")
                            .flex_1()
                            .p(px(10.0))
                            .rounded(px(14.0))
                            .bg(if self.is_wifi_on {
                                hsla(45.0 / 360.0, 0.90, 0.60, 0.18)
                            } else {
                                hsla(0.0, 0.0, 1.0, 0.05)
                            })
                            .border_1()
                            .border_color(if self.is_wifi_on {
                                hsla(45.0 / 360.0, 0.90, 0.60, 0.40)
                            } else {
                                hsla(0.0, 0.0, 1.0, 0.08)
                            })
                            .flex()
                            .items_center()
                            .justify_between()
                            .child(
                                div()
                                    .flex()
                                    .items_center()
                                    .gap(px(8.0))
                                    .min_w_0()
                                    .cursor_pointer()
                                    .when_some(on_wifi.clone(), |el, cb| {
                                        el.on_mouse_down(MouseButton::Left, move |_, _, _| (cb)())
                                    })
                                    .child(
                                        div()
                                            .w(px(28.0))
                                            .h(px(28.0))
                                            .flex_shrink_0()
                                            .rounded_full()
                                            .bg(if self.is_wifi_on {
                                                hsla(45.0 / 360.0, 0.90, 0.60, 1.0)
                                            } else {
                                                hsla(0.0, 0.0, 1.0, 0.10)
                                            })
                                            .flex()
                                            .items_center()
                                            .justify_center()
                                            .child(
                                                Icon::new(IconName::Wifi)
                                                    .size(px(14.0))
                                                    .text_color(if self.is_wifi_on {
                                                        hsla(0.0, 0.0, 0.10, 1.0)
                                                    } else {
                                                        hsla(0.0, 0.0, 0.60, 1.0)
                                                    }),
                                            ),
                                    )
                                    .child(
                                        div()
                                            .flex()
                                            .flex_col()
                                            .min_w_0()
                                            .child(
                                                div()
                                                    .text_xs()
                                                    .font_weight(FontWeight::BOLD)
                                                    .text_color(hsla(0.0, 0.0, 0.95, 1.0))
                                                    .child("Wi-Fi"),
                                            )
                                            .child(
                                                div()
                                                    .text_xs()
                                                    .text_color(hsla(0.0, 0.0, 0.60, 1.0))
                                                    .overflow_hidden()
                                                    .whitespace_nowrap()
                                                    .text_ellipsis()
                                                    .child(wifi_label),
                                            ),
                                    ),
                            )
                            .child(
                                div()
                                    .flex()
                                    .items_center()
                                    .gap(px(4.0))
                                    .flex_shrink_0()
                                    .child(
                                        Switch::new("cc-wifi-switch")
                                            .checked(self.is_wifi_on)
                                            .on_click({
                                                let on_wifi = on_wifi.clone();
                                                move |_, _, _| {
                                                    if let Some(cb) = on_wifi.as_ref() {
                                                        cb();
                                                    }
                                                }
                                            }),
                                    )
                                    .child(
                                        Button::new("cc-wifi-chevron")
                                            .ghost()
                                            .compact()
                                            .icon(
                                                Icon::new(if self.show_wifi_list {
                                                    IconName::ChevronUp
                                                } else {
                                                    IconName::ChevronDown
                                                })
                                                .size(px(12.0)),
                                            )
                                            .when_some(on_wifi_list, |btn, cb| {
                                                btn.on_click(move |_, _, _| (cb)())
                                            }),
                                    ),
                            ),
                    )
                    // Bluetooth Tile
                    .child(
                        div()
                            .id("cc-bt-tile")
                            .flex_1()
                            .p(px(10.0))
                            .rounded(px(14.0))
                            .bg(if self.is_bt_on {
                                hsla(210.0 / 360.0, 0.85, 0.55, 0.18)
                            } else {
                                hsla(0.0, 0.0, 1.0, 0.05)
                            })
                            .border_1()
                            .border_color(if self.is_bt_on {
                                hsla(210.0 / 360.0, 0.85, 0.55, 0.40)
                            } else {
                                hsla(0.0, 0.0, 1.0, 0.08)
                            })
                            .flex()
                            .items_center()
                            .justify_between()
                            .child(
                                div()
                                    .flex()
                                    .items_center()
                                    .gap(px(8.0))
                                    .min_w_0()
                                    .cursor_pointer()
                                    .when_some(on_bt.clone(), |el, cb| {
                                        el.on_mouse_down(MouseButton::Left, move |_, _, _| (cb)())
                                    })
                                    .child(
                                        div()
                                            .w(px(28.0))
                                            .h(px(28.0))
                                            .flex_shrink_0()
                                            .rounded_full()
                                            .bg(if self.is_bt_on {
                                                hsla(210.0 / 360.0, 0.85, 0.55, 1.0)
                                            } else {
                                                hsla(0.0, 0.0, 1.0, 0.10)
                                            })
                                            .flex()
                                            .items_center()
                                            .justify_center()
                                            .child(
                                                Icon::new(IconName::Bluetooth)
                                                    .size(px(14.0))
                                                    .text_color(if self.is_bt_on {
                                                        hsla(0.0, 0.0, 1.0, 1.0)
                                                    } else {
                                                        hsla(0.0, 0.0, 0.60, 1.0)
                                                    }),
                                            ),
                                    )
                                    .child(
                                        div()
                                            .flex()
                                            .flex_col()
                                            .min_w_0()
                                            .child(
                                                div()
                                                    .text_xs()
                                                    .font_weight(FontWeight::BOLD)
                                                    .text_color(hsla(0.0, 0.0, 0.95, 1.0))
                                                    .child("Bluetooth"),
                                            )
                                            .child(
                                                div()
                                                    .text_xs()
                                                    .text_color(hsla(0.0, 0.0, 0.60, 1.0))
                                                    .overflow_hidden()
                                                    .whitespace_nowrap()
                                                    .text_ellipsis()
                                                    .child(bt_label),
                                            ),
                                    ),
                            )
                            .child(
                                div()
                                    .flex()
                                    .items_center()
                                    .gap(px(4.0))
                                    .flex_shrink_0()
                                    .child(
                                        Switch::new("cc-bt-switch")
                                            .checked(self.is_bt_on)
                                            .on_click({
                                                let on_bt = on_bt.clone();
                                                move |_, _, _| {
                                                    if let Some(cb) = on_bt.as_ref() {
                                                        cb();
                                                    }
                                                }
                                            }),
                                    )
                                    .child(
                                        Button::new("cc-bt-chevron")
                                            .ghost()
                                            .compact()
                                            .icon(
                                                Icon::new(if self.show_bt_list {
                                                    IconName::ChevronUp
                                                } else {
                                                    IconName::ChevronDown
                                                })
                                                .size(px(12.0)),
                                            )
                                            .when_some(on_bt_list, |btn, cb| {
                                                btn.on_click(move |_, _, _| (cb)())
                                            }),
                                    ),
                            ),
                    ),
            )
            // ── Expandable Wi-Fi Networks Subpanel ──
            .when(self.show_wifi_list, |parent| {
                parent.child(
                    div()
                        .p(px(10.0))
                        .rounded(px(12.0))
                        .bg(hsla(0.0, 0.0, 1.0, 0.05))
                        .border_1()
                        .border_color(hsla(0.0, 0.0, 1.0, 0.10))
                        .flex()
                        .flex_col()
                        .gap(px(6.0))
                        .child(
                            div()
                                .text_xs()
                                .font_weight(FontWeight::BOLD)
                                .text_color(hsla(45.0 / 360.0, 0.90, 0.60, 1.0))
                                .child("Available Wi-Fi Networks"),
                        )
                        .child(
                            if self.wifi_networks.is_empty() {
                                div()
                                    .py(px(12.0))
                                    .flex()
                                    .items_center()
                                    .justify_center()
                                    .child(
                                        div()
                                            .text_xs()
                                            .text_color(hsla(0.0, 0.0, 0.60, 1.0))
                                            .child("Scanning networks..."),
                                    )
                                    .into_any_element()
                            } else {
                                div()
                                    .id("cc-wifi-scroll-list")
                                    .flex()
                                    .flex_col()
                                    .gap(px(4.0))
                                    .max_h(px(180.0))
                                    .overflow_y_scroll()
                                    .children(self.wifi_networks.iter().enumerate().map(|(idx, ap)| {
                                        let ssid_clone = ap.ssid.clone();
                                        let on_c = on_connect.clone();
                                        Button::new(("cc-wifi-item", idx))
                                            .ghost()
                                            .w_full()
                                            .child(
                                                div()
                                                    .flex()
                                                    .items_center()
                                                    .justify_between()
                                                    .w_full()
                                                    .child(
                                                        div()
                                                            .flex()
                                                            .items_center()
                                                            .gap(px(6.0))
                                                            .child(
                                                                Icon::new(IconName::Wifi)
                                                                    .size(px(12.0))
                                                                    .text_color(if ap.is_active {
                                                                        hsla(142.0 / 360.0, 0.85, 0.55, 1.0)
                                                                    } else {
                                                                        hsla(0.0, 0.0, 0.70, 1.0)
                                                                    }),
                                                            )
                                                            .child(
                                                                div()
                                                                    .text_xs()
                                                                    .font_weight(if ap.is_active { FontWeight::BOLD } else { FontWeight::NORMAL })
                                                                    .text_color(hsla(0.0, 0.0, 0.90, 1.0))
                                                                    .child(ap.ssid.clone()),
                                                            ),
                                                    )
                                                    .child(
                                                        Tag::secondary().child(format!("{}%", ap.signal)),
                                                    ),
                                            )
                                            .when_some(on_c, move |btn, cb| {
                                                btn.on_click(move |_, _, _| (cb)(ssid_clone.clone()))
                                            })
                                    }))
                                    .into_any_element()
                            },
                        ),
                )
            })
            // ── Expandable Bluetooth Devices Subpanel ──
            .when(self.show_bt_list, |parent| {
                parent.child(
                    div()
                        .p(px(10.0))
                        .rounded(px(12.0))
                        .bg(hsla(0.0, 0.0, 1.0, 0.05))
                        .border_1()
                        .border_color(hsla(0.0, 0.0, 1.0, 0.10))
                        .flex()
                        .flex_col()
                        .gap(px(6.0))
                        .child(
                            div()
                                .text_xs()
                                .font_weight(FontWeight::BOLD)
                                .text_color(hsla(210.0 / 360.0, 0.85, 0.65, 1.0))
                                .child("Paired Bluetooth Devices"),
                        )
                        .child(
                            if self.bt_devices.is_empty() {
                                div()
                                    .py(px(12.0))
                                    .flex()
                                    .items_center()
                                    .justify_center()
                                    .child(
                                        div()
                                            .text_xs()
                                            .text_color(hsla(0.0, 0.0, 0.60, 1.0))
                                            .child("Scanning Bluetooth devices..."),
                                    )
                                    .into_any_element()
                            } else {
                                div()
                                    .id("cc-bt-scroll-list")
                                    .flex()
                                    .flex_col()
                                    .gap(px(4.0))
                                    .max_h(px(180.0))
                                    .overflow_y_scroll()
                                    .children(self.bt_devices.iter().enumerate().map(|(idx, dev)| {
                                        let is_conn = dev.is_connected;
                                        let dev_label = if is_conn {
                                            if let Some(bat) = dev.battery_percent {
                                                format!("Connected ({}%)", bat)
                                            } else {
                                                "Connected".to_string()
                                            }
                                        } else {
                                            "Disconnected".to_string()
                                        };
                                        div()
                                            .id(SharedString::from(format!("cc-bt-dev-{}", idx)))
                                            .flex()
                                            .items_center()
                                            .justify_between()
                                            .p(px(6.0))
                                            .rounded(px(8.0))
                                            .bg(hsla(0.0, 0.0, 1.0, 0.03))
                                            .child(
                                                div()
                                                    .flex()
                                                    .items_center()
                                                    .gap(px(6.0))
                                                    .child(
                                                        Icon::new(IconName::Bluetooth)
                                                            .size(px(12.0))
                                                            .text_color(if is_conn {
                                                                hsla(142.0 / 360.0, 0.85, 0.55, 1.0)
                                                            } else {
                                                                hsla(0.0, 0.0, 0.60, 1.0)
                                                            }),
                                                    )
                                                    .child(
                                                        div()
                                                            .text_xs()
                                                            .text_color(hsla(0.0, 0.0, 0.90, 1.0))
                                                            .child(dev.name.clone()),
                                                    ),
                                            )
                                            .child(
                                                if is_conn {
                                                    Tag::primary().child(dev_label)
                                                } else {
                                                    Tag::secondary().child(dev_label)
                                                },
                                            )
                                    }))
                                    .into_any_element()
                            },
                        ),
                )
            })
            // ── Master Volume Slider Card ──
            .child(
                div()
                    .p(px(12.0))
                    .rounded(px(14.0))
                    .bg(hsla(0.0, 0.0, 1.0, 0.04))
                    .border_1()
                    .border_color(hsla(0.0, 0.0, 1.0, 0.08))
                    .flex()
                    .flex_col()
                    .gap(px(8.0))
                    .child(
                        div()
                            .flex()
                            .items_center()
                            .justify_between()
                            .child(
                                div()
                                    .flex()
                                    .items_center()
                                    .gap(px(6.0))
                                    .child(
                                        Button::new("cc-vol-mute")
                                            .ghost()
                                            .compact()
                                            .icon(
                                                Icon::new(if self.is_muted {
                                                    IconName::VolumeX
                                                } else {
                                                    IconName::Volume2
                                                })
                                                .size(px(14.0))
                                                .text_color(hsla(0.0, 0.0, 0.90, 1.0)),
                                            )
                                            .when_some(on_mute, |btn, cb| {
                                                btn.on_click(move |_, _, _| (cb)())
                                            }),
                                    )
                                    .child(
                                        div()
                                            .text_xs()
                                            .font_weight(FontWeight::MEDIUM)
                                            .text_color(hsla(0.0, 0.0, 0.90, 1.0))
                                            .child("Master Volume"),
                                    ),
                            )
                            .child(
                                div()
                                    .flex()
                                    .items_center()
                                    .gap(px(6.0))
                                    .child(
                                        Button::new("cc-vol-down")
                                            .ghost()
                                            .compact()
                                            .label("-")
                                            .when_some(on_vol.clone(), |btn, cb| {
                                                btn.on_click(move |_, _, _| (cb)(-5))
                                            }),
                                    )
                                    .child(
                                        Tag::secondary().child(format!("{}%", self.volume_percent)),
                                    )
                                    .child(
                                        Button::new("cc-vol-up")
                                            .ghost()
                                            .compact()
                                            .label("+")
                                            .when_some(on_vol, |btn, cb| {
                                                btn.on_click(move |_, _, _| (cb)(5))
                                            }),
                                    ),
                            ),
                    )
                    // Visual Volume Bar
                    .child(
                        div()
                            .relative()
                            .w_full()
                            .h(px(8.0))
                            .rounded_full()
                            .bg(hsla(0.0, 0.0, 1.0, 0.10))
                            .overflow_hidden()
                            .child(
                                div()
                                    .h_full()
                                    .w(relative(self.volume_percent as f32 / 100.0))
                                    .rounded_full()
                                    .bg(if self.is_muted {
                                        hsla(0.0, 0.0, 0.40, 1.0)
                                    } else {
                                        hsla(45.0 / 360.0, 0.90, 0.60, 1.0)
                                    }),
                            ),
                    ),
            )
            // ── Master Display Brightness Slider Card ──
            .child(
                div()
                    .p(px(12.0))
                    .rounded(px(14.0))
                    .bg(hsla(0.0, 0.0, 1.0, 0.04))
                    .border_1()
                    .border_color(hsla(0.0, 0.0, 1.0, 0.08))
                    .flex()
                    .flex_col()
                    .gap(px(8.0))
                    .child(
                        div()
                            .flex()
                            .items_center()
                            .justify_between()
                            .child(
                                div()
                                    .flex()
                                    .items_center()
                                    .gap(px(6.0))
                                    .child(
                                        Icon::new(IconName::Sun)
                                            .size(px(14.0))
                                            .text_color(hsla(45.0 / 360.0, 0.90, 0.60, 1.0)),
                                    )
                                    .child(
                                        div()
                                            .text_xs()
                                            .font_weight(FontWeight::MEDIUM)
                                            .text_color(hsla(0.0, 0.0, 0.90, 1.0))
                                            .child("Display Brightness"),
                                    ),
                            )
                            .child(
                                div()
                                    .flex()
                                    .items_center()
                                    .gap(px(6.0))
                                    .child(
                                        Button::new("cc-bright-down")
                                            .ghost()
                                            .compact()
                                            .label("-")
                                            .when_some(on_bright.clone(), |btn, cb| {
                                                btn.on_click(move |_, _, _| (cb)(-5))
                                            }),
                                    )
                                    .child(
                                        Tag::secondary().child(format!("{}%", self.brightness_percent)),
                                    )
                                    .child(
                                        Button::new("cc-bright-up")
                                            .ghost()
                                            .compact()
                                            .label("+")
                                            .when_some(on_bright, |btn, cb| {
                                                btn.on_click(move |_, _, _| (cb)(5))
                                            }),
                                    ),
                            ),
                    )
                    // Visual Brightness Bar
                    .child(
                        div()
                            .relative()
                            .w_full()
                            .h(px(8.0))
                            .rounded_full()
                            .bg(hsla(0.0, 0.0, 1.0, 0.10))
                            .overflow_hidden()
                            .child(
                                div()
                                    .h_full()
                                    .w(relative(self.brightness_percent as f32 / 100.0))
                                    .rounded_full()
                                    .bg(hsla(45.0 / 360.0, 0.90, 0.60, 1.0)),
                            ),
                    ),
            )
            // ── Power Profiles Selector Pill Strip ──
            .child(
                div()
                    .p(px(10.0))
                    .rounded(px(14.0))
                    .bg(hsla(0.0, 0.0, 1.0, 0.04))
                    .border_1()
                    .border_color(hsla(0.0, 0.0, 1.0, 0.08))
                    .flex()
                    .flex_col()
                    .gap(px(8.0))
                    .child(
                        div()
                            .text_xs()
                            .font_weight(FontWeight::MEDIUM)
                            .text_color(hsla(0.0, 0.0, 0.80, 1.0))
                            .child("Power Profile"),
                    )
                    .child(
                        div()
                            .flex()
                            .gap(px(6.0))
                            .children(["power-saver", "balanced", "performance"].iter().map(|&prof| {
                                let is_active = self.active_power_profile == prof;
                                let label = match prof {
                                    "power-saver" => "Saver",
                                    "balanced" => "Balanced",
                                    "performance" => "Performance",
                                    _ => prof,
                                };
                                let on_p = on_profile.clone();
                                let prof_str = prof.to_string();
                                let btn = Button::new(SharedString::from(format!("prof-{}", prof)))
                                    .flex_1()
                                    .label(label);
                                let btn = if is_active {
                                    btn.primary()
                                } else {
                                    btn.ghost()
                                };
                                btn.when_some(on_p, move |b, cb| {
                                    b.on_click(move |_, _, _| (cb)(prof_str.clone()))
                                })
                            })),
                    ),
            )
            // ── Battery & System Vitals Card ──
            .child(
                div()
                    .p(px(10.0))
                    .rounded(px(14.0))
                    .bg(hsla(0.0, 0.0, 1.0, 0.04))
                    .border_1()
                    .border_color(hsla(0.0, 0.0, 1.0, 0.08))
                    .flex()
                    .items_center()
                    .justify_between()
                    .child(
                        div()
                            .flex()
                            .items_center()
                            .gap(px(8.0))
                            .child(
                                Icon::new(if self.is_charging {
                                    IconName::BatteryCharging
                                } else {
                                    IconName::BatteryFull
                                })
                                .size(px(16.0))
                                .text_color(if self.is_charging {
                                    hsla(142.0 / 360.0, 0.85, 0.55, 1.0)
                                } else {
                                    hsla(0.0, 0.0, 0.90, 1.0)
                                }),
                            )
                            .child(
                                div()
                                    .text_xs()
                                    .font_weight(FontWeight::MEDIUM)
                                    .text_color(hsla(0.0, 0.0, 0.85, 1.0))
                                    .child(if self.is_charging {
                                        "Battery Charging"
                                    } else {
                                        "Battery Normal"
                                    }),
                            ),
                    )
                    .child(
                        if self.is_charging {
                            Tag::primary().child(format!("{}%", self.battery_percent))
                        } else {
                            Tag::secondary().child(format!("{}%", self.battery_percent))
                        },
                    ),
            )
            // ── Quick Actions Footer ──
            .child(
                div()
                    .flex()
                    .items_center()
                    .gap(px(8.0))
                    .when_some(on_launcher, |this, cb| {
                        this.child(
                            Button::new("cc-action-launcher")
                                .secondary()
                                .flex_1()
                                .icon(Icon::new(IconName::Search).size(px(12.0)))
                                .label("Apps")
                                .on_click(move |_, _, _| {
                                    (cb)();
                                }),
                        )
                    })
                    .when_some(on_clipboard, |this, cb| {
                        this.child(
                            Button::new("cc-action-clipboard")
                                .secondary()
                                .flex_1()
                                .icon(Icon::new(IconName::ClipboardList).size(px(12.0)))
                                .label("Clips")
                                .on_click(move |_, _, _| {
                                    (cb)();
                                }),
                        )
                    })
                    .when_some(on_settings, |this, cb| {
                        this.child(
                            Button::new("cc-action-settings")
                                .secondary()
                                .flex_1()
                                .icon(Icon::new(IconName::Settings).size(px(12.0)))
                                .label("Settings")
                                .on_click(move |_, _, _| {
                                    (cb)();
                                }),
                        )
                    })
                    .when_some(on_power, |this, cb| {
                        this.child(
                            Button::new("cc-action-power")
                                .secondary()
                                .flex_1()
                                .icon(Icon::new(IconName::Power).size(px(12.0)))
                                .label("Power")
                                .on_click(move |_, _, _| {
                                    (cb)();
                                }),
                        )
                    }),
            )
    }
}
