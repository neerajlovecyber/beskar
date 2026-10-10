use gpui_kit::assets::IconName;
use gpui_kit::component::Icon;
use gpui_kit::prelude::FluentBuilder;
use gpui_kit::*;
use std::sync::Arc;

/// Quick Settings & Control Center popover card.
/// Adapted from minflair's `QuickSettings.qml` and macOS / iOS Control Center.
/// Features:
/// - Wi-Fi tile (toggle + active SSID)
/// - Bluetooth tile (toggle + status)
/// - Volume slider with percentage and mute toggle
/// - Battery health & charging status
/// - Power actions
#[derive(IntoElement)]
pub struct ControlCenterWidget {
    volume_percent: u8,
    is_muted: bool,
    battery_percent: u8,
    is_charging: bool,
    wifi_ssid: Option<String>,
    is_wifi_on: bool,
    is_bt_on: bool,
    on_volume_change: Option<Arc<dyn Fn(i32) + Send + Sync>>,
    on_toggle_mute: Option<Arc<dyn Fn() + Send + Sync>>,
    on_close: Option<Arc<dyn Fn() + Send + Sync>>,
}

impl ControlCenterWidget {
    pub fn new(volume_percent: u8, battery_percent: u8) -> Self {
        Self {
            volume_percent,
            is_muted: false,
            battery_percent,
            is_charging: false,
            wifi_ssid: None,
            is_wifi_on: true,
            is_bt_on: true,
            on_volume_change: None,
            on_toggle_mute: None,
            on_close: None,
        }
    }

    pub fn muted(mut self, muted: bool) -> Self {
        self.is_muted = muted;
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

    pub fn on_volume_change(mut self, handler: impl Fn(i32) + Send + Sync + 'static) -> Self {
        self.on_volume_change = Some(Arc::new(handler));
        self
    }

    pub fn on_toggle_mute(mut self, handler: impl Fn() + Send + Sync + 'static) -> Self {
        self.on_toggle_mute = Some(Arc::new(handler));
        self
    }

    pub fn on_close(mut self, handler: impl Fn() + Send + Sync + 'static) -> Self {
        self.on_close = Some(Arc::new(handler));
        self
    }
}

impl RenderOnce for ControlCenterWidget {
    fn render(self, _window: &mut Window, _cx: &mut App) -> impl IntoElement {
        let _on_vol = self.on_volume_change;
        let on_mute = self.on_toggle_mute;
        let on_close = self.on_close;

        let wifi_label = self
            .wifi_ssid
            .unwrap_or_else(|| if self.is_wifi_on { "Wi-Fi On".into() } else { "Wi-Fi Off".into() });

        let bt_label = if self.is_bt_on { "Bluetooth On" } else { "Bluetooth Off" };

        div()
            .w(px(320.0))
            .p(px(16.0))
            .rounded(px(20.0))
            // Frosted Obsidian Acrylic Glass
            .bg(hsla(240.0 / 360.0, 0.14, 0.08, 0.94))
            .border_1()
            .border_color(hsla(240.0 / 360.0, 0.10, 1.0, 0.14))
            .shadow_xl()
            .flex()
            .flex_col()
            .gap(px(14.0))
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
                    .child(
                        div()
                            .w(px(20.0))
                            .h(px(20.0))
                            .flex()
                            .items_center()
                            .justify_center()
                            .rounded_full()
                            .bg(hsla(0.0, 0.0, 1.0, 0.08))
                            .hover(|s| s.bg(hsla(0.0, 0.0, 1.0, 0.16)).cursor_pointer())
                            .when_some(on_close, |el, cb| {
                                el.on_mouse_down(MouseButton::Left, move |_, _, _| (cb)())
                            })
                            .child(
                                Icon::new(IconName::X)
                                    .size(px(12.0))
                                    .text_color(hsla(0.0, 0.0, 0.70, 1.0)),
                            ),
                    ),
            )
            // ── Quick Toggle Grid (Wi-Fi & Bluetooth Cards) ──
            .child(
                div()
                    .flex()
                    .gap(px(10.0))
                    // Wi-Fi Tile
                    .child(
                        div()
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
                            .gap(px(8.0))
                            .child(
                                div()
                                    .w(px(28.0))
                                    .h(px(28.0))
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
                                            .child(wifi_label),
                                    ),
                            ),
                    )
                    // Bluetooth Tile
                    .child(
                        div()
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
                            .gap(px(8.0))
                            .child(
                                div()
                                    .w(px(28.0))
                                    .h(px(28.0))
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
                                            .child(bt_label),
                                    ),
                            ),
                    ),
            )
            // ── Volume Slider Card ──
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
                                        div()
                                            .hover(|s| s.cursor_pointer())
                                            .when_some(on_mute, |el, cb| {
                                                el.on_mouse_down(MouseButton::Left, move |_, _, _| (cb)())
                                            })
                                            .child(
                                                Icon::new(if self.is_muted {
                                                    IconName::VolumeX
                                                } else {
                                                    IconName::Volume2
                                                })
                                                .size(px(14.0))
                                                .text_color(hsla(0.0, 0.0, 0.90, 1.0)),
                                            ),
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
                                    .text_xs()
                                    .font_weight(FontWeight::BOLD)
                                    .text_color(hsla(45.0 / 360.0, 0.90, 0.60, 1.0))
                                    .child(format!("{}%", self.volume_percent)),
                            ),
                    )
                    // Visual Volume Bar with step controls
                    .child(
                        div()
                            .relative()
                            .h(px(10.0))
                            .rounded_full()
                            .bg(hsla(0.0, 0.0, 1.0, 0.10))
                            .overflow_hidden()
                            .child(
                                div()
                                    .h_full()
                                    .w(px((self.volume_percent as f32 / 100.0) * 296.0))
                                    .rounded_full()
                                    .bg(if self.is_muted {
                                        hsla(0.0, 0.0, 0.40, 1.0)
                                    } else {
                                        hsla(45.0 / 360.0, 0.90, 0.60, 1.0)
                                    }),
                            ),
                    ),
            )
            // ── Battery & System Vitals Card ──
            .child(
                div()
                    .p(px(12.0))
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
                        div()
                            .text_xs()
                            .font_weight(FontWeight::BOLD)
                            .text_color(if self.is_charging {
                                hsla(142.0 / 360.0, 0.85, 0.55, 1.0)
                            } else {
                                hsla(0.0, 0.0, 0.95, 1.0)
                            })
                            .child(format!("{}%", self.battery_percent)),
                    ),
            )
    }
}
