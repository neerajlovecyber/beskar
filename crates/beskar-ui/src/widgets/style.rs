//! Concave continuous Bézier geometry and tint styling.
//! Ported directly from `references/capsule/crates/app/src/capsule/widgets/style.rs:27-130`.

#![allow(dead_code)]

use gpui_kit::gpui::{
    Bounds, Hsla, IntoElement, PathBuilder, Pixels, Size, div, point, px,
};
use gpui_kit::prelude::*;

pub fn opaque(mut color: Hsla) -> Hsla {
    color.a = 1.0;
    color
}

fn hsla_to_rgba_tuple(h: f32, s: f32, l: f32, a: f32) -> (f32, f32, f32, f32) {
    if s <= 0.0 {
        return (l, l, l, a);
    }
    let q = if l < 0.5 { l * (1.0 + s) } else { l + s - l * s };
    let p = 2.0 * l - q;
    let hue_to_rgb = |mut t: f32| {
        if t < 0.0 { t += 1.0; }
        if t > 1.0 { t -= 1.0; }
        if t < 1.0 / 6.0 { return p + (q - p) * 6.0 * t; }
        if t < 1.0 / 2.0 { return q; }
        if t < 2.0 / 3.0 { return p + (q - p) * (2.0 / 3.0 - t) * 6.0; }
        p
    };
    (hue_to_rgb(h + 1.0 / 3.0), hue_to_rgb(h), hue_to_rgb(h - 1.0 / 3.0), a)
}

fn rgba_tuple_to_hsla(r: f32, g: f32, b: f32, a: f32) -> Hsla {
    let max = r.max(g).max(b);
    let min = r.min(g).min(b);
    let l = (max + min) / 2.0;
    if (max - min).abs() < f32::EPSILON {
        return gpui_kit::hsla(0.0, 0.0, l, a);
    }
    let d = max - min;
    let s = if l > 0.5 { d / (2.0 - max - min) } else { d / (max + min) };
    let h = if max == r {
        ((g - b) / d).rem_euclid(6.0)
    } else if max == g {
        (b - r) / d + 2.0
    } else {
        (r - g) / d + 4.0
    } / 6.0;
    gpui_kit::hsla(h.rem_euclid(1.0), s, l, a)
}

pub fn tint(base: Hsla, color: Hsla, amount: f32) -> Hsla {
    let (br, bg, bb, _) = hsla_to_rgba_tuple(base.h, base.s, base.l, base.a);
    let (cr, cg, cb, ca) = hsla_to_rgba_tuple(color.h, color.s, color.l, color.a);
    let amount = (amount * ca).clamp(0.0, 1.0);
    rgba_tuple_to_hsla(
        br + (cr - br) * amount,
        bg + (cg - bg) * amount,
        bb + (cb - bb) * amount,
        1.0,
    )
}

pub fn concave_radii(size: Size<Pixels>, radius: f32) -> (f32, f32) {
    let width = f32::from(size.width).max(0.0);
    let height = f32::from(size.height).max(0.0);
    let radius = radius.max(0.0).min(width / 2.0).min(height / 2.0);
    let shoulder = 12.0_f32.min(height / 4.0).min(width / 4.0);
    (radius, shoulder)
}

pub fn concave_background(
    size: Size<Pixels>,
    radius: f32,
    bottom: bool,
    color: Hsla,
) -> impl IntoElement {
    let (radius, shoulder) = concave_radii(size, radius);
    gpui_kit::gpui::canvas(
        |_, _, _| (),
        move |bounds, _, window, _| {
            let width = f32::from(size.width);
            let height = f32::from(size.height);
            let p = |x, y| {
                bounds.origin + point(px(x + shoulder), px(if bottom { height - y } else { y }))
            };
            let k = 0.552_284_8;
            let mut path = PathBuilder::fill();
            path.move_to(p(-shoulder, 0.0));
            path.line_to(p(width + shoulder, 0.0));
            path.cubic_bezier_to(
                p(width, shoulder),
                p(width + shoulder * (1.0 - k), 0.0),
                p(width, shoulder * (1.0 - k)),
            );
            path.line_to(p(width, height - radius));
            path.cubic_bezier_to(
                p(width - radius, height),
                p(width, height - radius * (1.0 - k)),
                p(width - radius * (1.0 - k), height),
            );
            path.line_to(p(radius, height));
            path.cubic_bezier_to(
                p(0.0, height - radius),
                p(radius * (1.0 - k), height),
                p(0.0, height - radius * (1.0 - k)),
            );
            path.line_to(p(0.0, shoulder));
            path.cubic_bezier_to(
                p(-shoulder, 0.0),
                p(0.0, shoulder * (1.0 - k)),
                p(-shoulder * (1.0 - k), 0.0),
            );
            path.close();
            if let Ok(path) = path.build() {
                window.paint_path(path, color);
            }
        },
    )
    .absolute()
    .top_0()
    .left(px(-shoulder))
    .w(size.width + px(shoulder * 2.0))
    .h(size.height)
}

