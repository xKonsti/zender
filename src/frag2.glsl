#version 410 core

flat in vec2 rect_center;
flat in vec2 rect_size;
flat in vec4 rect_color;
flat in float corner_radius;
flat in vec4 border_width; // l,r,t,b
flat in vec4 border_color;
flat in int v_use_texture;

flat in float cos_rot;
flat in float sin_rot;

in vec2 v_uv;

out vec4 out_color;

uniform vec4 window_params; // window_size.xy, window_scale.xy
uniform sampler2D tex; // Texture atlas (or white texture for solids)

// Signed distance to rounded rect (uniform radius, symmetric half-size)
float RoundedRectSDF(vec2 p, vec2 center, vec2 half_size, float r) {
    vec2 q = abs(p - center) - half_size + vec2(r);
    return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - r;
}

// Signed distance to an *asymmetrically inset* rounded rect.
// border = (top, right, bottom, left) in clockwise order.
float RoundedRectInsetSDF(vec2 p, vec2 center, vec2 half_size, float r, vec4 border) {
    // Map into named variables for clarity
    float left = border[0];
    float right = border[1];
    float top = border[2];
    float bottom = border[3];

    // Compute new center shifted by asymmetric inset
    vec2 shift = vec2(
            (left - right) * 0.5,
            (bottom - top) * 0.5);
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

    float b_left = border_width[0];
    float b_right = border_width[1];
    float b_top = border_width[2];
    float b_bottom = border_width[3];
    // at max it should be half the size
    float corner_radius_clamped = min(corner_radius, min(half_size.x, half_size.y));

    vec4 color = rect_color;

    if (v_use_texture == 1) { // Render text
        float mask = texture(tex, v_uv).r;
        color.a *= mask;
        out_color = color;
        return;
    }

    if (v_use_texture == 2) { // render image (full RGBA)
        vec4 tex_color = texture(tex, v_uv);
        // Apply tint color
        out_color = tex_color * color;
        return;
    }

    // Compute distance to outer rectangle
    float dist_outer = RoundedRectSDF(sample_pos, rect_center, half_size, corner_radius_clamped);

    // Compute distance to inner rectangle (inset by border)
    // vec2 inset_half = half_size - 0.5 * vec2(b_bottom + b_right, b_top + b_left);
    vec2 inset_half = half_size - 0.5 * vec2(b_left + b_right, b_top + b_bottom);
    //border_width.w + border_width.y, border_width.x + border_width.z);
    float inset_radius = max(0.0, corner_radius_clamped - 0.5 * max(max(b_top, b_right), max(b_left, b_bottom)));
    // float dist_inner = RoundedRectSDF(sample_pos, rect_center, inset_half, inset_radius);
    float dist_inner = RoundedRectInsetSDF(sample_pos, rect_center, half_size, corner_radius_clamped, border_width);

    // Compute softness for anti-aliasing
    float softness_outer = fwidth(dist_outer);
    float softness_inner = fwidth(dist_inner);

    // Border alpha = inside outer, outside inner
    float alpha_border = smoothstep(0.0, softness_outer, -dist_outer) * smoothstep(0.0, softness_inner, dist_inner);

    // Fill alpha = inside inner
    float alpha_fill = 1.0 - smoothstep(0.0, softness_inner, dist_inner);

    // Discard outside outer
    if (dist_outer > 0.0) discard;

    // Combine border and fill to avoid 1-pixel gaps
    float alpha = clamp(alpha_fill * rect_color.a + alpha_border * border_color.a, 0.0, 1.0);

    float mix_factor = (alpha > 0.0) ? (alpha_border / alpha) : 0.0;
    out_color = vec4(
            mix(color.rgb, border_color.rgb, mix_factor),
            alpha
        );
}
