//! Connectivity (Wi-Fi & Bluetooth) Satellite Detail Widget
//! Ported directly from `references/capsule/crates/app/src/capsule/widgets/dashboard/details/connectivity.rs`.

use beskar_services::{BluetoothDeviceItem, WifiAccessPoint};
use gpui_kit::assets::IconName;
use gpui_kit::component::Icon;
use gpui_kit::component::tag::Tag;
use gpui_kit::prelude::FluentBuilder;
use gpui_kit::*;
use std::sync::Arc;

pub const WIDTH: f32 = 320.0;
pub const HEIGHT: f32 = 400.0;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ConnectivityTab {
    Wifi,
    Bluetooth,
}

#[derive(IntoElement)]
pub struct ConnectivityDetailWidget {
    active_tab: ConnectivityTab,
    wifi_enabled: bool,
    wifi_networks: Vec<WifiAccessPoint>,
    bt_enabled: bool,
    bt_devices: Vec<BluetoothDeviceItem>,
    on_toggle_wifi: Option<Arc<dyn Fn() + Send + Sync>>,
    on_scan_wifi: Option<Arc<dyn Fn() + Send + Sync>>,
    on_connect_wifi: Option<Arc<dyn Fn(String) + Send + Sync>>,
    on_toggle_bt: Option<Arc<dyn Fn() + Send + Sync>>,
    on_select_tab: Option<Arc<dyn Fn(ConnectivityTab) + Send + Sync>>,
    on_close: Option<Arc<dyn Fn() + Send + Sync>>,
}

impl ConnectivityDetailWidget {
    pub fn new(active_tab: ConnectivityTab) -> Self {
        Self {
            active_tab,
            wifi_enabled: true,
            wifi_networks: Vec::new(),
            bt_enabled: true,
            bt_devices: Vec::new(),
            on_toggle_wifi: None,
            on_scan_wifi: None,
            on_connect_wifi: None,
            on_toggle_bt: None,
            on_select_tab: None,
            on_close: None,
        }
    }

    pub fn wifi_enabled(mut self, enabled: bool) -> Self {
        self.wifi_enabled = enabled;
        self
    }

    pub fn wifi_networks(mut self, networks: Vec<WifiAccessPoint>) -> Self {
        self.wifi_networks = networks;
        self
    }

    pub fn bt_enabled(mut self, enabled: bool) -> Self {
        self.bt_enabled = enabled;
        self
    }

    pub fn bt_devices(mut self, devices: Vec<BluetoothDeviceItem>) -> Self {
        self.bt_devices = devices;
        self
    }

    pub fn on_toggle_wifi(mut self, handler: impl Fn() + Send + Sync + 'static) -> Self {
        self.on_toggle_wifi = Some(Arc::new(handler));
        self
    }

    pub fn on_scan_wifi(mut self, handler: impl Fn() + Send + Sync + 'static) -> Self {
        self.on_scan_wifi = Some(Arc::new(handler));
        self
    }

    pub fn on_connect_wifi(mut self, handler: impl Fn(String) + Send + Sync + 'static) -> Self {
        self.on_connect_wifi = Some(Arc::new(handler));
        self
    }

    pub fn on_toggle_bt(mut self, handler: impl Fn() + Send + Sync + 'static) -> Self {
        self.on_toggle_bt = Some(Arc::new(handler));
        self
    }

    pub fn on_select_tab(
        mut self,
        handler: impl Fn(ConnectivityTab) + Send + Sync + 'static,
    ) -> Self {
        self.on_select_tab = Some(Arc::new(handler));
        self
    }

    pub fn on_close(mut self, handler: impl Fn() + Send + Sync + 'static) -> Self {
        self.on_close = Some(Arc::new(handler));
        self
    }
}

