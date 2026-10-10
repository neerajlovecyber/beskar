use beskar_core::models::AppItem;
use gpui_kit::assets::IconName;
use gpui_kit::component::Icon;
use gpui_kit::prelude::FluentBuilder;
use gpui_kit::*;
use std::sync::Arc;

/// App launcher widget with live fuzzy/prefix search filtering, keyboard & mouse selection,
/// categories metadata badge, and Minflair obsidian acrylic styling.
#[derive(IntoElement)]
pub struct LauncherWidget {
    query: String,
    apps: Vec<AppItem>,
    selected_idx: usize,
    on_select: Option<Arc<dyn Fn(usize) + Send + Sync>>,
    on_launch: Option<Arc<dyn Fn(String) + Send + Sync>>,
    on_clear: Option<Arc<dyn Fn() + Send + Sync>>,
    on_close: Option<Arc<dyn Fn() + Send + Sync>>,
}

impl LauncherWidget {
    pub fn new(apps: Vec<AppItem>) -> Self {
        Self {
            query: String::new(),
            apps,
            selected_idx: 0,
            on_select: None,
            on_launch: None,
            on_clear: None,
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

    pub fn on_select(mut self, handler: impl Fn(usize) + Send + Sync + 'static) -> Self {
        self.on_select = Some(Arc::new(handler));
        self
    }

    pub fn on_launch(mut self, handler: impl Fn(String) + Send + Sync + 'static) -> Self {
        self.on_launch = Some(Arc::new(handler));
        self
    }

    pub fn on_clear(mut self, handler: impl Fn() + Send + Sync + 'static) -> Self {
        self.on_clear = Some(Arc::new(handler));
        self
    }

    pub fn on_close(mut self, handler: impl Fn() + Send + Sync + 'static) -> Self {
        self.on_close = Some(Arc::new(handler));
        self
    }

    /// Pure filtering and ranking function matching Minflair mechanics.
    pub fn filter_and_rank(apps: &[AppItem], query: &str) -> Vec<AppItem> {
        let q = query.trim().to_lowercase();
        if q.is_empty() {
            return apps.to_vec();
        }

        struct ScoredApp {
            app: AppItem,
            score: u32,
        }

        let mut scored: Vec<ScoredApp> = Vec::new();
        for app in apps {
            let name_lower = app.name.to_lowercase();
            let local_lower = app.local_name.to_lowercase();
            let cat_lower = app.categories.to_lowercase();
            let exec_lower = app.exec.to_lowercase();

            let score = if name_lower.starts_with(&q) {
                10
            } else if local_lower.starts_with(&q) {
                20
            } else if name_lower.split_whitespace().any(|w| w.starts_with(&q)) {
                30
            } else if name_lower.contains(&q) {
                40
            } else if local_lower.contains(&q) {
                50
            } else if cat_lower.contains(&q) {
                60
            } else if exec_lower.contains(&q) {
                70
            } else {
                continue;
            };

            scored.push(ScoredApp {
                app: app.clone(),
                score,
            });
        }

        scored.sort_by(|a, b| {
            a.score
                .cmp(&b.score)
                .then_with(|| a.app.name.to_lowercase().cmp(&b.app.name.to_lowercase()))
        });

        scored.into_iter().map(|s| s.app).collect()
    }
}

fn app_icon_for_category(categories: &str, name: &str) -> IconName {
    let cat = categories.to_lowercase();
    let name_l = name.to_lowercase();
    if cat.contains("development")
        || cat.contains("programming")
        || name_l.contains("code")
        || name_l.contains("rust")
    {
        IconName::Code
    } else if cat.contains("terminal")
        || name_l.contains("terminal")
        || name_l.contains("kitty")
        || name_l.contains("alacritty")
    {
        IconName::Terminal
    } else if cat.contains("settings")
        || cat.contains("preferences")
        || cat.contains("configuration")
    {
        IconName::Settings
    } else if cat.contains("network")
        || cat.contains("webbrowser")
        || cat.contains("internet")
        || name_l.contains("browser")
    {
        IconName::Globe
    } else if cat.contains("audio") || cat.contains("music") {
        IconName::Music
    } else if cat.contains("video") || cat.contains("player") || cat.contains("tv") {
        IconName::Film
    } else if cat.contains("graphics") || cat.contains("photo") || cat.contains("image") {
        IconName::Image
    } else if cat.contains("filemanager") || cat.contains("files") {
        IconName::Folder
    } else if cat.contains("office") || cat.contains("document") || cat.contains("texteditor") {
        IconName::FileText
    } else if cat.contains("utility") || cat.contains("system") {
        IconName::Boxes
    } else {
        IconName::Rocket
    }
}

impl RenderOnce for LauncherWidget {
    fn render(self, _window: &mut Window, _cx: &mut App) -> impl IntoElement {
        let filtered_apps = Self::filter_and_rank(&self.apps, &self.query);
        let total_count = filtered_apps.len();
        let selected_idx = self.selected_idx.min(total_count.saturating_sub(1));

        let on_select = self.on_select.clone();
        let on_launch = self.on_launch.clone();
        let on_clear = self.on_clear.clone();
        let on_close = self.on_close.clone();

        // Minflair obsidian theme tokens
        let bg_obsidian = hsla(268.0 / 360.0, 0.40, 0.05, 0.95);
        let border_subtle = hsla(0.0, 0.0, 1.0, 0.14);
        let accent = hsla(261.0 / 360.0, 0.86, 0.73, 1.0);
        let accent_glow = hsla(261.0 / 360.0, 0.86, 0.73, 0.22);
        let accent_border = hsla(261.0 / 360.0, 0.86, 0.73, 0.45);

        // Windowed visible list (max 8 visible items matching Minflair)
        const WINDOW_SIZE: usize = 8;
        let start_idx = if selected_idx >= WINDOW_SIZE {
            selected_idx - WINDOW_SIZE + 1
        } else {
            0
        };
        let end_idx = (start_idx + WINDOW_SIZE).min(total_count);
        let visible_items = if total_count > 0 {
            &filtered_apps[start_idx..end_idx]
        } else {
            &[]
        };

        div()
            .w(px(640.0))
            .max_h(px(460.0))
            .flex()
            .flex_col()
            .rounded(px(18.0))
            .bg(bg_obsidian)
            .border_1()
            .border_color(border_subtle)
            .shadow_2xl()
            .overflow_hidden()
            // Header Search Input
            .child(
                div()
                    .w_full()
                    .h(px(56.0))
                    .flex()
                    .items_center()
                    .px(px(16.0))
                    .border_b_1()
                    .border_color(hsla(0.0, 0.0, 1.0, 0.08))
                    .gap(px(12.0))
                    .child(
                        Icon::new(IconName::Search)
                            .size(px(18.0))
                            .text_color(accent),
                    )
                    .child(
                        div().flex_1().flex().items_center().child(
                            if self.query.is_empty() {
                                div()
                                    .text_sm()
                                    .font_weight(FontWeight::NORMAL)
                                    .text_color(hsla(0.0, 0.0, 0.50, 0.85))
                                    .child("Search applications, utilities, and settings...")
                            } else {
                                div()
                                    .flex()
                                    .items_center()
                                    .child(
                                        div()
                                            .text_sm()
                                            .font_weight(FontWeight::SEMIBOLD)
                                            .text_color(hsla(0.0, 0.0, 0.98, 1.0))
                                            .child(self.query.clone()),
                                    )
                                    .child(
                                        div()
                                            .w(px(2.0))
                                            .h(px(16.0))
                                            .ml(px(2.0))
                                            .rounded_full()
                                            .bg(accent),
                                    )
                            },
                        ),
                    )
                    .when(!self.query.is_empty(), |this| {
                        let on_clear = on_clear.clone();
                        this.child(
                            div()
                                .size(px(22.0))
                                .rounded_full()
                                .flex()
                                .items_center()
                                .justify_center()
                                .bg(hsla(0.0, 0.0, 1.0, 0.08))
                                .hover(|s| s.bg(hsla(0.0, 0.0, 1.0, 0.16)).cursor_pointer())
                                .on_mouse_down(MouseButton::Left, move |_, _, _| {
                                    if let Some(h) = on_clear.as_ref() {
                                        h();
                                    }
                                })
                                .child(
                                    Icon::new(IconName::X)
                                        .size(px(12.0))
                                        .text_color(hsla(0.0, 0.0, 0.75, 1.0)),
                                ),
                        )
                    })
                    .child(
                        div()
                            .px(px(7.0))
                            .py(px(2.5))
                            .rounded(px(5.0))
                            .bg(hsla(0.0, 0.0, 1.0, 0.08))
                            .border_1()
                            .border_color(hsla(0.0, 0.0, 1.0, 0.12))
                            .text_xs()
                            .font_weight(FontWeight::MEDIUM)
                            .text_color(hsla(0.0, 0.0, 0.65, 0.90))
                            .hover(|s| s.cursor_pointer().bg(hsla(0.0, 0.0, 1.0, 0.18)))
                            .on_mouse_down(MouseButton::Left, move |_, _, _| {
                                if let Some(h) = on_close.as_ref() {
                                    h();
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
                                .py(px(48.0))
                                .flex()
                                .flex_col()
                                .items_center()
                                .justify_center()
                                .gap(px(10.0))
                                .child(
                                    Icon::new(IconName::Search)
                                        .size(px(28.0))
                                        .text_color(hsla(0.0, 0.0, 0.35, 1.0)),
                                )
                                .child(
                                    div()
                                        .text_sm()
                                        .font_weight(FontWeight::MEDIUM)
                                        .text_color(hsla(0.0, 0.0, 0.50, 1.0))
                                        .child("No matching applications found"),
                                ),
                        )
                    })
                    .children(visible_items.iter().enumerate().map(|(i, app)| {
                        let real_idx = start_idx + i;
                        let is_active = real_idx == selected_idx;
                        let exec = app.exec.clone();
                        let on_launch = on_launch.clone();
                        let on_select = on_select.clone();

                        let icon_name = app_icon_for_category(&app.categories, &app.name);

                        div()
                            .w_full()
                            .h(px(44.0))
                            .flex()
                            .items_center()
                            .px(px(10.0))
                            .rounded(px(12.0))
                            .border_1()
                            .border_color(if is_active {
                                accent_border
                            } else {
                                hsla(0.0, 0.0, 0.0, 0.0)
                            })
                            .bg(if is_active {
                                accent_glow
                            } else {
                                hsla(0.0, 0.0, 0.0, 0.0)
                            })
                            .hover(|s| s.bg(hsla(0.0, 0.0, 1.0, 0.06)).cursor_pointer())
                            .on_mouse_down(MouseButton::Left, move |_, _, _| {
                                if let Some(h) = on_launch.as_ref() {
                                    h(exec.clone());
                                }
                            })
                            .on_mouse_move(move |_, _, _| {
                                if let Some(h) = on_select.as_ref() {
                                    h(real_idx);
                                }
                            })
                            // App Icon Badge (28x28)
                            .child(
                                div()
                                    .size(px(28.0))
                                    .rounded(px(8.0))
                                    .mr(px(10.0))
                                    .flex()
                                    .items_center()
                                    .justify_center()
                                    .bg(if is_active {
                                        accent_glow
                                    } else {
                                        hsla(0.0, 0.0, 1.0, 0.07)
                                    })
                                    .border_1()
                                    .border_color(if is_active {
                                        accent_border
                                    } else {
                                        hsla(0.0, 0.0, 1.0, 0.10)
                                    })
                                    .child(Icon::new(icon_name).size(px(15.0)).text_color(
                                        if is_active {
                                            accent
                                        } else {
                                            hsla(0.0, 0.0, 0.85, 1.0)
                                        },
                                    )),
                            )
                            // App Title & Category Subtitle
                            .child(
                                div()
                                    .flex_1()
                                    .flex()
                                    .flex_col()
                                    .justify_center()
                                    .child(
                                        div()
                                            .text_sm()
                                            .font_weight(if is_active {
                                                FontWeight::BOLD
                                            } else {
                                                FontWeight::MEDIUM
                                            })
                                            .text_color(if is_active {
                                                accent
                                            } else {
                                                hsla(0.0, 0.0, 0.92, 1.0)
                                            })
                                            .child(app.name.clone()),
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
                                                .text_color(hsla(220.0 / 360.0, 0.15, 0.65, 0.70))
                                                .child(cat),
                                        )
                                    }),
                            )
                            // Action / Open badge when active
                            .when(is_active, |this| {
                                this.child(
                                    div()
                                        .px(px(8.0))
                                        .py(px(3.0))
                                        .rounded(px(6.0))
                                        .bg(accent)
                                        .text_xs()
                                        .font_weight(FontWeight::BOLD)
                                        .text_color(hsla(0.0, 0.0, 0.05, 1.0))
                                        .child("↵ Open"),
                                )
                            })
                    })),
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
                    .border_color(hsla(0.0, 0.0, 1.0, 0.06))
                    .bg(hsla(220.0 / 360.0, 0.22, 0.06, 0.50))
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
                            )
                            .child(
                                div()
                                    .text_xs()
                                    .text_color(hsla(0.0, 0.0, 0.50, 0.85))
                                    .child("ESC close"),
                            ),
                    ),
            )
    }
}
