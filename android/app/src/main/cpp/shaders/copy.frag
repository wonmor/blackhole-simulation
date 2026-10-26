#version 450
// Pass-through copy (TAA-disabled path / history priming).
layout(location = 0) in  vec2 uv;
layout(location = 0) out vec4 outColor;
layout(set = 0, binding = 1) uniform sampler2D tex;

void main() {
    outColor = vec4(texture(tex, uv).rgb, 1.0);
}
