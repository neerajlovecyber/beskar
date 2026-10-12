use beskar_core::models::{WindowInfo, WorkspaceInfo};
use gpui_kit::assets::IconName;
use gpui_kit::component::Icon;
use gpui_kit::prelude::FluentBuilder;
use gpui_kit::*;
use std::sync::Arc;

fn resolve_window_icon(app_id: Option<&str>, title: Option<&str>) -> IconName {
    let text = format!(
        "{} {}",
        app_id.unwrap_or_default().to_lowercase(),
        title.unwrap_or_default().to_lowercase()
    );

    if text.contains("firefox") || text.contains("chrome") || text.contains("browser") {
        IconName::Globe
    } else if text.contains("term") || text.contains("kitty") || text.contains("alacritty") || text.contains("wezterm") {
        IconName::Terminal
    } else if text.contains("code") || text.contains("zed") || text.contains("nvim") || text.contains("vim") {
        IconName::Code
    } else if text.contains("files") || text.contains("folder") || text.contains("nautilus") || text.contains("thunar") || text.contains("dolphin") {
        IconName::Folder
    } else if text.contains("music") || text.contains("spotify") {
        IconName::Music
    } else if text.contains("discord") || text.contains("slack") || text.contains("telegram") {
        IconName::MessageSquare
    } else if text.contains("settings") {
        IconName::Settings
    } else {
        IconName::AppWindow
    }
}

/// Grouped snapshot of live system and shell telemetry for BeskarBar.
#[derive(Clone, Default)]
pub struct BarState {
    pub is_convex: bool,
    pub workspaces: Vec<WorkspaceInfo>,
    pub active_ws: Option<u64>,
    pub active_window: Option<WindowInfo>,
    pub time_str: String,
    pub date_str: Option<String>,
    pub media: Option<(String, String, bool)>,
    pub notification: Option<(String, String)>,
    pub volume_percent: u8,
    pub is_muted: bool,
    pub battery_percent: u8,
    pub is_charging: bool,
    pub animated_center_width: Option<f32>,
    pub cava_bands: Option<[u8; 4]>,
    pub tray_items: Vec<beskar_core::models::TrayItem>,
}

/// Callbacks for interactive bar actions.
#[derive(Clone, Default)]
pub struct BarActions {
    pub on_select_ws: Option<Arc<dyn Fn(u64) + Send + Sync>>,
    pub on_scroll_ws: Option<Arc<dyn Fn(i32) + Send + Sync>>,
    pub on_play_pause: Option<Arc<dyn Fn() + Send + Sync>>,
    pub on_volume_click: Option<Arc<dyn Fn() + Send + Sync>>,
    pub on_volume_scroll: Option<Arc<dyn Fn(i32) + Send + Sync>>,
    pub on_control_center_click: Option<Arc<dyn Fn() + Send + Sync>>,
    pub on_power_click: Option<Arc<dyn Fn() + Send + Sync>>,
    pub on_launcher_click: Option<Arc<dyn Fn() + Send + Sync>>,
    pub on_clock_click: Option<Arc<dyn Fn() + Send + Sync>>,
    pub on_dashboard_click: Option<Arc<dyn Fn() + Send + Sync>>,
    pub on_music_click: Option<Arc<dyn Fn() + Send + Sync>>,
    pub on_capture_click: Option<Arc<dyn Fn() + Send + Sync>>,
    pub on_wallpaper_click: Option<Arc<dyn Fn() + Send + Sync>>,
    pub on_tray_click: Option<Arc<dyn Fn(String) + Send + Sync>>,
    pub on_tray_menu: Option<Arc<dyn Fn(String) + Send + Sync>>,
    pub on_window_click: Option<Arc<dyn Fn() + Send + Sync>>,
    pub on_window_close: Option<Arc<dyn Fn() + Send + Sync>>,
}

/// Beskar Bar surface separating the top bar into 3 distinct layout regions:
/// - [Left Island]: Workspaces & active tasks
/// - [Dynamic Center Island]: Dynamic morphing pill (clock, MPRIS, notifications)
/// - [Right Island]: Vitals, battery, volume, quick sliders, system tray
#[derive(IntoElement)]
pub struct BeskarBar {
    left: Vec<AnyElement>,
    center: Vec<AnyElement>,
    right: Vec<AnyElement>,
    padding_x: Pixels,
    is_island_cluster: bool,
    is_convex: bool,
}

impl Default for BeskarBar {
    fn default() -> Self {
        Self::new()
    }
}

