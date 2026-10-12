pub mod bt_list;
pub mod footer;
pub mod header;
pub mod power_profiles;
pub mod quick_toggles;
pub mod sliders;
pub mod wifi_list;

use beskar_services::{BluetoothDeviceItem, WifiAccessPoint};
use gpui_kit::component::slider::SliderState;
use gpui_kit::prelude::FluentBuilder;
use gpui_kit::*;
use std::sync::Arc;

/// Quick Settings & Control Center popover card.
/// Modularized architecture with subcomponents for quick toggles, sliders, lists, and profiles.
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
    volume_slider: Option<Entity<SliderState>>,
    brightness_slider: Option<Entity<SliderState>>,
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
            volume_slider: None,
            brightness_slider: None,
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

    pub fn volume_slider(mut self, slider: Entity<SliderState>) -> Self {
        self.volume_slider = Some(slider);
        self
    }

    pub fn brightness_slider(mut self, slider: Entity<SliderState>) -> Self {
        self.brightness_slider = Some(slider);
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
        let wifi_label = self.wifi_ssid.unwrap_or_else(|| {
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
            .bg(beskar_theme::Theme::card_bg())
            .border_1()
            .border_color(beskar_theme::Theme::card_border())
            .shadow_xl()
            .flex()
            .flex_col()
            .gap(px(12.0))
            // 1. Header
            .child(header::render_header(self.on_close))
            // 2. Quick Toggles Grid
            .child(quick_toggles::render_quick_toggles(
                self.is_wifi_on,
                wifi_label,
                self.show_wifi_list,
                self.on_toggle_wifi,
                self.on_toggle_wifi_list,
                self.is_bt_on,
                bt_label,
                self.show_bt_list,
                self.on_toggle_bluetooth,
                self.on_toggle_bt_list,
            ))
            // 3. Expandable Wi-Fi List
            .when(self.show_wifi_list, |parent| {
                parent.child(wifi_list::render_wifi_list(
                    &self.wifi_networks,
                    self.on_connect_wifi,
                ))
            })
            // 4. Expandable Bluetooth List
            .when(self.show_bt_list, |parent| {
                parent.child(bt_list::render_bt_list(&self.bt_devices))
            })
            // 5. Volume Slider
            .child(sliders::render_volume_card(
                self.volume_percent,
                self.is_muted,
                self.volume_slider.as_ref(),
                self.on_toggle_mute,
            ))
            // 6. Brightness Slider
            .child(sliders::render_brightness_card(
                self.brightness_percent,
                self.brightness_slider.as_ref(),
            ))
            // 7. Power Profile Selector
            .child(power_profiles::render_power_profiles(
                &self.active_power_profile,
                self.on_set_power_profile,
            ))
            // 8. Battery Vitals
            .child(power_profiles::render_battery_card(
                self.battery_percent,
                self.is_charging,
            ))
            // 9. Quick Actions Footer
            .child(footer::render_footer(
                self.on_open_launcher,
                self.on_open_clipboard,
                self.on_open_settings,
                self.on_open_power,
            ))
    }
}
