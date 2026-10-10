use gpui::{div, px, AnyElement, IntoElement, ParentElement, Pixels, RenderOnce, Styled, Window, App};

/// Beskar Bar surface separating the top bar into 3 distinct layout regions:
/// - [Left Island]: Workspaces & active tasks
/// - [Dynamic Center Island]: Dynamic morphing pill (clock, MPRIS, notifications)
/// - [Right Island]: Vitals, battery, volume, quick sliders, system tray
#[derive(IntoElement)]
pub struct BeskarBar {
    left: Vec<AnyElement>,
    center: Vec<AnyElement>,
    right: Vec<AnyElement>,
    padding_x: Pixels,
}

impl BeskarBar {
    pub fn new() -> Self {
        Self {
            left: Vec::new(),
            center: Vec::new(),
            right: Vec::new(),
            padding_x: px(12.0),
        }
    }

    pub fn left(mut self, elements: impl IntoIterator<Item = AnyElement>) -> Self {
        self.left.extend(elements);
        self
    }

    pub fn center(mut self, elements: impl IntoIterator<Item = AnyElement>) -> Self {
        self.center.extend(elements);
        self
    }

    pub fn right(mut self, elements: impl IntoIterator<Item = AnyElement>) -> Self {
        self.right.extend(elements);
        self
    }
}

impl RenderOnce for BeskarBar {
    fn render(self, _window: &mut Window, _cx: &mut App) -> impl IntoElement {
        div()
            .size_full()
            .flex()
            .items_center()
            .px(self.padding_x)
            .py(px(4.0))
            // Left region: Left Island
            .child(
                div()
                    .flex()
                    .flex_1()
                    .items_center()
                    .justify_start()
                    .children(self.left),
            )
            // Center region: Dynamic Center Island
            .child(
                div()
                    .flex()
                    .items_center()
                    .justify_center()
                    .children(self.center),
            )
            // Right region: Right Island
            .child(
                div()
                    .flex()
                    .flex_1()
                    .items_center()
                    .justify_end()
                    .children(self.right),
            )
    }
}