impl BeskarBar {
    pub fn new() -> Self {
        Self {
            left: Vec::new(),
            center: Vec::new(),
            right: Vec::new(),
            padding_x: px(12.0),
            is_island_cluster: false,
            is_convex: false,
        }
    }

    pub fn convex(mut self, convex: bool) -> Self {
        self.is_convex = convex;
        self
    }

    pub fn island_cluster(mut self, cluster: bool) -> Self {
        self.is_island_cluster = cluster;
        self
    }

    pub fn left(mut self, elements: impl IntoIterator<Item = AnyElement>) -> Self {
        self.left.extend(elements);
        self
    }

    pub fn center(mut self, elements: impl IntoIterator<Item = AnyElement>) -> Self {
        self.center.extend(elements);
        self
    }

    pub fn right(mut self, elements: impl IntoIterator<Item = AnyElement>) -> Self {
        self.right.extend(elements);
        self
    }

    /// Construct BeskarBar from a grouped state snapshot and actions.
    pub fn from_state(state: BarState, actions: BarActions) -> Self {
        use crate::pill::IslandPill;
        use crate::widgets::{DynamicCenterWidget, VitalsWidget, WorkspacesWidget};

        let is_convex = state.is_convex;
        let mut ws_widget = WorkspacesWidget::new(state.workspaces, state.active_ws);
        if let Some(handler) = actions.on_select_ws {
            ws_widget = ws_widget.on_select(move |id| (handler)(id));
        }
        if let Some(handler) = actions.on_scroll_ws {
            ws_widget = ws_widget.on_scroll(move |dir| (handler)(dir));
        }

        let on_star = actions.on_launcher_click.clone();
        let on_dash = actions.on_dashboard_click.clone();
        let star_badge = div()
            .flex()
            .items_center()
            .justify_center()
            .w(px(24.0))
            .h(px(24.0))
            .mr(px(8.0))
            .rounded_md()
            .text_xs()
            .font_weight(FontWeight::BOLD)
            .text_color(hsla(45.0 / 360.0, 0.90, 0.60, 1.0))
            .hover(|s| {
                s.cursor_pointer()
                    .bg(beskar_theme::Theme::bg_secondary())
                    .text_color(hsla(45.0 / 360.0, 1.0, 0.75, 1.0))
            })
            .on_mouse_down(MouseButton::Left, move |_, _, _| {
                if let Some(handler) = on_star.as_ref() {
                    handler();
                }
            })
            .on_mouse_down(MouseButton::Right, move |_, _, _| {
                if let Some(handler) = on_dash.as_ref() {
                    handler();
                }
            })
            .child("✦");

        let left_pill = IslandPill::new()
            .convex(is_convex)
            .child(star_badge)
            .child(ws_widget)
            .when_some(state.active_window, |pill, win| {
                let title_text = win
                    .title
                    .as_deref()
                    .filter(|t| !t.trim().is_empty())
                    .or(win.app_id.as_deref())
                    .unwrap_or("");

                if title_text.is_empty() {
                    return pill;
                }

                let icon = resolve_window_icon(win.app_id.as_deref(), win.title.as_deref());
                let short_title = if title_text.chars().count() > 24 {
                    let mut s: String = title_text.chars().take(24).collect();
                    s.push('…');
                    s
                } else {
                    title_text.to_string()
                };

                let on_win_clk = actions.on_window_click.clone();
                let on_win_cls = actions.on_window_close.clone();
                pill.child(
                    div()
                        .flex()
                        .items_center()
                        .gap(px(6.0))
                        .ml(px(8.0))
                        .pl(px(8.0))
                        .border_l_1()
                        .border_color(hsla(0.0, 0.0, 1.0, 0.12))
                        .cursor_pointer()
                        .hover(|s| s.bg(beskar_theme::Theme::bg_secondary()).rounded_md())
                        .when_some(on_win_clk, |el, cb| {
                            el.on_mouse_down(MouseButton::Left, move |_, _, _| (cb)())
                        })
                        .when_some(on_win_cls, |el, cb| {
                            el.on_mouse_down(MouseButton::Middle, move |_, _, _| (cb)())
                        })
                        .child(
                            Icon::new(icon)
                                .size(px(13.0))
                                .text_color(hsla(0.0, 0.0, 0.75, 1.0)),
                        )
                        .child(
                            div()
                                .text_xs()
                                .font_weight(FontWeight::MEDIUM)
                                .text_color(hsla(0.0, 0.0, 0.85, 1.0))
                                .child(short_title),
                        ),
                )
            });

        let mut center_widget = DynamicCenterWidget::new(state.time_str)
            .date(state.date_str)
            .notification(state.notification);
        if let Some(bands) = state.cava_bands {
            center_widget = center_widget.cava_bands(bands);
        }
        if let Some(w) = state.animated_center_width {
            center_widget = center_widget.width(px(w));
        }
        if let Some((title, artist, is_playing)) = state.media {
            center_widget = center_widget.media(Some(title), Some(artist), is_playing);
        }
        if let Some(handler) = actions.on_play_pause {
            center_widget = center_widget.on_play_pause(move || (handler)());
        }
        if let Some(handler) = actions.on_clock_click {
            center_widget = center_widget.on_clock_click(move || (handler)());
        }
        if let Some(handler) = actions.on_music_click {
            center_widget = center_widget.on_media_click(move || (handler)());
        } else if let Some(ref handler) = actions.on_control_center_click {
            let h = handler.clone();
            center_widget = center_widget.on_media_click(move || (h)());
        }
        let center_pill = IslandPill::new().convex(is_convex).child(center_widget);

        let mut vitals_widget = VitalsWidget::new(state.volume_percent, state.battery_percent)
            .muted(state.is_muted)
            .charging(state.is_charging)
            .tray(state.tray_items);
        if let Some(handler) = actions.on_volume_click {
            vitals_widget = vitals_widget.on_volume_click(move || (handler)());
        }
        if let Some(handler) = actions.on_volume_scroll {
            vitals_widget = vitals_widget.on_volume_scroll(move |delta| (handler)(delta));
        }
        if let Some(handler) = actions.on_control_center_click {
            vitals_widget = vitals_widget.on_control_center_click(move || (handler)());
        }
        if let Some(handler) = actions.on_capture_click {
            vitals_widget = vitals_widget.on_capture_click(move || (handler)());
        }
        if let Some(handler) = actions.on_wallpaper_click {
            vitals_widget = vitals_widget.on_wallpaper_click(move || (handler)());
        }
        if let Some(handler) = actions.on_power_click {
            vitals_widget = vitals_widget.on_power_click(move || (handler)());
        }
        if let Some(handler) = actions.on_tray_click {
            vitals_widget = vitals_widget.on_tray_click(move |id| (handler)(id));
        }
        if let Some(handler) = actions.on_tray_menu {
            vitals_widget = vitals_widget.on_tray_menu(move |id| (handler)(id));
        }
        let right_pill = IslandPill::new().convex(is_convex).child(vitals_widget);

        Self::new()
            .convex(is_convex)
            .left([left_pill.into_any_element()])
            .center([center_pill.into_any_element()])
            .right([right_pill.into_any_element()])
    }

