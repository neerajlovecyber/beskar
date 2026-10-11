use beskar_theme::Theme;
use gpui_kit::assets::IconName;
use gpui_kit::component::button::{Button, ButtonVariant, ButtonVariants};
use gpui_kit::component::Icon;
use gpui_kit::*;
use std::sync::Arc;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PowerAction {
    Lock,
    Suspend,
    Logout,
    Restart,
    Shutdown,
}

impl PowerAction {
    pub const ALL: [Self; 5] = [
        Self::Lock,
        Self::Suspend,
        Self::Logout,
        Self::Restart,
        Self::Shutdown,
    ];

    pub fn label(&self) -> &'static str {
        match self {
            Self::Lock => "Lock",
            Self::Suspend => "Suspend",
            Self::Logout => "Logout",
            Self::Restart => "Reboot",
            Self::Shutdown => "Shutdown",
        }
    }

    pub fn description(&self) -> &'static str {
        match self {
            Self::Lock => "Lock active desktop session",
            Self::Suspend => "Put system into low-power sleep",
            Self::Logout => "Exit compositor session",
            Self::Restart => "Reboot the system",
            Self::Shutdown => "Power off the computer",
        }
    }

    pub fn icon(&self) -> IconName {
        match self {
            Self::Lock => IconName::Lock,
            Self::Suspend => IconName::Moon,
            Self::Logout => IconName::LogOut,
            Self::Restart => IconName::RotateCw,
            Self::Shutdown => IconName::Power,
        }
    }

    pub fn requires_confirmation(&self) -> bool {
        match self {
            Self::Lock => false,
            Self::Suspend | Self::Logout | Self::Restart | Self::Shutdown => true,
        }
    }

    pub fn default_command(&self) -> &'static str {
        match self {
            Self::Lock => "loginctl lock-session",
            Self::Suspend => "systemctl suspend",
            Self::Logout => "niri msg action quit --skip-confirmation",
            Self::Restart => "systemctl reboot",
            Self::Shutdown => "systemctl poweroff",
        }
    }
}

