use std::sync::Arc;

use gpui_kit::assets::IconName;
use gpui_kit::component::button::{Button, ButtonVariants};
use gpui_kit::component::Icon;
use gpui_kit::gpui::{
    div, px, AnyElement, FontWeight, InteractiveElement, IntoElement,
    MouseButton, ParentElement, Styled,
};

use beskar_services::github::{ContributionDay, GithubProfile};
use beskar_services::vitals::VitalsSnapshot;
use beskar_theme::Theme;

#[derive(Debug, Clone, Default)]
pub struct GitStreakStats {
    pub total_contributions: u32,
    pub current_streak: u32,
    pub longest_streak: u32,
}

pub fn calculate_streaks(contributions: &[ContributionDay]) -> GitStreakStats {
    if contributions.is_empty() {
        return GitStreakStats::default();
    }
    let total: u32 = contributions.iter().map(|d| d.count).sum();
    let mut current_streak = 0;
    let mut longest_streak = 0;
    let mut current_run = 0;

    for day in contributions {
        if day.count > 0 {
            current_run += 1;
            if current_run > longest_streak {
                longest_streak = current_run;
            }
        } else {
            current_run = 0;
        }
    }

    for day in contributions.iter().rev() {
        if day.count > 0 {
            current_streak += 1;
        } else {
            if current_streak == 0 {
                continue;
            }
            break;
        }
    }

    GitStreakStats {
        total_contributions: total,
        current_streak,
        longest_streak,
    }
}

#[derive(Debug, Clone)]
pub struct DevPullRequest {
    pub number: u32,
    pub title: String,
    pub repo: String,
    pub status: &'static str,
    pub url: String,
}

#[derive(Debug, Clone)]
pub struct DevRepoStatus {
    pub name: String,
    pub path: String,
    pub branch: String,
    pub is_dirty: bool,
    pub modified_count: usize,
}

/// Header containing title, profile info, refresh button, and close button
pub fn render_header(
    profile: &GithubProfile,
    is_fetching: bool,
    on_refresh: Arc<dyn Fn() + Send + Sync>,
    on_close: Arc<dyn Fn() + Send + Sync>,
) -> AnyElement {
    let initials: String = profile
        .name
        .split_whitespace()
        .filter_map(|w| w.chars().next())
        .take(2)
        .collect();
    let initials = if initials.is_empty() {
        "GH".to_string()
    } else {
        initials.to_uppercase()
    };

    div()
        .flex()
        .flex_col()
        .gap(px(10.0))
        .w_full()
        .child(
            // Top action bar
            div()
                .flex()
                .items_center()
                .justify_between()
                .w_full()
                .child(
                    div()
                        .flex()
                        .items_center()
                        .gap(px(8.0))
                        .child(
                            div()
                                .flex()
                                .items_center()
                                .justify_center()
                                .size(px(26.0))
                                .rounded_full()
                                .bg(Theme::accent_alpha(0.15))
                                .child(Icon::new(IconName::Github).size(px(15.0)).text_color(Theme::accent())),
                        )
                        .child(
                            div()
                                .text_sm()
                                .font_weight(FontWeight::BOLD)
                                .text_color(Theme::fg())
                                .child("GITHUB DEV DASHBOARD"),
                        )
                        .child(
                            div()
                                .px(px(6.0))
                                .py(px(1.5))
                                .rounded_full()
                                .bg(Theme::accent_alpha(0.12))
                                .border_1()
                                .border_color(Theme::accent_alpha(0.3))
                                .text_xs()
                                .font_weight(FontWeight::SEMIBOLD)
                                .text_color(Theme::accent())
                                .child("LIVE"),
                        ),
                )
                .child(
                    div()
                        .flex()
                        .items_center()
                        .gap(px(6.0))
                        .child(
                            Button::new("dash-refresh")
                                .ghost()
                                .compact()
                                .icon(Icon::new(IconName::RotateCcw).size(px(13.0)))
                                .on_click(move |_, _, _| (on_refresh)()),
                        )
                        .child(
                            Button::new("dash-close")
                                .ghost()
                                .compact()
                                .icon(Icon::new(IconName::X).size(px(13.0)))
                                .on_click(move |_, _, _| (on_close)()),
                        ),
                ),
        )
        .child(
            // Profile card
            div()
                .flex()
                .items_center()
                .gap(px(12.0))
                .p(px(10.0))
                .rounded(px(12.0))
                .bg(Theme::surface())
                .border_1()
                .border_color(Theme::border())
                .child(
                    div()
                        .size(px(38.0))
                        .rounded_full()
                        .bg(Theme::accent_alpha(0.2))
                        .border_1()
                        .border_color(Theme::accent_alpha(0.4))
                        .flex()
                        .items_center()
                        .justify_center()
                        .text_sm()
                        .font_weight(FontWeight::BOLD)
                        .text_color(Theme::accent())
                        .child(initials),
                )
                .child(
                    div()
                        .flex_1()
                        .min_w_0()
                        .flex()
                        .flex_col()
                        .gap(px(1.0))
                        .child(
                            div()
                                .flex()
                                .items_center()
                                .gap(px(6.0))
                                .child(
                                    div()
                                        .text_sm()
                                        .font_weight(FontWeight::SEMIBOLD)
                                        .text_color(Theme::fg())
                                        .child(profile.name.clone()),
                                )
                                .child(
                                    div()
                                        .text_xs()
                                        .text_color(Theme::foreground_muted())
                                        .child(format!("@{}", profile.username)),
                                ),
                        )
                        .child(
                            div()
                                .text_xs()
                                .text_color(Theme::foreground_muted())
                                .whitespace_nowrap()
                                .text_ellipsis()
                                .child(if is_fetching {
                                    "Updating GitHub telemetry...".to_string()
                                } else {
                                    profile.bio.clone()
                                }),
                        ),
                ),
        )
        .into_any_element()
}

