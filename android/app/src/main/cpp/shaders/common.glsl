// Shared uniform block — layout matches the C++ `BHUniforms` struct byte-for-byte.
// The struct is authored so std140 offsets coincide with tight 16-byte rows
// (no vec3/array members), so the host can memcpy directly into the UBO.
#ifndef BH_COMMON_GLSL
#define BH_COMMON_GLSL

layout(set = 0, binding = 0, std140) uniform U {
    vec2  resolution;          // 0
    float time;                // 8
    float mass;                // 12
    float spin;                // 16
    float diskDensity;         // 20
    float diskTemp;            // 24
    float zoom;                // 28
    vec2  mouse;               // 32  yaw/pitch in 0..1
    float lensingStrength;     // 40
    float diskSize;            // 44
    int   maxRaySteps;         // 48
    int   enableDoppler;       // 52
    int   enableJets;          // 56
    int   enableLensing;       // 60
    int   enableDisk;          // 64
    int   enableStars;         // 68
    int   enablePhotonGlow;    // 72
    int   enableRedshiftView;  // 76
    vec2  jitter;              // 80
    float diskScaleHeight;     // 88
    float bloomThreshold;      // 92
    float bloomIntensity;      // 96
    float taaFeedback;         // 100
    float frameDragStrength;   // 104
    int   frameIndex;          // 108  -> 112
} u;

float saturate(float x) { return clamp(x, 0.0, 1.0); }
vec3  saturate(vec3 x)  { return clamp(x, vec3(0.0), vec3(1.0)); }

#endif
