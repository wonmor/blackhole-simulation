//! C-ABI bridge between `gravitas-core` and native consumers (iOS / macOS Swift app).
//!
//! Build via `cargo build --release --target <triple>`; the static archive is
//! bundled into a multi-platform xcframework by `apple/scripts/build-gravitas-xcframework.sh`.
//!
//! Surface stays small on purpose. The GPU does the per-pixel raymarching;
//! Rust supplies high-precision scalar observables and the analytic shadow
//! boundary for diagnostic overlays.

#![deny(unsafe_op_in_unsafe_fn)]

use core::slice;
use gravitas::metric::{Kerr, Metric, Orbit};

/// Outer event horizon r_+ = M + sqrt(M^2 - a^2).
#[no_mangle]
pub extern "C" fn gravitas_kerr_horizon(mass: f64, spin: f64) -> f64 {
    Kerr::new(mass, spin).event_horizon()
}

/// Prograde photon sphere radius (Bardeen 1973).
#[no_mangle]
pub extern "C" fn gravitas_kerr_photon_sphere(mass: f64, spin: f64) -> f64 {
    Kerr::new(mass, spin).photon_sphere()
}

/// Innermost stable circular orbit (Bardeen, Press & Teukolsky 1972).
/// `prograde != 0` for prograde orbits.
#[no_mangle]
pub extern "C" fn gravitas_kerr_isco(mass: f64, spin: f64, prograde: i32) -> f64 {
    let orbit = if prograde != 0 { Orbit::Prograde } else { Orbit::Retrograde };
    Kerr::new(mass, spin).isco(orbit)
}

/// Outer ergosphere radius for a fixed colatitude `cos_theta`.
#[no_mangle]
pub extern "C" fn gravitas_kerr_ergosphere(mass: f64, spin: f64, cos_theta: f64) -> f64 {
    let m2 = mass * mass;
    let a2 = spin * spin;
    let disc = (m2 - a2 * cos_theta * cos_theta).max(0.0);
    mass + disc.sqrt()
}

/// Fill `out_xy` with `count` interleaved (alpha, beta) points sampling the
/// analytic critical curve (shadow boundary) of a Kerr black hole as seen by
/// an observer at infinity with inclination `inclination_rad`.
///
/// Returns the number of points written (== `count`), or 0 on error.
///
/// # Safety
/// `out_xy` must point to at least `count * 2` writable f64 slots.
#[no_mangle]
pub unsafe extern "C" fn gravitas_kerr_shadow_curve(
    mass: f64,
    spin: f64,
    inclination_rad: f64,
    out_xy: *mut f64,
    count: u32,
) -> u32 {
    if out_xy.is_null() || count == 0 {
        return 0;
    }
    let n = count as usize;
    let buf = unsafe { slice::from_raw_parts_mut(out_xy, n * 2) };

    // Parametric Bardeen critical curve: scan the prograde photon-sphere radius
    // r in [r_ph_pro, r_ph_retro] and project onto the observer's celestial
    // coordinates (alpha, beta). For each parameter:
    //   alpha = -L_z / sin(i)
    //   beta  = sqrt(Q + a^2 cos^2(i) - L_z^2 cot^2(i))
    let bh = Kerr::new(mass, spin);
    let r_pro = bh.photon_sphere();
    // Retrograde photon sphere: same closed form with -spin.
    let r_retro = Kerr::new(mass, -spin).photon_sphere();
    let r_min = r_pro.min(r_retro);
    let r_max = r_pro.max(r_retro);

    let sin_i = inclination_rad.sin();
    let cos_i = inclination_rad.cos();
    let cot2_i = if sin_i.abs() > 1e-9 {
        (cos_i / sin_i).powi(2)
    } else {
        0.0
    };
    let a2 = spin * spin;

    // Walk r along the upper branch then back along the lower branch so the
    // result is a closed polyline.
    let half = n / 2;
    for k in 0..n {
        // Triangle wave parameterization keeps endpoints stable.
        let t = if k < half {
            (k as f64) / (half.max(1) as f64)
        } else {
            1.0 - ((k - half) as f64) / ((n - half).max(1) as f64)
        };
        let r = r_min + t * (r_max - r_min);
        let r2 = r * r;

        // Effective Lz, Q for null circular orbit at radius r (Bardeen 1973):
        //   Lz = (r^2 - a^2 - 2 M r) / (a (r - M))      [for a != 0]
        //   Q  = -r^3 ((r - 3M)^2 - 4 a^2) / (a^2 (r - M)^2)
        let (lz, q) = if spin.abs() < 1e-9 {
            // Schwarzschild limit: circular shadow at b = 3 sqrt(3) M.
            let b = 3.0 * 3f64.sqrt() * mass;
            let theta = 2.0 * core::f64::consts::PI * (k as f64) / (n as f64);
            buf[2 * k] = b * theta.cos();
            buf[2 * k + 1] = b * theta.sin();
            continue;
        } else {
            let denom = spin * (r - mass);
            let lz = (r2 - a2 - 2.0 * mass * r) / denom;
            let q = -r * r2 * ((r - 3.0 * mass).powi(2) - 4.0 * a2) / (denom * denom);
            (lz, q)
        };

        let alpha = if sin_i.abs() > 1e-9 { -lz / sin_i } else { 0.0 };
        let beta_arg = q + a2 * cos_i * cos_i - lz * lz * cot2_i;
        let mut beta = beta_arg.max(0.0).sqrt();
        if k >= half {
            beta = -beta; // close the curve on the lower half
        }
        buf[2 * k] = alpha;
        buf[2 * k + 1] = beta;
    }
    count
}

/// Returns the version of gravitas-core this FFI was built against.
#[no_mangle]
pub extern "C" fn gravitas_version() -> *const core::ffi::c_char {
    static VERSION: &[u8] = concat!(env!("CARGO_PKG_VERSION"), "\0").as_bytes();
    VERSION.as_ptr() as *const core::ffi::c_char
}
