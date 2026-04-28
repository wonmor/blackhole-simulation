#ifndef ShaderTypes_h
#define ShaderTypes_h

#ifdef __METAL_VERSION__
#include <metal_stdlib>
using namespace metal;
typedef float2 BHFloat2;
typedef float3 BHFloat3;
typedef float4 BHFloat4;
#else
#import <simd/simd.h>
typedef simd_float2 BHFloat2;
typedef simd_float3 BHFloat3;
typedef simd_float4 BHFloat4;
#endif

// Layout-stable struct shared between Swift and MSL.
// All fields are 4-byte aligned. Pad explicitly to keep
// 16-byte alignment for MSL `constant` buffers.
typedef struct {
    BHFloat2 resolution;       // 8B
    float    time;             // 4B
    float    mass;             // 4B    -> 16

    float    spin;             // 4B
    float    diskDensity;      // 4B
    float    diskTemp;         // 4B
    float    zoom;             // 4B    -> 32

    BHFloat2 mouse;            // 8B  (yaw/pitch in 0..1)
    float    lensingStrength;  // 4B
    float    diskSize;         // 4B    -> 48

    int      maxRaySteps;      // 4B
    float    debug;            // 4B
    float    showRedshift;     // 4B
    float    _pad0;            // 4B    -> 64
} BHUniforms;

#endif /* ShaderTypes_h */
