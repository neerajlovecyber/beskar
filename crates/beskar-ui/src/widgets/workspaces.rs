use beskar_core::models::WorkspaceInfo;
use gpui_kit::prelude::FluentBuilder;
use gpui_kit::*;
use std::sync::Arc;

/// Workspaces widget adapted directly from Minflair's `Workspaces.qml`.
/// Features:
/// - Dynamic 10-slot layout with min 5 slots matching Minflair
/// - Active workspace: elongated 24×8px capsule colored in `Theme::accent()` (lavender `#a77ef5`)
/// - Occupied workspace (`has_windows`): 8×8px dot at 0.65 opacity (0.95 on hover)
/// - Empty workspace: 8×8px dot at 0.22 opacity (0.45 on hover)
/// - Hover scale with pointer cursor
/// - Smooth mouse-wheel scrolling for prev/next workspace switching
#[derive(Clone, IntoElement)]
pub struct WorkspacesWidget {
    workspaces: Vec<WorkspaceInfo>,
    active_id: Option<u64>,
    on_select: Option<Arc<dyn Fn(u64) + Send + Sync>>,
    on_scroll: Option<Arc<dyn Fn(i32) + Send + Sync>>,
}

impl WorkspacesWidget {
    pub fn new(workspaces: Vec<WorkspaceInfo>, active_id: Option<u64>) -> Self {
        Self {
            workspaces,
            active_id,
            on_select: None,
            on_scroll: None,
        }
    }

    pub fn on_select(mut self, handler: impl Fn(u64) + Send + Sync + 'static) -> Self {
        self.on_select = Some(Arc::new(handler));
        self
    }

    pub fn on_scroll(mut self, handler: impl Fn(i32) + Send + Sync + 'static) -> Self {
        self.on_scroll = Some(Arc::new(handler));
        self
    }
}

impl RenderOnce for WorkspacesWidget {
    fn render(self, _window: &mut Window, _cx: &mut App) -> impl IntoElement {
        let on_select = self.on_select;
        let on_scroll = self.on_scroll;

        // Determine the single active workspace ID (preferring focused workspace)
        let active_ws_id = self
            .workspaces
            .iter()
            .find(|w| w.is_focused)
            .map(|w| w.id)
            .or(self.active_id)
            .or_else(|| self.workspaces.first().map(|w| w.id))
            .unwrap_or(1);

        // Find the index (1-based) of the active workspace
        let active_slot_idx = self
            .workspaces
            .iter()
            .find(|w| w.id == active_ws_id)
            .map(|w| w.idx as u64)
            .unwrap_or(active_ws_id.max(1));

        // Find highest occupied workspace index (matching Minflair maxOccupiedWsId)
        let max_occupied_ws = self
            .workspaces
            .iter()
            .filter(|w| w.has_windows)
            .map(|w| w.idx as u64)
            .max()
            .unwrap_or(1);

        // Visible count calculation from Minflair: Math.min(10, Math.max(Math.max(activeWsId, maxOccupiedWsId) + 1, 5))
        let visible_count = 10.min((active_slot_idx.max(max_occupied_ws) + 1).max(5));

        div()
            .flex()
            .items_center()
            .gap(px(6.0))
            .h(px(28.0))
            .px(px(10.0))
            .py(px(4.0))
            .rounded_full()
            .bg(beskar_theme::Theme::bg_secondary())
            .when_some(on_scroll, |el, cb| {
                el.on_scroll_wheel(move |event, _, _| {
                    let delta = event.delta.pixel_delta(px(1.0));
                    if delta.y.abs() > px(0.5) {
                        let direction = if delta.y > px(0.0) { -1 } else { 1 };
                        (cb)(direction);
                    }
                })
            })
            .children((1..=visible_count).map(|slot_idx| {
                // Find matching workspace by idx (1-based slot)
                let ws_match = self
                    .workspaces
                    .iter()
                    .find(|w| (w.idx as u64) == slot_idx || (self.workspaces.len() == 1 && w.id == slot_idx));

                // A slot is active IF AND ONLY IF it represents the single active workspace
                let is_active = if let Some(ws) = ws_match {
                    ws.id == active_ws_id
                } else {
                    slot_idx == active_slot_idx
                };

                let has_windows = ws_match.map_or(false, |w| w.has_windows);
                let target_id = ws_match.map_or(slot_idx, |w| w.id);

                let on_select_cb = on_select.clone();

                if is_active {
                    // Active workspace: Elongated 24×8px capsule in accent color (lavender #a77ef5)
                    div()
                        .w(px(24.0))
                        .h(px(8.0))
                        .rounded(px(4.0))
                        .bg(beskar_theme::Theme::accent())
                        .shadow_sm()
                        .into_any_element()
                } else {
                    // Inactive workspace: 8×8px dot with Minflair opacities
                    let mut fg_normal = beskar_theme::Theme::fg();
                    let mut fg_hover = beskar_theme::Theme::fg();

                    if has_windows {
                        fg_normal.a = 0.65;
                        fg_hover.a = 0.95;
                    } else {
                        fg_normal.a = 0.22;
                        fg_hover.a = 0.45;
                    }

                    div()
                        .flex()
                        .items_center()
                        .justify_center()
                        .w(px(14.0))
                        .h(px(18.0))
                        .cursor_pointer()
                        .child(
                            div()
                                .w(px(8.0))
                                .h(px(8.0))
                                .rounded_full()
                                .bg(fg_normal)
                                .hover(move |s| s.bg(fg_hover)),
                        )
                        .when_some(on_select_cb, move |el, cb| {
                            el.on_mouse_down(MouseButton::Left, move |_, _, _| {
                                (cb)(target_id);
                            })
                        })
                        .into_any_element()
                }
            }))
    }
}
