use std::sync::Arc;

use gpui_kit::component::button::{Button, ButtonVariants};
use gpui_kit::component::switch::Switch;
use gpui_kit::component::tag::Tag;
use gpui_kit::prelude::FluentBuilder;
use gpui_kit::*;

use super::view::SettingsConfig;

// ── General Page ──
pub fn render_general_page() -> gpui::Div {
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
                        .bg(beskar_theme::Theme::success_alpha(0.20))
                        .text_xs()
                        .font_weight(FontWeight::BOLD)
                        .text_color(beskar_theme::Theme::success())
                        .child("Connected"),
                ))
                .child(settings_row(
                    "Secondary Compositor",
                    "Umbriel / Noctalia wlroots protocol backend",
                    div()
                        .px(px(8.0))
                        .py(px(4.0))
                        .rounded(px(6.0))
                        .bg(beskar_theme::Theme::card_bg())
                        .text_xs()
                        .font_weight(FontWeight::MEDIUM)
                        .text_color(beskar_theme::Theme::text_secondary())
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
                        .text_color(beskar_theme::Theme::accent())
                        .child("Vulkan / wgpu"),
                ))
                .child(settings_row(
                    "Layer Shell Anchor",
                    "Exclusive top layer surface (40px logical height)",
                    div()
                        .text_xs()
                        .font_weight(FontWeight::MEDIUM)
                        .text_color(beskar_theme::Theme::text_secondary())
                        .child("Top Bezel Flush"),
                )),
        )
}

// ── Appearance Page ──
pub fn render_appearance_page(
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
                                .text_color(beskar_theme::Theme::text_secondary())
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
                                            gpui_kit::transparent_black()
                                        })
                                        .border_color(if is_active {
                                            beskar_theme::Theme::accent()
                                        } else {
                                            beskar_theme::Theme::subtle_border()
                                        })
                                        .hover(|s| s.bg(beskar_theme::Theme::bg_secondary()))
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
                                                    beskar_theme::Theme::text_secondary()
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
                                        .text_color(beskar_theme::Theme::text_secondary())
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
                                .text_color(beskar_theme::Theme::text_secondary())
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
                                                    beskar_theme::Theme::fg()
                                                } else {
                                                    beskar_theme::Theme::glass_dark(0.40)
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
                                                    beskar_theme::Theme::fg()
                                                } else {
                                                    beskar_theme::Theme::text_secondary()
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
                        .bg(beskar_theme::Theme::accent_alpha(0.15))
                        .text_xs()
                        .font_weight(FontWeight::BOLD)
                        .text_color(beskar_theme::Theme::accent())
                        .child("Enabled"),
                ))
                .child(settings_row(
                    "Corner Fillet Radius",
                    "Cubic Bézier continuous curvature fillets",
                    div()
                        .text_xs()
                        .font_weight(FontWeight::BOLD)
                        .text_color(beskar_theme::Theme::fg())
                        .child("18 px"),
                )),
        )
}

// ── Bar & Islands Page ──
pub fn render_bar_page(
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
                            beskar_theme::Theme::info_alpha(0.20)
                        } else {
                            beskar_theme::Theme::accent_alpha(0.20)
                        })
                        .text_xs()
                        .font_weight(FontWeight::BOLD)
                        .text_color(if notch_mode {
                            beskar_theme::Theme::info()
                        } else {
                            beskar_theme::Theme::accent()
                        })
                        .when_some(on_notch, move |el, cb| {
                            el.on_mouse_down(MouseButton::Left, move |_, _, _| (cb)(!notch_mode))
                        })
                        .child(if notch_mode { "Bezel Notch" } else { "Floating Island" }),
                ))
                .child(settings_row(
                    "Dynamic Media Expansion",
                    "Morph Center Island smoothly when audio/media is playing",
                    Switch::new("settings-media-morph-switch")
                        .checked(media_morph)
                        .on_click({
                            let on_media = on_media.clone();
                            move |_, _, _| {
                                if let Some(cb) = on_media.as_ref() {
                                    cb(!media_morph);
                                }
                            }
                        }),
                ))
                .child(settings_row(
                    "Active Window Title",
                    "Display focused application icon and title beside workspace pills",
                    Switch::new("settings-win-title-switch")
                        .checked(active_win_title)
                        .on_click({
                            let on_win_title = on_win_title.clone();
                            move |_, _, _| {
                                if let Some(cb) = on_win_title.as_ref() {
                                    cb(!active_win_title);
                                }
                            }
                        }),
                )),
        )
}

// ── Hardware Page ──
pub fn render_hardware_page(config: &SettingsConfig) -> gpui::Div {
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
                            beskar_theme::Theme::accent()
                        } else {
                            beskar_theme::Theme::muted()
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
                            beskar_theme::Theme::info()
                        } else {
                            beskar_theme::Theme::muted()
                        })
                        .child(if config.is_bt_on { "Active" } else { "Powered Off" }),
                ))
                .child(settings_row(
                    "Master Audio Volume",
                    "WirePlumber / PulseAudio master volume sink",
                    div()
                        .text_xs()
                        .font_weight(FontWeight::BOLD)
                        .text_color(beskar_theme::Theme::accent())
                        .child(format!("{}%", config.volume_percent)),
                ))
                .child(settings_row(
                    "Battery Power",
                    "UPower daemon battery charge status",
                    div()
                        .text_xs()
                        .font_weight(FontWeight::BOLD)
                        .text_color(beskar_theme::Theme::success())
                        .child(format!("{}%", config.battery_percent)),
                )),
        )
}

// ── Notifications Page ──
pub fn render_notifications_page(
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
                        .bg(beskar_theme::Theme::success_alpha(0.20))
                        .text_xs()
                        .font_weight(FontWeight::BOLD)
                        .text_color(beskar_theme::Theme::success())
                        .child("Running"),
                ))
                .child(settings_row(
                    "Auto-Dismiss Timeout",
                    "Time before normal notifications dismiss automatically",
                    div()
                        .text_xs()
                        .font_weight(FontWeight::BOLD)
                        .text_color(beskar_theme::Theme::fg())
                        .child(format!("{} seconds", timeout_secs)),
                ))
                .child(settings_row(
                    "Test Toast Banner",
                    "Dispatch a test notification to verify toast animations and layout",
                    Button::new("test-toast")
                        .primary()
                        .compact()
                        .label("Send Test")
                        .when_some(on_test_notif, |btn, cb| {
                            btn.on_click(move |_, _, _| (cb)())
                        }),
                )),
        )
}

// ── Keybindings Page ──
pub fn render_keybindings_page() -> gpui::Div {
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
pub fn settings_card(title: &'static str) -> gpui::Div {
    div()
        .p(px(14.0))
        .rounded(px(14.0))
        .bg(beskar_theme::Theme::glass_fill(0.04))
        .border_1()
        .border_color(beskar_theme::Theme::card_border())
        .flex()
        .flex_col()
        .gap(px(10.0))
        .child(
            div()
                .text_xs()
                .font_weight(FontWeight::BOLD)
                .text_color(beskar_theme::Theme::text_secondary())
                .child(title),
        )
}

pub fn settings_row(title: &'static str, description: &'static str, control: impl IntoElement) -> gpui::Div {
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
                        .text_color(beskar_theme::Theme::fg())
                        .child(title),
                )
                .child(
                    div()
                        .text_xs()
                        .text_color(beskar_theme::Theme::text_secondary())
                        .child(description),
                ),
        )
        .child(control)
}

pub fn kbd_chip(label: &'static str) -> impl IntoElement {
    Tag::secondary().child(label)
}
