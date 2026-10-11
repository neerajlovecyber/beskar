use gpui_kit::assets::IconName;
use gpui_kit::component::Icon;
use gpui_kit::prelude::FluentBuilder;
use gpui_kit::*;
use std::sync::Arc;

/// Categories in the Settings window sidebar.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SettingsCategory {
    General,
    Appearance,
    BarAndIslands,
    Hardware,
    Notifications,
    Keybindings,
}

impl SettingsCategory {
    pub const ALL: [Self; 6] = [
        Self::General,
        Self::Appearance,
        Self::BarAndIslands,
        Self::Hardware,
        Self::Notifications,
        Self::Keybindings,
    ];

    pub fn title(&self) -> &'static str {
        match self {
            Self::General => "General",
            Self::Appearance => "Appearance",
            Self::BarAndIslands => "Bar & Islands",
            Self::Hardware => "Hardware & Vitals",
            Self::Notifications => "Notifications",
            Self::Keybindings => "Shortcuts",
        }
    }

    pub fn icon(&self) -> IconName {
        match self {
            Self::General => IconName::Settings2,
            Self::Appearance => IconName::Palette,
            Self::BarAndIslands => IconName::LayoutDashboard,
            Self::Hardware => IconName::Cpu,
            Self::Notifications => IconName::Bell,
            Self::Keybindings => IconName::SquareTerminal,
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
}

impl Default for SettingsConfig {
    fn default() -> Self {
        Self {
            active_category: SettingsCategory::General,
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
    on_close: Option<Arc<dyn Fn() + Send + Sync>>,
}

impl SettingsWidget {
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
            on_close: None,
        }
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
        let on_notch = self.on_toggle_notch_mode;
        let on_win_title = self.on_toggle_window_title;
        let on_media = self.on_toggle_media_morph;
        let on_accent = self.on_select_accent;
        let on_preset = self.on_select_preset;
        let on_test_notif = self.on_test_notification;

        let accents = [
            ("Beskar Gold", hsla(45.0 / 360.0, 0.95, 0.58, 1.0)),
            ("Neon Cyan", hsla(188.0 / 360.0, 0.95, 0.52, 1.0)),
            ("Cyber Purple", hsla(270.0 / 360.0, 0.90, 0.65, 1.0)),
            ("Emerald Mint", hsla(150.0 / 360.0, 0.85, 0.55, 1.0)),
            ("Crimson Rose", hsla(350.0 / 360.0, 0.85, 0.58, 1.0)),
        ];

        div()
            .w(px(760.0))
            .h(px(520.0))
            .rounded(px(22.0))
            // Frosted Obsidian Acrylic Glass
            .bg(hsla(240.0 / 360.0, 0.16, 0.08, 0.95))
            .border_1()
            .border_color(hsla(240.0 / 360.0, 0.10, 1.0, 0.14))
            .shadow_2xl()
            .flex()
            .overflow_hidden()
            // ── Left Sidebar Navigation (220px) ──
            .child(
                div()
                    .w(px(220.0))
                    .h_full()
                    .bg(hsla(0.0, 0.0, 0.0, 0.25))
                    .border_r_1()
                    .border_color(hsla(0.0, 0.0, 1.0, 0.08))
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
                                            .bg(hsla(45.0 / 360.0, 0.90, 0.60, 1.0))
                                            .flex()
                                            .items_center()
                                            .justify_center()
                                            .child(
                                                Icon::new(IconName::Settings2)
                                                    .size(px(16.0))
                                                    .text_color(hsla(0.0, 0.0, 0.08, 1.0)),
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
                                                    .text_color(hsla(0.0, 0.0, 0.98, 1.0))
                                                    .child("Beskar Shell"),
                                            )
                                            .child(
                                                div()
                                                    .text_xs()
                                                    .text_color(hsla(0.0, 0.0, 0.55, 1.0))
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
                                                hsla(45.0 / 360.0, 0.90, 0.60, 0.16)
                                            } else {
                                                hsla(0.0, 0.0, 0.0, 0.0)
                                            })
                                            .hover(move |s| {
                                                if !is_active {
                                                    s.bg(hsla(0.0, 0.0, 1.0, 0.06))
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
                                                        hsla(45.0 / 360.0, 0.90, 0.60, 1.0)
                                                    } else {
                                                        hsla(0.0, 0.0, 0.60, 1.0)
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
                                                        hsla(0.0, 0.0, 0.98, 1.0)
                                                    } else {
                                                        hsla(0.0, 0.0, 0.80, 1.0)
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
                            .border_color(hsla(0.0, 0.0, 1.0, 0.06))
                            .child(
                                div()
                                    .text_xs()
                                    .text_color(hsla(0.0, 0.0, 0.45, 1.0))
                                    .child("v0.1.0 • Wayland"),
                            )
                            .child(
                                div()
                                    .px(px(8.0))
                                    .py(px(4.0))
                                    .rounded(px(6.0))
                                    .bg(hsla(0.0, 0.0, 1.0, 0.08))
                                    .hover(|s| s.bg(hsla(0.0, 0.0, 1.0, 0.16)).cursor_pointer())
                                    .when_some(on_close.clone(), |el, cb| {
                                        el.on_mouse_down(MouseButton::Left, move |_, _, _| (cb)())
                                    })
                                    .text_xs()
                                    .font_weight(FontWeight::MEDIUM)
                                    .text_color(hsla(0.0, 0.0, 0.85, 1.0))
                                    .child("Done"),
                            ),
                    ),
            )
            // ── Right Main Content Area (540px) ──
            .child(
                div()
                    .flex_1()
                    .h_full()
                    .p(px(24.0))
                    .flex()
                    .flex_col()
                    .gap(px(16.0))
                    .overflow_hidden()
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
                                    .text_color(hsla(0.0, 0.0, 0.98, 1.0))
                                    .child(config.active_category.title()),
                            )
                            .child(
                                div()
                                    .w(px(24.0))
                                    .h(px(24.0))
                                    .rounded_full()
                                    .flex()
                                    .items_center()
                                    .justify_center()
                                    .bg(hsla(0.0, 0.0, 1.0, 0.08))
                                    .hover(|s| s.bg(hsla(0.0, 0.0, 1.0, 0.18)).cursor_pointer())
                                    .when_some(on_close, |el, cb| {
                                        el.on_mouse_down(MouseButton::Left, move |_, _, _| (cb)())
                                    })
                                    .child(
                                        Icon::new(IconName::X)
                                            .size(px(14.0))
                                            .text_color(hsla(0.0, 0.0, 0.70, 1.0)),
                                    ),
                            ),
                    )
                    // Page Body Switcher
                    .child(match config.active_category {
                        SettingsCategory::General => {
                            render_general_page()
                        }
                        SettingsCategory::Appearance => {
                            render_appearance_page(
                                &accents,
                                config.accent_color_idx,
                                config.dark_mode,
                                on_accent,
                                on_preset,
                            )
                        }
                        SettingsCategory::BarAndIslands => {
                            render_bar_page(
                                config.island_mode_notch,
                                config.show_active_window_title,
                                config.morph_on_media,
                                on_notch,
                                on_win_title,
                                on_media,
                            )
                        }
                        SettingsCategory::Hardware => {
                            render_hardware_page(&config)
                        }
                        SettingsCategory::Notifications => {
                            render_notifications_page(config.notification_timeout_secs, on_test_notif)
                        }
                        SettingsCategory::Keybindings => {
                            render_keybindings_page()
                        }
                    }),
            )
    }
}

