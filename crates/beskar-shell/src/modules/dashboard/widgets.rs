use std::sync::Arc;

use gpui_kit::assets::IconName;
use gpui_kit::component::Icon;
use gpui_kit::component::button::{Button, ButtonVariants};
use gpui_kit::prelude::FluentBuilder;
use gpui_kit::gpui::{
    AnyElement, FontWeight, InteractiveElement, IntoElement, MouseButton, ParentElement, Styled,
    div, px,
};

use beskar_services::github::{ContributionDay, GithubProfile};
use beskar_services::updates::SystemUpdatesState;
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

/// 1. User Profile Header matching minflair:
/// Avatar, username, handle, short bio/quote, and clean 3-row stat summary (Total Stars, Repositories, Total Forks).
pub fn render_user_profile_header(
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
        // Top action bar
        .child(
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
                                .child(
                                    Icon::new(IconName::Github)
                                        .size(px(15.0))
                                        .text_color(Theme::accent()),
                                ),
                        )
                        .child(
                            div()
                                .text_sm()
                                .font_weight(FontWeight::BOLD)
                                .text_color(Theme::fg())
                                .child("GITHUB DASHBOARD"),
                        ),
                )
                .child(
                    div()
                        .flex()
                        .items_center()
                        .gap(px(4.0))
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
        // User profile hero
        .child(
            div()
                .flex()
                .flex_col()
                .gap(px(10.0))
                .p(px(12.0))
                .rounded(px(12.0))
                .bg(Theme::surface())
                .border_1()
                .border_color(Theme::border())
                .child(
                    div()
                        .flex()
                        .items_center()
                        .gap(px(12.0))
                        .child(
                            div()
                                .size(px(42.0))
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
                                        .text_sm()
                                        .font_weight(FontWeight::BOLD)
                                        .text_color(Theme::fg())
                                        .child(profile.name.clone()),
                                )
                                .child(
                                    div()
                                        .text_xs()
                                        .text_color(Theme::accent())
                                        .child(format!("@{}", profile.username)),
                                ),
                        ),
                )
                .when(!profile.bio.is_empty(), |hero| {
                    hero.child(
                        div()
                            .text_xs()
                            .italic()
                            .text_color(Theme::foreground_muted())
                            .child(if is_fetching {
                                "Refreshing telemetry...".to_string()
                            } else {
                                profile.bio.clone()
                            }),
                    )
                })
                .child(
                    div()
                        .h(px(1.0))
                        .w_full()
                        .bg(Theme::border().opacity(0.6)),
                )
                // Clean 3-row stat summary
                .child(
                    div()
                        .flex()
                        .flex_col()
                        .gap(px(6.0))
                        .child(render_stat_row(
                            IconName::Star,
                            "Total Stars",
                            &profile.total_stars.to_string(),
                        ))
                        .child(render_stat_row(
                            IconName::Code,
                            "Repositories",
                            &profile.public_repos.to_string(),
                        ))
                        .child(render_stat_row(
                            IconName::GitFork,
                            "Total Forks",
                            &profile.total_forks.to_string(),
                        )),
                ),
        )
        .into_any_element()
}

fn render_stat_row(icon: IconName, label: &'static str, value: &str) -> AnyElement {
    div()
        .flex()
        .items_center()
        .justify_between()
        .w_full()
        .px(px(4.0))
        .py(px(2.0))
        .child(
            div()
                .flex()
                .items_center()
                .gap(px(8.0))
                .child(Icon::new(icon).size(px(13.0)).text_color(Theme::accent()))
                .child(
                    div()
                        .text_xs()
                        .font_weight(FontWeight::MEDIUM)
                        .text_color(Theme::fg())
                        .child(label),
                ),
        )
        .child(
            div()
                .text_xs()
                .font_weight(FontWeight::BOLD)
                .text_color(Theme::fg())
                .child(value.to_string()),
        )
        .into_any_element()
}

