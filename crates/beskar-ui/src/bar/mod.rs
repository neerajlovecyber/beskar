pub mod convex;
pub mod gaming;
pub mod island;
pub mod state;

pub use convex::{ConcaveBarPosition, ConcaveBarWidget};
pub use gaming::GamingBarWidget;
pub use island::{IslandBarWidget, OutgoingContent};
pub use state::{resolve_window_icon, BarActions, BarState, BarStyle};

use beskar_core::models::{WindowInfo, WorkspaceInfo};
use gpui_kit::assets::IconName;
use gpui_kit::component::Icon;
use gpui_kit::prelude::FluentBuilder;
use gpui_kit::*;

fn viewport_width(geometry: Option<&crate::convex::ConvexGeometry>) -> f32 {
    geometry
        .map(|geometry| geometry.width)
        .filter(|width| *width > 0.0)
        .unwrap_or(1920.0)
}

/// Beskar Bar surface separating the top bar into 3 distinct layout regions:
/// - [Left Island]: App launch button, Workspaces, open apps dock & active window
/// - [Dynamic Center Island]: Dynamic morphing notch (date, clock, MPRIS, notifications)
/// - [Right Island]: Taskbar running apps, vitals, battery, volume, system tray, power
#[derive(IntoElement)]
pub struct BeskarBar {
    left: Vec<AnyElement>,
    center: Vec<AnyElement>,
    right: Vec<AnyElement>,
    is_island_cluster: bool,
    is_convex: bool,
    is_gaming: bool,
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
            is_island_cluster: false,
            is_convex: false,
            is_gaming: false,
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

    pub fn gaming(mut self, gaming: bool) -> Self {
        self.is_gaming = gaming;
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
        let viewport_width = viewport_width(state.geometry.as_ref());
        let compact_bar = viewport_width < 800.0;
        let ws_count = state.workspaces.len();
        let has_active_win = has_win && state.active_window.is_some();
        let ws_apps_count = state.workspace_windows.len();
        let tray_count = state.tray_items.len();
        let taskbar_count = state.all_windows.len().min(6);
        let left_preferred_w = if compact_bar {
            92.0
        } else {
            (48.0
                + (ws_count.clamp(5, 10) as f32 * 18.0 + 36.0)
                + (ws_apps_count as f32 * 23.0)
                + if has_active_win { 150.0 } else { 0.0 }
                + 48.0)
                .max(240.0)
        };
        let right_preferred_w = if compact_bar {
            114.0
        } else {
            (taskbar_count as f32 * 25.0
                + (tray_count as f32 * 26.0)
                + if tray_count > 0 { 12.0 } else { 0.0 }
                + 160.0
                + 36.0
                + 48.0)
                .max(260.0)
        };
        let requested_center_w = state.animated_center_width.unwrap_or(220.0).max(220.0);
        let geometry = crate::convex::ConvexGeometry::auto_calculate(
            viewport_width,
            38.0,
            left_preferred_w,
            requested_center_w,
            right_preferred_w,
        );
        let center_w = geometry.center_w;
        let left_w = geometry.left_w;
        let right_w = geometry.right_w;
        let center_x = geometry.center_x;

        let mut ws_widget =
            WorkspacesWidget::new(state.workspaces, state.active_ws).compact(compact_bar);
        if let Some(handler) = actions.on_select_ws {
            ws_widget = ws_widget.on_select(move |id| (handler)(id));
        }
        if let Some(handler) = actions.on_scroll_ws {
            ws_widget = ws_widget.on_scroll(move |dir| (handler)(dir));
        }

        // Dedicated App Launcher Button (Left Island Trigger)
        let on_launch = actions.on_launcher_click.clone();
        let on_dash = actions.on_dashboard_click.clone();
        let app_launch_btn = div()
            .flex()
            .items_center()
            .gap(px(5.0))
            .px(px(8.0))
            .py(px(2.0))
            .mr(px(6.0))
            .rounded_full()
            .bg(beskar_theme::Theme::accent_alpha(0.14))
            .border_1()
            .border_color(beskar_theme::Theme::accent_alpha(0.32))
            .text_xs()
            .font_weight(FontWeight::SEMIBOLD)
            .text_color(beskar_theme::Theme::accent())
            .cursor_pointer()
            .hover(|s| {
                s.bg(beskar_theme::Theme::accent_alpha(0.24))
                    .border_color(beskar_theme::Theme::accent())
            })
            .on_mouse_down(MouseButton::Left, move |_, window, cx| {
                if let Some(ref handler) = on_launch {
                    handler(window, cx);
                }
            })
            .on_mouse_down(MouseButton::Right, move |_, window, cx| {
                if let Some(ref handler) = on_dash {
                    handler(window, cx);
                }
            })
            .child(
                Icon::new(IconName::LayoutGrid)
                    .size(px(13.0))
                    .text_color(beskar_theme::Theme::accent()),
            )
            .when(!compact_bar, |button| button.child("Apps"));

        // Open Applications in the Active Workspace (Workspace Window Icons)
        let ws_apps_row = if !compact_bar && !state.workspace_windows.is_empty() {
            let mut row = div().flex().items_center().gap(px(3.0)).ml(px(6.0));
            let on_win_select = actions.on_select_window.clone();
            for win in &state.workspace_windows {
                let icon = resolve_window_icon(win.app_id.as_deref(), win.title.as_deref());
                let win_id = win.id;
                let is_focused = win.is_focused;
                let on_sel = on_win_select.clone();

                row = row.child(
                    div()
                        .id(("workspace-window", win_id))
                        .flex()
                        .items_center()
                        .justify_center()
                        .w(px(20.0))
                        .h(px(20.0))
                        .rounded_md()
                        .bg(if is_focused {
                            beskar_theme::Theme::accent_alpha(0.25)
                        } else {
                            beskar_theme::Theme::bg_secondary()
                        })
                        .border_1()
                        .border_color(if is_focused {
                            beskar_theme::Theme::accent()
                        } else {
                            beskar_theme::Theme::subtle_border()
                        })
                        .cursor_pointer()
                        .hover(|s| {
                            s.bg(beskar_theme::Theme::bg_secondary())
                                .border_color(beskar_theme::Theme::accent())
                        })
                        .on_mouse_down(MouseButton::Left, move |_, _, _| {
                            if let Some(ref cb) = on_sel {
                                cb(win_id);
                            }
                        })
                        .child(
                            Icon::new(icon)
                                .size(px(11.0))
                                .text_color(if is_focused {
                                    beskar_theme::Theme::accent()
                                } else {
                                    beskar_theme::Theme::text_secondary()
                                }),
                        ),
                );
            }
            Some(row)
        } else {
            None
        };

        // Current Focused Application Name and Icon Pill
        let mut active_win_element = if has_win && !compact_bar {
            state.active_window.as_ref().and_then(|win| {
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
                let on_win_clk = actions.on_window_click.clone();
                let on_win_cls = actions.on_window_close.clone();
                Some(
                    div()
                        .flex()
                        .items_center()
                        .gap(px(6.0))
                        .ml(px(8.0))
                        .pl(px(8.0))
                        .max_w(px(160.0))
                        .min_w_0()
                        .overflow_hidden()
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
                                .text_color(beskar_theme::Theme::accent()),
                        )
                        .child(
                            div()
                                .min_w_0()
                                .overflow_hidden()
                                .whitespace_nowrap()
                                .text_ellipsis()
                                .text_xs()
                                .font_weight(FontWeight::MEDIUM)
                                .text_color(beskar_theme::Theme::fg())
                                .child(title_text.to_string()),
                        ),
                )
            })
        } else {
            None
        };

