// Kerr black hole raymarcher - Metal port
// Sources:
//   src/shaders/blackhole/fragment.glsl.ts          (main loop)
//   src/shaders/blackhole/chunks/metric.ts          (Kerr-Schild geodesic accel)
//   src/shaders/blackhole/chunks/disk.ts            (Page-Thorne kinematics)
//   src/shaders/blackhole/chunks/blackbody.ts       (Tanner-Helland blackbody)
//   src/shaders/blackhole/chunks/background.ts      (starfield + nebula)
//
// Output: linear HDR rgba16float — bloom + ACES applied in Postprocess.metal.

#include <metal_stdlib>
#include "../Shared/ShaderTypes.h"
using namespace metal;

constant float PI       = 3.14159265359;
constant float MAX_DIST = 100.0;
constant float MIN_STEP = 0.05;
constant float MAX_STEP = 2.0;

// ---------- Vertex ----------

struct VSOut {
    float4 position [[position]];
    float2 fragCoord;
};

vertex VSOut bh_vs(uint vid [[vertex_id]],
                   constant BHUniforms& u [[buffer(0)]])
{
    float2 pos;
    switch (vid) {
        case 0: pos = float2(-1.0, -3.0); break;
        case 1: pos = float2(-1.0,  1.0); break;
        default: pos = float2( 3.0,  1.0); break;
    }
    VSOut o;
    o.position  = float4(pos, 0.0, 1.0);
    o.fragCoord = (pos * 0.5 + 0.5) * u.resolution;
    return o;
}

// ---------- Hash + Noise (procedural) ----------

inline float hash13(float3 p) {
    p = fract(p * float3(443.8975, 397.2973, 491.1871));
    p += dot(p, p.yzx + 19.19);
    return fract((p.x + p.y) * p.z);
}

inline float vnoise(float3 p) {
    float3 i = floor(p);
    float3 f = fract(p);
    float3 u = f * f * (3.0 - 2.0 * f);
    float n000 = hash13(i + float3(0,0,0));
    float n100 = hash13(i + float3(1,0,0));
    float n010 = hash13(i + float3(0,1,0));
    float n110 = hash13(i + float3(1,1,0));
    float n001 = hash13(i + float3(0,0,1));
    float n101 = hash13(i + float3(1,0,1));
    float n011 = hash13(i + float3(0,1,1));
    float n111 = hash13(i + float3(1,1,1));
    return mix(mix(mix(n000, n100, u.x), mix(n010, n110, u.x), u.y),
               mix(mix(n001, n101, u.x), mix(n011, n111, u.x), u.y), u.z);
}

inline float fbm(float3 p) {
    float a = 0.5, s = 0.0;
    for (int i = 0; i < 4; ++i) { s += a * vnoise(p); p *= 2.02; a *= 0.5; }
    return s;
}

// ---------- Blackbody (Tanner-Helland), star color ----------
// Returns linear-light RGB.
inline float3 blackbody(float temp) {
    float t = max(temp, 1.0) / 100.0;
    float r, g, b;
    if (t <= 66.0) {
        r = 255.0;
        g = 99.4708025861 * log(t) - 161.1195681661;
        b = (t <= 19.0) ? 0.0 : 138.5177312231 * log(t - 10.0) - 305.0447927307;
    } else {
        r = 329.698727446  * pow(t - 60.0, -0.1332047592);
        g = 288.1221695283 * pow(t - 60.0, -0.0755148492);
        b = 255.0;
    }
    float3 srgb = clamp(float3(r, g, b) / 255.0, 0.0, 1.0);
    return pow(max(srgb, 0.0), float3(2.2));
}

inline float3 starColor(float bv) {
    float t = clamp(bv, -0.4, 2.0);
    if (t < 0.0)  return float3(0.6, 0.7, 1.0);
    if (t < 0.3)  return float3(0.85, 0.88, 1.0);
    if (t < 0.6)  return float3(1.0, 0.96, 0.9);
    if (t < 1.0)  return float3(1.0, 0.85, 0.6);
    return float3(1.0, 0.6, 0.4);
}

// ---------- Starfield + nebula ----------

