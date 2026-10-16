use beskar_services::MediaTrack;
use beskar_theme::Theme;
use gpui_kit::gpui::{
    canvas, div, img, point, px, svg, AnyElement, FontWeight,
    InteractiveElement, IntoElement, MouseButton, MouseDownEvent, ObjectFit,
    ParentElement, PathBuilder, StatefulInteractiveElement,
    Styled,
};
use gpui_kit::prelude::*;
use std::path::PathBuf;

pub fn position(track: &MediaTrack, elapsed: std::time::Duration) -> i64 {
    let position = track.position_micros.unwrap_or(0).max(0);
    let elapsed = if track.is_playing {
        elapsed.as_micros().min(i64::MAX as u128) as i64
    } else {
        0
    };
    let next = position.saturating_add(elapsed);
    track
        .length_micros
        .filter(|length| *length > 0)
        .map_or(next, |length| next.min(length))
}

#[derive(Clone)]
pub struct MediaCardCallbacks {
    pub on_play_pause: std::sync::Arc<dyn Fn() + Send + Sync>,
    pub on_prev: std::sync::Arc<dyn Fn() + Send + Sync>,
    pub on_next: std::sync::Arc<dyn Fn() + Send + Sync>,
    pub on_seek: std::sync::Arc<dyn Fn(f64) + Send + Sync>,
}

