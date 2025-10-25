#version 410 core

layout(location = 0) in vec2 base_pos; // Base quad vertex [-0.5, 0.5]
layout(location = 1) in vec2 inst_tl; // Instance top-left (unscaled)
layout(location = 2) in vec2 inst_size; // Instance size (unscaled)
layout(location = 3) in vec4 inst_color; // Instance color
layout(location = 4) in float inst_corner_radius; // Instance corner radius
layout(location = 5) in vec4 inst_border_width; // Border width (l, r, t, b)
layout(location = 6) in vec4 inst_border_color; // Border color
layout(location = 7) in int use_texture; // 0 = solid, 1 = text, 2 = image
layout(location = 8) in vec4 uv_data; // UV data for atlas (x, y, width, height)
layout(location = 9) in float rotation_rad; // Rotation angle in radians

flat out vec2 rect_center;
flat out vec2 rect_size;
flat out vec4 rect_color;
flat out float corner_radius;
flat out vec4 border_width;
flat out vec4 border_color;
flat out int v_use_texture;

flat out float cos_rot;
flat out float sin_rot;

out vec2 v_uv;

uniform vec4 window_params; // xy = window size, zw = window scale

void main() {
    vec2 window_scale = window_params.zw;
    vec2 buffer_size = window_params.xy * window_scale;

    // Compute the rectangle center (unscaled)
    vec2 rect_center_unscaled = inst_tl + inst_size * 0.5;

    // Build 2D rotation matrix
    float c = cos(rotation_rad);
    float s = sin(rotation_rad);
    cos_rot = c;
    sin_rot = s;
    mat2 rot = mat2(c, -s, s, c);

    // Compute vertex position relative to rectangle center, apply rotation
    vec2 local_pos = base_pos * inst_size; // base_pos is [-0.5, 0.5]
    vec2 rotated = rot * local_pos;
    vec2 final_pos_unscaled = rect_center_unscaled + rotated;

    // Convert to window coordinates
    vec2 final_pos_scaled = final_pos_unscaled * window_scale;

    // Convert to NDC: (0,0) → (-1,1), (buffer_size.x, buffer_size.y) → (1,-1)
    vec2 ndc = (final_pos_scaled / buffer_size) * 2.0 - 1.0;
    ndc.y = -ndc.y; // Flip Y for top-left origin
    gl_Position = vec4(ndc, 0.0, 1.0);

    // Pass instance data to fragment shader
    rect_center = rect_center_unscaled * window_scale;
    rect_center.y = buffer_size.y - rect_center.y;
    rect_size = inst_size * window_scale;
    rect_color = inst_color;

    float scale_min = min(window_scale.x, window_scale.y);
    corner_radius = min(inst_corner_radius * scale_min, min(rect_size.x, rect_size.y));
    border_width = inst_border_width * scale_min;
    border_color = inst_border_color;

    v_use_texture = use_texture;

    // UV mapping (base_pos in [-0.5, 0.5] → 0..1)
    vec2 quad_uv = base_pos + 0.5;
    v_uv = quad_uv * uv_data.zw + uv_data.xy;
}