inline float3 starfield(float3 dir, float time) {
    float3 stars = float3(0.0);

    float3 cell = floor(dir * 200.0);
    float n = hash13(cell);
    if (n > 0.998) {
        float brightness = pow(n, 10.0) * 2.0;
        float bv = hash13(cell + 127.1) * 2.4 - 0.4;
        float twinkle = 0.85 + 0.15 * sin(time * (3.0 + hash13(cell + 73.7) * 2.0));
        stars = starColor(bv) * brightness * twinkle;
    }
    cell = floor(dir * 500.0);
    n = hash13(cell);
    if (n > 0.996) {
        float brightness = pow(n, 20.0) * 1.5;
        float bv = hash13(cell + 217.3) * 2.4 - 0.4;
        stars += starColor(bv) * brightness;
    }
    float neb = fbm(dir * 2.0 + float3(time * 0.01)) * 0.03;
    stars += float3(neb * 0.2, neb * 0.3, neb * 0.5) + float3(0.05, 0.02, 0.05) * abs(neb);
    return stars;
}

// ---------- Kerr metric helpers ----------

inline float kerr_horizon(float M, float a) {
    return M + sqrt(max(0.0, M*M - a*a));
}

// Bardeen, Press & Teukolsky 1972
inline float kerr_isco(float M, float a) {
    float aStar = a / max(M, 1e-6);
    float absS = abs(clamp(aStar, -0.9999, 0.9999));
    float z1 = 1.0 + pow(1.0 - absS*absS, 1.0/3.0) *
               (pow(1.0 + absS, 1.0/3.0) + pow(1.0 - absS, 1.0/3.0));
    float z2 = sqrt(3.0 * absS*absS + z1*z1);
    float s = (a >= 0.0) ? 1.0 : -1.0;
    return M * (3.0 + z2 - s * sqrt((3.0 - z1) * (3.0 + z1 + 2.0 * z2)));
}

// Bardeen 1973, prograde photon sphere
inline float kerr_photon_sphere(float M, float a) {
    float aStar = clamp(a / max(M, 1e-6), -0.9999, 0.9999);
    float arg = clamp(-aStar, -1.0, 1.0);
    float theta = (2.0/3.0) * acos(arg);
    return 2.0 * M * (1.0 + cos(theta));
}

inline float kerr_ergosphere(float M, float a, float r, float cosTheta) {
    return M + sqrt(max(0.0, M*M - a*a * cosTheta*cosTheta));
}

// Oblate spheroidal Kerr radial coordinate
inline float kerr_r(float3 p, float a) {
    float a2 = a*a;
    float rho2 = dot(p, p);
    float diff = rho2 - a2;
    float disc = diff*diff + 4.0 * a2 * p.y*p.y;
    float r2 = 0.5 * (diff + sqrt(max(0.0, disc)));
    return sqrt(max(1e-8, r2));
}

struct KerrAccel {
    float3 accel;
    float  rK;
    float  omega;
};

// Kerr-Schild Hamiltonian geodesic acceleration
inline KerrAccel kerr_accel(float3 p, float3 v, float M, float a) {
    KerrAccel res;
    float a2 = a * a;
    float rho2 = dot(p, p);
    float diff = rho2 - a2;
    float disc = diff*diff + 4.0 * a2 * p.y*p.y;
    float r2 = 0.5 * (diff + sqrt(max(0.0, disc)));
    float rK = sqrt(max(1e-8, r2));
    res.rK = rK;

    // Effective angular momentum (Bardeen 1973): L_eff² = (Lz - a)² + Q
    float3 L = cross(p, v);
    float Ly = L.y;
    float Ly_eff = Ly - a;
    float L2_eff = Ly_eff * Ly_eff + (dot(L, L) - Ly * Ly);

    float r_inv  = 1.0 / rK;
    float r2_inv = r_inv * r_inv;
    float r4_inv = r2_inv * r2_inv;

    // Σ = r² + a²cos²θ for spin along Y
    float sigma = r2 + a2 * (p.y*p.y / max(1e-8, r2));
    float sigma_ratio = r2 / max(1e-8, sigma);

    float3 r_hat = -normalize(p);

    // Radial: -(M/r² + 3M·L_eff²/r⁴) r̂ with Kerr-Schild correction
    res.accel = r_hat * (M * r2_inv * sigma_ratio +
                         3.0 * M * max(0.0, L2_eff) * r4_inv * sigma_ratio);

    // Frame-dragging gravito-magnetic force
    float drag_denom = rK * r2 + a2 * rK;
    float drag_coeff = 2.0 * M * a / max(1e-8, drag_denom);
    res.accel += cross(float3(0.0, 1.0, 0.0), v) * drag_coeff;

    // ZAMO angular velocity
    res.omega = 2.0 * M * a / max(1e-8, drag_denom);
    return res;
}

