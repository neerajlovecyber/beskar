use std::sync::Arc;

use gpui_kit::assets::IconName;
use gpui_kit::component::button::{Button, ButtonVariants};
use gpui_kit::component::Icon;
use gpui_kit::prelude::FluentBuilder;
use gpui_kit::*;

use super::pages::*;

/// Categories in the Settings window sidebar.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SettingsCategory {
    Appearance,
    Keybindings,
    Extensions,
    Apps,
    Media,
    LockScreen,
    System,
    Record,
    Notifications,
    General,
}

impl SettingsCategory {
    pub const ALL: [Self; 10] = [
        Self::Appearance,
        Self::Keybindings,
        Self::Extensions,
        Self::Apps,
        Self::Media,
        Self::LockScreen,
        Self::System,
        Self::Record,
        Self::Notifications,
        Self::General,
    ];

    pub fn title(&self) -> &'static str {
        match self {
            Self::Appearance => "Appearance",
            Self::Keybindings => "Shortcuts & Keybinds",
            Self::Extensions => "Extensions & Plugins",
            Self::Apps => "Apps",
            Self::Media => "Media",
            Self::LockScreen => "Lock Screen",
            Self::System => "System",
            Self::Record => "Screen Record",
            Self::Notifications => "Notifications",
            Self::General => "General",
        }
    }

    pub fn icon(&self) -> IconName {
        match self {
            Self::Appearance => IconName::Palette,
            Self::Keybindings => IconName::SquareTerminal,
            Self::Extensions => IconName::Blocks,
            Self::Apps => IconName::LayoutGrid,
            Self::Media => IconName::Music,
            Self::LockScreen => IconName::Lock,
            Self::System => IconName::Cpu,
            Self::Record => IconName::Video,
            Self::Notifications => IconName::Bell,
            Self::General => IconName::Settings2,
        }
    }
}

/// Settings configuration state passed to and modified by the Settings UI.
#[derive(Debug, Clone)]
pub struct SettingsConfig {
    pub active_category: SettingsCategory,
    pub accent_color_idx: usize,
    pub dark_mode: bool,
    pub island_mode_notch: bool,
    pub show_active_window_title: bool,
    pub morph_on_media: bool,
    pub bar_height: u32,
    pub corner_radius: u32,
    pub notification_timeout_secs: u32,
    pub is_wifi_on: bool,
    pub is_bt_on: bool,
    pub volume_percent: u8,
    pub battery_percent: u8,
    pub lockscreen_blur: bool,
    pub lockscreen_show_lyrics: bool,
    pub clock_format: String,
}

impl Default for SettingsConfig {
    fn default() -> Self {
        Self {
            active_category: SettingsCategory::Appearance,
            accent_color_idx: 0,
            dark_mode: true,
            island_mode_notch: false,
            show_active_window_title: true,
            morph_on_media: true,
            bar_height: 40,
            corner_radius: 18,
            notification_timeout_secs: 6,
            is_wifi_on: true,
            is_bt_on: true,
            volume_percent: 65,
            battery_percent: 85,
            lockscreen_blur: true,
            lockscreen_show_lyrics: true,
            clock_format: "%-I:%M %p".to_string(),
        }
    }
}

/// Dedicated macOS / iRiS preferences and settings window component.
/// Built with pure GPUI-Kit primitives.
#[derive(IntoElement)]
pub struct SettingsWidget {
    config: SettingsConfig,
    on_select_category: Option<Arc<dyn Fn(SettingsCategory) + Send + Sync>>,
    on_toggle_notch_mode: Option<Arc<dyn Fn(bool) + Send + Sync>>,
    on_toggle_window_title: Option<Arc<dyn Fn(bool) + Send + Sync>>,
    on_toggle_media_morph: Option<Arc<dyn Fn(bool) + Send + Sync>>,
    on_select_accent: Option<Arc<dyn Fn(usize) + Send + Sync>>,
    on_select_preset: Option<Arc<dyn Fn(beskar_theme::ThemePreset) + Send + Sync>>,
    on_test_notification: Option<Arc<dyn Fn() + Send + Sync>>,
    on_toggle_lockscreen_blur: Option<Arc<dyn Fn(bool) + Send + Sync>>,
    on_toggle_lockscreen_lyrics: Option<Arc<dyn Fn(bool) + Send + Sync>>,
    on_close: Option<Arc<dyn Fn() + Send + Sync>>,
}

impl SettingsWidget {
    pub const WIDTH: f32 = 1120.0;
    pub const HEIGHT: f32 = 780.0;

    pub fn new(config: SettingsConfig) -> Self {
        Self {
            config,
            on_select_category: None,
            on_toggle_notch_mode: None,
            on_toggle_window_title: None,
            on_toggle_media_morph: None,
            on_select_accent: None,
            on_select_preset: None,
            on_test_notification: None,
            on_toggle_lockscreen_blur: None,
            on_toggle_lockscreen_lyrics: None,
            on_close: None,
        }
    }

