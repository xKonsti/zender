#version 410 core

layout(location = 0) in vec2 base_pos;              // Base quad vertex [-0.5, 0.5]
layout(location = 1) in vec2 inst_tl;              // Instance top-left (unscaled)
layout(location = 2) in vec2 inst_size;             // Instance size (unscaled)
layout(location = 3) in vec4 inst_color;            // Instance color
layout(location = 4) in float inst_corner_radius;   // Instance corner radius
layout(location = 5) in vec4 inst_border_width;    // Instance border width (l, r, t, b)
layout(location = 6) in vec4 inst_border_color;     // Instance border color
layout(location = 7) in int use_texture;            // 0 = solid, 1 = text, 2 = image
layout(location = 8) in vec4 uv_data;               // UV data for atlas (x, y, width, height)

flat out vec2 rect_center;
flat out vec2 rect_size;
flat out vec4 rect_color;
flat out float corner_radius;
flat out vec4 border_width;
flat out vec4 border_color;
flat out int v_use_texture;
out vec2 v_uv;

uniform vec4 window_params;

void main() {
    vec2 window_scale = window_params.zw;
    vec2 buffer_size = window_params.xy * window_scale;
    
    vec2 inst_size_scaled = inst_size * window_scale;
    vec2 inst_tl_scaled = inst_tl * window_scale; // Top-left in window coords
    vec2 base_pos_scaled = (inst_tl + (base_pos + 0.5) * inst_size) * window_scale;

    // Convert to NDC: (0,0) -> (-1,1), (buffer_size.x, buffer_size.y) -> (1,-1)
    vec2 ndc = (base_pos_scaled / buffer_size) * 2.0 - 1.0;
    ndc.y = -ndc.y; // Flip y for top-left origin
    gl_Position = vec4(ndc, 0.0, 1.0);

    rect_center = inst_tl_scaled + inst_size_scaled / 2; // Center in window coords
    rect_center.y = buffer_size.y - rect_center.y;
    rect_size = inst_size_scaled;
    rect_color = inst_color;
    corner_radius = min(inst_corner_radius * min(window_scale.x, window_scale.y), min(inst_size_scaled.x, inst_size_scaled.y));
    border_width = inst_border_width * min(window_scale.x, window_scale.y);
    border_color = inst_border_color;
    v_use_texture = use_texture; // 0 = solid, 1 = textured
    vec2 quad_uv = base_pos + 0.5; // 0..1
    v_uv = quad_uv * uv_data.zw + uv_data.xy;
}
