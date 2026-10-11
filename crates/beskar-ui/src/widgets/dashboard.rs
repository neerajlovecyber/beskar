use beskar_services::github::{ContributionDay, GithubProfile, GithubState};
use beskar_services::updates::SystemUpdatesState;
use gpui_kit::assets::IconName;
use gpui_kit::component::Icon;
use gpui_kit::prelude::FluentBuilder;
use gpui_kit::*;
use std::sync::Arc;

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
                    .border_color(hsla(0.0, 0.0, 1.0, 0.08))
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
                                    .bg(hsla(45.0 / 360.0, 0.90, 0.55, 0.20))
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
                                    div()
                                        .w(px(28.0))
                                        .h(px(28.0))
                                        .rounded_md()
                                        .flex()
                                        .items_center()
                                        .justify_center()
                                        .bg(beskar_theme::Theme::bg_secondary())
                                        .text_color(beskar_theme::Theme::muted())
                                        .hover(|s| s.bg(hsla(0.0, 0.8, 0.5, 0.25)).text_color(hsla(0.0, 0.9, 0.7, 1.0)).cursor_pointer())
                                        .on_mouse_down(MouseButton::Left, move |_, _, _| (cb)())
                                        .child(Icon::new(IconName::X).size(px(14.0))),
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

/// Profile Card with avatar, rotating ring indicator, and statistics
fn render_profile_card(
    profile: &GithubProfile,
    is_fetching: bool,
    on_refresh: Option<Arc<dyn Fn() + Send + Sync>>,
    on_open: Option<Arc<dyn Fn() + Send + Sync>>,
) -> impl IntoElement {
    let top_repo = profile.top_repo_name.clone();
    let top_desc = profile.top_repo_desc.clone();
    let top_stars = profile.top_repo_stars;
    let top_lang = profile.top_repo_lang.clone();

    div()
        .w(px(320.0))
        .flex()
        .flex_col()
        .gap(px(12.0))
        .p(px(14.0))
        .rounded(px(16.0))
        .bg(beskar_theme::Theme::bg_secondary())
        .border_1()
        .border_color(hsla(0.0, 0.0, 1.0, 0.06))
        // Avatar + Name Header
        .child(
            div()
                .flex()
                .items_center()
                .gap(px(12.0))
                // Circular Avatar with Gradient Ring
                .child(
                    div()
                        .w(px(52.0))
                        .h(px(52.0))
                        .rounded_full()
                        .p(px(2.0))
                        .bg(if is_fetching {
                            hsla(45.0 / 360.0, 0.95, 0.55, 1.0)
                        } else {
                            hsla(210.0 / 360.0, 0.85, 0.55, 0.80)
                        })
                        .flex()
                        .items_center()
                        .justify_center()
                        .child(
                            div()
                                .w_full()
                                .h_full()
                                .rounded_full()
                                .bg(hsla(220.0 / 360.0, 0.30, 0.12, 1.0))
                                .flex()
                                .items_center()
                                .justify_center()
                                .text_color(beskar_theme::Theme::accent())
                                .child(Icon::new(IconName::Github).size(px(26.0))),
                        ),
                )
                .child(
                    div()
                        .flex()
                        .flex_col()
                        .flex_1()
                        .child(
                            div()
                                .text_sm()
                                .font_weight(FontWeight::BOLD)
                                .text_color(beskar_theme::Theme::fg())
                                .child(profile.name.clone()),
                        )
                        .child(
                            div()
                                .text_xs()
                                .text_color(beskar_theme::Theme::accent())
                                .child(format!("@{}", profile.username)),
                        )
                        .child(
                            div()
                                .text_xs()
                                .text_color(beskar_theme::Theme::muted())
                                .child(profile.bio.clone()),
                        ),
                ),
        )
        // Profile Stats Counters (Repos, Followers, Stars, Forks)
        .child(
            div()
                .flex()
                .items_center()
                .justify_between()
                .px(px(8.0))
                .py(px(8.0))
                .rounded_lg()
                .bg(hsla(0.0, 0.0, 0.0, 0.25))
                .child(stat_pill("Repos", profile.public_repos.to_string()))
                .child(stat_pill("Followers", profile.followers.to_string()))
                .child(stat_pill("Stars", profile.total_stars.to_string()))
                .child(stat_pill("Forks", profile.total_forks.to_string())),
        )
        // Top Repository Showcase Card
        .child(
            div()
                .flex()
                .flex_col()
                .gap(px(4.0))
                .p(px(10.0))
                .rounded_lg()
                .bg(hsla(0.0, 0.0, 1.0, 0.04))
                .border_1()
                .border_color(hsla(0.0, 0.0, 1.0, 0.06))
                .child(
                    div()
                        .flex()
                        .items_center()
                        .justify_between()
                        .child(
                            div()
                                .flex()
                                .items_center()
                                .gap(px(6.0))
                                .child(Icon::new(IconName::FolderGit2).size(px(12.0)).text_color(beskar_theme::Theme::accent()))
                                .child(
                                    div()
                                        .text_xs()
                                        .font_weight(FontWeight::SEMIBOLD)
                                        .text_color(beskar_theme::Theme::fg())
                                        .child(top_repo),
                                ),
                        )
                        .child(
                            div()
                                .flex()
                                .items_center()
                                .gap(px(3.0))
                                .text_color(beskar_theme::Theme::accent())
                                .child(Icon::new(IconName::Star).size(px(10.0)))
                                .child(
                                    div()
                                        .text_xs()
                                        .child(top_stars.to_string()),
                                ),
                        ),
                )
                .child(
                    div()
                        .text_xs()
                        .text_color(beskar_theme::Theme::muted())
                        .child(top_desc),
                )
                .child(
                    div()
                        .flex()
                        .items_center()
                        .gap(px(4.0))
                        .pt(px(2.0))
                        .child(
                            div()
                                .w(px(6.0))
                                .h(px(6.0))
                                .rounded_full()
                                .bg(beskar_theme::Theme::accent()),
                        )
                        .child(
                            div()
                                .text_xs()
                                .text_color(hsla(0.0, 0.0, 0.75, 1.0))
                                .child(top_lang),
                        ),
                ),
        )
        // Profile Action Buttons
        .child(
            div()
                .flex()
                .items_center()
                .gap(px(8.0))
                .pt(px(4.0))
                .child(
                    div()
                        .flex_1()
                        .h(px(28.0))
                        .rounded_md()
                        .bg(beskar_theme::Theme::accent())
                        .text_color(hsla(0.0, 0.0, 0.1, 1.0))
                        .flex()
                        .items_center()
                        .justify_center()
                        .gap(px(6.0))
                        .text_xs()
                        .font_weight(FontWeight::BOLD)
                        .hover(|s| s.bg(hsla(45.0 / 360.0, 1.0, 0.65, 1.0)).cursor_pointer())
                        .when_some(on_open, |el, cb| {
                            el.on_mouse_down(MouseButton::Left, move |_, _, _| (cb)())
                        })
                        .child(Icon::new(IconName::ExternalLink).size(px(12.0)))
                        .child("GitHub Profile"),
                )
                .child(
                    div()
                        .w(px(28.0))
                        .h(px(28.0))
                        .rounded_md()
                        .bg(beskar_theme::Theme::bg_secondary())
                        .text_color(beskar_theme::Theme::muted())
                        .flex()
                        .items_center()
                        .justify_center()
                        .hover(|s| s.bg(hsla(0.0, 0.0, 1.0, 0.12)).text_color(beskar_theme::Theme::fg()).cursor_pointer())
                        .when_some(on_refresh, |el, cb| {
                            el.on_mouse_down(MouseButton::Left, move |_, _, _| (cb)())
                        })
                        .child(Icon::new(IconName::RefreshCw).size(px(12.0))),
                ),
        )
}

