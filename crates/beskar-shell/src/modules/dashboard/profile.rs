use std::sync::Arc;

use beskar_services::github::GithubProfile;
use gpui_kit::assets::IconName;
use gpui_kit::component::button::{Button, ButtonVariants};
use gpui_kit::component::Icon;
use gpui_kit::prelude::FluentBuilder;
use gpui_kit::*;

/// Profile Card with avatar, rotating ring indicator, and statistics
pub fn render_profile_card(
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
        .border_color(beskar_theme::Theme::card_border())
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
                            beskar_theme::Theme::accent()
                        } else {
                            beskar_theme::Theme::info()
                        })
                        .flex()
                        .items_center()
                        .justify_center()
                        .child(
                            div()
                                .w_full()
                                .h_full()
                                .rounded_full()
                                .bg(beskar_theme::Theme::card_bg())
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
                .bg(beskar_theme::Theme::glass_dark(0.25))
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
                .bg(beskar_theme::Theme::glass_fill(0.04))
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
                                .text_color(beskar_theme::Theme::text_secondary())
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
                    Button::new("dash-gh-profile")
                        .primary()
                        .compact()
                        .label("GitHub Profile")
                        .icon(Icon::new(IconName::ExternalLink).size(px(12.0)))
                        .when_some(on_open, |btn, cb| {
                            btn.on_click(move |_, _, _| (cb)())
                        }),
                )
                .child(
                    Button::new("dash-gh-refresh")
                        .ghost()
                        .compact()
                        .icon(Icon::new(IconName::RefreshCw).size(px(12.0)))
                        .when_some(on_refresh, |btn, cb| {
                            btn.on_click(move |_, _, _| (cb)())
                        }),
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
