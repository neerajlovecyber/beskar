use beskar_services::github::ContributionDay;
use gpui_kit::assets::IconName;
use gpui_kit::component::Icon;
use gpui_kit::*;

/// 52-Week GitHub Heatmap Grid matching GithubContributionsWidget.qml
pub fn render_contributions_heatmap(
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
        .border_color(beskar_theme::Theme::card_border())
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
                                0 => beskar_theme::Theme::subtle_border(),
                                1 => beskar_theme::Theme::success_alpha(0.35),
                                2 => beskar_theme::Theme::success_alpha(0.60),
                                3 => beskar_theme::Theme::success_alpha(0.85),
                                _ => beskar_theme::Theme::success(),
                            };

                            div()
                                .w(px(10.0))
                                .h(px(10.0))
                                .rounded_xs()
                                .bg(cell_color)
                                .hover(move |s| {
                                    s.border_1()
                                        .border_color(beskar_theme::Theme::fg())
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
                .child(swatch(beskar_theme::Theme::subtle_border()))
                .child(swatch(beskar_theme::Theme::success_alpha(0.35)))
                .child(swatch(beskar_theme::Theme::success_alpha(0.60)))
                .child(swatch(beskar_theme::Theme::success_alpha(0.85)))
                .child(swatch(beskar_theme::Theme::success()))
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
