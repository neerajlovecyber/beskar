use gpui_kit::assets::IconName;
use gpui_kit::component::button::{Button, ButtonVariants};
use gpui_kit::component::tag::Tag;
use gpui_kit::component::Icon;
use gpui_kit::prelude::FluentBuilder;
use gpui_kit::*;
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
    cpu_usage: Option<f32>,
    ram_usage: Option<f32>,
    modules: Option<Vec<beskar_core::config::BarModule>>,
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
            cpu_usage: None,
            ram_usage: None,
            modules: None,
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

    pub fn modules(mut self, modules: Vec<beskar_core::config::BarModule>) -> Self {
        self.modules = Some(modules);
        self
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

    pub fn cpu(mut self, usage: Option<f32>) -> Self {
        self.cpu_usage = usage;
        self
    }

    pub fn ram(mut self, usage: Option<f32>) -> Self {
        self.ram_usage = usage;
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
            beskar_theme::Theme::success()
        } else if self.battery_percent <= 20 {
            beskar_theme::Theme::danger()
        } else {
            beskar_theme::Theme::fg()
        };

        let volume_icon = if self.is_muted {
            IconName::VolumeX
        } else {
            IconName::Volume2
        };

        let volume_color = if self.is_muted {
            beskar_theme::Theme::muted()
        } else {
            beskar_theme::Theme::fg()
        };

        let on_scroll = self.on_volume_scroll;

        let on_tray_clk = self.on_tray_click;
        let _on_tray_ctx = self.on_tray_menu;

        let has_tray = self.modules.as_ref().map_or(true, |m| m.contains(&beskar_core::config::BarModule::Tray));
        let has_controls = self.modules.as_ref().map_or(true, |m| m.contains(&beskar_core::config::BarModule::QuickControls));
        let has_vitals = self.modules.as_ref().map_or(true, |m| m.contains(&beskar_core::config::BarModule::Vitals));
        let has_power = self.modules.as_ref().map_or(true, |m| m.contains(&beskar_core::config::BarModule::Power));

        div()
            .flex()
            .items_center()
            .gap(px(6.0))
            // Render tray icons if any registered and enabled
            .when(has_tray && !self.tray_items.is_empty(), |this| {
                let mut tray_row = div().flex().items_center().gap(px(4.0));
                for item in self.tray_items {
                    let icon_name = infer_tray_icon(&item.id, &item.icon, &item.title);
                    let item_id_left = item.id.clone();
                    let on_tc = on_tray_clk.clone();
                    let on_cc_fallback = on_cc.clone();

                    tray_row = tray_row.child(
                        Button::new(SharedString::from(format!("tray-btn-{}", item.id)))
                            .ghost()
                            .compact()
                            .icon(
                                Icon::new(icon_name)
                                    .size(px(14.0))
                                    .text_color(beskar_theme::Theme::fg()),
                            )
                            .on_click(move |_, _, _| {
                                if let Some(ref cb) = on_tc {
                                    cb(item_id_left.clone());
                                } else if let Some(ref cb) = on_cc_fallback {
                                    cb();
                                }
                            }),
                    );
                }
                this.child(tray_row)
                    .child(div().w(px(1.0)).h(px(12.0)).bg(beskar_theme::Theme::subtle_border()))
            })
            // Recording badge: green pulsing dot + timer
            .when(is_recording, |this| {
                this.child(
                    Tag::danger()
                        .child(self.recording_time.unwrap_or_default()),
                )
            })
            // Quick Controls triggers (Control Center, Screen Capture, Wallpaper Gallery)
            .when(has_controls, |this| {
                this.child(
                    Button::new("vitals-cc")
                        .ghost()
                        .compact()
                        .icon(
                            Icon::new(IconName::SlidersHorizontal)
                                .size(px(14.0))
                                .text_color(beskar_theme::Theme::fg()),
                        )
                        .when_some(on_cc.clone(), |btn, cb| {
                            btn.on_click(move |_, _, _| (cb)())
                        }),
                )
                .child(
                    Button::new("vitals-capture")
                        .ghost()
                        .compact()
                        .icon(
                            Icon::new(IconName::Camera)
                                .size(px(14.0))
                                .text_color(beskar_theme::Theme::fg()),
                        )
                        .when_some(self.on_capture_click, |btn, cb| {
                            btn.on_click(move |_, _, _| (cb)())
                        }),
                )
                .child(
                    Button::new("vitals-wallpaper")
                        .ghost()
                        .compact()
                        .icon(
                            Icon::new(IconName::Image)
                                .size(px(14.0))
                                .text_color(beskar_theme::Theme::fg()),
                        )
                        .when_some(self.on_wallpaper_click, |btn, cb| {
                            btn.on_click(move |_, _, _| (cb)())
                        }),
                )
            })
            // Hardware Vitals (CPU, RAM, Volume, Wi-Fi, Bluetooth, Battery)
            .when(has_vitals, |this| {
                let this = this
                    .when_some(self.cpu_usage, |this, cpu| {
                        let color = if cpu > 80.0 {
                            beskar_theme::Theme::danger()
                        } else if cpu > 50.0 {
                            beskar_theme::Theme::warning()
                        } else {
                            beskar_theme::Theme::fg()
                        };
                        this.child(
                            div()
                                .flex()
                                .items_center()
                                .gap(px(3.0))
                                .px(px(5.0))
                                .py(px(2.0))
                                .rounded_md()
                                .text_color(color)
                                .hover(|s| s.bg(beskar_theme::Theme::bg_secondary()))
                                .child(Icon::new(IconName::Cpu).size(px(13.0)).text_color(color))
                                .child(
                                    div()
                                        .text_xs()
                                        .font_weight(FontWeight::MEDIUM)
                                        .child(format!("{:.0}%", cpu)),
                                ),
                        )
                    })
                    .when_some(self.ram_usage, |this, ram| {
                        let color = if ram > 85.0 {
                            beskar_theme::Theme::danger()
                        } else if ram > 70.0 {
                            beskar_theme::Theme::warning()
                        } else {
                            beskar_theme::Theme::fg()
                        };
                        this.child(
                            div()
                                .flex()
                                .items_center()
                                .gap(px(3.0))
                                .px(px(5.0))
                                .py(px(2.0))
                                .rounded_md()
                                .text_color(color)
                                .hover(|s| s.bg(beskar_theme::Theme::bg_secondary()))
                                .child(Icon::new(IconName::HardDrive).size(px(13.0)).text_color(color))
                                .child(
                                    div()
                                        .text_xs()
                                        .font_weight(FontWeight::MEDIUM)
                                        .child(format!("{:.0}%", ram)),
                                ),
                        )
                    });

                this.child(
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
                                .text_color(beskar_theme::Theme::fg())
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
                .child(
                    Button::new("vitals-wifi")
                        .ghost()
                        .compact()
                        .icon(
                            Icon::new(if self.is_wifi_connected {
                                IconName::Wifi
                            } else {
                                IconName::WifiOff
                            })
                            .size(px(14.0))
                            .text_color(if self.is_wifi_connected {
                                beskar_theme::Theme::fg()
                            } else {
                                beskar_theme::Theme::muted()
                            }),
                        )
                        .when_some(on_cc.clone(), |btn, cb| {
                            btn.on_click(move |_, _, _| (cb)())
                        }),
                )
                .child(
                    Button::new("vitals-bluetooth")
                        .ghost()
                        .compact()
                        .icon(
                            Icon::new(IconName::Bluetooth)
                                .size(px(14.0))
                                .text_color(if self.is_bluetooth_connected {
                                    beskar_theme::Theme::accent()
                                } else {
                                    beskar_theme::Theme::muted()
                                }),
                        )
                        .when_some(on_cc.clone(), |btn, cb| {
                            btn.on_click(move |_, _, _| (cb)())
                        }),
                )
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
            })
            // Power button trigger
            .when(has_power, |this| {
                this.child(
                    Button::new("vitals-power")
                        .danger()
                        .ghost()
                        .compact()
                        .icon(
                            Icon::new(IconName::Power)
                                .size(px(14.0))
                                .text_color(beskar_theme::Theme::danger()),
                        )
                        .when_some(on_pwr, |btn, cb| {
                            btn.on_click(move |_, _, _| (cb)())
                        }),
                )
            })
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