/// A desktop Power Menu overlay widget matching Minflair's ActionMenu architecture.
/// Features a horizontal 5-action strip with two-stage confirmation prompt,
/// keyboard arrow selection, and smooth obsidian glass styling.
#[derive(IntoElement)]
pub struct PowerMenuWidget {
    selected_index: usize,
    pending_action: Option<PowerAction>,
    confirm_index: usize,
    on_action: Option<Arc<dyn Fn(PowerAction) + Send + Sync>>,
    on_request_confirm: Option<Arc<dyn Fn(PowerAction) + Send + Sync>>,
    on_cancel_confirm: Option<Arc<dyn Fn() + Send + Sync>>,
    on_select: Option<Arc<dyn Fn(usize) + Send + Sync>>,
    on_confirm_select: Option<Arc<dyn Fn(usize) + Send + Sync>>,
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
            selected_index: 0,
            pending_action: None,
            confirm_index: 1, // Default confirm button highlighted
            on_action: None,
            on_request_confirm: None,
            on_cancel_confirm: None,
            on_select: None,
            on_confirm_select: None,
            on_close: None,
        }
    }

    pub fn selected_index(mut self, idx: usize) -> Self {
        self.selected_index = idx.min(PowerAction::ALL.len().saturating_sub(1));
        self
    }

    pub fn pending_action(mut self, action: Option<PowerAction>) -> Self {
        self.pending_action = action;
        self
    }

    pub fn confirm_index(mut self, idx: usize) -> Self {
        self.confirm_index = idx.min(1);
        self
    }

    pub fn on_action(mut self, handler: impl Fn(PowerAction) + Send + Sync + 'static) -> Self {
        self.on_action = Some(Arc::new(handler));
        self
    }

    pub fn on_request_confirm(
        mut self,
        handler: impl Fn(PowerAction) + Send + Sync + 'static,
    ) -> Self {
        self.on_request_confirm = Some(Arc::new(handler));
        self
    }

    pub fn on_cancel_confirm(mut self, handler: impl Fn() + Send + Sync + 'static) -> Self {
        self.on_cancel_confirm = Some(Arc::new(handler));
        self
    }

    pub fn on_select(mut self, handler: impl Fn(usize) + Send + Sync + 'static) -> Self {
        self.on_select = Some(Arc::new(handler));
        self
    }

    pub fn on_confirm_select(mut self, handler: impl Fn(usize) + Send + Sync + 'static) -> Self {
        self.on_confirm_select = Some(Arc::new(handler));
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
        let on_req = self.on_request_confirm;
        let on_cancel = self.on_cancel_confirm;
        let on_select = self.on_select;
        let on_confirm_select = self.on_confirm_select;
        let _ = self.on_close;

        div()
            .id("power-menu-container")
            .relative()
            .p(px(6.0))
            .rounded(px(16.0))
            // Minflair Deep Obsidian Glass (Theme.bg)
            .bg(Theme::bg())
            .border_1()
            .border_color(Theme::border())
            .shadow_xl()
            .child(if let Some(pending) = self.pending_action {
                // ── Stage 2: Confirmation Prompt ──
                let is_critical = matches!(pending, PowerAction::Shutdown | PowerAction::Restart);
                let action_cb = on_action.clone();
                let cancel_cb = on_cancel.clone();
                let conf_sel_cancel = on_confirm_select.clone();
                let conf_sel_confirm = on_confirm_select.clone();

                div()
                    .id("power-confirm-stage")
                    .flex()
                    .items_center()
                    .justify_between()
                    .w(px(336.0))
                    .h(px(48.0))
                    .px(px(10.0))
                    .child(
                        div()
                            .flex()
                            .items_center()
                            .gap(px(8.0))
                            .child(
                                div()
                                    .w(px(24.0))
                                    .h(px(24.0))
                                    .rounded_full()
                                    .flex()
                                    .items_center()
                                    .justify_center()
                                    .bg(if is_critical {
                                        hsla(350.0 / 360.0, 0.85, 0.50, 0.20)
                                    } else {
                                        hsla(261.0 / 360.0, 0.86, 0.73, 0.20)
                                    })
                                    .child(
                                        Icon::new(pending.icon())
                                            .size(px(13.0))
                                            .text_color(if is_critical {
                                                hsla(350.0 / 360.0, 0.90, 0.65, 1.0)
                                            } else {
                                                hsla(261.0 / 360.0, 0.90, 0.75, 1.0)
                                            }),
                                    ),
                            )
                            .child(
                                div()
                                    .text_sm()
                                    .font_weight(FontWeight::BOLD)
                                    .text_color(hsla(0.0, 0.0, 0.95, 1.0))
                                    .child(format!("Confirm {}?", pending.label())),
                            ),
                    )
                    .child(
                        div()
                            .flex()
                            .items_center()
                            .gap(px(6.0))
                            // Cancel Button (index 0)
                            .child(
                                Button::new("power-confirm-cancel")
                                    .ghost()
                                    .icon(Icon::new(IconName::X).size(px(12.0)))
                                    .label("Cancel")
                                    .on_click(move |_, _, _| {
                                        if let Some(ref cb) = conf_sel_cancel {
                                            cb(0);
                                        }
                                        if let Some(ref cb) = cancel_cb {
                                            cb();
                                        }
                                    }),
                            )
                            // Confirm Button (index 1)
                            .child(
                                Button::new("power-confirm-action")
                                    .with_variant(if is_critical {
                                        ButtonVariant::Danger
                                    } else {
                                        ButtonVariant::Primary
                                    })
                                    .icon(Icon::new(IconName::Check).size(px(12.0)))
                                    .label("Confirm")
                                    .on_click(move |_, _, _| {
                                        if let Some(ref cb) = conf_sel_confirm {
                                            cb(1);
                                        }
                                        if let Some(ref cb) = action_cb {
                                            cb(pending);
                                        }
                                    }),
                            ),
                    )
            } else {
                // ── Stage 1: Horizontal Action Menu Strip ──
                let cur_selected = self.selected_index;

                div()
                    .id("power-actions-strip")
                    .flex()
                    .items_center()
                    .gap(px(4.0))
                    .children(PowerAction::ALL.into_iter().enumerate().map(|(idx, action)| {
                        let is_sel = cur_selected == idx;
                        let is_shutdown = action == PowerAction::Shutdown;
                        let action_cb = on_action.clone();
                        let req_cb = on_req.clone();
                        let sel_cb = on_select.clone();

                        div()
                            .id(("power-action", idx))
                            .w(px(64.0))
                            .h(px(48.0))
                            .rounded(px(12.0))
                            .flex()
                            .flex_col()
                            .items_center()
                            .justify_center()
                            .gap(px(2.0))
                            .cursor_pointer()
                            // Accent pill selection matching Minflair ActionMenu.qml
                            .bg(if is_sel {
                                if is_shutdown {
                                    hsla(350.0 / 360.0, 0.85, 0.50, 1.0)
                                } else {
                                    hsla(261.0 / 360.0, 0.86, 0.73, 1.0)
                                }
                            } else {
                                hsla(0.0, 0.0, 1.0, 0.0)
                            })
                            .hover(move |s| {
                                if !is_sel {
                                    s.bg(hsla(0.0, 0.0, 1.0, 0.12))
                                } else {
                                    s
                                }
                            })
                            .on_mouse_down(MouseButton::Left, move |_, _, _| {
                                if let Some(ref cb) = sel_cb {
                                    cb(idx);
                                }
                                if action.requires_confirmation() {
                                    if let Some(ref cb) = req_cb {
                                        cb(action);
                                    }
                                } else if let Some(ref cb) = action_cb {
                                    cb(action);
                                }
                            })
                            .child(
                                Icon::new(action.icon())
                                    .size(px(16.0))
                                    .text_color(if is_sel {
                                        if is_shutdown {
                                            hsla(0.0, 0.0, 1.0, 1.0)
                                        } else {
                                            hsla(0.0, 0.0, 0.05, 1.0)
                                        }
                                    } else {
                                        hsla(0.0, 0.0, 0.80, 1.0)
                                    }),
                            )
                            .child(
                                div()
                                    .text_xs()
                                    .font_weight(if is_sel {
                                        FontWeight::BOLD
                                    } else {
                                        FontWeight::MEDIUM
                                    })
                                    .text_color(if is_sel {
                                        if is_shutdown {
                                            hsla(0.0, 0.0, 1.0, 1.0)
                                        } else {
                                            hsla(0.0, 0.0, 0.05, 1.0)
                                        }
                                    } else {
                                        hsla(0.0, 0.0, 0.65, 1.0)
                                    })
                                    .child(action.label()),
                            )
                    }))
            })
    }
}


