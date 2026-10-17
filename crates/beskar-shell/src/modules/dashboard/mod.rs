pub mod navigation;
pub mod widgets;

use std::sync::Arc;
use std::time::Duration;

use gpui_kit::prelude::*;
use gpui_kit::*;

use crate::panel_host::{PanelEdge, PanelHost, PanelModule, Slot};
use beskar_services::github::{ContributionDay, GithubService, GithubState};
use beskar_services::vitals::{VitalsService, VitalsSnapshot};
use beskar_theme::Theme;

pub use self::navigation::Navigation;
use self::widgets::*;

#[derive(Debug, Clone)]
pub enum DashboardMsg {
    RefreshGithub,
    HoverDay(Option<ContributionDay>),
    OpenPr(String),
    Close,
}

pub struct DashboardView {
    pub github_state: GithubState,
    pub vitals: VitalsSnapshot,
    pub streak_stats: GitStreakStats,
    pub active_prs: Vec<DevPullRequest>,
    pub active_repos: Vec<DevRepoStatus>,
    pub hovered_day: Option<ContributionDay>,
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
        Size::new(px(460.0), px(740.0))
    }

    fn build(cx: &mut Context<Self>) -> Self {
        Self::new(cx)
    }
}

impl DashboardView {
    pub fn new(cx: &mut Context<Self>) -> Self {
        let focus_handle = cx.focus_handle();
        let (msg_tx, mut msg_rx) = tokio::sync::mpsc::unbounded_channel::<DashboardMsg>();

        let initial_github = GithubService::get_or_load("nsp");
        let initial_streaks = calculate_streaks(&initial_github.contributions);
        let initial_vitals = VitalsService::global().snapshot();

        let initial_prs = vec![
            DevPullRequest {
                number: 142,
                title: "feat(shell): unified omni-launcher with math engine".to_string(),
                repo: "beskar".to_string(),
                status: "Open",
                url: "https://github.com/beskar-shell/beskar/pull/142".to_string(),
            },
            DevPullRequest {
                number: 89,
                title: "fix(bar): fractional scaling & Wayland subsurface clipping".to_string(),
                repo: "beskar".to_string(),
                status: "Review",
                url: "https://github.com/beskar-shell/beskar/pull/89".to_string(),
            },
            DevPullRequest {
                number: 31,
                title: "perf(gpui): zero-copy layer-shell surface buffers".to_string(),
                repo: "gpui-kit".to_string(),
                status: "Approved",
                url: "https://github.com/gpui-kit/gpui-kit/pull/31".to_string(),
            },
        ];

        let initial_repos = vec![
            DevRepoStatus {
                name: "beskar".to_string(),
                path: "~/Documents/p/beskar".to_string(),
                branch: "main".to_string(),
                is_dirty: true,
                modified_count: 3,
            },
            DevRepoStatus {
                name: "gpui-kit".to_string(),
                path: "~/Documents/p/gpui-kit".to_string(),
                branch: "main".to_string(),
                is_dirty: false,
                modified_count: 0,
            },
        ];

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
                            let fresh = GithubService::fetch_github_profile_and_contributions("nsp").await;
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
                    DashboardMsg::OpenPr(url) => {
                        tokio::spawn(async move {
                            let _ = tokio::process::Command::new("xdg-open")
                                .arg(&url)
                                .spawn();
                        });
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

        // 1-second system vitals polling loop
        cx.spawn(async move |this, cx| {
            loop {
                tokio::time::sleep(Duration::from_millis(1000)).await;
                let current_vitals = VitalsService::global().snapshot();
                let res = this.update(cx, |this, cx| {
                    this.vitals = current_vitals;
                    cx.notify();
                });
                if res.is_err() {
                    break;
                }
            }
        })
        .detach();

        Self {
            github_state: initial_github,
            vitals: initial_vitals,
            streak_stats: initial_streaks,
            active_prs: initial_prs,
            active_repos: initial_repos,
            hovered_day: None,
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
        let tx_pr = tx;

        let on_refresh = Arc::new(move || {
            let _ = tx_refresh.send(DashboardMsg::RefreshGithub);
        });

        let on_close = Arc::new(move || {
            let _ = tx_close.send(DashboardMsg::Close);
        });

        let on_hover_day = Arc::new(move |day: Option<ContributionDay>| {
            let _ = tx_hover.send(DashboardMsg::HoverDay(day));
        });

        let on_open_pr = Arc::new(move |url: String| {
            let _ = tx_pr.send(DashboardMsg::OpenPr(url));
        });

        div()
            .id("dashboard-outer")
            .w(px(460.0))
            .max_h(px(740.0))
            .overflow_y_scroll()
            .p(px(14.0))
            .rounded_l_none()
            .rounded_r(px(24.0))
            .bg(Theme::card_bg())
            .border_1()
            .border_l(px(0.0))
            .border_color(Theme::card_border())
            .shadow_xl()
            .flex()
            .flex_col()
            .gap(px(10.0))
            .track_focus(&self.focus_handle)
            .key_context("Dashboard")
            .on_key_down(cx.listener(|_this, event: &KeyDownEvent, _window, cx| {
                if event.keystroke.key == "escape" {
                    PanelHost::close(cx);
                    cx.stop_propagation();
                }
            }))
            .child(render_header(
                &self.github_state.profile,
                self.github_state.is_fetching,
                on_refresh,
                on_close,
            ))
            .child(render_streak_metrics(&self.streak_stats))
            .child(render_heatmap_grid(
                &self.github_state.contributions,
                self.hovered_day.as_ref(),
                on_hover_day,
            ))
            .child(render_active_prs(&self.active_prs, on_open_pr))
            .child(render_system_vitals(&self.vitals))
            .child(render_active_repos(&self.active_repos))
    }
}
