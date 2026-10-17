use std::sync::Arc;

use gpui_kit::component::button::{Button, ButtonVariants};
use gpui_kit::component::switch::Switch;
use gpui_kit::component::tag::Tag;
use gpui_kit::prelude::FluentBuilder;
use gpui_kit::*;

use super::helpers::*;
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
            settings_card("Window Management (Niri / Hyprland)")
                .child(settings_row(
                    "Close Active Window",
                    "Terminate the currently focused application window",
                    kbd_chip("Super + Q"),
                ))
                .child(settings_row(
                    "Toggle Floating / Tile",
                    "Switch active window between tiling column and floating layer",
                    kbd_chip("Super + Space"),
                ))
                .child(settings_row(
                    "Toggle Fullscreen Mode",
                    "Expand active window across entire workspace area",
                    kbd_chip("Super + F"),
                ))
                .child(settings_row(
                    "Spawn Terminal Emulator",
                    "Open default GPU-accelerated terminal (Alacritty / Foot / Kitty)",
                    kbd_chip("Super + Return"),
                )),
        )
        .child(
            settings_card("Shell Surfaces & Omni-Launcher")
                .child(settings_row(
                    "Unified Omni-Launcher & Calculator",
                    "Fuzzy desktop search, math evaluation & power actions",
                    kbd_chip("Super + D"),
                ))
                .child(settings_row(
                    "Control Center",
                    "Quick toggles matrix, PipeWire sink & brightness sliders",
                    kbd_chip("Super + C"),
                ))
                .child(settings_row(
                    "GitHub Dev Dashboard",
                    "52-week contribution heatmap, commit streaks & vitals drawer",
                    kbd_chip("Super + G"),
                ))
                .child(settings_row(
                    "Clipboard History",
                    "Search and paste recent text and image clips",
                    kbd_chip("Super + V"),
                ))
                .child(settings_row(
                    "Power Menu",
                    "Lock, Suspend, Restart, or Shutdown the system",
                    kbd_chip("Super + X"),
                ))
                .child(settings_row(
                    "Desktop Preferences",
                    "Open this standalone preferences customizer window",
                    kbd_chip("Super + S"),
                ))
                .child(settings_row(
                    "Lock Screen",
                    "Lock the active display with clock and password prompt",
                    kbd_chip("Super + L"),
                )),
        )
        .child(
            settings_card("Media & Hardware Audio")
                .child(settings_row(
                    "Play / Pause Active Media",
                    "Toggle playback for currently active MPRIS media source",
                    kbd_chip("XF86AudioPlay"),
                ))
                .child(settings_row(
                    "Next Track",
                    "Skip forward to next audio track in player queue",
                    kbd_chip("XF86AudioNext"),
                ))
                .child(settings_row(
                    "Previous Track",
                    "Return to previous audio track in player queue",
                    kbd_chip("XF86AudioPrev"),
                ))
                .child(settings_row(
                    "Raise Master Volume",
                    "Increase master PipeWire audio output level by 5%",
                    kbd_chip("XF86AudioRaiseVolume"),
                ))
                .child(settings_row(
                    "Lower Master Volume",
                    "Decrease master PipeWire audio output level by 5%",
                    kbd_chip("XF86AudioLowerVolume"),
                ))
                .child(settings_row(
                    "Mute Master Output",
                    "Toggle audio mute state on active sink",
                    kbd_chip("XF86AudioMute"),
                )),
        )
        .child(
            settings_card("Display & Screen Capture")
                .child(settings_row(
                    "Full Display Screenshot",
                    "Capture entire desktop surface directly to clipboard",
                    kbd_chip("Print"),
                ))
                .child(settings_row(
                    "Interactive Area Snipping",
                    "Select rectangular display region for screenshot or OCR",
                    kbd_chip("Super + Shift + S"),
                )),
        )
}

