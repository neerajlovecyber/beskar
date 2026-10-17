use super::model::ClipboardTab;
use super::ClipboardView;
use beskar_theme::Theme;
use beskar_ui::components::Input;
use beskar_ui::widgets::style;
use gpui_kit::gpui::{
    AnyElement, Context, IntoElement, StyledImage, div, img,
    prelude::*, px, svg,
};

pub const WIDTH: f32 = 480.0;
pub const COLUMNS: usize = 2;
pub const CARD_HEIGHT: f32 = 144.0;
pub const GRID_GAP: f32 = 10.0;
pub const PADDING: f32 = 16.0;
pub const GAP: f32 = 10.0;
pub const HEADER_HEIGHT: f32 = 40.0;
pub const TABS_HEIGHT: f32 = 28.0;
pub const FOOTER_HEIGHT: f32 = 18.0;
pub const BASE_HEIGHT: f32 =
    PADDING * 2.0 + HEADER_HEIGHT + TABS_HEIGHT + FOOTER_HEIGHT + GAP * 3.0;
pub const MAX_HEIGHT: f32 = BASE_HEIGHT + CARD_HEIGHT * 2.0 + GRID_GAP;
pub const CARD_WIDTH: f32 = (WIDTH - PADDING * 2.0 - GRID_GAP) / COLUMNS as f32;

#[derive(Clone, Copy)]
enum ItemAction {
    Pin(usize),
    Remove(usize),
    Clear,
}

fn action(
    id: String,
    icon: &'static str,
    enabled: bool,
    highlighted: bool,
    cx: &mut Context<ClipboardView>,
    action: ItemAction,
) -> gpui_kit::gpui::Stateful<gpui_kit::gpui::Div> {
    let hover = style::hover();
    div()
        .id(id)
        .size(px(26.0))
        .flex_shrink_0()
        .flex()
        .items_center()
        .justify_center()
        .rounded_full()
        .opacity(if enabled { 1.0 } else { 0.3 })
        .when(enabled, |s| {
            s.cursor_pointer()
                .hover(move |s| s.bg(hover))
                .on_click(cx.listener(move |module, _, _, cx| {
                    cx.stop_propagation();
                    match action {
                        ItemAction::Pin(index) => module.pin(index, cx),
                        ItemAction::Remove(index) => module.remove(index, cx),
                        ItemAction::Clear => module.clear(cx),
                    }
                }))
        })
        .child(svg().path(icon).size(px(13.0)).text_color(if highlighted {
            Theme::accent()
        } else {
            Theme::muted()
        }))
}