/// Streak & Metric summaries (Total contributions, Current streak, Longest streak)
pub fn render_streak_metrics(stats: &GitStreakStats) -> AnyElement {
    div()
        .flex()
        .items_center()
        .gap(px(8.0))
        .w_full()
        .child(render_metric_card(
            "COMMITS",
            &format!("{}", stats.total_contributions),
            IconName::GitCommitHorizontal,
            Theme::accent(),
        ))
        .child(render_metric_card(
            "CURRENT STREAK",
            &format!("{} days", stats.current_streak),
            IconName::Flame,
            Theme::warning(),
        ))
        .child(render_metric_card(
            "LONGEST STREAK",
            &format!("{} days", stats.longest_streak),
            IconName::Activity,
            Theme::success(),
        ))
        .into_any_element()
}

fn render_metric_card(
    label: &'static str,
    value: &str,
    icon: IconName,
    accent_color: gpui_kit::gpui::Hsla,
) -> AnyElement {
    div()
        .flex_1()
        .p(px(8.0))
        .rounded(px(10.0))
        .bg(Theme::surface())
        .border_1()
        .border_color(Theme::border())
        .flex()
        .flex_col()
        .gap(px(3.0))
        .child(
            div()
                .flex()
                .items_center()
                .justify_between()
                .child(
                    div()
                        .text_xs()
                        .font_weight(FontWeight::MEDIUM)
                        .text_color(Theme::foreground_muted())
                        .child(label),
                )
                .child(Icon::new(icon).size(px(13.0)).text_color(accent_color)),
        )
        .child(
            div()
                .text_sm()
                .font_weight(FontWeight::BOLD)
                .text_color(Theme::fg())
                .child(value.to_string()),
        )
        .into_any_element()
}

