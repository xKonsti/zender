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

void main() {
    out_color = rect_color; // Output solid orange for testing
}
