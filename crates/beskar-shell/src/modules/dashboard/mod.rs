pub mod navigation;
pub mod widgets;

use std::sync::Arc;

use gpui_kit::prelude::*;
use gpui_kit::*;

use crate::panel_host::{PanelEdge, PanelHost, PanelModule, Slot};
use beskar_services::github::{ContributionDay, GithubService, GithubState};
use beskar_services::updates::{SystemUpdatesState, UpdateService};

pub use self::navigation::Navigation;
use self::widgets::*;

#[derive(Debug, Clone)]
pub enum DashboardMsg {
    RefreshGithub,
    HoverDay(Option<ContributionDay>),
    RunUpdate,
    Close,
}

pub struct DashboardView {
    pub github_state: GithubState,
    pub streak_stats: GitStreakStats,
    pub updates_state: SystemUpdatesState,
    pub hovered_day: Option<ContributionDay>,
    pub quote: (&'static str, &'static str),
    focus_handle: FocusHandle,
    msg_tx: tokio::sync::mpsc::UnboundedSender<DashboardMsg>,
}

impl PanelModule for DashboardView {
    const ID: &'static str = "dashboard";

    fn slot() -> Slot {
        Slot::Left
    }

    fn panel_edge() -> PanelEdge {
        PanelEdge::Left
    }

    fn size() -> Size<Pixels> {
        Size::new(px(440.0), px(540.0))
    }

    fn build(cx: &mut Context<Self>) -> Self {
        Self::new(cx)
    }

    fn initial_focus_handle(&self, cx: &App) -> Option<FocusHandle> {
        Some(Focusable::focus_handle(self, cx))
    }
}

impl DashboardView {
    pub fn new(cx: &mut Context<Self>) -> Self {
        let focus_handle = cx.focus_handle();
        let (msg_tx, mut msg_rx) = tokio::sync::mpsc::unbounded_channel::<DashboardMsg>();

        let initial_github = GithubService::get_or_load("nsp");
        let initial_streaks = calculate_streaks(&initial_github.contributions);
        let initial_updates = UpdateService::cached();

        // Message dispatcher loop
        cx.spawn(async move |this, cx| {
            while let Some(msg) = msg_rx.recv().await {
                match msg {
                    DashboardMsg::RefreshGithub => {
                        let _ = this.update(cx, |this, cx| {
                            this.github_state.is_fetching = true;
                            cx.notify();
                        });
                        let this_weak = this.clone();
                        cx.spawn(async move |cx| {
                            let fresh =
                                GithubService::fetch_github_profile_and_contributions("nsp").await;
                            let _ = this_weak.update(cx, |this, cx| {
                                this.streak_stats = calculate_streaks(&fresh.contributions);
                                this.github_state = fresh;
                                cx.notify();
                            });
                        })
                        .detach();
                    }
                    DashboardMsg::HoverDay(day) => {
                        let _ = this.update(cx, |this, cx| {
                            this.hovered_day = day;
                            cx.notify();
                        });
                    }
                    DashboardMsg::RunUpdate => {
                        UpdateService::run_system_update();
                    }
                    DashboardMsg::Close => {
                        let _ = this.update(cx, |_, cx| {
                            PanelHost::close_by_id(Self::ID, cx);
                        });
                    }
                }
            }
        })
        .detach();

        // Check system updates once on launch
        cx.spawn(async move |this, cx| {
            let snap = UpdateService::check_system_updates().await;
            let _ = this.update(cx, |this, cx| {
                this.updates_state = snap;
                cx.notify();
            });
        })
        .detach();

        Self {
            github_state: initial_github,
            streak_stats: initial_streaks,
            updates_state: initial_updates,
            hovered_day: None,
            quote: ("Talk is cheap. Show me the code.", "Linus Torvalds"),
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
        let tx = self.msg_tx.clone();
        let tx_refresh = tx.clone();
        let tx_close = tx.clone();
        let tx_hover = tx.clone();
        let tx_update = tx;

        let on_refresh = Arc::new(move || {
            let _ = tx_refresh.send(DashboardMsg::RefreshGithub);
        });

        let on_close = Arc::new(move || {
            let _ = tx_close.send(DashboardMsg::Close);
        });

        let on_hover_day = Arc::new(move |day: Option<ContributionDay>| {
            let _ = tx_hover.send(DashboardMsg::HoverDay(day));
        });

        let on_update = Arc::new(move || {
            let _ = tx_update.send(DashboardMsg::RunUpdate);
        });

        div()
            .id("dashboard-outer")
            .w(px(440.0))
            .max_h(px(540.0))
            .overflow_y_scroll()
            .p(px(14.0))
            .flex()
            .flex_col()
            .gap(px(10.0))
            .track_focus(&self.focus_handle)
            .key_context("Dashboard")
            .on_key_down(cx.listener(|_this, event: &KeyDownEvent, _window, cx| {
                if event.keystroke.key == "escape" {
                    PanelHost::close_by_id(Self::ID, cx);
                    cx.stop_propagation();
                }
            }))
            // 1. User Profile Header with Avatar, name, bio, and 3-row stats
            .child(render_user_profile_header(
                &self.github_state.profile,
                self.github_state.is_fetching,
                on_refresh,
                on_close,
            ))
            // 2. Contributions Card with heatmap grid
            .child(render_heatmap_card(
                &self.github_state.contributions,
                self.hovered_day.as_ref(),
                on_hover_day,
            ))
            // 3. System Updates Card
            .child(render_updates_card(
                &self.updates_state,
                on_update,
            ))
            // 4. Footer Quote
            .child(render_quote_footer(self.quote.0, self.quote.1))
    }
}
