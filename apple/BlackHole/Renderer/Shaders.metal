#include <metal_stdlib>
#include "../Shared/ShaderTypes.h"
using namespace metal;

// Black hole raymarcher
// Ported from src/shaders/blackhole/raymarching.wgsl.ts
// + Velocity-Verlet structure from src/shaders/blackhole/fragment.glsl.ts
// V1 uses Newtonian-corrected gravity (not full Kerr geodesics).

constant float PI       = 3.14159265359;
constant float MAX_DIST = 100.0;
constant float MIN_STEP = 0.05;
constant float MAX_STEP = 2.0;

// ---------- Vertex: fullscreen triangle ----------

struct VSOut {
    float4 position [[position]];
    float2 fragCoord;
};

vertex VSOut vs_main(uint vid [[vertex_id]],
                     constant BHUniforms& u [[buffer(0)]])
{
    // Single oversized triangle covering the screen.
    float2 pos;
    switch (vid) {
        case 0: pos = float2(-1.0, -3.0); break;
        case 1: pos = float2(-1.0,  1.0); break;
        default: pos = float2( 3.0,  1.0); break;
    }
    VSOut o;
    o.position  = float4(pos, 0.0, 1.0);
    // Fragment coords in pixels with origin at bottom-left.
    o.fragCoord = (pos * 0.5 + 0.5) * u.resolution;
    return o;
}

// ---------- Helpers ----------

inline float2x2 rot(float a) {
    float s = sin(a), c = cos(a);
    return float2x2(c, -s, s, c);
}

// 3D hash → [0,1]. Cheap, deterministic.
inline float hash13(float3 p) {
    p = fract(p * float3(443.8975, 397.2973, 491.1871));
    p += dot(p, p.yzx + 19.19);
    return fract((p.x + p.y) * p.z);
}

// Procedural starfield based on ray direction
inline float3 starfield(float3 dir) {
    float3 cell = floor(dir * 200.0);
    float h = hash13(cell);
    if (h > 0.997) {
        float b = pow(h, 12.0) * 4.0;
        // Slight blue/yellow tint per star
        float3 tint = mix(float3(0.85, 0.92, 1.0),
                          float3(1.0, 0.95, 0.80),
                          fract(h * 71.0));
        return tint * b;
    }
    return float3(0.0);
}

// Reinhard tone mapping
inline float3 tonemap(float3 c) {
    return c / (c + float3(1.0));
}

// ---------- Disk ----------
// Thin equatorial accretion disk between r ∈ [innerR, outerR]
// modulated by a temperature gradient and angular swirl.
inline float3 sample_disk(float3 p, float3 v, float r, float innerR, float outerR,
                          float t, float diskTemp, float diskDensity, thread float &alpha)
{
    float3 result = float3(0.0);
    if (alpha > 0.99) return result;

    // Disk geometry: thin slab around y = 0
    float thickness = 0.25 + r * 0.04;
    float vert = abs(p.y) / thickness;
    if (vert > 1.5) return result;
    if (r < innerR || r > outerR) return result;

    // Radial brightness falloff
    float radial = (1.0 - smoothstep(innerR, outerR, r)) *
                   smoothstep(innerR * 0.95, innerR * 1.10, r);
    float vertFalloff = exp(-vert * vert * 1.5);

    // Swirl pattern (Doppler-like asymmetry placeholder)
    float phi = atan2(p.z, p.x);
    float swirl = 0.5 + 0.5 * sin(phi * 3.0 - t * 0.6 + r * 1.2);
    float turbulence = 0.5 + 0.5 * sin(phi * 17.0 + r * 5.0);

    // Color: hot blue inner, warm outer
    float tNorm = saturate((r - innerR) / max(outerR - innerR, 0.001));
    float3 hot  = float3(0.85, 0.95, 1.20);
    float3 warm = float3(1.20, 0.55, 0.20);
    float3 col  = mix(hot, warm, tNorm) * diskTemp;

    float density = radial * vertFalloff * (0.6 + 0.4 * swirl) * (0.7 + 0.6 * turbulence);
    density *= diskDensity;

    // Front-side Doppler boost: brighter where moving toward the camera (-z)
    float doppler = saturate(0.5 - 0.5 * dot(normalize(p), normalize(v)));
    col *= (0.6 + 1.4 * doppler);

    float aStep = saturate(density * 0.35);
    result = col * aStep * (1.0 - alpha);
    alpha = saturate(alpha + aStep * (1.0 - alpha));
    return result;
}