inline float2x2 rot(float angle) {
    float s = sin(angle), c = cos(angle);
    return float2x2(c, -s, s, c);
}

// ---------- Disk sampling ----------
// Page & Thorne kinematics with exact Kerr Doppler factor.
inline float3 sample_disk(thread float3 &p, float3 p_prev, thread float3 &v,
                          float r, float isco, float M, float a, float dt,
                          constant BHUniforms& u, thread float &alpha)
{
    if (alpha > 0.99) return float3(0.0);

    // Plane crossing detection — fill holes from step-skipping
    bool crossedEquator = (p_prev.y * p.y < 0.0);
    float3 sampleP = p;
    if (crossedEquator) {
        float t = abs(p_prev.y) / max(1e-4, abs(p_prev.y) + abs(p.y));
        sampleP = mix(p_prev, p, t);
    }
    float sampleR = length(sampleP);

    float effectiveScaleHeight = min(u.diskScaleHeight, 0.20);
    float diskHeight = sampleR * effectiveScaleHeight;
    float diskInner = isco;
    float diskOuter = max(M * u.diskSize, diskInner * 1.1);

    if (!((abs(sampleP.y) < diskHeight || crossedEquator) &&
          sampleR > diskInner && sampleR < diskOuter)) {
        return float3(0.0);
    }

    // Frame-dragged turbulence rotation
    float sqrt_M = sqrt(max(M, 1e-6));
    float signSpin = (u.spin >= 0.0) ? 1.0 : -1.0;
    float OmegaPhase = (signSpin * sqrt_M) /
                       (sampleR * sqrt(sampleR) + a * sqrt_M);
    float rotAngle = OmegaPhase * u.time * 1.0 * 10.0;
    float2x2 rotPhase = rot(rotAngle);
    float3 noiseP = sampleP;
    {
        float2 xz = rotPhase * float2(noiseP.x, noiseP.z);
        noiseP.x = xz.x; noiseP.z = xz.y;
    }
    noiseP *= 1.5;
    float turbulence = vnoise(noiseP) * 0.5 + vnoise(noiseP * 3.0) * 0.25;

    float heightFalloff = exp(-abs(sampleP.y) /
                              max(1e-3, sampleR * effectiveScaleHeight * 0.5));
    float radialFalloff = smoothstep(diskOuter, diskInner, sampleR);
    float baseDensity = turbulence * heightFalloff * radialFalloff;
    if (baseDensity <= 0.001) return float3(0.0);

    // Page–Thorne / Kerr equatorial kinematics
    float r2 = sampleR * sampleR;
    float Omega = (signSpin * sqrt_M) /
                  (sampleR * sqrt(sampleR) + a * sqrt_M);
    float g_tt = -(1.0 - 2.0 * M / sampleR);
    float g_tphi = -2.0 * M * a / sampleR;
    float g_phiphi = r2 + a*a + 2.0 * M * a*a / sampleR;
    float u_t_sq = -(g_tt + 2.0 * Omega * g_tphi + Omega * Omega * g_phiphi);
    float u_t = 1.0 / sqrt(max(1e-6, u_t_sq));

    // Photon angular momentum proxy from the local frame
    float L_photon = p.z * v.x - p.x * v.z;

    // Doppler factor δ = 1 / (u_t (1 - Ω L))
    float delta = 1.0 / max(0.01, u_t * (1.0 - Omega * L_photon));

    float beaming = (u.enableDoppler != 0) ? max(0.01, pow(delta, 3.5)) : 1.0;

    // Novikov-Thorne temperature with zero-torque inner boundary
    float isco_r = clamp(isco / sampleR, 0.0, 1.0);
    float nt_factor = max(0.0, 1.0 - sqrt(isco_r));
    float radialTempGradient = pow(isco_r, 0.75) * pow(nt_factor, 0.25);
    float temperature = u.diskTemp * 8000.0 * radialTempGradient * delta;

    float3 diskColor = blackbody(temperature) * beaming;
    float density = baseDensity * u.diskDensity * 0.12 * dt;

    float3 emission = diskColor * density * (1.0 - alpha);
    alpha = saturate(alpha + density);
    return emission;
}

