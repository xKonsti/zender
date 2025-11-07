#version 410 core

layout(location = 0) in vec2 base_pos; // Base quad vertex [-0.5, 0.5]
layout(location = 1) in vec2 inst_tl; // Instance top-left (unscaled)
layout(location = 2) in vec2 inst_size; // Instance size (unscaled)
layout(location = 3) in vec4 inst_color; // Instance color
layout(location = 4) in float inst_corner_radius; // Instance corner radius
layout(location = 5) in vec4 inst_border_width; // Border width (l, r, t, b)
layout(location = 6) in vec4 inst_border_color; // Border color
layout(location = 7) in int use_texture; // 0 = solid, 1 = text, 2 = image, 3 = arc
layout(location = 8) in vec4 uv_data; // UV data for atlas (x, y, width, height) OR arc angles (start_angle, end_angle, unused, unused)
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
flat out vec2 arc_angles; // start_angle, end_angle

uniform vec4 window_params; // xy = window size, zw = window scale
uniform mat3 u_camera_matrix; // Camera transformation matrix
uniform int u_use_camera; // 1 = apply camera, 0 = no camera

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

    // Conditionally expand bounding box for solids only (use_texture = 0)
    float aa_padding = (use_texture == 0) ? 2.0 / min(window_scale.x, window_scale.y) : 0.0;
    vec2 padded_size = inst_size + vec2(aa_padding);

    // Position the quad's vertex: apply rotation around center in unscaled coords
    vec2 local_pos = base_pos * padded_size; // Use padded size for vertex positions
    vec2 rotated = rot * local_pos;
    vec2 final_pos_unscaled = rotated + rect_center_unscaled;

    // Apply camera transform if enabled
    vec2 camera_transformed = final_pos_unscaled;
    vec2 camera_transformed_center = rect_center_unscaled;
    if (u_use_camera == 1) {
        vec3 pos_homogeneous = vec3(final_pos_unscaled, 1.0);
        vec3 transformed = u_camera_matrix * pos_homogeneous;
        camera_transformed = transformed.xy;

        // Also transform the rect center for fragment shader
        vec3 center_homogeneous = vec3(rect_center_unscaled, 1.0);
        vec3 center_transformed = u_camera_matrix * center_homogeneous;
        camera_transformed_center = center_transformed.xy;
    }

    // Scale to buffer coordinates
    vec2 final_pos_scaled = camera_transformed * window_scale;

    vec2 ndc = (final_pos_scaled / buffer_size) * 2.0 - 1.0;
    ndc.y = -ndc.y; // Flip Y for top-left origin in API
    gl_Position = vec4(ndc, 0.0, 1.0);

    // Pass instance data to fragment shader (in buffer coordinates)
    rect_center = camera_transformed_center * window_scale;
    // Convert to GL framebuffer coordinate space where origin is top-left
    rect_center.y = buffer_size.y - rect_center.y;

    // Extract camera zoom factor (length of first column of rotation/scale part)
    float camera_zoom = 1.0;
    if (u_use_camera == 1) {
        camera_zoom = length(u_camera_matrix[0].xy);
    }

    // Pass rect size scaled by camera zoom to fragment shader
    rect_size = inst_size * window_scale * camera_zoom; // Scaled size for SDF computation

    rect_color = inst_color;

    float scale_min = min(window_scale.x, window_scale.y) * camera_zoom;
    // Corner radius needs to be clamped against the (zoomed) rect size
    corner_radius = min(inst_corner_radius * scale_min, min(rect_size.x, rect_size.y));
    border_width = inst_border_width * scale_min;
    border_color = inst_border_color;

    v_use_texture = use_texture;

    // UV mapping: map base_pos [-0.5, 0.5] to [0, 1] for text/image, adjusted for padding
    vec2 quad_uv = (base_pos + 0.5) * (inst_size / padded_size);
    v_uv = quad_uv * uv_data.zw + uv_data.xy;

    // Arc angles (reusing uv_data for arc mode)
    arc_angles = uv_data.xy;
}