// ---------- Fragment: raymarcher ----------

fragment float4 fs_main(VSOut in [[stage_in]],
                        constant BHUniforms& u [[buffer(0)]])
{
    float minRes = min(u.resolution.x, u.resolution.y);
    float2 uv = (in.fragCoord - 0.5 * u.resolution) / minRes;

    // Camera ray
    float3 ro = float3(0.0, 0.0, -u.zoom);
    float3 rd = normalize(float3(uv, 1.5));

    // Mouse-driven yaw/pitch
    float2x2 rx = rot((u.mouse.y - 0.5) * PI);
    float2x2 ry = rot((u.mouse.x - 0.5) * 2.0 * PI);
    {
        float2 yz = rx * float2(ro.y, ro.z); ro.y = yz.x; ro.z = yz.y;
        float2 vyz = rx * float2(rd.y, rd.z); rd.y = vyz.x; rd.z = vyz.y;
        float2 xz = ry * float2(ro.x, ro.z); ro.x = xz.x; ro.z = xz.y;
        float2 vxz = ry * float2(rd.x, rd.z); rd.x = vxz.x; rd.z = vxz.y;
    }

    float M  = max(u.mass, 0.05);
    float rh = 2.0 * M;          // Schwarzschild horizon
    float rph = 3.0 * M;         // photon sphere (Schwarzschild)
    float innerR = 3.0 * M;       // ISCO-ish for v1
    float outerR = innerR + max(u.diskSize, 1.0);

    float3 p = ro;
    float3 v = rd;

    // Don't start inside the horizon
    if (length(p) < rh * 1.5) {
        p = normalize(p) * rh * 1.5;
    }

    // Cull rays whose impact parameter is clearly captured.
    float impactParam = length(cross(p, v));
    bool hitHorizon = impactParam < rh * 0.9;

    float3 acc = float3(0.0);
    float  alpha = 0.0;

    int maxSteps = clamp(u.maxRaySteps, 32, 500);

    for (int i = 0; i < maxSteps; ++i) {
        float r = length(p);
        if (r < rh * 1.01) { hitHorizon = true; break; }
        if (r > MAX_DIST) break;

        // Adaptive step
        float distFactor = 1.0 + r * 0.05;
        float dt = clamp((r - rh) * 0.1 * distFactor, MIN_STEP, MAX_STEP * distFactor);
        float sphereProx = abs(r - rph);
        dt = min(dt, MIN_STEP + sphereProx * 0.15);

        // Refine through the disk plane
        float hRefine = smoothstep(0.2, 0.0, abs(p.y));
        float currentDt = dt * (1.0 - hRefine * 0.7);

        // Newtonian-corrected acceleration: -GM r̂ / r²
        float3 accel = -normalize(p) * (M / max(r * r, 1e-4)) * u.lensingStrength;

        // Velocity-Verlet position step
        p += v * currentDt + 0.5 * accel * currentDt * currentDt;

        if (alpha < 0.95) {
            float r2 = max(length(p), 1e-4);
            float3 accelNew = -normalize(p) * (M / (r2 * r2)) * u.lensingStrength;
            v += 0.5 * (accel + accelNew) * currentDt;
        }
        v = normalize(v);

        // Sample the disk
        acc += sample_disk(p, v, length(p), innerR, outerR, u.time,
                           u.diskTemp, u.diskDensity, alpha);
        if (alpha > 0.99) break;
    }

    // Background + photon ring
    float3 background = hitHorizon ? float3(0.0) : starfield(v);

    float3 photon = float3(0.0);
    if (!hitHorizon) {
        float distToRing = abs(length(p) - rph);
        photon = float3(1.0) * exp(-distToRing * 18.0) * 0.6 * u.lensingStrength;
    }

    float3 col = background * (1.0 - alpha) + acc + photon * (1.0 - alpha);

    if (u.showRedshift > 0.5 && hitHorizon) {
        col = float3(0.0);
    }

    // Tone map + gamma
    col = tonemap(col);
    col = pow(max(col, 0.0), float3(1.0 / 2.2));
    return float4(col, 1.0);
}