// ---------- Relativistic jets ----------

inline float3 sample_jet(float3 p, float3 v, float r, float rh, float dt,
                         float time, thread float &alpha)
{
    if (alpha > 0.99) return float3(0.0);
    float jy = abs(p.y);
    if (jy <= rh * 1.8 || jy >= MAX_DIST * 0.8) return float3(0.0);

    float jr = length(p.xz);
    float jw = 1.0 + jy * 0.15;
    if (jr >= jw * 2.0) return float3(0.0);

    float radialFalloff = exp(-(jr*jr) / (jw * 0.5));
    float lengthFalloff = exp(-jy * 0.05);
    float flow = p.y * 2.0 - time * 8.0;
    float3 uvJ = float3(p.x, flow, p.z);
    float n = vnoise(uvJ * 0.5) * 0.6 + vnoise(uvJ * 1.5) * 0.4;
    float jd = radialFalloff * lengthFalloff * max(0.0, n - 0.2);
    if (jd <= 0.001) return float3(0.0);

    float jetVel = 0.92 * sign(p.y);
    float3 jetVec = float3(0.0, jetVel, 0.0);
    float cosT = dot(normalize(jetVec), -v);
    float beta = abs(jetVel);
    float gamma = 1.0 / sqrt(1.0 - beta * beta);
    float deltaJet = 1.0 / (gamma * (1.0 - beta * cosT));
    float beam = pow(deltaJet, 3.5);
    float3 base = float3(0.4, 0.7, 1.0);
    float3 emit = base * jd * 0.05 * beam * dt;
    alpha = saturate(alpha + jd * 0.05 * dt);
    return emit * (1.0 - alpha);
}

// ---------- Fragment ----------

