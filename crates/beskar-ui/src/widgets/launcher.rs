use beskar_core::models::AppItem;
use gpui_kit::prelude::FluentBuilder;
use gpui_kit::*;
use std::sync::Arc;

/// Premium Raycast / Spotlight style application launcher modal.
/// Floating glass acrylic card with search filtering, app badges, and launch callbacks.
#[derive(IntoElement)]
pub struct LauncherWidget {
    query: String,
    apps: Vec<AppItem>,
    selected_idx: usize,
    on_launch: Option<Arc<dyn Fn(String) + Send + Sync>>,
    on_close: Option<Arc<dyn Fn() + Send + Sync>>,
}

impl LauncherWidget {
    pub fn new(apps: Vec<AppItem>) -> Self {
        Self {
            query: String::new(),
            apps,
            selected_idx: 0,
            on_launch: None,
            on_close: None,
        }
    }

    pub fn query(mut self, query: impl Into<String>) -> Self {
        self.query = query.into();
        self
    }

    pub fn selected_idx(mut self, idx: usize) -> Self {
        self.selected_idx = idx;
        self
    }

    pub fn on_launch(mut self, handler: impl Fn(String) + Send + Sync + 'static) -> Self {
        self.on_launch = Some(Arc::new(handler));
        self
    }

    pub fn on_close(mut self, handler: impl Fn() + Send + Sync + 'static) -> Self {
        self.on_close = Some(Arc::new(handler));
        self
    }
}

