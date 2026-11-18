// iBlackHole for Apple Vision Pro: stereo Kerr black hole that sits in the room.
//
// Two passes per eye, both driven by CompositorServices views:
//
//  A  bh_march_fs     Offscreen, at an adaptive fraction of the eye resolution.
//                     Rays that miss the black hole's bounding sphere exit after
//                     one ray/sphere test. Rays that enter it are integrated
//                     through the same Kerr acceleration, disk and jet model as
//                     the iPhone / Mac renderer (BlackHole.metal), with a step
//                     budget the CPU governor keeps inside the 90 fps frame.
//                     Output 0: premultiplied emission + opacity.
//                     Output 1: escape direction in world space (w = 1).
//
//  B  bh_composite_fs Full resolution with the system foveation map. Upsamples A,
//                     draws point stars along the lensed direction (weak-field
//                     deflection 4M/b outside the sphere, so the starfield bends
//                     continuously across the sphere edge), tone maps, and writes
//                     reverse-Z depth so passthrough and hands composite correctly.
//                     Mixed immersion: only the black hole is drawn, alpha
//                     premultiplied, the room stays visible around it.
//                     Full immersion: the lensed sky fills the whole view.

#include <metal_stdlib>
using namespace metal;

// ---------- Shared layouts (mirrored in ImmersiveRenderer.swift) ----------

struct ImmEye {
    float4x4 viewFromClip;   // inverse projection of this eye
    float4x4 worldFromView;  // eye pose in the immersive space
    float4   misc;           // x: clip depth of the black hole centre, y: 1 = encode gamma,
                             // z, w: offscreen viewport size / offscreen texture size
};

struct ImmScene {
    float4x4 bhFromWorld;    // rigid: world -> black-hole frame (spin axis = +y)
    float4x4 worldFromBH;
    float4   a;   // x units per metre, y M, z spin parameter a (units of length), w bounding radius R
    float4   b;   // x time, y disk clock, z lensing strength, w frame-drag strength
    float4   c;   // x disk density, y disk temperature K, z disk outer radius, w disk scale height
    float4   d;   // x max steps, y mode (0 mixed, 1 full), z feature bits, w sky brightness
};

constant uint F_LENS = 1u, F_DISK = 2u, F_DOPPLER = 4u, F_PHOTON = 8u, F_STARS = 16u, F_JETS = 32u;

constant float MIN_STEP          = 0.01;
constant float MAX_STEP          = 1.2;
constant float HORIZON_THRESHOLD = 1.15;
constant float DISK_HEIGHT_MULT  = 0.45;
constant float DISK_TURB_SCALE   = 0.75;
constant float DISK_TURB_DETAIL  = 2.5;
constant float DISK_TIME_SCALE   = 0.12;
constant float DISK_DENSITY_FALL = 0.25;

// ---------- Full-screen triangle ----------

struct VSOut {
    float4 position [[position, invariant]];
    float2 ndc;
};

vertex VSOut imm_vs(uint vid [[vertex_id]])
{
    float2 pos = float2((vid == 2) ? 3.0 : -1.0, (vid == 0) ? -3.0 : 1.0);
    VSOut o;
    o.position = float4(pos, 0.0, 1.0);
    o.ndc = pos;
    return o;
}

// ---------- Hash + noise ----------

inline float hash13(float3 p) {
    p = fract(p * float3(443.8975, 397.2973, 491.1871));
    p += dot(p, p.yzx + 19.19);
    return fract((p.x + p.y) * p.z);
}

inline float3 hash33(float3 p) {
    return float3(hash13(p), hash13(p + 31.7), hash13(p + 77.3));
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

// ---------- Colour ----------

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
    if (t < 0.0)  return float3(0.62, 0.72, 1.0);
    if (t < 0.3)  return float3(0.85, 0.88, 1.0);
    if (t < 0.6)  return float3(1.0, 0.96, 0.9);
    if (t < 1.0)  return float3(1.0, 0.85, 0.62);
    return float3(1.0, 0.64, 0.44);
}

