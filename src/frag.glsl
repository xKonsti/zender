#version 410 core

flat in vec2 rect_center;
flat in vec2 rect_size;
flat in vec4 rect_color;
flat in float corner_radius;
flat in vec4 border_width;   // t,r,b,l
flat in vec4 border_color;
flat in int v_use_texture;
in vec2 v_uv;

out vec4 out_color;

uniform vec4 window_params; // window_size.xy, window_scale.xy
uniform sampler2D tex;     // Texture atlas (or white texture for solids)

// Signed distance to rounded rect (uniform radius, symmetric half-size)
float RoundedRectSDF(vec2 p, vec2 center, vec2 half_size, float r) {
    vec2 q = abs(p - center) - half_size + vec2(r);
    return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - r;
}

// Signed distance to an *asymmetrically inset* rounded rect.
// border = (top, right, bottom, left) in clockwise order.
float RoundedRectInsetSDF(vec2 p, vec2 center, vec2 half_size, float r, vec4 border) {
    // Map into named variables for clarity
    float top    = border.x;
    float right  = border.y;
    float bottom = border.z;
    float left   = border.w;

    // Compute new center shifted by asymmetric inset
    vec2 shift = vec2((left - right) * 0.5,
                      (top - bottom) * 0.5);
    vec2 new_center = center + shift;

    // Shrink half-size according to both sides
    vec2 new_half = half_size - vec2((left + right) * 0.5,
                                     (top + bottom) * 0.5);

    // Shrink radius by the *maximum* inset
    float new_r = max(0.0, r - max(max(left, right), max(top, bottom)));

    return RoundedRectSDF(p, new_center, new_half, new_r);
}

void main() {
    vec2 sample_pos = gl_FragCoord.xy;
    vec2 half_size = rect_size * 0.5;

    // Base fill color (textured or solid)
    vec4 color = rect_color;
    if (v_use_texture == 1) {
        float mask = texture(tex, v_uv).r;
        color.a *= mask;
    }

    // Outer/inner SDFs
    float dist_outer = RoundedRectSDF(sample_pos, rect_center, half_size, corner_radius);
    float dist_inner = RoundedRectInsetSDF(sample_pos, rect_center, half_size, corner_radius, border_width);

    float softness_outer = fwidth(dist_outer);
    float softness_inner = fwidth(dist_inner);

    if (dist_outer > 0.0) {
        // Outside outer shape
        discard;
    } else if (dist_inner < 0.0) {
        // Inside inner content region
        float alpha = 1.0 - smoothstep(0.0, softness_inner, dist_inner);
        out_color = vec4(color.rgb, color.a * alpha);
    } else {
        // Between outer and inner -> border
        float alpha_outer = 1.0 - smoothstep(0.0, softness_outer, dist_outer);
        float alpha_inner = smoothstep(0.0, softness_inner, dist_inner);
        float alpha = min(alpha_outer, alpha_inner);
        out_color = vec4(border_color.rgb, border_color.a * alpha);
    }
}
