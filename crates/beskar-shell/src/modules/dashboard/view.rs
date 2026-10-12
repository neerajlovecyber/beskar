use std::sync::Arc;

use beskar_services::github::GithubState;
use beskar_services::updates::SystemUpdatesState;
use gpui_kit::assets::IconName;
use gpui_kit::component::button::{Button, ButtonVariants};
use gpui_kit::component::tag::Tag;
use gpui_kit::component::Icon;
use gpui_kit::prelude::FluentBuilder;
use gpui_kit::*;

use super::heatmap::render_contributions_heatmap;
use super::profile::render_profile_card;

/// Developer Dashboard Widget featuring:
/// - 52-week (364-cell) GitHub contribution heatmap grid with tonal levels
/// - GitHub profile card with animated avatar gradient ring, repo stats, follower counters
/// - Pacman / AUR system update tracker
/// - Daily developer quote card
#[derive(IntoElement)]
pub struct DashboardWidget {
    github_state: GithubState,
    updates_state: SystemUpdatesState,
    on_refresh_github: Option<Arc<dyn Fn() + Send + Sync>>,
    on_refresh_updates: Option<Arc<dyn Fn() + Send + Sync>>,
    on_run_update: Option<Arc<dyn Fn() + Send + Sync>>,
    on_open_profile: Option<Arc<dyn Fn() + Send + Sync>>,
    on_close: Option<Arc<dyn Fn() + Send + Sync>>,
}

impl DashboardWidget {
    pub fn new(github_state: GithubState, updates_state: SystemUpdatesState) -> Self {
        Self {
            github_state,
            updates_state,
            on_refresh_github: None,
            on_refresh_updates: None,
            on_run_update: None,
            on_open_profile: None,
            on_close: None,
        }
    }

    pub fn on_refresh_github(mut self, handler: impl Fn() + Send + Sync + 'static) -> Self {
        self.on_refresh_github = Some(Arc::new(handler));
        self
    }

    pub fn on_refresh_updates(mut self, handler: impl Fn() + Send + Sync + 'static) -> Self {
        self.on_refresh_updates = Some(Arc::new(handler));
        self
    }

    pub fn on_run_update(mut self, handler: impl Fn() + Send + Sync + 'static) -> Self {
        self.on_run_update = Some(Arc::new(handler));
        self
    }

    pub fn on_open_profile(mut self, handler: impl Fn() + Send + Sync + 'static) -> Self {
        self.on_open_profile = Some(Arc::new(handler));
        self
    }

    pub fn on_close(mut self, handler: impl Fn() + Send + Sync + 'static) -> Self {
        self.on_close = Some(Arc::new(handler));
        self
    }
}

impl RenderOnce for DashboardWidget {
    fn render(self, _window: &mut Window, _cx: &mut App) -> impl IntoElement {
        let gh = self.github_state;
        let up = self.updates_state;
        let profile = gh.profile;
        let contributions = gh.contributions;
        let is_fetching = gh.is_fetching;

        let on_refresh_gh = self.on_refresh_github;
        let on_refresh_up = self.on_refresh_updates;
        let on_run_up = self.on_run_update;
        let on_open_prof = self.on_open_profile;
        let on_close = self.on_close;

        div()
            .w(px(780.0))
            .flex()
            .flex_col()
            .gap(px(16.0))
            .p(px(20.0))
            .rounded(px(22.0))
            .bg(beskar_theme::Theme::bg())
            .border_1()
            .border_color(beskar_theme::Theme::border())
            .shadow_lg()
            // 1. Dashboard Header
            .child(
                div()
                    .flex()
                    .items_center()
                    .justify_between()
                    .pb(px(12.0))
                    .border_b_1()
                    .border_color(beskar_theme::Theme::subtle_border())
                    .child(
                        div()
                            .flex()
                            .items_center()
                            .gap(px(10.0))
                            .child(
                                div()
                                    .w(px(32.0))
                                    .h(px(32.0))
                                    .rounded_lg()
                                    .bg(beskar_theme::Theme::accent_alpha(0.20))
                                    .flex()
                                    .items_center()
                                    .justify_center()
                                    .text_color(beskar_theme::Theme::accent())
                                    .child(Icon::new(IconName::LayoutDashboard).size(px(18.0))),
                            )
                            .child(
                                div()
                                    .flex()
                                    .flex_col()
                                    .child(
                                        div()
                                            .text_sm()
                                            .font_weight(FontWeight::BOLD)
                                            .text_color(beskar_theme::Theme::fg())
                                            .child("Developer Dashboard"),
                                    )
                                    .child(
                                        div()
                                            .text_xs()
                                            .text_color(beskar_theme::Theme::muted())
                                            .child("System Vitals, GitHub Activity & Workspaces"),
                                    ),
                            ),
                    )
                    .child(
                        div()
                            .flex()
                            .items_center()
                            .gap(px(8.0))
                            .when_some(on_close, |el, cb| {
                                el.child(
                                    Button::new("dash-close")
                                        .ghost()
                                        .compact()
                                        .icon(Icon::new(IconName::X).size(px(14.0)))
                                        .on_click(move |_, _, _| (cb)()),
                                )
                            }),
                    ),
            )
            // 2. Middle Row: Left Profile + Right Updates & Quotes
            .child(
                div()
                    .flex()
                    .gap(px(16.0))
                    // Left: GitHub Profile Card
                    .child(
                        render_profile_card(&profile, is_fetching, on_refresh_gh, on_open_prof)
                    )
                    // Right: System Updates Card + Quote Card
                    .child(
                        div()
                            .flex()
                            .flex_col()
                            .flex_1()
                            .gap(px(12.0))
                            .child(render_updates_card(&up, on_refresh_up, on_run_up))
                            .child(render_quote_card()),
                    ),
            )
            // 3. Bottom: 52-Week GitHub Heatmap Chart
            .child(
                render_contributions_heatmap(&profile.username, &contributions)
            )
    }
}