/// 52-week Contribution Heatmap Grid
pub fn render_heatmap_grid(
    contributions: &[ContributionDay],
    hovered_day: Option<&ContributionDay>,
    on_hover_day: Arc<dyn Fn(Option<ContributionDay>) + Send + Sync>,
) -> AnyElement {
    let mut weeks: Vec<Vec<ContributionDay>> = Vec::with_capacity(52);
    let mut current_week = Vec::with_capacity(7);

    for day in contributions {
        current_week.push(day.clone());
        if current_week.len() == 7 {
            weeks.push(current_week);
            current_week = Vec::with_capacity(7);
        }
    }
    if !current_week.is_empty() {
        weeks.push(current_week);
    }

    let mut grid_row = div()
        .flex()
        .gap(px(2.0))
        .items_center()
        .justify_start()
        .py(px(4.0));

    for (week_idx, week) in weeks.into_iter().enumerate() {
        let mut col = div().flex().flex_col().gap(px(2.0));
        for (day_idx, day) in week.into_iter().enumerate() {
            let day_clone = day.clone();
            let hover_cb = on_hover_day.clone();
            let bg_color = match day.level {
                0 => Theme::border().opacity(0.35),
                1 => Theme::accent_alpha(0.28),
                2 => Theme::accent_alpha(0.52),
                3 => Theme::accent_alpha(0.78),
                _ => Theme::accent(),
            };

            col = col.child(
                div()
                    .id(("heat-cell", week_idx * 7 + day_idx))
                    .size(px(6.0))
                    .rounded(px(1.5))
                    .bg(bg_color)
                    .cursor_pointer()
                    .hover(|s| s.border_1().border_color(Theme::fg()))
                    .on_mouse_down(MouseButton::Left, {
                        let d = day_clone.clone();
                        let h = hover_cb.clone();
                        move |_, _, _| (h)(Some(d.clone()))
                    }),
            );
        }
        grid_row = grid_row.child(col);
    }

    div()
        .flex()
        .flex_col()
        .gap(px(6.0))
        .p(px(10.0))
        .rounded(px(12.0))
        .bg(Theme::surface())
        .border_1()
        .border_color(Theme::border())
        .child(
            div()
                .flex()
                .items_center()
                .justify_between()
                .w_full()
                .child(
                    div()
                        .text_xs()
                        .font_weight(FontWeight::SEMIBOLD)
                        .text_color(Theme::fg())
                        .child("52-WEEK CONTRIBUTION HEATMAP"),
                )
                .child(
                    // Legend
                    div()
                        .flex()
                        .items_center()
                        .gap(px(3.0))
                        .child(div().text_xs().text_color(Theme::foreground_muted()).child("Less"))
                        .child(div().size(px(6.0)).rounded(px(1.0)).bg(Theme::border().opacity(0.35)))
                        .child(div().size(px(6.0)).rounded(px(1.0)).bg(Theme::accent_alpha(0.28)))
                        .child(div().size(px(6.0)).rounded(px(1.0)).bg(Theme::accent_alpha(0.52)))
                        .child(div().size(px(6.0)).rounded(px(1.0)).bg(Theme::accent_alpha(0.78)))
                        .child(div().size(px(6.0)).rounded(px(1.0)).bg(Theme::accent()))
                        .child(div().text_xs().text_color(Theme::foreground_muted()).child("More")),
                ),
        )
        .child(grid_row)
        .child(
            // Tooltip / Details pill
            div()
                .text_xs()
                .text_color(Theme::foreground_muted())
                .child(if let Some(day) = hovered_day {
                    format!("● {} on {}", day.tooltip, day.date)
                } else {
                    "Click or hover any cell to inspect daily commit distribution.".to_string()
                }),
        )
        .into_any_element()
}

