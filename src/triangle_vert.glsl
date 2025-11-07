#version 410 core

layout(location = 0) in vec2 pos;
layout(location = 1) in vec4 color;

flat out vec4 v_color;
out vec2 v_pos_screen;

uniform vec4 window_params; // xy = window size, zw = window scale

void main() {
    vec2 window_scale = window_params.zw;
    vec2 buffer_size = window_params.xy * window_scale;

    // Scale to buffer coordinates
    vec2 final_pos_scaled = pos * window_scale;
    v_pos_screen = final_pos_scaled;

    // Convert to NDC
    vec2 ndc = (final_pos_scaled / buffer_size) * 2.0 - 1.0;
    ndc.y = -ndc.y; // Flip Y for top-left origin

    gl_Position = vec4(ndc, 0.0, 1.0);
    v_color = color;
}