        let mut app_launch_btn = Some(app_launch_btn);
        let mut ws_widget = Some(ws_widget);
        let mut ws_apps_row = ws_apps_row;
        let mut left_pill = IslandPill::new().padding(
            if compact_bar { px(6.0) } else { px(14.0) },
            if compact_bar { px(4.0) } else { px(6.0) },
        );
        for m in &mod_left {
            match m {
                beskar_core::config::BarModule::BrandStar => {
                    if let Some(btn) = app_launch_btn.take() {
                        left_pill = left_pill.child(btn);
                    }
                }
                beskar_core::config::BarModule::Workspaces => {
                    if let Some(ws) = ws_widget.take() {
                        left_pill = left_pill.child(ws);
                    }
                    if let Some(apps) = ws_apps_row.take() {
                        left_pill = left_pill.child(apps);
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
        center_widget = center_widget.width(px(center_w));
        if let Some((title, artist, is_playing)) = state.media {
            center_widget = center_widget.media(Some(title), Some(artist), is_playing);
        }
        if let Some(handler) = actions.on_play_pause {
            center_widget = center_widget.on_play_pause(move || (handler)());
        }
        if let Some(handler) = actions.on_clock_click {
            center_widget = center_widget.on_clock_click(move |window, cx| (handler)(window, cx));
        }
        if let Some(handler) = actions.on_control_center_click.clone() {
            center_widget =
                center_widget.on_notification_click(move |window, cx| (handler)(window, cx));
        }
        if let Some(handler) = actions.on_music_click {
            center_widget = center_widget.on_media_click(move |window, cx| (handler)(window, cx));
        } else if let Some(ref handler) = actions.on_control_center_click {
            let h = handler.clone();
            center_widget = center_widget.on_media_click(move |window, cx| (h)(window, cx));
        }

        let is_island = state.bar_style == beskar_core::config::BarStyleConfig::Island;
        let is_convex = state.bar_style == beskar_core::config::BarStyleConfig::Convex || state.is_convex;
        let is_gaming = state.bar_style == beskar_core::config::BarStyleConfig::Gaming;

        let left_element = if is_convex {
            crate::bar::ConcaveBarWidget::new(Size::new(px(left_w), px(38.0)))
                .position(crate::bar::ConcaveBarPosition::Left)
                .radius(16.0)
                .color(beskar_theme::Theme::bg())
                .child(left_pill)
                .into_any_element()
        } else {
            left_pill.into_any_element()
        };

        let center_element = if is_convex {
            crate::bar::ConcaveBarWidget::new(Size::new(px(center_w), px(38.0)))
                .position(crate::bar::ConcaveBarPosition::Center)
                .radius(16.0)
                .color(beskar_theme::Theme::bg())
                .child(center_widget)
                .into_any_element()
        } else {
            div()
                .w(px(center_w))
                .max_w(px(center_w))
                .h(px(38.0))
                .overflow_hidden()
                .flex()
                .items_center()
                .justify_center()
                .child(IslandPill::new().child(center_widget))
                .into_any_element()
        };



        // Taskbar Apps Dock (Running Applications in Right Island)
        let taskbar_dock = if !compact_bar && !state.all_windows.is_empty() {
            let mut dock = div().flex().items_center().gap(px(3.0)).mr(px(8.0));
            let on_win_select = actions.on_select_window.clone();
            for win in state.all_windows.iter().take(6) {
                let icon = resolve_window_icon(win.app_id.as_deref(), win.title.as_deref());
                let win_id = win.id;
                let is_focused = win.is_focused;
                let on_sel = on_win_select.clone();

                dock = dock.child(
                    div()
                        .id(("taskbar-window", win_id))
                        .flex()
                        .items_center()
                        .justify_center()
                        .w(px(22.0))
                        .h(px(22.0))
                        .rounded_md()
                        .bg(if is_focused {
                            beskar_theme::Theme::accent_alpha(0.25)
                        } else {
                            beskar_theme::Theme::bg_secondary()
                        })
                        .border_1()
                        .border_color(if is_focused {
                            beskar_theme::Theme::accent()
                        } else {
                            beskar_theme::Theme::subtle_border()
                        })
                        .cursor_pointer()
                        .hover(|s| {
                            s.bg(beskar_theme::Theme::bg_secondary())
                                .border_color(beskar_theme::Theme::accent())
                        })
                        .on_mouse_down(MouseButton::Left, move |_, _, _| {
                            if let Some(ref cb) = on_sel {
                                cb(win_id);
                            }
                        })
                        .child(
                            Icon::new(icon)
                                .size(px(12.0))
                                .text_color(if is_focused {
                                    beskar_theme::Theme::accent()
                                } else {
                                    beskar_theme::Theme::fg()
                                }),
                        ),
                );
            }
            Some(dock)
        } else {
            None
        };

        let mut vitals_widget = VitalsWidget::new(state.volume_percent, state.battery_percent)
            .muted(state.is_muted)
            .charging(state.is_charging)
            .cpu(state.cpu_usage)
            .ram(state.ram_usage)
            .tray(state.tray_items)
            .modules(mod_right)
            .compact(compact_bar);
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

        let mut right_pill = IslandPill::new();
        if let Some(dock) = taskbar_dock {
            right_pill = right_pill.child(dock);
        }
        right_pill = right_pill.child(vitals_widget);

        let right_element = if is_convex {
            crate::bar::ConcaveBarWidget::new(Size::new(px(right_w), px(38.0)))
                .position(crate::bar::ConcaveBarPosition::Right)
                .radius(16.0)
                .color(beskar_theme::Theme::bg())
                .child(right_pill)
                .into_any_element()
        } else {
            right_pill.into_any_element()
        };

        let geom = crate::convex::ConvexGeometry {
            height: 38.0,
            left_w,
            center_x,
            center_w,
            right_w,
            ..geometry
        };

        Self::new()
            .convex(is_convex)
            .gaming(is_gaming)
            .island_cluster(is_island)
            .geometry(geom)
            .left([left_element])
            .center([center_element])
            .right([right_element])
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
        volume: u8,
        is_muted: bool,
        battery: u8,
        is_charging: bool,
    ) -> Self {
        let state = BarState {
            is_convex,
            workspaces,
            active_ws,
            active_window,
            time_str: time_str.into(),
            date_str,
            media,
            volume_percent: volume,
            is_muted,
            battery_percent: battery,
            is_charging,
            ..Default::default()
        };
        Self::from_state(state, BarActions::default())
    }
}

impl RenderOnce for BeskarBar {
    fn render(self, _window: &mut Window, _cx: &mut App) -> impl IntoElement {
        let geometry = self.geometry.unwrap_or_default();
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
                .into_any_element()
        } else {
            div()
                .relative()
                .size_full()
                .child(
                    div()
                        .absolute()
                        .top_0()
                        .bottom_0()
                        .left_0()
                        .w(px(geometry.left_w))
                        .min_w_0()
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
                        .left(px(geometry.center_x))
                        .w(px(geometry.center_w))
                        .min_w_0()
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
                        .right_0()
                        .w(px(geometry.right_w))
                        .min_w_0()
                        .flex()
                        .items_center()
                        .justify_end()
                        .children(self.right),
                )
                .into_any_element()
        }
    }
}