// One layer of point stars: each cell of a 3D grid over the direction sphere may
// hold one star at a random offset, drawn as a small Gaussian so it stays a point
// at Vision Pro resolution instead of filling the cell.
inline float3 starLayer(float3 dir, float density, float keep, float size, float gain) {
    float3 q = dir * density;
    float3 cell = floor(q);
    float n = hash13(cell);
    if (n < keep) return float3(0.0);
    float3 c = cell + 0.2 + 0.6 * hash33(cell + 5.3);
    float d2 = length_squared(q - c);
    float b = exp(-d2 / (size * size)) * gain * (0.35 + 0.65 * pow((n - keep) / (1.0 - keep), 3.0));
    return starColor(hash13(cell + 127.1) * 2.4 - 0.4) * b;
}

inline float3 sky(float3 dir, float time) {
    float3 s = starLayer(dir, 160.0, 0.985, 0.10, 2.6);
    s += starLayer(dir, 420.0, 0.975, 0.12, 1.1);
    s += starLayer(dir, 900.0, 0.970, 0.14, 0.45);
    // A faint galactic band and dust so full immersion is not a flat black.
    float3 g = normalize(float3(0.32, 0.88, -0.35));
    float band = exp(-pow(dot(dir, g) * 4.2, 2.0));
    float neb = vnoise(dir * 3.1 + float3(0.0, 0.0, time * 0.003)) * 0.6 + vnoise(dir * 7.3) * 0.4;
    s += band * (0.010 + 0.022 * neb) * float3(0.85, 0.80, 1.0);
    s += float3(0.006, 0.004, 0.010) * neb * neb;
    return s;
}

// ---------- Kerr helpers (as BlackHole.metal) ----------

inline float kerr_horizon(float M, float a) { return M + sqrt(max(0.0, M*M - a*a)); }

inline float kerr_isco(float M, float a) {
    float aStar = a / max(M, 1e-6);
    float absS = abs(clamp(aStar, -0.9999, 0.9999));
    float z1 = 1.0 + pow(1.0 - absS*absS, 1.0/3.0)
                   * (pow(1.0 + absS, 1.0/3.0) + pow(1.0 - absS, 1.0/3.0));
    float z2 = sqrt(3.0 * absS*absS + z1*z1);
    float s = (a >= 0.0) ? 1.0 : -1.0;
    return M * (3.0 + z2 - s * sqrt((3.0 - z1) * (3.0 + z1 + 2.0 * z2)));
}

// Equatorial circular photon orbit; a > 0 prograde, a < 0 retrograde.
inline float kerr_photon_sphere(float M, float a) {
    float aStar = clamp(a / max(M, 1e-6), -0.9999, 0.9999);
    float theta = (2.0/3.0) * acos(clamp(-aStar, -1.0, 1.0));
    return 2.0 * M * (1.0 + cos(theta));
}

struct KerrAccel { float3 accel; float omega; };

inline KerrAccel kerr_accel(float3 p, float3 v, float M, float a) {
    KerrAccel res;
    float a2 = a * a;
    float rho2 = dot(p, p);
    float diff = rho2 - a2;
    float disc = diff*diff + 4.0 * a2 * p.y*p.y;
    float r2 = 0.5 * (diff + sqrt(max(0.0, disc)));
    float rK = sqrt(max(1e-8, r2));

    float3 L = cross(p, v);
    float Ly = L.y;
    float Ly_eff = Ly - a;
    float L2_eff = Ly_eff * Ly_eff + (dot(L, L) - Ly * Ly);

    float r_inv  = 1.0 / rK;
    float r2_inv = r_inv * r_inv;
    float r4_inv = r2_inv * r2_inv;
    float sigma = r2 + a2 * (p.y*p.y / max(1e-8, r2));
    float sigma_ratio = r2 / max(1e-8, sigma);

    float3 r_hat = -normalize(p);
    res.accel = r_hat * (M * r2_inv * sigma_ratio + 3.0 * M * max(0.0, L2_eff) * r4_inv * sigma_ratio);
    float drag_denom = rK * r2 + a2 * rK;
    float drag_coeff = 2.0 * M * a / max(1e-8, drag_denom);
    res.accel += cross(float3(0.0, 1.0, 0.0), v) * drag_coeff;
    res.omega = drag_coeff;
    return res;
}

inline float2x2 rot(float angle) {
    float s = sin(angle), c = cos(angle);
    return float2x2(c, -s, s, c);
}

