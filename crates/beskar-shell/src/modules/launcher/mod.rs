pub mod calc;
pub mod items;

use std::path::PathBuf;
use beskar_core::models::AppItem;
use beskar_services::ClipboardService;
use beskar_theme::Theme;
use gpui_kit::assets::IconName;
use gpui_kit::component::button::{Button, ButtonVariants};
use gpui_kit::component::tag::Tag;
use gpui_kit::component::Icon;
use gpui_kit::prelude::FluentBuilder;
use gpui_kit::*;

use crate::panel_host::{KeyboardInteractivity, PanelEdge, PanelHost, PanelModule, Slot};
use items::{search_unified, LauncherCategory, LauncherResult};

/// Unified Bottom Floating Launcher (Spotlight / Omni-Bar)
pub struct LauncherView {
    query: String,
    selected_idx: usize,
    category: LauncherCategory,
    apps: Vec<AppItem>,
    focus_handle: FocusHandle,
}

impl PanelModule for LauncherView {
    const ID: &'static str = "launcher";

    fn slot() -> Slot {
        Slot::Focus
    }

    fn panel_edge() -> PanelEdge {
        PanelEdge::Bottom
    }

    fn size() -> Size<Pixels> {
        Size::new(px(680.0), px(460.0))
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
            category: LauncherCategory::All,
            apps,
            focus_handle,
        }
    }

    pub fn execute_item(&self, item: &LauncherResult, cx: &mut App) {
        match item {
            LauncherResult::Calculation { formatted, .. } => {
                ClipboardService::new().copy_text(formatted);
                PanelHost::close(cx);
            }
            LauncherResult::App(app) => {
                let _ = beskar_services::launch_app(&app.exec);
                PanelHost::close(cx);
            }
            LauncherResult::Setting(_) => {
                PanelHost::close(cx);
                crate::modules::toggle_settings(cx);
            }
            LauncherResult::Power(action) => {
                let cmd = action.default_command();
                let is_lock = *action == crate::modules::power_menu::PowerAction::Lock;
                PanelHost::close(cx);
                if is_lock {
                    crate::modules::toggle_lockscreen(cx);
                } else {
                    let parts: Vec<String> = cmd.split_whitespace().map(|s| s.to_string()).collect();
                    if let Some((exe, args)) = parts.split_first() {
                        let _ = std::process::Command::new(exe).args(args).spawn();
                    }
                }
            }
        }
    }
}

impl Focusable for LauncherView {
    fn focus_handle(&self, _cx: &App) -> FocusHandle {
        self.focus_handle.clone()
    }
}

