use beskar_services::ClipboardEntry;
use beskar_theme::Theme;
use gpui_kit::assets::IconName;
use gpui_kit::component::button::{Button, ButtonVariants};
use gpui_kit::component::tag::Tag;
use gpui_kit::component::Icon;
use gpui_kit::prelude::FluentBuilder;
use gpui_kit::*;

use crate::panel_host::{PanelHost, PanelModule};

/// Dedicated, autonomous View for Clipboard History
pub struct ClipboardView {
    query: String,
    items: Vec<ClipboardEntry>,
    selected_idx: usize,
    focus_handle: FocusHandle,
}

impl PanelModule for ClipboardView {
    const ID: &'static str = "clipboard";

    fn build(cx: &mut Context<Self>) -> Self {
        Self::new(cx)
    }
}

impl ClipboardView {
    pub fn new(cx: &mut Context<Self>) -> Self {
        let focus_handle = cx.focus_handle();

        cx.spawn(async move |this, cx| {
            let items = tokio::task::spawn_blocking(|| {
                beskar_services::ClipboardService::list_history(50)
            })
            .await
            .unwrap_or_default();

            let _ = this.update(cx, |this, cx| {
                this.items = items;
                cx.notify();
            });
        })
        .detach();

        Self {
            query: String::new(),
            items: Vec::new(),
            selected_idx: 0,
            focus_handle,
        }
    }

    pub fn filter_items<'a>(items: &'a [ClipboardEntry], query: &str) -> Vec<&'a ClipboardEntry> {
        let q = query.trim().to_lowercase();
        if q.is_empty() {
            items.iter().collect()
        } else {
            items
                .iter()
                .filter(|item| item.text.to_lowercase().contains(&q))
                .collect()
        }
    }

    pub fn copy_item(&self, id: &str, cx: &mut App) {
        beskar_services::ClipboardService::copy_item(id);
        beskar_services::SoundService::play_volume_change();
        PanelHost::close(cx);
    }

    pub fn delete_item(&mut self, line: &str, cx: &mut Context<Self>) {
        beskar_services::ClipboardService::delete_item(line);
        self.items = beskar_services::ClipboardService::list_history(50);
        self.selected_idx = self.selected_idx.min(self.items.len().saturating_sub(1));
        cx.notify();
    }

    pub fn clear_all(&mut self, cx: &mut Context<Self>) {
        beskar_services::ClipboardService::clear_history();
        self.items.clear();
        self.selected_idx = 0;
        cx.notify();
    }
}

impl Focusable for ClipboardView {
    fn focus_handle(&self, _cx: &App) -> FocusHandle {
        self.focus_handle.clone()
    }
}

