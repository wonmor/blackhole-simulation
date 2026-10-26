import Foundation

/// Curated educational presets. One tap configures every relevant physics +
/// camera param to a regime that matches a famous astrophysical object or
/// extreme-spacetime scenario. The first four are free; the rest ship with
/// BlackHole Pro.
enum Scenario: String, CaseIterable, Identifiable {
    // Free
    case stellar
    case sgrA
    case maximalSpin
    case schwarzschild
    // Pro
    case m87
    case gargantua
    case retrograde
    case cygnusX1
    case quasar
    case bareShadow

    var id: String { rawValue }

    var isPro: Bool {
        switch self {
        case .stellar, .sgrA, .maximalSpin, .schwarzschild: return false
        default: return true
        }
    }

    static var free: [Scenario] { allCases.filter { !$0.isPro } }
    static var pro: [Scenario] { allCases.filter { $0.isPro } }

    var displayName: String {
        switch self {
        case .stellar:       return "Stellar"
        case .sgrA:          return "Sgr A* proxy"
        case .maximalSpin:   return "Maximal Spin"
        case .schwarzschild: return "Schwarzschild"
        case .m87:           return "M87* (EHT view)"
        case .gargantua:     return "Film look"
        case .retrograde:    return "Retrograde disk"
        case .cygnusX1:      return "Cygnus X-1"
        case .quasar:        return "Quasar"
        case .bareShadow:    return "Bare shadow"
        }
    }

    var subtitle: String {
        switch self {
        case .stellar:       return "10 M☉ | a=0.5 | hot disk"
        case .sgrA:          return "Supermassive proxy | a=0.94"
        case .maximalSpin:   return "Near-Kerr extremal | a=0.99"
        case .schwarzschild: return "Non-rotating | classic ring"
        case .m87:           return "Near face-on | a=0.9 | jets"
        case .gargantua:     return "Thin cool disk | no Doppler"
        case .retrograde:    return "a=-0.9 | ISCO pushed out"
        case .cygnusX1:      return "X-ray binary | a=0.95"
        case .quasar:        return "40,000 K disk | jets"
        case .bareShadow:    return "No disk | lensed stars only"
        }
    }

    var symbol: String {
        switch self {
        case .stellar:       return "sparkles"
        case .sgrA:          return "scope"
        case .maximalSpin:   return "arrow.clockwise"
        case .schwarzschild: return "hurricane"
        case .m87:           return "camera.viewfinder"
        case .gargantua:     return "film"
        case .retrograde:    return "arrow.uturn.backward"
        case .cygnusX1:      return "bolt"
        case .quasar:        return "flame"
        case .bareShadow:    return "eye"
        }
    }

    /// Apply this scenario's parameters to the given live `params` instance.
    /// Persistence happens automatically via the @Published didSet hooks.
    /// Every scenario sets the effect toggles too, so switching between them
    /// never leaves a stray effect from the previous one.
    @MainActor
    func apply(to params: BlackHoleParameters) {
        // Defaults shared by most scenarios.
        params.enableLensing = true
        params.enableDisk = true
        params.enableDoppler = true
        params.enablePhotonGlow = true
        params.enableStars = true
        params.enableJets = true
        params.showRedshift = false
        params.frameDragStrength = 2.0
        params.bloomThreshold = 1.0
        params.bloomIntensity = 0.45
        params.pitch = 0.539
        let keepCinematic = params.preset == .cinematic

        switch self {
        case .stellar:
            params.mass = 10.0
            params.spin = 0.50
            params.lensingStrength = 0.7
            params.diskSize = 80.0
            params.diskTemp = 15000.0
            params.diskDensity = 4.0
            params.diskScaleHeight = 0.18
            params.zoom = 80.0
            params.preset = .high

        case .sgrA:
            params.mass = 4.0
            params.spin = 0.94
            params.lensingStrength = 0.9
            params.diskSize = 60.0
            params.diskTemp = 8000.0
            params.diskDensity = 3.5
            params.diskScaleHeight = 0.20
            params.zoom = 60.0
            params.preset = .high

        case .maximalSpin:
            params.mass = 2.0
            params.spin = 0.99
            params.lensingStrength = 1.2
            params.diskSize = 40.0
            params.diskTemp = 20000.0
            params.diskDensity = 4.5
            params.diskScaleHeight = 0.15
            params.zoom = 30.0
            params.preset = .ultra

        case .schwarzschild:
            params.mass = 1.0
            params.spin = 0.0
            params.lensingStrength = 0.7
            params.diskSize = 50.0
            params.diskTemp = 9500.0
            params.diskDensity = 4.0
            params.diskScaleHeight = 0.20
            params.zoom = 30.0
            params.enableJets = false
            params.preset = .high

        case .m87:
            // M87* is seen ~17 degrees from its jet axis, so the disk is close
            // to face-on and the shadow sits inside a near-circular ring.
            params.mass = 6.5
            params.spin = 0.90
            params.lensingStrength = 1.0
            params.diskSize = 45.0
            params.diskTemp = 6000.0
            params.diskDensity = 3.0
            params.diskScaleHeight = 0.22
            params.zoom = 55.0
            params.pitch = 0.12
            params.bloomIntensity = 0.7
            params.preset = .ultra

        case .gargantua:
            // The film's render removed Doppler beaming and used a thin,
            // cool disk seen almost edge-on.
            params.mass = 3.0
            params.spin = 0.99
            params.lensingStrength = 1.0
            params.diskSize = 30.0
            params.diskTemp = 4500.0
            params.diskDensity = 5.0
            params.diskScaleHeight = 0.05
            params.zoom = 25.0
            params.pitch = 0.51
            params.enableDoppler = false
            params.enableJets = false
            params.preset = .ultra

        case .retrograde:
            // Disk orbits against the hole's spin: the ISCO moves out toward
            // 9 M, so the inner edge of the disk visibly recedes.
            params.mass = 2.0
            params.spin = -0.90
            params.lensingStrength = 1.0
            params.diskSize = 50.0
            params.diskTemp = 12000.0
            params.diskDensity = 4.0
            params.diskScaleHeight = 0.15
            params.zoom = 35.0
            params.enableJets = false
            params.preset = .ultra

        case .cygnusX1:
            // A ~21 solar-mass hole fed by a blue supergiant; the inner disk
            // reaches millions of kelvin and glows in X-rays. Temperature here
            // is clamped to the visible-colour range of the renderer.
            params.mass = 10.0
            params.spin = 0.95
            params.lensingStrength = 0.9
            params.diskSize = 35.0
            params.diskTemp = 32000.0
            params.diskDensity = 4.5
            params.diskScaleHeight = 0.12
            params.zoom = 40.0
            params.preset = .ultra

        case .quasar:
            params.mass = 8.0
            params.spin = 0.98
            params.lensingStrength = 1.0
            params.diskSize = 100.0
            params.diskTemp = 40000.0
            params.diskDensity = 5.0
            params.diskScaleHeight = 0.25
            params.zoom = 90.0
            params.pitch = 0.40
            params.bloomIntensity = 1.0
            params.preset = .ultra

        case .bareShadow:
            // Strip the disk away: what remains is the shadow and the
            // starfield lensed into an Einstein ring around it.
            params.mass = 1.0
            params.spin = 0.70
            params.lensingStrength = 1.4
            params.diskSize = 50.0
            params.diskTemp = 9500.0
            params.diskDensity = 4.0
            params.diskScaleHeight = 0.20
            params.zoom = 18.0
            params.enableDisk = false
            params.enableJets = false
            params.preset = .ultra
        }

        if keepCinematic { params.preset = .cinematic }
    }
}
