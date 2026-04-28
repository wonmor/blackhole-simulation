import Foundation

/// Scalar Kerr observables exposed to Swift.
///
/// Two backends:
///   * `GRAVITAS_LINKED` defined → calls into the `gravitas-ffi` C library
///     (built from `physics-engine/gravitas-ffi` via the script in
///     `apple/scripts/build-gravitas-xcframework.sh`).
///   * Otherwise → pure-Swift implementations, identical formulas to the
///     Bardeen / Press-Teukolsky closed forms used in the MSL shader.
///
/// This split lets the app run today without the Rust toolchain installed,
/// and switch to the validated Rust kernel once the xcframework is linked.
enum Gravitas {

    /// Outer event horizon r_+ = M + sqrt(M² - a²).
    static func eventHorizon(mass: Double, spin: Double) -> Double {
        #if GRAVITAS_LINKED
        return gravitas_kerr_horizon(mass, spin)
        #else
        let disc = max(0.0, mass * mass - spin * spin)
        return mass + disc.squareRoot()
        #endif
    }

    /// Prograde photon sphere radius (Bardeen 1973).
    static func photonSphere(mass: Double, spin: Double) -> Double {
        #if GRAVITAS_LINKED
        return gravitas_kerr_photon_sphere(mass, spin)
        #else
        let aStar = max(-0.9999, min(0.9999, spin / mass))
        let theta = (2.0 / 3.0) * acos(max(-1.0, min(1.0, -aStar)))
        return 2.0 * mass * (1.0 + cos(theta))
        #endif
    }

    /// ISCO (Bardeen, Press & Teukolsky 1972).
    static func isco(mass: Double, spin: Double, prograde: Bool = true) -> Double {
        #if GRAVITAS_LINKED
        return gravitas_kerr_isco(mass, spin, prograde ? 1 : 0)
        #else
        let aStar = max(-0.9999, min(0.9999, spin / mass))
        let absS = abs(aStar)
        let z1 = 1.0 + pow(1.0 - absS * absS, 1.0/3.0)
                       * (pow(1.0 + absS, 1.0/3.0) + pow(1.0 - absS, 1.0/3.0))
        let z2 = (3.0 * absS * absS + z1 * z1).squareRoot()
        let s = (spin >= 0.0) == prograde ? 1.0 : -1.0
        return mass * (3.0 + z2 - s * ((3.0 - z1) * (3.0 + z1 + 2.0 * z2)).squareRoot())
        #endif
    }

    /// Outer ergosphere radius at colatitude `cosTheta`.
    static func ergosphere(mass: Double, spin: Double, cosTheta: Double) -> Double {
        #if GRAVITAS_LINKED
        return gravitas_kerr_ergosphere(mass, spin, cosTheta)
        #else
        let disc = max(0.0, mass * mass - spin * spin * cosTheta * cosTheta)
        return mass + disc.squareRoot()
        #endif
    }

    /// Analytic Kerr critical curve sampled at `count` points (closed polyline).
    /// Returns the points as `(alpha, beta)` celestial coordinates.
    static func shadowCurve(mass: Double, spin: Double, inclinationRad: Double, count: Int) -> [(Double, Double)] {
        #if GRAVITAS_LINKED
        var buf = [Double](repeating: 0.0, count: count * 2)
        let n = buf.withUnsafeMutableBufferPointer { p -> UInt32 in
            gravitas_kerr_shadow_curve(mass, spin, inclinationRad, p.baseAddress, UInt32(count))
        }
        var out: [(Double, Double)] = []
        out.reserveCapacity(Int(n))
        for i in 0..<Int(n) {
            out.append((buf[2 * i], buf[2 * i + 1]))
        }
        return out
        #else
        // Schwarzschild fallback: circular shadow at b = 3 sqrt(3) M.
        // (Full Kerr critical curve is in the FFI; we only need a placeholder
        // for the Swift overlay until rustup is wired in.)
        let b = 3.0 * 3.0.squareRoot() * mass
        return (0..<count).map { k in
            let t = Double(k) / Double(count) * 2.0 * .pi
            return (b * cos(t), b * sin(t))
        }
        #endif
    }
}