/// Updates Card matching Minflair's UpdatesCard.qml
fn render_updates_card(
    up: &SystemUpdatesState,
    on_refresh: Option<Arc<dyn Fn() + Send + Sync>>,
    on_run_update: Option<Arc<dyn Fn() + Send + Sync>>,
) -> impl IntoElement {
    let total = up.pacman_count + up.aur_count;
    let has_updates = total > 0;

    div()
        .flex()
        .flex_col()
        .gap(px(8.0))
        .p(px(12.0))
        .rounded(px(14.0))
        .bg(beskar_theme::Theme::bg_secondary())
        .border_1()
        .border_color(beskar_theme::Theme::card_border())
        .child(
            div()
                .flex()
                .items_center()
                .justify_between()
                .child(
                    div()
                        .flex()
                        .items_center()
                        .gap(px(8.0))
                        .child(Icon::new(IconName::PackageCheck).size(px(16.0)).text_color(if has_updates {
                            beskar_theme::Theme::accent()
                        } else {
                            beskar_theme::Theme::success()
                        }))
                        .child(
                            div()
                                .text_xs()
                                .font_weight(FontWeight::BOLD)
                                .text_color(beskar_theme::Theme::fg())
                                .child("System Updates"),
                        ),
                )
                .child(
                    div()
                        .flex()
                        .items_center()
                        .gap(px(6.0))
                        .child(Tag::secondary().child(if has_updates {
                            format!("{} Pending", total)
                        } else {
                            "Up to date".to_string()
                        }))
                        .when_some(on_refresh, |el, cb| {
                            el.child(
                                Button::new("dash-up-refresh")
                                    .ghost()
                                    .compact()
                                    .icon(Icon::new(IconName::RefreshCw).size(px(12.0)))
                                    .on_click(move |_, _, _| (cb)()),
                            )
                        }),
                ),
        )
        // Detail row (Pacman / AUR breakdown)
        .child(
            div()
                .flex()
                .items_center()
                .justify_between()
                .text_xs()
                .text_color(beskar_theme::Theme::muted())
                .child(format!("Repo: {} • AUR: {}", up.pacman_count, up.aur_count))
                .child(
                    div()
                        .flex()
                        .items_center()
                        .gap(px(4.0))
                        .child(
                            div()
                                .w(px(6.0))
                                .h(px(6.0))
                                .rounded_full()
                                .bg(if up.is_checking {
                                    beskar_theme::Theme::accent()
                                } else if has_updates {
                                    beskar_theme::Theme::warning()
                                } else {
                                    beskar_theme::Theme::success()
                                }),
                        )
                        .child(if up.is_checking {
                            "Checking..."
                        } else if has_updates {
                            "Updates available"
                        } else {
                            "System fresh"
                        }),
                ),
        )
        // Action: Run updates button if available
        .when(has_updates, |el| {
            el.child(
                Button::new("dash-run-up")
                    .primary()
                    .compact()
                    .label(format!("Update All ({})", total))
                    .icon(Icon::new(IconName::Download).size(px(12.0)))
                    .when_some(on_run_update, |btn, cb| {
                        btn.on_click(move |_, _, _| (cb)())
                    }),
            )
        })
}

/// Developer Quote Card matching Minflair's QuoteCard.qml
fn render_quote_card() -> impl IntoElement {
    div()
        .flex()
        .flex_col()
        .gap(px(6.0))
        .p(px(12.0))
        .rounded(px(14.0))
        .bg(beskar_theme::Theme::bg_secondary())
        .border_1()
        .border_color(beskar_theme::Theme::card_border())
        .child(
            div()
                .flex()
                .items_center()
                .gap(px(6.0))
                .child(Icon::new(IconName::Quote).size(px(14.0)).text_color(beskar_theme::Theme::accent()))
                .child(
                    div()
                        .text_xs()
                        .font_weight(FontWeight::BOLD)
                        .text_color(beskar_theme::Theme::fg())
                        .child("Quote of the Day"),
                ),
        )
        .child(
            div()
                .text_xs()
                .italic()
                .text_color(beskar_theme::Theme::fg())
                .child("\"Simplicity is prerequisite for reliability.\""),
        )
        .child(
            div()
                .text_xs()
                .text_color(beskar_theme::Theme::muted())
                .child("— Edsger W. Dijkstra"),
        )
}
