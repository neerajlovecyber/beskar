use gpui_kit::*;

/// Render parameters for minflair-style convex bar Bézier fillets
#[derive(Debug, Clone, Copy)]
pub struct ConvexGeometry {
    pub width: f32,
    pub height: f32,
    pub left_w: f32,
    pub center_x: f32,
    pub center_w: f32,
    pub right_w: f32,
    pub top_bezel: f32,
    pub flare_width: f32,
    pub flare_height: f32,
    pub bottom_radius: f32,
    pub center_bottom_radius: f32,
    pub center_height: f32,
    pub base_height: f32,
}

impl Default for ConvexGeometry {
    fn default() -> Self {
        Self {
            width: 1920.0,
            height: 44.0,
            left_w: 320.0,
            center_x: 830.0,
            center_w: 260.0,
            right_w: 320.0,
            top_bezel: 2.0,
            flare_width: 18.0,
            flare_height: 16.0,
            bottom_radius: 16.0,
            center_bottom_radius: 16.0,
            center_height: 44.0,
            base_height: 44.0,
        }
    }
}

/// Paint the convex notch path with cubic Bézier fillets directly onto the GPUI Window.
pub fn trace_convex_notch(
    builder: &mut PathBuilder,
    ox: f32,
    oy: f32,
    geom: &ConvexGeometry,
) {
    let w = geom.width;
    let bh = if geom.base_height > 0.0 { geom.base_height } else { geom.height };
    let ch = geom.center_height;
    let lw = geom.left_w;
    let cx = geom.center_x;
    let cw = geom.center_w;
    let rw = geom.right_w;
    let tb = geom.top_bezel;
    let fw = geom.flare_width;
    let fh = geom.flare_height;
    let br = geom.bottom_radius;
    let cbr = geom.center_bottom_radius;

    let pt = |x: f32, y: f32| point(px(ox + x), px(oy + y));

    // 1. Left notch top-left
    builder.move_to(pt(0.0, 0.0));
    builder.line_to(pt(0.0, bh));
    builder.line_to(pt(lw - fw - br, bh));

    // Left notch bottom corner fillet
    builder.cubic_bezier_to(
        pt(lw - fw, bh - br),
        pt(lw - fw - br * 0.45, bh),
        pt(lw - fw, bh - br * 0.45),
    );

    if bh - br > fh + tb {
        builder.line_to(pt(lw - fw, fh + tb));
    }

    // Left notch flare up into bridge 1
    builder.cubic_bezier_to(
        pt(lw, tb),
        pt(lw - fw, fh * 0.45 + tb),
        pt(lw - fw * 0.55, tb),
    );

    // 2. Bridge 1
    builder.line_to(pt(cx, tb));

    // 3. Flare down into center notch
    builder.cubic_bezier_to(
        pt(cx + fw, fh + tb),
        pt(cx + fw * 0.55, tb),
        pt(cx + fw, fh * 0.45 + tb),
    );

    if ch - cbr > fh + tb {
        builder.line_to(pt(cx + fw, ch - cbr));
    }

    // Center notch bottom-left fillet
    builder.cubic_bezier_to(
        pt(cx + fw + cbr, ch),
        pt(cx + fw, ch - cbr * 0.45),
        pt(cx + fw + cbr * 0.45, ch),
    );

    // 4. Center notch bottom horizontal line
    builder.line_to(pt(cx + cw - fw - cbr, ch));

    // Center notch bottom-right fillet
    builder.cubic_bezier_to(
        pt(cx + cw - fw, ch - cbr),
        pt(cx + cw - fw - cbr * 0.45, ch),
        pt(cx + cw - fw, ch - cbr * 0.45),
    );

    if ch - cbr > fh + tb {
        builder.line_to(pt(cx + cw - fw, fh + tb));
    }

    // Flare up from center notch into bridge 2
    builder.cubic_bezier_to(
        pt(cx + cw, tb),
        pt(cx + cw - fw, fh * 0.45 + tb),
        pt(cx + cw - fw * 0.55, tb),
    );

    // 5. Bridge 2
    let rx = (w - rw).max(cx + cw);
    builder.line_to(pt(rx, tb));

    // 6. Flare down into right notch
    builder.cubic_bezier_to(
        pt(rx + fw, fh + tb),
        pt(rx + fw * 0.55, tb),
        pt(rx + fw, fh * 0.45 + tb),
    );

    if bh - br > fh + tb {
        builder.line_to(pt(rx + fw, bh - br));
    }

    // Right notch bottom-left fillet
    builder.cubic_bezier_to(
        pt(rx + fw + br, bh),
        pt(rx + fw, bh - br * 0.45),
        pt(rx + fw + br * 0.45, bh),
    );

    // 7. Right notch bottom and close
    builder.line_to(pt(w, bh));
    builder.line_to(pt(w, 0.0));
    builder.close();
}

/// Canvas element painting the complete minflair Convex Shape backdrop
#[derive(IntoElement)]
pub struct ConvexBarShape {
    geometry: ConvexGeometry,
    fill_color: Hsla,
    border_color: Hsla,
}

impl ConvexBarShape {
    pub fn new(geom: ConvexGeometry, fill_color: Hsla, border_color: Hsla) -> Self {
        Self {
            geometry: geom,
            fill_color,
            border_color,
        }
    }
}

impl RenderOnce for ConvexBarShape {
    fn render(self, _window: &mut Window, _cx: &mut App) -> impl IntoElement {
        let geom = self.geometry;
        let fill = self.fill_color;
        let border = self.border_color;

        canvas(
            |_bounds, _, _| (),
            move |bounds, _, window, _cx| {
                let ox = f32::from(bounds.origin.x);
                let oy = f32::from(bounds.origin.y);
                let w = f32::from(bounds.size.width);
                let mut dynamic_geom = geom;
                dynamic_geom.width = w;
                dynamic_geom.center_x = (w - dynamic_geom.center_w) * 0.5;

                // 1. Fill path
                let mut fill_builder = PathBuilder::fill();
                trace_convex_notch(&mut fill_builder, ox, oy, &dynamic_geom);
                if let Ok(fill_path) = fill_builder.build() {
                    window.paint_path(fill_path, fill);
                }

                // 2. 1px Stroke outline
                let mut stroke_builder = PathBuilder::stroke(px(1.0));
                trace_convex_notch(&mut stroke_builder, ox, oy, &dynamic_geom);
                if let Ok(stroke_path) = stroke_builder.build() {
                    window.paint_path(stroke_path, border);
                }
            },
        )
        .size_full()
    }
}