// ── General Page ──
fn render_general_page() -> gpui::Div {
    div()
        .flex()
        .flex_col()
        .gap(px(12.0))
        .child(
            settings_card("Compositor Connection")
                .child(settings_row(
                    "Primary Compositor",
                    "Native Niri IPC socket stream with auto-reconnection",
                    div()
                        .px(px(8.0))
                        .py(px(4.0))
                        .rounded(px(6.0))
                        .bg(hsla(142.0 / 360.0, 0.85, 0.55, 0.20))
                        .text_xs()
                        .font_weight(FontWeight::BOLD)
                        .text_color(hsla(142.0 / 360.0, 0.90, 0.65, 1.0))
                        .child("Connected"),
                ))
                .child(settings_row(
                    "Secondary Compositor",
                    "Umbriel / Noctalia wlroots protocol backend",
                    div()
                        .px(px(8.0))
                        .py(px(4.0))
                        .rounded(px(6.0))
                        .bg(hsla(0.0, 0.0, 1.0, 0.08))
                        .text_xs()
                        .font_weight(FontWeight::MEDIUM)
                        .text_color(hsla(0.0, 0.0, 0.70, 1.0))
                        .child("Standby"),
                )),
        )
        .child(
            settings_card("Shell Runtime Engine")
                .child(settings_row(
                    "Renderer",
                    "Zed GPUI vector pipeline accelerated by wgpu",
                    div()
                        .text_xs()
                        .font_weight(FontWeight::MEDIUM)
                        .text_color(hsla(45.0 / 360.0, 0.90, 0.60, 1.0))
                        .child("Vulkan / wgpu"),
                ))
                .child(settings_row(
                    "Layer Shell Anchor",
                    "Exclusive top layer surface (40px logical height)",
                    div()
                        .text_xs()
                        .font_weight(FontWeight::MEDIUM)
                        .text_color(hsla(0.0, 0.0, 0.75, 1.0))
                        .child("Top Bezel Flush"),
                )),
        )
}

