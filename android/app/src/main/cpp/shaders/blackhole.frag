#version 450
// Kerr black hole raymarcher — Vulkan GLSL port of apple/.../BlackHole.metal.
// Output: linear HDR rgba16f — bloom + ACES applied in the post chain.
#include "common.glsl"

layout(location = 0) in  vec2 fragCoord;
layout(location = 0) out vec4 outColor;

const float PI               = 3.14159265359;
const float MAX_DIST         = 10000.0;
const float MIN_STEP         = 0.01;
const float MAX_STEP         = 1.2;
const float HORIZON_THRESHOLD= 1.15;
const float DISK_HEIGHT_MULT = 0.45;
const float DISK_TURB_SCALE  = 0.75;
const float DISK_TURB_DETAIL = 2.5;
const float DISK_TIME_SCALE  = 0.12;
const float DISK_DENSITY_FALL= 0.25;

// Feature flags — specialization constants set per pipeline (mirror the Metal
// function constants). The branches fold away at pipeline-build time.
layout(constant_id = 0) const bool ENABLE_LENSING       = true;
layout(constant_id = 1) const bool ENABLE_DISK          = true;
layout(constant_id = 2) const bool ENABLE_DOPPLER       = true;
layout(constant_id = 3) const bool ENABLE_PHOTON_GLOW   = true;
layout(constant_id = 4) const bool ENABLE_STARS         = true;
layout(constant_id = 5) const bool ENABLE_JETS          = true;
layout(constant_id = 6) const bool ENABLE_REDSHIFT_VIEW = false;

// ---------- Hash + Noise ----------
float hash13(vec3 p) {
    p = fract(p * vec3(443.8975, 397.2973, 491.1871));
    p += dot(p, p.yzx + 19.19);
    return fract((p.x + p.y) * p.z);
}

float vnoise(vec3 p) {
    vec3 i = floor(p);
    vec3 f = fract(p);
    vec3 w = f * f * (3.0 - 2.0 * f);
    float n000 = hash13(i + vec3(0,0,0));
    float n100 = hash13(i + vec3(1,0,0));
    float n010 = hash13(i + vec3(0,1,0));
    float n110 = hash13(i + vec3(1,1,0));
    float n001 = hash13(i + vec3(0,0,1));
    float n101 = hash13(i + vec3(1,0,1));
    float n011 = hash13(i + vec3(0,1,1));
    float n111 = hash13(i + vec3(1,1,1));
    return mix(mix(mix(n000, n100, w.x), mix(n010, n110, w.x), w.y),
               mix(mix(n001, n101, w.x), mix(n011, n111, w.x), w.y), w.z);
}

float fbm(vec3 p) {
    float a = 0.5, s = 0.0;
    for (int i = 0; i < 4; ++i) { s += a * vnoise(p); p *= 2.02; a *= 0.5; }
    return s;
}

// ---------- Blackbody / star color ----------
vec3 blackbody(float temp) {
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
    vec3 srgb = clamp(vec3(r, g, b) / 255.0, 0.0, 1.0);
    return pow(max(srgb, vec3(0.0)), vec3(2.2));
}

vec3 starColor(float bv) {
    float t = clamp(bv, -0.4, 2.0);
    if (t < 0.0)  return vec3(0.6, 0.7, 1.0);
    if (t < 0.3)  return vec3(0.85, 0.88, 1.0);
    if (t < 0.6)  return vec3(1.0, 0.96, 0.9);
    if (t < 1.0)  return vec3(1.0, 0.85, 0.6);
    return vec3(1.0, 0.6, 0.4);
}

vec3 starfield(vec3 dir, float time) {
    vec3 stars = vec3(0.0);
    vec3 cell = floor(dir * 200.0);
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
    float neb = fbm(dir * 2.0 + vec3(time * 0.01)) * 0.03;
    stars += vec3(neb * 0.2, neb * 0.3, neb * 0.5) + vec3(0.05, 0.02, 0.05) * abs(neb);
    return stars;
}

// ---------- Kerr helpers ----------
float kerr_horizon(float M, float a) {
    return M + sqrt(max(0.0, M*M - a*a));
}

float kerr_isco(float M, float a) {
    float aStar = a / max(M, 1e-6);
    float absS = abs(clamp(aStar, -0.9999, 0.9999));
    float z1 = 1.0 + pow(1.0 - absS*absS, 1.0/3.0) *
               (pow(1.0 + absS, 1.0/3.0) + pow(1.0 - absS, 1.0/3.0));
    float z2 = sqrt(3.0 * absS*absS + z1*z1);
    float s = (a >= 0.0) ? 1.0 : -1.0;
    return M * (3.0 + z2 - s * sqrt((3.0 - z1) * (3.0 + z1 + 2.0 * z2)));
}

