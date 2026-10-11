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
    is_bluetooth_connected: bool,
    tray_items: Vec<beskar_core::models::TrayItem>,
    on_volume_click: Option<Arc<dyn Fn() + Send + Sync>>,
    on_volume_scroll: Option<Arc<dyn Fn(i32) + Send + Sync>>,
    on_power_click: Option<Arc<dyn Fn() + Send + Sync>>,
    on_control_center_click: Option<Arc<dyn Fn() + Send + Sync>>,
    on_capture_click: Option<Arc<dyn Fn() + Send + Sync>>,
    on_wallpaper_click: Option<Arc<dyn Fn() + Send + Sync>>,
    on_tray_click: Option<Arc<dyn Fn(String) + Send + Sync>>,
    on_tray_menu: Option<Arc<dyn Fn(String) + Send + Sync>>,
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
            is_bluetooth_connected: true,
            tray_items: Vec::new(),
            on_volume_click: None,
            on_volume_scroll: None,
            on_power_click: None,
            on_control_center_click: None,
            on_capture_click: None,
            on_wallpaper_click: None,
            on_tray_click: None,
            on_tray_menu: None,
        }
    }

    pub fn on_tray_click(mut self, handler: impl Fn(String) + Send + Sync + 'static) -> Self {
        self.on_tray_click = Some(Arc::new(handler));
        self
    }

    pub fn on_tray_menu(mut self, handler: impl Fn(String) + Send + Sync + 'static) -> Self {
        self.on_tray_menu = Some(Arc::new(handler));
        self
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

    pub fn bluetooth(mut self, connected: bool) -> Self {
        self.is_bluetooth_connected = connected;
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

    pub fn on_capture_click(mut self, handler: impl Fn() + Send + Sync + 'static) -> Self {
        self.on_capture_click = Some(Arc::new(handler));
        self
    }

    pub fn on_wallpaper_click(mut self, handler: impl Fn() + Send + Sync + 'static) -> Self {
        self.on_wallpaper_click = Some(Arc::new(handler));
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

        let on_tray_clk = self.on_tray_click;
        let on_tray_ctx = self.on_tray_menu;

        div()
            .flex()
            .items_center()
            .gap(px(6.0))
            // Render tray icons if any registered
            .when(!self.tray_items.is_empty(), |this| {
                let mut tray_row = div().flex().items_center().gap(px(4.0));
                for item in self.tray_items {
                    let icon_name = infer_tray_icon(&item.id, &item.icon, &item.title);
                    let item_id_left = item.id.clone();
                    let item_id_right = item.id.clone();
                    let on_tc = on_tray_clk.clone();
                    let on_tm = on_tray_ctx.clone();
                    let on_cc_fallback = on_cc.clone();

                    tray_row = tray_row.child(
                        div()
                            .w(px(24.0))
                            .h(px(24.0))
                            .rounded_md()
                            .flex()
                            .items_center()
                            .justify_center()
                            .text_color(hsla(0.0, 0.0, 0.85, 1.0))
                            .hover(|s| {
                                s.bg(beskar_theme::Theme::bg_secondary())
                                    .text_color(beskar_theme::Theme::accent())
                                    .cursor_pointer()
                            })
                            .on_mouse_down(MouseButton::Left, move |_, _, _| {
                                if let Some(ref cb) = on_tc {
                                    cb(item_id_left.clone());
                                } else if let Some(ref cb) = on_cc_fallback {
                                    cb();
                                }
                            })
                            .on_mouse_down(MouseButton::Right, move |_, _, _| {
                                if let Some(ref cb) = on_tm {
                                    cb(item_id_right.clone());
                                }
                            })
                            .child(Icon::new(icon_name).size(px(14.0))),
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
                    .w(px(26.0))
                    .h(px(24.0))
                    .rounded_md()
                    .flex()
                    .items_center()
                    .justify_center()
                    .text_color(hsla(0.0, 0.0, 0.80, 1.0))
                    .hover(|style| {
                        style
                            .bg(beskar_theme::Theme::bg_secondary())
                            .text_color(beskar_theme::Theme::accent())
                            .cursor_pointer()
                    })
                    .when_some(on_cc.clone(), |el, cb| {
                        el.on_mouse_down(MouseButton::Left, move |_, _, _| (cb)())
                    })
                    .child(
                        Icon::new(IconName::SlidersHorizontal)
                            .size(px(14.0))
                            .text_color(hsla(0.0, 0.0, 0.80, 1.0)),
                    ),
            )
            // Screen Capture quick trigger
            .child(
                div()
                    .w(px(26.0))
                    .h(px(24.0))
                    .rounded_md()
                    .flex()
                    .items_center()
                    .justify_center()
                    .text_color(hsla(0.0, 0.0, 0.80, 1.0))
                    .hover(|style| {
                        style
                            .bg(beskar_theme::Theme::bg_secondary())
                            .text_color(beskar_theme::Theme::accent())
                            .cursor_pointer()
                    })
                    .when_some(self.on_capture_click, |el, cb| {
                        el.on_mouse_down(MouseButton::Left, move |_, _, _| (cb)())
                    })
                    .child(
                        Icon::new(IconName::Camera)
                            .size(px(14.0))
                            .text_color(hsla(0.0, 0.0, 0.80, 1.0)),
                    ),
            )
            // Wallpaper Gallery quick trigger
            .child(
                div()
                    .w(px(26.0))
                    .h(px(24.0))
                    .rounded_md()
                    .flex()
                    .items_center()
                    .justify_center()
                    .text_color(hsla(0.0, 0.0, 0.80, 1.0))
                    .hover(|style| {
                        style
                            .bg(beskar_theme::Theme::bg_secondary())
                            .text_color(beskar_theme::Theme::accent())
                            .cursor_pointer()
                    })
                    .when_some(self.on_wallpaper_click, |el, cb| {
                        el.on_mouse_down(MouseButton::Left, move |_, _, _| (cb)())
                    })
                    .child(
                        Icon::new(IconName::Image)
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
                    .px(px(6.0))
                    .py(px(2.0))
                    .rounded_md()
                    .text_color(volume_color)
                    .hover(|style| {
                        style
                            .bg(beskar_theme::Theme::bg_secondary())
                            .text_color(hsla(0.0, 0.0, 1.0, 1.0))
                            .cursor_pointer()
                    })
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
            // Network Wi-Fi icon & trigger
            .child(
                div()
                    .w(px(26.0))
                    .h(px(24.0))
                    .rounded_md()
                    .flex()
                    .items_center()
                    .justify_center()
                    .hover(|style| {
                        style
                            .bg(beskar_theme::Theme::bg_secondary())
                            .cursor_pointer()
                    })
                    .when_some(on_cc.clone(), |el, cb| {
                        el.on_mouse_down(MouseButton::Left, move |_, _, _| (cb)())
                    })
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
            // Bluetooth icon & trigger
            .child(
                div()
                    .w(px(26.0))
                    .h(px(24.0))
                    .rounded_md()
                    .flex()
                    .items_center()
                    .justify_center()
                    .hover(|style| {
                        style
                            .bg(beskar_theme::Theme::bg_secondary())
                            .cursor_pointer()
                    })
                    .when_some(on_cc.clone(), |el, cb| {
                        el.on_mouse_down(MouseButton::Left, move |_, _, _| (cb)())
                    })
                    .child(
                        Icon::new(IconName::Bluetooth)
                            .size(px(14.0))
                            .text_color(if self.is_bluetooth_connected {
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
                    .px(px(6.0))
                    .py(px(2.0))
                    .rounded_md()
                    .text_color(battery_color)
                    .hover(|style| {
                        style
                            .bg(beskar_theme::Theme::bg_secondary())
                            .cursor_pointer()
                    })
                    .when_some(on_cc.clone(), |el, cb| {
                        el.on_mouse_down(MouseButton::Left, move |_, _, _| (cb)())
                    })
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
                    .w(px(26.0))
                    .h(px(24.0))
                    .rounded_md()
                    .flex()
                    .items_center()
                    .justify_center()
                    .hover(|style| {
                        style
                            .bg(hsla(350.0 / 360.0, 0.85, 0.50, 0.20))
                            .text_color(hsla(350.0 / 360.0, 0.90, 0.65, 1.0))
                            .cursor_pointer()
                    })
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

fn infer_tray_icon(id: &str, icon_name: &str, title: &str) -> IconName {
    let lower = format!(
        "{} {} {}",
        id.to_lowercase(),
        icon_name.to_lowercase(),
        title.to_lowercase()
    );

    if lower.contains("firefox") || lower.contains("chrome") || lower.contains("chromium") || lower.contains("browser") {
        IconName::Globe
    } else if lower.contains("discord") || lower.contains("vesktop") {
        IconName::MessageSquare
    } else if lower.contains("telegram") {
        IconName::Send
    } else if lower.contains("slack") {
        IconName::MessageCircle
    } else if lower.contains("spotify") || lower.contains("music") {
        IconName::Music
    } else if lower.contains("bluetooth") || lower.contains("blue") {
        IconName::Bluetooth
    } else if lower.contains("wifi") || lower.contains("network") || lower.contains("nm-") {
        IconName::Wifi
    } else if lower.contains("audio") || lower.contains("volume") || lower.contains("pulse") {
        IconName::Volume2
    } else if lower.contains("battery") || lower.contains("power") {
        IconName::BatteryCharging
    } else if lower.contains("settings") {
        IconName::Settings
    } else if lower.contains("cloud") || lower.contains("sync") || lower.contains("dropbox") || lower.contains("nextcloud") {
        IconName::Cloud
    } else {
        IconName::AppWindow
    }
}
