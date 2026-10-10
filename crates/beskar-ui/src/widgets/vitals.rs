use gpui_kit::prelude::FluentBuilder;
use gpui_kit::*;
use gpui_kit::assets::IconName;
use gpui_kit::component::Icon;
use std::sync::Arc;

/// Right Island vitals cluster adapted from minflair & gpui-shell.
/// Features:
/// - Active recording badge (`• 0:01`)
/// - Control Center trigger
/// - PipeWire Volume indicator with mute awareness
/// - Network indicator
/// - Battery icon & percentage with charging badge
/// - Power menu trigger
#[derive(IntoElement)]
pub struct VitalsWidget {
    recording_time: Option<String>,
    volume_percent: u8,
    is_muted: bool,
    battery_percent: u8,
    is_charging: bool,
    is_wifi_connected: bool,
    tray_items: Vec<beskar_core::models::TrayItem>,
    on_volume_click: Option<Arc<dyn Fn() + Send + Sync>>,
    on_volume_scroll: Option<Arc<dyn Fn(i32) + Send + Sync>>,
    on_power_click: Option<Arc<dyn Fn() + Send + Sync>>,
    on_control_center_click: Option<Arc<dyn Fn() + Send + Sync>>,
}

impl VitalsWidget {
    pub fn new(volume_percent: u8, battery_percent: u8) -> Self {
        Self {
            recording_time: None,
            volume_percent,
            is_muted: false,
            battery_percent,
            is_charging: false,
            is_wifi_connected: true,
            tray_items: Vec::new(),
            on_volume_click: None,
            on_volume_scroll: None,
            on_power_click: None,
            on_control_center_click: None,
        }
    }

    pub fn tray(mut self, items: Vec<beskar_core::models::TrayItem>) -> Self {
        self.tray_items = items;
        self
    }

    pub fn on_volume_scroll(mut self, handler: impl Fn(i32) + Send + Sync + 'static) -> Self {
        self.on_volume_scroll = Some(Arc::new(handler));
        self
    }

    pub fn recording(mut self, time: Option<String>) -> Self {
        self.recording_time = time;
        self
    }

    pub fn muted(mut self, muted: bool) -> Self {
        self.is_muted = muted;
        self
    }

    pub fn charging(mut self, charging: bool) -> Self {
        self.is_charging = charging;
        self
    }

    pub fn on_volume_click(mut self, handler: impl Fn() + Send + Sync + 'static) -> Self {
        self.on_volume_click = Some(Arc::new(handler));
        self
    }

    pub fn on_power_click(mut self, handler: impl Fn() + Send + Sync + 'static) -> Self {
        self.on_power_click = Some(Arc::new(handler));
        self
    }

    pub fn on_control_center_click(mut self, handler: impl Fn() + Send + Sync + 'static) -> Self {
        self.on_control_center_click = Some(Arc::new(handler));
        self
    }
}

