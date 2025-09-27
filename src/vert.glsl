#version 410 core
layout(location = 0) in vec3 aPos;
layout(location = 1) in vec4 aColor;

out vec4 vColor;

uniform vec2 uWindowSize;

void main() {
    vColor = aColor;
    // Convert from pixel coords → NDC [-1,1]
    float ndcX = (aPos.x / uWindowSize.x) * 2.0 - 1.0;
    float ndcY = 1.0 - (aPos.y / uWindowSize.y) * 2.0; // flip Y for top-left origin
    gl_Position = vec4(ndcX, ndcY, 0.0, 1.0);
}
