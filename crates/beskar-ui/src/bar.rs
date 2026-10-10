use beskar_core::models::WorkspaceInfo;
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
        }
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

    /// Builds the signature 3-Island layout matching minflair and the reference screenshot:
    /// - Left: Brand star badge + WorkspacesWidget inside an IslandPill
    /// - Center: DynamicCenterWidget (Clock + MPRIS) inside an IslandPill
    /// - Right: VitalsWidget (Recording + Controls + Audio/WiFi/Battery/Power) inside an IslandPill
    pub fn live_islands(
        workspaces: Vec<WorkspaceInfo>,
        active_ws: Option<u64>,
        time_str: impl Into<String>,
        date_str: Option<String>,
        media: Option<(String, String, bool)>,
        volume_percent: u8,
        is_muted: bool,
        battery_percent: u8,
        is_charging: bool,
        animated_center_width: Option<f32>,
        tray_items: Vec<beskar_core::models::TrayItem>,
        on_select_ws: Option<Arc<dyn Fn(u64) + Send + Sync>>,
        on_scroll_ws: Option<Arc<dyn Fn(i32) + Send + Sync>>,
        on_play_pause: Option<Arc<dyn Fn() + Send + Sync>>,
        on_volume_click: Option<Arc<dyn Fn() + Send + Sync>>,
        on_volume_scroll: Option<Arc<dyn Fn(i32) + Send + Sync>>,
        on_control_center_click: Option<Arc<dyn Fn() + Send + Sync>>,
        on_power_click: Option<Arc<dyn Fn() + Send + Sync>>,
        on_launcher_click: Option<Arc<dyn Fn() + Send + Sync>>,
    ) -> Self {
        use crate::pill::IslandPill;
        use crate::widgets::{DynamicCenterWidget, VitalsWidget, WorkspacesWidget};

        let mut ws_widget = WorkspacesWidget::new(workspaces, active_ws);
        if let Some(handler) = on_select_ws {
            ws_widget = ws_widget.on_select(move |id| (handler)(id));
        }
        if let Some(handler) = on_scroll_ws {
            ws_widget = ws_widget.on_scroll(move |dir| (handler)(dir));
        }

        let on_star = on_launcher_click.clone();
        let star_badge = div()
            .mr(px(8.0))
            .text_xs()
            .font_weight(FontWeight::BOLD)
            .text_color(hsla(45.0 / 360.0, 0.90, 0.60, 1.0))
            .hover(|s| {
                s.cursor_pointer()
                    .text_color(hsla(45.0 / 360.0, 1.0, 0.75, 1.0))
            })
            .on_mouse_down(MouseButton::Left, move |_, _, _| {
                if let Some(handler) = on_star.as_ref() {
                    handler();
                }
            })
            .child("✦");

        let left_pill = IslandPill::new()
            .convex(true)
            .child(star_badge)
            .child(ws_widget);

        let mut center_widget = DynamicCenterWidget::new(time_str).date(date_str);
        if let Some(w) = animated_center_width {
            center_widget = center_widget.width(px(w));
        }
        if let Some((title, artist, is_playing)) = media {
            center_widget = center_widget.media(Some(title), Some(artist), is_playing);
        }
        if let Some(handler) = on_play_pause {
            center_widget = center_widget.on_play_pause(move || (handler)());
        }
        let center_pill = IslandPill::new().convex(true).child(center_widget);

        let mut vitals_widget = VitalsWidget::new(volume_percent, battery_percent)
            .muted(is_muted)
            .charging(is_charging)
            .tray(tray_items);
        if let Some(handler) = on_volume_click {
            vitals_widget = vitals_widget.on_volume_click(move || (handler)());
        }
        if let Some(handler) = on_volume_scroll {
            vitals_widget = vitals_widget.on_volume_scroll(move |delta| (handler)(delta));
        }
        if let Some(handler) = on_control_center_click {
            vitals_widget = vitals_widget.on_control_center_click(move || (handler)());
        }
        if let Some(handler) = on_power_click {
            vitals_widget = vitals_widget.on_power_click(move || (handler)());
        }
        let right_pill = IslandPill::new().convex(true).child(vitals_widget);


        Self::new()
            .left([left_pill.into_any_element()])
            .center([center_pill.into_any_element()])
            .right([right_pill.into_any_element()])
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
            fake_workspaces,
            Some(active_ws),
            time_str,
            None,
            media,
            65,
            false,
            88,
            false,
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
        )
    }
}

impl RenderOnce for BeskarBar {
    fn render(self, _window: &mut Window, _cx: &mut App) -> impl IntoElement {
        div()
            .relative()
            .size_full()
            .flex()
            .items_start()
            .px(self.padding_x)
            // Continuous top bridge line connecting the notches across the top edge
            .child(
                div()
                    .absolute()
                    .top_0()
                    .left_0()
                    .right_0()
                    .h(px(5.0))
                    .bg(hsla(250.0 / 360.0, 0.16, 0.06, 0.96))
                    .border_b_1()
                    .border_color(hsla(240.0 / 360.0, 0.10, 1.0, 0.08)),
            )
            // Left region: Left Island Notch
            .child(
                div()
                    .flex()
                    .flex_1()
                    .items_start()
                    .justify_start()
                    .children(self.left),
            )
            // Center region: Dynamic Center Island Notch
            .child(
                div()
                    .flex()
                    .items_start()
                    .justify_center()
                    .children(self.center),
            )
            // Right region: Right Island Notch
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

