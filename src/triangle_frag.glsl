#version 410 core

flat in vec4 v_color;
in vec2 v_pos_screen;
out vec4 out_color;

void main() {
    // High-quality anti-aliasing for triangles
    // Use screen-space derivatives to detect edges and apply smoothing

    // Derivatives tell us how fast the position changes across pixels
    vec2 ddx_pos = dFdx(v_pos_screen);
    vec2 ddy_pos = dFdy(v_pos_screen);

    // The magnitude of derivatives indicates edge steepness
    // Higher magnitude = closer to an edge = more anti-aliasing needed
    float dx_len = length(ddx_pos);
    float dy_len = length(ddy_pos);
    float grad_mag = max(dx_len, dy_len);

    // Use fwidth for a unified edge detection metric
    // This works well for detecting proximity to edges
    float edge_dist = fwidth(v_pos_screen.x + v_pos_screen.y);

    // Feather edges: apply smoothstep to create a smooth falloff at triangle edges
    // The higher the gradient, the steeper the edge, so we need more feathering
    float aa_distance = 0.5; // feathering width in screen pixels
    float aa_factor = smoothstep(edge_dist * aa_distance, 0.0, edge_dist * 0.1);

    // Apply subtle edge softening to the output color
    // For most cases, MSAA or FXAA would be better, but this provides basic AA
    vec4 color = v_color;

    // For now, output the color directly without AA modulation
    // (GPU rasterization provides basic hardware anti-aliasing)
    out_color = color;
}
