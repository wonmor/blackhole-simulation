#version 450
// Luminance threshold for the bloom bright pass.
#include "common.glsl"

layout(location = 0) in  vec2 uv;
layout(location = 0) out vec4 outColor;
layout(set = 0, binding = 1) uniform sampler2D tex;

void main() {
    vec3 c = texture(tex, uv).rgb;
    float lum = dot(c, vec3(0.299, 0.587, 0.114));
    outColor = (lum > u.bloomThreshold) ? vec4(c, 1.0) : vec4(0, 0, 0, 1);
}