/// Active Pull Requests Section
pub fn render_active_prs(
    prs: &[DevPullRequest],
    on_open_pr: Arc<dyn Fn(String) + Send + Sync>,
) -> AnyElement {
    let mut list = div().flex().flex_col().gap(px(6.0)).w_full();

    for (idx, pr) in prs.iter().enumerate() {
        let pr_url = pr.url.clone();
        let open_cb = on_open_pr.clone();
        let (status_bg, status_fg) = match pr.status {
            "Open" => (Theme::success_alpha(0.15), Theme::success()),
            "Review" => (Theme::warning_alpha(0.15), Theme::warning()),
            _ => (Theme::accent_alpha(0.15), Theme::accent()),
        };

        list = list.child(
            div()
                .id(("pr-item", idx))
                .flex()
                .items_center()
                .justify_between()
                .p(px(7.0))
                .rounded(px(8.0))
                .bg(Theme::bg())
                .border_1()
                .border_color(Theme::border().opacity(0.6))
                .cursor_pointer()
                .hover(|s| s.bg(Theme::surface_hover()).border_color(Theme::accent_alpha(0.4)))
                .on_mouse_down(MouseButton::Left, move |_, _, _| {
                    (open_cb)(pr_url.clone());
                })
                .child(
                    div()
                        .flex_1()
                        .min_w_0()
                        .flex()
                        .items_center()
                        .gap(px(6.0))
                        .child(
                            div()
                                .px(px(5.0))
                                .py(px(1.0))
                                .rounded(px(4.0))
                                .bg(Theme::surface())
                                .text_xs()
                                .font_weight(FontWeight::BOLD)
                                .text_color(Theme::accent())
                                .child(pr.repo.clone()),
                        )
                        .child(
                            div()
                                .text_xs()
                                .text_color(Theme::fg())
                                .whitespace_nowrap()
                                .text_ellipsis()
                                .child(format!("#{} {}", pr.number, pr.title)),
                        ),
                )
                .child(
                    div()
                        .px(px(6.0))
                        .py(px(1.5))
                        .rounded_full()
                        .bg(status_bg)
                        .text_xs()
                        .font_weight(FontWeight::SEMIBOLD)
                        .text_color(status_fg)
                        .child(pr.status),
                ),
        );
    }

    div()
        .flex()
        .flex_col()
        .gap(px(8.0))
        .p(px(10.0))
        .rounded(px(12.0))
        .bg(Theme::surface())
        .border_1()
        .border_color(Theme::border())
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
                        .child(Icon::new(IconName::GitPullRequest).size(px(14.0)).text_color(Theme::accent()))
                        .child(
                            div()
                                .text_xs()
                                .font_weight(FontWeight::SEMIBOLD)
                                .text_color(Theme::fg())
                                .child("ACTIVE PULL REQUESTS"),
                        ),
                )
                .child(
                    div()
                        .text_xs()
                        .font_weight(FontWeight::BOLD)
                        .text_color(Theme::accent())
                        .child(format!("{} active", prs.len())),
                ),
        )
        .child(list)
        .into_any_element()
}

/// System Dev Vitals (CPU, RAM, Storage)
pub fn render_system_vitals(vitals: &VitalsSnapshot) -> AnyElement {
    let cpu_pct = vitals.cpu.global_usage_percent.round().clamp(0.0, 100.0) as u32;
    let ram_pct = vitals.memory.usage_percent.round().clamp(0.0, 100.0) as u32;
    let disk = vitals.disks.first();
    let disk_pct = disk.map(|d| d.usage_percent.round().clamp(0.0, 100.0) as u32).unwrap_or(48);

    div()
        .flex()
        .flex_col()
        .gap(px(8.0))
        .p(px(10.0))
        .rounded(px(12.0))
        .bg(Theme::surface())
        .border_1()
        .border_color(Theme::border())
        .child(
            div()
                .flex()
                .items_center()
                .gap(px(6.0))
                .child(Icon::new(IconName::Cpu).size(px(14.0)).text_color(Theme::accent()))
                .child(
                    div()
                        .text_xs()
                        .font_weight(FontWeight::SEMIBOLD)
                        .text_color(Theme::fg())
                        .child("SYSTEM DEV VITALS"),
                ),
        )
        .child(
            div()
                .flex()
                .items_center()
                .gap(px(8.0))
                .w_full()
                .child(render_vital_bar("CPU", &format!("{}%", cpu_pct), cpu_pct, Theme::accent()))
                .child(render_vital_bar(
                    "RAM",
                    &format!("{}%", ram_pct),
                    ram_pct,
                    Theme::info(),
                ))
                .child(render_vital_bar(
                    "DISK",
                    &format!("{}%", disk_pct),
                    disk_pct,
                    Theme::warning(),
                )),
        )
        .into_any_element()
}