// ── Appearance Page ──
fn render_appearance_page(
    accents: &[(&'static str, gpui::Hsla); 5],
    selected_idx: usize,
    _dark_mode: bool,
    on_accent: Option<Arc<dyn Fn(usize) + Send + Sync>>,
    on_preset: Option<Arc<dyn Fn(beskar_theme::ThemePreset) + Send + Sync>>,
) -> gpui::Div {
    let wallpaper_path_str = beskar_theme::ThemeEngine::detect_wallpaper_path()
        .map(|p| p.to_string_lossy().to_string())
        .unwrap_or_else(|| "Not detected (using default dark acrylic)".to_string());

    div()
        .flex()
        .flex_col()
        .gap(px(12.0))
        .child(
            settings_card("Theme Engine & Wallpaper Palette")
                .child(
                    div()
                        .flex()
                        .flex_col()
                        .gap(px(10.0))
                        .child(
                            div()
                                .text_xs()
                                .text_color(hsla(0.0, 0.0, 0.60, 1.0))
                                .child("Select desktop color tokens or extract dominant HSL acrylics directly from wallpaper"),
                        )
                        .child(
                            div()
                                .flex()
                                .items_center()
                                .gap(px(8.0))
                                .children([
                                    (beskar_theme::ThemePreset::Obsidian, "Obsidian Glass"),
                                    (beskar_theme::ThemePreset::CatppuccinMocha, "Catppuccin"),
                                    (beskar_theme::ThemePreset::GruvboxDark, "Gruvbox"),
                                    (beskar_theme::ThemePreset::Wallpaper, "Wallpaper Auto"),
                                ].into_iter().map(|(preset, name)| {
                                    let is_active = beskar_theme::ThemeEngine::current_preset() == preset;
                                    let on_p = on_preset.clone();
                                    div()
                                        .px(px(10.0))
                                        .py(px(5.0))
                                        .rounded(px(6.0))
                                        .cursor_pointer()
                                        .border_1()
                                        .bg(if is_active {
                                            beskar_theme::Theme::bg_secondary()
                                        } else {
                                            hsla(0.0, 0.0, 1.0, 0.04)
                                        })
                                        .border_color(if is_active {
                                            beskar_theme::Theme::accent()
                                        } else {
                                            hsla(0.0, 0.0, 1.0, 0.08)
                                        })
                                        .hover(|s| s.bg(hsla(0.0, 0.0, 1.0, 0.10)))
                                        .when_some(on_p, move |el, cb| {
                                            el.on_mouse_down(MouseButton::Left, move |_, _, _| (cb)(preset))
                                        })
                                        .child(
                                            div()
                                                .text_xs()
                                                .font_weight(if is_active { FontWeight::BOLD } else { FontWeight::MEDIUM })
                                                .text_color(if is_active {
                                                    beskar_theme::Theme::fg()
                                                } else {
                                                    hsla(0.0, 0.0, 0.70, 1.0)
                                                })
                                                .child(name),
                                        )
                                })),
                        )
                        .child(
                            div()
                                .flex()
                                .items_center()
                                .justify_between()
                                .pt(px(4.0))
                                .child(
                                    div()
                                        .text_xs()
                                        .text_color(hsla(0.0, 0.0, 0.50, 1.0))
                                        .child("Wallpaper Source:"),
                                )
                                .child(
                                    div()
                                        .max_w(px(260.0))
                                        .overflow_hidden()
                                        .text_xs()
                                        .font_weight(FontWeight::MEDIUM)
                                        .text_color(beskar_theme::Theme::accent())
                                        .child(wallpaper_path_str),
                                ),
                        ),
                ),
        )
        .child(
            settings_card("Accent Palette")
                .child(
                    div()
                        .flex()
                        .flex_col()
                        .gap(px(10.0))
                        .child(
                            div()
                                .text_xs()
                                .text_color(hsla(0.0, 0.0, 0.60, 1.0))
                                .child("Select the primary accent vibrancy used across dynamic islands and badges"),
                        )
                        .child(
                            div()
                                .flex()
                                .items_center()
                                .gap(px(12.0))
                                .children(accents.iter().enumerate().map(|(idx, (name, color))| {
                                    let is_active = idx == selected_idx;
                                    let on_acc = on_accent.clone();
                                    div()
                                        .flex()
                                        .flex_col()
                                        .items_center()
                                        .gap(px(4.0))
                                        .child(
                                            div()
                                                .size(px(32.0))
                                                .rounded_full()
                                                .cursor_pointer()
                                                .bg(*color)
                                                .border_2()
                                                .border_color(if is_active {
                                                    hsla(0.0, 0.0, 1.0, 0.90)
                                                } else {
                                                    hsla(0.0, 0.0, 0.0, 0.40)
                                                })
                                                .hover(|s| s.opacity(0.85))
                                                .when_some(on_acc, move |el, cb| {
                                                    el.on_mouse_down(MouseButton::Left, move |_, _, _| (cb)(idx))
                                                }),
                                        )
                                        .child(
                                            div()
                                                .text_xs()
                                                .font_weight(if is_active {
                                                    FontWeight::BOLD
                                                } else {
                                                    FontWeight::NORMAL
                                                })
                                                .text_color(if is_active {
                                                    hsla(0.0, 0.0, 0.95, 1.0)
                                                } else {
                                                    hsla(0.0, 0.0, 0.50, 1.0)
                                                })
                                                .child(*name),
                                        )
                                })),
                        ),
                ),
        )
        .child(
            settings_card("Surface Styling")
                .child(settings_row(
                    "Frosted Acrylic Glass",
                    "GPU backdrop acrylic dark slate shader with 1px hairline border",
                    div()
                        .px(px(8.0))
                        .py(px(4.0))
                        .rounded(px(6.0))
                        .bg(hsla(45.0 / 360.0, 0.90, 0.60, 0.15))
                        .text_xs()
                        .font_weight(FontWeight::BOLD)
                        .text_color(hsla(45.0 / 360.0, 0.90, 0.60, 1.0))
                        .child("Enabled"),
                ))
                .child(settings_row(
                    "Corner Fillet Radius",
                    "Cubic Bézier continuous curvature fillets",
                    div()
                        .text_xs()
                        .font_weight(FontWeight::BOLD)
                        .text_color(hsla(0.0, 0.0, 0.85, 1.0))
                        .child("18 px"),
                )),
        )
}

// ── Bar & Islands Page ──
fn render_bar_page(
    notch_mode: bool,
    active_win_title: bool,
    media_morph: bool,
    on_notch: Option<Arc<dyn Fn(bool) + Send + Sync>>,
    on_win_title: Option<Arc<dyn Fn(bool) + Send + Sync>>,
    on_media: Option<Arc<dyn Fn(bool) + Send + Sync>>,
) -> gpui::Div {
    div()
        .flex()
        .flex_col()
        .gap(px(12.0))
        .child(
            settings_card("Island Geometry & Layout")
                .child(settings_row(
                    "Island Topology Mode",
                    "Switch between Floating Capsules or Top Screen Bezel Notch",
                    div()
                        .px(px(10.0))
                        .py(px(4.0))
                        .rounded(px(6.0))
                        .cursor_pointer()
                        .bg(if notch_mode {
                            hsla(210.0 / 360.0, 0.85, 0.55, 0.20)
                        } else {
                            hsla(45.0 / 360.0, 0.90, 0.60, 0.20)
                        })
                        .text_xs()
                        .font_weight(FontWeight::BOLD)
                        .text_color(if notch_mode {
                            hsla(210.0 / 360.0, 0.90, 0.65, 1.0)
                        } else {
                            hsla(45.0 / 360.0, 0.90, 0.60, 1.0)
                        })
                        .when_some(on_notch, move |el, cb| {
                            el.on_mouse_down(MouseButton::Left, move |_, _, _| (cb)(!notch_mode))
                        })
                        .child(if notch_mode { "Bezel Notch" } else { "Floating Island" }),
                ))
                .child(settings_row(
                    "Dynamic Media Expansion",
                    "Morph Center Island smoothly when audio/media is playing",
                    div()
                        .px(px(8.0))
                        .py(px(4.0))
                        .rounded(px(6.0))
                        .cursor_pointer()
                        .bg(if media_morph {
                            hsla(142.0 / 360.0, 0.85, 0.55, 0.20)
                        } else {
                            hsla(0.0, 0.0, 1.0, 0.08)
                        })
                        .text_xs()
                        .font_weight(FontWeight::BOLD)
                        .text_color(if media_morph {
                            hsla(142.0 / 360.0, 0.90, 0.65, 1.0)
                        } else {
                            hsla(0.0, 0.0, 0.60, 1.0)
                        })
                        .when_some(on_media, move |el, cb| {
                            el.on_mouse_down(MouseButton::Left, move |_, _, _| (cb)(!media_morph))
                        })
                        .child(if media_morph { "Active" } else { "Disabled" }),
                ))
                .child(settings_row(
                    "Active Window Title",
                    "Display focused application icon and title beside workspace pills",
                    div()
                        .px(px(8.0))
                        .py(px(4.0))
                        .rounded(px(6.0))
                        .cursor_pointer()
                        .bg(if active_win_title {
                            hsla(142.0 / 360.0, 0.85, 0.55, 0.20)
                        } else {
                            hsla(0.0, 0.0, 1.0, 0.08)
                        })
                        .text_xs()
                        .font_weight(FontWeight::BOLD)
                        .text_color(if active_win_title {
                            hsla(142.0 / 360.0, 0.90, 0.65, 1.0)
                        } else {
                            hsla(0.0, 0.0, 0.60, 1.0)
                        })
                        .when_some(on_win_title, move |el, cb| {
                            el.on_mouse_down(MouseButton::Left, move |_, _, _| (cb)(!active_win_title))
                        })
                        .child(if active_win_title { "Enabled" } else { "Hidden" }),
                )),
        )
}

// ── Hardware Page ──
fn render_hardware_page(config: &SettingsConfig) -> gpui::Div {
    div()
        .flex()
        .flex_col()
        .gap(px(12.0))
        .child(
            settings_card("Live Hardware Status")
                .child(settings_row(
                    "Wi-Fi Network",
                    "NetworkManager radio status & active connection",
                    div()
                        .text_xs()
                        .font_weight(FontWeight::BOLD)
                        .text_color(if config.is_wifi_on {
                            hsla(45.0 / 360.0, 0.90, 0.60, 1.0)
                        } else {
                            hsla(0.0, 0.0, 0.50, 1.0)
                        })
                        .child(if config.is_wifi_on { "Connected" } else { "Disabled" }),
                ))
                .child(settings_row(
                    "Bluetooth Controller",
                    "BlueZ daemon radio status",
                    div()
                        .text_xs()
                        .font_weight(FontWeight::BOLD)
                        .text_color(if config.is_bt_on {
                            hsla(210.0 / 360.0, 0.90, 0.65, 1.0)
                        } else {
                            hsla(0.0, 0.0, 0.50, 1.0)
                        })
                        .child(if config.is_bt_on { "Active" } else { "Powered Off" }),
                ))
                .child(settings_row(
                    "Master Audio Volume",
                    "WirePlumber / PulseAudio master volume sink",
                    div()
                        .text_xs()
                        .font_weight(FontWeight::BOLD)
                        .text_color(hsla(45.0 / 360.0, 0.90, 0.60, 1.0))
                        .child(format!("{}%", config.volume_percent)),
                ))
                .child(settings_row(
                    "Battery Power",
                    "UPower daemon battery charge status",
                    div()
                        .text_xs()
                        .font_weight(FontWeight::BOLD)
                        .text_color(hsla(142.0 / 360.0, 0.85, 0.55, 1.0))
                        .child(format!("{}%", config.battery_percent)),
                )),
        )
}

// ── Notifications Page ──
fn render_notifications_page(
    timeout_secs: u32,
    on_test_notif: Option<Arc<dyn Fn() + Send + Sync>>,
) -> gpui::Div {
    div()
        .flex()
        .flex_col()
        .gap(px(12.0))
        .child(
            settings_card("Desktop Notifications")
                .child(settings_row(
                    "Notification Toast Server",
                    "D-Bus org.freedesktop.Notifications listener server",
                    div()
                        .px(px(8.0))
                        .py(px(4.0))
                        .rounded(px(6.0))
                        .bg(hsla(142.0 / 360.0, 0.85, 0.55, 0.20))
                        .text_xs()
                        .font_weight(FontWeight::BOLD)
                        .text_color(hsla(142.0 / 360.0, 0.90, 0.65, 1.0))
                        .child("Running"),
                ))
                .child(settings_row(
                    "Auto-Dismiss Timeout",
                    "Time before normal notifications dismiss automatically",
                    div()
                        .text_xs()
                        .font_weight(FontWeight::BOLD)
                        .text_color(hsla(0.0, 0.0, 0.85, 1.0))
                        .child(format!("{} seconds", timeout_secs)),
                ))
                .child(settings_row(
                    "Test Toast Banner",
                    "Dispatch a test notification to verify toast animations and layout",
                    div()
                        .px(px(10.0))
                        .py(px(4.0))
                        .rounded(px(6.0))
                        .cursor_pointer()
                        .bg(hsla(45.0 / 360.0, 0.90, 0.60, 0.18))
                        .border_1()
                        .border_color(hsla(45.0 / 360.0, 0.90, 0.60, 0.40))
                        .hover(|s| s.bg(hsla(45.0 / 360.0, 0.90, 0.60, 0.28)))
                        .when_some(on_test_notif, |el, cb| {
                            el.on_mouse_down(MouseButton::Left, move |_, _, _| (cb)())
                        })
                        .text_xs()
                        .font_weight(FontWeight::BOLD)
                        .text_color(hsla(45.0 / 360.0, 0.90, 0.60, 1.0))
                        .child("Send Test"),
                )),
        )
}

// ── Keybindings Page ──
fn render_keybindings_page() -> gpui::Div {
    div()
        .flex()
        .flex_col()
        .gap(px(12.0))
        .child(
            settings_card("Shell Global Shortcuts")
                .child(settings_row(
                    "App Launcher",
                    "Fuzzy search desktop applications & quick launch",
                    kbd_chip("Super + D"),
                ))
                .child(settings_row(
                    "Control Center",
                    "Quick toggles for Wi-Fi, Bluetooth, volume & battery",
                    kbd_chip("Super + C"),
                ))
                .child(settings_row(
                    "Power Menu",
                    "Lock, Suspend, Restart, or Shutdown the system",
                    kbd_chip("Super + X"),
                ))
                .child(settings_row(
                    "Settings",
                    "Open this preferences customizer window",
                    kbd_chip("Super + S"),
                ))
                .child(settings_row(
                    "Lock Screen",
                    "Lock the active display with clock and password prompt",
                    kbd_chip("Super + L"),
                )),
        )
}

// ── Helper Components ──
fn settings_card(title: &'static str) -> gpui::Div {
    div()
        .p(px(14.0))
        .rounded(px(14.0))
        .bg(hsla(0.0, 0.0, 1.0, 0.04))
        .border_1()
        .border_color(hsla(0.0, 0.0, 1.0, 0.08))
        .flex()
        .flex_col()
        .gap(px(10.0))
        .child(
            div()
                .text_xs()
                .font_weight(FontWeight::BOLD)
                .text_color(hsla(0.0, 0.0, 0.55, 1.0))
                .child(title),
        )
}

fn settings_row(title: &'static str, description: &'static str, control: impl IntoElement) -> gpui::Div {
    div()
        .flex()
        .items_center()
        .justify_between()
        .py(px(4.0))
        .child(
            div()
                .flex()
                .flex_col()
                .gap(px(2.0))
                .child(
                    div()
                        .text_xs()
                        .font_weight(FontWeight::BOLD)
                        .text_color(hsla(0.0, 0.0, 0.95, 1.0))
                        .child(title),
                )
                .child(
                    div()
                        .text_xs()
                        .text_color(hsla(0.0, 0.0, 0.55, 1.0))
                        .child(description),
                ),
        )
        .child(control)
}

fn kbd_chip(label: &'static str) -> gpui::Div {
    div()
        .px(px(8.0))
        .py(px(3.0))
        .rounded(px(6.0))
        .bg(hsla(0.0, 0.0, 1.0, 0.08))
        .border_1()
        .border_color(hsla(0.0, 0.0, 1.0, 0.14))
        .text_xs()
        .font_weight(FontWeight::BOLD)
        .text_color(hsla(0.0, 0.0, 0.90, 1.0))
        .child(label)
}
