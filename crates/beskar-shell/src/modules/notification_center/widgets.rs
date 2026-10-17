use super::NotificationCenterView;
use beskar_services::NotificationItem;
use beskar_theme::Theme;
use beskar_ui::components::{Badge, BadgeVariant, Button, ButtonSize, ButtonVariant, Chip, IconButton, Input};
use beskar_ui::widgets::style;
use gpui_kit::gpui::{
    AnyElement, Context, FontWeight, IntoElement, Pixels, Size, WindowTextSystem, div, img,
    prelude::*, px, svg,
};
use std::path::PathBuf;

pub const WIDTH: f32 = 440.0;
pub const HISTORY_HEIGHT: f32 = 400.0;

fn visible_action(key: &str, label: &str, replying: bool) -> bool {
    !key.trim().is_empty()
        && (!label.trim().is_empty() || key == "default" || key == "inline-reply")
        && !(replying && key == "inline-reply")
}

fn action_label(key: &str, label: &str) -> String {
    if !label.trim().is_empty() {
        return label.to_owned();
    }
    if key == "inline-reply" {
        "Reply".to_string()
    } else {
        "Open".to_string()
    }
}

pub fn measure(
    text: &str,
    font_size: f32,
    weight: FontWeight,
    wrap: bool,
    _cx: &gpui_kit::App,
    text_system: &WindowTextSystem,
) -> Size<Pixels> {
    let font_family = Theme::font_family();
    let runs = [gpui_kit::gpui::TextRun {
        len: text.len(),
        font: gpui_kit::gpui::Font {
            weight,
            ..gpui_kit::gpui::font(font_family)
        },
        color: Theme::fg(),
        ..Default::default()
    }];
    text_system
        .shape_text(
            text.to_owned().into(),
            px(font_size),
            &runs,
            wrap.then(|| px(WIDTH - 32.0)),
            wrap.then_some(4),
        )
        .map(|shaped| {
            let line_height = px(if font_size == 15.0 { 21.0 } else { 18.0 });
            let mut total_width = px(0.0);
            let mut total_height = px(0.0);
            for line in shaped {
                let sz = line.size(line_height);
                total_width = total_width.max(sz.width);
                total_height += sz.height;
            }
            if wrap {
                total_height = total_height.min(line_height * 4.0);
            }
            gpui_kit::gpui::size(total_width, total_height)
        })

        .unwrap_or_else(|_| gpui_kit::gpui::size(px(text.chars().count() as f32 * font_size), px(84.0)))
}

pub fn actions_height(
    item: &NotificationItem,
    replying: bool,
    cx: &gpui_kit::App,
    text_system: &WindowTextSystem,
) -> f32 {
    let mut rows: usize = 0;
    let mut used = 0.0;
    let width = WIDTH - 32.0;
    for (key, label) in &item.actions {
        if !visible_action(key, label, replying) {
            continue;
        }
        let label = action_label(key, label);
        let button =
            (f32::from(measure(&label, 11.0, FontWeight::NORMAL, false, cx, text_system).width)
                + 30.0)
                .min(width);
        if rows == 0 || used + 6.0 + button > width {
            rows += 1;
            used = button;
        } else {
            used += 6.0 + button;
        }
    }
    let rows = rows.min(3);
    rows as f32 * 28.0 + rows.saturating_sub(1) as f32 * 6.0
}

pub fn popup_height(
    item: Option<&NotificationItem>,
    replying: bool,
    failed: bool,
    cx: &gpui_kit::App,
    text_system: &WindowTextSystem,
) -> f32 {
    let content = item.map_or(144.0, |item| {
        let summary = f32::from(
            measure(
                &item.summary,
                15.0,
                FontWeight::SEMIBOLD,
                true,
                cx,
                text_system,
            )
            .height,
        )
        .max(21.0);
        let body = if item.body.is_empty() {
            0.0
        } else {
            5.0 + f32::from(
                measure(&item.body, 13.0, FontWeight::NORMAL, true, cx, text_system).height,
            )
        };
        let actions = actions_height(item, replying, cx, text_system);
        32.0 + 32.0 + 10.0 + summary + body + if actions > 0.0 { 10.0 + actions } else { 0.0 }
    });
    content.max(126.0)
        + if replying {
            84.0 + if failed { 24.0 } else { 0.0 }
        } else {
            0.0
        }
}