float kerr_photon_sphere(float M, float a) {
    float aStar = clamp(a / max(M, 1e-6), -0.9999, 0.9999);
    float arg = clamp(-aStar, -1.0, 1.0);
    float theta = (2.0/3.0) * acos(arg);
    return 2.0 * M * (1.0 + cos(theta));
}

float kerr_ergosphere(float M, float a, float r, float cosTheta) {
    return M + sqrt(max(0.0, M*M - a*a * cosTheta*cosTheta));
}

struct KerrAccel { vec3 accel; float rK; float omega; };

KerrAccel kerr_accel(vec3 p, vec3 v, float M, float a) {
    KerrAccel res;
    float a2 = a * a;
    float rho2 = dot(p, p);
    float diff = rho2 - a2;
    float disc = diff*diff + 4.0 * a2 * p.y*p.y;
    float r2 = 0.5 * (diff + sqrt(max(0.0, disc)));
    float rK = sqrt(max(1e-8, r2));
    res.rK = rK;

    vec3 L = cross(p, v);
    float Ly = L.y;
    float Ly_eff = Ly - a;
    float L2_eff = Ly_eff * Ly_eff + (dot(L, L) - Ly * Ly);

    float r_inv  = 1.0 / rK;
    float r2_inv = r_inv * r_inv;
    float r4_inv = r2_inv * r2_inv;

    float sigma = r2 + a2 * (p.y*p.y / max(1e-8, r2));
    float sigma_ratio = r2 / max(1e-8, sigma);

    vec3 r_hat = -normalize(p);

    res.accel = r_hat * (M * r2_inv * sigma_ratio +
                         3.0 * M * max(0.0, L2_eff) * r4_inv * sigma_ratio);

    float drag_denom = rK * r2 + a2 * rK;
    float drag_coeff = 2.0 * M * a / max(1e-8, drag_denom);
    res.accel += cross(vec3(0.0, 1.0, 0.0), v) * drag_coeff;

    res.omega = 2.0 * M * a / max(1e-8, drag_denom);
    return res;
}

mat2 rot(float angle) {
    float s = sin(angle), c = cos(angle);
    return mat2(c, -s, s, c);
}

// ---------- Disk ----------
vec3 sample_disk(vec3 p, vec3 p_prev, vec3 v, float r, float isco,
                 float M, float a, float dt, inout float alpha) {
    if (alpha > 0.99) return vec3(0.0);

    bool crossedEquator = (p_prev.y * p.y < 0.0);
    vec3 sampleP = p;
    if (crossedEquator) {
        float t = abs(p_prev.y) / max(1e-4, abs(p_prev.y) + abs(p.y));
        sampleP = mix(p_prev, p, t);
    }
    float sampleR = length(sampleP);

    float effectiveScaleHeight = min(u.diskScaleHeight, DISK_HEIGHT_MULT);
    float diskHeight = sampleR * effectiveScaleHeight;
    float diskInner = isco;
    float diskOuter = max(M * u.diskSize, diskInner * 1.1);

    if (!((abs(sampleP.y) < diskHeight || crossedEquator) &&
          sampleR > diskInner && sampleR < diskOuter)) {
        return vec3(0.0);
    }

    float sqrt_M = sqrt(max(M, 1e-6));
    float signSpin = (u.spin >= 0.0) ? 1.0 : -1.0;
    float OmegaPhase = (signSpin * sqrt_M) / (sampleR * sqrt(sampleR) + a * sqrt_M);
    float rotAngle = OmegaPhase * u.time * DISK_TIME_SCALE * 10.0;
    mat2 rotPhase = rot(rotAngle);
    vec3 noiseP = sampleP;
    {
        vec2 xz = rotPhase * vec2(noiseP.x, noiseP.z);
        noiseP.x = xz.x; noiseP.z = xz.y;
    }
    noiseP *= DISK_TURB_SCALE;
    float turbulence = vnoise(noiseP) * 0.5 + vnoise(noiseP * DISK_TURB_DETAIL) * 0.25;

    float heightFalloff = exp(-abs(sampleP.y) /
                              max(1e-3, sampleR * effectiveScaleHeight * DISK_DENSITY_FALL));
    float radialFalloff = smoothstep(diskOuter, diskInner, sampleR);
    float baseDensity = turbulence * heightFalloff * radialFalloff;
    if (baseDensity <= 0.001) return vec3(0.0);

    float r2 = sampleR * sampleR;
    float Omega = (signSpin * sqrt_M) / (sampleR * sqrt(sampleR) + a * sqrt_M);
    float g_tt = -(1.0 - 2.0 * M / sampleR);
    float g_tphi = -2.0 * M * a / sampleR;
    float g_phiphi = r2 + a*a + 2.0 * M * a*a / sampleR;
    float u_t_sq = -(g_tt + 2.0 * Omega * g_tphi + Omega * Omega * g_phiphi);
    float u_t = 1.0 / sqrt(max(1e-6, u_t_sq));

    float L_photon = p.z * v.x - p.x * v.z;
    float delta = 1.0 / max(0.01, u_t * (1.0 - Omega * L_photon));
    float beaming = ENABLE_DOPPLER ? max(0.01, pow(delta, 3.5)) : 1.0;

    float isco_r = clamp(isco / sampleR, 0.0, 1.0);
    float nt_factor = max(0.0, 1.0 - sqrt(isco_r));
    float radialTempGradient = pow(isco_r, 0.75) * pow(nt_factor, 0.25);
    float temperature = u.diskTemp * radialTempGradient * delta;

    vec3 diskColor = blackbody(temperature) * beaming;
    float density = baseDensity * u.diskDensity * 0.12 * dt;

    vec3 emission = diskColor * density * (1.0 - alpha);
    alpha = saturate(alpha + density);
    return emission;
}

