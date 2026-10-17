use std::sync::Mutex;

use beskar_core::models::TrayMenuItem;
use beskar_services::TrayService;
use beskar_theme::Theme;
use gpui_kit::assets::IconName;
use gpui_kit::component::button::{Button, ButtonVariants};
use gpui_kit::component::spinner::Spinner;
use gpui_kit::component::Icon;
use gpui_kit::prelude::FluentBuilder;
use gpui_kit::*;

use crate::panel_host::{LayerAnchor, PanelHost, PanelModule};

static ACTIVE_TRAY_KEY: Mutex<Option<String>> = Mutex::new(None);

/// Open the native D-Bus context menu for the specified tray item key.
pub fn open_tray_menu(key: String, cx: &mut App) {
    if let Ok(mut guard) = ACTIVE_TRAY_KEY.lock() {
        *guard = Some(key);
    }
    PanelHost::open::<TrayMenuView>(cx);
}

pub struct TrayMenuView {
    item_key: String,
    menu_items: Vec<TrayMenuItem>,
    is_loading: bool,
}

impl PanelModule for TrayMenuView {
    const ID: &'static str = "tray_menu";

    fn size() -> Size<Pixels> {
        Size::new(px(240.0), px(380.0))
    }

    fn anchor() -> LayerAnchor {
        LayerAnchor::TOP | LayerAnchor::RIGHT
    }

    fn margin() -> (Pixels, Pixels, Pixels, Pixels) {
        (px(48.0), px(16.0), px(0.0), px(0.0))
    }

    fn build(cx: &mut Context<Self>) -> Self {
        let key = ACTIVE_TRAY_KEY
            .lock()
            .ok()
            .and_then(|g| g.clone())
            .unwrap_or_default();

        let key_for_task = key.clone();
        cx.spawn(async move |this, cx| {
            let items = TrayService::fetch_menu(&key_for_task).await;
            let _ = this.update(cx, |this, cx| {
                this.menu_items = items;
                this.is_loading = false;
                cx.notify();
            });
        })
        .detach();

        Self {
            item_key: key,
            menu_items: Vec::new(),
            is_loading: true,
        }
    }
}

impl TrayMenuView {
    fn render_menu_item(
        &self,
        item: &TrayMenuItem,
        key: &str,
    ) -> impl IntoElement {
        if item.is_separator {
            return div()
                .h(px(1.0))
                .my(px(4.0))
                .bg(Theme::subtle_border())
                .into_any_element();
        }

        let item_id = item.id;
        let key_str = key.to_string();
        let is_enabled = item.enabled;
        let is_checked = item.checked.unwrap_or(false);

        let check_icon = if is_checked {
            Icon::new(IconName::Check)
                .size(px(14.0))
                .text_color(Theme::accent())
                .into_any_element()
        } else {
            div().w(px(14.0)).into_any_element()
        };

        let label = item.label.clone();
        let fg_color = if is_enabled { Theme::fg() } else { Theme::muted() };

        let mut btn = Button::new(SharedString::from(format!("tray-item-{}", item_id)))
            .ghost()
            .compact()
            .w_full()
            .child(
                div()
                    .w_full()
                    .flex()
                    .items_center()
                    .gap(px(8.0))
                    .child(check_icon)
                    .child(
                        div()
                            .flex_1()
                            .text_size(px(13.0))
                            .text_color(fg_color)
                            .child(label),
                    ),
            );

        if is_enabled {
            btn = btn.on_click(move |_, _, cx| {
                let k = key_str.clone();
                tokio::spawn(async move {
                    let _ = TrayService::click_menu_item(&k, item_id).await;
                });
                PanelHost::close(cx);
            });
        }

        btn.into_any_element()
    }
}

impl Render for TrayMenuView {
    fn render(&mut self, _: &mut Window, _: &mut Context<Self>) -> impl IntoElement {
        let key = self.item_key.clone();

        div()
            .id("tray-menu-card")
            .w(px(240.0))
            .max_h(px(380.0))
            .overflow_hidden()
            .p(px(6.0))
            .bg(Theme::card_bg())
            .border_1()
            .border_r(px(0.0))
            .border_color(Theme::card_border())
            .rounded_r_none()
            .rounded_l(px(16.0))
            .shadow_lg()
            .on_key_down(|event, _, cx| {
                if event.keystroke.key == "escape" {
                    PanelHost::close(cx);
                }
            })
            .when(self.is_loading, |this| {
                this.flex()
                    .items_center()
                    .justify_center()
                    .py(px(24.0))
                    .gap(px(8.0))
                    .child(Spinner::new())
                    .child(
                        div()
                            .text_size(px(12.0))
                            .text_color(Theme::muted())
                            .child("Loading menu..."),
                    )
            })
            .when(!self.is_loading && self.menu_items.is_empty(), |this| {
                this.flex()
                    .flex_col()
                    .items_center()
                    .justify_center()
                    .py(px(16.0))
                    .child(
                        div()
                            .text_size(px(12.0))
                            .text_color(Theme::muted())
                            .child("No menu actions available"),
                    )
            })
            .when(!self.is_loading && !self.menu_items.is_empty(), |this| {
                let mut col = div().flex().flex_col().gap(px(2.0));
                for item in &self.menu_items {
                    col = col.child(self.render_menu_item(item, &key));
                }
                this.child(col)
            })
    }
}
