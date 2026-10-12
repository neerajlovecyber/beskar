use beskar_core::models::ClipboardEntry;
use beskar_theme::Theme;
use gpui_kit::assets::IconName;
use gpui_kit::component::button::{Button, ButtonVariants};
use gpui_kit::component::tag::Tag;
use gpui_kit::component::Icon;
use gpui_kit::prelude::FluentBuilder;
use gpui_kit::*;
use std::sync::Arc;

/// Native Clipboard History Widget matching Minflair's `ClipboardContent.qml`.
/// Features:
/// - Real-time fuzzy query filtering
/// - Highlighting selected entry
/// - One-click or Enter key copying via `cliphist decode | wl-copy`
/// - Single item deletion and Clear All history
#[derive(IntoElement)]
pub struct ClipboardWidget {
    query: String,
    items: Vec<ClipboardEntry>,
    selected_idx: usize,
    on_select: Option<Arc<dyn Fn(usize) + Send + Sync>>,
    on_copy: Option<Arc<dyn Fn(String) + Send + Sync>>,
    on_delete: Option<Arc<dyn Fn(String) + Send + Sync>>,
    on_clear_all: Option<Arc<dyn Fn() + Send + Sync>>,
    on_clear_query: Option<Arc<dyn Fn() + Send + Sync>>,
    on_close: Option<Arc<dyn Fn() + Send + Sync>>,
}

impl ClipboardWidget {
    pub fn new(items: Vec<ClipboardEntry>) -> Self {
        Self {
            query: String::new(),
            items,
            selected_idx: 0,
            on_select: None,
            on_copy: None,
            on_delete: None,
            on_clear_all: None,
            on_clear_query: None,
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

    pub fn on_copy(mut self, handler: impl Fn(String) + Send + Sync + 'static) -> Self {
        self.on_copy = Some(Arc::new(handler));
        self
    }

    pub fn on_delete(mut self, handler: impl Fn(String) + Send + Sync + 'static) -> Self {
        self.on_delete = Some(Arc::new(handler));
        self
    }

    pub fn on_clear_all(mut self, handler: impl Fn() + Send + Sync + 'static) -> Self {
        self.on_clear_all = Some(Arc::new(handler));
        self
    }

    pub fn on_clear_query(mut self, handler: impl Fn() + Send + Sync + 'static) -> Self {
        self.on_clear_query = Some(Arc::new(handler));
        self
    }

    pub fn on_close(mut self, handler: impl Fn() + Send + Sync + 'static) -> Self {
        self.on_close = Some(Arc::new(handler));
        self
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
}

impl RenderOnce for ClipboardWidget {
    fn render(self, _window: &mut Window, _cx: &mut App) -> impl IntoElement {
        let filtered_items = Self::filter_items(&self.items, &self.query);
        let total_count = filtered_items.len();
        let selected_idx = self.selected_idx.min(total_count.saturating_sub(1));

        let on_copy = self.on_copy;
        let on_delete = self.on_delete;
        let on_select = self.on_select;
        let on_clear_all = self.on_clear_all;
        let on_clear_query = self.on_clear_query;
        let on_close = self.on_close;

        let bg_color = Theme::bg();
        let border_color = Theme::border();
        let fg_color = Theme::fg();
        let fg_muted = Theme::muted();
        let accent_color = Theme::accent();

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
            // Top Search & Header Bar
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
                        let on_cq = on_clear_query.clone();
                        this.child(
                            Button::new("clip-clear-query")
                                .ghost()
                                .compact()
                                .label("Clear")
                                .when_some(on_cq, |btn, cb| {
                                    btn.on_click(move |_, _, _| (cb)())
                                }),
                        )
                    })
                    .child(
                        Button::new("clip-close")
                            .ghost()
                            .compact()
                            .icon(Icon::new(IconName::X).size(px(14.0)))
                            .when_some(on_close, |btn, cb| {
                                btn.on_click(move |_, _, _| (cb)())
                            }),
                    ),
            )
            // Middle Items List
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

                        let on_sel = on_select.clone();
                        let on_cp = on_copy.clone();
                        let on_del = on_delete.clone();

                        let cp_id = item_id.clone();
                        let del_line = full_line.clone();

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
                            .when_some(on_sel, |el, cb| {
                                el.on_mouse_down(MouseButton::Left, move |_, _, _| (cb)(idx))
                            })
                            // Index badge
                            .child(Tag::secondary().child(format!("#{}", idx + 1)))
                            // Content icon
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
                            // Text Preview
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
                            // Copy Action Button
                            .child(
                                Button::new(("clip-copy", idx))
                                    .ghost()
                                    .compact()
                                    .icon(Icon::new(IconName::Copy).size(px(14.0)))
                                    .when_some(on_cp, |btn, cb| {
                                        btn.on_click(move |_, _, _| (cb)(cp_id.clone()))
                                    }),
                            )
                            // Delete Action Button
                            .child(
                                Button::new(("clip-del", idx))
                                    .danger()
                                    .ghost()
                                    .compact()
                                    .icon(Icon::new(IconName::Trash).size(px(14.0)))
                                    .when_some(on_del, |btn, cb| {
                                        btn.on_click(move |_, _, _| (cb)(del_line.clone()))
                                    }),
                            )
                    })),
            )
            // Footer with Stats and Clear All
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
                    .when_some(on_clear_all, |this, cb| {
                        this.child(
                            Button::new("clip-clear-all")
                                .danger()
                                .compact()
                                .icon(Icon::new(IconName::Trash).size(px(12.0)))
                                .label("Clear All")
                                .on_click(move |_, _, _| (cb)()),
                        )
                    }),
            )
    }
}
