#version 450
// Fullscreen triangle for the post passes. uv in [0,1], (0,0) = top-left,
// consistent with Vulkan's framebuffer/sample origin so passes round-trip.
layout(location = 0) out vec2 uv;

void main() {
    vec2 pos;
    if (gl_VertexIndex == 0)      pos = vec2(-1.0, -3.0);
    else if (gl_VertexIndex == 1) pos = vec2(-1.0,  1.0);
    else                          pos = vec2( 3.0,  1.0);

    gl_Position = vec4(pos, 0.0, 1.0);
    uv = pos * 0.5 + 0.5;
}
