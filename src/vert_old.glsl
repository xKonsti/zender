#version 410 core

layout(location = 0) in vec2 base_pos;              // Base quad vertex [-0.5, 0.5]
layout(location = 1) in vec2 inst_pos;              // Instance top-left (unscaled)
layout(location = 2) in vec2 inst_size;             // Instance size (unscaled)
layout(location = 3) in vec4 inst_color;            // Instance color
layout(location = 4) in float inst_corner_radius;   // Instance corner radius
layout(location = 5) in float inst_border_width;    // Instance border width
layout(location = 6) in vec4 inst_border_color;     // Instance border color
layout(location = 7) in int use_texture;            // 0 = solid, 1 = textured
layout(location = 8) in vec2 uv_offset;             // UV offset for atlas

flat out vec2 rect_center;
flat out vec2 rect_size;
flat out vec4 rect_color;
flat out float corner_radius;
flat out float border_width;
flat out vec4 border_color;
flat out int v_use_texture;
out vec2 v_uv;

uniform vec4 window_params; // vec2 size, vec2 scale

void main() {
    vec2 window_size = window_params.xy;
    vec2 window_scale = window_params.zw;

    // Scale base_pos by inst_size and translate by inst_pos
    vec2 scaled_size = inst_size * window_scale;
    vec2 scaled_pos = (inst_pos + base_pos * inst_size) * window_scale;

    // Convert to NDC: (0,0) top-left -> (-1,1), (width,height) bottom-right -> (1,-1)
    vec2 ndc = (scaled_pos / window_size) * 2.0 - 1.0;
    ndc.y = -ndc.y; // Flip y for top-left origin
    gl_Position = vec4(ndc, 0.0, 1.0);

    // Pass to fragment (unscaled for SDF, in world coords)
    rect_center = inst_pos + inst_size * 0.5; // Center in unscaled coords
    rect_size = inst_size;
    rect_color = inst_color;
    corner_radius = inst_corner_radius;
    border_width = inst_border_width;
    border_color = inst_border_color;
    v_use_texture = use_texture;
    v_uv = base_pos + 0.5 + uv_offset; // Map [-0.5,0.5] to [0,1] UV + offset
}