// ---------- Jets ----------
vec3 sample_jet(vec3 p, vec3 v, float r, float rh, float dt, float time, inout float alpha) {
    if (alpha > 0.99) return vec3(0.0);
    float jy = abs(p.y);
    if (jy <= rh * 1.8 || jy >= MAX_DIST * 0.8) return vec3(0.0);

    float jr = length(p.xz);
    float jw = 1.0 + jy * 0.15;
    if (jr >= jw * 2.0) return vec3(0.0);

    float radialFalloff = exp(-(jr*jr) / (jw * 0.5));
    float lengthFalloff = exp(-jy * 0.05);
    float flow = p.y * 2.0 - time * 8.0;
    vec3 uvJ = vec3(p.x, flow, p.z);
    float n = vnoise(uvJ * 0.5) * 0.6 + vnoise(uvJ * 1.5) * 0.4;
    float jd = radialFalloff * lengthFalloff * max(0.0, n - 0.2);
    if (jd <= 0.001) return vec3(0.0);

    float jetVel = 0.92 * sign(p.y);
    vec3 jetVec = vec3(0.0, jetVel, 0.0);
    float cosT = dot(normalize(jetVec), -v);
    float beta = abs(jetVel);
    float gamma = 1.0 / sqrt(1.0 - beta * beta);
    float deltaJet = 1.0 / (gamma * (1.0 - beta * cosT));
    float beam = pow(deltaJet, 3.5);
    vec3 base = vec3(0.4, 0.7, 1.0);
    vec3 emit = base * jd * 0.05 * beam * dt;
    alpha = saturate(alpha + jd * 0.05 * dt);
    return emit * (1.0 - alpha);
}