impl RenderOnce for ConnectivityDetailWidget {
    fn render(self, _window: &mut Window, _cx: &mut App) -> impl IntoElement {
        let is_wifi = self.active_tab == ConnectivityTab::Wifi;
        let on_tab = self.on_select_tab;
        let on_cls = self.on_close;

        let on_tab_wifi = on_tab.clone();
        let on_tab_bt = on_tab;

        let tab_bar = div()
            .flex()
            .gap(px(6.0))
            .p(px(3.0))
            .rounded(px(10.0))
            .bg(beskar_theme::Theme::glass_fill(0.04))
            .child(
                div()
                    .flex_1()
                    .py(px(4.0))
                    .rounded(px(8.0))
                    .text_center()
                    .text_xs()
                    .font_weight(if is_wifi {
                        FontWeight::BOLD
                    } else {
                        FontWeight::NORMAL
                    })
                    .bg(if is_wifi {
                        beskar_theme::Theme::accent()
                    } else {
                        gpui_kit::hsla(0.0, 0.0, 0.0, 0.0)
                    })
                    .text_color(if is_wifi {
                        beskar_theme::Theme::bg()
                    } else {
                        beskar_theme::Theme::fg()
                    })
                    .cursor_pointer()
                    .when_some(on_tab_wifi, |el, cb| {
                        el.on_mouse_down(MouseButton::Left, move |_, _, _| {
                            (cb)(ConnectivityTab::Wifi)
                        })
                    })
                    .child("Wi-Fi"),
            )
            .child(
                div()
                    .flex_1()
                    .py(px(4.0))
                    .rounded(px(8.0))
                    .text_center()
                    .text_xs()
                    .font_weight(if !is_wifi {
                        FontWeight::BOLD
                    } else {
                        FontWeight::NORMAL
                    })
                    .bg(if !is_wifi {
                        beskar_theme::Theme::accent()
                    } else {
                        gpui_kit::hsla(0.0, 0.0, 0.0, 0.0)
                    })
                    .text_color(if !is_wifi {
                        beskar_theme::Theme::bg()
                    } else {
                        beskar_theme::Theme::fg()
                    })
                    .cursor_pointer()
                    .when_some(on_tab_bt, |el, cb| {
                        el.on_mouse_down(MouseButton::Left, move |_, _, _| {
                            (cb)(ConnectivityTab::Bluetooth)
                        })
                    })
                    .child("Bluetooth"),
            );

        let content_list = if is_wifi {
            let on_c = self.on_connect_wifi;
            let on_scan = self.on_scan_wifi;
            let on_tog = self.on_toggle_wifi;

            let header_row = div()
                .flex()
                .items_center()
                .justify_between()
                .p(px(8.0))
                .rounded(px(10.0))
                .bg(beskar_theme::Theme::glass_fill(0.04))
                .child(
                    div()
                        .flex()
                        .items_center()
                        .gap(px(6.0))
                        .cursor_pointer()
                        .when_some(on_tog, |el, cb| {
                            el.on_mouse_down(MouseButton::Left, move |_, _, _| (cb)())
                        })
                        .child(Icon::new(IconName::Wifi).size(px(14.0)).text_color(
                            if self.wifi_enabled {
                                beskar_theme::Theme::success()
                            } else {
                                beskar_theme::Theme::muted()
                            },
                        ))
                        .child(div().text_xs().text_color(beskar_theme::Theme::fg()).child(
                            if self.wifi_enabled {
                                "Wi-Fi Enabled"
                            } else {
                                "Wi-Fi Disabled"
                            },
                        )),
                )
                .child(
                    div()
                        .flex()
                        .items_center()
                        .gap(px(4.0))
                        .cursor_pointer()
                        .hover(|s| s.text_color(beskar_theme::Theme::accent()))
                        .when_some(on_scan, |el, cb| {
                            el.on_mouse_down(MouseButton::Left, move |_, _, _| (cb)())
                        })
                        .child(Icon::new(IconName::RotateCcw).size(px(12.0)))
                        .child(div().text_xs().child("Scan")),
                );

            let mut list = div()
                .id("connectivity-wifi-scroll-list")
                .flex_1()
                .flex()
                .flex_col()
                .gap(px(4.0))
                .overflow_y_scroll();

            if self.wifi_networks.is_empty() {
                list = list.child(
                    div()
                        .py(px(16.0))
                        .flex()
                        .items_center()
                        .justify_center()
                        .text_xs()
                        .text_color(beskar_theme::Theme::text_secondary())
                        .child("No Wi-Fi networks found"),
                );
            } else {
                for ap in self.wifi_networks {
                    let ssid = ap.ssid.clone();
                    let on_conn = on_c.clone();
                    list = list.child(
                        div()
                            .w_full()
                            .p(px(8.0))
                            .rounded(px(8.0))
                            .flex()
                            .items_center()
                            .justify_between()
                            .cursor_pointer()
                            .bg(if ap.is_active {
                                beskar_theme::Theme::accent_alpha(0.18)
                            } else {
                                beskar_theme::Theme::glass_fill(0.03)
                            })
                            .hover(|s| s.bg(beskar_theme::Theme::bg_secondary()))
                            .when_some(on_conn, move |el, cb| {
                                el.on_mouse_down(MouseButton::Left, move |_, _, _| {
                                    (cb)(ssid.clone())
                                })
                            })
                            .child(
                                div()
                                    .flex()
                                    .items_center()
                                    .gap(px(6.0))
                                    .child(Icon::new(IconName::Wifi).size(px(13.0)).text_color(
                                        if ap.is_active {
                                            beskar_theme::Theme::success()
                                        } else {
                                            beskar_theme::Theme::text_secondary()
                                        },
                                    ))
                                    .child(
                                        div()
                                            .text_xs()
                                            .font_weight(if ap.is_active {
                                                FontWeight::BOLD
                                            } else {
                                                FontWeight::NORMAL
                                            })
                                            .text_color(beskar_theme::Theme::fg())
                                            .child(ap.ssid),
                                    ),
                            )
                            .child(Tag::secondary().child(format!("{}%", ap.signal))),
                    );
                }
            }

            div()
                .flex_1()
                .flex()
                .flex_col()
                .gap(px(8.0))
                .child(header_row)
                .child(list)
                .into_any_element()
        } else {
            let on_tog_bt = self.on_toggle_bt;
            let header_row = div()
                .flex()
                .items_center()
                .justify_between()
                .p(px(8.0))
                .rounded(px(10.0))
                .bg(beskar_theme::Theme::glass_fill(0.04))
                .child(
                    div()
                        .flex()
                        .items_center()
                        .gap(px(6.0))
                        .cursor_pointer()
                        .when_some(on_tog_bt, |el, cb| {
                            el.on_mouse_down(MouseButton::Left, move |_, _, _| (cb)())
                        })
                        .child(Icon::new(IconName::Bluetooth).size(px(14.0)).text_color(
                            if self.bt_enabled {
                                beskar_theme::Theme::info()
                            } else {
                                beskar_theme::Theme::muted()
                            },
                        ))
                        .child(div().text_xs().text_color(beskar_theme::Theme::fg()).child(
                            if self.bt_enabled {
                                "Bluetooth Enabled"
                            } else {
                                "Bluetooth Disabled"
                            },
                        )),
                );

            let mut list = div()
                .id("connectivity-bt-scroll-list")
                .flex_1()
                .flex()
                .flex_col()
                .gap(px(4.0))
                .overflow_y_scroll();

            if self.bt_devices.is_empty() {
                list = list.child(
                    div()
                        .py(px(16.0))
                        .flex()
                        .items_center()
                        .justify_center()
                        .text_xs()
                        .text_color(beskar_theme::Theme::text_secondary())
                        .child("No Bluetooth devices found"),
                );
            } else {
                for dev in self.bt_devices {
                    let is_conn = dev.is_connected;
                    let label = if is_conn {
                        if let Some(bat) = dev.battery_percent {
                            format!("Connected ({}%)", bat)
                        } else {
                            "Connected".to_string()
                        }
                    } else {
                        "Disconnected".to_string()
                    };

                    list = list.child(
                        div()
                            .w_full()
                            .p(px(8.0))
                            .rounded(px(8.0))
                            .flex()
                            .items_center()
                            .justify_between()
                            .bg(beskar_theme::Theme::glass_fill(0.03))
                            .child(
                                div()
                                    .flex()
                                    .items_center()
                                    .gap(px(6.0))
                                    .child(
                                        Icon::new(IconName::Bluetooth).size(px(13.0)).text_color(
                                            if is_conn {
                                                beskar_theme::Theme::success()
                                            } else {
                                                beskar_theme::Theme::muted()
                                            },
                                        ),
                                    )
                                    .child(
                                        div()
                                            .text_xs()
                                            .text_color(beskar_theme::Theme::fg())
                                            .child(dev.name),
                                    ),
                            )
                            .child(if is_conn {
                                Tag::primary().child(label)
                            } else {
                                Tag::secondary().child(label)
                            }),
                    );
                }
            }

            div()
                .flex_1()
                .flex()
                .flex_col()
                .gap(px(8.0))
                .child(header_row)
                .child(list)
                .into_any_element()
        };

        div()
            .w(px(WIDTH))
            .h(px(HEIGHT))
            .flex()
            .flex_col()
            .p(px(16.0))
            .gap(px(10.0))
            .rounded(px(16.0))
            .bg(beskar_theme::Theme::bg_secondary())
            .border_1()
            .border_color(beskar_theme::Theme::subtle_border())
            .overflow_hidden()
            .child(
                div()
                    .h(px(28.0))
                    .flex_shrink_0()
                    .flex()
                    .items_center()
                    .justify_between()
                    .child(
                        div()
                            .flex()
                            .items_center()
                            .gap(px(8.0))
                            .child(
                                Icon::new(if is_wifi {
                                    IconName::Wifi
                                } else {
                                    IconName::Bluetooth
                                })
                                .size(px(16.0))
                                .text_color(beskar_theme::Theme::accent()),
                            )
                            .child(
                                div()
                                    .text_size(px(13.0))
                                    .font_weight(FontWeight::MEDIUM)
                                    .child("Connectivity"),
                            ),
                    )
                    .when_some(on_cls, |parent, cb| {
                        parent.child(
                            div()
                                .size(px(24.0))
                                .flex()
                                .items_center()
                                .justify_center()
                                .rounded_full()
                                .cursor_pointer()
                                .hover(|s| s.bg(beskar_theme::Theme::bg()))
                                .on_mouse_down(MouseButton::Left, move |_, _, _| (cb)())
                                .child(Icon::new(IconName::X).size(px(14.0))),
                        )
                    }),
            )
            .child(tab_bar)
            .child(content_list)
    }
}
