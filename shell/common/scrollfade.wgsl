// A small theme-coloured scrim at the edge of a scrolling viewport.
fn shade(s: Shader) -> vec4<f32> {
    return vec4<f32>(s.color.rgb, smoothstep(0.0, 1.0, s.uv.y) * s.a.x);
}
