use beskar_core::config::{BarStyleConfig, ShellConfig, ThemePresetConfig};
use beskar_services::audio::AudioService;
use beskar_services::battery::BatteryService;
pub mod helpers;
pub mod pages;
pub mod view;

pub use self::view::{SettingsCategory, SettingsConfig, SettingsWidget};
use gpui_kit::*;

use crate::panel_host::{PanelHost, PanelModule};

#[derive(Debug, Clone)]
enum SettingsMsg {
    SelectCategory(SettingsCategory),
    ToggleNotch(bool),
    ToggleWindowTitle(bool),
    ToggleMedia(bool),
    SelectAccent(usize),
    SelectPreset(beskar_theme::ThemePreset),
    TestNotification,
    Close,
}

/// Dedicated View for Settings / Preferences
pub struct SettingsView {
    config: SettingsConfig,
    focus_handle: FocusHandle,
    msg_tx: tokio::sync::mpsc::UnboundedSender<SettingsMsg>,
}

impl PanelModule for SettingsView {
    const ID: &'static str = "settings";

    fn build(cx: &mut Context<Self>) -> Self {
        Self::new(cx)
    }
}

impl SettingsView {
    pub fn new(cx: &mut Context<Self>) -> Self {
        let focus_handle = cx.focus_handle();
        let (msg_tx, mut msg_rx) = tokio::sync::mpsc::unbounded_channel::<SettingsMsg>();

        let mut config = SettingsConfig::default();
        let shell_cfg = ShellConfig::load();
        config.island_mode_notch = shell_cfg.bar_style == BarStyleConfig::Convex;
        config.show_active_window_title = shell_cfg.show_workspaces;
        config.morph_on_media = shell_cfg.show_media_in_center;

        let aud = AudioService::read_state();
        let bat = BatteryService::new().read_state();
        let (is_wifi_on, _) = beskar_services::NetworkHelper::get_wifi_status();
        let is_bt_on = beskar_services::BluetoothHelper::get_bluetooth_status();
        config.volume_percent = (aud.volume * 100.0).round() as u8;
        config.battery_percent = bat.percentage.round() as u8;
        config.is_wifi_on = is_wifi_on;
        config.is_bt_on = is_bt_on;

        cx.spawn(async move |this, cx| {
            while let Some(msg) = msg_rx.recv().await {
                let _ = this.update(cx, |this, cx| match msg {
                    SettingsMsg::SelectCategory(cat) => {
                        this.config.active_category = cat;
                        cx.notify();
                    }
                    SettingsMsg::ToggleNotch(val) => {
                        this.config.island_mode_notch = val;
                        let mut shell_cfg = ShellConfig::load();
                        shell_cfg.bar_style = if val {
                            BarStyleConfig::Convex
                        } else {
                            BarStyleConfig::Island
                        };
                        let _ = shell_cfg.save();
                        cx.notify();
                    }
                    SettingsMsg::ToggleWindowTitle(val) => {
                        this.config.show_active_window_title = val;
                        let mut shell_cfg = ShellConfig::load();
                        shell_cfg.show_workspaces = val;
                        let _ = shell_cfg.save();
                        cx.notify();
                    }
                    SettingsMsg::ToggleMedia(val) => {
                        this.config.morph_on_media = val;
                        let mut shell_cfg = ShellConfig::load();
                        shell_cfg.show_media_in_center = val;
                        let _ = shell_cfg.save();
                        cx.notify();
                    }
                    SettingsMsg::SelectAccent(idx) => {
                        this.config.accent_color_idx = idx;
                        cx.notify();
                    }
                    SettingsMsg::SelectPreset(preset) => {
                        beskar_theme::ThemeEngine::set_preset(preset);
                        let mut shell_cfg = ShellConfig::load();
                        shell_cfg.theme_preset = match preset {
                            beskar_theme::ThemePreset::Obsidian => ThemePresetConfig::ObsidianGlass,
                            beskar_theme::ThemePreset::CatppuccinMocha => ThemePresetConfig::CatppuccinMocha,
                            beskar_theme::ThemePreset::GruvboxDark => ThemePresetConfig::GruvboxDark,
                            beskar_theme::ThemePreset::Wallpaper => ThemePresetConfig::WallpaperAuto,
                        };
                        let _ = shell_cfg.save();
                        cx.notify();
                    }
                    SettingsMsg::TestNotification => {
                        beskar_services::notifications::send_test(
                            "Beskar Shell",
                            "Dynamic island and control center settings updated!",
                        );
                    }
                    SettingsMsg::Close => {
                        PanelHost::close(cx);
                    }
                });
            }
        })
        .detach();

        Self {
            config,
            focus_handle,
            msg_tx,
        }
    }
}

impl Focusable for SettingsView {
    fn focus_handle(&self, _cx: &App) -> FocusHandle {
        self.focus_handle.clone()
    }
}

impl Render for SettingsView {
    fn render(&mut self, _window: &mut Window, cx: &mut Context<Self>) -> impl IntoElement {
        let tx_cat = self.msg_tx.clone();
        let tx_notch = self.msg_tx.clone();
        let tx_win = self.msg_tx.clone();
        let tx_media = self.msg_tx.clone();
        let tx_accent = self.msg_tx.clone();
        let tx_preset = self.msg_tx.clone();
        let tx_test = self.msg_tx.clone();
        let tx_close = self.msg_tx.clone();

        div()
            .id("settings-backdrop")
            .size_full()
            .flex()
            .items_center()
            .justify_center()
            .track_focus(&self.focus_handle)
            .key_context("Settings")
            .on_mouse_down(MouseButton::Left, move |_, window, _cx| {
                PanelHost::forget(SettingsView::ID);
                window.remove_window();
            })
            .on_key_down(cx.listener(|_, event: &KeyDownEvent, window, cx| {
                if event.keystroke.key == "escape" {
                    PanelHost::forget(SettingsView::ID);
                    window.remove_window();
                    cx.stop_propagation();
                }
            }))
            .child(
                div()
                    .on_mouse_down(MouseButton::Left, |_, _, cx| {
                        cx.stop_propagation();
                    })
                    .child(
                        SettingsWidget::new(self.config.clone())
                            .on_select_category(move |cat| {
                                let _ = tx_cat.send(SettingsMsg::SelectCategory(cat));
                            })
                            .on_toggle_notch_mode(move |val| {
                                let _ = tx_notch.send(SettingsMsg::ToggleNotch(val));
                            })
                            .on_toggle_window_title(move |val| {
                                let _ = tx_win.send(SettingsMsg::ToggleWindowTitle(val));
                            })
                            .on_toggle_media_morph(move |val| {
                                let _ = tx_media.send(SettingsMsg::ToggleMedia(val));
                            })
                            .on_select_accent(move |idx| {
                                let _ = tx_accent.send(SettingsMsg::SelectAccent(idx));
                            })
                            .on_select_preset(move |preset| {
                                let _ = tx_preset.send(SettingsMsg::SelectPreset(preset));
                            })
                            .on_test_notification(move || {
                                let _ = tx_test.send(SettingsMsg::TestNotification);
                            })
                            .on_close(move || {
                                let _ = tx_close.send(SettingsMsg::Close);
                            }),
                    ),
            )
    }
}