impl RenderOnce for VitalsWidget {
    fn render(self, _window: &mut Window, _cx: &mut App) -> impl IntoElement {
        let is_recording = self.recording_time.is_some();
        let on_vol = self.on_volume_click;
        let on_pwr = self.on_power_click;
        let on_cc = self.on_control_center_click;

        let battery_icon = if self.is_charging {
            IconName::BatteryCharging
        } else if self.battery_percent > 80 {
            IconName::BatteryFull
        } else if self.battery_percent > 30 {
            IconName::BatteryMedium
        } else {
            IconName::BatteryLow
        };

        let battery_color = if self.is_charging {
            hsla(142.0 / 360.0, 0.85, 0.55, 1.0)
        } else if self.battery_percent <= 20 {
            hsla(10.0 / 360.0, 0.85, 0.60, 1.0)
        } else {
            hsla(0.0, 0.0, 0.90, 1.0)
        };

        let volume_icon = if self.is_muted {
            IconName::VolumeX
        } else {
            IconName::Volume2
        };

        let volume_color = if self.is_muted {
            hsla(0.0, 0.0, 0.50, 1.0)
        } else {
            hsla(0.0, 0.0, 0.90, 1.0)
        };

        let on_scroll = self.on_volume_scroll;

        div()
            .flex()
            .items_center()
            .gap(px(12.0))
            // Render tray icons if any registered
            .when(!self.tray_items.is_empty(), |this| {
                let mut tray_row = div().flex().items_center().gap(px(6.0));
                for _item in self.tray_items {
                    tray_row = tray_row.child(
                        div()
                            .w(px(16.0))
                            .h(px(16.0))
                            .flex()
                            .items_center()
                            .justify_center()
                            .hover(|s| s.cursor_pointer())
                            .child(
                                // Dot badge for registered tray items
                                div()
                                    .w(px(8.0))
                                    .h(px(8.0))
                                    .rounded_full()
                                    .bg(hsla(45.0 / 360.0, 0.90, 0.60, 0.90))
                                    .hover(|s| s.bg(hsla(45.0 / 360.0, 1.0, 0.75, 1.0))),
                            ),
                    );
                }
                this.child(tray_row)
                    .child(div().w(px(1.0)).h(px(12.0)).bg(hsla(0.0, 0.0, 1.0, 0.12)))
            })
            // Recording badge: green pulsing dot + timer
            .when(is_recording, |this| {
                this.child(
                    div()
                        .flex()
                        .items_center()
                        .gap(px(5.0))
                        .px(px(6.0))
                        .py(px(2.0))
                        .rounded_full()
                        .bg(hsla(142.0 / 360.0, 0.70, 0.30, 0.25))
                        .child(
                            div()
                                .w(px(6.0))
                                .h(px(6.0))
                                .rounded_full()
                                .bg(hsla(142.0 / 360.0, 0.85, 0.55, 1.0)),
                        )
                        .child(
                            div()
                                .text_xs()
                                .font_weight(FontWeight::MEDIUM)
                                .text_color(hsla(0.0, 0.0, 0.90, 1.0))
                                .child(self.recording_time.unwrap_or_default()),
                        ),
                )
            })
            // Sliders / Control Center button
            .child(
                div()
                    .w(px(16.0))
                    .h(px(16.0))
                    .flex()
                    .items_center()
                    .justify_center()
                    .text_color(hsla(0.0, 0.0, 0.80, 1.0))
                    .hover(|style| style.text_color(hsla(45.0 / 360.0, 0.90, 0.60, 1.0)).cursor_pointer())
                    .when_some(on_cc, |el, cb| {
                        el.on_mouse_down(MouseButton::Left, move |_, _, _| (cb)())
                    })
                    .child(
                        Icon::new(IconName::SlidersHorizontal)
                            .size(px(14.0))
                            .text_color(hsla(0.0, 0.0, 0.80, 1.0)),
                    ),
            )
            // Volume icon & indicator with scroll-to-step volume support
            .child(
                div()
                    .flex()
                    .items_center()
                    .gap(px(4.0))
                    .text_color(volume_color)
                    .hover(|style| style.text_color(hsla(0.0, 0.0, 1.0, 1.0)).cursor_pointer())
                    .when_some(on_vol, |el, cb| {
                        el.on_mouse_down(MouseButton::Left, move |_, _, _| (cb)())
                    })
                    .when_some(on_scroll, |el, cb| {
                        el.on_scroll_wheel(move |event, _, _| {
                            let delta = if event.delta.pixel_delta(px(1.0)).y > px(0.0) { 2 } else { -2 };
                            (cb)(delta);
                        })
                    })
                    .child(Icon::new(volume_icon).size(px(14.0)).text_color(volume_color))
                    .child(
                        div()
                            .text_xs()
                            .font_weight(FontWeight::MEDIUM)
                            .child(if self.is_muted {
                                "Mute".to_string()
                            } else {
                                format!("{}%", self.volume_percent)
                            }),
                    ),
            )
            // Network icon
            .child(
                div()
                    .w(px(16.0))
                    .h(px(16.0))
                    .flex()
                    .items_center()
                    .justify_center()
                    .child(
                        Icon::new(if self.is_wifi_connected {
                            IconName::Wifi
                        } else {
                            IconName::WifiOff
                        })
                        .size(px(14.0))
                        .text_color(if self.is_wifi_connected {
                            hsla(0.0, 0.0, 0.85, 1.0)
                        } else {
                            hsla(0.0, 0.0, 0.40, 1.0)
                        }),
                    ),
            )
            // Battery icon & percentage
            .child(
                div()
                    .flex()
                    .items_center()
                    .gap(px(4.0))
                    .text_color(battery_color)
                    .child(Icon::new(battery_icon).size(px(14.0)).text_color(battery_color))
                    .child(
                        div()
                            .text_xs()
                            .font_weight(FontWeight::MEDIUM)
                            .child(format!("{}%", self.battery_percent)),
                    ),
            )
            // Power button
            .child(
                div()
                    .w(px(16.0))
                    .h(px(16.0))
                    .flex()
                    .items_center()
                    .justify_center()
                    .hover(|style| style.text_color(hsla(350.0 / 360.0, 0.85, 0.60, 1.0)).cursor_pointer())
                    .when_some(on_pwr, |el, cb| {
                        el.on_mouse_down(MouseButton::Left, move |_, _, _| (cb)())
                    })
                    .child(
                        Icon::new(IconName::Power)
                            .size(px(14.0))
                            .text_color(hsla(0.0, 0.0, 0.70, 1.0)),
                    ),
            )
    }
}
