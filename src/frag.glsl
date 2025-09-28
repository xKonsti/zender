#version 410 core
in vec2 vPos;
in vec4 vColor;

out vec4 FragColor;

uniform vec2 uRectPos;   // rect top-left (x, y)
uniform vec2 uRectSize;  // rect width, height
uniform float uRadius;   // corner radius in px

void main() {
    vec2 local = vPos - uRectPos;      // pixel position relative to rect
    vec2 size = uRectSize;

    // clamp to nearest corner
    vec2 corner = clamp(local, vec2(uRadius), size - vec2(uRadius));
    float dist = length(local - corner);

    if (dist > uRadius) {
        discard; // outside rounded corner
    }

    FragColor = vColor;
}