pub fn render(
    module: &ClipboardView,
    cx: &mut Context<ClipboardView>,
) -> gpui_kit::gpui::Stateful<gpui_kit::gpui::Div> {
    let preview_radius = px(style::INNER_RADIUS - 2.0);
    let hover = style::hover();
    let mut header = div()
        .h(px(HEADER_HEIGHT))
        .flex_shrink_0()
        .flex()
        .items_center()
        .gap(px(8.0));
    let mut tabs = div()
        .h(px(TABS_HEIGHT))
        .flex_shrink_0()
        .flex()
        .items_center()
        .gap(px(8.0));
    for (tab, id, label) in [
        (
            ClipboardTab::History,
            "clipboard-history-tab",
            "History",
        ),
        (
            ClipboardTab::Snippets,
            "clipboard-snippets-tab",
            "Snippets",
        ),
    ] {
        let active = module.model.tab == tab;
        tabs = tabs.child(
            div()
                .id(id)
                .h(px(TABS_HEIGHT))
                .px(px(8.0))
                .rounded_full()
                .flex()
                .items_center()
                .cursor_pointer()
                .bg(if active {
                    Theme::accent()
                } else {
                    style::surface()
                })
                .text_color(if active {
                    style::on_accent()
                } else {
                    Theme::muted()
                })
                .on_click(cx.listener(move |module, _, _, cx| module.switch_tab(tab, cx)))
                .child(div().text_size(px(12.0)).child(label)),
        );
    }
    let actions = div()
        .flex_shrink_0()
        .flex()
        .items_center()
        .gap(px(8.0))
        .when(module.model.tab == ClipboardTab::History, |s| {
            s.child(action(
                "clipboard-clear".into(),
                "trash.svg",
                !module.busy && !module.model.items.is_empty(),
                false,
                cx,
                ItemAction::Clear,
            ))
        })
        .child(
            div()
                .id("clipboard-close")
                .size(px(26.0))
                .flex_shrink_0()
                .flex()
                .items_center()
                .justify_center()
                .rounded_full()
                .bg(style::surface())
                .cursor_pointer()
                .hover(move |s| s.bg(hover))
                .on_click(cx.listener(|_, _, _, cx| {
                    crate::panel_host::PanelHost::close(cx);
                }))
                .child(
                    svg()
                        .path("close.svg")
                        .size(px(13.0))
                        .text_color(Theme::muted()),
                ),
        );
    let search = Input::from_state("clipboard-search", &module.search_input)
        .placeholder("Search clipboard...")
        .cleanable(true)
        .h_px(HEADER_HEIGHT)
        .w_full()
        .rounded_full()
        .bg(style::surface())
        .border_color(style::border())
        .focused_border_color(Theme::accent())
        .prefix(
            svg()
                .path("search.svg")
                .size(px(14.0))
                .text_color(Theme::muted()),
        )
        .on_clear(cx.listener(|this, _, _, cx| {
            this.search_input.clear();
            this.search(String::new(), cx);
        }));
    header = header.child(search).child(actions);
    let mut gallery = div()
        .id("clipboard-gallery")
        .w_full()
        .flex_1()
        .min_h_0()
        .flex()
        .flex_col()
        .gap(px(GRID_GAP))
        .overflow_y_scroll()
        .track_scroll(&module.scroll);
    if module.model.filtered.is_empty() {
        gallery = gallery.items_center().justify_center().child(
            div()
                .text_size(px(12.0))
                .text_color(Theme::muted())
                .child(if module.loading {
                    "Loading..."
                } else if !module.model.query.is_empty() {
                    "No results found"
                } else if module.model.tab == ClipboardTab::History {
                    "Clipboard history is empty"
                } else {
                    "No snippets saved"
                }),
        );
    }
    for (row_index, pair) in module.model.filtered.chunks(COLUMNS).enumerate() {
        let mut row = div()
            .id(("clipboard-gallery-row", row_index))
            .w_full()
            .h(px(CARD_HEIGHT))
            .min_h(px(CARD_HEIGHT))
            .flex_shrink_0()
            .flex()
            .justify_center()
            .gap(px(GRID_GAP));
        for (column, &source) in pair.iter().enumerate() {
            let index = row_index * COLUMNS + column;
            let selected = index == module.model.selected;
            let (id, content): (String, AnyElement) = match module.model.tab {
                ClipboardTab::History => {
                    let item = &module.model.items[source];
                    let content = if item.is_image {
                        div()
                            .size_full()
                            .flex()
                            .flex_col()
                            .child(
                                div()
                                    .w(px(CARD_WIDTH - 4.0))
                                    .h(px(104.0))
                                    .flex_shrink_0()
                                    .rounded_tl(preview_radius)
                                    .rounded_tr(preview_radius)
                                    .bg(style::surface())
                                    .flex()
                                    .items_center()
                                    .justify_center()
                                    .when_some(module.images.get(&item.id), |s, image| {
                                        s.child(
                                            img(image.clone())
                                                .w(px(CARD_WIDTH - 4.0))
                                                .h(px(104.0))
                                                .aspect_ratio((CARD_WIDTH - 4.0) / 104.0)
                                                .rounded_tl(preview_radius)
                                                .rounded_tr(preview_radius)
                                                .object_fit(gpui_kit::gpui::ObjectFit::Cover),
                                        )
                                    })
                                    .when(!module.images.contains_key(&item.id), |s| {
                                        s.child(
                                            svg()
                                                .path("wallpaper.svg")
                                                .size(px(24.0))
                                                .text_color(Theme::muted()),
                                        )
                                    }),
                            )
                            .child(
                                div()
                                    .flex_1()
                                    .min_h_0()
                                    .px(px(10.0))
                                    .flex()
                                    .items_center()
                                    .gap(px(6.0))
                                    .child(
                                        svg()
                                            .path("wallpaper.svg")
                                            .size(px(12.0))
                                            .flex_shrink_0()
                                            .text_color(Theme::muted()),
                                    )
                                    .child(
                                        div()
                                            .flex_1()
                                            .min_w_0()
                                            .text_size(px(10.0))
                                            .whitespace_nowrap()
                                            .text_ellipsis()
                                            .child(if item.preview.is_empty() {
                                                "Image".to_string()
                                            } else {
                                                item.preview.clone()
                                            }),
                                    ),
                            )
                    } else {
                        div()
                            .size_full()
                            .p(px(12.0))
                            .flex()
                            .flex_col()
                            .gap(px(8.0))
                            .child(
                                div()
                                    .h(px(22.0))
                                    .flex_shrink_0()
                                    .flex()
                                    .items_center()
                                    .gap(px(6.0))
                                    .child(
                                        svg()
                                            .path("file-text.svg")
                                            .size(px(13.0))
                                            .text_color(Theme::muted()),
                                    )
                                    .child(
                                        div()
                                            .flex_1()
                                            .text_size(px(10.0))
                                            .text_color(Theme::muted())
                                            .child(format!("{:02}", index + 1)),
                                    )
                                    .child(action(
                                        format!("clipboard-pin-{}", item.id),
                                        "pin.svg",
                                        !module.busy,
                                        module.pinned.contains(&item.id),
                                        cx,
                                        ItemAction::Pin(index),
                                    )),
                            )
                            .child(
                                div()
                                    .flex_1()
                                    .min_h_0()
                                    .w_full()
                                    .overflow_hidden()
                                    .text_size(px(13.0))
                                    .line_height(px(19.0))
                                    .child(if item.preview.is_empty() {
                                        "Empty text item".to_string()
                                    } else {
                                        item.preview.clone()
                                    }),
                            )
                    };
                    (
                        format!("clipboard-card-{}", item.id),
                        content.into_any_element(),
                    )
                }
                ClipboardTab::Snippets => {
                    let snippet = &module.model.snippets[source];
                    let content = div()
                        .size_full()
                        .p(px(12.0))
                        .flex()
                        .flex_col()
                        .gap(px(8.0))
                        .child(
                            div()
                                .h(px(22.0))
                                .flex_shrink_0()
                                .flex()
                                .items_center()
                                .gap(px(6.0))
                                .child(
                                    svg()
                                        .path("pin.svg")
                                        .size(px(13.0))
                                        .flex_shrink_0()
                                        .text_color(Theme::accent()),
                                )
                                .child(
                                    div()
                                        .flex_1()
                                        .min_w_0()
                                        .text_size(px(11.0))
                                        .whitespace_nowrap()
                                        .text_ellipsis()
                                        .child(snippet.title.clone()),
                                )
                                .child(action(
                                    format!("clipboard-remove-{}", snippet.id),
                                    "close.svg",
                                    !module.busy,
                                    false,
                                    cx,
                                    ItemAction::Remove(index),
                                )),
                        )
                        .child(
                            div()
                                .flex_1()
                                .min_h_0()
                                .w_full()
                                .overflow_hidden()
                                .text_size(px(13.0))
                                .line_height(px(19.0))
                                .child(snippet.content.clone()),
                        );
                    (
                        format!("clipboard-card-snippet-{}", snippet.id),
                        content.into_any_element(),
                    )
                }
            };
            row = row.child(
                div()
                    .id(id)
                    .w(px(CARD_WIDTH))
                    .h(px(CARD_HEIGHT))
                    .min_h(px(CARD_HEIGHT))
                    .flex_shrink_0()
                    .rounded(px(style::INNER_RADIUS))
                    .overflow_hidden()
                    .border_2()
                    .border_color(if selected {
                        Theme::accent()
                    } else {
                        style::border()
                    })
                    .bg(if selected {
                        style::selected()
                    } else {
                        style::surface()
                    })
                    .when(!module.busy, |s| {
                        s.cursor_pointer()
                            .hover(move |s| s.bg(hover))
                            .on_mouse_move(
                                cx.listener(move |module, _, _, cx| {
                                    module.select(index, false, cx)
                                }),
                            )
                            .on_click(cx.listener(move |module, _, _, cx| module.copy(index, cx)))
                    })
                    .child(content),
            );
        }
        gallery = gallery.child(row);
    }
    let footer = if let Some(error) = &module.error {
        error.clone()
    } else if module.busy {
        "Working...".to_string()
    } else {
        "Enter to copy • Tab to switch • Esc to close".to_string()
    };
    div()
        .id("clipboard-module")
        .size_full()
        .p(px(PADDING))
        .flex()
        .flex_col()
        .gap(px(GAP))
        .rounded_b_none()
        .rounded_t(px(24.0))
        .bg(Theme::bg())
        .border_1()
        .border_b(px(0.0))
        .border_color(Theme::border())
        .font_family(Theme::font_family())
        .text_color(Theme::fg())
        .child(header)
        .child(tabs)
        .child(gallery)
        .child(
            div()
                .h(px(FOOTER_HEIGHT))
                .flex_shrink_0()
                .flex()
                .items_center()
                .justify_between()
                .gap(px(8.0))
                .child(
                    div()
                        .flex_1()
                        .min_w_0()
                        .text_size(px(10.0))
                        .text_ellipsis()
                        .text_color(if module.error.is_some() {
                            Theme::danger()
                        } else {
                            Theme::muted()
                        })
                        .child(footer),
                )
                .child(
                    div()
                        .text_size(px(10.0))
                        .text_color(Theme::muted())
                        .child(module.model.filtered.len().to_string()),
                ),
        )
}

#[cfg(test)]
pub(crate) mod tests {
    use super::*;

    #[test]
    fn two_full_rows_fit_below_the_search_header_and_tabs_and_above_the_footer() {
        let controls = PADDING * 2.0 + HEADER_HEIGHT + TABS_HEIGHT + FOOTER_HEIGHT + GAP * 3.0;
        assert_eq!(controls, BASE_HEIGHT);
        assert_eq!(MAX_HEIGHT - controls, CARD_HEIGHT * 2.0 + GRID_GAP);
        assert_eq!(
            CARD_WIDTH * COLUMNS as f32 + GRID_GAP + PADDING * 2.0,
            WIDTH
        );
        assert_eq!(CARD_HEIGHT - 4.0 - 104.0, 36.0);
    }
}
