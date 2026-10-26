#version 450
// Separable 9-tap gaussian. HORIZONTAL specialization constant selects the
// axis, mirroring the two Metal blur_h / blur_v functions with one shader.
layout(location = 0) in  vec2 uv;
layout(location = 0) out vec4 outColor;
layout(set = 0, binding = 1) uniform sampler2D tex;

layout(constant_id = 0) const bool HORIZONTAL = true;

const float BLUR_W[5] = float[](0.227027, 0.1945946, 0.1216216, 0.054054, 0.016216);

void main() {
    vec2 texel = 1.0 / vec2(textureSize(tex, 0));
    vec3 r = texture(tex, uv).rgb * BLUR_W[0];
    for (int i = 1; i < 5; ++i) {
        vec2 off = HORIZONTAL ? vec2(texel.x * float(i), 0.0)
                              : vec2(0.0, texel.y * float(i));
        r += texture(tex, uv + off).rgb * BLUR_W[i];
        r += texture(tex, uv - off).rgb * BLUR_W[i];
    }
    outColor = vec4(r, 1.0);
}
