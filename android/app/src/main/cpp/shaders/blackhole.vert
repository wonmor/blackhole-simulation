#version 450
// Fullscreen triangle. Emits pixel-space fragCoord like the Metal bh_vs.
#include "common.glsl"

layout(location = 0) out vec2 fragCoord;

void main() {
    vec2 pos;
    if (gl_VertexIndex == 0)      pos = vec2(-1.0, -3.0);
    else if (gl_VertexIndex == 1) pos = vec2(-1.0,  1.0);
    else                          pos = vec2( 3.0,  1.0);

    gl_Position = vec4(pos, 0.0, 1.0);
    fragCoord = (pos * 0.5 + 0.5) * u.resolution;
}
