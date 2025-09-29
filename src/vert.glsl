#version 410 core

layout(location = 0) in vec2 aPos;       // Vertex position in window coordinates
layout(location = 1) in vec4 aColor;     // Vertex color
layout(location = 2) in vec2 aRectCenter;     // Vertex color
layout(location = 3) in vec2 aRectSize;     // Vertex color
layout(location = 4) in float aCornerRadius;     // Vertex color
layout(location = 5) in float aBorderWidth;     // Vertex color
layout(location = 6) in vec4 aBorderColor;     // Vertex color

out vec4 FragColor;                      // Output color to fragment shader
out vec2 FragCoord;                      // Output fragment coordinates to fragment shader

uniform vec2 uWindowSize;                // Window size for coordinate transformation

void main() {
    FragColor = aColor;                  // Pass color to fragment shader
    FragCoord = aPos;                    // Pass window coordinates to fragment shader
    
    // Convert from window coordinates to NDC
    // Window coords: (0,0) at top-left, (width,height) at bottom-right
    // NDC: (-1,-1) at bottom-left, (1,1) at top-right
    vec2 ndc = (aPos / uWindowSize) * 2.0 - 1.0;
    ndc.y = -ndc.y;                      // Flip Y to convert from window space to NDC
    
    gl_Position = vec4(ndc, 0.0, 1.0);  // Set the final position in NDC
}