void main() {
    float minRes = min(u.resolution.x, u.resolution.y);
    vec2 uv = (fragCoord + u.jitter - 0.5 * u.resolution) / minRes;

    vec3 ro = vec3(0.0, 0.0, -u.zoom);
    vec3 rd = normalize(vec3(uv, 1.5));

    mat2 rx = rot((u.mouse.y - 0.5) * PI);
    mat2 ry = rot((u.mouse.x - 0.5) * 2.0 * PI);
    {
        vec2 yz = rx * vec2(ro.y, ro.z); ro.y = yz.x; ro.z = yz.y;
        vec2 vyz = rx * vec2(rd.y, rd.z); rd.y = vyz.x; rd.z = vyz.y;
        vec2 xz = ry * vec2(ro.x, ro.z); ro.x = xz.x; ro.z = xz.y;
        vec2 vxz = ry * vec2(rd.x, rd.z); rd.x = vxz.x; rd.z = vxz.y;
    }

    float M  = max(u.mass, 0.05);
    float a  = clamp(u.spin * M, -M * 0.9999, M * 0.9999);
    float rh  = kerr_horizon(M, a);
    float rph = kerr_photon_sphere(M, a);
    float isco = kerr_isco(M, a);

    vec3 p = ro;
    vec3 v = rd;
    if (length(p) < rh * 1.5) p = normalize(p) * rh * 1.5;

    vec3 acc = vec3(0.0);
    float alpha = 0.0;
    bool hitHorizon = false;
    float maxRedshift = 0.0;
    bool redshiftInit = false;

    float impact = length(cross(p, v));
    if (impact < rh * 0.9) hitHorizon = true;

    float bn = hash13(vec3(fragCoord, float(u.frameIndex)));
    p += v * bn * MIN_STEP;

    int maxSteps = clamp(u.maxRaySteps, 32, 500);
    vec3 p_prev = p;

    int photonCrossings = 0;
    float prevY = p.y;
    float minR = length(p);

    float diskOuterApprox = max(M * u.diskSize, isco * 1.1);
    float farFieldR = max(diskOuterApprox * 1.5, rph * 5.0);

    bool loopHorizonHit = false;
    for (int i = 0; i < maxSteps && !loopHorizonHit; ++i) {
        p_prev = p;
        float r = length(p);
        minR = min(minR, r);
        if (r < rh * HORIZON_THRESHOLD) {
            hitHorizon = true;
            loopHorizonHit = true;
            break;
        }
        if (r > MAX_DIST) break;

        if (r > farFieldR) {
            if (r > diskOuterApprox * 2.0 && dot(p, v) > 0.0) break;
            p += v * (MAX_STEP * 4.0);
            continue;
        }

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

        vec3 accel = vec3(0.0);
        float omega = 0.0;
        if (ENABLE_LENSING) {
            KerrAccel kA = kerr_accel(p, v, M, a);
            accel = kA.accel * u.lensingStrength;
            omega = kA.omega * u.frameDragStrength;
            mat2 zamo = rot(omega * currentDt);
            vec2 xz = zamo * vec2(v.x, v.z);
            v.x = xz.x; v.z = xz.y;
        }

        p += v * currentDt + 0.5 * accel * currentDt * currentDt;
        float r_new = length(p);

        if (ENABLE_LENSING && alpha < 0.95) {
            KerrAccel kB = kerr_accel(p, v, M, a);
            vec3 accelNew = kB.accel * u.lensingStrength;
            v += 0.5 * (accel + accelNew) * currentDt;
        }
        v = normalize(v);

        if (prevY * p.y < 0.0 && r_new < rph * 2.0 && r_new > rh) {
            photonCrossings = min(photonCrossings + 1, 3);
        }
        prevY = p.y;

        if (ENABLE_REDSHIFT_VIEW) {
            float pot = sqrt(max(0.0, 1.0 - 2.0 * M / max(length(p), 1e-3)));
            if (!redshiftInit) { maxRedshift = pot; redshiftInit = true; }
            else maxRedshift = min(maxRedshift, pot);
        }

        if (ENABLE_DISK) {
            acc += sample_disk(p, p_prev, v, length(p), isco, M, a, currentDt, alpha);
        }
        if (ENABLE_JETS) {
            acc += sample_jet(p, v, length(p), rh, currentDt, u.time, alpha);
        }
        if (alpha > 0.99) break;
    }

    if (ENABLE_REDSHIFT_VIEW) {
        float val = hitHorizon ? 0.0 : maxRedshift;
        vec3 heat = mix(vec3(0.0), vec3(1, 0, 0), smoothstep(0.0, 0.3, val));
        heat = mix(heat, vec3(1, 1, 0), smoothstep(0.3, 0.7, val));
        heat = mix(heat, vec3(0, 0, 1), smoothstep(0.7, 1.0, val));
        outColor = vec4(heat, 1.0);
        return;
    }

    vec3 background = vec3(0.0);
    if (ENABLE_STARS && !hitHorizon) background = starfield(v, u.time);

    vec3 photon = vec3(0.0);
    if (ENABLE_PHOTON_GLOW) {
        float distToRing = abs(minR - rph);
        float directRing = exp(-distToRing * 28.0) * 1.6 * u.lensingStrength;
        float higherOrderRing = 0.0;
        if (photonCrossings > 0) {
            float ringSharpness = 60.0 + float(photonCrossings) * 30.0;
            float ringBrightness = exp(-float(photonCrossings)) * 1.2;
            higherOrderRing = exp(-distToRing * ringSharpness) * ringBrightness * u.lensingStrength;
        }
        photon = vec3(1.0) * (directRing + higherOrderRing);
    }

    vec3 ergo = vec3(0.0);
    float absA = abs(u.spin);
    if (absA > 0.1 && !hitHorizon) {
        float rFinal = length(p);
        float cosTheta = p.y / max(rFinal, 1e-3);
        float r_ergo = kerr_ergosphere(M, a, rFinal, cosTheta);
        float ergoGlow = exp(-abs(rFinal - r_ergo) * 20.0) * 0.35 * absA;
        ergo = vec3(0.3, 0.35, 0.9) * ergoGlow;
    }

    if (hitHorizon) background = vec3(0.0);

    vec3 col = background * (1.0 - alpha)
             + acc
             + photon * (1.0 - alpha)
             + ergo * (1.0 - alpha);

    outColor = vec4(max(col, vec3(0.0)), 1.0);
}
