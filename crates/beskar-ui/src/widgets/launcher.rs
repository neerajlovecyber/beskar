use beskar_core::models::AppItem;
use beskar_theme::Theme;
use gpui_kit::assets::IconName;
use gpui_kit::component::button::{Button, ButtonVariants};
use gpui_kit::component::tag::Tag;
use gpui_kit::component::Icon;
use gpui_kit::prelude::FluentBuilder;
use gpui_kit::*;
use std::path::{Path, PathBuf};
use std::sync::Arc;

/// Premium App Launcher Widget ported with 100% fidelity to Minflair:
/// `LauncherContent.qml`, `LauncherItemDelegate.qml`, `ThemedSearchBar.qml`, and `FloatingOverlayStyle.qml`.
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

    /// Pure filtering and ranking function matching Minflair filterApps mechanics.
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

impl RenderOnce for LauncherWidget {
    fn render(self, _window: &mut Window, _cx: &mut App) -> impl IntoElement {
        let filtered_apps = Self::filter_and_rank(&self.apps, &self.query);
        let total_count = filtered_apps.len();
        let selected_idx = self.selected_idx.min(total_count.saturating_sub(1));

        let on_select = self.on_select.clone();
        let on_launch = self.on_launch.clone();
        let on_clear = self.on_clear.clone();

        // Exact Minflair theme tokens
        let theme_bg = Theme::bg();
        let theme_fg = Theme::fg();
        let theme_accent = Theme::accent();
        let theme_muted = Theme::muted();
        let theme_border = Theme::border();
        let theme_bg_secondary = Theme::bg_secondary();

        // Minflair FloatingOverlayStyle container:
        // preferredWidth = 700px, windowRadius = 32px (size3Xl), contentPadding = 16px (sizeLg)
        div()
            .w(px(700.0))
            .flex()
            .flex_col()
            .p(px(16.0))
            .rounded(px(32.0))
            .bg(theme_bg)
            .border_1()
            .border_color(theme_border)
            .shadow_2xl()
            .overflow_hidden()
            .gap(px(12.0))
            // ThemedSearchBar (Constants.size4Xl = 40px height, sizeMd = 14px radius)
            .child(
                div()
                    .w_full()
                    .h(px(40.0))
                    .flex()
                    .items_center()
                    .px(px(16.0))
                    .rounded(px(14.0))
                    .bg(theme_bg_secondary)
                    .gap(px(12.0))
                    // Search icon (Theme.muted)
                    .child(
                        Icon::new(IconName::Search)
                            .size(px(16.0))
                            .text_color(theme_muted),
                    )
                    // Search input text / placeholder
                    .child(
                        div().flex_1().flex().items_center().child(
                            if self.query.is_empty() {
                                div()
                                    .text_sm()
                                    .font_weight(FontWeight::NORMAL)
                                    .text_color(theme_muted)
                                    .child("Search applications...")
                            } else {
                                div()
                                    .text_sm()
                                    .font_weight(FontWeight::NORMAL)
                                    .text_color(theme_fg)
                                    .child(self.query.clone())
                            },
                        ),
                    )
                    // Clear button (Theme.muted "x")
                    .when(!self.query.is_empty(), |this| {
                        let on_clear = on_clear.clone();
                        this.child(
                            Button::new("launcher-clear")
                                .ghost()
                                .compact()
                                .icon(Icon::new(IconName::X).size(px(14.0)))
                                .when_some(on_clear, |btn, cb| {
                                    btn.on_click(move |_, _, _| (cb)())
                                }),
                        )
                    }),
            )
            // Applications ListView (minflair listSpacing = 8px)
            .child(
                div()
                    .id("launcher-apps-list")
                    .w_full()
                    .max_h(px(460.0))
                    .overflow_y_scroll()
                    .flex()
                    .flex_col()
                    .gap(px(6.0))
                    .pb(px(8.0))
                    .pr(px(4.0))
                    // GhostEmptyState
                    .when(total_count == 0, |this| {
                        this.child(
                            div()
                                .w_full()
                                .py(px(48.0))
                                .flex()
                                .flex_col()
                                .items_center()
                                .justify_center()
                                .gap(px(8.0))
                                .child(
                                    Icon::new(IconName::Search)
                                        .size(px(24.0))
                                        .text_color(theme_muted),
                                )
                                .child(
                                    div()
                                        .text_sm()
                                        .font_weight(FontWeight::NORMAL)
                                        .text_color(theme_muted)
                                        .child("No applications found"),
                                ),
                        )
                    })
                    // LauncherItemDelegate delegates (height = 44px, radius = 16px)
                    .children(filtered_apps.iter().enumerate().map(|(i, app)| {
                        let real_idx = i;
                        let is_current = real_idx == selected_idx;
                        let exec = app.exec.clone();
                        let on_launch = on_launch.clone();
                        let on_select = on_select.clone();

                        let icon_path_exists = !app.icon.is_empty() && Path::new(&app.icon).exists();
                        let icon_path = PathBuf::from(&app.icon);

                        div()
                            .w_full()
                            .h(px(44.0))
                            .flex()
                            .items_center()
                            .px(px(16.0))
                            .rounded(px(16.0))
                            // Minflair delegate highlight: Theme.bgSecondary on current or hovered
                            .bg(if is_current {
                                theme_bg_secondary
                            } else {
                                gpui_kit::transparent_black()
                            })
                            .hover(move |s| {
                                s.bg(theme_bg_secondary).cursor_pointer()
                            })
                            .on_mouse_down(MouseButton::Left, move |_, _, _| {
                                if let Some(s) = on_select.as_ref() {
                                    s(real_idx);
                                }
                                if let Some(h) = on_launch.as_ref() {
                                    h(exec.clone());
                                }
                            })
                            // Clean App Icon: 24x24px (Constants.size2Xl) without background box or circles
                            .child(
                                div()
                                    .size(px(24.0))
                                    .mr(px(16.0))
                                    .flex()
                                    .items_center()
                                    .justify_center()
                                    .child(
                                        if icon_path_exists {
                                            img(icon_path)
                                                .size(px(24.0))
                                                .rounded(px(4.0))
                                                .into_any_element()
                                        } else {
                                            Icon::new(IconName::Rocket)
                                                .size(px(24.0))
                                                .text_color(if is_current {
                                                    theme_accent
                                                } else {
                                                    theme_muted
                                                })
                                                .into_any_element()
                                        },
                                    ),
                            )
                            // App Name (ThemedText: font.bold when current, accent color when current, else fg)
                            .child(
                                div()
                                    .flex_1()
                                    .text_sm()
                                    .font_weight(if is_current {
                                        FontWeight::BOLD
                                    } else {
                                        FontWeight::NORMAL
                                    })
                                    .text_color(if is_current {
                                        theme_accent
                                    } else {
                                        theme_fg
                                    })
                                    .child(app.name.clone()),
                            )
                            // Category subtle subtitle on right (Theme.muted)
                            .when(!app.categories.is_empty(), |this| {
                                let cat = app
                                    .categories
                                    .split(';')
                                    .find(|c| !c.is_empty())
                                    .unwrap_or("")
                                    .to_string();
                                this.child(Tag::secondary().child(cat))
                            })
                    })),
            )
    }
}
