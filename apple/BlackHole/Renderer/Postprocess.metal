// Post-processing chain: TAA -> bloom (bright pass + separable blur) -> composite.
// Sources:
//   src/shaders/postprocess/ataa.wgsl.ts          (neighborhood-clamped TAA)
//   src/shaders/postprocess/bloom.glsl.ts         (threshold + 9-tap gaussian)
//   src/shaders/blackhole/chunks/common.ts        (ACES tone mapping)
//
// All pass shaders use a fullscreen triangle vertex stage.

#include <metal_stdlib>
#include "../Shared/ShaderTypes.h"
using namespace metal;

// ---------- Fullscreen triangle vertex shader ----------

struct PPVSOut {
    float4 position [[position]];
    float2 uv;
};

vertex PPVSOut pp_vs(uint vid [[vertex_id]])
{
    float2 pos;
    switch (vid) {
        case 0: pos = float2(-1.0, -3.0); break;
        case 1: pos = float2(-1.0,  1.0); break;
        default: pos = float2( 3.0,  1.0); break;
    }
    PPVSOut o;
    o.position = float4(pos, 0.0, 1.0);
    o.uv = pos * 0.5 + 0.5;
    o.uv.y = 1.0 - o.uv.y;   // flip Y so (0,0) is top-left in framebuffer space
    return o;
}

// ---------- Color helpers ----------

inline float3 rgb_to_ycocg(float3 c) {
    float y  = dot(c, float3(0.25, 0.5,  0.25));
    float co = dot(c, float3(0.5,  0.0, -0.5 ));
    float cg = dot(c, float3(-0.25, 0.5, -0.25));
    return float3(y, co, cg);
}

inline float3 ycocg_to_rgb(float3 c) {
    float y = c.x, co = c.y, cg = c.z;
    return float3(y + co - cg, y + cg, y - co - cg);
}

inline float3 aces(float3 c) {
    const float A = 2.51, B = 0.03, C = 2.43, D = 0.59, E = 0.14;
    return clamp((c * (A * c + B)) / (c * (C * c + D) + E), 0.0, 1.0);
}

// ---------- Pass 1: TAA resolve (neighborhood clamping, no motion vectors) ----------
//
// Uses a YCoCg neighborhood box around the current pixel. The history is
// clamped to that box, then mixed with the current sample. We don't have
// motion vectors here (no per-pixel reprojection), so the host is expected
// to fully reset history on large camera changes via `taaFeedback = 0`.

fragment float4 taa_fs(PPVSOut in [[stage_in]],
                       constant BHUniforms& u [[buffer(0)]],
                       texture2d<float, access::sample> currTex [[texture(0)]],
                       texture2d<float, access::sample> histTex [[texture(1)]],
                       sampler                          smp     [[sampler(0)]])
{
    uint w = currTex.get_width();
    uint h = currTex.get_height();
    uint2 pos = uint2(in.uv * float2(w, h));
    pos.x = min(pos.x, w - 1);
    pos.y = min(pos.y, h - 1);

    float3 m1 = float3(0.0);
    float3 m2 = float3(0.0);
    float3 center = rgb_to_ycocg(currTex.read(pos).rgb);
    for (int dy = -1; dy <= 1; ++dy) {
        for (int dx = -1; dx <= 1; ++dx) {
            int2 sp = int2(pos) + int2(dx, dy);
            sp = clamp(sp, int2(0), int2(int(w) - 1, int(h) - 1));
            float3 s = rgb_to_ycocg(currTex.read(uint2(sp)).rgb);
            m1 += s;
            m2 += s * s;
        }
    }
    float3 mean = m1 / 9.0;
    float3 sd   = sqrt(max(m2 / 9.0 - mean * mean, float3(0.0)));
    float3 boxMin = mean - 2.0 * sd;
    float3 boxMax = mean + 2.0 * sd;

    float3 history = rgb_to_ycocg(histTex.sample(smp, in.uv).rgb);
    history = clamp(history, boxMin, boxMax);

    float3 resolved = mix(center, history, u.taaFeedback);
    return float4(ycocg_to_rgb(resolved), 1.0);
}

// ---------- Pass 2: bright pass (luminance threshold) ----------

fragment float4 bright_fs(PPVSOut in [[stage_in]],
                          constant BHUniforms& u [[buffer(0)]],
                          texture2d<float, access::sample> tex [[texture(0)]],
                          sampler                          smp [[sampler(0)]])
{
    float3 c = tex.sample(smp, in.uv).rgb;
    float lum = dot(c, float3(0.299, 0.587, 0.114));
    return (lum > u.bloomThreshold) ? float4(c, 1.0) : float4(0, 0, 0, 1);
}

// ---------- Pass 3: separable gaussian blur (5-tap + mirrored = 9-tap) ----------
// Direction is (1,0) for horizontal, (0,1) for vertical, in pixel units.

constant float BLUR_W[5] = { 0.227027, 0.1945946, 0.1216216, 0.054054, 0.016216 };

fragment float4 blur_h_fs(PPVSOut in [[stage_in]],
                          texture2d<float, access::sample> tex [[texture(0)]],
                          sampler                          smp [[sampler(0)]])
{
    float2 texel = 1.0 / float2(tex.get_width(), tex.get_height());
    float3 r = tex.sample(smp, in.uv).rgb * BLUR_W[0];
    for (int i = 1; i < 5; ++i) {
        float2 off = float2(texel.x * float(i), 0.0);
        r += tex.sample(smp, in.uv + off).rgb * BLUR_W[i];
        r += tex.sample(smp, in.uv - off).rgb * BLUR_W[i];
    }
    return float4(r, 1.0);
}

fragment float4 blur_v_fs(PPVSOut in [[stage_in]],
                          texture2d<float, access::sample> tex [[texture(0)]],
                          sampler                          smp [[sampler(0)]])
{
    float2 texel = 1.0 / float2(tex.get_width(), tex.get_height());
    float3 r = tex.sample(smp, in.uv).rgb * BLUR_W[0];
    for (int i = 1; i < 5; ++i) {
        float2 off = float2(0.0, texel.y * float(i));
        r += tex.sample(smp, in.uv + off).rgb * BLUR_W[i];
        r += tex.sample(smp, in.uv - off).rgb * BLUR_W[i];
    }
    return float4(r, 1.0);
}

// ---------- Pass 4: composite (additive bloom + ACES + gamma) ----------

fragment float4 composite_fs(PPVSOut in [[stage_in]],
                             constant BHUniforms& u [[buffer(0)]],
                             texture2d<float, access::sample> sceneTex [[texture(0)]],
                             texture2d<float, access::sample> bloomTex [[texture(1)]],
                             sampler                          smp      [[sampler(0)]])
{
    float3 scene = sceneTex.sample(smp, in.uv).rgb;
    float3 bloom = bloomTex.sample(smp, in.uv).rgb;
    float3 result = scene + bloom * u.bloomIntensity;
    result = aces(result);
    result = pow(max(result, 0.0), float3(1.0 / 2.2));
    return float4(result, 1.0);
}

// Pass-through copy (history priming, etc.)
fragment float4 copy_fs(PPVSOut in [[stage_in]],
                        texture2d<float, access::sample> tex [[texture(0)]],
                        sampler                          smp [[sampler(0)]])
{
    return float4(tex.sample(smp, in.uv).rgb, 1.0);
}
