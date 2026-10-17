use beskar_theme::Theme;
use gpui_kit::assets::IconName;
use gpui_kit::component::button::{Button, ButtonVariant, ButtonVariants};
use gpui_kit::component::Icon;
use gpui_kit::*;

use crate::panel_host::{PanelEdge, PanelHost, PanelModule, Slot};

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
            Self::Logout => "loginctl terminate-user $USER",
            Self::Restart => "systemctl reboot",
            Self::Shutdown => "systemctl poweroff",
        }
    }
}

/// Dedicated, autonomous View for the Power Menu
pub struct PowerMenuView {
    selected_index: usize,
    pending_action: Option<PowerAction>,
    confirm_index: usize,
    focus_handle: FocusHandle,
}

impl PanelModule for PowerMenuView {
    const ID: &'static str = "power_menu";

    fn slot() -> Slot {
        Slot::Focus
    }

    fn panel_edge() -> PanelEdge {
        PanelEdge::Bottom
    }

    fn size() -> Size<Pixels> {
        Size::new(px(356.0), px(64.0))
    }

    fn build(cx: &mut Context<Self>) -> Self {
        Self::new(cx)
    }
}

impl PowerMenuView {
    pub fn new(cx: &mut Context<Self>) -> Self {
        let focus_handle = cx.focus_handle();

        Self {
            selected_index: 0,
            pending_action: None,
            confirm_index: 1,
            focus_handle,
        }
    }

    pub fn execute_action(&self, action: PowerAction, cx: &mut App) {
        if action == PowerAction::Lock {
            PanelHost::close(cx);
            PanelHost::toggle_by_id("lock_screen", cx);
        } else {
            let cmd = action.default_command();
            tokio::task::spawn_blocking(move || {
                let _ = std::process::Command::new("sh").args(["-c", cmd]).spawn();
            });
            PanelHost::close(cx);
        }
    }
}

impl Focusable for PowerMenuView {
    fn focus_handle(&self, _cx: &App) -> FocusHandle {
        self.focus_handle.clone()
    }
}

