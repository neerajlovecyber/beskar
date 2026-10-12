pub mod view;
use self::view::DashboardWidget;
use gpui_kit::*;

use crate::panel_host::{PanelHost, PanelModule};

#[derive(Debug, Clone)]
enum DashboardMsg {
    RefreshGithub,
    RefreshUpdates,
    RunUpdate,
    OpenProfile,
    Close,
}

pub struct DashboardView {
    github_state: beskar_services::GithubState,
    updates_state: beskar_services::SystemUpdatesState,
    focus_handle: FocusHandle,
    msg_tx: tokio::sync::mpsc::UnboundedSender<DashboardMsg>,
}

impl PanelModule for DashboardView {
    const ID: &'static str = "dashboard";

    fn build(cx: &mut Context<Self>) -> Self {
        Self::new(cx)
    }
}

impl DashboardView {
    pub fn new(cx: &mut Context<Self>) -> Self {
        let focus_handle = cx.focus_handle();
        let (msg_tx, mut msg_rx) = tokio::sync::mpsc::unbounded_channel::<DashboardMsg>();

        let user = std::env::var("USER").unwrap_or_else(|_| "developer".to_string());
        let github_state = beskar_services::GithubService::get_or_load(&user);
        let updates_state = beskar_services::UpdateService::cached();

        cx.spawn(async move |this, cx| {
            while let Some(msg) = msg_rx.recv().await {
                match msg {
                    DashboardMsg::RefreshGithub => {
                        let user_clone = user.clone();
                        let state = cx
                            .background_executor()
                            .spawn(async move {
                                beskar_services::GithubService::fetch_github_profile_and_contributions(
                                    &user_clone,
                                )
                                .await
                            })
                            .await;
                        let _ = this.update(cx, |this, cx| {
                            this.github_state = state;
                            cx.notify();
                        });
                    }
                    DashboardMsg::RefreshUpdates => {
                        let state = cx
                            .background_executor()
                            .spawn(async move {
                                beskar_services::UpdateService::check_system_updates().await
                            })
                            .await;
                        let _ = this.update(cx, |this, cx| {
                            this.updates_state = state;
                            cx.notify();
                        });
                    }
                    DashboardMsg::RunUpdate => {
                        cx.background_executor()
                            .spawn(async move {
                                beskar_services::UpdateService::run_system_update();
                            })
                            .detach();
                    }
                    DashboardMsg::OpenProfile => {
                        let _ = std::process::Command::new("xdg-open")
                            .arg("https://github.com")
                            .spawn();
                    }
                    DashboardMsg::Close => {
                        let _ = this.update(cx, |_, cx| {
                            PanelHost::close(cx);
                        });
                    }
                }
            }
        })
        .detach();

        Self {
            github_state,
            updates_state,
            focus_handle,
            msg_tx,
        }
    }
}

impl Focusable for DashboardView {
    fn focus_handle(&self, _cx: &App) -> FocusHandle {
        self.focus_handle.clone()
    }
}

impl Render for DashboardView {
    fn render(&mut self, _window: &mut Window, cx: &mut Context<Self>) -> impl IntoElement {
        let tx_gh = self.msg_tx.clone();
        let tx_up = self.msg_tx.clone();
        let tx_run = self.msg_tx.clone();
        let tx_prof = self.msg_tx.clone();
        let tx_close = self.msg_tx.clone();

        div()
            .id("dashboard-backdrop")
            .size_full()
            .flex()
            .flex_col()
            .items_center()
            .pt(px(60.0))
            .track_focus(&self.focus_handle)
            .key_context("DashboardView")
            .on_mouse_down(MouseButton::Left, move |_, window, _cx| {
                PanelHost::forget(DashboardView::ID);
                window.remove_window();
            })
            .on_key_down(cx.listener(|_this, event: &KeyDownEvent, window, cx| {
                if event.keystroke.key == "escape" {
                    PanelHost::forget(DashboardView::ID);
                    window.remove_window();
                    cx.stop_propagation();
                }
            }))
            .child(
                div()
                    .id("dashboard-card-wrapper")
                    .max_h(px(740.0))
                    .overflow_y_scroll()
                    .pb(px(8.0))
                    .on_mouse_down(MouseButton::Left, |_, _, cx| {
                        cx.stop_propagation();
                    })
                    .child(
                        DashboardWidget::new(self.github_state.clone(), self.updates_state.clone())
                            .on_refresh_github(move || {
                                let _ = tx_gh.send(DashboardMsg::RefreshGithub);
                            })
                            .on_refresh_updates(move || {
                                let _ = tx_up.send(DashboardMsg::RefreshUpdates);
                            })
                            .on_run_update(move || {
                                let _ = tx_run.send(DashboardMsg::RunUpdate);
                            })
                            .on_open_profile(move || {
                                let _ = tx_prof.send(DashboardMsg::OpenProfile);
                            })
                            .on_close(move || {
                                let _ = tx_close.send(DashboardMsg::Close);
                            }),
                    ),
            )
    }
}