fn stat_pill(label: &'static str, value: String) -> impl IntoElement {
    div()
        .flex()
        .flex_col()
        .items_center()
        .child(
            div()
                .text_xs()
                .font_weight(FontWeight::BOLD)
                .text_color(beskar_theme::Theme::fg())
                .child(value),
        )
        .child(
            div()
                .text_xs()
                .text_color(beskar_theme::Theme::muted())
                .child(label),
        )
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
        .border_color(hsla(0.0, 0.0, 1.0, 0.06))
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
                            hsla(140.0 / 360.0, 0.75, 0.50, 1.0)
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
                        .child(
                            div()
                                .px(px(6.0))
                                .py(px(2.0))
                                .rounded_full()
                                .bg(if has_updates {
                                    hsla(45.0 / 360.0, 0.90, 0.50, 0.20)
                                } else {
                                    hsla(140.0 / 360.0, 0.75, 0.40, 0.20)
                                })
                                .text_xs()
                                .font_weight(FontWeight::SEMIBOLD)
                                .text_color(if has_updates {
                                    beskar_theme::Theme::accent()
                                } else {
                                    hsla(140.0 / 360.0, 0.85, 0.60, 1.0)
                                })
                                .child(if has_updates {
                                    format!("{} Pending", total)
                                } else {
                                    "Up to date".to_string()
                                }),
                        )
                        .when_some(on_refresh, |el, cb| {
                            el.child(
                                div()
                                    .w(px(22.0))
                                    .h(px(22.0))
                                    .rounded_md()
                                    .flex()
                                    .items_center()
                                    .justify_center()
                                    .hover(|s| s.bg(hsla(0.0, 0.0, 1.0, 0.12)).cursor_pointer())
                                    .on_mouse_down(MouseButton::Left, move |_, _, _| (cb)())
                                    .child(Icon::new(IconName::RefreshCw).size(px(10.0))),
                            )
                        }),
                ),
        )
        .child(
            div()
                .flex()
                .items_center()
                .justify_between()
                .child(
                    div()
                        .flex()
                        .items_center()
                        .gap(px(12.0))
                        .child(
                            div()
                                .text_xs()
                                .text_color(hsla(0.0, 0.0, 0.75, 1.0))
                                .child(format!("Pacman: {}", up.pacman_count)),
                        )
                        .child(
                            div()
                                .text_xs()
                                .text_color(hsla(0.0, 0.0, 0.75, 1.0))
                                .child(format!("AUR: {}", up.aur_count)),
                        ),
                )
                .when_some(on_run_update, |el, cb| {
                    el.child(
                        div()
                            .px(px(8.0))
                            .py(px(4.0))
                            .rounded_md()
                            .bg(hsla(0.0, 0.0, 1.0, 0.08))
                            .text_xs()
                            .font_weight(FontWeight::MEDIUM)
                            .text_color(beskar_theme::Theme::fg())
                            .hover(|s| s.bg(beskar_theme::Theme::accent()).text_color(hsla(0.0, 0.0, 0.1, 1.0)).cursor_pointer())
                            .on_mouse_down(MouseButton::Left, move |_, _, _| (cb)())
                            .child("Upgrade Now"),
                    )
                }),
        )
}

