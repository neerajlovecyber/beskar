use std::path::{Path, PathBuf};
use beskar_core::models::AppItem;
use beskar_theme::Theme;
use gpui_kit::assets::IconName;
use gpui_kit::component::button::{Button, ButtonVariants};
use gpui_kit::component::tag::Tag;
use gpui_kit::component::Icon;
use gpui_kit::prelude::FluentBuilder;
use gpui_kit::*;

use crate::panel_host::{KeyboardInteractivity, LayerAnchor, PanelHost, PanelModule};

/// Dedicated, autonomous View for the App Launcher
pub struct LauncherView {
    query: String,
    selected_idx: usize,
    apps: Vec<AppItem>,
    focus_handle: FocusHandle,
}

impl PanelModule for LauncherView {
    const ID: &'static str = "launcher";

    fn size() -> Size<Pixels> {
        Size::new(px(700.0), px(520.0))
    }

    fn anchor() -> LayerAnchor {
        LayerAnchor::TOP
    }

    fn margin() -> (Pixels, Pixels, Pixels, Pixels) {
        (px(90.0), px(0.0), px(0.0), px(0.0))
    }

    fn keyboard_interactivity() -> KeyboardInteractivity {
        KeyboardInteractivity::Exclusive
    }

    fn build(cx: &mut Context<Self>) -> Self {
        Self::new(cx)
    }
}

impl LauncherView {
    pub fn new(cx: &mut Context<Self>) -> Self {
        let apps = beskar_services::list_apps();
        let focus_handle = cx.focus_handle();

        Self {
            query: String::new(),
            selected_idx: 0,
            apps,
            focus_handle,
        }
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

    pub fn launch(&self, cmd: &str, cx: &mut App) {
        let _ = beskar_services::launch_app(cmd);
        PanelHost::close(cx);
    }
}

impl Focusable for LauncherView {
    fn focus_handle(&self, _cx: &App) -> FocusHandle {
        self.focus_handle.clone()
    }
}

impl Render for LauncherView {
    fn render(&mut self, _window: &mut Window, cx: &mut Context<Self>) -> impl IntoElement {
        let filtered_apps = Self::filter_and_rank(&self.apps, &self.query);
        let total_count = filtered_apps.len();
        let selected_idx = self.selected_idx.min(total_count.saturating_sub(1));

        let theme_bg = Theme::bg();
        let theme_fg = Theme::fg();
        let theme_accent = Theme::accent();
        let theme_muted = Theme::muted();
        let theme_border = Theme::border();
        let theme_bg_secondary = Theme::bg_secondary();

        div()
            .id("launcher-card")
            .w(px(700.0))
            .max_h(px(520.0))
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
            .track_focus(&self.focus_handle)
            .key_context("Launcher")
            .on_key_down(cx.listener(move |this, event: &KeyDownEvent, _window, cx| {
                let key = &event.keystroke.key;
                let filtered = Self::filter_and_rank(&this.apps, &this.query);
                let count = filtered.len();

                if key == "escape" {
                    PanelHost::close(cx);
                    cx.stop_propagation();
                } else if key == "down" {
                    if count > 0 {
                        this.selected_idx = (this.selected_idx + 1).min(count - 1);
                        cx.notify();
                    }
                    cx.stop_propagation();
                } else if key == "up" {
                    if this.selected_idx > 0 {
                        this.selected_idx -= 1;
                        cx.notify();
                    }
                    cx.stop_propagation();
                } else if key == "enter" {
                    if let Some(app) = filtered.get(this.selected_idx) {
                        this.launch(&app.exec, cx);
                    }
                    cx.stop_propagation();
                } else if key == "backspace" {
                    this.query.pop();
                    this.selected_idx = 0;
                    cx.notify();
                    cx.stop_propagation();
                } else if let Some(ch) = &event.keystroke.key_char {
                    this.query.push_str(ch.as_ref());
                    this.selected_idx = 0;
                    cx.notify();
                    cx.stop_propagation();
                } else if key.len() == 1 {
                    this.query.push_str(key);
                    this.selected_idx = 0;
                    cx.notify();
                    cx.stop_propagation();
                }
            }))
                    // Search Bar
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
                            .child(
                                Icon::new(IconName::Search)
                                    .size(px(16.0))
                                    .text_color(theme_muted),
                            )
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
                            .when(!self.query.is_empty(), |this| {
                                this.child(
                                    Button::new("launcher-clear")
                                        .ghost()
                                        .compact()
                                        .icon(Icon::new(IconName::X).size(px(14.0)))
                                        .on_click(cx.listener(|this, _, _, cx| {
                                            this.query.clear();
                                            this.selected_idx = 0;
                                            cx.notify();
                                        })),
                                )
                            }),
                    )
                    // Apps List
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
                            .children(filtered_apps.iter().enumerate().map(|(i, app)| {
                                let real_idx = i;
                                let is_current = real_idx == selected_idx;
                                let exec = app.exec.clone();
                                let icon_path_exists = !app.icon.is_empty() && Path::new(&app.icon).exists();
                                let icon_path = PathBuf::from(&app.icon);

                                div()
                                    .w_full()
                                    .h(px(44.0))
                                    .flex()
                                    .items_center()
                                    .px(px(16.0))
                                    .rounded(px(16.0))
                                    .bg(if is_current {
                                        theme_bg_secondary
                                    } else {
                                        gpui_kit::transparent_black()
                                    })
                                    .hover(move |s| {
                                        s.bg(theme_bg_secondary).cursor_pointer()
                                    })
                                    .on_mouse_down(MouseButton::Left, cx.listener({
                                        let exec = exec.clone();
                                        move |this, _, _, cx| {
                                            this.selected_idx = real_idx;
                                            this.launch(&exec, cx);
                                        }
                                    }))
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
