use beskar_core::models::WorkspaceInfo;
use gpui_kit::prelude::FluentBuilder;
use gpui_kit::*;
use std::sync::Arc;

/// Workspaces widget adapted directly from gpui-shell & minflair.
/// Renders actual compositor workspaces from Niri:
/// - Elongated amber/gold capsule pill for the active workspace
/// - Subtle dots for inactive workspaces with hover and click interactions
#[derive(IntoElement)]
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
        let active_id = self.active_id;
        let on_select = self.on_select;
        let on_scroll = self.on_scroll;

        // If no workspaces are reported yet, show 4 default placeholders
        let workspaces = if self.workspaces.is_empty() {
            (1..=4)
                .map(|i| WorkspaceInfo {
                    id: i as u64,
                    idx: i as u8,
                    name: None,
                    output: String::new(),
                    is_active: i == 1,
                    is_focused: i == 1,
                })
                .collect()
        } else {
            self.workspaces
        };

        div()
            .flex()
            .items_center()
            .gap(px(7.0))
            .py(px(4.0))
            .px(px(4.0))
            .when_some(on_scroll, |el, cb| {
                el.on_scroll_wheel(move |event, _, _| {
                    let delta = event.delta.pixel_delta(px(1.0));
                    if delta.y.abs() > px(0.5) {
                        let direction = if delta.y > px(0.0) { -1 } else { 1 };
                        (cb)(direction);
                    }
                })
            })
            .children(workspaces.into_iter().map(|ws| {
                let id = ws.id;
                let is_active = ws.is_focused || ws.is_active || (Some(ws.id) == active_id);
                let on_select_cb = on_select.clone();

                if is_active {
                    // Active workspace: Elongated gold/amber capsule pill (24px wide, 8px tall)
                    div()
                        .w(px(24.0))
                        .h(px(8.0))
                        .rounded(px(4.0))
                        .bg(hsla(45.0 / 360.0, 0.90, 0.60, 1.0))
                        .shadow_sm()
                } else {
                    // Inactive workspace: Subtle 8px circular dot
                    div()
                        .w(px(8.0))
                        .h(px(8.0))
                        .rounded_full()
                        .bg(hsla(240.0 / 360.0, 0.08, 0.40, 0.60))
                        .hover(|style| {
                            style
                                .bg(hsla(0.0, 0.0, 0.90, 0.90))
                                .cursor_pointer()
                        })
                        .when_some(on_select_cb, |el, cb| {
                            el.on_mouse_down(MouseButton::Left, move |_, _, _| {
                                (cb)(id);
                            })
                        })
                }
            }))
    }
}
