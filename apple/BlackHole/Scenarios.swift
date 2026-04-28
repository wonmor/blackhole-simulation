import Foundation

/// Curated educational presets. One tap configures every relevant physics +
/// camera param to a regime that matches a famous astrophysical object or
/// extreme-spacetime scenario.
enum Scenario: String, CaseIterable, Identifiable {
    case stellar
    case sgrA
    case maximalSpin
    case schwarzschild

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .stellar:       return "Stellar"
        case .sgrA:          return "Sgr A* proxy"
        case .maximalSpin:   return "Maximal Spin"
        case .schwarzschild: return "Schwarzschild"
        }
    }

    var subtitle: String {
        switch self {
        case .stellar:       return "10 M☉ · a=0.5 · hot disk"
        case .sgrA:          return "Supermassive proxy · a=0.94"
        case .maximalSpin:   return "Near-Kerr extremal · a=0.99"
        case .schwarzschild: return "Non-rotating · classic ring"
        }
    }

    var symbol: String {
        switch self {
        case .stellar:       return "star.fill"
        case .sgrA:          return "circle.hexagongrid.fill"
        case .maximalSpin:   return "arrow.clockwise.circle.fill"
        case .schwarzschild: return "circle.dashed"
        }
    }

    /// Apply this scenario's parameters to the given live `params` instance.
    /// Persistence happens automatically via the @Published didSet hooks.
    @MainActor
    func apply(to params: BlackHoleParameters) {
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
            params.pitch = 0.539
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
            params.pitch = 0.539
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
            params.pitch = 0.539
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
            params.pitch = 0.539
            params.preset = .high
        }
    }
}
