#ifndef GRAVITAS_H
#define GRAVITAS_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/**
 * Outer event horizon r_+ = M + sqrt(M^2 - a^2).
 */
double gravitas_kerr_horizon(double mass, double spin);

/**
 * Prograde photon sphere radius (Bardeen 1973).
 */
double gravitas_kerr_photon_sphere(double mass, double spin);

/**
 * Innermost stable circular orbit (Bardeen, Press & Teukolsky 1972).
 * Pass `prograde != 0` for prograde orbits, 0 for retrograde.
 */
double gravitas_kerr_isco(double mass, double spin, int32_t prograde);

/**
 * Outer ergosphere radius at a given polar coordinate.
 */
double gravitas_kerr_ergosphere(double mass, double spin, double cos_theta);

/**
 * Fill `out_xy` with `count` interleaved (alpha, beta) points along the analytic
 * critical curve of a Kerr black hole, as seen by an observer at infinity at
 * the given inclination (radians; 0 = pole-on, pi/2 = edge-on).
 *
 * `out_xy` must point to at least `count * 2` writable doubles.
 * Returns the number of points written (== `count`), or 0 on error.
 */
uint32_t gravitas_kerr_shadow_curve(double mass,
                                    double spin,
                                    double inclination_rad,
                                    double* out_xy,
                                    uint32_t count);

/** Version string of the gravitas-core build this FFI links against. */
const char* gravitas_version(void);

#ifdef __cplusplus
}
#endif

#endif /* GRAVITAS_H */
