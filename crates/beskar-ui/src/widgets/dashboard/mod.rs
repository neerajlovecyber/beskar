pub mod media;

use gpui_kit::gpui::{
    div, px, size, AnyElement, Div, IntoElement, Pixels, Size, Styled,
};
use gpui_kit::prelude::*;

pub const WIDTH: f32 = 560.0;
pub const HEIGHT: f32 = 574.0;
pub const PADDING: f32 = 12.0;
pub const GAP: f32 = 8.0;
pub const HEADER: f32 = 28.0;
pub const LEFT: f32 = 268.0;
pub const RIGHT: f32 = WIDTH - PADDING * 2.0 - LEFT - GAP;
pub const CONTROLS: f32 = 68.0;
pub const CONTENT: f32 = CONTROLS * 3.0 + GAP * 2.0;
pub const MEDIA_HEIGHT: f32 = CONTENT;
pub const SLIDER: f32 = 80.0;
pub const NOTIFICATIONS: f32 = 150.0;
pub const FOOTER: f32 = 40.0;
pub const BOTTOM_PADDING: f32 = PADDING;
pub const BODY: f32 = HEIGHT - PADDING - BOTTOM_PADDING - HEADER - GAP;

pub fn module_size(has_tray: bool) -> Size<Pixels> {
    let height = if has_tray {
        HEIGHT
    } else {
        HEIGHT - FOOTER - GAP
    };
    size(px(WIDTH), px(height))
}

pub fn card(radius: f32) -> Div {
    crate::widgets::style::card(radius)
}

#[derive(Clone, Debug, PartialEq)]
pub enum DashboardAction {
    Satellite(String),
    Close,
    CloseSatellite(String),
    Wifi,
    Bluetooth,
    Dnd,
    Mute,
    Brightness(u32),
    Sink(String),
    ScanWifi,
    ScanBluetooth,
    SelectWifi(String),
    ConnectWifi,
    BluetoothDevice(String),
    Month(i8),
    Settings,
    ClearNotifications,
    RemoveNotification(u32),
    Notification(u32, String),
    Media(i8),
    Seek(f64),
    TrayActivate { bus: String, path: String },
    TrayMenu(String, String, i32),
}

pub fn empty(text: impl Into<String>) -> AnyElement {
    div()
        .w_full()
        .p(px(16.0))
        .text_size(px(12.0))
        .text_color(beskar_theme::Theme::foreground_muted())
        .child(text.into())
        .into_any_element()
}

pub fn error(text: impl Into<String>) -> AnyElement {
    div()
        .w_full()
        .text_size(px(12.0))
        .text_color(beskar_theme::Theme::red())
        .child(text.into())
        .into_any_element()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn dimensions_match_columns_and_vertical_layout() {
        assert_eq!(PADDING * 2.0 + LEFT + GAP + RIGHT, WIDTH);
        assert_eq!(PADDING + BOTTOM_PADDING + HEADER + GAP + BODY, HEIGHT);
        assert_eq!(CONTENT + SLIDER + NOTIFICATIONS + FOOTER + GAP * 3.0, BODY);
        assert_eq!(module_size(true), size(px(WIDTH), px(HEIGHT)));
        assert_eq!(
            module_size(false),
            size(px(WIDTH), px(HEIGHT - FOOTER - GAP))
        );
    }
}
