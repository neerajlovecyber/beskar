//! Satellite Host Overlay Container
//! Coordinates floating Satellite OSD panels (Wifi, Bluetooth, Audio, Calendar, Tray)
//! positioned dynamically via `SatelliteLayout` beside the bar or capsule.

use crate::satellite::{Satellite, SatelliteId, SatelliteVisual, Side};
use gpui_kit::gpui::{div, px, Bounds, IntoElement, Pixels, Size};
use gpui_kit::prelude::FluentBuilder;
use gpui_kit::*;

pub fn render_satellite_surface(
    visual: &SatelliteVisual,
    content: impl IntoElement,
    radius: f32,
) -> impl IntoElement {
    let layout = &visual.layout;
    let radius = px(radius.max(0.0))
        .min(layout.bounds.size.width / 2.0)
        .min(layout.bounds.size.height / 2.0);

    let body = div()
        .absolute()
        .top_0()
        .when(matches!(layout.side, Side::Left), |s| s.right_0())
        .when(!matches!(layout.side, Side::Left), |s| s.left_0())
        .w(layout.content_size.width)
        .max_h(layout.content_size.height)
        .flex()
        .flex_col()
        .child(content);

    div()
        .id(SharedString::from(format!("satellite-{:?}", visual.id)))
        .absolute()
        .left(layout.bounds.origin.x)
        .top(layout.bounds.origin.y)
        .w(layout.bounds.size.width)
        .h(layout.bounds.size.height)
        .rounded(radius)
        .opacity(visual.progress.clamp(0.0, 1.0))
        .overflow_hidden()
        .bg(beskar_theme::Theme::bg_secondary())
        .border_1()
        .border_color(beskar_theme::Theme::subtle_border())
        .shadow_xl()
        .child(body)
        .when(!visual.open || visual.progress < 1.0, |s| {
            s.child(div().absolute().inset_0())
        })
}

#[derive(IntoElement)]
pub struct SatelliteOverlayHost {
    visuals: Vec<SatelliteVisual>,
    content_map: Vec<(SatelliteId, AnyElement)>,
}

impl Default for SatelliteOverlayHost {
    fn default() -> Self {
        Self::new()
    }
}

impl SatelliteOverlayHost {
    pub fn new() -> Self {
        Self {
            visuals: Vec::new(),
            content_map: Vec::new(),
        }
    }

    pub fn compute_visuals(
        satellite: &Satellite,
        viewport: Size<Pixels>,
        capsule: Bounds<Pixels>,
        gap: Pixels,
        measured: &[(SatelliteId, Bounds<Pixels>)],
    ) -> Vec<SatelliteVisual> {
        satellite.layout(viewport, capsule, gap, measured)
    }

    pub fn visuals(mut self, visuals: Vec<SatelliteVisual>) -> Self {
        self.visuals = visuals;
        self
    }

    pub fn panel(mut self, id: SatelliteId, element: impl IntoElement) -> Self {
        self.content_map.push((id, element.into_any_element()));
        self
    }
}

impl RenderOnce for SatelliteOverlayHost {
    fn render(mut self, _window: &mut Window, _cx: &mut App) -> impl IntoElement {
        let mut container = div().absolute().inset_0();
        for visual in self.visuals {
            if let Some(pos) = self.content_map.iter().position(|(id, _)| *id == visual.id) {
                let (_, content) = self.content_map.swap_remove(pos);
                container = container.child(render_satellite_surface(&visual, content, 16.0));
            }
        }
        container
    }
}