/// 2. Contributions Card: Clean, compact contribution heatmap grid
pub fn render_heatmap_card(
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
        .py(px(2.0));

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
                    .size(px(6.5))
                    .rounded(px(1.5))
                    .bg(bg_color)
                    .cursor_pointer()
                    .on_mouse_down(MouseButton::Left, move |_, _, _| {
                        (hover_cb)(Some(day_clone.clone()));
                    }),
            );
        }
        grid_row = grid_row.child(col);
    }

    div()
        .flex()
        .flex_col()
        .gap(px(6.0))
        .p(px(12.0))
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
                        .font_weight(FontWeight::BOLD)
                        .text_color(Theme::foreground_muted())
                        .child("CONTRIBUTIONS"),
                )
                .when_some(hovered_day, |header, day| {
                    header.child(
                        div()
                            .text_xs()
                            .text_color(Theme::accent())
                            .child(format!("{}: {} commits", day.date, day.count)),
                    )
                }),
        )
        .child(
            div()
                .w_full()
                .overflow_hidden()
                .child(grid_row),
        )
        .into_any_element()
}

/// 3. System Updates Card matching minflair UpdatesCard.qml:
/// Simple pending packages counter ("X packages pending" with "Pacman / AUR" subtext) and an "Update" pill button.
pub fn render_updates_card(
    updates: &SystemUpdatesState,
    on_update: Arc<dyn Fn() + Send + Sync>,
) -> AnyElement {
    let total = updates.pacman_count + updates.aur_count;
    let has_updates = total > 0;

    div()
        .flex()
        .items_center()
        .justify_between()
        .p(px(12.0))
        .rounded(px(12.0))
        .bg(Theme::surface())
        .border_1()
        .border_color(Theme::border())
        .child(
            div()
                .flex()
                .items_center()
                .gap(px(10.0))
                .child(
                    div()
                        .size(px(32.0))
                        .rounded_full()
                        .bg(if has_updates {
                            Theme::accent_alpha(0.18)
                        } else {
                            Theme::border().opacity(0.3)
                        })
                        .flex()
                        .items_center()
                        .justify_center()
                        .child(
                            Icon::new(if has_updates {
                                IconName::Package
                            } else {
                                IconName::Check
                            })
                            .size(px(16.0))
                            .text_color(if has_updates {
                                Theme::accent()
                            } else {
                                Theme::foreground_muted()
                            }),
                        ),
                )
                .child(
                    div()
                        .flex()
                        .flex_col()
                        .gap(px(1.0))
                        .child(
                            div()
                                .text_xs()
                                .font_weight(FontWeight::BOLD)
                                .text_color(Theme::fg())
                                .child(if updates.is_checking {
                                    "Checking updates...".to_string()
                                } else if has_updates {
                                    format!("{} packages pending", total)
                                } else {
                                    "System up to date".to_string()
                                }),
                        )
                        .child(
                            div()
                                .text_xs()
                                .text_color(Theme::foreground_muted())
                                .child(if updates.is_checking {
                                    "Please wait".to_string()
                                } else if has_updates {
                                    format!("Pacman: {} | AUR: {}", updates.pacman_count, updates.aur_count)
                                } else {
                                    "All packages are currently up to date".to_string()
                                }),
                        ),
                ),
        )
        .child(
            Button::new("update-btn")
                .primary()
                .compact()
                .label(if has_updates { "Update" } else { "Check" })
                .on_click(move |_, _, _| (on_update)()),
        )
        .into_any_element()
}

/// 4. Footer Quote: Subtle italicized quote at the bottom.
pub fn render_quote_footer(quote_text: &str, author: &str) -> AnyElement {
    div()
        .flex()
        .flex_col()
        .gap(px(3.0))
        .w_full()
        .pt(px(4.0))
        .px(px(6.0))
        .child(
            div()
                .text_xs()
                .italic()
                .text_color(Theme::foreground_muted().opacity(0.85))
                .child(format!("“{}”", quote_text)),
        )
        .child(
            div()
                .flex()
                .justify_end()
                .child(
                    div()
                        .text_xs()
                        .font_weight(FontWeight::MEDIUM)
                        .text_color(Theme::foreground_muted().opacity(0.65))
                        .child(format!("— {}", author)),
                ),
        )
        .into_any_element()
}