impl Render for PowerMenuView {
    fn render(&mut self, _window: &mut Window, cx: &mut Context<Self>) -> impl IntoElement {
        let cur_selected = self.selected_index;

        div()
            .id("power-menu-container")
            .relative()
            .w(px(356.0))
            .h(px(64.0))
            .p(px(6.0))
            .rounded_b_none()
            .rounded_t(px(20.0))
            .bg(Theme::bg())
            .border_1()
            .border_b(px(0.0))
            .border_color(Theme::border())
            .shadow_xl()
            .track_focus(&self.focus_handle)
            .key_context("PowerMenu")
            .on_key_down(cx.listener(move |this, event: &KeyDownEvent, _window, cx| {
                let key = &event.keystroke.key;

                if this.pending_action.is_some() {
                    if key == "escape" || key == "n" || key == "left" {
                        this.pending_action = None;
                        cx.notify();
                        cx.stop_propagation();
                    } else if key == "right" {
                        this.confirm_index = 1;
                        cx.notify();
                        cx.stop_propagation();
                    } else if key == "enter" || key == "y" {
                        if let Some(action) = this.pending_action {
                            this.execute_action(action, cx);
                        }
                        cx.stop_propagation();
                    }
                } else if key == "escape" {
                    PanelHost::close(cx);
                    cx.stop_propagation();
                } else if key == "1" || key == "l" {
                    this.execute_action(PowerAction::Lock, cx);
                    cx.stop_propagation();
                } else if key == "2" || key == "s" {
                    this.pending_action = Some(PowerAction::Suspend);
                    this.confirm_index = 1;
                    cx.notify();
                    cx.stop_propagation();
                } else if key == "3" || key == "e" {
                    this.pending_action = Some(PowerAction::Logout);
                    this.confirm_index = 1;
                    cx.notify();
                    cx.stop_propagation();
                } else if key == "4" || key == "r" {
                    this.pending_action = Some(PowerAction::Restart);
                    this.confirm_index = 1;
                    cx.notify();
                    cx.stop_propagation();
                } else if key == "5" || key == "p" {
                    this.pending_action = Some(PowerAction::Shutdown);
                    this.confirm_index = 1;
                    cx.notify();
                    cx.stop_propagation();
                } else if key == "right" || key == "down" {
                    this.selected_index = (this.selected_index + 1)
                        .min(PowerAction::ALL.len().saturating_sub(1));
                    cx.notify();
                    cx.stop_propagation();
                } else if key == "left" || key == "up" {
                    if this.selected_index > 0 {
                        this.selected_index -= 1;
                        cx.notify();
                    }
                    cx.stop_propagation();
                } else if key == "enter" {
                    let action = PowerAction::ALL[this.selected_index];
                    if action.requires_confirmation() {
                        this.pending_action = Some(action);
                        this.confirm_index = 1;
                        cx.notify();
                    } else {
                        this.execute_action(action, cx);
                    }
                    cx.stop_propagation();
                }
            }))
            .child(if let Some(pending) = self.pending_action {
                        let is_critical = matches!(pending, PowerAction::Shutdown | PowerAction::Restart);

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
                                                beskar_theme::Theme::danger_alpha(0.20)
                                            } else {
                                                beskar_theme::Theme::accent_alpha(0.20)
                                            })
                                            .child(
                                                Icon::new(pending.icon())
                                                    .size(px(13.0))
                                                    .text_color(if is_critical {
                                                        beskar_theme::Theme::danger()
                                                    } else {
                                                        beskar_theme::Theme::accent()
                                                    }),
                                            ),
                                    )
                                    .child(
                                        div()
                                            .text_sm()
                                            .font_weight(FontWeight::BOLD)
                                            .text_color(beskar_theme::Theme::fg())
                                            .child(format!("Confirm {}?", pending.label())),
                                    ),
                            )
                            .child(
                                div()
                                    .flex()
                                    .items_center()
                                    .gap(px(6.0))
                                    .child(
                                        Button::new("power-confirm-cancel")
                                            .ghost()
                                            .icon(Icon::new(IconName::X).size(px(12.0)))
                                            .label("Cancel")
                                            .on_click(cx.listener(|this, _, _, cx| {
                                                this.pending_action = None;
                                                cx.notify();
                                            })),
                                    )
                                    .child(
                                        Button::new("power-confirm-action")
                                            .with_variant(if is_critical {
                                                ButtonVariant::Danger
                                            } else {
                                                ButtonVariant::Primary
                                            })
                                            .icon(Icon::new(IconName::Check).size(px(12.0)))
                                            .label("Confirm")
                                            .on_click(cx.listener(move |this, _, _, cx| {
                                                this.execute_action(pending, cx);
                                            })),
                                    ),
                            )
                    } else {
                        div()
                            .id("power-actions-strip")
                            .flex()
                            .items_center()
                            .gap(px(4.0))
                            .children(PowerAction::ALL.into_iter().enumerate().map(|(idx, action)| {
                                let is_sel = cur_selected == idx;
                                let is_shutdown = action == PowerAction::Shutdown;

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
                                    .bg(if is_sel {
                                        if is_shutdown {
                                            beskar_theme::Theme::danger_alpha(0.25)
                                        } else {
                                            Theme::bg_secondary()
                                        }
                                    } else {
                                        gpui_kit::transparent_black()
                                    })
                                    .hover(move |s| {
                                        s.bg(if is_shutdown {
                                            beskar_theme::Theme::danger_alpha(0.20)
                                        } else {
                                            Theme::bg_secondary()
                                        })
                                    })
                                    .on_mouse_down(MouseButton::Left, cx.listener(move |this, _, _, cx| {
                                        this.selected_index = idx;
                                        if action.requires_confirmation() {
                                            this.pending_action = Some(action);
                                            this.confirm_index = 1;
                                            cx.notify();
                                        } else {
                                            this.execute_action(action, cx);
                                        }
                                    }))
                                    .child(
                                        Icon::new(action.icon())
                                            .size(px(16.0))
                                            .text_color(if is_sel {
                                                if is_shutdown {
                                                    beskar_theme::Theme::danger()
                                                } else {
                                                    Theme::accent()
                                                }
                                            } else {
                                                Theme::muted()
                                            }),
                                    )
                                    .child(
                                        div()
                                            .text_xs()
                                            .font_weight(if is_sel {
                                                FontWeight::BOLD
                                            } else {
                                                FontWeight::NORMAL
                                            })
                                            .text_color(if is_sel {
                                                if is_shutdown {
                                                    beskar_theme::Theme::danger()
                                                } else {
                                                    Theme::fg()
                                                }
                                            } else {
                                                Theme::muted()
                                            })
                                            .child(action.label()),
                                    )
                            }))
                    })
    }
}