pub fn concave_input_regions(
    bounds: Bounds<Pixels>,
    radius: f32,
    bottom: bool,
) -> Vec<Bounds<Pixels>> {
    let (radius, shoulder) = concave_radii(bounds.size, radius);
    let height = f32::from(bounds.size.height);
    let mut regions = Vec::new();
    let mut y = 0.0;
    while y < height {
        let band_height = if y >= shoulder && y < height - radius {
            height - radius - y
        } else {
            (height - y).min(1.0)
        };
        let sample = y + band_height / 2.0;
        let inset = if sample < shoulder {
            -shoulder
                + (shoulder * shoulder - (sample - shoulder).powi(2))
                    .max(0.0)
                    .sqrt()
        } else if sample > height - radius {
            radius
                - (radius * radius - (sample - height + radius).powi(2))
                    .max(0.0)
                    .sqrt()
        } else {
            0.0
        };
        regions.push(Bounds {
            origin: bounds.origin
                + point(
                    px(inset),
                    px(if bottom { height - y - band_height } else { y }),
                ),
            size: Size {
                width: bounds.size.width - px(inset * 2.0),
                height: px(band_height),
            },
        });
        y += band_height;
    }
    regions
}

pub const CARD_RADIUS: f32 = 16.0;
pub const INNER_RADIUS: f32 = 12.0;

pub fn surface() -> Hsla {
    beskar_theme::Theme::bg_secondary()
}

pub fn hover() -> Hsla {
    tint(surface(), beskar_theme::Theme::accent(), 0.08)
}

pub fn selected() -> Hsla {
    tint(surface(), beskar_theme::Theme::accent(), 0.12)
}

pub fn border() -> Hsla {
    beskar_theme::Theme::border()
}

pub fn on_accent() -> Hsla {
    beskar_theme::Theme::accent()
}

pub fn raised() -> Hsla {
    tint(surface(), beskar_theme::Theme::fg(), 0.06)
}

pub fn accent_card() -> Hsla {
    tint(surface(), beskar_theme::Theme::accent(), 0.2)
}

pub fn card(radius: f32) -> gpui_kit::gpui::Div {
    div().rounded(px(radius)).bg(surface())
}


#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn concave_curves_fit_compact_and_expanded_capsules() {
        for width in [1.0, 40.0, 250.0, 560.0] {
            for height in [1.0, 25.0, 40.0, 212.0, 562.0] {
                for configured_radius in [0.0, 12.0, 24.0, 100.0, 1000.0] {
                    let size = Size {
                        width: px(width),
                        height: px(height),
                    };
                    let (radius, shoulder) = concave_radii(size, configured_radius);
                    assert!(radius + shoulder <= height);
                    assert!(radius * 2.0 <= width);
                    assert!(shoulder <= 12.0);
                    assert_eq!(shoulder, concave_radii(size, 0.0).1);
                    assert_eq!(shoulder, concave_radii(size, 1000.0).1);
                }
            }
        }
    }

    #[test]
    fn concave_input_regions_follow_the_outline_on_both_edges() {
        let bounds = Bounds {
            origin: point(px(100.0), px(50.0)),
            size: Size {
                width: px(250.0),
                height: px(40.0),
            },
        };
        let top = concave_input_regions(bounds, 1000.0, false);
        let bottom = concave_input_regions(bounds, 1000.0, true);
        assert_eq!(top.len(), bottom.len());
        assert!(top[0].origin.x < bounds.origin.x);
        assert!(top[top.len() - 1].origin.x > bounds.origin.x);
        assert!(top.len() < 40);
        let mut covered_height = px(0.0);
        for (top, bottom) in top.iter().zip(&bottom) {
            assert!(top.size.width > px(0.0));
            assert!(top.size.height > px(0.0));
            assert_eq!(top.size, bottom.size);
            assert_eq!(top.origin.x, bottom.origin.x);
            assert_eq!(
                bottom.origin.y,
                bounds.origin.y + bounds.size.height
                    - (top.origin.y - bounds.origin.y)
                    - top.size.height,
            );
            assert_eq!(top.origin.y, bounds.origin.y + covered_height);
            covered_height += top.size.height;
        }
        assert_eq!(covered_height, bounds.size.height);
    }

    #[test]
    fn tint_preserves_base_at_low_strength() {
        let base = gpui_kit::hsla(0.0, 0.0, 0.0, 1.0);
        let white = gpui_kit::hsla(0.0, 0.0, 1.0, 1.0);
        let tinted = tint(base, white, 0.06);
        let (r, g, b, a) = hsla_to_rgba_tuple(tinted.h, tinted.s, tinted.l, tinted.a);
        for channel in [r, g, b] {
            assert!((channel - 0.06).abs() < 0.0001);
        }
        assert_eq!(a, 1.0);
    }
}
