#version 450
// Additive bloom + ACES + gamma. Writes the swapchain image.
#include "common.glsl"

layout(location = 0) in  vec2 uv;
layout(location = 0) out vec4 outColor;
layout(set = 0, binding = 1) uniform sampler2D sceneTex;
layout(set = 0, binding = 2) uniform sampler2D bloomTex;

vec3 aces(vec3 c) {
    const float A = 2.51, B = 0.03, C = 2.43, D = 0.59, E = 0.14;
    return clamp((c * (A * c + B)) / (c * (C * c + D) + E), 0.0, 1.0);
}

void main() {
    vec3 scene = texture(sceneTex, uv).rgb;
    vec3 bloom = texture(bloomTex, uv).rgb;
    vec3 result = scene + bloom * u.bloomIntensity;
    result = aces(result);
    result = pow(max(result, vec3(0.0)), vec3(1.0 / 2.2));
    outColor = vec4(result, 1.0);
}