pub fn render_media_card(
    track: Option<&MediaTrack>,
    elapsed: std::time::Duration,
    wave_phase: f32,
    radius: f32,
    callbacks: Option<MediaCardCallbacks>,
    seek_tracker: Option<&crate::tracker::DimensionTracker>,
) -> AnyElement {
    let card = div()
        .id("dashboard-media")
        .relative()
        .overflow_hidden()
        .h(px(super::MEDIA_HEIGHT))
        .w_full()
        .flex_shrink_0()
        .flex()
        .flex_col()
        .p(px(8.0))
        .gap(px(12.0))
        .justify_center()
        .rounded(px(radius))
        .bg(crate::widgets::style::surface());

    let Some(track) = track else {
        return card
            .justify_center()
            .child(super::empty("No Media Playing"))
            .into_any_element();
    };

    let pos = position(track, elapsed);
    let length = track.length_micros.unwrap_or(0).max(0);
    let fraction = if length > 0 {
        (pos as f32 / length as f32).clamp(0.0, 1.0)
    } else {
        0.0
    };
    let amplitude = if track.is_playing { 3.0 } else { 0.0 };
    let active = Theme::accent();
    let inactive = Theme::foreground_muted().opacity(0.3);

    let tracker_clone = seek_tracker.cloned();
    let cb_seek = callbacks.as_ref().map(|c| c.on_seek.clone());
    let length_f64 = length as f64 / 1_000_000.0;

    let mut progress = div()
        .id("dashboard-seek")
        .relative()
        .w_full()
        .h(px(12.0))
        .flex_shrink_0();

    if length > 0 {
        if let Some(cb) = cb_seek {
            let trk = tracker_clone.clone();
            progress = progress
                .cursor_pointer()
                .on_mouse_down(MouseButton::Left, move |event: &MouseDownEvent, _, _| {
                    let click_x: f32 = event.position.x.into();
                    if let Some(ref t) = trk {
                        let width = t.width(0.0);
                        if width > 0.0 {
                            let frac = ((click_x - t.left()) / width).clamp(0.0, 1.0);
                            cb(frac as f64 * length_f64);
                        }
                    }
                });
        }
    }

    let progress_canvas = canvas(
        move |bounds, _, _| {
            if let Some(ref t) = tracker_clone {
                t.track_bounds(bounds);
            }
        },
        move |bounds, _, window, _| {
            let width: f32 = bounds.size.width.into();
            let height: f32 = bounds.size.height.into();
            let center = height / 2.0;
            let played = width * fraction;

            let mut rest = PathBuilder::stroke(px(2.0));
            rest.move_to(bounds.origin + point(px(played), px(center)));
            rest.line_to(bounds.origin + point(px(width), px(center)));
            if let Ok(path) = rest.build() {
                window.paint_path(path, inactive);
            }

            if played > 0.0 {
                let mut wave = PathBuilder::stroke(px(2.0));
                let steps = played.ceil() as usize;
                for step in 0..=steps {
                    let x = (step as f32).min(played);
                    let envelope = (x / 8.0).min(1.0) * ((played - x) / 8.0).clamp(0.0, 1.0);
                    let y = center
                        + (x / 22.0 * std::f32::consts::TAU - wave_phase).sin()
                            * amplitude
                            * envelope;
                    let point = bounds.origin + point(px(x), px(y));
                    if step == 0 {
                        wave.move_to(point);
                    } else {
                        wave.line_to(point);
                    }
                }
                if let Ok(path) = wave.build() {
                    window.paint_path(path, active);
                }
            }
        },
    )
    .w_full()
    .h_full();

    let progress = progress.child(progress_canvas);

    let card = card.when_some(track.local_art_path.as_ref(), |card, path| {
        card.child(
            div()
                .absolute()
                .inset_0()
                .child(
                    img(PathBuf::from(path))
                        .absolute()
                        .inset_0()
                        .size_full()
                        .aspect_ratio(super::RIGHT / super::MEDIA_HEIGHT)
                        .rounded(px(radius))
                        .object_fit(ObjectFit::Cover),
                )
                .child(
                    div()
                        .absolute()
                        .inset_0()
                        .rounded(px(radius))
                        .bg(Theme::bg().opacity(0.78)),
                ),
        )
    });

    let cb_play = callbacks.as_ref().map(|c| c.on_play_pause.clone());
    let mut play_btn = div()
        .id("dashboard-play")
        .size(px(36.0))
        .flex_shrink_0()
        .rounded_full()
        .bg(Theme::accent())
        .flex()
        .items_center()
        .justify_center();

    if let Some(cb) = cb_play {
        play_btn = play_btn.cursor_pointer().on_click(move |_, _, _| cb());
    }

    let play_btn = play_btn.child(
        svg()
            .path(if track.is_playing {
                "pause.svg"
            } else {
                "play.svg"
            })
            .size(px(22.0))
            .text_color(crate::widgets::style::on_accent()),
    );

    let cb_prev = callbacks.as_ref().map(|c| c.on_prev.clone());
    let mut prev_btn = div()
        .id("dashboard-previous")
        .size(px(32.0))
        .flex_shrink_0()
        .flex()
        .items_center()
        .justify_center()
        .rounded(px(8.0))
        .opacity(if track.can_go_previous { 1.0 } else { 0.35 });

    if track.can_go_previous {
        if let Some(cb) = cb_prev {
            prev_btn = prev_btn
                .cursor_pointer()
                .hover(|s| s.bg(crate::widgets::style::hover()))
                .on_click(move |_, _, _| cb());
        }
    }
    let prev_btn = prev_btn.child(
        svg()
            .path("skip-back.svg")
            .size(px(18.0))
            .text_color(Theme::foreground_muted()),
    );

    let cb_next = callbacks.as_ref().map(|c| c.on_next.clone());
    let mut next_btn = div()
        .id("dashboard-next")
        .size(px(32.0))
        .flex_shrink_0()
        .flex()
        .items_center()
        .justify_center()
        .rounded(px(8.0))
        .opacity(if track.can_go_next { 1.0 } else { 0.35 });

    if track.can_go_next {
        if let Some(cb) = cb_next {
            next_btn = next_btn
                .cursor_pointer()
                .hover(|s| s.bg(crate::widgets::style::hover()))
                .on_click(move |_, _, _| cb());
        }
    }
    let next_btn = next_btn.child(
        svg()
            .path("skip-forward.svg")
            .size(px(18.0))
            .text_color(Theme::foreground_muted()),
    );

    card.child(
        div()
            .relative()
            .w_full()
            .min_h(px(52.0))
            .flex_shrink_0()
            .px(px(12.0))
            .flex()
            .items_center()
            .gap(px(12.0))
            .child(
                div()
                    .flex_1()
                    .min_w_0()
                    .flex()
                    .flex_col()
                    .gap(px(4.0))
                    .child(
                        div()
                            .text_size(px(17.0))
                            .font_weight(FontWeight::SEMIBOLD)
                            .whitespace_nowrap()
                            .text_ellipsis()
                            .child(track.title.clone()),
                    )
                    .child(
                        div()
                            .text_size(px(11.0))
                            .text_color(Theme::foreground_muted())
                            .whitespace_nowrap()
                            .text_ellipsis()
                            .child(track.artist.clone()),
                    ),
            )
            .child(play_btn),
    )
    .child(
        div()
            .relative()
            .w_full()
            .flex_shrink_0()
            .flex()
            .items_center()
            .gap(px(4.0))
            .child(prev_btn)
            .child(
                div()
                    .flex_1()
                    .min_w_0()
                    .h(px(32.0))
                    .flex()
                    .items_center()
                    .child(progress),
            )
            .child(next_btn),
    )
    .into_any_element()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn progress_stops_when_paused_and_never_exceeds_the_track() {
        let mut track = MediaTrack {
            position_micros: Some(2_000_000),
            length_micros: Some(3_000_000),
            ..Default::default()
        };
        assert_eq!(
            position(&track, std::time::Duration::from_secs(4)),
            2_000_000
        );
        track.is_playing = true;
        assert_eq!(
            position(&track, std::time::Duration::from_secs(4)),
            3_000_000
        );
        track.position_micros = Some(-20);
        assert_eq!(position(&track, std::time::Duration::ZERO), 0);
    }
}