// Weak-field bending (4M/b in total) collected along a straight ray between the
// signed distances s0 and s1 from its point of closest approach. Bends v towards
// the mass. Used for the parts of a ray outside the integrated sphere.
inline float3 bend(float3 p, float3 v, float s0, float s1, float M, float k) {
    float3 pc = p - v * dot(p, v);             // closest approach to the centre
    float b = max(length(pc), 1e-3);
    float t0 = s0 / sqrt(s0 * s0 + b * b);
    float t1 = s1 / sqrt(s1 * s1 + b * b);
    float ang = min(2.0 * M / b * (t1 - t0) * k, 0.8);
    float3 n = -pc / b;
    return normalize(v * cos(ang) + n * sin(ang));
}

// ---------- Disk + jets ----------

inline float3 sample_disk(float3 p, float3 p_prev, float3 v, float isco, float M, float a,
                          float dt, constant ImmScene& s, uint flags, thread float &alpha)
{
    bool crossed = (p_prev.y * p.y < 0.0);
    float3 sp = p;
    if (crossed) {
        float t = abs(p_prev.y) / max(1e-4, abs(p_prev.y) + abs(p.y));
        sp = mix(p_prev, p, t);
    }
    float r = length(sp);
    float h = min(s.c.w, DISK_HEIGHT_MULT);
    float outer = max(s.c.z, isco * 1.1);
    if (!((abs(sp.y) < r * h || crossed) && r > isco && r < outer)) return float3(0.0);

    float sqrtM = sqrt(max(M, 1e-6));
    float sgn = (a >= 0.0) ? 1.0 : -1.0;
    float Omega = (sgn * sqrtM) / (r * sqrt(r) + a * sqrtM);
    float2 xz = rot(Omega * s.b.y * DISK_TIME_SCALE * 10.0) * sp.xz;
    float3 np = float3(xz.x, sp.y, xz.y) * DISK_TURB_SCALE;
    float turb = vnoise(np) * 0.5 + vnoise(np * DISK_TURB_DETAIL) * 0.25;
    float hFall = exp(-abs(sp.y) / max(1e-3, r * h * DISK_DENSITY_FALL));
    float base = turb * hFall * smoothstep(outer, isco, r);
    if (base <= 0.001) return float3(0.0);

    float r2 = r * r;
    float g_tt = -(1.0 - 2.0 * M / r);
    float g_tphi = -2.0 * M * a / r;
    float g_pp = r2 + a*a + 2.0 * M * a*a / r;
    float ut = 1.0 / sqrt(max(1e-6, -(g_tt + 2.0 * Omega * g_tphi + Omega * Omega * g_pp)));
    float Lph = p.z * v.x - p.x * v.z;
    float delta = 1.0 / max(0.01, ut * (1.0 - Omega * Lph));
    float beaming = (flags & F_DOPPLER) ? max(0.01, pow(delta, 3.5)) : 1.0;

    float ir = clamp(isco / r, 0.0, 1.0);
    float grad = pow(ir, 0.75) * pow(max(0.0, 1.0 - sqrt(ir)), 0.25);
    float3 col = blackbody(s.c.y * grad * ((flags & F_DOPPLER) ? delta : 1.0)) * beaming;
    float dens = base * s.c.x * 0.12 * dt;
    float3 e = col * dens * (1.0 - alpha);
    alpha = saturate(alpha + dens);
    return e;
}

inline float3 sample_jet(float3 p, float3 v, float rh, float R, float dt, float time, thread float &alpha)
{
    float jy = abs(p.y);
    if (jy <= rh * 1.8) return float3(0.0);
    float jr = length(p.xz);
    float jw = 1.0 + jy * 0.15;
    if (jr >= jw * 2.0) return float3(0.0);
    float flow = p.y * 2.0 - time * 8.0;
    float3 uvJ = float3(p.x, flow, p.z);
    float n = vnoise(uvJ * 0.5) * 0.6 + vnoise(uvJ * 1.5) * 0.4;
    float jd = exp(-(jr*jr) / (jw * 0.5)) * exp(-jy * 0.05) * max(0.0, n - 0.2)
             * smoothstep(R, R * 0.7, length(p));
    if (jd <= 0.001) return float3(0.0);
    float beta = 0.92;
    float cosT = dot(float3(0.0, sign(p.y), 0.0), -v);
    float dj = 1.0 / ((1.0 / sqrt(1.0 - beta * beta)) * (1.0 - beta * cosT));
    float3 emit = float3(0.4, 0.7, 1.0) * jd * 0.05 * pow(dj, 3.5) * dt;
    float3 e = emit * (1.0 - alpha);
    alpha = saturate(alpha + jd * 0.05 * dt);
    return e;
}

