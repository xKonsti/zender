#version 410 core

in vec4 FragColor;                       // Color from vertex shader
in vec2 FragCoord;                       // Window-space coordinates from vertex shader

out vec4 color;                          // Final output color

// Uniforms for rectangle parameters
uniform vec2 uRectCenter;                // Center of the rectangle in window coordinates
uniform vec2 uRectSize;                  // Full width and height of the rectangle
uniform float uCornerRadius;             // Corner radius
uniform float uBorderWidth;              // Optional: border width (0.0 for filled rectangle)
uniform vec4 uBorderColor;               // Optional: border color

// Signed distance function for a rounded rectangle
float sdRoundedRect(vec2 p, vec2 b, float r) {
    vec2 q = abs(p) - b + r;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

void main() {
    // Calculate position relative to rectangle center
    vec2 p = FragCoord - uRectCenter;
    
    // Calculate half-size of the rectangle
    vec2 halfSize = uRectSize * 0.5;
    
    // Calculate the signed distance to the rounded rectangle
    float d = sdRoundedRect(p, halfSize, uCornerRadius);
    
    // Calculate anti-aliasing factor
    float aa = fwidth(d);
    
    if (uBorderWidth > 0.0) {
        // Render with border
        float outerD = d;
        float innerD = sdRoundedRect(p, halfSize - vec2(uBorderWidth), max(0.0, uCornerRadius - uBorderWidth));
        
        // Anti-aliased border
        float outerAlpha = 1.0 - smoothstep(-aa, aa, outerD);
        float innerAlpha = 1.0 - smoothstep(-aa, aa, innerD);
        float borderAlpha = outerAlpha - innerAlpha;
        
        // Mix fill and border colors
        vec4 fillColor = FragColor;
        vec4 finalColor = mix(fillColor, uBorderColor, borderAlpha / max(outerAlpha, 0.001));
        
        color = vec4(finalColor.rgb, finalColor.a * outerAlpha);
    } else {
        // Simple filled rectangle with anti-aliasing
        float alpha = 1.0 - smoothstep(-aa, aa, d);
        color = vec4(FragColor.rgb, FragColor.a * alpha);
    }
}
