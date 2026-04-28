import Foundation

/// Visual-quality budget for the render pipeline. Higher presets cost more GPU.
/// Step counts match `SIMULATION_CONFIG.rayTracingSteps` from the web build.
enum QualityPreset: String, CaseIterable, Identifiable {
    case low, medium, high, ultra

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .low:    return "Low"
        case .medium: return "Medium"
        case .high:   return "High"
        case .ultra:  return "Ultra"
        }
    }

    /// Mirrors the web `rayTracingSteps` table: 32 / 64 / 128 / 256.
    var maxRaySteps: Int {
        switch self {
        case .low:    return 32
        case .medium: return 64
        case .high:   return 128
        case .ultra:  return 256
        }
    }

    var renderScale: Float {
        switch self {
        case .low:    return 0.5
        case .medium: return 0.75
        case .high:   return 1.0
        case .ultra:  return 1.0
        }
    }

    var taaEnabled: Bool {
        switch self {
        case .low:    return false
        case .medium: return true
        case .high:   return true
        case .ultra:  return true
        }
    }

    var bloomEnabled: Bool {
        switch self {
        case .low:    return false
        case .medium: return false
        case .high:   return true
        case .ultra:  return true
        }
    }
}