pub fn render(
    module: &NotificationCenterView,
    cx: &mut Context<NotificationCenterView>,
) -> AnyElement {
    let mut root = div()
        .size_full()
        .p(px(16.0))
        .flex()
        .flex_col()
        .gap(px(12.0))
        .rounded_r_none()
        .rounded_l(px(24.0))
        .bg(Theme::bg())
        .border_1()
        .border_r(px(0.0))
        .border_color(Theme::border());

    root = root.child(
        div()
            .h(px(36.0))
            .flex_shrink_0()
            .flex()
            .items_center()
            .justify_between()
            .child(
                div()
                    .flex()
                    .items_center()
                    .gap(px(10.0))
                    .child(
                        div()
                            .text_size(px(18.0))
                            .font_weight(FontWeight::SEMIBOLD)
                            .text_color(Theme::fg())
                            .child("Notifications"),
                    )
                    .child(
                        Badge::new(module.items.len().to_string())
                            .id("notification-count")
                            .variant(BadgeVariant::Neutral),
                    ),
            )
            .child(
                div()
                    .flex()
                    .gap(px(6.0))
                    .when(!module.items.is_empty(), |s| {
                        s.child(
                            IconButton::new("notification-clear", "trash.svg")
                                .size(30.0)
                                .tooltip("Clear All")
                                .on_click(cx.listener(|view, _, _, _| {
                                    view.clear_all();
                                })),
                        )
                    })
                    .child(
                        IconButton::new("notification-close", "close.svg")
                            .size(30.0)
                            .tooltip("Close")
                            .on_click(cx.listener(|_, _, _, cx| {
                                crate::panel_host::PanelHost::close(cx);
                            })),
                    ),
            ),
    );

    let mut list = div()
        .id("notification-history")
        .flex_1()
        .min_h_0()
        .overflow_y_scroll()
        .flex()
        .flex_col()
        .gap(px(10.0));

    if module.items.is_empty() {
        list = list.child(
            div()
                .flex_1()
                .w_full()
                .flex()
                .flex_col()
                .items_center()
                .justify_center()
                .gap(px(12.0))
                .child(
                    svg()
                        .path("bell.svg")
                        .size(px(28.0))
                        .text_color(Theme::muted()),
                )
                .child(
                    div()
                        .text_size(px(13.0))
                        .text_color(Theme::muted())
                        .child("No notifications"),
                ),
        );
    }

    for item in module.items.iter().rev() {
        list = list.child(card(module, item, false, cx));
    }

    root.child(list).into_any_element()
}

pub fn card(
    module: &NotificationCenterView,
    item: &NotificationItem,
    popup: bool,
    cx: &mut Context<NotificationCenterView>,
) -> AnyElement {
    let id = item.id;
    let icon_path = if item.app_icon.starts_with('/') {
        Some(PathBuf::from(&item.app_icon))
    } else {
        None
    };

    let icon = if let Some(path) = icon_path {
        img(path).size(px(22.0)).into_any_element()
    } else {
        svg()
            .path("bell.svg")
            .size(px(20.0))
            .text_color(Theme::accent())
            .into_any_element()
    };

    let mut content = div()
        .id(format!("notification-content-{id}"))
        .w_full()
        .min_w_0()
        .when(popup, |s| s.flex_1().min_h_0().overflow_y_scroll())
        .flex()
        .flex_col()
        .gap(px(5.0))
        .child(
            div()
                .w_full()
                .flex_shrink_0()
                .text_size(px(15.0))
                .font_weight(FontWeight::SEMIBOLD)
                .line_height(px(21.0))
                .text_color(Theme::fg())
                .child(item.summary.clone()),
        )
        .when(!item.body.is_empty(), |s| {
            s.child(
                div()
                    .w_full()
                    .flex_shrink_0()
                    .text_size(px(13.0))
                    .line_height(px(18.0))
                    .text_color(Theme::muted())
                    .child(item.body.clone()),
            )
        });

    if item.actions.iter().any(|(key, _)| key == "default") {
        content = content
            .cursor_pointer()
            .on_click(cx.listener(move |module, _, window, cx| {
                module.action(id, "default".into(), window, cx);
            }));
    }

    let mut row = div()
        .id(format!("notification-card-{id}"))
        .min_w_0()
        .w_full()
        .flex()
        .flex_col()
        .gap(px(10.0))
        .when(popup, |s| {
            s.flex_1().min_h_0().on_hover(
                cx.listener(|_, hovered, _, _| {
                    beskar_services::NotificationStore::global().set_hovered(*hovered);
                }),
            )
        })
        .when(!popup, |s| {
            s.flex_shrink_0()
                .min_h(px(100.0))
                .p(px(14.0))
                .rounded(px(style::CARD_RADIUS))
                .bg(style::surface())
        })
        .child(
            div()
                .h(px(32.0))
                .flex_shrink_0()
                .flex()
                .items_center()
                .gap(px(10.0))
                .child(
                    div()
                        .size(px(32.0))
                        .flex_shrink_0()
                        .rounded_full()
                        .bg(style::selected())
                        .flex()
                        .items_center()
                        .justify_center()
                        .child(icon),
                )
                .child(
                    div()
                        .flex_1()
                        .min_w_0()
                        .text_size(px(12.0))
                        .text_color(Theme::muted())
                        .text_ellipsis()
                        .child(item.app_name.clone()),
                )
                .child(
                    IconButton::new(format!("notification-dismiss-{id}"), "close.svg")
                        .size(28.0)
                        .on_click(cx.listener(move |module, _, _, _| {
                            module.dismiss(id);
                        })),
                ),
        )
        .child(content);

    let replying = module.reply.as_ref().is_some_and(|reply| reply.id == id);
    let mut actions = div()
        .id(format!("notification-actions-{id}"))
        .w_full()
        .min_w_0()
        .flex_shrink_0()
        .flex()
        .flex_wrap()
        .gap(px(6.0))
        .when(popup, |s| {
            s.h(px(actions_height(item, replying, cx, &module.text_system)))
                .overflow_y_scroll()
        });

    let mut has_actions = false;
    for (key, label) in &item.actions {
        if !visible_action(key, label, replying) {
            continue;
        }
        has_actions = true;
        let label = action_label(key, label);
        let key = key.clone();
        actions = actions.child(
            Chip::new(format!("notification-action-{id}-{key}"), label)
                .on_click(cx.listener(move |module, _, window, cx| {
                    module.action(id, key.clone(), window, cx);
                })),
        );
    }
    if has_actions {
        row = row.child(actions);
    }

    if let Some(reply) = module.reply.as_ref().filter(|reply| reply.id == id) {
        let enabled = !reply.pending && !reply.input.is_empty();
        row = row.child(
            div()
                .flex_shrink_0()
                .flex()
                .flex_col()
                .gap(px(6.0))
                .child(
                    Input::from_state(
                        format!("notification-reply-input-{id}"),
                        &reply.input,
                    )
                    .placeholder("Reply...")
                    .h_px(36.0)
                    .rounded(px(style::INNER_RADIUS))
                    .bg(style::surface())
                    .focused(true),
                )
                .child(
                    div()
                        .h(px(32.0))
                        .flex()
                        .items_center()
                        .justify_between()
                        .child(
                            Button::new(format!("notification-reply-cancel-{id}"))
                                .label("Cancel")
                                .variant(ButtonVariant::Secondary)
                                .size(ButtonSize::Sm)
                                .on_click(cx.listener(|module, _, _, cx| module.cancel_reply(cx))),
                        )
                        .child(
                            Button::new(format!("notification-reply-send-{id}"))
                                .label(if reply.pending { "Sending..." } else { "Send" })
                                .variant(ButtonVariant::Primary)
                                .size(ButtonSize::Sm)
                                .disabled(!enabled)
                                .on_click(cx.listener(|module, _, _, cx| module.send_reply(cx))),
                        ),
                )
                .when(reply.failed, |s| {
                    s.child(
                        div()
                            .text_size(px(12.0))
                            .line_height(px(18.0))
                            .text_color(Theme::danger())
                            .child("Failed to send reply"),
                    )
                }),
        );
    }

    row.into_any_element()
}

