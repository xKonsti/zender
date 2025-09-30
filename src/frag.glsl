#version 410 core

flat in vec2 rect_center;
flat in vec2 rect_size;
flat in vec4 rect_color;
flat in float corner_radius;

uniform vec2 window_size;

out vec4 out_color;

float RoundedRectSDF(vec2 sample_pos, vec2 rect_center, vec2 rect_half_size, float r) {
    vec2 distance2 = abs(rect_center - sample_pos) - rect_half_size + vec2(r, r);
    return 
        min(max(distance2.x, distance2.y), 0.0)  // neg - 0 for inside
        + length(max(distance2, 0.0))               // 0 - pos for outside
        - r;                                        // - r for rounded corners
}

void main() {
    vec2 half_size = rect_size / 2;
    float radius = min(corner_radius, min(half_size.x, half_size.y));
    float distance = RoundedRectSDF(gl_FragCoord.xy, rect_center, half_size, radius);

    float softness = fwidth(distance); // smooth anti-aliasing
    float alpha = 1.0 - smoothstep(0.0, softness, distance);

    out_color = vec4(rect_color.rgb, rect_color.a * alpha);
}
