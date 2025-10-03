#version 410 core

flat in vec2 rect_center;
flat in vec2 rect_size;
flat in vec4 rect_color;
flat in float corner_radius;
flat in float border_width;
flat in vec4 border_color;
flat in int v_use_texture;
in vec2 v_uv;

out vec4 out_color;

uniform vec4 window_params; // window_size.xy, window_scale.xy
uniform sampler2D tex;     // Texture atlas (or white texture for solids)

float RoundedRectSDF(vec2 sample_pos, vec2 rect_rect_center, vec2 rect_half_size, float r) {
    vec2 distance2 = abs(rect_rect_center - sample_pos) - rect_half_size + vec2(r, r);
    return min(max(distance2.x, distance2.y), 0.0) + length(max(distance2, 0.0)) - r;
}

void main() {
    vec2 sample_pos = gl_FragCoord.xy;
    vec2 half_size = rect_size / 2;

    // Solid or textured color
    vec4 color = rect_color;
    if (v_use_texture == 1) {
        float mask = texture(tex, v_uv).r;
        // color.rgb *= mask;
        color.a *= mask;
        // color = vec4(1,0,0,1);
        // color = texture(tex, v_uv) * rect_color; // Multiply by tint
    }

    // INFO: DEBUG SDF
    // float dot_size = 8.0;
    // if (length(sample_pos - rect_center) < dot_size) {
    //     out_color = vec4(0,0,1,1);
    //     return;
    // }
    // float dist = RoundedRectSDF(sample_pos, rect_center, half_size -  border_width, corner_radius);
    //
    // if (dist <= 0.0) {
    //     out_color = vec4(0,1,0,1);
    // } else {
    //     out_color = vec4(1,0,0,1);
    // }
    // return;
    
    // Border SDF (if border_width > 0)
    if (border_width > 0.0) {
        float dist_inner = RoundedRectSDF(
                sample_pos,
                rect_center,
                half_size - border_width,
                max(0.0, corner_radius - border_width)
                );
        float dist_outer = RoundedRectSDF(sample_pos, rect_center, half_size, corner_radius);
        float softness = fwidth(dist_outer); // optional, for smooth edges


        if (dist_outer > 0.0) {
            color.a = 0.0;
        } else if (dist_inner < 0.0) {
            color.a = 1.0; 
        } else {
            color = mix(color, border_color, smoothstep(0.0, softness, dist_inner));
            // color.a = 1.0 - smoothstep(0.0, softness, dist_outer);
        }
    } else {
        float dist = RoundedRectSDF(sample_pos, rect_center, half_size, corner_radius);
        float softness = fwidth(dist);
        float alpha = 1.0 - smoothstep(0.0, softness, dist);
        color.a *= alpha;
    }

    out_color = color;
}