/// Motivational developer quote card
fn render_quote_card() -> impl IntoElement {
    div()
        .flex()
        .flex_col()
        .gap(px(6.0))
        .p(px(12.0))
        .rounded(px(14.0))
        .bg(beskar_theme::Theme::bg_secondary())
        .border_1()
        .border_color(hsla(0.0, 0.0, 1.0, 0.06))
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
                .text_color(hsla(0.0, 0.0, 0.80, 1.0))
                .child("\"Simplicity is prerequisite for reliability.\""),
        )
        .child(
            div()
                .text_xs()
                .text_color(beskar_theme::Theme::muted())
                .child("— Edsger W. Dijkstra"),
        )
}

/// 52-Week GitHub Heatmap Grid matching GithubContributionsWidget.qml
fn render_contributions_heatmap(
    username: &str,
    contributions: &[ContributionDay],
) -> impl IntoElement {
    let total_sum: u32 = contributions.iter().map(|c| c.count).sum();
    let column_count = contributions.len().div_ceil(7);

    div()
        .flex()
        .flex_col()
        .gap(px(10.0))
        .p(px(14.0))
        .rounded(px(16.0))
        .bg(beskar_theme::Theme::bg_secondary())
        .border_1()
        .border_color(hsla(0.0, 0.0, 1.0, 0.06))
        // Heatmap Header
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
                        .child(Icon::new(IconName::Activity).size(px(16.0)).text_color(beskar_theme::Theme::accent()))
                        .child(
                            div()
                                .text_xs()
                                .font_weight(FontWeight::BOLD)
                                .text_color(beskar_theme::Theme::fg())
                                .child("Contribution Activity"),
                        )
                        .child(
                            div()
                                .text_xs()
                                .text_color(beskar_theme::Theme::muted())
                                .child(format!("({} in the last year)", total_sum)),
                        ),
                )
                .child(
                    div()
                        .text_xs()
                        .text_color(beskar_theme::Theme::accent())
                        .child(format!("github.com/{}", username)),
                ),
        )
        // 52-Week Grid of 7 rows
        .child(
            div()
                .flex()
                .gap(px(3.0))
                .overflow_x_hidden()
                .children((0..column_count).map(|col_idx| {
                    div()
                        .flex()
                        .flex_col()
                        .gap(px(3.0))
                        .children((0..7).map(move |row_idx| {
                            let idx = col_idx * 7 + row_idx;
                            let level = if idx < contributions.len() {
                                contributions[idx].level
                            } else {
                                0
                            };
                            let cell_color = match level {
                                0 => hsla(220.0 / 360.0, 0.15, 0.16, 0.60),
                                1 => hsla(140.0 / 360.0, 0.65, 0.32, 0.90),
                                2 => hsla(140.0 / 360.0, 0.75, 0.45, 0.95),
                                3 => hsla(140.0 / 360.0, 0.85, 0.58, 1.00),
                                _ => hsla(140.0 / 360.0, 0.95, 0.70, 1.00),
                            };

                            div()
                                .w(px(10.0))
                                .h(px(10.0))
                                .rounded_xs()
                                .bg(cell_color)
                                .hover(move |s| {
                                    s.border_1()
                                        .border_color(hsla(0.0, 0.0, 1.0, 0.9))
                                        .cursor_pointer()
                                })
                        }))
                })),
        )
        // Heatmap Legend (Less -> Swatches -> More)
        .child(
            div()
                .flex()
                .items_center()
                .justify_end()
                .gap(px(4.0))
                .child(
                    div()
                        .text_xs()
                        .text_color(beskar_theme::Theme::muted())
                        .child("Less"),
                )
                .child(swatch(hsla(220.0 / 360.0, 0.15, 0.16, 0.60)))
                .child(swatch(hsla(140.0 / 360.0, 0.65, 0.32, 0.90)))
                .child(swatch(hsla(140.0 / 360.0, 0.75, 0.45, 0.95)))
                .child(swatch(hsla(140.0 / 360.0, 0.85, 0.58, 1.00)))
                .child(swatch(hsla(140.0 / 360.0, 0.95, 0.70, 1.00)))
                .child(
                    div()
                        .text_xs()
                        .text_color(beskar_theme::Theme::muted())
                        .child("More"),
                ),
        )
}

fn swatch(color: Hsla) -> impl IntoElement {
    div()
        .w(px(8.0))
        .h(px(8.0))
        .rounded_xs()
        .bg(color)
}
