use beskar_services::BluetoothDeviceItem;
use gpui_kit::assets::IconName;
use gpui_kit::component::tag::Tag;
use gpui_kit::component::Icon;
use gpui_kit::*;

pub fn render_bt_list(
    bt_devices: &[BluetoothDeviceItem],
) -> impl IntoElement {
    div()
        .p(px(10.0))
        .rounded(px(12.0))
        .bg(beskar_theme::Theme::glass_fill(0.05))
        .border_1()
        .border_color(beskar_theme::Theme::subtle_border())
        .flex()
        .flex_col()
        .gap(px(6.0))
        .child(
            div()
                .text_xs()
                .font_weight(FontWeight::BOLD)
                .text_color(beskar_theme::Theme::info())
                .child("Paired Bluetooth Devices"),
        )
        .child(if bt_devices.is_empty() {
            div()
                .py(px(12.0))
                .flex()
                .items_center()
                .justify_center()
                .child(
                    div()
                        .text_xs()
                        .text_color(beskar_theme::Theme::muted())
                        .child("Scanning Bluetooth devices..."),
                )
                .into_any_element()
        } else {
            div()
                .id("cc-bt-scroll-list")
                .flex()
                .flex_col()
                .gap(px(4.0))
                .max_h(px(180.0))
                .overflow_y_scroll()
                .children(bt_devices.iter().enumerate().map(|(idx, dev)| {
                    let is_conn = dev.is_connected;
                    let dev_label = if is_conn {
                        if let Some(bat) = dev.battery_percent {
                            format!("Connected ({}%)", bat)
                        } else {
                            "Connected".to_string()
                        }
                    } else {
                        "Disconnected".to_string()
                    };
                    div()
                        .id(SharedString::from(format!("cc-bt-dev-{}", idx)))
                        .flex()
                        .items_center()
                        .justify_between()
                        .p(px(6.0))
                        .rounded(px(8.0))
                        .bg(beskar_theme::Theme::glass_fill(0.03))
                        .child(
                            div()
                                .flex()
                                .items_center()
                                .gap(px(6.0))
                                .child(
                                    Icon::new(IconName::Bluetooth)
                                        .size(px(12.0))
                                        .text_color(if is_conn {
                                            beskar_theme::Theme::success()
                                        } else {
                                            beskar_theme::Theme::muted()
                                        }),
                                )
                                .child(
                                    div()
                                        .text_xs()
                                        .text_color(beskar_theme::Theme::fg())
                                        .child(dev.name.clone()),
                                ),
                        )
                        .child(if is_conn {
                            Tag::primary().child(dev_label)
                        } else {
                            Tag::secondary().child(dev_label)
                        })
                }))
                .into_any_element()
        })
}