// ---------- Ray set-up ----------

struct Ray { float3 ro; float3 rd; float3 wd; };   // BH-frame origin/dir, world dir

inline Ray eyeRay(float2 ndc, constant ImmEye& e, constant ImmScene& s) {
    float4 v = e.viewFromClip * float4(ndc, 0.5, 1.0);
    float3 vd = normalize(v.xyz / v.w);
    float3 wd = normalize((e.worldFromView * float4(vd, 0.0)).xyz);
    float3 wo = e.worldFromView.columns[3].xyz;
    Ray r;
    r.ro = (s.bhFromWorld * float4(wo, 1.0)).xyz * s.a.x;
    r.rd = normalize((s.bhFromWorld * float4(wd, 0.0)).xyz);
    r.wd = wd;
    return r;
}

// ---------- Pass A: integrate rays through the sphere ----------

struct MarchOut {
    float4 color [[color(0)]];
    float4 dir   [[color(1)]];
};

fragment MarchOut bh_march_fs(VSOut in [[stage_in]],
                              constant ImmEye& e [[buffer(0)]],
                              constant ImmScene& s [[buffer(1)]])
{
    MarchOut o;
    o.color = float4(0.0);
    o.dir = float4(0.0);

    Ray ray = eyeRay(in.ndc, e, s);
    float R = s.a.w;
    float3 ro = ray.ro, rd = ray.rd;

    // Ray / bounding sphere.
    float bq = dot(ro, rd);
    float cq = dot(ro, ro) - R * R;
    float disc = bq * bq - cq;
    if (disc <= 0.0) return o;
    float sq = sqrt(disc);
    float tEnter = -bq - sq, tExit = -bq + sq;
    if (tExit <= 0.0) return o;

    uint flags = uint(s.d.z);
    float M = s.a.y;
    float a = s.a.z;
    float lens = (flags & F_LENS) ? s.b.z : 0.0;
    float rh = kerr_horizon(M, a);
    float isco = kerr_isco(M, a);

    float3 p = ro;
    float3 v = rd;
    if (tEnter > 0.0) {
        // Bending collected on the way in, from the eye to the sphere.
        float s0 = dot(ro, rd), s1 = s0 + tEnter;
        v = bend(ro, rd, s0, s1, M, lens);
        p = ro + rd * tEnter;
    }

    // Photon-ring radius for this ray's orbital sense (prograde rays skim closer).
    float3 L0 = cross(p, v);
    float lhat = L0.y / max(length(L0), 1e-4);
    float rph = kerr_photon_sphere(M, a * lhat);

    float3 acc = float3(0.0);
    float alpha = 0.0;
    bool hit = false;
    bool escaped = false;
    float rmin = 1e9;
    int maxSteps = int(s.d.x);
    float3 p_prev = p;

    for (int i = 0; i < maxSteps; ++i) {
        p_prev = p;
        float r = length(p);
        rmin = min(rmin, r);
        if (r < rh * HORIZON_THRESHOLD) { hit = true; break; }
        if (r > R * 1.001 && dot(p, v) > 0.0) { escaped = true; break; }

        float distFactor = 1.0 + r * 0.05;
        float dt = clamp((r - rh) * 0.1 * distFactor, MIN_STEP, MAX_STEP * distFactor);
        if (r > 30.0) dt = min(max(dt, MIN_STEP + (r - 30.0) * 0.08), MAX_STEP * 2.5);
        dt = min(dt, 0.03 + abs(r - rph) * 0.2);
        dt *= (1.0 - smoothstep(0.2, 0.0, abs(p.y)) * 0.5);

        float3 accel = float3(0.0);
        if (lens > 0.0) {
            KerrAccel kA = kerr_accel(p, v, M, a);
            accel = kA.accel * lens;
            float2 xz = rot(kA.omega * s.b.w * dt) * v.xz;
            v.x = xz.x; v.z = xz.y;
        }
        p += v * dt + 0.5 * accel * dt * dt;
        if (lens > 0.0 && alpha < 0.95) {
            KerrAccel kB = kerr_accel(p, v, M, a);
            v += 0.5 * (accel + kB.accel * lens) * dt;
        }
        v = normalize(v);

        if (flags & F_DISK) acc += sample_disk(p, p_prev, v, isco, M, a, dt, s, flags, alpha);
        if (flags & F_JETS) acc += sample_jet(p, v, rh, R, dt, s.b.x, alpha);
        if (alpha > 0.99) break;
    }

    // Out of steps before leaving the sphere: a ray still heading inwards, or one
    // circling inside the photon region, is captured; one already climbing out
    // keeps its current direction.
    if (!hit && !escaped && alpha < 0.99) {
        float rEnd = length(p);
        if (rEnd < rph * 1.6 || dot(p, v) < 0.0) hit = true;
    }

    if (!hit && (flags & F_PHOTON) && lens > 0.0) {
        float d = max(0.0, rmin - rph);
        float ring = exp(-d / (0.10 * M)) * 0.9 + exp(-d / (0.025 * M)) * 1.8;
        float3 ringCol = float3(1.0, 0.86, 0.66) * ring * min(lens, 1.5) * (1.0 - alpha);
        acc += ringCol;
        alpha = saturate(alpha + min(ring * 0.3, 0.5) * (1.0 - alpha));
    }

    if (hit) {
        alpha = 1.0;
        o.dir = float4(ray.wd, 0.0);
    } else {
        // Bending still to come between the sphere and infinity.
        float sOut = dot(p, v);
        float3 vOut = bend(p, v, sOut, 1e6, M, lens);
        float3 wd = normalize((s.worldFromBH * float4(vOut, 0.0)).xyz);
        o.dir = float4(wd, 1.0);
    }
    o.color = float4(acc, alpha);
    return o;
}