#[cfg(test)]
pub(crate) mod tests {
    use super::*;

    #[test]
    fn popup_reserves_wrapped_summary_actions_and_reply_space() {
        gpui_kit::platform::headless().run(|cx| {
            let text_system = WindowTextSystem::new(cx.text_system().clone());
            let mut item = NotificationItem {
                id: 1,
                app_name: String::new(),
                app_icon: String::new(),
                summary: "Title".into(),
                body: String::new(),
                actions: vec![],
                received_at: std::time::Instant::now(),
                timeout: std::time::Duration::from_secs(5),
                urgency: 1,
            };
            assert_eq!(popup_height(Some(&item), false, false, cx, &text_system), 126.0);
            item.summary = "Ajustado: subí el contador y corregí la altura de línea para centrar el número en la insignia. Binario recompilado; reinicia Capsule.".into();
            item.actions.push(("default".into(), "Abrir".into()));
            let summary_height = f32::from(measure(&item.summary, 15.0, FontWeight::SEMIBOLD, true, cx, &text_system).height);
            assert!(summary_height > 21.0);
            assert_eq!(popup_height(Some(&item), false, false, cx, &text_system), 32.0 + 32.0 + 10.0 + summary_height + 10.0 + 28.0);
            item.summary = "Title".into();
            item.body = "Long message\n".repeat(1000);
            item.actions = vec![("inline-reply".into(), "Reply".into())];
            assert_eq!(popup_height(Some(&item), false, false, cx, &text_system), 210.0);
            assert_eq!(popup_height(Some(&item), true, false, cx, &text_system), 256.0);
            assert_eq!(popup_height(Some(&item), true, true, cx, &text_system), 280.0);
            item.actions = (0..6).map(|i| (format!("action-{i}"), "Very long action label ".repeat(20))).collect();
            assert_eq!(actions_height(&item, false, cx, &text_system), 96.0);
            let app = cx.to_async();
            cx.foreground_executor().spawn(async move {
                app.background_executor().timer(std::time::Duration::from_millis(10)).await;
                app.update(|cx| cx.quit());
            }).detach();
        });
    }
}
