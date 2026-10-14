pub mod state;
pub use state::{resolve_window_icon, BarActions, BarState};

use beskar_core::models::{WindowInfo, WorkspaceInfo};
use gpui_kit::component::Icon;
use gpui_kit::prelude::FluentBuilder;
use gpui_kit::*;
use std::sync::Arc;

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
    geometry: Option<crate::convex::ConvexGeometry>,
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
            geometry: None,
        }
    }

    pub fn geometry(mut self, geom: crate::convex::ConvexGeometry) -> Self {
        self.geometry = Some(geom);
        self
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

        let mod_left = state.modules_left.unwrap_or_else(|| {
            vec![
                beskar_core::config::BarModule::BrandStar,
                beskar_core::config::BarModule::Workspaces,
                beskar_core::config::BarModule::ActiveWindow,
            ]
        });
        let _mod_center = state.modules_center.unwrap_or_else(|| {
            vec![
                beskar_core::config::BarModule::Clock,
                beskar_core::config::BarModule::Media,
            ]
        });
        let mod_right = state.modules_right.unwrap_or_else(|| {
            vec![
                beskar_core::config::BarModule::Tray,
                beskar_core::config::BarModule::QuickControls,
                beskar_core::config::BarModule::Vitals,
                beskar_core::config::BarModule::Power,
            ]
        });

        let has_win = mod_left.contains(&beskar_core::config::BarModule::ActiveWindow);

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
            .text_color(beskar_theme::Theme::accent())
            .hover(|s| {
                s.cursor_pointer()
                    .bg(beskar_theme::Theme::bg_secondary())
                    .text_color(beskar_theme::Theme::accent())
            })
            .on_mouse_down(MouseButton::Left, move |_, window, cx| {
                if let Some(handler) = on_star.as_ref() {
                    handler(window, cx);
                }
            })
            .on_mouse_down(MouseButton::Right, move |_, window, cx| {
                if let Some(handler) = on_dash.as_ref() {
                    handler(window, cx);
                }
            })
            .child("✦");

        let active_win_element = if has_win {
            state.active_window.and_then(|win| {
                let title_text = win
                    .title
                    .as_deref()
                    .filter(|t| !t.trim().is_empty())
                    .or(win.app_id.as_deref())
                    .unwrap_or("");

                if title_text.is_empty() {
                    return None;
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
                Some(
                    div()
                        .flex()
                        .items_center()
                        .gap(px(6.0))
                        .ml(px(8.0))
                        .pl(px(8.0))
                        .border_l_1()
                        .border_color(beskar_theme::Theme::subtle_border())
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
                                .text_color(beskar_theme::Theme::text_secondary()),
                        )
                        .child(
                            div()
                                .text_xs()
                                .font_weight(FontWeight::MEDIUM)
                                .text_color(beskar_theme::Theme::fg())
                                .child(short_title),
                        ),
                )
            })
        } else {
            None
        };

        let mut star_badge = Some(star_badge);
        let mut ws_widget = Some(ws_widget);
        let mut active_win_element = active_win_element;

        let mut left_pill = IslandPill::new().convex(is_convex);
        for m in &mod_left {
            match m {
                beskar_core::config::BarModule::BrandStar => {
                    if let Some(badge) = star_badge.take() {
                        left_pill = left_pill.child(badge);
                    }
                }
                beskar_core::config::BarModule::Workspaces => {
                    if let Some(ws) = ws_widget.take() {
                        left_pill = left_pill.child(ws);
                    }
                }
                beskar_core::config::BarModule::ActiveWindow => {
                    if let Some(win_el) = active_win_element.take() {
                        left_pill = left_pill.child(win_el);
                    }
                }
                _ => {}
            }
        }

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
            center_widget = center_widget.on_clock_click(move |window, cx| (handler)(window, cx));
        }
        if let Some(handler) = actions.on_music_click {
            center_widget = center_widget.on_media_click(move |window, cx| (handler)(window, cx));
        } else if let Some(ref handler) = actions.on_control_center_click {
            let h = handler.clone();
            center_widget = center_widget.on_media_click(move |window, cx| (h)(window, cx));
        }
        let center_pill = IslandPill::new().convex(is_convex).child(center_widget);

        let mut vitals_widget = VitalsWidget::new(state.volume_percent, state.battery_percent)
            .muted(state.is_muted)
            .charging(state.is_charging)
            .cpu(state.cpu_usage)
            .ram(state.ram_usage)
            .tray(state.tray_items)
            .modules(mod_right);
        if let Some(handler) = actions.on_volume_click {
            vitals_widget = vitals_widget.on_volume_click(move || (handler)());
        }
        if let Some(handler) = actions.on_volume_scroll {
            vitals_widget = vitals_widget.on_volume_scroll(move |delta| (handler)(delta));
        }
        if let Some(handler) = actions.on_control_center_click {
            vitals_widget = vitals_widget.on_control_center_click(move |window, cx| (handler)(window, cx));
        }
        if let Some(handler) = actions.on_capture_click {
            vitals_widget = vitals_widget.on_capture_click(move |window, cx| (handler)(window, cx));
        }
        if let Some(handler) = actions.on_wallpaper_click {
            vitals_widget = vitals_widget.on_wallpaper_click(move |window, cx| (handler)(window, cx));
        }
        if let Some(handler) = actions.on_power_click {
            vitals_widget = vitals_widget.on_power_click(move |window, cx| (handler)(window, cx));
        }
        if let Some(handler) = actions.on_tray_click {
            vitals_widget = vitals_widget.on_tray_click(move |id| (handler)(id));
        }
        if let Some(handler) = actions.on_tray_menu {
            vitals_widget = vitals_widget.on_tray_menu(move |id, window, cx| (handler)(id, window, cx));
        }
        let right_pill = IslandPill::new().convex(is_convex).child(vitals_widget);

        let geom = state.geometry.unwrap_or_else(|| {
            let center_w = state.animated_center_width.unwrap_or(260.0);
            crate::convex::ConvexGeometry {
                center_w,
                ..Default::default()
            }
        });

        Self::new()
            .convex(is_convex)
            .geometry(geom)
            .left([left_pill.into_any_element()])
            .center([center_pill.into_any_element()])
            .right([right_pill.into_any_element()])
    }

    /// Builds the signature 3-Island layout matching minflair and the reference screenshot
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
        on_control_center_click: Option<crate::bar::state::BarUiCallback>,
        on_power_click: Option<crate::bar::state::BarUiCallback>,
        on_launcher_click: Option<crate::bar::state::BarUiCallback>,
        on_clock_click: Option<crate::bar::state::BarUiCallback>,
        on_dashboard_click: Option<crate::bar::state::BarUiCallback>,
        on_music_click: Option<crate::bar::state::BarUiCallback>,
        on_capture_click: Option<crate::bar::state::BarUiCallback>,
        on_wallpaper_click: Option<crate::bar::state::BarUiCallback>,
        on_tray_click: Option<Arc<dyn Fn(String) + Send + Sync>>,
        on_tray_menu: Option<crate::bar::state::BarTrayMenuCallback>,
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
            cpu_usage: None,
            ram_usage: None,
            animated_center_width,
            cava_bands,
            tray_items,
            modules_left: None,
            modules_center: None,
            modules_right: None,
            geometry: None,
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
                has_windows: false,
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
            let geom = self.geometry.unwrap_or_default();
            div()
                .relative()
                .size_full()
                .when(self.is_convex, |this| {
                    let fill = beskar_theme::Theme::bg();
                    let border = beskar_theme::Theme::subtle_border();
                    this.child(
                        div()
                            .absolute()
                            .inset_0()
                            .child(crate::convex::ConvexBarShape::new(geom, fill, border)),
                    )
                })
                .child(
                    div()
                        .absolute()
                        .inset_0()
                        .flex()
                        .items_center()
                        .justify_center()
                        .children(self.center),
                )
                .child(
                    div()
                        .absolute()
                        .top_0()
                        .bottom_0()
                        .left_0()
                        .pl(self.padding_x)
                        .flex()
                        .items_center()
                        .justify_start()
                        .children(self.left),
                )
                .child(
                    div()
                        .absolute()
                        .top_0()
                        .bottom_0()
                        .right_0()
                        .pr(self.padding_x)
                        .flex()
                        .items_center()
                        .justify_end()
                        .children(self.right),
                )
        }
    }
}