impl RenderOnce for LauncherWidget {
    fn render(self, _window: &mut Window, _cx: &mut App) -> impl IntoElement {
        let q = self.query.to_lowercase();
        let filtered_apps: Vec<AppItem> = if q.is_empty() {
            self.apps
        } else {
            self.apps
                .into_iter()
                .filter(|a| {
                    a.name.to_lowercase().contains(&q)
                        || a.local_name.to_lowercase().contains(&q)
                        || a.categories.to_lowercase().contains(&q)
                        || a.exec.to_lowercase().contains(&q)
                })
                .collect()
        };

        let total_count = filtered_apps.len();
        let selected_idx = self.selected_idx.min(total_count.saturating_sub(1));
        let on_launch = self.on_launch.clone();
        let on_close = self.on_close.clone();

        div()
            .w(px(560.0))
            .max_h(px(460.0))
            .flex()
            .flex_col()
            .rounded(px(18.0))
            // Acrylic glass backdrop
            .bg(hsla(220.0 / 360.0, 0.22, 0.10, 0.94))
            .border_1()
            .border_color(hsla(0.0, 0.0, 1.0, 0.16))
            .shadow_xl()
            .overflow_hidden()
            // Specular top highlight line
            .child(
                div()
                    .w_full()
                    .h(px(1.0))
                    .bg(hsla(0.0, 0.0, 1.0, 0.25)),
            )
            // Search Input Header
            .child(
                div()
                    .w_full()
                    .h(px(54.0))
                    .flex()
                    .items_center()
                    .px(px(16.0))
                    .border_b_1()
                    .border_color(hsla(0.0, 0.0, 1.0, 0.10))
                    .gap(px(12.0))
                    .child(
                        // Magnifying glass / search star badge
                        div()
                            .text_base()
                            .font_weight(FontWeight::BOLD)
                            .text_color(hsla(215.0 / 360.0, 0.85, 0.65, 1.0))
                            .child("✦"),
                    )
                    .child(
                        div()
                            .flex_1()
                            .text_sm()
                            .font_weight(FontWeight::MEDIUM)
                            .text_color(if self.query.is_empty() {
                                hsla(0.0, 0.0, 0.60, 0.80)
                            } else {
                                hsla(0.0, 0.0, 0.98, 1.0)
                            })
                            .child(if self.query.is_empty() {
                                "Search applications, utilities, and settings...".to_string()
                            } else {
                                self.query.clone()
                            }),
                    )
                    .child(
                        // ESC key badge to close
                        div()
                            .px(px(6.0))
                            .py(px(2.0))
                            .rounded(px(4.0))
                            .bg(hsla(0.0, 0.0, 1.0, 0.10))
                            .border_1()
                            .border_color(hsla(0.0, 0.0, 1.0, 0.15))
                            .text_xs()
                            .text_color(hsla(0.0, 0.0, 0.70, 0.90))
                            .hover(|s| s.cursor_pointer().bg(hsla(0.0, 0.0, 1.0, 0.20)))
                            .on_mouse_down(MouseButton::Left, move |_, _, _| {
                                if let Some(handler) = on_close.as_ref() {
                                    handler();
                                }
                            })
                            .child("ESC"),
                    ),
            )
            // Applications List
            .child(
                div()
                    .w_full()
                    .flex_1()
                    .flex()
                    .flex_col()
                    .py(px(8.0))
                    .px(px(8.0))
                    .gap(px(4.0))
                    .when(total_count == 0, |this| {
                        this.child(
                            div()
                                .w_full()
                                .py(px(32.0))
                                .flex()
                                .flex_col()
                                .items_center()
                                .justify_center()
                                .text_sm()
                                .text_color(hsla(0.0, 0.0, 0.50, 1.0))
                                .child("No matching applications found"),
                        )
                    })
                    .children(
                        filtered_apps
                            .into_iter()
                            .take(7)
                            .enumerate()
                            .map(|(i, app)| {
                                let is_active = i == selected_idx;
                                let exec = app.exec.clone();
                                let on_launch = on_launch.clone();

                                let first_letter = app
                                    .name
                                    .chars()
                                    .next()
                                    .unwrap_or('A')
                                    .to_uppercase()
                                    .to_string();

                                div()
                                    .w_full()
                                    .h(px(46.0))
                                    .flex()
                                    .items_center()
                                    .px(px(10.0))
                                    .rounded(px(10.0))
                                    .border_1()
                                    .border_color(if is_active {
                                        hsla(215.0 / 360.0, 0.75, 0.60, 0.40)
                                    } else {
                                        hsla(0.0, 0.0, 0.0, 0.0)
                                    })
                                    .bg(if is_active {
                                        hsla(215.0 / 360.0, 0.50, 0.25, 0.45)
                                    } else {
                                        hsla(0.0, 0.0, 0.0, 0.0)
                                    })
                                    .hover(|s| {
                                        s.bg(hsla(0.0, 0.0, 1.0, 0.08))
                                            .cursor_pointer()
                                    })
                                    .on_mouse_down(MouseButton::Left, move |_, _, _| {
                                        if let Some(handler) = on_launch.as_ref() {
                                            handler(exec.clone());
                                        }
                                    })
                                    // App Icon Badge
                                    .child(
                                        div()
                                            .size(px(28.0))
                                            .rounded(px(8.0))
                                            .mr(px(10.0))
                                            .flex()
                                            .items_center()
                                            .justify_center()
                                            .bg(if is_active {
                                                hsla(215.0 / 360.0, 0.70, 0.50, 0.35)
                                            } else {
                                                hsla(0.0, 0.0, 1.0, 0.08)
                                            })
                                            .border_1()
                                            .border_color(hsla(0.0, 0.0, 1.0, 0.12))
                                            .text_xs()
                                            .font_weight(FontWeight::BOLD)
                                            .text_color(if is_active {
                                                hsla(215.0 / 360.0, 0.90, 0.80, 1.0)
                                            } else {
                                                hsla(0.0, 0.0, 0.85, 1.0)
                                            })
                                            .child(first_letter),
                                    )
                                    // App Title & Category
                                    .child(
                                        div()
                                            .flex_1()
                                            .flex()
                                            .flex_col()
                                            .justify_center()
                                            .child(
                                                div()
                                                    .text_sm()
                                                    .font_weight(FontWeight::SEMIBOLD)
                                                    .text_color(if is_active {
                                                        hsla(0.0, 0.0, 1.0, 1.0)
                                                    } else {
                                                        hsla(0.0, 0.0, 0.90, 1.0)
                                                    })
                                                    .child(app.name),
                                            )
                                            .when(!app.categories.is_empty(), |this| {
                                                let cat = app
                                                    .categories
                                                    .split(';')
                                                    .filter(|c| !c.is_empty())
                                                    .take(2)
                                                    .collect::<Vec<_>>()
                                                    .join(" • ");
                                                this.child(
                                                    div()
                                                        .text_xs()
                                                        .text_color(hsla(
                                                            220.0 / 360.0,
                                                            0.15,
                                                            0.65,
                                                            0.80,
                                                        ))
                                                        .child(cat),
                                                )
                                            }),
                                    )
                                    // Enter / Launch badge when active
                                    .when(is_active, |this| {
                                        this.child(
                                            div()
                                                .px(px(8.0))
                                                .py(px(3.0))
                                                .rounded(px(6.0))
                                                .bg(hsla(215.0 / 360.0, 0.60, 0.40, 0.50))
                                                .text_xs()
                                                .font_weight(FontWeight::MEDIUM)
                                                .text_color(hsla(0.0, 0.0, 1.0, 0.95))
                                                .child("↵ Open"),
                                        )
                                    })
                            }),
                    ),
            )
            // Footer Info Bar
            .child(
                div()
                    .w_full()
                    .h(px(36.0))
                    .px(px(16.0))
                    .flex()
                    .items_center()
                    .justify_between()
                    .border_t_1()
                    .border_color(hsla(0.0, 0.0, 1.0, 0.08))
                    .bg(hsla(220.0 / 360.0, 0.22, 0.08, 0.50))
                    .child(
                        div()
                            .text_xs()
                            .text_color(hsla(0.0, 0.0, 0.55, 0.85))
                            .child(format!("{total_count} applications found")),
                    )
                    .child(
                        div()
                            .flex()
                            .items_center()
                            .gap(px(12.0))
                            .child(
                                div()
                                    .text_xs()
                                    .text_color(hsla(0.0, 0.0, 0.50, 0.85))
                                    .child("↑↓ navigate"),
                            )
                            .child(
                                div()
                                    .text_xs()
                                    .text_color(hsla(0.0, 0.0, 0.50, 0.85))
                                    .child("↵ launch"),
                            ),
                    ),
            )
    }
}