impl Render for ClipboardView {
    fn render(&mut self, _window: &mut Window, cx: &mut Context<Self>) -> impl IntoElement {
        let filtered_items = Self::filter_items(&self.items, &self.query);
        let total_count = filtered_items.len();
        let selected_idx = self.selected_idx.min(total_count.saturating_sub(1));

        let bg_color = Theme::bg();
        let border_color = Theme::border();
        let fg_color = Theme::fg();
        let fg_muted = Theme::muted();
        let accent_color = Theme::accent();

        div()
            .id("clipboard-backdrop")
            .size_full()
            .flex()
            .items_center()
            .justify_center()
            .track_focus(&self.focus_handle)
            .key_context("Clipboard")
            .on_mouse_down(MouseButton::Left, move |_, window, _cx| {
                PanelHost::forget(ClipboardView::ID);
                window.remove_window();
            })
            .on_key_down(cx.listener(move |this, event: &KeyDownEvent, _window, cx| {
                let key = &event.keystroke.key;
                let filtered = Self::filter_items(&this.items, &this.query);
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
                    if let Some(item) = filtered.get(this.selected_idx) {
                        let id = item.id.clone();
                        this.copy_item(&id, cx);
                    }
                    cx.stop_propagation();
                } else if key == "delete" {
                    if let Some(item) = filtered.get(this.selected_idx) {
                        let line = item.full_line.clone();
                        this.delete_item(&line, cx);
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
            .child(
                div()
                    .w(px(640.0))
                    .h(px(480.0))
                    .bg(bg_color)
                    .border_1()
                    .border_color(border_color)
                    .rounded(px(18.0))
                    .shadow_xl()
                    .flex()
                    .flex_col()
                    .overflow_hidden()
                    .on_mouse_down(MouseButton::Left, |_, _, cx| {
                        cx.stop_propagation();
                    })
                    // Search & Header
                    .child(
                        div()
                            .h(px(56.0))
                            .px(px(16.0))
                            .border_b_1()
                            .border_color(border_color)
                            .flex()
                            .items_center()
                            .gap(px(12.0))
                            .child(
                                Icon::new(IconName::ClipboardList)
                                    .size(px(18.0))
                                    .text_color(accent_color),
                            )
                            .child(
                                div()
                                    .flex_1()
                                    .text_sm()
                                    .text_color(if self.query.is_empty() {
                                        fg_muted
                                    } else {
                                        fg_color
                                    })
                                    .child(if self.query.is_empty() {
                                        "Search clipboard history... (Type to filter)".to_string()
                                    } else {
                                        self.query.clone()
                                    }),
                            )
                            .when(!self.query.is_empty(), |this| {
                                this.child(
                                    Button::new("clip-clear-query")
                                        .ghost()
                                        .compact()
                                        .label("Clear")
                                        .on_click(cx.listener(|this, _, _, cx| {
                                            this.query.clear();
                                            this.selected_idx = 0;
                                            cx.notify();
                                        })),
                                )
                            })
                            .child(
                                Button::new("clip-close")
                                    .ghost()
                                    .compact()
                                    .icon(Icon::new(IconName::X).size(px(14.0)))
                                    .on_click(cx.listener(|_, _, _, cx| {
                                        PanelHost::close(cx);
                                    })),
                            ),
                    )
                    // Items List
                    .child(
                        div()
                            .id("clipboard-history-list")
                            .flex_1()
                            .overflow_y_scroll()
                            .p(px(8.0))
                            .pb(px(16.0))
                            .flex()
                            .flex_col()
                            .gap(px(4.0))
                            .when(total_count == 0, |this| {
                                this.child(
                                    div()
                                        .size_full()
                                        .flex()
                                        .flex_col()
                                        .items_center()
                                        .justify_center()
                                        .gap(px(8.0))
                                        .child(
                                            Icon::new(IconName::Clipboard)
                                                .size(px(32.0))
                                                .text_color(fg_muted),
                                        )
                                        .child(
                                            div()
                                                .text_sm()
                                                .text_color(fg_muted)
                                                .child("No clipboard entries found"),
                                        ),
                                )
                            })
                            .children(filtered_items.into_iter().enumerate().map(|(idx, item)| {
                                let is_selected = idx == selected_idx;
                                let item_id = item.id.clone();
                                let full_line = item.full_line.clone();

                                div()
                                    .h(px(46.0))
                                    .px(px(12.0))
                                    .rounded_lg()
                                    .flex()
                                    .items_center()
                                    .gap(px(10.0))
                                    .bg(if is_selected {
                                        beskar_theme::Theme::card_border()
                                    } else {
                                        gpui_kit::transparent_black()
                                    })
                                    .border_1()
                                    .border_color(if is_selected {
                                        accent_color
                                    } else {
                                        beskar_theme::Theme::subtle_border()
                                    })
                                    .hover(|s| s.bg(beskar_theme::Theme::bg_secondary()).cursor_pointer())
                                    .on_mouse_down(MouseButton::Left, cx.listener({
                                        let item_id = item_id.clone();
                                        move |this, _, _, cx| {
                                            this.selected_idx = idx;
                                            this.copy_item(&item_id, cx);
                                        }
                                    }))
                                    .child(Tag::secondary().child(format!("#{}", idx + 1)))
                                    .child(
                                        Icon::new(if item.is_image {
                                            IconName::Image
                                        } else {
                                            IconName::FileText
                                        })
                                        .size(px(14.0))
                                        .text_color(if is_selected {
                                            accent_color
                                        } else {
                                            fg_muted
                                        }),
                                    )
                                    .child(
                                        div()
                                            .flex_1()
                                            .overflow_hidden()
                                            .text_sm()
                                            .text_color(fg_color)
                                            .child(if item.text.len() > 80 {
                                                format!("{}...", &item.text[..80])
                                            } else {
                                                item.text.clone()
                                            }),
                                    )
                                    .child(
                                        Button::new(("clip-copy", idx))
                                            .ghost()
                                            .compact()
                                            .icon(Icon::new(IconName::Copy).size(px(14.0)))
                                            .on_click(cx.listener({
                                                let item_id = item_id.clone();
                                                move |this, _, _, cx| {
                                                    this.copy_item(&item_id, cx);
                                                }
                                            })),
                                    )
                                    .child(
                                        Button::new(("clip-del", idx))
                                            .danger()
                                            .ghost()
                                            .compact()
                                            .icon(Icon::new(IconName::Trash).size(px(14.0)))
                                            .on_click(cx.listener({
                                                let full_line = full_line.clone();
                                                move |this, _, _, cx| {
                                                    this.delete_item(&full_line, cx);
                                                }
                                            })),
                                    )
                            })),
                    )
                    // Footer
                    .child(
                        div()
                            .h(px(42.0))
                            .px(px(16.0))
                            .border_t_1()
                            .border_color(border_color)
                            .bg(beskar_theme::Theme::glass_dark(0.20))
                            .flex()
                            .items_center()
                            .justify_between()
                            .child(
                                div()
                                    .flex()
                                    .items_center()
                                    .gap(px(8.0))
                                    .child(
                                        div()
                                            .text_xs()
                                            .text_color(fg_muted)
                                            .child(format!("{} items", total_count)),
                                    )
                                    .child(div().w(px(3.0)).h(px(3.0)).rounded_full().bg(fg_muted))
                                    .child(
                                        div()
                                            .text_xs()
                                            .text_color(fg_muted)
                                            .child("↑↓ Navigate · Enter Copy · Del Delete · Esc Close"),
                                    ),
                            )
                            .child(
                                Button::new("clip-clear-all")
                                    .danger()
                                    .compact()
                                    .icon(Icon::new(IconName::Trash).size(px(12.0)))
                                    .label("Clear All")
                                    .on_click(cx.listener(|this, _, _, cx| {
                                        this.clear_all(cx);
                                    })),
                            ),
                    ),
            )
    }
}
