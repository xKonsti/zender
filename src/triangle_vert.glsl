#version 410 core

layout(location = 0) in vec2 pos;
layout(location = 1) in vec4 color;

flat out vec4 v_color;
out vec2 v_pos_screen;

uniform vec4 window_params; // xy = window size, zw = window scale
uniform mat3 u_camera_matrix; // Camera transformation matrix
uniform int u_use_camera; // 1 = apply camera, 0 = no camera

void main() {
    vec2 window_scale = window_params.zw;
    vec2 buffer_size = window_params.xy * window_scale;

    // Apply camera transform if enabled
    vec2 camera_transformed = pos;
    if (u_use_camera == 1) {
        vec3 pos_homogeneous = vec3(pos, 1.0);
        vec3 transformed = u_camera_matrix * pos_homogeneous;
        camera_transformed = transformed.xy;
    }

    // Scale to buffer coordinates
    vec2 final_pos_scaled = camera_transformed * window_scale;
    v_pos_screen = final_pos_scaled;

    // Convert to NDC
    vec2 ndc = (final_pos_scaled / buffer_size) * 2.0 - 1.0;
    ndc.y = -ndc.y; // Flip Y for top-left origin

    gl_Position = vec4(ndc, 0.0, 1.0);
    v_color = color;
}
