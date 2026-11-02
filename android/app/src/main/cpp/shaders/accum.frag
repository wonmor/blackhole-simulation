#version 450
// Running mean for offscreen export supersampling: out = mix(curr, hist, k)
// with k = n / (n + 1). Unlike taa.frag there is no neighbourhood clamp, so
// N jittered passes converge to a true N-sample average.
#include "common.glsl"

layout(location = 0) in  vec2 uv;
layout(location = 0) out vec4 outColor;
layout(set = 0, binding = 1) uniform sampler2D currTex;
layout(set = 0, binding = 2) uniform sampler2D histTex;

void main() {
    vec3 c = texture(currTex, uv).rgb;
    vec3 h = texture(histTex, uv).rgb;
    if (any(isnan(c)) || any(isinf(c))) c = vec3(0.0);
    if (any(isnan(h)) || any(isinf(h))) h = c;
    outColor = vec4(mix(c, h, u.taaFeedback), 1.0);
}