    /// Builds the signature 3-Island layout matching minflair and the reference screenshot:
    /// - Left: Brand star badge + WorkspacesWidget inside an IslandPill
    /// - Center: DynamicCenterWidget (Clock + MPRIS) inside an IslandPill
    /// - Right: VitalsWidget (Recording + Controls + Audio/WiFi/Battery/Power) inside an IslandPill
    #[allow(clippy::too_many_arguments)]
    pub fn live_islands(
        is_convex: bool,
        workspaces: Vec<WorkspaceInfo>,
        active_ws: Option<u64>,
        active_window: Option<WindowInfo>,
        time_str: impl Into<String>,
        date_str: Option<String>,
        media: Option<(String, String, bool)>,
        notification: Option<(String, String)>,
        volume_percent: u8,
        is_muted: bool,
        battery_percent: u8,
        is_charging: bool,
        animated_center_width: Option<f32>,
        cava_bands: Option<[u8; 4]>,
        tray_items: Vec<beskar_core::models::TrayItem>,
        on_select_ws: Option<Arc<dyn Fn(u64) + Send + Sync>>,
        on_scroll_ws: Option<Arc<dyn Fn(i32) + Send + Sync>>,
        on_play_pause: Option<Arc<dyn Fn() + Send + Sync>>,
        on_volume_click: Option<Arc<dyn Fn() + Send + Sync>>,
        on_volume_scroll: Option<Arc<dyn Fn(i32) + Send + Sync>>,
        on_control_center_click: Option<Arc<dyn Fn() + Send + Sync>>,
        on_power_click: Option<Arc<dyn Fn() + Send + Sync>>,
        on_launcher_click: Option<Arc<dyn Fn() + Send + Sync>>,
        on_clock_click: Option<Arc<dyn Fn() + Send + Sync>>,
        on_dashboard_click: Option<Arc<dyn Fn() + Send + Sync>>,
        on_music_click: Option<Arc<dyn Fn() + Send + Sync>>,
        on_capture_click: Option<Arc<dyn Fn() + Send + Sync>>,
        on_wallpaper_click: Option<Arc<dyn Fn() + Send + Sync>>,
        on_tray_click: Option<Arc<dyn Fn(String) + Send + Sync>>,
        on_tray_menu: Option<Arc<dyn Fn(String) + Send + Sync>>,
        on_window_click: Option<Arc<dyn Fn() + Send + Sync>>,
        on_window_close: Option<Arc<dyn Fn() + Send + Sync>>,
    ) -> Self {
        let state = BarState {
            is_convex,
            workspaces,
            active_ws,
            active_window,
            time_str: time_str.into(),
            date_str,
            media,
            notification,
            volume_percent,
            is_muted,
            battery_percent,
            is_charging,
            animated_center_width,
            cava_bands,
            tray_items,
        };
        let actions = BarActions {
            on_select_ws,
            on_scroll_ws,
            on_play_pause,
            on_volume_click,
            on_volume_scroll,
            on_control_center_click,
            on_power_click,
            on_launcher_click,
            on_clock_click,
            on_dashboard_click,
            on_music_click,
            on_capture_click,
            on_wallpaper_click,
            on_tray_click,
            on_tray_menu,
            on_window_click,
            on_window_close,
        };
        Self::from_state(state, actions)
    }

