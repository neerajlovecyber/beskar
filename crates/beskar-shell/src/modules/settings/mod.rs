use beskar_core::config::{BarStyleConfig, ShellConfig, ThemePresetConfig};
use beskar_services::audio::AudioService;
use beskar_services::battery::BatteryService;
pub mod animator;
pub mod helpers;
pub mod pages;
pub mod view;

pub use self::view::{SettingsCategory, SettingsConfig, SettingsWidget};
use self::animator::SettingsAnimator;
use gpui_kit::*;

use crate::panel_host::{LayerAnchor, PanelHost, PanelModule, Slot};

#[derive(Debug, Clone)]
enum SettingsMsg {
    SelectCategory(SettingsCategory),
    ToggleNotch(bool),
    ToggleWindowTitle(bool),
    ToggleMedia(bool),
    SelectAccent(usize),
    SelectPreset(beskar_theme::ThemePreset),
    ToggleLockBlur(bool),
    ToggleLockLyrics(bool),
    TestNotification,
    Close,
}

/// Dedicated View for Settings / Preferences
pub struct SettingsView {
    config: SettingsConfig,
    animator: SettingsAnimator,
    focus_handle: FocusHandle,
    msg_tx: tokio::sync::mpsc::UnboundedSender<SettingsMsg>,
}

impl PanelModule for SettingsView {
    const ID: &'static str = "settings";

    fn slot() -> Slot {
        Slot::Focus
    }

    fn size() -> Size<Pixels> {
        Size::new(px(SettingsWidget::WIDTH), px(SettingsWidget::HEIGHT))
    }

    fn anchor() -> LayerAnchor {
        LayerAnchor::TOP
    }

    fn margin() -> (Pixels, Pixels, Pixels, Pixels) {
        (px(40.0), px(0.0), px(0.0), px(0.0))
    }

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
        config.lockscreen_blur = shell_cfg.lockscreen_blur;
        config.lockscreen_show_lyrics = shell_cfg.lockscreen_show_lyrics;
        config.clock_format = shell_cfg.clock_format.clone();

        let animator = SettingsAnimator::new(shell_cfg.animation_duration_ms as u64);

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
                        this.animator.start_section_transition(std::time::Duration::from_millis(200));
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
                    SettingsMsg::ToggleLockBlur(val) => {
                        this.config.lockscreen_blur = val;
                        let mut shell_cfg = ShellConfig::load();
                        shell_cfg.lockscreen_blur = val;
                        let _ = shell_cfg.save();
                        cx.notify();
                    }
                    SettingsMsg::ToggleLockLyrics(val) => {
                        this.config.lockscreen_show_lyrics = val;
                        let mut shell_cfg = ShellConfig::load();
                        shell_cfg.lockscreen_show_lyrics = val;
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
            animator,
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
        let tx_blur = self.msg_tx.clone();
        let tx_lyrics = self.msg_tx.clone();
        let tx_test = self.msg_tx.clone();
        let tx_close = self.msg_tx.clone();

        let (running, _) = self.animator.advance(std::time::Instant::now());
        if running {
            _window.request_animation_frame();
        }

        div()
            .id("settings-card")
            .w(px(SettingsWidget::WIDTH))
            .h(px(SettingsWidget::HEIGHT))
            .opacity(self.animator.card_opacity)
            .track_focus(&self.focus_handle)
            .key_context("Settings")
            .on_key_down(cx.listener(|_, event: &KeyDownEvent, _window, cx| {
                if event.keystroke.key == "escape" {
                    PanelHost::close(cx);
                    cx.stop_propagation();
                }
            }))
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
                    .on_toggle_lockscreen_blur(move |val| {
                        let _ = tx_blur.send(SettingsMsg::ToggleLockBlur(val));
                    })
                    .on_toggle_lockscreen_lyrics(move |val| {
                        let _ = tx_lyrics.send(SettingsMsg::ToggleLockLyrics(val));
                    })
                    .on_test_notification(move || {
                        let _ = tx_test.send(SettingsMsg::TestNotification);
                    })
                    .on_close(move || {
                        let _ = tx_close.send(SettingsMsg::Close);
                    }),
            )
    }
}