// ── Package & Extension Manager Page ──
pub fn render_extensions_page() -> gpui::Div {
    div()
        .flex()
        .flex_col()
        .gap(px(12.0))
        .child(
            settings_card("Package & Extension Ecosystem")
                .child(settings_row(
                    "Extension Runtime",
                    "Sandboxed dynamic widgets loaded from ~/.local/share/beskar/extensions",
                    div()
                        .px(px(8.0))
                        .py(px(4.0))
                        .rounded(px(6.0))
                        .bg(beskar_theme::Theme::success_alpha(0.20))
                        .text_xs()
                        .font_weight(FontWeight::BOLD)
                        .text_color(beskar_theme::Theme::success())
                        .child("4 Active · 3 Available"),
                )),
        )
        .child(
            settings_card("Core Installed Extensions")
                .child(settings_row(
                    "beskar-cava-visualizer (v0.2.1)",
                    "4-bar dynamic audio frequency visualizer integrated into the center notch",
                    div()
                        .flex()
                        .items_center()
                        .gap(px(8.0))
                        .child(Tag::primary().child("Active"))
                        .child(Switch::new("ext-cava-switch").checked(true)),
                ))
                .child(settings_row(
                    "beskar-github-telemetry (v1.0.0)",
                    "52-week contribution heatmap, commit streaks, and dev metrics panel",
                    div()
                        .flex()
                        .items_center()
                        .gap(px(8.0))
                        .child(Tag::primary().child("Active"))
                        .child(Switch::new("ext-gh-switch").checked(true)),
                ))
                .child(settings_row(
                    "beskar-weather-notch (v0.4.0)",
                    "Dynamic weather condition badge with temperature & 24h precipitation forecast",
                    div()
                        .flex()
                        .items_center()
                        .gap(px(8.0))
                        .child(Tag::primary().child("Active"))
                        .child(Switch::new("ext-weather-switch").checked(true)),
                ))
                .child(settings_row(
                    "beskar-clipboard-preview (v0.9.3)",
                    "Rich clipboard history manager with image and text previews",
                    div()
                        .flex()
                        .items_center()
                        .gap(px(8.0))
                        .child(Tag::primary().child("Active"))
                        .child(Switch::new("ext-clip-switch").checked(true)),
                )),
        )
        .child(
            settings_card("Community Extension Store")
                .child(settings_row(
                    "beskar-pomodoro-timer (v0.1.0)",
                    "Productivity focus timer pill with ambient sound notifications",
                    div()
                        .flex()
                        .items_center()
                        .gap(px(8.0))
                        .child(Tag::secondary().child("Community"))
                        .child(
                            Button::new("install-pomodoro")
                                .primary()
                                .compact()
                                .label("Install"),
                        ),
                ))
                .child(settings_row(
                    "beskar-spotify-lyrics (v0.3.2)",
                    "Real-time synced lyrics streaming inside the center music player",
                    div()
                        .flex()
                        .items_center()
                        .gap(px(8.0))
                        .child(Tag::secondary().child("Community"))
                        .child(
                            Button::new("install-lyrics")
                                .primary()
                                .compact()
                                .label("Install"),
                        ),
                ))
                .child(settings_row(
                    "beskar-docker-monitor (v0.1.4)",
                    "Container telemetry and quick restart actions in the dev drawer",
                    div()
                        .flex()
                        .items_center()
                        .gap(px(8.0))
                        .child(Tag::secondary().child("Community"))
                        .child(
                            Button::new("install-docker")
                                .primary()
                                .compact()
                                .label("Install"),
                        ),
                )),
        )
}

// ── Apps Page ──
pub fn render_apps_page() -> gpui::Div {
    let apps = beskar_services::list_apps();
    div()
        .flex()
        .flex_col()
        .gap(px(12.0))
        .child(
            settings_card("Application Launcher Configuration")
                .child(settings_row(
                    "Installed Applications",
                    "Discovered from XDG standard application desktop entries",
                    div()
                        .text_xs()
                        .font_weight(FontWeight::BOLD)
                        .text_color(beskar_theme::Theme::fg())
                        .child(format!("{} apps detected", apps.len())),
                ))
                .child(settings_row(
                    "Default Terminal",
                    "Terminal emulator spawned by launcher and updates card",
                    div()
                        .text_xs()
                        .font_weight(FontWeight::MEDIUM)
                        .text_color(beskar_theme::Theme::accent())
                        .child("alacritty / kitty / foot"),
                )),
        )
        .child(
            settings_card("Discovered Desktop Applications")
                .children(apps.into_iter().take(8).map(|app| {
                    settings_row(
                        Box::leak(app.name.clone().into_boxed_str()),
                        Box::leak(format!("Exec: {}", app.exec).into_boxed_str()),
                        div()
                            .px(px(8.0))
                            .py(px(2.0))
                            .rounded(px(4.0))
                            .bg(beskar_theme::Theme::glass_fill(0.08))
                            .text_xs()
                            .text_color(beskar_theme::Theme::muted())
                            .child("Installed"),
                    )
                })),
        )
}

