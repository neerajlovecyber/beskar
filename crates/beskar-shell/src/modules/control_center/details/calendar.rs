//! Calendar Satellite Detail Widget
//! Ported directly from `references/capsule/crates/app/src/capsule/widgets/satellite/calendar.rs`.

use chrono::{Datelike, Local, NaiveDate};
use gpui_kit::assets::IconName;
use gpui_kit::component::Icon;
use gpui_kit::prelude::FluentBuilder;
use gpui_kit::*;
use std::sync::Arc;

pub const WIDTH: f32 = 300.0;
pub const HEIGHT: f32 = 300.0;

#[derive(IntoElement)]
pub struct CalendarWidget {
    year: i32,
    month: u32,
    on_change_month: Option<Arc<dyn Fn(i8) + Send + Sync>>,
    on_close: Option<Arc<dyn Fn() + Send + Sync>>,
}

impl CalendarWidget {
    pub fn new(year: i32, month: u32) -> Self {
        Self {
            year,
            month,
            on_change_month: None,
            on_close: None,
        }
    }

    pub fn on_change_month(mut self, handler: impl Fn(i8) + Send + Sync + 'static) -> Self {
        self.on_change_month = Some(Arc::new(handler));
        self
    }

    pub fn on_close(mut self, handler: impl Fn() + Send + Sync + 'static) -> Self {
        self.on_close = Some(Arc::new(handler));
        self
    }
}

impl RenderOnce for CalendarWidget {
    fn render(self, _window: &mut Window, _cx: &mut App) -> impl IntoElement {
        let year = self.year;
        let month = self.month;
        let today = Local::now().date_naive();

        let month_names = [
            "January",
            "February",
            "March",
            "April",
            "May",
            "June",
            "July",
            "August",
            "September",
            "October",
            "November",
            "December",
        ];
        let month_name = month_names
            .get(month.saturating_sub(1) as usize)
            .unwrap_or(&"");

        let weekdays = ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"];

        let first = NaiveDate::from_ymd_opt(year, month, 1);
        let offset = first
            .map(|date| date.weekday().num_days_from_monday() as i32)
            .unwrap_or(0);

        let mut labels = div().flex().gap(px(4.0)).h(px(20.0));
        for label in weekdays {
            labels = labels.child(
                div()
                    .flex_1()
                    .text_center()
                    .text_size(px(11.0))
                    .text_color(beskar_theme::Theme::text_secondary())
                    .child(label),
            );
        }

        let mut grid = div().flex_1().min_h_0().flex().flex_col().gap(px(4.0));
        for week in 0..6 {
            let mut row = div().flex_1().min_h_0().flex().gap(px(4.0));
            for weekday in 0..7 {
                let day = week * 7 + weekday - offset + 1;
                let date = if day > 0 {
                    NaiveDate::from_ymd_opt(year, month, day as u32)
                } else {
                    None
                };
                let selected = date == Some(today);
                row = row.child(
                    div()
                        .flex_1()
                        .min_w_0()
                        .h_full()
                        .flex()
                        .items_center()
                        .justify_center()
                        .rounded_full()
                        .when(selected, |s| s.bg(beskar_theme::Theme::accent()))
                        .text_color(if selected {
                            beskar_theme::Theme::bg()
                        } else {
                            beskar_theme::Theme::fg()
                        })
                        .text_size(px(12.0))
                        .child(date.map(|d| d.day().to_string()).unwrap_or_default()),
                );
            }
            grid = grid.child(row);
        }

        let on_prev = self.on_change_month.clone();
        let on_next = self.on_change_month.clone();
        let on_cls = self.on_close;

        div()
            .w(px(WIDTH))
            .h(px(HEIGHT))
            .flex()
            .flex_col()
            .p(px(16.0))
            .gap(px(12.0))
            .rounded(px(16.0))
            .bg(beskar_theme::Theme::bg_secondary())
            .border_1()
            .border_color(beskar_theme::Theme::subtle_border())
            .text_size(px(13.0))
            .text_color(beskar_theme::Theme::fg())
            .overflow_hidden()
            .child(
                div()
                    .h(px(28.0))
                    .flex_shrink_0()
                    .flex()
                    .items_center()
                    .justify_between()
                    .child(
                        div()
                            .flex()
                            .items_center()
                            .gap(px(8.0))
                            .child(
                                Icon::new(IconName::Calendar)
                                    .size(px(16.0))
                                    .text_color(beskar_theme::Theme::accent()),
                            )
                            .child(
                                div()
                                    .text_size(px(13.0))
                                    .font_weight(FontWeight::MEDIUM)
                                    .child(format!("{month_name} {year}")),
                            ),
                    )
                    .child(
                        div()
                            .flex()
                            .items_center()
                            .gap(px(4.0))
                            .child(
                                div()
                                    .size(px(24.0))
                                    .flex()
                                    .items_center()
                                    .justify_center()
                                    .rounded_full()
                                    .cursor_pointer()
                                    .hover(|s| s.bg(beskar_theme::Theme::bg()))
                                    .when_some(on_prev, |el, cb| {
                                        el.on_mouse_down(MouseButton::Left, move |_, _, _| (cb)(-1))
                                    })
                                    .child(Icon::new(IconName::ChevronLeft).size(px(14.0))),
                            )
                            .child(
                                div()
                                    .size(px(24.0))
                                    .flex()
                                    .items_center()
                                    .justify_center()
                                    .rounded_full()
                                    .cursor_pointer()
                                    .hover(|s| s.bg(beskar_theme::Theme::bg()))
                                    .when_some(on_next, |el, cb| {
                                        el.on_mouse_down(MouseButton::Left, move |_, _, _| (cb)(1))
                                    })
                                    .child(Icon::new(IconName::ChevronRight).size(px(14.0))),
                            )
                            .when_some(on_cls, |parent, cb| {
                                parent.child(
                                    div()
                                        .size(px(24.0))
                                        .flex()
                                        .items_center()
                                        .justify_center()
                                        .rounded_full()
                                        .cursor_pointer()
                                        .hover(|s| s.bg(beskar_theme::Theme::bg()))
                                        .on_mouse_down(MouseButton::Left, move |_, _, _| (cb)())
                                        .child(Icon::new(IconName::X).size(px(14.0))),
                                )
                            }),
                    ),
            )
            .child(labels)
            .child(grid)
    }
}
