#version 410 core

layout(location = 0) in vec2 aPos;           // Vertex position in window coordinates
layout(location = 1) in vec4 aColor;         // Vertex color
layout(location = 2) in vec2 aRectCenter;    // Rectangle center
layout(location = 3) in vec2 aRectSize;      // Rectangle size
layout(location = 4) in float aCornerRadius; // Corner radius
layout(location = 5) in float aBorderWidth;  // Border width
layout(location = 6) in vec4 aBorderColor;   // Border color

out vec2 rect_pos;
flat out vec2 rect_center;
flat out vec2 rect_size;
flat out vec4 rect_color;
flat out float corner_radius;

uniform vec2 window_size;                    // Window size for coordinate transformation

void main() {
    rect_pos = aPos;
    rect_center = aRectCenter;
    rect_size = aRectSize;
    rect_color = aColor;
    corner_radius = aCornerRadius;

    // Convert from window coordinates to NDC
    // Window coords: (0,0) at top-left, (width,height) at bottom-right
    // NDC: (-1,-1) at bottom-left, (1,1) at top-right
    vec2 ndc = (aPos / window_size) * 2.0 - 1.0;
    ndc.y = -ndc.y;                          // Flip Y to convert from window space to NDC
    
    gl_Position = vec4(ndc, 0.0, 1.0);      // Set the final position in NDC
}
