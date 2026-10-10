use gpui_kit::assets::IconName;
use gpui_kit::component::Icon;
use gpui_kit::prelude::FluentBuilder;
use gpui_kit::*;
use std::sync::Arc;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PowerAction {
    Lock,
    Suspend,
    Restart,
    Shutdown,
    Logout,
}

impl PowerAction {
    pub fn label(&self) -> &'static str {
        match self {
            Self::Lock => "Lock",
            Self::Suspend => "Suspend",
            Self::Restart => "Restart",
            Self::Shutdown => "Shutdown",
            Self::Logout => "Logout",
        }
    }

    pub fn description(&self) -> &'static str {
        match self {
            Self::Lock => "Lock current session",
            Self::Suspend => "Sleep device",
            Self::Restart => "Reboot operating system",
            Self::Shutdown => "Power off device",
            Self::Logout => "Exit compositor session",
        }
    }

    pub fn icon(&self) -> IconName {
        match self {
            Self::Lock => IconName::Lock,
            Self::Suspend => IconName::Moon,
            Self::Restart => IconName::RotateCw,
            Self::Shutdown => IconName::Power,
            Self::Logout => IconName::LogOut,
        }
    }

    pub fn default_command(&self) -> &'static str {
        match self {
            Self::Lock => "loginctl lock-session",
            Self::Suspend => "systemctl suspend",
            Self::Restart => "systemctl reboot",
            Self::Shutdown => "systemctl poweroff",
            Self::Logout => "niri msg action quit --skip-confirmation",
        }
    }
}

/// A desktop Power Menu overlay widget styled with dark glassmorphism,
/// smooth hover transitions, and emergency red glow on shutdown.
#[derive(IntoElement)]
pub struct PowerMenuWidget {
    on_action: Option<Arc<dyn Fn(PowerAction) + Send + Sync>>,
    on_close: Option<Arc<dyn Fn() + Send + Sync>>,
}

impl Default for PowerMenuWidget {
    fn default() -> Self {
        Self::new()
    }
}

impl PowerMenuWidget {
    pub fn new() -> Self {
        Self {
            on_action: None,
            on_close: None,
        }
    }

    pub fn on_action(mut self, handler: impl Fn(PowerAction) + Send + Sync + 'static) -> Self {
        self.on_action = Some(Arc::new(handler));
        self
    }

    pub fn on_close(mut self, handler: impl Fn() + Send + Sync + 'static) -> Self {
        self.on_close = Some(Arc::new(handler));
        self
    }
}

impl RenderOnce for PowerMenuWidget {
    fn render(self, _window: &mut Window, _cx: &mut App) -> impl IntoElement {
        let on_action = self.on_action;
        let on_close = self.on_close;

        let actions = [
            PowerAction::Lock,
            PowerAction::Suspend,
            PowerAction::Logout,
            PowerAction::Restart,
            PowerAction::Shutdown,
        ];

        div()
            .relative()
            .w(px(240.0))
            .p(px(12.0))
            .rounded(px(16.0))
            // Deep obsidian backdrop with 95% opacity
            .bg(hsla(240.0 / 360.0, 0.16, 0.08, 0.95))
            .border_1()
            .border_color(hsla(240.0 / 360.0, 0.12, 1.0, 0.14))
            .shadow_lg()
            // Top specular edge highlight
            .child(
                div()
                    .absolute()
                    .top_0()
                    .left(px(16.0))
                    .right(px(16.0))
                    .h(px(1.0))
                    .bg(hsla(0.0, 0.0, 1.0, 0.20)),
            )
            // Header
            .child(
                div()
                    .flex()
                    .items_center()
                    .justify_between()
                    .pb(px(8.0))
                    .mb(px(6.0))
                    .border_b_1()
                    .border_color(hsla(0.0, 0.0, 1.0, 0.08))
                    .child(
                        div()
                            .text_xs()
                            .font_weight(FontWeight::BOLD)
                            .text_color(hsla(0.0, 0.0, 0.85, 1.0))
                            .child("Power Menu"),
                    )
                    .child(
                        div()
                            .w(px(18.0))
                            .h(px(18.0))
                            .flex()
                            .items_center()
                            .justify_center()
                            .rounded(px(4.0))
                            .text_color(hsla(0.0, 0.0, 0.50, 1.0))
                            .hover(|s| {
                                s.bg(hsla(0.0, 0.0, 1.0, 0.10))
                                    .text_color(hsla(0.0, 0.0, 0.90, 1.0))
                                    .cursor_pointer()
                            })
                            .when_some(on_close, |el, cb| {
                                el.on_mouse_down(MouseButton::Left, move |_, _, _| (cb)())
                            })
                            .child(Icon::new(IconName::X).size(px(12.0))),
                    ),
            )
            // Actions list
            .child(
                div()
                    .flex()
                    .flex_col()
                    .gap(px(4.0))
                    .children(actions.into_iter().map(|action| {
                        let is_shutdown = action == PowerAction::Shutdown;
                        let cb = on_action.clone();

                        let item = div()
                            .flex()
                            .items_center()
                            .justify_between()
                            .px(px(10.0))
                            .py(px(8.0))
                            .rounded(px(8.0))
                            .hover(move |s| {
                                if is_shutdown {
                                    s.cursor_pointer()
                                        .bg(hsla(350.0 / 360.0, 0.85, 0.45, 0.25))
                                        .border_1()
                                        .border_color(hsla(350.0 / 360.0, 0.85, 0.55, 0.50))
                                } else {
                                    s.cursor_pointer()
                                        .bg(hsla(240.0 / 360.0, 0.14, 0.20, 0.50))
                                        .border_1()
                                        .border_color(hsla(0.0, 0.0, 1.0, 0.12))
                                }
                            })

                            .on_mouse_down(MouseButton::Left, move |_, _, _| {
                                if let Some(h) = cb.as_ref() {
                                    h(action);
                                }
                            })
                            .child(
                                div()
                                    .flex()
                                    .items_center()
                                    .gap(px(10.0))
                                    .child(
                                        div()
                                            .w(px(24.0))
                                            .h(px(24.0))
                                            .flex()
                                            .items_center()
                                            .justify_center()
                                            .rounded(px(6.0))
                                            .bg(if is_shutdown {
                                                hsla(350.0 / 360.0, 0.70, 0.35, 0.30)
                                            } else {
                                                hsla(240.0 / 360.0, 0.14, 0.20, 0.40)
                                            })
                                            .child(
                                                Icon::new(action.icon())
                                                    .size(px(13.0))
                                                    .text_color(if is_shutdown {
                                                        hsla(350.0 / 360.0, 0.90, 0.65, 1.0)
                                                    } else {
                                                        hsla(0.0, 0.0, 0.85, 1.0)
                                                    }),
                                            ),
                                    )
                                    .child(
                                        div()
                                            .flex()
                                            .flex_col()
                                            .child(
                                                div()
                                                    .text_xs()
                                                    .font_weight(FontWeight::MEDIUM)
                                                    .text_color(if is_shutdown {
                                                        hsla(350.0 / 360.0, 0.95, 0.70, 1.0)
                                                    } else {
                                                        hsla(0.0, 0.0, 0.95, 1.0)
                                                    })
                                                    .child(action.label()),
                                            )
                                            .child(
                                                div()
                                                    .text_xs()
                                                    .text_color(hsla(0.0, 0.0, 0.50, 1.0))
                                                    .child(action.description()),
                                            ),
                                    ),
                            );

                        item
                    })),
            )
    }
}