// ── Media Page ──
pub fn render_media_page(morph_on_media: bool, on_media: Option<Arc<dyn Fn(bool) + Send + Sync>>) -> gpui::Div {
    let players = beskar_services::MprisService::fetch_all_players();
    let current_track = players.first();
    let title: &'static str = match current_track {
        Some(t) => Box::leak(t.title.clone().into_boxed_str()),
        None => "No media playing",
    };
    let artist: String = match current_track {
        Some(t) => t.artist.clone(),
        None => "Idle".to_string(),
    };

    div()
        .flex()
        .flex_col()
        .gap(px(12.0))
        .child(
            settings_card("MPRIS Media Playback & Dynamic Island")
                .child(settings_row(
                    "Center Island Morph on Media",
                    "Expand dynamic island to display animated sine wave and track controls",
                    Switch::new("settings-media-morph")
                        .checked(morph_on_media)
                        .when_some(on_media, |sw, cb| {
                            sw.on_click(move |_, _, _| (cb)(!morph_on_media))
                        }),
                ))
                .child(settings_row(
                    "Active Media Players",
                    "Connected D-Bus org.mpris.MediaPlayer2 instances",
                    div()
                        .text_xs()
                        .font_weight(FontWeight::BOLD)
                        .text_color(beskar_theme::Theme::fg())
                        .child(format!("{} active", players.len())),
                )),
        )
        .child(
            settings_card("Currently Playing Track")
                .child(settings_row(
                    "Title",
                    title,
                    div()
                        .text_xs()
                        .font_weight(FontWeight::MEDIUM)
                        .text_color(beskar_theme::Theme::accent())
                        .child(artist),
                )),
        )
}

// ── Lock Screen Page ──
pub fn render_lockscreen_page(
    config: &SettingsConfig,
    on_blur: Option<Arc<dyn Fn(bool) + Send + Sync>>,
    on_lyrics: Option<Arc<dyn Fn(bool) + Send + Sync>>,
) -> gpui::Div {
    let blur_active = config.lockscreen_blur;
    let lyrics_active = config.lockscreen_show_lyrics;

    div()
        .flex()
        .flex_col()
        .gap(px(12.0))
        .child(
            settings_card("Lock Screen Visuals & Authentication")
                .child(settings_row(
                    "Atmospheric Wallpaper Blur",
                    "Apply Gaussian blur to the active desktop wallpaper behind the lock screen",
                    Switch::new("settings-lock-blur")
                        .checked(blur_active)
                        .when_some(on_blur, |sw, cb| {
                            sw.on_click(move |_, _, _| (cb)(!blur_active))
                        }),
                ))
                .child(settings_row(
                    "Synchronized Music Lyrics",
                    "Display synced song lyrics on the primary display when playing media",
                    Switch::new("settings-lock-lyrics")
                        .checked(lyrics_active)
                        .when_some(on_lyrics, |sw, cb| {
                            sw.on_click(move |_, _, _| (cb)(!lyrics_active))
                        }),
                ))
                .child(settings_row(
                    "Clock Time Format",
                    "Time readout display format (12-hour AM/PM or 24-hour)",
                    div()
                        .text_xs()
                        .font_weight(FontWeight::BOLD)
                        .text_color(beskar_theme::Theme::fg())
                        .child(config.clock_format.clone()),
                )),
        )
}

// ── Record Page ──
pub fn render_record_page() -> gpui::Div {
    div()
        .flex()
        .flex_col()
        .gap(px(12.0))
        .child(
            settings_card("Screen Recording (wf-recorder)")
                .child(settings_row(
                    "Video Format & Framerate",
                    "High-definition 60 FPS recording with hardware acceleration",
                    div()
                        .px(px(8.0))
                        .py(px(4.0))
                        .rounded(px(6.0))
                        .bg(beskar_theme::Theme::card_bg())
                        .text_xs()
                        .font_weight(FontWeight::BOLD)
                        .text_color(beskar_theme::Theme::accent())
                        .child("MP4 / 60 FPS"),
                ))
                .child(settings_row(
                    "Audio Capture Channel",
                    "PulseAudio / PipeWire default desktop audio monitor",
                    div()
                        .text_xs()
                        .font_weight(FontWeight::MEDIUM)
                        .text_color(beskar_theme::Theme::fg())
                        .child("System Sound Output"),
                ))
                .child(settings_row(
                    "OCR Extraction Engine",
                    "Optical Character Recognition via grim, slurp and tesseract",
                    div()
                        .text_xs()
                        .font_weight(FontWeight::MEDIUM)
                        .text_color(beskar_theme::Theme::success())
                        .child("Active"),
                )),
        )
}
