//! Tray Satellite Detail Widget
//! Ported directly from `references/capsule/crates/app/src/capsule/widgets/dashboard/details/tray.rs`.

use gpui_kit::assets::IconName;
use gpui_kit::component::Icon;
use gpui_kit::prelude::FluentBuilder;
use gpui_kit::*;
use std::sync::Arc;

pub const WIDTH: f32 = 320.0;
pub const HEIGHT: f32 = 400.0;

#[derive(Clone, Debug)]
pub struct TrayMenuItem {
    pub id: i32,
    pub label: String,
    pub enabled: bool,
    pub visible: bool,
    pub is_separator: bool,
    pub children: Vec<TrayMenuItem>,
}

#[derive(IntoElement)]
pub struct TrayDetailWidget {
    title: String,
    items: Vec<TrayMenuItem>,
    on_activate: Option<Arc<dyn Fn() + Send + Sync>>,
    on_menu_item: Option<Arc<dyn Fn(i32) + Send + Sync>>,
    on_close: Option<Arc<dyn Fn() + Send + Sync>>,
}

impl TrayDetailWidget {
    pub fn new(title: String, items: Vec<TrayMenuItem>) -> Self {
        Self {
            title,
            items,
            on_activate: None,
            on_menu_item: None,
            on_close: None,
        }
    }

    pub fn on_activate(mut self, handler: impl Fn() + Send + Sync + 'static) -> Self {
        self.on_activate = Some(Arc::new(handler));
        self
    }

    pub fn on_menu_item(mut self, handler: impl Fn(i32) + Send + Sync + 'static) -> Self {
        self.on_menu_item = Some(Arc::new(handler));
        self
    }

    pub fn on_close(mut self, handler: impl Fn() + Send + Sync + 'static) -> Self {
        self.on_close = Some(Arc::new(handler));
        self
    }
}

fn render_entry(
    entry: &TrayMenuItem,
    on_item: &Option<Arc<dyn Fn(i32) + Send + Sync>>,
) -> AnyElement {
    if !entry.visible {
        return div().into_any_element();
    }
    if entry.is_separator {
        return div()
            .h(px(1.0))
            .w_full()
            .my(px(4.0))
            .bg(beskar_theme::Theme::subtle_border())
            .into_any_element();
    }

    let mut row = div()
        .min_h(px(32.0))
        .px(px(10.0))
        .py(px(6.0))
        .rounded(px(8.0))
        .bg(beskar_theme::Theme::glass_fill(0.04))
        .opacity(if entry.enabled { 1.0 } else { 0.4 })
        .text_xs()
        .text_color(beskar_theme::Theme::fg())
        .child(entry.label.replace('_', ""));

    if entry.enabled {
        let id = entry.id;
        let on_click = on_item.clone();
        row = row
            .cursor_pointer()
            .hover(|s| s.bg(beskar_theme::Theme::bg_secondary()))
            .when_some(on_click, move |el, cb| {
                el.on_mouse_down(MouseButton::Left, move |_, _, _| (cb)(id))
            });
    }

    if !entry.children.is_empty() {
        let mut group = div().flex().flex_col().gap(px(2.0)).child(row);
        for child in &entry.children {
            group = group.child(div().pl(px(12.0)).child(render_entry(child, on_item)));
        }
        group.into_any_element()
    } else {
        row.into_any_element()
    }
}

impl RenderOnce for TrayDetailWidget {
    fn render(self, _window: &mut Window, _cx: &mut App) -> impl IntoElement {
        let on_act = self.on_activate;
        let on_cls = self.on_close;
        let on_item = self.on_menu_item;

        let mut list = div()
            .id("tray-menu-scroll-list")
            .flex_1()
            .flex()
            .flex_col()
            .gap(px(4.0))
            .overflow_y_scroll();

        if self.items.is_empty() {
            list = list.child(
                div()
                    .py(px(16.0))
                    .flex()
                    .items_center()
                    .justify_center()
                    .text_xs()
                    .text_color(beskar_theme::Theme::text_secondary())
                    .child("No menu items available"),
            );
        } else {
            for entry in &self.items {
                list = list.child(render_entry(entry, &on_item));
            }
        }

        div()
            .w(px(WIDTH))
            .h(px(HEIGHT))
            .flex()
            .flex_col()
            .p(px(16.0))
            .gap(px(10.0))
            .rounded(px(16.0))
            .bg(beskar_theme::Theme::bg_secondary())
            .border_1()
            .border_color(beskar_theme::Theme::subtle_border())
            .overflow_hidden()
            .child(
                div()
                    .h(px(28.0))
                    .flex_shrink_0()
                    .flex()
                    .items_center()
                    .justify_between()
                    .child(
                        div()
                            .flex()
                            .items_center()
                            .gap(px(8.0))
                            .child(
                                Icon::new(IconName::LayoutGrid)
                                    .size(px(16.0))
                                    .text_color(beskar_theme::Theme::accent()),
                            )
                            .child(
                                div()
                                    .text_size(px(13.0))
                                    .font_weight(FontWeight::MEDIUM)
                                    .child(self.title),
                            ),
                    )
                    .when_some(on_cls, |parent, cb| {
                        parent.child(
                            div()
                                .size(px(24.0))
                                .flex()
                                .items_center()
                                .justify_center()
                                .rounded_full()
                                .cursor_pointer()
                                .hover(|s| s.bg(beskar_theme::Theme::bg()))
                                .on_mouse_down(MouseButton::Left, move |_, _, _| (cb)())
                                .child(Icon::new(IconName::X).size(px(14.0))),
                        )
                    }),
            )
            .when_some(on_act, |parent, cb| {
                parent.child(
                    div()
                        .p(px(8.0))
                        .rounded(px(8.0))
                        .flex()
                        .items_center()
                        .justify_center()
                        .bg(beskar_theme::Theme::glass_fill(0.04))
                        .cursor_pointer()
                        .hover(|s| s.bg(beskar_theme::Theme::bg_secondary()))
                        .on_mouse_down(MouseButton::Left, move |_, _, _| (cb)())
                        .child(
                            div()
                                .text_xs()
                                .font_weight(FontWeight::MEDIUM)
                                .text_color(beskar_theme::Theme::accent())
                                .child("Activate Window"),
                        ),
                )
            })
            .child(list)
    }
}