fragment float4 bh_fs(VSOut in [[stage_in]],
                      constant BHUniforms& u [[buffer(0)]])
{
    float minRes = min(u.resolution.x, u.resolution.y);
    float2 uv = (in.fragCoord + u.jitter - 0.5 * u.resolution) / minRes;

    // Camera
    float3 ro = float3(0.0, 0.0, -u.zoom);
    float3 rd = normalize(float3(uv, 1.5));

    float2x2 rx = rot((u.mouse.y - 0.5) * PI);
    float2x2 ry = rot((u.mouse.x - 0.5) * 2.0 * PI);
    {
        float2 yz = rx * float2(ro.y, ro.z); ro.y = yz.x; ro.z = yz.y;
        float2 vyz = rx * float2(rd.y, rd.z); rd.y = vyz.x; rd.z = vyz.y;
        float2 xz = ry * float2(ro.x, ro.z); ro.x = xz.x; ro.z = xz.y;
        float2 vxz = ry * float2(rd.x, rd.z); rd.x = vxz.x; rd.z = vxz.y;
    }

    float M  = max(u.mass, 0.05);
    float a  = clamp(u.spin * M, -M * 0.9999, M * 0.9999);
    float rh  = kerr_horizon(M, a);
    float rph = kerr_photon_sphere(M, a);
    float isco = kerr_isco(M, a);

    float3 p = ro;
    float3 v = rd;

    // Push the ray off the horizon if we started inside.
    if (length(p) < rh * 1.5) p = normalize(p) * rh * 1.5;

    float3 acc = float3(0.0);
    float  alpha = 0.0;
    bool hitHorizon = false;
    float maxRedshift = 0.0;
    bool redshiftInit = false;

    float impact = length(cross(p, v));
    if (impact < rh * 0.9) hitHorizon = true;

    // Blue-noise dither (procedural substitute)
    float bn = hash13(float3(in.fragCoord, float(u.frameIndex)));
    p += v * bn * MIN_STEP;

    int maxSteps = clamp(u.maxRaySteps, 32, 500);
    float3 p_prev = p;

    for (int i = 0; i < maxSteps && !hitHorizon; ++i) {
        p_prev = p;
        float r = length(p);
        if (r < rh * 1.10) { hitHorizon = true; break; }
        if (r > MAX_DIST) break;

        // Adaptive step size with curvature awareness
        float distFactor = 1.0 + r * 0.05;
        float dt = clamp((r - rh) * 0.1 * distFactor, MIN_STEP, MAX_STEP * distFactor);
        if (r > 30.0) {
            float farBoost = (r - 30.0) * 0.08;
            dt = max(dt, MIN_STEP + farBoost);
            dt = min(dt, MAX_STEP * 2.5);
        }
        float sphereProx = abs(r - rph);
        dt = min(dt, MIN_STEP + sphereProx * 0.15);
        float hRefine = smoothstep(0.2, 0.0, abs(p.y));
        float currentDt = dt * (1.0 - hRefine * 0.7);

        // Kerr geodesic acceleration + ZAMO velocity rotation
        float3 accel = float3(0.0);
        float omega = 0.0;
        if (u.enableLensing != 0) {
            KerrAccel kA = kerr_accel(p, v, M, a);
            accel = kA.accel * u.lensingStrength;
            omega = kA.omega * u.frameDragStrength;
            float2x2 zamo = rot(omega * currentDt);
            float2 xz = zamo * float2(v.x, v.z);
            v.x = xz.x; v.z = xz.y;
        }

        // Velocity-Verlet step
        p += v * currentDt + 0.5 * accel * currentDt * currentDt;

        if (u.enableLensing != 0 && alpha < 0.95) {
            KerrAccel kB = kerr_accel(p, v, M, a);
            float3 accelNew = kB.accel * u.lensingStrength;
            v += 0.5 * (accel + accelNew) * currentDt;
        }
        v = normalize(v);

        // Redshift tracking (Schwarzschild proxy)
        if (u.enableRedshiftView != 0) {
            float pot = sqrt(max(0.0, 1.0 - 2.0 * M / max(length(p), 1e-3)));
            if (!redshiftInit) { maxRedshift = pot; redshiftInit = true; }
            else maxRedshift = min(maxRedshift, pot);
        }

        // Disk emission
        if (u.enableDisk != 0) {
            acc += sample_disk(p, p_prev, v, length(p), isco, M, a, currentDt, u, alpha);
        }
        if (u.enableJets != 0) {
            acc += sample_jet(p, v, length(p), rh, currentDt, u.time, alpha);
        }
        if (alpha > 0.99) break;
    }

    // Redshift overlay
    if (u.enableRedshiftView != 0) {
        float val = hitHorizon ? 0.0 : maxRedshift;
        float3 heat = mix(float3(0.0), float3(1, 0, 0), smoothstep(0.0, 0.3, val));
        heat = mix(heat, float3(1, 1, 0), smoothstep(0.3, 0.7, val));
        heat = mix(heat, float3(0, 0, 1), smoothstep(0.7, 1.0, val));
        return float4(heat, 1.0);
    }

    // Background + photon ring + ergosphere
    float3 background = float3(0.0);
    if (u.enableStars != 0 && !hitHorizon) background = starfield(v, u.time);

    float3 photon = float3(0.0);
    if (u.enablePhotonGlow != 0 && !hitHorizon) {
        float distToRing = abs(length(p) - rph);
        photon = float3(1.0) * exp(-distToRing * 40.0) * 1.8 * u.lensingStrength;
    }

    float3 ergo = float3(0.0);
    float absA = abs(u.spin);
    if (absA > 0.1 && !hitHorizon) {
        float rFinal = length(p);
        float cosTheta = p.y / max(rFinal, 1e-3);
        float r_ergo = kerr_ergosphere(M, a, rFinal, cosTheta);
        float ergoGlow = exp(-abs(rFinal - r_ergo) * 20.0) * 0.35 * absA;
        ergo = float3(0.3, 0.35, 0.9) * ergoGlow;
    }

    if (hitHorizon) background = float3(0.0);

    float3 col = background * (1.0 - alpha)
               + acc
               + photon * (1.0 - alpha)
               + ergo * (1.0 - alpha);

    // HDR linear output — tone mapping happens later.
    return float4(max(col, 0.0), 1.0);
}