    pub fn default_islands(
        active_ws: u64,
        total_ws: usize,
        time_str: impl Into<String>,
        media: Option<(String, String, bool)>,
    ) -> Self {
        let fake_workspaces = (1..=total_ws)
            .map(|i| WorkspaceInfo {
                id: i as u64,
                idx: i as u8,
                name: None,
                output: String::new(),
                is_active: i as u64 == active_ws,
                is_focused: i as u64 == active_ws,
            })
            .collect();

        Self::live_islands(
            false,
            fake_workspaces,
            Some(active_ws),
            None,
            time_str,
            None,
            media,
            None,
            65,
            false,
            88,
            false,
            None,
            None,
            Vec::new(),
            None,
            None,
            None,
            None,
            None,
            None,
            None,
            None,
            None,
            None,
            None,
            None,
            None,
            None,
            None,
            None,
            None,
        )
    }
}

impl RenderOnce for BeskarBar {
    fn render(self, _window: &mut Window, _cx: &mut App) -> impl IntoElement {
        if self.is_island_cluster {
            // minflair IslandBar mode: Left Pill, Center Dynamic Island, and Right Pill
            // sit grouped together as a floating tri-capsule island cluster at the top center!
            div()
                .relative()
                .size_full()
                .flex()
                .items_start()
                .justify_center()
                .gap(px(10.0))
                .children(self.left)
                .children(self.center)
                .children(self.right)
        } else {
            // minflair ConvexBar mode: Left Notch, Center Notch, and Right Notch
            // connected with the continuous top bezel bridge
            let mut container = div()
                .relative()
                .size_full()
                .flex()
                .items_start()
                .px(self.padding_x);

            if self.is_convex {
                use crate::convex::{ConvexBarShape, ConvexGeometry};
                let geom = ConvexGeometry {
                    width: 1920.0,
                    height: 40.0,
                    left_w: 330.0,
                    center_x: 820.0,
                    center_w: 280.0,
                    right_w: 340.0,
                    top_bezel: 2.0,
                    flare_width: 16.0,
                    flare_height: 14.0,
                    bottom_radius: 14.0,
                    center_bottom_radius: 14.0,
                    center_height: 40.0,
                    base_height: 40.0,
                };
                container = container.child(
                    div()
                        .absolute()
                        .inset_0()
                        .child(ConvexBarShape::new(
                            geom,
                            beskar_theme::Theme::bg(),
                            beskar_theme::Theme::border(),
                        )),
                );
            }

            container
                // Left region: Left Island Notch / Pill
                .child(
                    div()
                        .flex()
                        .flex_1()
                        .items_start()
                        .justify_start()
                        .children(self.left),
                )
                // Center region: Dynamic Center Island Notch / Pill
                .child(
                    div()
                        .flex()
                        .items_start()
                        .justify_center()
                        .children(self.center),
                )
                // Right region: Right Island Notch / Pill
                .child(
                    div()
                        .flex()
                        .flex_1()
                        .items_start()
                        .justify_end()
                        .children(self.right),
                )
        }
    }
}