    pub fn on_toggle_lockscreen_blur(
        mut self,
        handler: impl Fn(bool) + Send + Sync + 'static,
    ) -> Self {
        self.on_toggle_lockscreen_blur = Some(Arc::new(handler));
        self
    }

    pub fn on_toggle_lockscreen_lyrics(
        mut self,
        handler: impl Fn(bool) + Send + Sync + 'static,
    ) -> Self {
        self.on_toggle_lockscreen_lyrics = Some(Arc::new(handler));
        self
    }

    pub fn on_select_category(
        mut self,
        handler: impl Fn(SettingsCategory) + Send + Sync + 'static,
    ) -> Self {
        self.on_select_category = Some(Arc::new(handler));
        self
    }

    pub fn on_toggle_notch_mode(mut self, handler: impl Fn(bool) + Send + Sync + 'static) -> Self {
        self.on_toggle_notch_mode = Some(Arc::new(handler));
        self
    }

    pub fn on_toggle_window_title(
        mut self,
        handler: impl Fn(bool) + Send + Sync + 'static,
    ) -> Self {
        self.on_toggle_window_title = Some(Arc::new(handler));
        self
    }

    pub fn on_toggle_media_morph(
        mut self,
        handler: impl Fn(bool) + Send + Sync + 'static,
    ) -> Self {
        self.on_toggle_media_morph = Some(Arc::new(handler));
        self
    }

    pub fn on_select_accent(mut self, handler: impl Fn(usize) + Send + Sync + 'static) -> Self {
        self.on_select_accent = Some(Arc::new(handler));
        self
    }

    pub fn on_select_preset(
        mut self,
        handler: impl Fn(beskar_theme::ThemePreset) + Send + Sync + 'static,
    ) -> Self {
        self.on_select_preset = Some(Arc::new(handler));
        self
    }

    pub fn on_test_notification(mut self, handler: impl Fn() + Send + Sync + 'static) -> Self {
        self.on_test_notification = Some(Arc::new(handler));
        self
    }

    pub fn on_close(mut self, handler: impl Fn() + Send + Sync + 'static) -> Self {
        self.on_close = Some(Arc::new(handler));
        self
    }
}

