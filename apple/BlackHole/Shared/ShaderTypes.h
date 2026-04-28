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

// Shared uniforms layout. Keep 16-byte aligned for MSL `constant` buffers.
typedef struct {
    BHFloat2 resolution;         // 8B
    float    time;               // 4B
    float    mass;               // 4B    -> 16

    float    spin;               // 4B
    float    diskDensity;        // 4B
    float    diskTemp;           // 4B
    float    zoom;               // 4B    -> 32

    BHFloat2 mouse;              // 8B   yaw/pitch in 0..1
    float    lensingStrength;    // 4B
    float    diskSize;           // 4B    -> 48

    int      maxRaySteps;        // 4B
    int      enableDoppler;      // 4B
    int      enableJets;         // 4B
    int      enableLensing;      // 4B    -> 64

    int      enableDisk;         // 4B
    int      enableStars;        // 4B
    int      enablePhotonGlow;   // 4B
    int      enableRedshiftView; // 4B    -> 80

    BHFloat2 jitter;             // 8B   sub-pixel jitter for TAA
    float    diskScaleHeight;    // 4B
    float    bloomThreshold;     // 4B    -> 96

    float    bloomIntensity;     // 4B
    float    taaFeedback;        // 4B
    float    frameDragStrength;  // 4B
    int      frameIndex;         // 4B    -> 112
} BHUniforms;

#endif /* ShaderTypes_h */
