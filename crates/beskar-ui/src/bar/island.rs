//! Island 3-pill morphing layout with cross-fade scaling.
//! Ported directly from `references/capsule/crates/app/src/capsule/mod.rs:52-137`.

use gpui_kit::prelude::*;
use gpui_kit::*;

pub struct OutgoingContent {
    pub view: AnyElement,
    pub size: Size<Pixels>,
    pub scale: f32,
    pub opacity: f32,
}

#[derive(IntoElement)]
pub struct IslandBarWidget {
    left: Vec<AnyElement>,
    center: Option<AnyElement>,
    right: Vec<AnyElement>,
    outgoing: Option<OutgoingContent>,
    size: Size<Pixels>,
    progress: f32,
    scale: f32,
}

impl IslandBarWidget {
    pub fn new(size: Size<Pixels>) -> Self {
        Self {
            left: Vec::new(),
            center: None,
            right: Vec::new(),
            outgoing: None,
            size,
            progress: 1.0,
            scale: 1.0,
        }
    }

    pub fn progress(mut self, progress: f32) -> Self {
        self.progress = progress.clamp(0.0, 1.0);
        self.scale = 0.98 + self.progress * 0.02;
        self
    }

    pub fn outgoing(mut self, outgoing: Option<OutgoingContent>) -> Self {
        self.outgoing = outgoing;
        self
    }

    pub fn left(mut self, elements: impl IntoIterator<Item = AnyElement>) -> Self {
        self.left.extend(elements);
        self
    }

    pub fn center(mut self, element: impl IntoElement) -> Self {
        self.center = Some(element.into_any_element());
        self
    }

    pub fn right(mut self, elements: impl IntoIterator<Item = AnyElement>) -> Self {
        self.right.extend(elements);
        self
    }
}

impl RenderOnce for IslandBarWidget {
    fn render(self, _window: &mut Window, _cx: &mut App) -> impl IntoElement {
        let size = self.size;
        let progress = self.progress;
        let scale = self.scale;

        let center_wrapper = div()
            .w(size.width)
            .h(size.height)
            .flex_shrink_0()
            .when_some(self.outgoing, |s, o| {
                s.child(
                    div()
                        .absolute()
                        .top((size.height - o.size.height * o.scale) * 0.5)
                        .left((size.width - o.size.width * o.scale) * 0.5)
                        .w(o.size.width * o.scale)
                        .h(o.size.height * o.scale)
                        .opacity(o.opacity * (1.0 - progress))
                        .child(o.view),
                )
            })
            .when_some(self.center, |s, center_el| {
                s.child(
                    div()
                        .relative()
                        .top(size.height * (1.0 - scale) * 0.5)
                        .left(size.width * (1.0 - scale) * 0.5)
                        .w(size.width * scale)
                        .h(size.height * scale)
                        .opacity(progress)
                        .child(center_el),
                )
            });

        div()
            .relative()
            .size_full()
            .flex()
            .items_start()
            .justify_center()
            .gap(px(10.0))
            .children(self.left)
            .child(center_wrapper)
            .children(self.right)
    }
}
