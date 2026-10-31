#version 450
// Neighborhood-clamped temporal AA (no motion vectors). Host resets history
// via taaFeedback = 0 on large camera changes.
#include "common.glsl"

layout(location = 0) in  vec2 uv;
layout(location = 0) out vec4 outColor;

layout(set = 0, binding = 1) uniform sampler2D currTex;
layout(set = 0, binding = 2) uniform sampler2D histTex;

vec3 rgb_to_ycocg(vec3 c) {
    return vec3(dot(c, vec3(0.25, 0.5, 0.25)),
                dot(c, vec3(0.5, 0.0, -0.5)),
                dot(c, vec3(-0.25, 0.5, -0.25)));
}
vec3 ycocg_to_rgb(vec3 c) {
    float y = c.x, co = c.y, cg = c.z;
    return vec3(y + co - cg, y + cg, y - co - cg);
}

void main() {
    ivec2 sz = textureSize(currTex, 0);
    int w = sz.x, h = sz.y;
    ivec2 pos = ivec2(uv * vec2(w, h));
    pos.x = min(pos.x, w - 1);
    pos.y = min(pos.y, h - 1);

    vec3 m1 = vec3(0.0);
    vec3 m2 = vec3(0.0);
    vec3 center = rgb_to_ycocg(texelFetch(currTex, pos, 0).rgb);
    if (any(isnan(center)) || any(isinf(center))) center = vec3(0.0);
    for (int dy = -1; dy <= 1; ++dy) {
        for (int dx = -1; dx <= 1; ++dx) {
            ivec2 sp = clamp(pos + ivec2(dx, dy), ivec2(0), ivec2(w - 1, h - 1));
            vec3 s = rgb_to_ycocg(texelFetch(currTex, sp, 0).rgb);
            if (any(isnan(s)) || any(isinf(s))) s = vec3(0.0);
            m1 += s;
            m2 += s * s;
        }
    }
    vec3 mean = m1 / 9.0;
    vec3 sd   = sqrt(max(m2 / 9.0 - mean * mean, vec3(0.0)));
    vec3 boxMin = mean - 2.0 * sd;
    vec3 boxMax = mean + 2.0 * sd;

    vec3 history = rgb_to_ycocg(texture(histTex, uv).rgb);
    // A freshly allocated history target holds undefined memory; some
    // Mali/PowerVR drivers hand back NaN/Inf there. NaN * 0 is still NaN, so
    // scrub it explicitly instead of trusting taaFeedback = 0.
    if (any(isnan(history)) || any(isinf(history))) history = center;
    history = clamp(history, boxMin, boxMax);

    vec3 resolved = mix(center, history, u.taaFeedback);
    outColor = vec4(ycocg_to_rgb(resolved), 1.0);
}