fn render_vital_bar(
    label: &'static str,
    val_str: &str,
    percent: u32,
    bar_color: gpui_kit::gpui::Hsla,
) -> AnyElement {
    div()
        .flex_1()
        .flex()
        .flex_col()
        .gap(px(4.0))
        .p(px(7.0))
        .rounded(px(8.0))
        .bg(Theme::bg())
        .border_1()
        .border_color(Theme::border().opacity(0.6))
        .child(
            div()
                .flex()
                .items_center()
                .justify_between()
                .child(div().text_xs().text_color(Theme::foreground_muted()).child(label))
                .child(div().text_xs().font_weight(FontWeight::BOLD).text_color(Theme::fg()).child(val_str.to_string())),
        )
        .child(
            div()
                .w_full()
                .h(px(4.0))
                .rounded_full()
                .bg(Theme::border())
                .child(
                    div()
                        .h_full()
                        .w(gpui_kit::gpui::relative(percent as f32 / 100.0))
                        .rounded_full()
                        .bg(bar_color),
                ),
        )
        .into_any_element()
}

/// Active Repositories
pub fn render_active_repos(repos: &[DevRepoStatus]) -> AnyElement {
    let mut list = div().flex().flex_col().gap(px(6.0)).w_full();

    for (idx, repo) in repos.iter().enumerate() {
        let (status_icon, status_color, status_text) = if repo.is_dirty {
            (IconName::Sparkles, Theme::warning(), format!("* modified ({} files)", repo.modified_count))
        } else {
            (IconName::Check, Theme::success(), "clean".to_string())
        };

        list = list.child(
            div()
                .id(("repo-item", idx))
                .flex()
                .items_center()
                .justify_between()
                .p(px(7.0))
                .rounded(px(8.0))
                .bg(Theme::bg())
                .border_1()
                .border_color(Theme::border().opacity(0.6))
                .child(
                    div()
                        .flex_1()
                        .min_w_0()
                        .flex()
                        .flex_col()
                        .gap(px(2.0))
                        .child(
                            div()
                                .flex()
                                .items_center()
                                .gap(px(5.0))
                                .child(Icon::new(IconName::Folder).size(px(12.0)).text_color(Theme::accent()))
                                .child(
                                    div()
                                        .text_xs()
                                        .font_weight(FontWeight::SEMIBOLD)
                                        .text_color(Theme::fg())
                                        .child(repo.name.clone()),
                                )
                                .child(
                                    div()
                                        .flex()
                                        .items_center()
                                        .gap(px(3.0))
                                        .child(Icon::new(IconName::GitBranch).size(px(11.0)).text_color(Theme::foreground_muted()))
                                        .child(
                                            div()
                                                .text_xs()
                                                .text_color(Theme::foreground_muted())
                                                .child(repo.branch.clone()),
                                        ),
                                ),
                        )
                        .child(
                            div()
                                .text_xs()
                                .text_color(Theme::foreground_muted())
                                .whitespace_nowrap()
                                .text_ellipsis()
                                .child(repo.path.clone()),
                        ),
                )
                .child(
                    div()
                        .flex()
                        .items_center()
                        .gap(px(4.0))
                        .text_xs()
                        .font_weight(FontWeight::MEDIUM)
                        .text_color(status_color)
                        .child(Icon::new(status_icon).size(px(11.0)).text_color(status_color))
                        .child(status_text),
                ),
        );
    }

    div()
        .flex()
        .flex_col()
        .gap(px(8.0))
        .p(px(10.0))
        .rounded(px(12.0))
        .bg(Theme::surface())
        .border_1()
        .border_color(Theme::border())
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
                        .child(Icon::new(IconName::Folder).size(px(14.0)).text_color(Theme::accent()))
                        .child(
                            div()
                                .text_xs()
                                .font_weight(FontWeight::SEMIBOLD)
                                .text_color(Theme::fg())
                                .child("ACTIVE REPOSITORIES"),
                        ),
                )
                .child(
                    div()
                        .text_xs()
                        .font_weight(FontWeight::BOLD)
                        .text_color(Theme::accent())
                        .child(format!("{} projects", repos.len())),
                ),
        )
        .child(list)
        .into_any_element()
}