impl RenderOnce for SettingsWidget {
    fn render(self, _window: &mut Window, _cx: &mut App) -> impl IntoElement {
        let config = self.config.clone();
        let on_cat = self.on_select_category;
        let on_close = self.on_close;
        let _on_notch = self.on_toggle_notch_mode;
        let _on_win_title = self.on_toggle_window_title;
        let on_media = self.on_toggle_media_morph;
        let on_accent = self.on_select_accent;
        let on_preset = self.on_select_preset;
        let on_test_notif = self.on_test_notification;
        let on_blur = self.on_toggle_lockscreen_blur;
        let on_lyrics = self.on_toggle_lockscreen_lyrics;

        let accents = [
            ("Beskar Gold", hsla(45.0 / 360.0, 0.95, 0.58, 1.0)),
            ("Neon Cyan", hsla(188.0 / 360.0, 0.95, 0.52, 1.0)),
            ("Cyber Purple", hsla(270.0 / 360.0, 0.90, 0.65, 1.0)),
            ("Emerald Mint", hsla(150.0 / 360.0, 0.85, 0.55, 1.0)),
            ("Crimson Rose", hsla(350.0 / 360.0, 0.85, 0.58, 1.0)),
        ];

        div()
            .w(px(Self::WIDTH))
            .h(px(Self::HEIGHT))
            .rounded(px(22.0))
            // Frosted Obsidian Acrylic Glass
            .bg(beskar_theme::Theme::bg())
            .border_1()
            .border_color(beskar_theme::Theme::card_border())
            .shadow_2xl()
            .flex()
            .overflow_hidden()
            // ── Left Sidebar Navigation (250px) ──
            .child(
                div()
                    .w(px(250.0))
                    .h_full()
                    .bg(beskar_theme::Theme::glass_dark(0.25))
                    .border_r_1()
                    .border_color(beskar_theme::Theme::subtle_border())
                    .p(px(16.0))
                    .flex()
                    .flex_col()
                    .justify_between()
                    // Top: Logo Header + Nav Links
                    .child(
                        div()
                            .flex()
                            .flex_col()
                            .gap(px(14.0))
                            // Brand Header
                            .child(
                                div()
                                    .flex()
                                    .items_center()
                                    .gap(px(10.0))
                                    .child(
                                        div()
                                            .w(px(28.0))
                                            .h(px(28.0))
                                            .rounded(px(8.0))
                                            .bg(beskar_theme::Theme::accent())
                                            .flex()
                                            .items_center()
                                            .justify_center()
                                            .child(
                                                Icon::new(IconName::Settings2)
                                                    .size(px(16.0))
                                                    .text_color(beskar_theme::Theme::bg()),
                                            ),
                                    )
                                    .child(
                                        div()
                                            .flex()
                                            .flex_col()
                                            .child(
                                                div()
                                                    .text_sm()
                                                    .font_weight(FontWeight::BOLD)
                                                    .text_color(beskar_theme::Theme::fg())
                                                    .child("Beskar Shell"),
                                            )
                                            .child(
                                                div()
                                                    .text_xs()
                                                    .text_color(beskar_theme::Theme::text_secondary())
                                                    .child("Preferences"),
                                            ),
                                    ),
                            )
                            // Nav Categories
                            .child(
                                div()
                                    .flex()
                                    .flex_col()
                                    .gap(px(4.0))
                                    .children(SettingsCategory::ALL.into_iter().map(|cat| {
                                        let is_active = config.active_category == cat;
                                        let on_cat_click = on_cat.clone();
                                        div()
                                            .id(ElementId::Name(format!("settings-tab-{:?}", cat).into()))
                                            .px(px(10.0))
                                            .py(px(8.0))
                                            .rounded(px(8.0))
                                            .cursor_pointer()
                                            .bg(if is_active {
                                                beskar_theme::Theme::accent_alpha(0.16)
                                            } else {
                                                gpui_kit::transparent_black()
                                            })
                                            .hover(move |s| {
                                                if !is_active {
                                                    s.bg(beskar_theme::Theme::card_border())
                                                } else {
                                                    s
                                                }
                                            })
                                            .when_some(on_cat_click, move |el, cb| {
                                                el.on_mouse_down(MouseButton::Left, move |_, _, _| (cb)(cat))
                                            })
                                            .flex()
                                            .items_center()
                                            .gap(px(10.0))
                                            .child(
                                                Icon::new(cat.icon())
                                                    .size(px(15.0))
                                                    .text_color(if is_active {
                                                        beskar_theme::Theme::accent()
                                                    } else {
                                                        beskar_theme::Theme::muted()
                                                    }),
                                            )
                                            .child(
                                                div()
                                                    .text_xs()
                                                    .font_weight(if is_active {
                                                        FontWeight::BOLD
                                                    } else {
                                                        FontWeight::MEDIUM
                                                    })
                                                    .text_color(if is_active {
                                                        beskar_theme::Theme::fg()
                                                    } else {
                                                        beskar_theme::Theme::text_secondary()
                                                    })
                                                    .child(cat.title()),
                                            )
                                    })),
                            ),
                    )
                    // Bottom: Version + Close
                    .child(
                        div()
                            .flex()
                            .items_center()
                            .justify_between()
                            .pt(px(10.0))
                            .border_t_1()
                            .border_color(beskar_theme::Theme::subtle_border())
                            .child(
                                div()
                                    .text_xs()
                                    .text_color(beskar_theme::Theme::muted())
                                    .child("v0.1.0 • Wayland"),
                            )
                            .child(
                                Button::new("settings-done")
                                    .ghost()
                                    .compact()
                                    .label("Done")
                                    .when_some(on_close.clone(), |btn, cb| {
                                        btn.on_click(move |_, _, _| (cb)())
                                    }),
                            ),
                    ),
            )
            // ── Right Main Content Area (Responsive) ──
            .child(
                div()
                    .id("settings-page-scroll")
                    .flex_1()
                    .h_full()
                    .p(px(24.0))
                    .pb(px(24.0))
                    .flex()
                    .flex_col()
                    .gap(px(16.0))
                    .overflow_y_scroll()
                    // Page Title + Close button
                    .child(
                        div()
                            .flex()
                            .items_center()
                            .justify_between()
                            .child(
                                div()
                                    .text_lg()
                                    .font_weight(FontWeight::BOLD)
                                    .text_color(beskar_theme::Theme::fg())
                                    .child(config.active_category.title()),
                            )
                            .child(
                                Button::new("settings-close")
                                    .ghost()
                                    .compact()
                                    .icon(Icon::new(IconName::X).size(px(14.0)))
                                    .when_some(on_close, |btn, cb| {
                                        btn.on_click(move |_, _, _| (cb)())
                                    }),
                            ),
                    )
                    // Page Body Switcher
                    .child(match config.active_category {
                        SettingsCategory::Appearance => {
                            render_appearance_page(
                                &accents,
                                config.accent_color_idx,
                                config.dark_mode,
                                on_accent,
                                on_preset,
                            )
                        }
                        SettingsCategory::Keybindings => {
                            render_keybindings_page()
                        }
                        SettingsCategory::Extensions => {
                            render_extensions_page()
                        }
                        SettingsCategory::Apps => {
                            render_apps_page()
                        }
                        SettingsCategory::Media => {
                            render_media_page(config.morph_on_media, on_media)
                        }
                        SettingsCategory::LockScreen => {
                            render_lockscreen_page(&config, on_blur, on_lyrics)
                        }
                        SettingsCategory::System => {
                            render_hardware_page(&config)
                        }
                        SettingsCategory::Record => {
                            render_record_page()
                        }
                        SettingsCategory::Notifications => {
                            render_notifications_page(config.notification_timeout_secs, on_test_notif)
                        }
                        SettingsCategory::General => {
                            render_general_page()
                        }
                    }),
            )
    }
}
