use beskar_theme::Theme;
use gpui_kit::gpui::{
    App, ElementId, FontWeight, IntoElement, RenderOnce, SharedString, Styled, Window, div, px,
};
use gpui_kit::prelude::*;


#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum BadgeVariant {
    #[default]
    Neutral,
    Accent,
    Danger,
    Success,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum BadgeSize {
    Sm,
    #[default]
    Md,
}

impl BadgeSize {
    pub fn height(&self) -> f32 {
        match self {
            BadgeSize::Sm => 18.0,
            BadgeSize::Md => 22.0,
        }
    }

    pub fn text_size(&self) -> f32 {
        match self {
            BadgeSize::Sm => 10.0,
            BadgeSize::Md => 11.0,
        }
    }

    pub fn padding_x(&self) -> f32 {
        match self {
            BadgeSize::Sm => 6.0,
            BadgeSize::Md => 8.0,
        }
    }
}

#[derive(IntoElement)]
pub struct Badge {
    id: Option<ElementId>,
    content: Option<SharedString>,
    variant: BadgeVariant,
    size: BadgeSize,
    circle: bool,
}

impl Badge {
    pub fn new(content: impl Into<SharedString>) -> Self {
        Self {
            id: None,
            content: Some(content.into()),
            variant: BadgeVariant::Neutral,
            size: BadgeSize::Md,
            circle: false,
        }
    }

    pub fn id(mut self, id: impl Into<ElementId>) -> Self {
        self.id = Some(id.into());
        self
    }

    pub fn variant(mut self, variant: BadgeVariant) -> Self {
        self.variant = variant;
        self
    }

    pub fn size(mut self, size: BadgeSize) -> Self {
        self.size = size;
        self
    }

    pub fn circle(mut self, circle: bool) -> Self {
        self.circle = circle;
        self
    }
}

impl RenderOnce for Badge {
    fn render(self, _: &mut Window, _: &mut App) -> impl IntoElement {
        let (bg, fg) = match self.variant {
            BadgeVariant::Neutral => (Theme::bg_secondary(), Theme::muted()),
            BadgeVariant::Accent => (Theme::accent_alpha(0.2), Theme::accent()),
            BadgeVariant::Danger => (Theme::danger_alpha(0.2), Theme::danger()),
            BadgeVariant::Success => (Theme::success_alpha(0.2), Theme::success()),
        };

        let height = self.size.height();
        let text_size = self.size.text_size();
        let padding_x = if self.circle { 0.0 } else { self.size.padding_x() };

        let mut el = div()
            .id(self.id.unwrap_or_else(|| ElementId::from("badge")))
            .h(px(height))
            .px(px(padding_x))
            .rounded_full()
            .bg(bg)
            .text_color(fg)
            .text_size(px(text_size))
            .font_weight(FontWeight::SEMIBOLD)
            .flex()
            .items_center()
            .justify_center();

        if self.circle {
            el = el.w(px(height));
        }

        if let Some(content) = self.content {
            el = el.child(content);
        }

        el

    }
}