// ---------- Pass B: composite into the drawable ----------

struct CompOut {
    float4 color [[color(0)]];
    float  depth [[depth(any)]];
};

fragment CompOut bh_composite_fs(VSOut in [[stage_in]],
                                 constant ImmEye& e [[buffer(0)]],
                                 constant ImmScene& s [[buffer(1)]],
                                 texture2d<float> colA [[texture(0)]],
                                 texture2d<float> dirA [[texture(1)]])
{
    constexpr sampler lin(filter::linear, address::clamp_to_edge);
    float2 uv = float2(in.ndc.x * 0.5 + 0.5, 0.5 - in.ndc.y * 0.5) * e.misc.zw;
    float4 c = colA.sample(lin, uv);
    bool full = s.d.y > 0.5;
    uint flags = uint(s.d.z);

    float3 col = c.rgb;
    float alpha = c.a;

    if (full) {
        float3 sk = float3(0.0);
        if (flags & F_STARS) {
            float4 dA = dirA.sample(lin, uv);
            Ray ray = eyeRay(in.ndc, e, s);
            float3 dir = ray.wd;
            float lens = (flags & F_LENS) ? s.b.z : 0.0;
            if (lens > 0.0) {
                // Outside the integrated sphere: straight-line weak-field bending.
                float s0 = dot(ray.ro, ray.rd);
                float3 vb = bend(ray.ro, ray.rd, s0, 1e6, s.a.y, lens);
                float3 analytic = normalize((s.worldFromBH * float4(vb, 0.0)).xyz);
                float w = saturate(dA.w);
                float3 marched = (w > 1e-3) ? dA.xyz / w : analytic;
                dir = normalize(mix(analytic, marched, w));
            }
            sk = sky(dir, s.b.x) * s.d.w;
        }
        col = sk * (1.0 - alpha) + col;
        alpha = 1.0;
    }

    col = col / (col + 1.0);                       // Reinhard, premultiplied stays premultiplied
    if (!full) {
        // Over a lit room a glowing, half-transparent disk washes out; let its
        // own brightness make it more opaque so it reads like it does in space.
        float lum = dot(col, float3(0.2126, 0.7152, 0.0722));
        alpha = saturate(max(alpha * 1.6, lum * 2.2));
    }
    if (e.misc.y > 0.5) col = pow(max(col, 0.0), float3(1.0 / 2.2));

    CompOut o;
    o.color = float4(col, alpha);
    // Reverse-Z: 0 is infinitely far. Covered pixels sit at the black hole's centre.
    o.depth = (c.a > 0.01) ? e.misc.x : 0.0;
    return o;
}