impl Render for LauncherView {
    fn render(&mut self, _window: &mut Window, cx: &mut Context<Self>) -> impl IntoElement {
        let results = search_unified(&self.apps, &self.query, self.category);
        let total_count = results.len();
        let selected_idx = self.selected_idx.min(total_count.saturating_sub(1));

        let theme_bg = Theme::bg();
        let theme_fg = Theme::fg();
        let theme_accent = Theme::accent();
        let theme_muted = Theme::muted();
        let theme_border = Theme::border();
        let theme_bg_secondary = Theme::bg_secondary();
        let current_category = self.category;

        div()
            .id("launcher-unified-card")
            .w(px(680.0))
            .max_h(px(460.0))
            .flex()
            .flex_col()
            .p(px(14.0))
            .rounded_b_none()
            .rounded_t(px(24.0))
            .bg(theme_bg)
            .border_1()
            .border_b(px(0.0))
            .border_color(theme_border)
            .shadow_2xl()
            .overflow_hidden()
            .gap(px(10.0))
            .track_focus(&self.focus_handle)
            .key_context("UnifiedLauncher")
            .on_key_down(cx.listener(move |this, event: &KeyDownEvent, _window, cx| {
                let key = &event.keystroke.key;
                let active_results = search_unified(&this.apps, &this.query, this.category);
                let count = active_results.len();

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
                } else if key == "tab" {
                    let cats = LauncherCategory::ALL;
                    let current_pos = cats.iter().position(|&c| c == this.category).unwrap_or(0);
                    let next_pos = (current_pos + 1) % cats.len();
                    this.category = cats[next_pos];
                    this.selected_idx = 0;
                    cx.notify();
                    cx.stop_propagation();
                } else if key == "enter" {
                    if let Some(item) = active_results.get(this.selected_idx) {
                        this.execute_item(item, cx);
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
            // Top Search Input Box
            .child(
                div()
                    .w_full()
                    .h(px(42.0))
                    .flex()
                    .items_center()
                    .px(px(14.0))
                    .rounded(px(14.0))
                    .bg(theme_bg_secondary)
                    .border_1()
                    .border_color(beskar_theme::Theme::subtle_border())
                    .gap(px(10.0))
                    .child(
                        Icon::new(IconName::Search)
                            .size(px(16.0))
                            .text_color(theme_accent),
                    )
                    .child(
                        div().flex_1().flex().items_center().child(
                            if self.query.is_empty() {
                                div()
                                    .text_sm()
                                    .font_weight(FontWeight::NORMAL)
                                    .text_color(theme_muted)
                                    .child("Search apps, settings, calculate (25 * 4), or power...")
                            } else {
                                div()
                                    .text_sm()
                                    .font_weight(FontWeight::SEMIBOLD)
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
                    })
                    .child(
                        div()
                            .text_xs()
                            .px(px(6.0))
                            .py(px(2.0))
                            .rounded_md()
                            .bg(beskar_theme::Theme::bg())
                            .text_color(theme_muted)
                            .child("ESC"),
                    ),
            )
            // Category Filter Chips
            .child(
                div()
                    .w_full()
                    .flex()
                    .items_center()
                    .gap(px(6.0))
                    .py(px(2.0))
                    .children(LauncherCategory::ALL.into_iter().enumerate().map(|(idx, cat)| {
                        let is_active = cat == current_category;
                        div()
                            .id(("cat-chip", idx))
                            .flex()
                            .items_center()
                            .gap(px(5.0))
                            .px(px(10.0))
                            .py(px(3.0))
                            .rounded_full()
                            .cursor_pointer()
                            .bg(if is_active {
                                theme_accent
                            } else {
                                theme_bg_secondary
                            })
                            .text_color(if is_active {
                                gpui_kit::white()
                            } else {
                                theme_muted
                            })
                            .hover(move |s| {
                                if !is_active {
                                    s.bg(beskar_theme::Theme::subtle_border())
                                        .text_color(theme_fg)
                                } else {
                                    s
                                }
                            })
                            .on_mouse_down(MouseButton::Left, cx.listener(move |this, _, _, cx| {
                                this.category = cat;
                                this.selected_idx = 0;
                                cx.notify();
                            }))
                            .child(
                                Icon::new(cat.icon())
                                    .size(px(12.0))
                                    .text_color(if is_active {
                                        gpui_kit::white()
                                    } else {
                                        theme_muted
                                    }),
                            )
                            .child(
                                div()
                                    .text_xs()
                                    .font_weight(if is_active {
                                        FontWeight::BOLD
                                    } else {
                                        FontWeight::MEDIUM
                                    })
                                    .child(cat.label()),
                            )
                    })),
            )
            // Results List
            .child(
                div()
                    .id("launcher-results-list")
                    .w_full()
                    .max_h(px(340.0))
                    .overflow_y_scroll()
                    .flex()
                    .flex_col()
                    .gap(px(4.0))
                    .pb(px(4.0))
                    .pr(px(2.0))
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
                                        .child("No results found"),
                                ),
                        )
                    })
                    .children(results.into_iter().enumerate().map(|(i, item)| {
                        let is_current = i == selected_idx;
                        let icon_name = item.icon();
                        let title = item.title();
                        let subtitle = item.subtitle();
                        let cat = item.category();
                        let item_clone = item.clone();
                        let icon_path = item.icon_path().map(PathBuf::from);

                        div()
                            .id(("res-item", i))
                            .w_full()
                            .h(px(46.0))
                            .flex()
                            .items_center()
                            .justify_between()
                            .px(px(12.0))
                            .rounded(px(12.0))
                            .bg(if is_current {
                                theme_bg_secondary
                            } else {
                                gpui_kit::transparent_black()
                            })
                            .border_1()
                            .border_color(if is_current {
                                beskar_theme::Theme::accent_alpha(0.30)
                            } else {
                                gpui_kit::transparent_black()
                            })
                            .hover(move |s| {
                                s.bg(theme_bg_secondary).cursor_pointer()
                            })
                            .on_mouse_down(MouseButton::Left, cx.listener({
                                let item_to_exec = item_clone;
                                move |this, _, _, cx| {
                                    this.selected_idx = i;
                                    this.execute_item(&item_to_exec, cx);
                                }
                            }))
                            .child(
                                div()
                                    .flex()
                                    .items_center()
                                    .gap(px(12.0))
                                    .child(
                                        div()
                                            .size(px(28.0))
                                            .rounded(px(8.0))
                                            .flex()
                                            .items_center()
                                            .justify_center()
                                            .bg(if is_current {
                                                beskar_theme::Theme::accent_alpha(0.20)
                                            } else {
                                                beskar_theme::Theme::bg_secondary()
                                            })
                                            .child(
                                                if let Some(path) = icon_path {
                                                    img(path)
                                                        .size(px(20.0))
                                                        .rounded(px(4.0))
                                                        .into_any_element()
                                                } else {
                                                    Icon::new(icon_name)
                                                        .size(px(16.0))
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
                                            .flex()
                                            .flex_col()
                                            .child(
                                                div()
                                                    .text_sm()
                                                    .font_weight(if is_current {
                                                        FontWeight::BOLD
                                                    } else {
                                                        FontWeight::MEDIUM
                                                    })
                                                    .text_color(if is_current {
                                                        theme_accent
                                                    } else {
                                                        theme_fg
                                                    })
                                                    .child(title),
                                            )
                                            .child(
                                                div()
                                                    .text_xs()
                                                    .text_color(theme_muted)
                                                    .max_w(px(380.0))
                                                    .overflow_hidden()
                                                    .child(subtitle),
                                            ),
                                    ),
                            )
                            .child(
                                div()
                                    .flex()
                                    .items_center()
                                    .gap(px(6.0))
                                    .child(Tag::secondary().child(cat.label()))
                                    .when(is_current, |this| {
                                        this.child(
                                            div()
                                                .text_xs()
                                                .text_color(theme_accent)
                                                .font_weight(FontWeight::BOLD)
                                                .child("↵"),
                                        )
                                    }),
                            )
                    })),
            )
    }
}
